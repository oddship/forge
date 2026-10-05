{ ... }:
{
  imports = [ ../modules/profiles/production.nix ];
  networking.hostName = "forge-hetzner";
  # Provider bootstrap must prepare an ext4 root labelled nixos.
  fileSystems."/" = {
    device = "/dev/disk/by-label/nixos";
    fsType = "ext4";
  };
  boot.loader.grub.device = "/dev/sda";
  system.stateVersion = "24.11";
}
