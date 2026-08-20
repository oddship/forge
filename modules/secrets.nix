{ config, lib, ... }:

let
  cfg = config.forge.secrets;
in
{
  options.forge.secrets = {
    enable = lib.mkEnableOption "the Forge sops-nix secret integration";

    ageKeyFile = lib.mkOption {
      type = lib.types.str;
      default = "/var/lib/forge/age-key.txt";
      description = "External age identity used to decrypt the configured SOPS file.";
    };

    sopsFile = lib.mkOption {
      type = lib.types.nullOr lib.types.path;
      default = null;
      description = "Encrypted SOPS file used as the default for declared secrets.";
    };

    secrets = lib.mkOption {
      type = lib.types.attrs;
      default = { };
      description = "sops-nix secret declarations passed through unchanged.";
    };
  };

  config = lib.mkIf cfg.enable {
    assertions = [
      {
        assertion = cfg.sopsFile != null;
        message = "forge.secrets.sopsFile must be set when Forge secrets are enabled.";
      }
      {
        assertion = !lib.hasPrefix builtins.storeDir cfg.ageKeyFile;
        message = "forge.secrets.ageKeyFile must remain outside the Nix store.";
      }
    ];

    sops.age.keyFile = cfg.ageKeyFile;
    sops.secrets = cfg.secrets;

    sops.defaultSopsFile = lib.mkIf (cfg.sopsFile != null) cfg.sopsFile;
  };
}
