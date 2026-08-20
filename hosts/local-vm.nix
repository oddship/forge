{
  config,
  lib,
  modulesPath,
  pkgs,
  ...
}:

{
  imports = [
    (modulesPath + "/virtualisation/qemu-vm.nix")
    ../modules/base.nix
    ../modules/services
  ];

  networking.hostName = "forge-local";
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
      return = ''200 "<!doctype html><html><head><title>Forge local VM</title></head><body><h1>Forge local VM</h1><ul><li><a href=\"http://forge.localhost:8082\">Forgejo</a></li><li><a href=\"http://discourse.localhost:8081\">Discourse</a></li><li><a href=\"http://mailpit.localhost:8083\">Mailpit</a></li></ul></body></html>"'';
    };
  };

  forge.services.haproxy = {
    enable = true;
    additionalHostPorts = [ 8080 ];
  };

  forge.services.mailpit.enable = true;
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
    settings.server.ROOT_URL = "http://forge.localhost:8082/";
  };
  forge.services.discourse = {
    enable = true;
    hostname = "discourse.localhost";
    backup.enable = true;
  };
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

  virtualisation.forwardPorts = [
    {
      from = "host";
      host.address = "127.0.0.1";
      host.port = 8080;
      guest.port = 80;
    }
    {
      from = "host";
      host.address = "127.0.0.1";
      host.port = 8081;
      guest.port = 8081;
    }
    {
      from = "host";
      host.address = "127.0.0.1";
      host.port = 8082;
      guest.port = 8082;
    }
    {
      from = "host";
      host.address = "127.0.0.1";
      host.port = 8083;
      guest.port = 8083;
    }
    {
      from = "host";
      host.address = "127.0.0.1";
      host.port = 2222;
      guest.port = 2222;
    }
    {
      from = "host";
      host.address = "127.0.0.1";
      host.port = 2200;
      guest.port = 22;
    }
  ];
  virtualisation.memorySize = 4096;
  virtualisation.cores = 2;

  system.stateVersion = "24.11";
}
