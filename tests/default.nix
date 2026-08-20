{
  logchef,
  nixpkgs,
  sopsNix,
}:

let
  pkgs = nixpkgs.legacyPackages.x86_64-linux;
  args = {
    inherit logchef nixpkgs pkgs;
    inherit sopsNix;
  };
in
{
  local-smoke = import ./local-smoke.nix args;
  local-observability-smoke = import ./observability-smoke.nix args;
  netbird-policy = import ./netbird-policy.nix args;
  zitadel-policy = import ./zitadel-policy.nix args;
  zitadel-smoke = import ./zitadel-smoke.nix args;
  secrets-policy = import ./secrets-policy.nix args;
  production-host-policy = import ./production-host-policy.nix args;
}
