{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.forge.services.forgejo;
  defaults = {
    actions.ENABLED = true;

    database = {
      NAME = cfg.databaseName;
      USER = cfg.databaseUser;
    };

    mailer = {
      ENABLED = true;
      FROM = "forgejo@${cfg.domain}";
      SMTP_ADDR = cfg.smtp.address;
      SMTP_PORT = cfg.smtp.port;
    };

    server = {
      DOMAIN = cfg.domain;
      HTTP_ADDR = "127.0.0.1";
      HTTP_PORT = cfg.httpPort;
      ROOT_URL = "http://${cfg.domain}:${toString cfg.httpPort}/";
      DISABLE_SSH = !cfg.ssh.enable;
      START_SSH_SERVER = cfg.ssh.enable;
      SSH_USER = cfg.ssh.user;
      BUILTIN_SSH_SERVER_USER = cfg.ssh.user;
      SSH_PORT = cfg.ssh.port;
      SSH_LISTEN_PORT = cfg.ssh.port;
    };

    service.DISABLE_REGISTRATION = true;
  };
in
{
  options.forge.services.forgejo = {
    enable = lib.mkEnableOption "Forgejo";

    domain = lib.mkOption {
      type = lib.types.str;
      default = "forge.local";
      description = "Forgejo hostname used in generated URLs and mail.";
    };

    httpPort = lib.mkOption {
      type = lib.types.port;
      default = 3000;
      description = "Loopback HTTP port for Forgejo.";
    };

    databaseName = lib.mkOption {
      type = lib.types.str;
      default = "forgejo";
      description = "PostgreSQL database name used by Forgejo.";
    };

    databaseUser = lib.mkOption {
      type = lib.types.str;
      default = "forgejo";
      description = "PostgreSQL role used by Forgejo.";
    };

    ssh = {
      enable = lib.mkEnableOption "Forgejo Git over SSH";

      user = lib.mkOption {
        type = lib.types.str;
        default = "git";
        description = "SSH username displayed in Forgejo clone URLs.";
      };

      port = lib.mkOption {
        type = lib.types.port;
        default = 2222;
        description = "Unprivileged port for Forgejo's built-in Git SSH server.";
      };
    };

    admin = {
      bootstrap = lib.mkEnableOption "the initial Forgejo administrator";

      username = lib.mkOption {
        type = lib.types.str;
        default = "forge-admin";
        description = "Username created by the one-time administrator bootstrap.";
      };

      email = lib.mkOption {
        type = lib.types.str;
        default = "admin@forge.local";
        description = "Email address for the one-time administrator bootstrap.";
      };

      passwordFile = lib.mkOption {
        type = lib.types.nullOr lib.types.path;
        default = null;
        description = "External runtime file containing the initial administrator password.";
      };
    };

    smtp = {
      address = lib.mkOption {
        type = lib.types.str;
        default = "127.0.0.1";
        description = "SMTP host used by Forgejo.";
      };

      port = lib.mkOption {
        type = lib.types.port;
        default = 1025;
        description = "SMTP port used by Forgejo.";
      };

      passwordFile = lib.mkOption {
        type = lib.types.nullOr lib.types.path;
        default = null;
        description = "External runtime file containing the SMTP password.";
      };
    };

    backup = {
      enable = lib.mkEnableOption "Forgejo application dumps";

      interval = lib.mkOption {
        type = lib.types.str;
        default = "*-*-* 02:00:00";
        description = "Systemd calendar expression for Forgejo dumps.";
      };
    };

    settings = lib.mkOption {
      type = lib.types.attrs;
      default = { };
      description = "Additional Forgejo app.ini settings merged over the safe defaults.";
    };
  };

  config = lib.mkIf cfg.enable {
    assertions = [
      {
        assertion = !cfg.admin.bootstrap || cfg.admin.passwordFile != null;
        message = "forge.services.forgejo.admin.passwordFile is required when admin.bootstrap is enabled.";
      }
      {
        assertion = !cfg.ssh.enable || cfg.ssh.port > 1024;
        message = "forge.services.forgejo.ssh.port must be unprivileged when Forgejo's built-in SSH server is enabled.";
      }
    ];

    networking.firewall.allowedTCPPorts = lib.mkIf cfg.ssh.enable [ cfg.ssh.port ];

    services.forgejo = {
      enable = true;
      database = {
        type = "postgres";
        createDatabase = false;
        name = cfg.databaseName;
        user = cfg.databaseUser;
        socket = "/run/postgresql";
      };
      dump = {
        enable = cfg.backup.enable;
        interval = cfg.backup.interval;
        type = "tar.zst";
      };
      secrets = lib.mkIf (cfg.smtp.passwordFile != null) {
        mailer.PASSWD = cfg.smtp.passwordFile;
      };
      settings = lib.recursiveUpdate defaults cfg.settings;
    };

    systemd.services.forgejo-admin-bootstrap = lib.mkIf cfg.admin.bootstrap {
      description = "Create the initial Forgejo administrator";
      wantedBy = [ "multi-user.target" ];
      after = [
        "forgejo.service"
        "sops-install-secrets.service"
      ];
      requires = [
        "forgejo.service"
        "sops-install-secrets.service"
      ];
      path = [
        config.services.forgejo.package
        pkgs.coreutils
      ];
      environment = {
        FORGEJO_WORK_DIR = config.services.forgejo.stateDir;
        FORGEJO_CUSTOM = config.services.forgejo.customDir;
      };
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        User = config.services.forgejo.user;
        StateDirectory = "forgejo-admin-bootstrap";
        LoadCredential = [ "admin-password:${cfg.admin.passwordFile}" ];
      };
      script = ''
        set -euo pipefail

        marker="$STATE_DIRECTORY/created"
        if [ -e "$marker" ]; then
          exit 0
        fi

        password="$(cat "$CREDENTIALS_DIRECTORY/admin-password")"
        forgejo admin user create \
          --admin \
          --username ${lib.escapeShellArg cfg.admin.username} \
          --password "$password" \
          --email ${lib.escapeShellArg cfg.admin.email} \
          --must-change-password=false
        touch "$marker"
      '';
    };
  };
}
