{ pkgs }:

pkgs.mkShell {
  packages = with pkgs; [
    age
    git
    jq
    just
    nixfmt
    opentofu
    pre-commit
    sops
    shellcheck
    yamllint
  ];

  shellHook = ''
    bash ${./scripts/dev-shell-message}
  '';
}
