{ pkgs, sopsNix, ... }:
pkgs.testers.runNixOSTest {
  name = "forge-local-https-smoke";
  nodes.machine = {
    imports = [
      sopsNix.nixosModules.sops
      ../modules/profiles/local-https.nix
    ];
    virtualisation.memorySize = 4096;
    virtualisation.cores = 2;
  };
  testScript = ''
    start_all()
    machine.wait_for_unit("forgejo-admin-bootstrap.service")
    machine.wait_for_unit("haproxy.service")
    machine.wait_for_unit("discourse.service", timeout=600)
    ca = "/var/lib/forge-local-tls/ca.crt"
    forge = f"curl --fail --silent --show-error --max-time 10 --cacert {ca} --connect-to forge.forge.test:8443:127.0.0.1:443 https://forge.forge.test:8443"
    discourse = f"curl --fail --silent --show-error --max-time 10 --cacert {ca} --connect-to community.forge.test:8443:127.0.0.1:443 https://community.forge.test:8443"
    machine.wait_until_succeeds(f"{forge}/api/healthz", timeout=120)
    machine.wait_until_succeeds(f"{discourse}/srv/status", timeout=180)
    machine.succeed(f"{forge}/api/v1/user -u forge-admin:forge-local-forgejo-admin | jq -e '.is_admin == true'")
    csrf = machine.succeed(f"{discourse}/session/csrf.json -c /tmp/discourse.cookies | jq -r '.csrf'").strip()
    machine.succeed(f"{discourse}/session.json -b /tmp/discourse.cookies -c /tmp/discourse.cookies -H 'Origin: https://community.forge.test:8443' -H 'Accept: application/json' -H 'X-Requested-With: XMLHttpRequest' -H 'X-CSRF-Token: {csrf}' --data-urlencode login=admin --data-urlencode password=forge-local-discourse-admin | jq -e '.user.admin == true'")
    machine.succeed(f"{discourse}/session/current.json -b /tmp/discourse.cookies | jq -e '.current_user.admin == true'")
    machine.succeed("curl --silent --max-time 10 -I -H 'Host: forge.forge.test' http://127.0.0.1 | grep -i 'location: https://forge.forge.test/'")
    machine.succeed(f"curl --silent --max-time 10 --cacert {ca} --resolve forge.forge.test:443:127.0.0.1 -H 'Host: mailpit.localhost' -o /dev/null -w '%{{http_code}}' https://forge.forge.test | grep '^404$'")
    machine.succeed("test $(stat -c '%u:%a' /var/lib/forge/secrets/age-key.txt) = 0:600")
    paths = "/var/lib/forge/secrets/age-key.txt /etc/forge/secrets/production.yaml /run/secrets/discourse-secret-key-base /etc/forge/tls/edge.pem"
    before = machine.succeed(f"sha256sum {paths}")
    machine.reboot()
    # The driver's default QEMU launch uses -no-reboot. Restart the same
    # persistent disk after the guest completes its actual reboot shutdown.
    machine.wait_for_shutdown()
    machine.start()
    machine.wait_for_unit("sops-install-secrets.service")
    machine.wait_for_unit("forge-production-secret-check.service")
    machine.wait_for_unit("haproxy.service")
    machine.wait_for_unit("discourse.service", timeout=600)
    assert before == machine.succeed(f"sha256sum {paths}"), "secrets or certificates changed across reboot"
    machine.wait_until_succeeds(f"{forge}/api/v1/user -u forge-admin:forge-local-forgejo-admin | jq -e '.is_admin == true'", timeout=120)
    machine.wait_until_succeeds(f"{discourse}/srv/status", timeout=180)
  '';
}
