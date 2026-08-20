{ pkgs, ... }:

pkgs.testers.runNixOSTest {
  name = "forge-zitadel-smoke";

  nodes.machine =
    { lib, pkgs, ... }:
    {
      imports = [
        ../modules/base.nix
        ../modules/services
      ];

      forge.services.zitadel = {
        enable = true;
        externalDomain = "id.example.com";
        externalPort = 8080;
        tlsMode = "disabled";
        masterKeyFile = "/run/keys/zitadel-master-key";
        databaseSettingsFile = "/run/keys/zitadel-database.yaml";
        bootstrapStepsFile = "/run/keys/zitadel-steps.yaml";
        backup.enable = true;
      };

      forge.services.postgresql.users = lib.mkAfter [
        {
          name = "zitadel";
          ensureClauses.password = "zitadel";
        }
      ];

      services.postgresql.initialScript = pkgs.writeText "zitadel-test-postgresql-init.sql" ''
        ALTER ROLE postgres PASSWORD 'postgres';
      '';

      systemd.services.zitadel-test-secrets = {
        description = "Fixture-only ZITADEL runtime secrets";
        before = [ "zitadel.service" ];
        wantedBy = [ "multi-user.target" ];
        path = [ pkgs.coreutils ];
        serviceConfig = {
          Type = "oneshot";
          RemainAfterExit = true;
        };
        script = ''
          install -d -m 0755 /run/keys
          printf '%s' 01234567890123456789012345678901 > /run/keys/zitadel-master-key
          printf '%s\n' 'Database: { postgres: { DSN: "postgresql:///zitadel?host=/run/postgresql", User: { Password: "zitadel" }, Admin: { Password: "postgres" } } }' > /run/keys/zitadel-database.yaml
          printf '%s\n' 'FirstInstance: { Org: { Human: { Username: "root", Password: "RootPassword1!" } } }' > /run/keys/zitadel-steps.yaml
          chmod 0444 /run/keys/zitadel-master-key /run/keys/zitadel-database.yaml /run/keys/zitadel-steps.yaml
        '';
      };

      systemd.services.zitadel = {
        after = [ "zitadel-test-secrets.service" ];
        requires = [ "zitadel-test-secrets.service" ];
      };

      environment.systemPackages = [ pkgs.curl ];
      system.stateVersion = "24.11";
      virtualisation.memorySize = 4096;
      virtualisation.cores = 2;
    };

  testScript = ''
    start_all()
    machine.wait_for_unit("postgresql.service", timeout=60)
    machine.wait_for_unit("zitadel-test-secrets.service", timeout=60)
    machine.wait_for_unit("zitadel.service", timeout=180)
    machine.wait_for_open_port(8080, timeout=60)
    machine.succeed("curl --fail --silent http://127.0.0.1:8080/debug/healthz")
    machine.succeed("systemctl start zitadel-backup.service")
    archive = machine.succeed("find /var/backup/zitadel -maxdepth 1 -type f -name 'zitadel-*.tar.zst' -print -quit").strip()
    machine.succeed(f"test -n {archive!r}")
    machine.succeed(f"tar --zstd --list --file {archive} > /tmp/zitadel-archive-list")
    for member in ["database.dump", "master-key", "database-settings.yaml", "bootstrap-steps.yaml"]:
        machine.succeed(f"grep -F -x {member!r} /tmp/zitadel-archive-list")
    machine.succeed(f"FORGE_ALLOW_DESTRUCTIVE_RESTORE=1 forge-zitadel-restore {archive!r}")
    machine.wait_for_unit("zitadel.service", timeout=180)
    machine.wait_for_open_port(8080, timeout=60)
    machine.succeed("curl --fail --silent http://127.0.0.1:8080/debug/healthz")
  '';
}
