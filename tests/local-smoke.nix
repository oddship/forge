{ pkgs, sopsNix, ... }:

let
  actionsWorkflow = pkgs.writeText "local-workflow.yml" ''
    name: local workflow
    on:
      push:
    jobs:
      smoke:
        runs-on: ubuntu-latest
        steps:
          - run: echo forge-actions-ok
  '';

  actionsImage = pkgs.dockerTools.buildImage {
    name = "forge-actions";
    tag = "local";
    copyToRoot = pkgs.buildEnv {
      name = "forge-actions-root";
      paths = with pkgs; [
        bashInteractive
        coreutils
        gitMinimal
        dockerTools.binSh
        dockerTools.fakeNss
      ];
      pathsToLink = [
        "/bin"
        "/etc"
      ];
    };
    config.Cmd = [ "/bin/bash" ];
  };
in
pkgs.testers.runNixOSTest {
  name = "forge-local-smoke";

  nodes.machine =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    {
      imports = [
        sopsNix.nixosModules.sops
        ../modules/base.nix
        ../modules/local-apps.nix
        ../modules/local-secrets.nix
        ../modules/operator-access.nix
        ../modules/secrets.nix
        ../modules/services
      ];

      services.nginx.enable = true;
      services.nginx.virtualHosts."default" = {
        listen = [
          {
            addr = "127.0.0.1";
            port = 18080;
          }
        ];
        locations."/".return = ''200 "Forge local target"'';
      };
      forge.services.mailpit.enable = true;
      forge.localApps.enable = true;
      forge.services.postgresql = {
        enable = true;
        databases = [ "forgejo" ];
        users = [
          {
            name = "forgejo";
            ensureDBOwnership = true;
          }
        ];
        backup = {
          enable = true;
          pgdumpOptions = "--format=custom";
        };
      };
      forge.services.redis.enable = true;
      forge.services.redis.backup.enable = true;
      forge.services.forgejo = {
        enable = true;
        ssh.enable = true;
        admin = {
          bootstrap = true;
          email = "admin@forge.local";
          passwordFile = config.sops.secrets."forgejo-admin-password".path;
        };
        backup.enable = true;
      };
      forge.services.forgejoRunner = {
        enable = true;
        autoStart = false;
        uuid = "@FORGEJO_RUNNER_UUID@";
        tokenFile = "/run/forgejo-runner/token";
        containerRuntime = "podman";
        labels = [ "ubuntu-latest:docker://forge-actions:local" ];
      };
      systemd.services."forgejo-runner-default" = {
        preStart = ''
          cp -v ${config.services.forgejo-runner.instances.default.configFile} ./config.yaml
          chmod u+w ./config.yaml
          ${lib.getExe pkgs.replace-secret} "@FORGEJO_RUNNER_UUID@" "$CREDENTIALS_DIRECTORY/UUID" ./config.yaml
          chmod u-w ./config.yaml
        '';
        serviceConfig = {
          ExecStart = lib.mkForce "${lib.getExe config.services.forgejo-runner.package} daemon --config ./config.yaml";
          LoadCredential = [ "UUID:/run/forgejo-runner/uuid" ];
        };
      };
      forge.services.discourse = {
        enable = true;
        hostname = "discourse.local";
        backup.enable = true;
      };
      services.nginx.virtualHosts."discourse.local".listen = [
        {
          addr = "127.0.0.1";
          port = 18081;
        }
      ];
      forge.services.haproxy = {
        enable = true;
        discourseDomain = "discourse.local";
      };
      forge.localSecrets.enable = true;
      forge.operatorAccess.enable = true;
      environment.systemPackages = [
        config.services.forgejo.package
        config.services.discourse.package
        pkgs.curl
        pkgs.git
        pkgs.jq
        pkgs.openssh
        pkgs.postgresql_17
        pkgs.redis
      ];

      system.stateVersion = "24.11";
      virtualisation.memorySize = 4096;
      virtualisation.cores = 2;
    };

  testScript = ''
    import json
    import shlex

    start_all()
    machine.wait_for_unit("multi-user.target")
    machine.wait_for_unit("nginx.service")
    machine.wait_for_unit("haproxy.service")
    machine.wait_for_unit("mailpit-forge.service")
    machine.wait_for_unit("homepage-dashboard.service")
    machine.wait_for_unit("vaultwarden.service")
    machine.wait_for_unit("postgresql.service")
    machine.wait_for_unit("redis-forge.service")
    machine.wait_for_unit("redis-discourse.service")
    machine.wait_for_unit("forgejo.service")
    machine.wait_until_succeeds("test -e /var/lib/forgejo-admin-bootstrap/created", timeout=90)
    machine.succeed("systemctl is-active forgejo-admin-bootstrap.service")
    machine.wait_for_unit("discourse.service")
    machine.wait_for_unit("sops-install-secrets.service")
    machine.wait_for_unit("podman.socket")
    machine.succeed('ssh-keygen -q -t ed25519 -N "" -f /tmp/operator-key')
    machine.succeed("install -o root -g root -m 0600 /tmp/operator-key.pub /etc/forge/ssh/operator_authorized_keys")
    machine.succeed("systemctl reload sshd.service")
    machine.succeed("ssh -F /dev/null -i /tmp/operator-key -o IdentitiesOnly=yes -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o ConnectTimeout=10 operator@127.0.0.1 id -un | grep -Fx operator")
    machine.succeed("test -s /run/secrets/discourse-secret-key-base")
    machine.succeed('test "$(cat /run/secrets/discourse-admin-password)" = forge-local-discourse-admin')
    machine.succeed('test "$(cat /run/secrets/forgejo-admin-password)" = forge-local-forgejo-admin')
    machine.succeed("test -s /run/secrets/discourse-admin-password")
    machine.succeed("test -s /run/secrets/forgejo-admin-password")
    machine.succeed("grep -F 'sops:' /run/forge/local-secrets.yaml")
    initial_secret = machine.succeed("cat /run/secrets/discourse-secret-key-base").strip()
    machine.succeed("! grep -F -- " + repr(initial_secret) + " /run/forge/local-secrets.yaml")
    machine.succeed("! grep -F -- forge-local-discourse-admin /run/forge/local-secrets.yaml")
    machine.succeed("! grep -F -- forge-local-forgejo-admin /run/forge/local-secrets.yaml")
    machine.succeed("systemctl start forge-local-sops-rotate.service")
    machine.wait_until_succeeds("test -s /run/secrets/discourse-secret-key-base", timeout=30)
    rotated_secret = machine.succeed("cat /run/secrets/discourse-secret-key-base").strip()
    if initial_secret == rotated_secret:
        raise Exception("local SOPS rotation did not change the service secret")
    machine.succeed('test "$(cat /run/secrets/discourse-admin-password)" = forge-local-discourse-admin')
    machine.succeed('test "$(cat /run/secrets/forgejo-admin-password)" = forge-local-forgejo-admin')
    machine.wait_for_unit("discourse.service")
    machine.wait_for_open_port(3000)
    machine.wait_until_succeeds("ss -ltn | grep -F ':2222 '", timeout=90)
    machine.wait_for_open_port(80)
    machine.succeed("curl --fail -u forge-admin:forge-local-forgejo-admin http://127.0.0.1:3000/api/v1/user | jq -e '.is_admin == true'")
    machine.succeed("systemctl start postgresqlBackup-forgejo.service")
    machine.succeed("systemctl stop forgejo.service")
    machine.succeed("su - postgres -c 'dropdb --if-exists forgejo'")
    machine.succeed("gzip -dc /var/backup/postgresql/forgejo.sql.gz | su - postgres -c 'pg_restore --create --dbname=postgres'")
    machine.succeed("su - postgres -c 'psql --dbname=forgejo --command=\"SELECT 1\"'")
    machine.succeed("systemctl start forgejo.service")
    machine.wait_for_open_port(3000)
    machine.succeed("redis-cli -h 127.0.0.1 SET restore-marker forge")
    machine.succeed("systemctl start redisBackup-forge.service")
    machine.succeed("systemctl stop redis-forge.service")
    machine.succeed("cp /var/backup/redis/forge.rdb /var/lib/redis-forge/dump.rdb")
    machine.succeed("systemctl start redis-forge.service")
    machine.succeed("redis-cli -h 127.0.0.1 GET restore-marker | grep -F forge")
    machine.succeed("systemctl start discourse-backup.service")
    machine.succeed("archive=$(find /var/backup/discourse -maxdepth 1 -type f -name 'discourse-*.tar.zst' -print -quit); test -n \"$archive\"; FORGE_ALLOW_DESTRUCTIVE_RESTORE=1 forge-discourse-restore \"$archive\"")
    machine.wait_for_unit("discourse.service")
    # systemd becomes active before restored Discourse workers can serve HTTP.
    # A cold worker took over a minute in the real restore drill. Bound every
    # request so a stalled proxy response cannot consume the polling deadline.
    machine.wait_until_succeeds("curl --fail --silent --show-error --connect-timeout 3 --max-time 10 -H 'Host: discourse.local' http://127.0.0.1/ | grep -i Discourse", timeout=180)
    machine.succeed("su -l forgejo -c 'GITEA_WORK_DIR=/var/lib/forgejo forgejo admin user create --admin --username test --password totallysafe --email test@localhost --must-change-password=false'")
    api_token = machine.succeed(
        "curl --fail -X POST http://test:totallysafe@127.0.0.1:3000/api/v1/users/test/tokens "
        + "-H 'Accept: application/json' -H 'Content-Type: application/json' "
        + "-d '{\"name\":\"local-smoke\",\"scopes\":[\"all\"]}' | jq -r '.sha1'"
    ).strip()
    machine.succeed('ssh-keygen -q -t ed25519 -N "" -f /tmp/forgejo-git-key')
    git_public_key = machine.succeed("cat /tmp/forgejo-git-key.pub").strip()
    machine.succeed(
        "curl --fail -X POST http://127.0.0.1:3000/api/v1/user/keys "
        + "-H 'Accept: application/json' -H 'Content-Type: application/json' "
        + f"-H 'Authorization: token {api_token}' "
        + "--data "
        + shlex.quote(json.dumps({"title": "local-smoke", "key": git_public_key}))
    )
    machine.succeed(
        "curl --fail -X POST http://127.0.0.1:3000/api/v1/user/repos "
        + "-H 'Accept: application/json' -H 'Content-Type: application/json' "
        + f"-H 'Authorization: token {api_token}' "
        + "-d '{\"auto_init\":false,\"name\":\"repo\",\"private\":false}'"
    )
    machine.succeed("mkdir -p /tmp/actions-repo/.forgejo/workflows")
    machine.succeed("git -C /tmp/actions-repo init -b main")
    machine.succeed("git -C /tmp/actions-repo config user.email test@localhost")
    machine.succeed("git -C /tmp/actions-repo config user.name test")
    machine.succeed("echo initial > /tmp/actions-repo/testfile")
    machine.succeed("git -C /tmp/actions-repo add .")
    machine.succeed("git -C /tmp/actions-repo commit -m 'chore: initialize local test repository'")
    machine.succeed("git -C /tmp/actions-repo remote add origin http://test:totallysafe@127.0.0.1:3000/test/repo.git")
    machine.succeed("git -C /tmp/actions-repo push origin main")
    ssh_command = "ssh -F /dev/null -i /tmp/forgejo-git-key -o IdentitiesOnly=yes -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o ConnectTimeout=10"
    machine.succeed(f"GIT_SSH_COMMAND={shlex.quote(ssh_command)} git -C /tmp/actions-repo ls-remote ssh://git@127.0.0.1:2222/test/repo.git")
    machine.succeed("echo ssh-push >> /tmp/actions-repo/testfile")
    machine.succeed("git -C /tmp/actions-repo add testfile && git -C /tmp/actions-repo commit -m 'test: verify git ssh push'")
    machine.succeed(f"GIT_SSH_COMMAND={shlex.quote(ssh_command)} git -C /tmp/actions-repo push ssh://git@127.0.0.1:2222/test/repo.git main")
    machine.succeed(
        "curl --fail -X PATCH http://127.0.0.1:3000/api/v1/repos/test/repo "
        + "-H 'Accept: application/json' -H 'Content-Type: application/json' "
        + f"-H 'Authorization: token {api_token}' "
        + "-d '{\"has_actions\":true}'"
    )
    runner_registration_response = machine.succeed(
        "curl --fail http://127.0.0.1:3000/api/v1/admin/actions/runners "
        + f"-H 'Authorization: token {api_token}' "
        + "--json '{\"name\":\"local-native\",\"ephemeral\":false}'"
    )
    runner_registration = json.loads(runner_registration_response)
    machine.succeed("mkdir -p /run/forgejo-runner")
    machine.succeed(f"printf '%s' {json.dumps(runner_registration['token'])} > /run/forgejo-runner/token")
    machine.succeed(f"printf '%s' {json.dumps(runner_registration['uuid'])} > /run/forgejo-runner/uuid")
    machine.succeed("podman load --input=${actionsImage}")
    machine.succeed("podman image exists forge-actions:local")
    machine.succeed("systemctl start forgejo-runner-default.service")
    machine.wait_for_unit("forgejo-runner-default.service")
    machine.wait_until_succeeds("journalctl -o cat -u forgejo-runner-default.service | grep -E -q 'declared successfully|registered successfully'", timeout=30)
    machine.succeed("cp ${actionsWorkflow} /tmp/actions-repo/.forgejo/workflows/smoke.yml")
    machine.succeed("git -C /tmp/actions-repo add .")
    machine.succeed("git -C /tmp/actions-repo commit -m 'ci: add Forgejo Actions smoke workflow'")
    machine.succeed("git -C /tmp/actions-repo push origin main")

    def actions_workflow_succeeded():
        response = machine.succeed("curl --fail http://127.0.0.1:3000/api/v1/repos/test/repo/actions/tasks")
        runs = json.loads(response).get("workflow_runs", [])
        if not runs:
            return False
        status = runs[0].get("status")
        machine.log(f"Forgejo Actions workflow status: {status}")
        if status == "failure":
            raise Exception("Forgejo Actions workflow failed")
        return status == "success"

    retry(lambda _: actions_workflow_succeeded(), 180)
    machine.succeed("curl --fail http://127.0.0.1/ | grep -F 'Forge local target'")
    machine.succeed("curl --fail -H 'Host: forge.localhost' http://127.0.0.1/ | grep -F Forgejo")
    machine.succeed("curl --fail -H 'Host: mailpit.localhost' http://127.0.0.1/ | grep -F 'Mailpit'")
    machine.succeed("curl --fail -H 'Host: dashboard.localhost' http://127.0.0.1/ | grep -F 'Forgejo'")
    machine.succeed("curl --fail -o /dev/null -H 'Host: vaultwarden.localhost' http://127.0.0.1/alive")
    machine.succeed("curl --fail http://127.0.0.1:3000/ | grep -F Forgejo")
    machine.succeed("curl --fail http://127.0.0.1:8025/ | grep -F 'Mailpit'")
    machine.succeed("pg_isready --host 127.0.0.1")
    machine.succeed("redis-cli -h 127.0.0.1 ping | grep -F PONG")
    machine.succeed("test -s /var/backup/postgresql/forgejo.sql.gz")
    machine.succeed("systemctl start backup-vaultwarden.service")
    machine.succeed("test -s /var/backup/vaultwarden/db.sqlite3")
    machine.succeed("systemctl stop vaultwarden.service")
    machine.succeed("install -o vaultwarden -g vaultwarden -m 0600 /var/backup/vaultwarden/db.sqlite3 /var/lib/vaultwarden/db.sqlite3")
    machine.succeed("systemctl start vaultwarden.service")
    machine.wait_for_unit("vaultwarden.service")
    machine.succeed("curl --fail -o /dev/null -H 'Host: vaultwarden.localhost' http://127.0.0.1/alive")
    machine.succeed("systemctl start forgejo-dump.service")
    machine.succeed("find /var/lib/forgejo/dump -type f -print -quit | grep .")
  '';
}
