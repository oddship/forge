{ nixpkgs, pkgs, ... }:

let
  testConfig = nixpkgs.lib.nixosSystem {
    system = "x86_64-linux";
    modules = [
      ../modules/base.nix
      ../modules/services
      ({ lib, ... }: {
        forge.services.netbird = {
          enable = true;
          setupKeyFile = "/run/keys/netbird-setup-key";
          privateTCPPorts = [
            3001
            8125
            9090
          ];
        };
        networking.firewall.allowedTCPPorts = lib.mkForce [
          80
          443
        ];
        system.stateVersion = "24.11";
      })
    ];
  };
  evaluated = testConfig.config;
  privatePorts = evaluated.networking.firewall.interfaces.wt0.allowedTCPPorts;
  globalPorts = evaluated.networking.firewall.allowedTCPPorts;
in
pkgs.runCommand "forge-netbird-policy" { } ''
  test "${nixpkgs.lib.boolToString evaluated.services.netbird.clients.default.login.enable}" = true
  test "${evaluated.services.netbird.clients.default.login.setupKeyFile}" = /run/keys/netbird-setup-key
  test "${nixpkgs.lib.boolToString (builtins.elem 3001 privatePorts)}" = true
  test "${nixpkgs.lib.boolToString (builtins.elem 8125 privatePorts)}" = true
  test "${nixpkgs.lib.boolToString (builtins.elem 9090 privatePorts)}" = true
  test "${nixpkgs.lib.boolToString (builtins.elem 3001 globalPorts)}" = false
  test "${nixpkgs.lib.boolToString (builtins.elem 8125 globalPorts)}" = false
  test "${nixpkgs.lib.boolToString (builtins.elem 9090 globalPorts)}" = false
  touch "$out"
''
