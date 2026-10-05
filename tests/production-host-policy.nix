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
  acmeConfig = nixpkgs.lib.nixosSystem {
    system = "x86_64-linux";
    modules = [
      sopsNix.nixosModules.sops
      ../hosts/hetzner-vm.nix
      {
        forge.productionIngress.acme = {
          enable = true;
          email = "operator@example.com";
          acceptTerms = true;
        };
      }
    ];
  };
  acme = acmeConfig.config;
in
pkgs.runCommand "forge-production-host-policy" { } ''
  # Build the real optional ACME closure without activating or issuing a cert.
  test -e ${acme.system.build.toplevel}
  test "${acme.security.acme.certs.forge-edge.group}" = haproxy
  test "${acme.forge.services.haproxy.acmeChallengeBackend}" = 127.0.0.1:18085
  test "${acme.forge.services.haproxy.tls.certificateFile}" = /var/lib/acme/forge-edge/full.pem
  test "${evaluated.networking.hostName}" = forge-hetzner
  test "${evaluated.fileSystems."/".device}" = /dev/disk/by-label/nixos
  test "${evaluated.boot.loader.grub.device}" = /dev/sda
  test "${nixpkgs.lib.boolToString evaluated.forge.localSecrets.enable}" = false
  test "${nixpkgs.lib.boolToString evaluated.forge.operatorAccess.enable}" = true
  test "${nixpkgs.lib.boolToString evaluated.users.users.operator.isNormalUser}" = true
  test "${evaluated.services.openssh.authorizedKeysCommandUser}" = root
  test "${evaluated.services.openssh.authorizedKeysCommand}" != none
  test "${evaluated.forge.secrets.ageKeyFile}" = /var/lib/forge/secrets/age-key.txt
  test "${nixpkgs.lib.boolToString evaluated.forge.productionSecrets.enable}" = true
  test "${nixpkgs.lib.boolToString evaluated.forge.productionIngress.enable}" = true
  test "${nixpkgs.lib.boolToString evaluated.forge.services.haproxy.tls.enable}" = true
  test "${nixpkgs.lib.boolToString evaluated.forge.services.haproxy.exposeLocalRoutes}" = false
  test "${evaluated.services.forgejo.settings.server.ROOT_URL}" = https://forge.example.com/
  test "${
    toString (builtins.head evaluated.services.nginx.virtualHosts."community.example.com".listen).port
  }" = 18081
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
