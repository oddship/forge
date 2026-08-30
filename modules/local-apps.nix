{
  config,
  lib,
  ...
}:

let
  cfg = config.forge.localApps;
in
{
  options.forge.localApps = {
    enable = lib.mkEnableOption "the disposable local dashboard and password services";
  };

  config = lib.mkIf cfg.enable {
    # This profile is imported only by the local VM and its isolated smoke
    # test. Production hosts do not get these services by inheritance.
    forge.services.dashboard.enable = true;
    forge.services.vaultwarden = {
      enable = true;
      # Local account creation is useful for exercising the disposable UI.
      # Production must explicitly disable sign-ups and provide recovery
      # credentials before accepting users.
      signupsAllowed = true;
      backup.enable = true;
    };
  };
}
