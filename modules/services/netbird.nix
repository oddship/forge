{ config, lib, ... }:

let
  cfg = config.forge.services.netbird;
in
{
  options.forge.services.netbird = {
    enable = lib.mkEnableOption "the Forge NetBird private-access client";

    setupKeyFile = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      description = "External runtime file containing the NetBird setup key.";
    };

    setupKeyDependencies = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ ];
      description = "Systemd units that must provide setupKeyFile before NetBird login.";
    };

    interface = lib.mkOption {
      type = lib.types.str;
      default = "wt0";
      description = "WireGuard interface managed by NetBird.";
    };

    port = lib.mkOption {
      type = lib.types.port;
      default = 51820;
      description = "UDP port used for direct NetBird peer traffic.";
    };

    autoStart = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Start and connect the NetBird client during boot.";
    };

    openFirewall = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Allow direct peer traffic to the NetBird UDP port.";
    };

    privateTCPPorts = lib.mkOption {
      type = lib.types.listOf lib.types.port;
      default = [ ];
      description = "TCP ports allowed only on the NetBird interface.";
    };

    useRoutingFeatures = lib.mkOption {
      type = lib.types.enum [
        "none"
        "client"
        "server"
        "both"
      ];
      default = "none";
      description = "NetBird routing features; keep disabled unless this host is a routed peer.";
    };
  };

  config = lib.mkIf cfg.enable {
    assertions = [
      {
        assertion = cfg.setupKeyFile != null;
        message = "forge.services.netbird.setupKeyFile is required when NetBird is enabled.";
      }
      {
        assertion = cfg.setupKeyFile == null || !lib.hasPrefix builtins.storeDir cfg.setupKeyFile;
        message = "forge.services.netbird.setupKeyFile must not point into the Nix store.";
      }
      {
        assertion = builtins.match "[A-Za-z0-9_.-]+" cfg.interface != null;
        message = "forge.services.netbird.interface must be a valid interface name.";
      }
    ];

    services.netbird = {
      useRoutingFeatures = cfg.useRoutingFeatures;
      clients.default = {
        name = "netbird";
        interface = cfg.interface;
        port = cfg.port;
        autoStart = cfg.autoStart;
        hardened = true;
        openFirewall = cfg.openFirewall;
        login = {
          enable = true;
          setupKeyFile = cfg.setupKeyFile;
          systemdDependencies = cfg.setupKeyDependencies;
        };
      };
    };

    networking.firewall.interfaces.${cfg.interface}.allowedTCPPorts = cfg.privateTCPPorts;
  };
}
