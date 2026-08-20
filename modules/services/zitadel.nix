{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.forge.services.zitadel;
  restoreScript = pkgs.writeShellScriptBin "forge-zitadel-restore" ''
    set -euo pipefail

    if [ "$#" -ne 1 ]; then
      echo "usage: forge-zitadel-restore BACKUP_ARCHIVE" >&2
      exit 2
    fi
    if [ "''${FORGE_ALLOW_DESTRUCTIVE_RESTORE:-}" != "1" ]; then
      echo "refusing destructive restore; set FORGE_ALLOW_DESTRUCTIVE_RESTORE=1" >&2
      exit 1
    fi

    archive="$1"
    workdir="$(mktemp -d)"
    cleanup() {
      rm -rf "$workdir"
    }
    trap cleanup EXIT

    ${pkgs.gnutar}/bin/tar --zstd --extract --file "$archive" --directory "$workdir"
    test -s "$workdir/database.dump"
    test -s "$workdir/master-key"
    test -s "$workdir/database-settings.yaml"
    chown postgres:postgres "$workdir/database.dump"
    chmod 0711 "$workdir"

    systemctl stop zitadel.service
    runuser -u postgres -- ${cfg.postgresqlPackage}/bin/dropdb --if-exists ${cfg.database.name}
    runuser -u postgres -- ${cfg.postgresqlPackage}/bin/createdb --owner=${cfg.database.username} ${cfg.database.name}
    runuser -u postgres -- ${cfg.postgresqlPackage}/bin/pg_restore \
      --dbname=${cfg.database.name} "$workdir/database.dump"
    install -o zitadel -g zitadel -m 0400 "$workdir/master-key" ${cfg.masterKeyFile}
    install -o zitadel -g zitadel -m 0400 "$workdir/database-settings.yaml" ${cfg.databaseSettingsFile}
    ${lib.optionalString (cfg.bootstrapStepsFile != null) ''
      if [ -f "$workdir/bootstrap-steps.yaml" ]; then
        install -o zitadel -g zitadel -m 0400 "$workdir/bootstrap-steps.yaml" ${cfg.bootstrapStepsFile}
      fi
    ''}
    systemctl start zitadel.service
  '';
in
{
  options.forge.services.zitadel = {
    enable = lib.mkEnableOption "the Forge ZITADEL identity service";

    package = lib.mkOption {
      type = lib.types.package;
      default = pkgs.zitadel.overrideAttrs (oldAttrs: {
        meta = (oldAttrs.meta or { }) // {
          mainProgram = "zitadel";
        };
      });
      description = "ZITADEL package used by the service.";
    };

    externalDomain = lib.mkOption {
      type = lib.types.str;
      default = "id.example.com";
      description = "Public hostname used by ZITADEL discovery and callbacks.";
    };

    externalPort = lib.mkOption {
      type = lib.types.port;
      default = 443;
      description = "Public HTTPS port used by ZITADEL clients.";
    };

    listenPort = lib.mkOption {
      type = lib.types.port;
      default = 8080;
      description = "Internal HTTP/2 cleartext port served by ZITADEL.";
    };

    tlsMode = lib.mkOption {
      type = lib.types.enum [
        "external"
        "disabled"
      ];
      default = "external";
      description = "TLS boundary for ZITADEL; use external behind an HTTPS proxy.";
    };

    masterKeyFile = lib.mkOption {
      type = lib.types.str;
      default = "/run/keys/zitadel-master-key";
      description = "External runtime file containing ZITADEL's 32-byte master key.";
    };

    databaseSettingsFile = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      description = ''
        External YAML overlay containing database credentials and other
        sensitive ZITADEL settings.
      '';
    };

    bootstrapStepsFile = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      description = "Optional external YAML overlay for first-instance bootstrap steps.";
    };

    database = {
      manageLocally = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "Provision the local PostgreSQL database and role for ZITADEL.";
      };

      host = lib.mkOption {
        type = lib.types.str;
        default = "127.0.0.1";
        description = "PostgreSQL host; use the external overlay for credentials.";
      };

      port = lib.mkOption {
        type = lib.types.port;
        default = 5432;
        description = "PostgreSQL port.";
      };

      name = lib.mkOption {
        type = lib.types.str;
        default = "zitadel";
        description = "PostgreSQL database name.";
      };

      username = lib.mkOption {
        type = lib.types.str;
        default = "zitadel";
        description = "PostgreSQL role name.";
      };

      sslMode = lib.mkOption {
        type = lib.types.enum [
          "disable"
          "require"
          "verify-ca"
          "verify-full"
        ];
        default = "disable";
        description = "PostgreSQL SSL mode for the non-secret base configuration.";
      };
    };

    postgresqlPackage = lib.mkOption {
      type = lib.types.package;
      default = pkgs.postgresql_17;
      description = "PostgreSQL client package used by ZITADEL backup and restore.";
    };

    settings = lib.mkOption {
      type = lib.types.attrs;
      default = { };
      description = "Additional non-secret ZITADEL settings merged over the safe defaults.";
    };

    backup = {
      enable = lib.mkEnableOption "ZITADEL database and recovery-material backups";

      location = lib.mkOption {
        type = lib.types.path;
        default = "/var/backup/zitadel";
        description = "Local staging directory for encrypted-at-rest backup handling.";
      };

      startAt = lib.mkOption {
        type = lib.types.either (lib.types.listOf lib.types.str) lib.types.str;
        default = "*-*-* 03:30:00";
        description = "Systemd calendar expression for ZITADEL backups.";
      };

      retentionDays = lib.mkOption {
        type = lib.types.ints.positive;
        default = 14;
        description = "Number of days to retain local ZITADEL backup archives.";
      };
    };
  };

  config = lib.mkIf cfg.enable {
    assertions = [
      {
        assertion = cfg.databaseSettingsFile != null;
        message = "forge.services.zitadel.databaseSettingsFile must point to an external settings overlay.";
      }
      {
        assertion = !lib.hasPrefix builtins.storeDir cfg.masterKeyFile;
        message = "forge.services.zitadel.masterKeyFile must not point into the Nix store.";
      }
      {
        assertion = !cfg.backup.enable || cfg.database.manageLocally;
        message = "ZITADEL local backup currently requires database.manageLocally = true.";
      }
    ]
    ++
      map
        (path: {
          assertion = !lib.hasPrefix builtins.storeDir path;
          message = "ZITADEL runtime settings and bootstrap files must not point into the Nix store.";
        })
        (
          lib.filter (path: path != null) [
            cfg.databaseSettingsFile
            cfg.bootstrapStepsFile
          ]
        );

    services.zitadel = {
      enable = true;
      package = cfg.package;
      inherit (cfg) masterKeyFile tlsMode;
      settings = lib.recursiveUpdate {
        Port = cfg.listenPort;
        ExternalDomain = cfg.externalDomain;
        ExternalPort = cfg.externalPort;
        ExternalSecure = cfg.tlsMode == "external";
        Database.postgres = {
          Host = cfg.database.host;
          Port = cfg.database.port;
          Database = cfg.database.name;
          User = {
            Username = cfg.database.username;
            SSL.Mode = cfg.database.sslMode;
          };
          Admin = {
            ExistingDatabase = "postgres";
            Username = "postgres";
            SSL.Mode = cfg.database.sslMode;
          };
        };
      } cfg.settings;
      extraSettingsPaths = [ cfg.databaseSettingsFile ];
      extraStepsPaths = lib.optional (cfg.bootstrapStepsFile != null) cfg.bootstrapStepsFile;
    };

    forge.services.postgresql.enable = lib.mkIf cfg.database.manageLocally true;
    forge.services.postgresql.databases = lib.mkIf cfg.database.manageLocally [ cfg.database.name ];
    forge.services.postgresql.users = lib.mkIf cfg.database.manageLocally [
      {
        name = cfg.database.username;
        ensureDBOwnership = true;
      }
    ];

    systemd.services.zitadel = {
      after = lib.optional cfg.database.manageLocally "postgresql.service";
      requires = lib.optional cfg.database.manageLocally "postgresql.service";
      serviceConfig.UMask = "0077";
    };

    systemd.tmpfiles.rules = lib.mkIf cfg.backup.enable [
      "d '${cfg.backup.location}' 0700 root root - -"
    ];

    systemd.services.zitadel-backup = lib.mkIf cfg.backup.enable {
      description = "Backup ZITADEL state and recovery material";
      after = [ "postgresql.service" ];
      requires = [ "postgresql.service" ];
      startAt = cfg.backup.startAt;
      path = [
        cfg.postgresqlPackage
        pkgs.coreutils
        pkgs.gnutar
        pkgs.util-linux
        pkgs.zstd
      ];
      serviceConfig = {
        Type = "oneshot";
        User = "root";
        UMask = "0077";
      };
      script = ''
        set -euo pipefail
        timestamp="$(date -u +%Y%m%dT%H%M%SZ)"
        workdir="$(mktemp -d)"
        chown ${cfg.database.username}:${cfg.database.username} "$workdir"
        cleanup() {
          rm -rf "$workdir"
        }
        trap cleanup EXIT

        runuser -u ${cfg.database.username} -- pg_dump \
          --format=custom \
          --file="$workdir/database.dump" \
          --username=${cfg.database.username} \
          --dbname=${cfg.database.name}
        install -m 0400 ${cfg.masterKeyFile} "$workdir/master-key"
        install -m 0400 ${cfg.databaseSettingsFile} "$workdir/database-settings.yaml"
        ${lib.optionalString (cfg.bootstrapStepsFile != null) ''
          install -m 0400 ${cfg.bootstrapStepsFile} "$workdir/bootstrap-steps.yaml"
        ''}
        tar --zstd --create --file="${cfg.backup.location}/zitadel-$timestamp.tar.zst" \
          -C "$workdir" database.dump master-key database-settings.yaml ${
            lib.optionalString (cfg.bootstrapStepsFile != null) "bootstrap-steps.yaml"
          }
        chmod 0600 "${cfg.backup.location}/zitadel-$timestamp.tar.zst"
        find "${cfg.backup.location}" -maxdepth 1 -type f -name 'zitadel-*.tar.zst' \
          -mtime +${toString cfg.backup.retentionDays} -delete
      '';
    };

    environment.systemPackages = [ restoreScript ];
  };
}
