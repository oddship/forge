{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.forge.localSecrets;
  sopsFileLink = pkgs.runCommand "forge-local-sops-file-link" { } ''
    ln -s ${lib.escapeShellArg cfg.sopsFile} "$out"
  '';
  writeFixture = pkgs.writeShellScript "forge-write-local-sops-fixture" ''
    set -euo pipefail

    install -d -m 0700 /run/forge
    workdir="$(mktemp -d)"
    cleanup() {
      rm -rf -- "$workdir"
    }
    trap cleanup EXIT

    install -d -m 0700 "$(dirname ${lib.escapeShellArg cfg.ageKeyFile})"
    if [ ! -s ${lib.escapeShellArg cfg.ageKeyFile} ]; then
      ${pkgs.age}/bin/age-keygen -o ${lib.escapeShellArg cfg.ageKeyFile} >/dev/null 2>&1
      chmod 0600 ${lib.escapeShellArg cfg.ageKeyFile}
    fi

    printf 'discourse-secret-key-base: %s\n' \
      "$(${pkgs.openssl}/bin/openssl rand -hex 64)" > "$workdir/secrets.yaml"
    printf 'discourse-admin-password: %s\n' ${lib.escapeShellArg "${cfg.fixtureSeed}-discourse-admin"} >> "$workdir/secrets.yaml"
    printf 'forgejo-admin-password: %s\n' ${lib.escapeShellArg "${cfg.fixtureSeed}-forgejo-admin"} >> "$workdir/secrets.yaml"
    ${pkgs.sops}/bin/sops --encrypt --input-type yaml \
      --age "$(${pkgs.age}/bin/age-keygen -y ${lib.escapeShellArg cfg.ageKeyFile})" \
      --output ${lib.escapeShellArg (toString cfg.sopsFile)} "$workdir/secrets.yaml"
    chmod 0400 ${lib.escapeShellArg (toString cfg.sopsFile)}
  '';
in
{
  options.forge.localSecrets = {
    enable = lib.mkEnableOption "disposable local SOPS secrets for VM development";

    ageKeyFile = lib.mkOption {
      type = lib.types.str;
      default = "/var/lib/forge/age-key.txt";
      description = "Persistent local-only age identity generated inside the VM.";
    };

    sopsFile = lib.mkOption {
      type = lib.types.path;
      default = /run/forge/local-secrets.yaml;
      description = "Ephemeral encrypted fixture regenerated inside the local VM.";
    };

    fixtureSeed = lib.mkOption {
      type = lib.types.str;
      default = "forge-local";
      description = "Deterministic prefix for disposable local administrator credentials.";
    };
  };

  config = lib.mkIf cfg.enable {
    sops.useSystemdActivation = true;
    sops.validateSopsFiles = false;

    forge.secrets = {
      enable = true;
      ageKeyFile = cfg.ageKeyFile;
      sopsFile = sopsFileLink;
      secrets = {
        "discourse-secret-key-base" = {
          key = "discourse-secret-key-base";
          owner = "discourse";
          mode = "0400";
          restartUnits = [ "discourse.service" ];
        };
        "discourse-admin-password" = {
          key = "discourse-admin-password";
          owner = "discourse";
          mode = "0400";
          restartUnits = [ "discourse.service" ];
        };
        "forgejo-admin-password" = {
          key = "forgejo-admin-password";
          owner = "forgejo";
          mode = "0400";
          restartUnits = [ "forgejo.service" ];
        };
      };
    };

    forge.services.discourse = {
      secretKeyBaseFile = config.sops.secrets."discourse-secret-key-base".path;
      admin = {
        skipCreate = false;
        passwordFile = config.sops.secrets."discourse-admin-password".path;
      };
    };

    systemd.services."forge-local-sops-fixture" = {
      description = "Create the disposable local SOPS fixture before secret installation";
      wantedBy = [ "sysinit.target" ];
      before = [ "sops-install-secrets.service" ];
      after = [ "local-fs.target" ];
      unitConfig.DefaultDependencies = "no";
      serviceConfig = {
        Type = "oneshot";
        ExecStart = writeFixture;
        RemainAfterExit = true;
      };
    };

    systemd.services.sops-install-secrets = {
      requires = lib.mkAfter [ "forge-local-sops-fixture.service" ];
      after = lib.mkAfter [ "forge-local-sops-fixture.service" ];
    };

    systemd.services."forge-local-sops-rotate" = {
      description = "Rotate disposable local SOPS secrets and reinstall them";
      after = [ "sops-install-secrets.service" ];
      serviceConfig.Type = "oneshot";
      script = ''
        ${writeFixture}
        systemctl restart sops-install-secrets.service
      '';
    };
  };
}
