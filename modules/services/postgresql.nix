{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.forge.services.postgresql;
in
{
  options.forge.services.postgresql = {
    enable = lib.mkEnableOption "the Forge PostgreSQL service";

    package = lib.mkOption {
      type = lib.types.package;
      default = pkgs.postgresql_17;
      description = "PostgreSQL package used by the service.";
    };

    databases = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ ];
      description = "Databases created and included in the local dump backup.";
    };

    users = lib.mkOption {
      type = lib.types.listOf (
        lib.types.submodule {
          options = {
            name = lib.mkOption {
              type = lib.types.str;
              description = "Name of a local PostgreSQL role.";
            };

            ensureDBOwnership = lib.mkOption {
              type = lib.types.bool;
              default = false;
              description = "Grant ownership of the same-named database to the role.";
            };

            ensureClauses = lib.mkOption {
              type = lib.types.attrs;
              default = { };
              description = "Native PostgreSQL ALTER ROLE clauses applied during setup.";
            };
          };
        }
      );
      default = [ ];
      description = "Local PostgreSQL roles declared by service modules.";
    };

    backup = {
      enable = lib.mkEnableOption "local PostgreSQL dump backups";

      location = lib.mkOption {
        type = lib.types.path;
        default = "/var/backup/postgresql";
        description = "Local staging directory for PostgreSQL dumps.";
      };

      startAt = lib.mkOption {
        type = lib.types.either (lib.types.listOf lib.types.str) lib.types.str;
        default = "*-*-* 01:15:00";
        description = "Systemd calendar expression for PostgreSQL dumps.";
      };

      pgdumpOptions = lib.mkOption {
        type = lib.types.separatedString " ";
        default = "-C";
        description = "Options passed to pg_dump for local restore-compatible backups.";
      };
    };
  };

  config = lib.mkIf cfg.enable {
    services.postgresql = {
      enable = true;
      package = cfg.package;
      ensureDatabases = cfg.databases;
      ensureUsers = cfg.users;
    };

    services.postgresqlBackup = lib.mkIf cfg.backup.enable {
      enable = true;
      databases = cfg.databases;
      inherit (cfg.backup) location pgdumpOptions startAt;
    };
  };
}
