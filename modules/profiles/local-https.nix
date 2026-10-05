{
  config,
  lib,
  pkgs,
  ...
}:
{
  # Exercise the production software with real services, using only local
  # certificate issuance, disposable credentials, and private SMTP capture.
  imports = [
    ./production.nix
    ../local-secrets.nix
  ];
  forge.platform.domain = "forge.test";
  forge.localSecrets = {
    enable = true;
    persistFixture = true;
    ageKeyFile = config.forge.productionSecrets.ageKeyFile;
    sopsFile = /etc/forge/secrets/production.yaml;
  };
  systemd.services.forge-production-secret-check = {
    after = [ "forge-local-sops-fixture.service" ];
    requires = [ "forge-local-sops-fixture.service" ];
  };
  forge.services.mailpit.enable = lib.mkForce true;
  forge.services.forgejo = {
    smtp.address = lib.mkForce "127.0.0.1";
    smtp.port = lib.mkForce 1025;
    smtp.passwordFile = lib.mkForce null;
  };
  forge.services.discourse.mail = {
    serverAddress = lib.mkForce "127.0.0.1";
    port = lib.mkForce 1025;
  };
  forge.services.haproxy.additionalHostPorts = [ 8443 ];
  forge.productionIngress.publicPort = 8443;
  systemd.services.forge-local-tls = {
    description = "Issue a disposable local CA and HTTPS certificate";
    before = [ "haproxy.service" ];
    requiredBy = [ "haproxy.service" ];
    path = [
      pkgs.coreutils
      pkgs.openssl
    ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      StateDirectory = "forge-local-tls";
      StateDirectoryMode = "0700";
    };
    script = ''
      set -euo pipefail
      umask 077
      install -d -o root -g haproxy -m 0750 /etc/forge/tls
      if [ ! -s /etc/forge/tls/edge.pem ]; then
        cd /var/lib/forge-local-tls
        openssl req -x509 -newkey rsa:2048 -nodes -days 30 \
          -subj '/CN=Forge disposable local CA' -keyout ca.key -out ca.crt
        openssl req -newkey rsa:2048 -nodes -subj '/CN=forge.forge.test' \
          -keyout edge.key -out edge.csr
        printf '%s\n' 'subjectAltName=DNS:forge.forge.test,DNS:community.forge.test' \
          'extendedKeyUsage=serverAuth' > extensions
        openssl x509 -req -in edge.csr -CA ca.crt -CAkey ca.key -CAcreateserial \
          -days 30 -extfile extensions -out edge.crt
        cat edge.key edge.crt ca.crt > edge.pem
        install -o root -g haproxy -m 0640 edge.pem /etc/forge/tls/edge.pem
      fi
    '';
  };
  systemd.services.haproxy.after = [ "forge-local-tls.service" ];
  # The shared host store is owned by nobody in interactive QEMU guests.
  systemd.services.logrotate-checkconf.enable = false;
  environment.systemPackages = [ pkgs.jq ];
}
