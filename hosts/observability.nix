{
  modulesPath,
  logchef,
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

  networking.hostName = "forge-observability";
  networking.firewall.allowedTCPPorts = [
    3001
    8125
    9090
  ];

  services.logchef = {
    enable = true;
    package = logchef.packages.x86_64-linux.logchef;
    listenAddress = "0.0.0.0";
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
      manage_teams = false;
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
    };
  };

  forge.services.observability = {
    enable = true;
    listenAddress = "0.0.0.0";
    internalAddress = "127.0.0.1";
    grafanaSecretKeyFile = "/run/keys/grafana-secret-key";
  };

  # Deterministic credentials are only for this disposable local VM. Production
  # deployments must replace them with external secret injection.
  systemd.tmpfiles.rules = [
    "f /run/keys/grafana-secret-key 0444 root root - forge-local-grafana-secret"
    "f /run/keys/logchef-api-token-secret 0444 root root - forge-local-logchef-api-token-secret"
    "f /run/keys/logchef-admin-password 0444 root root - forge-local-admin-password"
  ];

  systemd.services.logchef = {
    after = [ "forge-observability-clickhouse-schema.service" ];
    requires = [ "forge-observability-clickhouse-schema.service" ];
  };

  environment.systemPackages = [ pkgs.curl ];

  virtualisation.forwardPorts = [
    {
      from = "host";
      host.address = "127.0.0.1";
      host.port = 8125;
      guest.port = 8125;
    }
    {
      from = "host";
      host.address = "127.0.0.1";
      host.port = 9090;
      guest.port = 9090;
    }
    {
      from = "host";
      host.address = "127.0.0.1";
      host.port = 3001;
      guest.port = 3001;
    }
  ];
  virtualisation.memorySize = 8192;
  virtualisation.cores = 2;

  system.stateVersion = "24.11";
}
