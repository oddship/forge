{
  config,
  lib,
  pkgs,
  ...
}:

{
  imports = [
    ../platform.nix
    ../local-apps.nix
    ../local-secrets.nix
    ../secrets.nix
  ];

  forge.platform.domain = "localhost";
  networking.firewall.allowedTCPPorts = [
    22
    8081
    8082
    8083
  ];

  # This password-only account is a disposable local-console convenience. The
  # production host keeps operator SSH key-only and receives its key through
  # the provider/bootstrap boundary.
  users.users.operator = {
    isNormalUser = true;
    initialPassword = "forge-local-operator";
    extraGroups = [ "wheel" ];
  };
  services.openssh.settings.PasswordAuthentication = lib.mkForce true;

  # The QEMU VM mounts the host Nix store with its files owned by the guest's
  # nobody user. Logrotate 3.22 rejects the generated store-backed config in
  # its boot-time check for that reason, even though NixOS already validates
  # the same config while building it. Keep the runtime check enabled on
  # production hosts, where store paths are root-owned.
  systemd.services.logrotate-checkconf.enable = false;

  services.nginx.enable = true;
  services.nginx.virtualHosts."default" = {
    listen = [
      {
        addr = "127.0.0.1";
        port = 18080;
      }
    ];
    locations."/" = {
      extraConfig = "default_type text/html;";
      # Keep the landing page content in a standalone asset so it can be
      # edited and reviewed as HTML rather than as a Nix string literal.
      return = "200 ${builtins.toJSON (builtins.readFile ../../hosts/local-vm-landing.html)}";
    };
  };

  forge.services.haproxy = {
    enable = true;
    additionalHostPorts = [ 8080 ];
  };

  forge.services.mailpit.enable = true;
  # These dashboard/password services are disposable local fixtures. The VM
  # is reachable through host-bound QEMU forwards, not a public listener.
  forge.localApps.enable = true;
  forge.services.penpot = {
    enable = true;
    localFixture = true;
    publicUri = "http://penpot.localhost:8080";
    smtp = {
      port = 1025;
      tls = false;
      from = "penpot@penpot.localhost";
    };
  };
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
    domain = "forge.localhost";
    ssh.enable = true;
    admin = {
      bootstrap = true;
      email = "admin@forge.localhost";
      passwordFile = config.sops.secrets."forgejo-admin-password".path;
    };
    backup.enable = true;
    settings.server.ROOT_URL = "http://forge.localhost:8080/";
  };
  forge.services.forgejoRunner = {
    enable = true;
    url = "http://127.0.0.1:3000/";
    uuid = "@FORGEJO_RUNNER_UUID@";
    tokenFile = "/var/lib/forgejo-runner-bootstrap/token";
    containerRuntime = "podman";
  };
  systemd.services.forgejo-runner-bootstrap = {
    description = "Register the disposable local Forgejo Actions runner";
    after = [ "forgejo-admin-bootstrap.service" ];
    requires = [ "forgejo-admin-bootstrap.service" ];
    before = [ "forgejo-runner-default.service" ];
    wantedBy = [ "multi-user.target" ];
    path = [
      pkgs.coreutils
      pkgs.curl
      pkgs.jq
    ];
    serviceConfig = {
      Type = "oneshot";
      StateDirectory = "forgejo-runner-bootstrap";
      StateDirectoryMode = "0700";
    };
    script = ''
      ${lib.getExe pkgs.bash} ${../../scripts/forgejo-runner-bootstrap} \
        http://127.0.0.1:3000 \
        ${config.sops.secrets."forgejo-admin-password".path} \
        /var/lib/forgejo-runner-bootstrap
    '';
  };
  systemd.services."forgejo-runner-default" = {
    after = [ "forgejo-runner-bootstrap.service" ];
    requires = [ "forgejo-runner-bootstrap.service" ];
    preStart = ''
      rm -f ./config.yaml
      cp -v ${config.services.forgejo-runner.instances.default.configFile} ./config.yaml
      chmod u+w ./config.yaml
      ${lib.getExe pkgs.replace-secret} \
        "@FORGEJO_RUNNER_UUID@" \
        "$CREDENTIALS_DIRECTORY/UUID" \
        ./config.yaml
      chmod u-w ./config.yaml
    '';
    serviceConfig = {
      ExecStart = lib.mkForce "${lib.getExe config.services.forgejo-runner.package} daemon --config ./config.yaml";
      LoadCredential = [ "UUID:/var/lib/forgejo-runner-bootstrap/uuid" ];
    };
  };
  forge.services.discourse = {
    enable = true;
    hostname = "discourse.localhost";
    backup.enable = true;
  };
  services.discourse.siteSettings.developer.port = 8080;
  # NixOS siteSettings are defaults and do not replace a value already stored
  # in Discourse's persistent database. Enforce the disposable browser origin
  # on every start so authentication callbacks retain the forwarded host port.
  systemd.services.discourse.preStart = lib.mkAfter ''
    ${config.services.discourse.package.rubyEnv}/bin/bundle exec rails runner \
      'SiteSetting.port = 8080'
  '';
  services.nginx.virtualHosts."discourse.localhost".listen = [
    {
      addr = "127.0.0.1";
      port = 18081;
    }
  ];

  forge.localSecrets.enable = true;

  services.nginx.virtualHosts."browser-forgejo" = {
    listen = [
      {
        addr = "0.0.0.0";
        port = 8082;
      }
    ];
    locations."/".proxyPass = "http://127.0.0.1:3000";
  };
  services.nginx.virtualHosts."browser-discourse" = {
    listen = [
      {
        addr = "0.0.0.0";
        port = 8081;
      }
    ];
    locations."/".proxyPass = "http://discourse";
  };
  services.nginx.virtualHosts."browser-mailpit" = {
    listen = [
      {
        addr = "0.0.0.0";
        port = 8083;
      }
    ];
    locations."/".proxyPass = "http://127.0.0.1:8025";
  };

  environment.systemPackages = [
    pkgs.curl
    pkgs.postgresql_17
    pkgs.redis
  ];

}
