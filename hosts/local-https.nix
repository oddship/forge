{ modulesPath, ... }:
{
  imports = [
    (modulesPath + "/virtualisation/qemu-vm.nix")
    ../modules/profiles/local-https.nix
  ];
  networking.hostName = "forge-local-https";
  virtualisation = {
    memorySize = 4096;
    diskSize = 8192;
    cores = 2;
    forwardPorts = [
      {
        from = "host";
        host.address = "127.0.0.1";
        host.port = 8443;
        guest.port = 443;
      }
      {
        from = "host";
        host.address = "127.0.0.1";
        host.port = 8084;
        guest.port = 80;
      }
    ];
  };
  system.stateVersion = "24.11";
}
