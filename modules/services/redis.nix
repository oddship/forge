{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.forge.services.redis;
in
{
  options.forge.services.redis = {
    enable = lib.mkEnableOption "the Forge Redis service";

    port = lib.mkOption {
      type = lib.types.port;
      default = 6379;
      description = "Loopback TCP port for the Redis service.";
    };

    appendOnly = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Enable Redis append-only persistence in addition to RDB snapshots.";
    };

    backup = {
      enable = lib.mkEnableOption "local Redis persistence for backup staging";

      location = lib.mkOption {
        type = lib.types.path;
        default = "/var/backup/redis";
        description = "Local staging directory for Redis RDB backups.";
      };

      startAt = lib.mkOption {
        type = lib.types.either (lib.types.listOf lib.types.str) lib.types.str;
        default = "*-*-* 01:30:00";
        description = "Systemd calendar expression for Redis backups.";
      };
    };
  };

  config = lib.mkIf cfg.enable {
    services.redis.servers.forge = {
      enable = true;
      inherit (cfg) port appendOnly;
      bind = "127.0.0.1";
      unixSocket = "/run/redis-forge/redis.sock";
      unixSocketPerm = 660;
    };

    systemd.tmpfiles.rules = lib.mkIf cfg.backup.enable [
      "d '${cfg.backup.location}' 0700 redis-forge redis-forge - -"
    ];

    systemd.services.redisBackup-forge = lib.mkIf cfg.backup.enable {
      description = "Backup of Forge Redis data";
      after = [ "redis-forge.service" ];
      requires = [ "redis-forge.service" ];
      startAt = cfg.backup.startAt;
      path = [
        pkgs.coreutils
        pkgs.redis
      ];
      serviceConfig = {
        Type = "oneshot";
        User = "redis-forge";
        Group = "redis-forge";
      };
      script = ''
        set -euo pipefail
        umask 0077
        redis-cli -s /run/redis-forge/redis.sock --rdb ${cfg.backup.location}/forge.rdb.in-progress
        mv ${cfg.backup.location}/forge.rdb.in-progress ${cfg.backup.location}/forge.rdb
      '';
    };
  };
}
