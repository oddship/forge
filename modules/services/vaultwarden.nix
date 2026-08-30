{
  config,
  lib,
  ...
}:

let
  cfg = config.forge.services.vaultwarden;
in
{
  options.forge.services.vaultwarden = {
    enable = lib.mkEnableOption "Vaultwarden";

    domain = lib.mkOption {
      type = lib.types.str;
      default = "http://vaultwarden.localhost:8080";
      description = "Public Vaultwarden URL used in generated links and redirects.";
    };

    listenPort = lib.mkOption {
      type = lib.types.port;
      default = 8222;
      description = "Local HTTP port for Vaultwarden.";
    };

    signupsAllowed = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Whether new Vaultwarden accounts may be created.";
    };

    backup = {
      enable = lib.mkEnableOption "Vaultwarden SQLite backups";

      location = lib.mkOption {
        type = lib.types.str;
        default = "/var/backup/vaultwarden";
        description = "Local staging directory for Vaultwarden backups.";
      };
    };
  };

  config = lib.mkIf cfg.enable {
    services.vaultwarden = {
      enable = true;
      backupDir = lib.mkIf cfg.backup.enable cfg.backup.location;
      config = {
        DOMAIN = cfg.domain;
        ROCKET_ADDRESS = "127.0.0.1";
        ROCKET_PORT = cfg.listenPort;
        SIGNUPS_ALLOWED = cfg.signupsAllowed;
        INVITATIONS_ALLOWED = cfg.signupsAllowed;
      };
    };
  };
}
