{ config, lib, ... }:

let
  cfg = config.forge.services.haproxy;
  hostValues =
    domain:
    lib.concatStringsSep " " (
      [ domain ]
      ++ map (port: "${domain}:${toString port}") ([ cfg.listenPort ] ++ cfg.additionalHostPorts)
    );
in
{
  options.forge.services.haproxy = {
    enable = lib.mkEnableOption "the Forge HAProxy edge";

    listenAddress = lib.mkOption {
      type = lib.types.str;
      default = "0.0.0.0";
      description = "Address on which the HTTP edge listens.";
    };

    listenPort = lib.mkOption {
      type = lib.types.port;
      default = 80;
      description = "Port on which the HTTP edge listens.";
    };

    additionalHostPorts = lib.mkOption {
      type = lib.types.listOf lib.types.port;
      default = [ ];
      description = "Host-side ports that may appear in local Host headers.";
    };

    forgejoDomain = lib.mkOption {
      type = lib.types.str;
      default = "forge.localhost";
    };

    discourseDomain = lib.mkOption {
      type = lib.types.str;
      default = "discourse.localhost";
    };

    mailpitDomain = lib.mkOption {
      type = lib.types.str;
      default = "mailpit.localhost";
    };

    dashboardDomain = lib.mkOption {
      type = lib.types.str;
      default = "dashboard.localhost";
    };

    vaultwardenDomain = lib.mkOption {
      type = lib.types.str;
      default = "vaultwarden.localhost";
    };

    penpotDomain = lib.mkOption {
      type = lib.types.str;
      default = "penpot.localhost";
    };

    penpotBackend = lib.mkOption {
      type = lib.types.str;
      default = "127.0.0.1:18083";
    };

    forgejoBackend = lib.mkOption {
      type = lib.types.str;
      default = "127.0.0.1:3000";
    };

    discourseBackend = lib.mkOption {
      type = lib.types.str;
      default = "127.0.0.1:18081";
    };

    mailpitBackend = lib.mkOption {
      type = lib.types.str;
      default = "127.0.0.1:8025";
    };

    dashboardBackend = lib.mkOption {
      type = lib.types.str;
      default = "127.0.0.1:18082";
    };

    vaultwardenBackend = lib.mkOption {
      type = lib.types.str;
      default = "127.0.0.1:8222";
    };

    landingBackend = lib.mkOption {
      type = lib.types.str;
      default = "127.0.0.1:18080";
    };
  };

  config = lib.mkIf cfg.enable {
    services.haproxy = {
      enable = true;
      config = ''
        defaults
          mode http
          option forwardfor
          option http-keep-alive
          timeout connect 5s
          timeout client 30s
          timeout server 30s

        frontend forge-http
          bind ${cfg.listenAddress}:${toString cfg.listenPort}
          http-request set-header X-Forwarded-Proto http
          acl forgejo_host hdr(host) -i ${hostValues cfg.forgejoDomain}
          acl discourse_host hdr(host) -i ${hostValues cfg.discourseDomain}
          acl mailpit_host hdr(host) -i ${hostValues cfg.mailpitDomain}
          acl dashboard_host hdr(host) -i ${hostValues cfg.dashboardDomain}
          acl vaultwarden_host hdr(host) -i ${hostValues cfg.vaultwardenDomain}
          ${lib.optionalString config.forge.services.penpot.enable "acl penpot_host hdr(host) -i ${hostValues cfg.penpotDomain}"}
          use_backend forgejo if forgejo_host
          use_backend discourse if discourse_host
          use_backend mailpit if mailpit_host
          use_backend dashboard if dashboard_host
          use_backend vaultwarden if vaultwarden_host
          ${lib.optionalString config.forge.services.penpot.enable "use_backend penpot if penpot_host"}
          default_backend landing

        backend forgejo
          server forgejo ${cfg.forgejoBackend} check

        backend discourse
          server discourse ${cfg.discourseBackend} check

        backend mailpit
          server mailpit ${cfg.mailpitBackend} check

        backend dashboard
          server dashboard ${cfg.dashboardBackend} check

        backend vaultwarden
          server vaultwarden ${cfg.vaultwardenBackend} check

        ${lib.optionalString config.forge.services.penpot.enable ''
          backend penpot
            timeout tunnel 1h
            server penpot ${cfg.penpotBackend} check
        ''}

        backend landing
          server landing ${cfg.landingBackend} check
      '';
    };
  };
}
