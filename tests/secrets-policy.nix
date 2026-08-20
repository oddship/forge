{
  nixpkgs,
  pkgs,
  sopsNix,
  ...
}:

let
  fixture = pkgs.writeText "forge-sops-policy-fixture.yaml" "placeholder: value\n";
  testConfig = nixpkgs.lib.nixosSystem {
    system = "x86_64-linux";
    modules = [
      sopsNix.nixosModules.sops
      ../modules/secrets.nix
      ({ ... }: {
        forge.secrets = {
          enable = true;
          ageKeyFile = "/var/lib/forge/age-key.txt";
          sopsFile = fixture;
          secrets."discourse-secret-key-base" = {
            key = "discourse-secret-key-base";
            owner = "root";
            mode = "0400";
          };
        };
        system.stateVersion = "24.11";
      })
    ];
  };
  evaluated = testConfig.config;
in
pkgs.runCommand "forge-secrets-policy" { } ''
  test "${evaluated.sops.age.keyFile}" = /var/lib/forge/age-key.txt
  test "${evaluated.sops.defaultSopsFile}" = ${fixture}
  test "${evaluated.sops.secrets.discourse-secret-key-base.path}" = /run/secrets/discourse-secret-key-base
  test "${evaluated.sops.secrets.discourse-secret-key-base.mode}" = 0400
  test "${
    nixpkgs.lib.boolToString (builtins.match ".*nix/store.*" evaluated.sops.age.keyFile == null)
  }" = true
  touch "$out"
''
