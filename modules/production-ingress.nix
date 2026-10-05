{ config, lib, ... }:
let
  cfg = config.forge.productionIngress;
  edge = config.forge.services.haproxy;
  certificateName = "forge-edge";
in
{
  options.forge.productionIngress = {
    enable = lib.mkEnableOption "provider-independent production HTTPS ingress";
    certificateFile = lib.mkOption {
      type = lib.types.str;
      default = "/etc/forge/tls/edge.pem";
    };
    publicPort = lib.mkOption {
      type = lib.types.port;
      default = 443;
      description = "Canonical browser HTTPS port; local QEMU forwarding may use a different host port.";
    };
    acme = {
      enable = lib.mkEnableOption "HTTP-01 issuance and renewal through NixOS ACME";
      email = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = null;
      };
      acceptTerms = lib.mkOption {
        type = lib.types.bool;
        default = false;
      };
    };
  };
  config = lib.mkIf cfg.enable {
    forge.services.haproxy = {
      tls = {
        enable = true;
        certificateFile =
          if cfg.acme.enable then "/var/lib/acme/${certificateName}/full.pem" else cfg.certificateFile;
      };
      exposeLocalRoutes = false;
      acmeChallengeBackend = lib.mkIf cfg.acme.enable "127.0.0.1:18085";
    };
    forge.services.forgejo.settings.server.ROOT_URL = "https://${config.forge.services.forgejo.domain}${
      lib.optionalString (cfg.publicPort != 443) ":${toString cfg.publicPort}"
    }/";
    services.discourse.siteSettings.security.force_https = lib.mkForce true;
    services.discourse.siteSettings.developer.port = lib.mkForce cfg.publicPort;
    # Defaults do not replace values already stored in Discourse's database.
    systemd.services.discourse.preStart = lib.mkAfter ''
      ${config.services.discourse.package.rubyEnv}/bin/bundle exec rails runner \
        'SiteSetting.port = ${toString cfg.publicPort}; SiteSetting.force_https = true'
    '';
    services.nginx.virtualHosts.${config.forge.services.discourse.hostname} = {
      listen = [
        {
          addr = "127.0.0.1";
          port = 18081;
        }
      ];
      # Only the trusted loopback edge reaches this listener. Retain the HTTPS
      # scheme and canonical Host instead of replacing them with nginx's HTTP hop.
      locations =
        lib.genAttrs
          [
            "@discourse"
            "~ ^/uploads/short-url/"
            "~ ^/secure-media-uploads/"
            "/srv/status"
            "~ ^/uploads/"
            "~ ^/admin/backups/"
            "~ ^/(svg-sprite/|letter_avatar/|letter_avatar_proxy/|user_avatar|highlight-js|stylesheets|theme-javascripts|favicon/proxied|service-worker)"
            "/message-bus/"
          ]
          (_: {
            recommendedProxySettings = false;
            extraConfig = lib.mkAfter ''
              proxy_set_header Host ${config.forge.services.discourse.hostname}${
                lib.optionalString (cfg.publicPort != 443) ":${toString cfg.publicPort}"
              };
              proxy_set_header X-Forwarded-Proto $http_x_forwarded_proto;
              proxy_set_header X-Forwarded-For $http_x_forwarded_for;
            '';
          });
    };
    security.acme = lib.mkIf cfg.acme.enable {
      acceptTerms = cfg.acme.acceptTerms;
      defaults.email = cfg.acme.email;
      certs.${certificateName} = {
        domain = edge.forgejoDomain;
        extraDomainNames = [ edge.discourseDomain ];
        group = "haproxy";
        webroot = "/var/lib/acme/challenge";
        reloadServices = [ "haproxy.service" ];
      };
    };
    services.nginx.virtualHosts.forge-acme = lib.mkIf cfg.acme.enable {
      listen = [
        {
          addr = "127.0.0.1";
          port = 18085;
        }
      ];
      root = "/var/lib/acme/challenge";
      locations."/".tryFiles = "$uri =404";
    };
    systemd.services.haproxy = lib.mkIf cfg.acme.enable {
      # In the locked NixOS module this unit creates the initial certificate;
      # live issuance happens in the separate order-renew unit below.
      after = [ "acme-${certificateName}.service" ];
      requires = [ "acme-${certificateName}.service" ];
    };
    systemd.services."acme-order-renew-${certificateName}" = lib.mkIf cfg.acme.enable {
      after = [
        "haproxy.service"
        "nginx.service"
      ];
      wants = [
        "haproxy.service"
        "nginx.service"
      ];
    };
    assertions = [
      {
        assertion = !cfg.acme.enable || (cfg.acme.email != null && cfg.acme.acceptTerms);
        message = "Configure an ACME contact and explicitly accept the certificate authority terms before enabling live issuance.";
      }
    ];
  };
}
