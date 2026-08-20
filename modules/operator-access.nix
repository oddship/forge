{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.forge.operatorAccess;
  authorizedKeysCommand = pkgs.writeShellScript "forge-operator-authorized-keys" ''
    set -eu

    if [ "''${1:-}" != ${lib.escapeShellArg cfg.user} ]; then
      exit 0
    fi

    if [ -r ${lib.escapeShellArg cfg.authorizedKeysFile} ]; then
      ${pkgs.coreutils}/bin/cat ${lib.escapeShellArg cfg.authorizedKeysFile}
    fi
  '';
in
{
  options.forge.operatorAccess = {
    enable = lib.mkEnableOption "declarative operator SSH access";

    user = lib.mkOption {
      type = lib.types.str;
      default = "operator";
      description = "Non-root operating-system account used for administration.";
    };

    authorizedKeysFile = lib.mkOption {
      type = lib.types.str;
      default = "/etc/forge/ssh/operator_authorized_keys";
      description = "Runtime file populated by the image or provider bootstrap with operator public keys.";
    };
  };

  config = lib.mkIf cfg.enable {
    assertions = [
      {
        assertion = lib.hasPrefix "/" cfg.authorizedKeysFile;
        message = "forge.operatorAccess.authorizedKeysFile must be an absolute runtime path.";
      }
    ];

    users.users.${cfg.user} = {
      isNormalUser = true;
      extraGroups = [ "wheel" ];
    };

    systemd.tmpfiles.rules = [
      "d ${builtins.dirOf cfg.authorizedKeysFile} 0700 root root - -"
      "d /run/forge/ssh 0755 root root - -"
    ];

    services.openssh.authorizedKeysCommand = "/run/forge/ssh/operator-authorized-keys %u";
    services.openssh.authorizedKeysCommandUser = "root";

    systemd.services.forge-operator-authorized-keys = {
      description = "Install the runtime operator SSH key lookup command";
      wantedBy = [ "sshd.service" ];
      requiredBy = [ "sshd.service" ];
      before = [ "sshd.service" ];
      path = [ pkgs.coreutils ];
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
      };
      script = ''
        install -d -o root -g root -m 0755 /run/forge/ssh
        install -o root -g root -m 0755 ${authorizedKeysCommand} /run/forge/ssh/operator-authorized-keys
      '';
    };
  };
}
