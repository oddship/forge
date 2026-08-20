{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.forge.services.discourse;
  adminPasswordFile =
    if cfg.admin.passwordFile != null then
      cfg.admin.passwordFile
    else
      pkgs.writeText "forge-discourse-admin-password-disabled" "";
  restoreScript = pkgs.writeShellScriptBin "forge-discourse-restore" ''
    set -euo pipefail

    if [ "$#" -ne 1 ]; then
      echo "usage: forge-discourse-restore BACKUP_ARCHIVE" >&2
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
    chown -R postgres:postgres "$workdir"
    systemctl stop discourse.service
    systemctl stop redis-discourse.service
    runuser -u postgres -- ${cfg.postgresqlPackage}/bin/dropdb --if-exists ${cfg.database.name}
    runuser -u postgres -- ${cfg.postgresqlPackage}/bin/createdb --owner=${cfg.database.username} ${cfg.database.name}
    runuser -u postgres -- ${cfg.postgresqlPackage}/bin/pg_restore --clean --if-exists --dbname=${cfg.database.name} "$workdir/database.dump"
    install -o redis-discourse -g redis-discourse -m 0600 "$workdir/redis.rdb" /var/lib/redis-discourse/dump.rdb
    systemctl start redis-discourse.service
    systemctl start discourse.service
  '';
in
{
  options.forge.services.discourse = {
    enable = lib.mkEnableOption "Discourse";

    hostname = lib.mkOption {
      type = lib.types.str;
      default = "discourse.local";
      description = "Hostname served by Discourse and its generated URLs.";
    };

    postgresqlPackage = lib.mkOption {
      type = lib.types.package;
      default = pkgs.postgresql_17;
      description = "PostgreSQL client package used by Discourse backup and restore commands.";
    };

    secretKeyBaseFile = lib.mkOption {
      type = lib.types.nullOr lib.types.path;
      default = null;
      description = "Runtime file containing Discourse's secret key base.";
    };

    database = {
      name = lib.mkOption {
        type = lib.types.str;
        default = "discourse";
        description = "Discourse PostgreSQL database name.";
      };

      username = lib.mkOption {
        type = lib.types.str;
        default = "discourse";
        description = "Discourse PostgreSQL role name.";
      };
    };

    redis = {
      port = lib.mkOption {
        type = lib.types.port;
        default = 6380;
        description = "Dedicated Redis port for Discourse.";
      };

      dbNumber = lib.mkOption {
        type = lib.types.int;
        default = 1;
        description = "Redis logical database used by Discourse.";
      };
    };

    mail = {
      serverAddress = lib.mkOption {
        type = lib.types.str;
        default = "127.0.0.1";
        description = "SMTP host used by Discourse.";
      };

      port = lib.mkOption {
        type = lib.types.port;
        default = 1025;
        description = "SMTP port used by Discourse.";
      };
    };

    admin = {
      skipCreate = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "Leave administrator creation to a separate bootstrap procedure.";
      };

      email = lib.mkOption {
        type = lib.types.str;
        default = "admin@discourse.local";
        description = "Initial Discourse administrator email address.";
      };

      username = lib.mkOption {
        type = lib.types.str;
        default = "admin";
        description = "Initial Discourse administrator username.";
      };

      fullName = lib.mkOption {
        type = lib.types.str;
        default = "Forge administrator";
        description = "Initial Discourse administrator display name.";
      };

      passwordFile = lib.mkOption {
        type = lib.types.nullOr lib.types.path;
        default = null;
        description = "Runtime file containing the initial administrator password.";
      };
    };

    backup = {
      enable = lib.mkEnableOption "Discourse backups";

      location = lib.mkOption {
        type = lib.types.str;
        default = "/var/backup/discourse";
        description = "Local staging directory for Discourse backups.";
      };

      startAt = lib.mkOption {
        type = lib.types.str;
        default = "*-*-* 03:00:00";
        description = "Systemd calendar expression for Discourse backups.";
      };

      retentionDays = lib.mkOption {
        type = lib.types.ints.positive;
        default = 14;
        description = "Number of days to retain local Discourse backup archives.";
      };
    };
  };

  config = lib.mkIf cfg.enable {
    assertions = [
      {
        assertion = cfg.secretKeyBaseFile != null;
        message = "forge.services.discourse.secretKeyBaseFile must point to an external secret file.";
      }
      {
        assertion = cfg.admin.skipCreate || cfg.admin.passwordFile != null;
        message = "forge.services.discourse.admin.passwordFile is required when admin.skipCreate is false.";
      }
    ];

    services.discourse = {
      enable = true;
      hostname = cfg.hostname;
      secretKeyBaseFile = cfg.secretKeyBaseFile;
      enableACME = false;
      database = {
        createLocally = true;
        ignorePostgresqlVersion = true;
        name = cfg.database.name;
        username = cfg.database.username;
      };
      redis = {
        host = "localhost";
        dbNumber = cfg.redis.dbNumber;
      };
      backendSettings = {
        redis_port = cfg.redis.port;
        redis_db = cfg.redis.dbNumber;
      };
      mail.outgoing = {
        serverAddress = cfg.mail.serverAddress;
        port = cfg.mail.port;
        enableStartTLSAuto = false;
        opensslVerifyMode = "none";
      };
      admin = {
        skipCreate = cfg.admin.skipCreate;
        email = cfg.admin.email;
        username = cfg.admin.username;
        fullName = cfg.admin.fullName;
        passwordFile = adminPasswordFile;
      };
    };

    systemd.tmpfiles.rules = lib.mkIf cfg.backup.enable [
      "d ${cfg.backup.location} 0750 root root -"
    ];

    systemd.services.discourse-backup = lib.mkIf cfg.backup.enable {
      description = "Backup Discourse data";
      after = [
        "discourse.service"
        "postgresql.service"
        "redis-discourse.service"
      ];
      serviceConfig = {
        Type = "oneshot";
        User = "root";
      };
      path = [
        cfg.postgresqlPackage
        pkgs.coreutils
        pkgs.gnutar
        pkgs.redis
        pkgs.util-linux
        pkgs.zstd
      ];
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
        redis-cli -h 127.0.0.1 -p ${toString cfg.redis.port} --rdb "$workdir/redis.rdb"
        tar --zstd --create --file="${cfg.backup.location}/discourse-$timestamp.tar.zst" \
          -C "$workdir" database.dump redis.rdb \
          -C /var/lib/discourse uploads
        chmod 0600 "${cfg.backup.location}/discourse-$timestamp.tar.zst"
        find "${cfg.backup.location}" -maxdepth 1 -type f -name 'discourse-*.tar.zst' \
          -mtime +${toString cfg.backup.retentionDays} -delete
      '';
    };

    systemd.timers.discourse-backup = lib.mkIf cfg.backup.enable {
      wantedBy = [ "timers.target" ];
      timerConfig = {
        OnCalendar = cfg.backup.startAt;
        Persistent = true;
        Unit = "discourse-backup.service";
      };
    };

    environment.systemPackages = [ restoreScript ];
  };
}
