{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.forge.services.penpot;
  # Official 2.18.1 multi-architecture image manifests, resolved from Docker Hub.
  imageDigests = {
    frontend = "sha256:e1eb4756ec175eb71390f9bf0ddee819468d72f67f12cf3b1532bee8d591217e";
    backend = "sha256:3b7df71db88d7c478b6a10103acb4108fa86a17a47277de81437de3899959e9e";
    exporter = "sha256:3b6f9d808c777908e4f4e290e91458ec747678a7994e39125e4f3af4ef70ba9f";
  };
  environmentFile = if cfg.localFixture then "/var/lib/penpot/secrets.env" else cfg.environmentFile;
  flags =
    "enable-login-with-password enable-smtp disable-telemetry"
    + lib.optionalString cfg.localFixture " disable-secure-session-cookies";
  commonEnvironment = {
    PENPOT_PUBLIC_URI = cfg.publicUri;
    PENPOT_FLAGS = flags;
    PENPOT_REDIS_URI = cfg.redisUri;
    PENPOT_HTTP_SERVER_HOST = "127.0.0.1";
  };
  # Keep upstream asset redirects, WebSockets, security headers and frontend
  # configuration, but move both listeners away from Forge's browser ports.
  nginxTemplate = pkgs.runCommand "forge-penpot-nginx-template" { } ''
    cp ${
      pkgs.fetchurl {
        url = "https://raw.githubusercontent.com/penpot/penpot/2.18.1/docker/images/files/nginx.conf.template";
        sha256 = "acbb2fe82eb4b60f9253bf253077c85c4a1afe3c8dfe2cbb59b4c13d2d11c000";
      }
    } "$out"
    substituteInPlace "$out" \
      --replace-fail 'listen 8080 default_server' 'listen 127.0.0.1:${toString cfg.listenPort} default_server' \
      --replace-fail 'listen 8082;' 'listen 127.0.0.1:${toString cfg.metricsPort};'
  '';
  container = component: {
    image = "docker.io/penpotapp/${component}@${imageDigests.${component}}";
    extraOptions = [ "--network=host" ];
    environment = commonEnvironment;
  };
in
{
  options.forge.services.penpot = {
    enable = lib.mkEnableOption "the Forge Penpot design service";
    localFixture = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Use disposable loopback database authentication and a VM-generated persistent secret. Never enable on a production host.";
    };
    publicUri = lib.mkOption {
      type = lib.types.str;
      default = "https://design.example.com";
      description = "Full browser origin, including the forwarded port for local development.";
    };
    environmentFile = lib.mkOption {
      type = lib.types.str;
      default = "/run/secrets/penpot-env";
      description = "Root-readable runtime environment file containing PENPOT_SECRET_KEY and database/SMTP credentials. Keep outside Git and the Nix store.";
    };
    listenPort = lib.mkOption {
      type = lib.types.port;
      default = 18083;
    };
    metricsPort = lib.mkOption {
      type = lib.types.port;
      default = 18084;
    };
    databaseUri = lib.mkOption {
      type = lib.types.str;
      default = "postgresql://127.0.0.1/penpot";
      description = "PostgreSQL URI without credentials; production database and role must be provisioned separately.";
    };
    redisUri = lib.mkOption {
      type = lib.types.str;
      default = "redis://127.0.0.1:6379/2";
    };
    smtp = {
      host = lib.mkOption {
        type = lib.types.str;
        default = "127.0.0.1";
      };
      port = lib.mkOption {
        type = lib.types.port;
        default = 587;
      };
      tls = lib.mkOption {
        type = lib.types.bool;
        default = true;
      };
      from = lib.mkOption {
        type = lib.types.str;
        default = "penpot@example.com";
      };
    };
  };

  config = lib.mkIf cfg.enable {
    assertions = [
      {
        assertion = cfg.localFixture || lib.hasPrefix "https://" cfg.publicUri;
        message = "Penpot requires HTTPS outside the disposable local fixture.";
      }
      {
        assertion = !(lib.hasPrefix "/nix/store/" environmentFile);
        message = "Penpot credentials must remain outside the Nix store.";
      }
    ];

    virtualisation.oci-containers.backend = "podman";
    virtualisation.oci-containers.containers = {
      penpot-backend = (container "backend") // {
        environment = commonEnvironment // {
          PENPOT_DATABASE_URI = cfg.databaseUri;
          PENPOT_DATABASE_USERNAME = "penpot";
          PENPOT_OBJECTS_STORAGE_BACKEND = "fs";
          PENPOT_OBJECTS_STORAGE_FS_DIRECTORY = "/opt/data/assets";
          PENPOT_TELEMETRY_ENABLED = "false";
          PENPOT_SMTP_HOST = cfg.smtp.host;
          PENPOT_SMTP_PORT = toString cfg.smtp.port;
          PENPOT_SMTP_TLS = lib.boolToString cfg.smtp.tls;
          PENPOT_SMTP_SSL = "false";
          PENPOT_SMTP_DEFAULT_FROM = cfg.smtp.from;
          PENPOT_SMTP_DEFAULT_REPLY_TO = cfg.smtp.from;
        };
        environmentFiles = [ environmentFile ];
        volumes = [ "/var/lib/penpot/assets:/opt/data/assets" ];
      };
      penpot-exporter = (container "exporter") // {
        environment = commonEnvironment // {
          PENPOT_INTERNAL_URI = "http://127.0.0.1:${toString cfg.listenPort}";
          NODE_OPTIONS = "--require=/opt/forge/loopback.cjs";
        };
        environmentFiles = [ environmentFile ];
        volumes = [ "${./penpot-exporter-loopback.cjs}:/opt/forge/loopback.cjs:ro" ];
      };
      penpot-frontend = (container "frontend") // {
        dependsOn = [
          "penpot-backend"
          "penpot-exporter"
        ];
        environment = commonEnvironment // {
          PENPOT_BACKEND_URI = "http://127.0.0.1:6060";
          PENPOT_EXPORTER_URI = "http://127.0.0.1:6061";
          PENPOT_DISABLE_IPV6_LISTEN = "true";
        };
        volumes = [
          "/var/lib/penpot/assets:/opt/data/assets:ro"
          "${nginxTemplate}:/tmp/nginx.conf.template:ro"
        ];
      };
    };

    # Official images run as uid/gid 1001. Reserve a named account so an
    # unrelated local service cannot accidentally own this persistent data.
    users.groups.penpot.gid = 1001;
    users.users.penpot = {
      isSystemUser = true;
      uid = 1001;
      group = "penpot";
    };
    systemd.tmpfiles.rules = [
      "d /var/lib/penpot 0700 root root - -"
      "d /var/lib/penpot/assets 0700 penpot penpot - -"
    ];

    systemd.services.penpot-local-init = lib.mkIf cfg.localFixture {
      description = "Initialize the disposable Penpot runtime secret";
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
      };
      path = [
        pkgs.coreutils
        pkgs.openssl
      ];
      script = ''
        set -euo pipefail
        umask 0077
        if [ ! -s /var/lib/penpot/secrets.env ]; then
          printf 'PENPOT_SECRET_KEY=%s\n' "$(openssl rand -base64 64 | tr -d '\n')" > /var/lib/penpot/secrets.env.new
          mv /var/lib/penpot/secrets.env.new /var/lib/penpot/secrets.env
        fi
      '';
    };
    systemd.services.podman-penpot-backend = {
      after = lib.optionals cfg.localFixture [
        "penpot-local-init.service"
        "postgresql.service"
        "redis-forge.service"
        "mailpit-forge.service"
      ];
      requires = lib.optionals cfg.localFixture [
        "penpot-local-init.service"
        "postgresql.service"
        "redis-forge.service"
        "mailpit-forge.service"
      ];
    };
    systemd.services.podman-penpot-exporter = {
      after = lib.optionals cfg.localFixture [
        "penpot-local-init.service"
        "redis-forge.service"
      ];
      requires = lib.optionals cfg.localFixture [
        "penpot-local-init.service"
        "redis-forge.service"
      ];
    };

    forge.services.postgresql = lib.mkIf cfg.localFixture {
      enable = true;
      databases = [ "penpot" ];
      users = [
        {
          name = "penpot";
          ensureDBOwnership = true;
        }
      ];
    };
    # Private VM-only exception: host-network containers reach the native DB
    # over loopback. Keep trust restricted to this database and role.
    services.postgresql.authentication = lib.mkIf cfg.localFixture (
      lib.mkBefore ''
        host penpot penpot 127.0.0.1/32 trust
      ''
    );
    forge.services.redis.enable = lib.mkIf cfg.localFixture true;
    forge.services.mailpit.enable = lib.mkIf cfg.localFixture true;
  };
}
