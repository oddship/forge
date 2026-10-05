{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.forge.platform;
in
{
  imports = [
    ../platform.nix
    ../operator-access.nix
    ../production-secrets.nix
    ../production-ingress.nix
  ];

  forge.platform.domain = lib.mkDefault "example.com";
  forge.operatorAccess.enable = true;
  forge.productionSecrets.enable = true;
  forge.productionIngress.enable = true;
  networking.firewall.allowedTCPPorts = lib.mkForce [
    22
    80
    443
    2222
  ];

  forge.secrets = {
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
    domain = "forge.${cfg.domain}";
    ssh.enable = true;
    admin = {
      bootstrap = true;
      email = "admin@forge.${cfg.domain}";
      passwordFile = config.sops.secrets."forgejo-admin-password".path;
    };
    smtp = {
      address = "smtp.${cfg.domain}";
      port = 587;
      passwordFile = config.sops.secrets."forgejo-mailer-password".path;
    };
    backup.enable = true;
  };

  forge.services.discourse = {
    enable = true;
    hostname = "community.${cfg.domain}";
    secretKeyBaseFile = config.sops.secrets."discourse-secret-key-base".path;
    admin = {
      skipCreate = false;
      email = "admin@community.${cfg.domain}";
      passwordFile = config.sops.secrets."discourse-admin-password".path;
    };
    mail = {
      serverAddress = "smtp.${cfg.domain}";
      port = 587;
    };
    backup.enable = true;
  };

  forge.services.haproxy = {
    enable = true;
    forgejoDomain = "forge.${cfg.domain}";
    discourseDomain = "community.${cfg.domain}";
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

}
