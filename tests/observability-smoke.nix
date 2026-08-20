{ logchef, pkgs, ... }:

pkgs.testers.runNixOSTest {
  name = "forge-local-observability-smoke";

  nodes.machine =
    {
      lib,
      modulesPath,
      pkgs,
      ...
    }:
    {
      imports = [
        (modulesPath + "/virtualisation/qemu-vm.nix")
        ../modules/base.nix
        ../modules/services/observability.nix
        logchef.nixosModules.default
      ];

      networking.hostName = "forge-observability-test";

      services.logchef = {
        enable = true;
        package = logchef.packages.x86_64-linux.logchef;
        listenAddress = "127.0.0.1";
        port = 8125;
        adminEmails = [ "admin@forge.local" ];
        localAuth = {
          enable = true;
          adminEmail = "admin@forge.local";
        };
        credentialFiles = {
          LOGCHEF_AUTH__API_TOKEN_SECRET = "/run/keys/logchef-api-token-secret";
          LOGCHEF_AUTH__LOCAL__ADMIN_PASSWORD = "/run/keys/logchef-admin-password";
        };
        settings.auth.local.enabled = true;
        settings.provisioning = {
          manage_sources = true;
          manage_teams = true;
          prune = false;
          dry_run = false;
          sources = [
            {
              name = "Forge platform logs";
              source_type = "clickhouse";
              meta_ts_field = "timestamp";
              connection = {
                host = "127.0.0.1:9000";
                database = "logs";
                table_name = "events";
                username = "default";
              };
            }
          ];
          teams = [
            {
              name = "Forge platform";
              sources = [ "Forge platform logs" ];
              members = [
                {
                  email = "admin@forge.local";
                  role = "admin";
                }
              ];
            }
          ];
        };
      };

      forge.services.observability = {
        enable = true;
        grafanaSecretKeyFile = "/run/keys/grafana-secret-key";
      };

      # This password exists only in the disposable test VM. Keep it outside
      # the Nix store while exercising Grafana's file-backed secret handling.
      services.grafana.settings.security.admin_password =
        "$__file{/run/credentials/grafana.service/grafana-admin-password}";

      systemd.services.grafana.serviceConfig.LoadCredential = lib.mkAfter [
        "grafana-admin-password:/run/keys/grafana-admin-password"
      ];

      systemd.services.logchef = {
        after = [ "forge-observability-clickhouse-schema.service" ];
        requires = [ "forge-observability-clickhouse-schema.service" ];
      };

      systemd.tmpfiles.rules = [
        "f /run/keys/grafana-secret-key 0444 root root - forge-test-grafana-secret"
        "f /run/keys/grafana-admin-password 0444 root root - forge-test-grafana-admin"
        "f /run/keys/logchef-api-token-secret 0444 root root - forge-test-logchef-secret-012345678901234567890123456789"
        "f /run/keys/logchef-admin-password 0444 root root - forge-test-logchef-admin-password-012345678901234567890"
      ];

      environment.systemPackages = [
        pkgs.curl
        pkgs.jq
        pkgs.systemd
      ];
      system.stateVersion = "24.11";
      virtualisation.memorySize = 8192;
      virtualisation.cores = 2;
    };

  testScript = ''
    import json
    import shlex

    start_all()
    machine.wait_for_unit("multi-user.target", timeout=60)
    machine.wait_for_unit("clickhouse.service", timeout=60)
    machine.wait_for_unit("forge-observability-clickhouse-schema.service", timeout=60)
    machine.wait_for_unit("vector.service", timeout=60)
    machine.wait_for_unit("prometheus.service", timeout=60)
    machine.wait_for_unit("grafana.service", timeout=60)
    machine.wait_for_unit("logchef.service", timeout=60)
    machine.wait_for_open_port(8123, timeout=60)
    machine.wait_for_open_port(8125, timeout=60)
    machine.wait_for_open_port(9090, timeout=60)
    machine.wait_for_open_port(3001, timeout=60)
    machine.succeed("curl --fail --silent http://127.0.0.1:8123/ping | grep -F Ok")
    machine.succeed("curl --fail --silent http://127.0.0.1:9090/-/ready")
    machine.succeed("curl --fail --silent http://127.0.0.1:3001/api/health | grep -F ok")
    machine.succeed("curl --fail --silent http://127.0.0.1:8125/ | grep -F 'id=\"app\"'")

    marker = "forge-observability-ingestion-marker"
    machine.succeed("systemd-cat --identifier=forge-observability-smoke echo " + marker)
    machine.wait_until_succeeds(
        "curl --fail --silent --get --data-urlencode \"query=SELECT count() FROM logs.events WHERE position(event, '" + marker + "') > 0\" http://127.0.0.1:8123/ | grep -E -q '^[1-9][0-9]*$'",
        timeout=90,
    )

    logchef_base = "http://127.0.0.1:8125/api/v1/"
    login_body = json.dumps(
        {
            "email": "admin@forge.local",
            "password": "forge-test-logchef-admin-password-012345678901234567890",
        }
    )
    machine.succeed(
        "curl --fail --silent --show-error --cookie-jar /tmp/logchef.cookies "
        "--header 'Content-Type: application/json' --data "
        + shlex.quote(login_body)
        + " "
        + logchef_base
        + "auth/local/login | jq -e '.status == \"success\"'"
    )
    machine.wait_until_succeeds(
        "curl --fail --silent --cookie /tmp/logchef.cookies "
        + logchef_base
        + "me/teams | jq -e '.status == \"success\" and (.data | length > 0)'",
        timeout=60,
    )
    teams = json.loads(
        machine.succeed("curl --fail --silent --cookie /tmp/logchef.cookies " + logchef_base + "me/teams")
    )["data"]
    team_id = teams[0]["id"]
    sources = json.loads(
        machine.succeed(
            f"curl --fail --silent --cookie /tmp/logchef.cookies {logchef_base}teams/{team_id}/sources"
        )
    )["data"]
    if not sources:
        raise Exception("Logchef provisioned team has no sources")
    source_id = sources[0]["id"]

    logchef_query = json.dumps(
        {
            "query_text": f"SELECT event FROM logs.events WHERE position(event, '{marker}') > 0 ORDER BY timestamp DESC LIMIT 20",
            "limit": 20,
        }
    )
    logchef_response = json.loads(
        machine.succeed(
            f"curl --fail --silent --show-error --cookie /tmp/logchef.cookies "
            f"--header 'Content-Type: application/json' --data {shlex.quote(logchef_query)} "
            f"{logchef_base}teams/{team_id}/sources/{source_id}/logs/query"
        )
    )
    if logchef_response.get("status") != "success":
        raise Exception(f"Logchef query failed: {logchef_response}")
    logchef_rows = logchef_response.get("data", {}).get("data", [])
    if not any(marker in row.get("event", "") for row in logchef_rows):
        raise Exception("Logchef query did not return the ingested marker")

    grafana_query = json.dumps(
        {
            "queries": [
                {
                    "refId": "A",
                    "datasource": {"type": "prometheus", "uid": "forge-prometheus"},
                    "expr": "up",
                    "range": True,
                    "format": "time_series",
                    "intervalMs": 15000,
                    "maxDataPoints": 1000,
                }
            ],
            "from": "now-5m",
            "to": "now",
        }
    )
    grafana_probe = (
      "curl --fail --silent --show-error --user admin:forge-test-grafana-admin "
        "--header 'Content-Type: application/json' --data "
        + shlex.quote(grafana_query)
        + " http://127.0.0.1:3001/api/ds/query | "
      "jq -e '.results.A.status == 200 and (.results.A.frames | length > 0)'"
    )
    machine.wait_until_succeeds(grafana_probe, timeout=60)
    machine.wait_until_succeeds(
        "curl --fail --silent --show-error --user admin:forge-test-grafana-admin "
        "http://127.0.0.1:3001/api/dashboards/uid/forge-overview | "
        "jq -e '.dashboard.uid == \"forge-overview\" and (.dashboard.panels | length > 0)'",
        timeout=60,
    )
  '';
}
