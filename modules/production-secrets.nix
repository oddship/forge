{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.forge.productionSecrets;
  encryptedFile = pkgs.runCommand "forge-production-sops-file-link" { } ''
    ln -s ${lib.escapeShellArg cfg.encryptedFile} "$out"
  '';
in
{
  imports = [ ./secrets.nix ];
  options.forge.productionSecrets = {
    enable = lib.mkEnableOption "persistent operator-provisioned production SOPS inputs";
    ageKeyFile = lib.mkOption {
      type = lib.types.str;
      default = "/var/lib/forge/secrets/age-key.txt";
      description = "Persistent root-owned identity installed outside Git and the Nix store.";
    };
    encryptedFile = lib.mkOption {
      type = lib.types.str;
      default = "/etc/forge/secrets/production.yaml";
    };
  };
  config = lib.mkIf cfg.enable {
    assertions = [
      {
        assertion =
          lib.hasPrefix "/" cfg.ageKeyFile
          && !(lib.hasPrefix "/run/" cfg.ageKeyFile)
          && !(lib.hasPrefix "/nix/store/" cfg.ageKeyFile);
        message = "Production age identity must use an absolute persistent path outside /run and the Nix store.";
      }
      {
        assertion =
          lib.hasPrefix "/" cfg.encryptedFile
          && !(lib.hasPrefix "/run/" cfg.encryptedFile)
          && !(lib.hasPrefix "/nix/store/" cfg.encryptedFile);
        message = "Production SOPS ciphertext must use an absolute persistent runtime path outside /run and the Nix store.";
      }
    ];
    sops.useSystemdActivation = true;
    sops.validateSopsFiles = false;
    forge.secrets = {
      enable = true;
      ageKeyFile = cfg.ageKeyFile;
      sopsFile = encryptedFile;
    };
    systemd.tmpfiles.rules = [
      "d ${builtins.dirOf cfg.ageKeyFile} 0700 root root - -"
      "d ${builtins.dirOf cfg.encryptedFile} 0700 root root - -"
    ];
    systemd.services.forge-production-secret-check = {
      before = [ "sops-install-secrets.service" ];
      after = [ "local-fs.target" ];
      unitConfig = {
        DefaultDependencies = false;
        RequiresMountsFor = [
          cfg.ageKeyFile
          cfg.encryptedFile
        ];
      };
      path = [
        pkgs.coreutils
        pkgs.age
      ];
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
      };
      script = ''
        set -euo pipefail
        key=${lib.escapeShellArg cfg.ageKeyFile}
        encrypted=${lib.escapeShellArg cfg.encryptedFile}
        test -s "$key"
        test -s "$encrypted"
        test "$(stat -c '%u:%a' "$key")" = 0:600
        age-keygen -y "$key" >/dev/null
      '';
    };
    systemd.services.sops-install-secrets = {
      requires = [ "forge-production-secret-check.service" ];
      after = [ "forge-production-secret-check.service" ];
    };
  };
}
