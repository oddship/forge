{
  config,
  lib,
  ...
}:

let
  cfg = config.forge.services.mailpit;
in
{
  options.forge.services.mailpit = {
    enable = lib.mkEnableOption "the private, non-delivering Forge Mailpit instance";

    listen = lib.mkOption {
      type = lib.types.str;
      default = "127.0.0.1:8025";
      description = "HTTP address for the Mailpit web interface.";
    };

    smtp = lib.mkOption {
      type = lib.types.str;
      default = "127.0.0.1:1025";
      description = "SMTP address used by local services to capture mail.";
    };

    maxMessages = lib.mkOption {
      type = lib.types.ints.unsigned;
      default = 5000;
      description = "Maximum number of captured messages retained by Mailpit.";
    };
  };

  config = lib.mkIf cfg.enable {
    services.mailpit.instances.forge = {
      database = "mailpit.db";
      listen = cfg.listen;
      max = cfg.maxMessages;
      smtp = cfg.smtp;
    };
  };
}
