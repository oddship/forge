{ modulesPath, ... }:
{
  imports = [
    (modulesPath + "/virtualisation/qemu-vm.nix")
    ../modules/profiles/local.nix
  ];
  networking.hostName = "forge-local";
  virtualisation.forwardPorts = [
    {
      from = "host";
      host.address = "127.0.0.1";
      host.port = 8080;
      guest.port = 80;
    }
    {
      from = "host";
      host.address = "127.0.0.1";
      host.port = 8081;
      guest.port = 8081;
    }
    {
      from = "host";
      host.address = "127.0.0.1";
      host.port = 8082;
      guest.port = 8082;
    }
    {
      from = "host";
      host.address = "127.0.0.1";
      host.port = 8083;
      guest.port = 8083;
    }
    {
      from = "host";
      host.address = "127.0.0.1";
      host.port = 2222;
      guest.port = 2222;
    }
    {
      from = "host";
      host.address = "127.0.0.1";
      host.port = 2200;
      guest.port = 22;
    }
  ];
  virtualisation.memorySize = 6144;
  # Penpot includes a JVM and a browser exporter; leave room for OCI layers.
  virtualisation.diskSize = 16384;
  virtualisation.cores = 2;

  system.stateVersion = "24.11";
}
