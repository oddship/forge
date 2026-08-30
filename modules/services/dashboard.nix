{
  config,
  lib,
  ...
}:

let
  cfg = config.forge.services.dashboard;
in
{
  options.forge.services.dashboard = {
    enable = lib.mkEnableOption "the Forge service dashboard";

    listenPort = lib.mkOption {
      type = lib.types.port;
      default = 18082;
      description = "Local HTTP port for the dashboard service.";
    };

    allowedHosts = lib.mkOption {
      type = lib.types.str;
      default = "dashboard.localhost,dashboard.localhost:8080,localhost:18082,127.0.0.1:18082";
      description = "Comma-separated Host values accepted by Homepage.";
    };
  };

  config = lib.mkIf cfg.enable {
    services.homepage-dashboard = {
      enable = true;
      listenPort = cfg.listenPort;
      allowedHosts = cfg.allowedHosts;
      settings = {
        title = "Forge";
        theme = "dark";
        color = "slate";
        headerStyle = "clean";
      };
      services = [
        {
          Core = [
            {
              Forgejo = {
                href = "http://forge.localhost:8080";
                description = "Source control and CI";
              };
            }
            {
              Discourse = {
                href = "http://discourse.localhost:8080";
                description = "Community discussion";
              };
            }
            {
              Vaultwarden = {
                href = "http://vaultwarden.localhost:8080";
                description = "Passwords and passkeys";
              };
            }
          ];
        }
        {
          Operations = [
            {
              Mailpit = {
                href = "http://mailpit.localhost:8080";
                description = "Captured development mail";
              };
            }
          ];
        }
      ];
    };
  };
}
