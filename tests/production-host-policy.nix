{
  nixpkgs,
  pkgs,
  sopsNix,
  ...
}:

let
  testConfig = nixpkgs.lib.nixosSystem {
    system = "x86_64-linux";
    modules = [
      sopsNix.nixosModules.sops
      ../hosts/hetzner-vm.nix
      ../modules/local-secrets.nix
      ../modules/secrets.nix
    ];
  };
  evaluated = testConfig.config;
in
pkgs.runCommand "forge-production-host-policy" { } ''
  test "${evaluated.networking.hostName}" = forge-hetzner
  test "${evaluated.fileSystems."/".device}" = /dev/disk/by-label/nixos
  test "${evaluated.boot.loader.grub.device}" = /dev/sda
  test "${nixpkgs.lib.boolToString evaluated.forge.localSecrets.enable}" = false
  test "${nixpkgs.lib.boolToString evaluated.forge.operatorAccess.enable}" = true
  test "${nixpkgs.lib.boolToString evaluated.users.users.operator.isNormalUser}" = true
  test "${evaluated.services.openssh.authorizedKeysCommandUser}" = root
  test "${evaluated.services.openssh.authorizedKeysCommand}" != none
  test "${evaluated.forge.secrets.ageKeyFile}" = /run/forge/secrets/age-key.txt
  test "${evaluated.sops.secrets.discourse-secret-key-base.owner}" = discourse
  test "${evaluated.sops.secrets.discourse-secret-key-base.mode}" = 0400
  test "${evaluated.sops.secrets.forgejo-mailer-password.owner}" = forgejo
  test "${evaluated.sops.secrets.forgejo-admin-password.owner}" = forgejo
  test "${evaluated.sops.secrets.forgejo-admin-password.mode}" = 0400
  test "${evaluated.sops.secrets.discourse-admin-password.owner}" = discourse
  test "${evaluated.sops.secrets.discourse-admin-password.mode}" = 0400
  test "${evaluated.forge.services.forgejo.admin.passwordFile}" = /run/secrets/forgejo-admin-password
  test "${evaluated.forge.services.discourse.admin.passwordFile}" = /run/secrets/discourse-admin-password
  test "${nixpkgs.lib.boolToString evaluated.forge.services.haproxy.enable}" = true
  test "${nixpkgs.lib.boolToString evaluated.forge.services.netbird.enable}" = false
  test "${nixpkgs.lib.boolToString evaluated.forge.services.zitadel.enable}" = false
  test "${nixpkgs.lib.boolToString evaluated.forge.services.penpot.enable}" = false
  test "${nixpkgs.lib.boolToString evaluated.services.forgejo.dump.enable}" = true
  test "${nixpkgs.lib.boolToString evaluated.services.postgresqlBackup.enable}" = true
  test "${evaluated.systemd.services.discourse-backup.description}" = "Backup Discourse data"
  touch "$out"
''
