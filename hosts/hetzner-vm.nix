{
  config,
  lib,
  pkgs,
  ...
}:

let
  productionSopsRuntimeFile = "/etc/forge/secrets/production.yaml";
  productionSopsFile = pkgs.runCommand "forge-production-sops-file-link" { } ''
    ln -s ${lib.escapeShellArg productionSopsRuntimeFile} "$out"
  '';
in
{
  imports = [
    ../modules/base.nix
    ../modules/operator-access.nix
    ../modules/services
  ];

  networking.hostName = "forge-hetzner";

  forge.operatorAccess.enable = true;

  # The Hetzner image/bootstrap step must format and label the root volume
  # `nixos` before installing this configuration. Keep this contract explicit
  # so the host is bootable independently of the local QEMU hardware module.
  fileSystems."/" = {
    device = "/dev/disk/by-label/nixos";
    fsType = "ext4";
  };
  boot.loader.grub.device = "/dev/sda";

  # TLS termination and certificate automation are a deployment gate. Do not
  # expose 443 until the HTTPS HAProxy configuration is added and exercised.
  networking.firewall.allowedTCPPorts = lib.mkForce [
    22
    80
    2222
  ];

  # These paths are bootstrap inputs, not generated configuration. The host
  # must receive both files before sops-install-secrets.service is started.
  systemd.tmpfiles.rules = [
    "d /etc/forge/secrets 0700 root root - -"
    "d /run/forge/secrets 0700 root root - -"
  ];
  systemd.services.sops-install-secrets.unitConfig.RequiresMountsFor = [
    "/etc/forge/secrets"
    "/run/forge/secrets"
  ];

  sops.useSystemdActivation = true;
  sops.validateSopsFiles = false;

  forge.secrets = {
    enable = true;
    ageKeyFile = "/run/forge/secrets/age-key.txt";
    sopsFile = productionSopsFile;
    secrets = {
      "discourse-secret-key-base" = {
        key = "discourse-secret-key-base";
        owner = "discourse";
        mode = "0400";
        restartUnits = [ "discourse.service" ];
      };
      "forgejo-mailer-password" = {
        key = "forgejo-mailer-password";
        owner = "forgejo";
        mode = "0400";
        restartUnits = [ "forgejo.service" ];
      };
      "forgejo-admin-password" = {
        key = "forgejo-admin-password";
        owner = "forgejo";
        mode = "0400";
      };
      "discourse-admin-password" = {
        key = "discourse-admin-password";
        owner = "discourse";
        mode = "0400";
      };
    };
  };

  forge.services.postgresql = {
    enable = true;
    databases = [
      "forgejo"
      "discourse"
    ];
    users = [
      {
        name = "forgejo";
        ensureDBOwnership = true;
      }
      {
        name = "discourse";
        ensureDBOwnership = true;
      }
    ];
    backup.enable = true;
  };

  forge.services.redis = {
    enable = true;
    backup.enable = true;
  };

  forge.services.forgejo = {
    enable = true;
    domain = "forge.example.com";
    ssh.enable = true;
    admin = {
      bootstrap = true;
      email = "admin@forge.example.com";
      passwordFile = config.sops.secrets."forgejo-admin-password".path;
    };
    smtp = {
      address = "smtp.example.com";
      port = 587;
      passwordFile = config.sops.secrets."forgejo-mailer-password".path;
    };
    backup.enable = true;
  };

  forge.services.discourse = {
    enable = true;
    hostname = "community.example.com";
    secretKeyBaseFile = config.sops.secrets."discourse-secret-key-base".path;
    admin = {
      skipCreate = false;
      email = "admin@community.example.com";
      passwordFile = config.sops.secrets."discourse-admin-password".path;
    };
    mail = {
      serverAddress = "smtp.example.com";
      port = 587;
    };
    backup.enable = true;
  };

  forge.services.haproxy = {
    enable = true;
    forgejoDomain = "forge.example.com";
    discourseDomain = "community.example.com";
  };

  # These are intentionally disabled until their control-plane bootstrap and
  # HTTPS routes are configured. Their secret inventory is documented in
  # ops/secrets-inventory.md and can be enabled without changing the host
  # secret boundary.
  forge.services.netbird.enable = false;
  forge.services.zitadel.enable = false;
  forge.services.mailpit.enable = false;
  forge.services.forgejoRunner.enable = false;

  environment.systemPackages = [
    pkgs.curl
    pkgs.postgresql_17
    pkgs.redis
  ];

  system.stateVersion = "24.11";
}
