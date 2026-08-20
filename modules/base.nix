{ ... }:

{
  networking.firewall.enable = true;
  networking.firewall.allowedTCPPorts = [
    80
    443
  ];

  services.openssh.enable = true;
  services.openssh.settings = {
    PasswordAuthentication = false;
    PermitRootLogin = "no";
  };

  users.groups.forge = { };
  users.users.forge = {
    group = "forge";
    isSystemUser = true;
  };

  time.timeZone = "UTC";
}
