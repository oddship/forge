{ nixpkgs, pkgs, ... }:

let
  configuration =
    fixture:
    nixpkgs.lib.nixosSystem {
      system = "x86_64-linux";
      modules = [
        ../modules/base.nix
        ../modules/services
        {
          forge.services.penpot = {
            enable = true;
            localFixture = fixture;
            publicUri = if fixture then "http://penpot.localhost:8080" else "https://design.example.com";
          };
          forge.services.haproxy.enable = true;
          system.stateVersion = "24.11";
        }
      ];
    };
  local = (configuration true).config;
  production = (configuration false).config;
  containers = local.virtualisation.oci-containers.containers;
  template = builtins.head (
    nixpkgs.lib.splitString ":" (builtins.elemAt containers.penpot-frontend.volumes 1)
  );
  disabled =
    (nixpkgs.lib.nixosSystem {
      system = "x86_64-linux";
      modules = [
        ../modules/services
        { forge.services.haproxy.enable = true; }
      ];
    }).config;
  lib = nixpkgs.lib;
in
assert lib.all (name: containers.${name}.extraOptions == [ "--network=host" ]) [
  "penpot-backend"
  "penpot-exporter"
  "penpot-frontend"
];
assert lib.all (name: containers.${name}.environment.PENPOT_HTTP_SERVER_HOST == "127.0.0.1") [
  "penpot-backend"
  "penpot-exporter"
];
assert containers.penpot-backend.environmentFiles == [ "/var/lib/penpot/secrets.env" ];
assert containers.penpot-exporter.environmentFiles == containers.penpot-backend.environmentFiles;
assert containers.penpot-exporter.environment.NODE_OPTIONS == "--require=/opt/forge/loopback.cjs";
assert lib.any (
  volume: lib.hasSuffix ":/opt/forge/loopback.cjs:ro" volume
) containers.penpot-exporter.volumes;
assert !(builtins.hasAttr "PENPOT_SECRET_KEY" containers.penpot-backend.environment);
assert lib.hasInfix "host penpot penpot 127.0.0.1/32 trust"
  local.services.postgresql.authentication;
assert !(lib.hasInfix "host penpot penpot" production.services.postgresql.authentication);
assert !(builtins.hasAttr "penpot-local-init" production.systemd.services);
assert
  production.virtualisation.oci-containers.containers.penpot-backend.environmentFiles
  == [ "/run/secrets/penpot-env" ];
assert
  !(lib.hasInfix "disable-secure-session-cookies" production.virtualisation.oci-containers.containers.penpot-backend.environment.PENPOT_FLAGS);
assert local.forge.services.postgresql.databases == [ "penpot" ];
assert !(builtins.elem 6060 local.networking.firewall.allowedTCPPorts);
assert !(builtins.elem 6061 local.networking.firewall.allowedTCPPorts);
assert !(lib.hasInfix "backend penpot" disabled.services.haproxy.config);
assert lib.hasInfix "penpot.localhost:8080"
  ((configuration true).extendModules {
    modules = [ { forge.services.haproxy.additionalHostPorts = [ 8080 ]; } ];
  }).config.services.haproxy.config;
pkgs.runCommand "forge-penpot-policy" { nativeBuildInputs = [ pkgs.nodejs ]; } ''
  grep -F 'listen 127.0.0.1:18083 default_server' ${template}
  grep -F 'listen 127.0.0.1:18084;' ${template}
  grep -F 'location /ws/notifications' ${template}
  grep -F 'location /internal/assets' ${template}
  node --require ${../modules/services/penpot-exporter-loopback.cjs} -e '
    const server = require("node:net").createServer();
    server.listen(6061, () => {
      const address = server.address();
      if (address.address !== "127.0.0.1") throw new Error("Exporter listener escaped loopback");
      server.close();
    });
  '
  touch "$out"
''
