{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.forge.services.observability;
  grafanaDashboard = pkgs.writeText "forge-overview-dashboard.json" (
    builtins.toJSON {
      annotations = {
        list = [ ];
      };
      editable = false;
      graphTooltip = 0;
      panels = [
        {
          datasource = {
            type = "prometheus";
            uid = "forge-prometheus";
          };
          fieldConfig = {
            defaults = { };
            overrides = [ ];
          };
          gridPos = {
            h = 8;
            w = 24;
            x = 0;
            y = 0;
          };
          options = {
            legend = {
              displayMode = "list";
              placement = "bottom";
            };
            tooltip = {
              mode = "single";
              sort = "none";
            };
          };
          targets = [
            {
              expr = "up";
              refId = "A";
            }
          ];
          title = "Prometheus targets";
          type = "timeseries";
        }
      ];
      refresh = "15s";
      schemaVersion = 39;
      tags = [ "forge" ];
      templating = {
        list = [ ];
      };
      time = {
        from = "now-1h";
        to = "now";
      };
      timezone = "browser";
      title = "Forge platform overview";
      uid = "forge-overview";
      version = 1;
    }
  );
  grafanaDashboardDirectory = pkgs.runCommand "forge-grafana-dashboards" { } ''
    mkdir -p "$out"
    cp ${grafanaDashboard} "$out/forge-overview.json"
  '';
in
{
  options.forge.services.observability = {
    enable = lib.mkEnableOption "the Forge observability stack";

    listenAddress = lib.mkOption {
      type = lib.types.str;
      default = "127.0.0.1";
      description = "Address used by private observability services.";
    };

    internalAddress = lib.mkOption {
      type = lib.types.str;
      default = "127.0.0.1";
      description = "Address used by observability services to reach one another.";
    };

    prometheusPort = lib.mkOption {
      type = lib.types.port;
      default = 9090;
      description = "Prometheus HTTP port.";
    };

    grafanaPort = lib.mkOption {
      type = lib.types.port;
      default = 3001;
      description = "Grafana HTTP port.";
    };

    grafanaSecretKeyFile = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      description = "External runtime file containing Grafana's encryption key.";
    };

    clickhouseHttpPort = lib.mkOption {
      type = lib.types.port;
      default = 8123;
      description = "ClickHouse HTTP port used by Vector and Logchef.";
    };

    clickhouseTcpPort = lib.mkOption {
      type = lib.types.port;
      default = 9000;
      description = "ClickHouse native TCP port.";
    };

    clickhouseDatabase = lib.mkOption {
      type = lib.types.str;
      default = "logs";
      description = "ClickHouse database receiving private platform logs.";
    };

    clickhouseTable = lib.mkOption {
      type = lib.types.str;
      default = "events";
      description = "ClickHouse table receiving private platform logs.";
    };

    retentionDays = lib.mkOption {
      type = lib.types.ints.positive;
      default = 14;
      description = "TTL for observability logs; logs are not backups.";
    };
  };

  config = lib.mkIf cfg.enable {
    assertions = [
      {
        assertion = builtins.match "[A-Za-z0-9_]+" cfg.clickhouseDatabase != null;
        message = "forge.services.observability.clickhouseDatabase must contain only letters, numbers, and underscores.";
      }
      {
        assertion = builtins.match "[A-Za-z0-9_]+" cfg.clickhouseTable != null;
        message = "forge.services.observability.clickhouseTable must contain only letters, numbers, and underscores.";
      }
      {
        assertion = cfg.grafanaSecretKeyFile != null;
        message = "forge.services.observability.grafanaSecretKeyFile must point to an external secret file.";
      }
      {
        assertion =
          cfg.grafanaSecretKeyFile == null || !lib.hasPrefix builtins.storeDir cfg.grafanaSecretKeyFile;
        message = "forge.services.observability.grafanaSecretKeyFile must not point into the Nix store.";
      }
    ];

    services.prometheus = {
      enable = true;
      listenAddress = cfg.listenAddress;
      port = cfg.prometheusPort;
      globalConfig.scrape_interval = "15s";
      scrapeConfigs = [
        {
          job_name = "prometheus";
          static_configs = [
            { targets = [ "${cfg.internalAddress}:${toString cfg.prometheusPort}" ]; }
          ];
        }
      ];
    };

    services.grafana = {
      enable = true;
      settings = {
        server = {
          http_addr = cfg.listenAddress;
          http_port = cfg.grafanaPort;
          domain = "grafana.forge.local";
        };
        "auth.anonymous".enabled = false;
        "users".allow_sign_up = false;
        security.secret_key = "$__file{/run/credentials/grafana.service/grafana-secret-key}";
      };
      provision = {
        enable = true;
        datasources.settings = {
          apiVersion = 1;
          datasources = [
            {
              name = "Prometheus";
              uid = "forge-prometheus";
              type = "prometheus";
              access = "proxy";
              url = "http://${cfg.internalAddress}:${toString cfg.prometheusPort}";
              isDefault = true;
            }
          ];
        };
        dashboards.settings = {
          apiVersion = 1;
          providers = [
            {
              name = "Forge";
              folder = "Forge";
              type = "file";
              disableDeletion = true;
              editable = false;
              options.path = grafanaDashboardDirectory;
            }
          ];
        };
      };
    };

    systemd.services.grafana.serviceConfig.LoadCredential = [
      "grafana-secret-key:${cfg.grafanaSecretKeyFile}"
    ];

    services.clickhouse = {
      enable = true;
      serverConfig = {
        listen_host = [ cfg.listenAddress ];
        http_port = cfg.clickhouseHttpPort;
        tcp_port = cfg.clickhouseTcpPort;
      };
    };

    systemd.services.forge-observability-clickhouse-schema = {
      description = "Create the bounded-retention Forge log schema";
      wantedBy = [ "multi-user.target" ];
      after = [ "clickhouse.service" ];
      requires = [ "clickhouse.service" ];
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
      };
      path = [ pkgs.curl ];
      script = ''
        set -euo pipefail
        curl --fail --silent --show-error \
          --data-binary 'CREATE DATABASE IF NOT EXISTS ${cfg.clickhouseDatabase}' \
          http://${cfg.internalAddress}:${toString cfg.clickhouseHttpPort}/
        curl --fail --silent --show-error \
          --data-binary 'CREATE TABLE IF NOT EXISTS ${cfg.clickhouseDatabase}.${cfg.clickhouseTable} (timestamp DateTime64(3), event String) ENGINE = MergeTree ORDER BY timestamp TTL timestamp + INTERVAL ${toString cfg.retentionDays} DAY DELETE' \
          http://${cfg.internalAddress}:${toString cfg.clickhouseHttpPort}/
      '';
    };

    services.vector = {
      enable = true;
      journaldAccess = true;
      settings = {
        sources.journald = {
          type = "journald";
        };
        transforms.to_clickhouse = {
          type = "remap";
          inputs = [ "journald" ];
          source = ''
            original = .
            . = {
              "timestamp": now(),
              "event": encode_json(original),
            }
          '';
        };
        sinks.clickhouse = {
          type = "clickhouse";
          inputs = [ "to_clickhouse" ];
          endpoint = "http://${cfg.internalAddress}:${toString cfg.clickhouseHttpPort}";
          database = cfg.clickhouseDatabase;
          table = cfg.clickhouseTable;
          format = "json_each_row";
          healthcheck.enabled = false;
        };
      };
    };

    systemd.services.vector.after = [ "forge-observability-clickhouse-schema.service" ];
  };
}
