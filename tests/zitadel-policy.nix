{ nixpkgs, pkgs, ... }:

let
  testConfig = nixpkgs.lib.nixosSystem {
    system = "x86_64-linux";
    modules = [
      ../modules/base.nix
      ../modules/services
      ({ ... }: {
        forge.services.zitadel = {
          enable = true;
          externalDomain = "id.example.com";
          masterKeyFile = "/run/keys/zitadel-master-key";
          databaseSettingsFile = "/run/keys/zitadel-database.yaml";
          bootstrapStepsFile = "/run/keys/zitadel-steps.yaml";
          backup.enable = true;
        };
        system.stateVersion = "24.11";
      })
    ];
  };
  evaluated = testConfig.config;
  zitadel = evaluated.services.zitadel;
in
pkgs.runCommand "forge-zitadel-policy" { } ''
  test "${nixpkgs.lib.boolToString zitadel.enable}" = true
  test "${zitadel.tlsMode}" = external
  test "${zitadel.settings.ExternalDomain}" = id.example.com
  test "${toString zitadel.settings.ExternalPort}" = 443
  test "${zitadel.settings.Database.postgres.Host}" = 127.0.0.1
  test "${toString zitadel.settings.Database.postgres.Port}" = 5432
  test "${toString (builtins.head zitadel.extraSettingsPaths)}" = /run/keys/zitadel-database.yaml
  test "${toString (builtins.head zitadel.extraStepsPaths)}" = /run/keys/zitadel-steps.yaml
  test "${toString evaluated.forge.services.postgresql.databases}" = zitadel
  test "${evaluated.systemd.services.zitadel.serviceConfig.User}" = zitadel
  test "${nixpkgs.lib.boolToString (builtins.hasAttr "zitadel-backup" evaluated.systemd.services)}" = true
  touch "$out"
''
