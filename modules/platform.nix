{ config, lib, ... }:

let
  cfg = config.forge.platform;
in
{
  imports = [
    ./base.nix
    ./services
  ];

  options.forge.platform.domain = lib.mkOption {
    type = lib.types.str;
    default = "localhost";
    description = "Base domain for the provider-independent Forge service stack.";
  };

  config = {
    forge.services.postgresql = {
      enable = lib.mkDefault true;
      databases = lib.mkDefault [ "forgejo" ];
      users = lib.mkDefault [
        {
          name = "forgejo";
          ensureDBOwnership = true;
        }
      ];
      backup.enable = lib.mkDefault true;
    };
    forge.services.redis = {
      enable = lib.mkDefault true;
      backup.enable = lib.mkDefault true;
    };
    forge.services.forgejo = {
      enable = lib.mkDefault true;
      domain = lib.mkDefault "forge.${cfg.domain}";
      ssh.enable = lib.mkDefault true;
      backup.enable = lib.mkDefault true;
    };
    forge.services.discourse = {
      enable = lib.mkDefault true;
      hostname = lib.mkDefault "community.${cfg.domain}";
      backup.enable = lib.mkDefault true;
    };
    forge.services.haproxy = {
      enable = lib.mkDefault true;
      forgejoDomain = lib.mkDefault config.forge.services.forgejo.domain;
      discourseDomain = lib.mkDefault config.forge.services.discourse.hostname;
    };
  };
}
