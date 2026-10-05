set shell := ["bash", "-euo", "pipefail", "-c"]

default: check

# Format all supported files in place.
fmt:
    find . -type f -name '*.nix' -not -path './.git/*' -exec nixfmt {} +
    bash scripts/tofu-format format

# Check formatting without changing files.
fmt-check:
    find . -type f -name '*.nix' -not -path './.git/*' -exec nixfmt --check {} +
    bash scripts/tofu-format check

# Run a fast syntax, formatting, and shell-script check.
check: fmt-check syntax-check shell-check

# Parse the local Nix expression without evaluating all flake outputs.
syntax-check:
    nix-instantiate --parse flake.nix >/dev/null

# Check repository shell scripts with ShellCheck.
shell-check:
    shellcheck scripts/dev-shell-message scripts/tofu-format scripts/tofu-validate scripts/tofu-workflow scripts/build-checks scripts/vm-stop scripts/forgejo-runner-bootstrap scripts/penpot-smoke

# Validate real provider schemas without connecting to cloud accounts.
infra-validate:
    bash scripts/tofu-validate

# Initialize the isolated one-time Object Storage bootstrap.
infra-bootstrap-init:
    bash scripts/tofu-workflow bootstrap init

# Review the real bucket bootstrap with operator-supplied environment inputs.
infra-bootstrap-plan:
    bash scripts/tofu-workflow bootstrap plan

# Initialize the cloud root against an existing remote state bucket.
infra-init backend:
    bash scripts/tofu-workflow hetzner init {{quote(backend)}}

# Review cloud provisioning; applying remains a separately authorized action.
infra-plan:
    bash scripts/tofu-workflow hetzner plan

# Apply only a saved plan that the operator has reviewed and authorized.
infra-apply root:
    bash scripts/tofu-workflow {{quote(root)}} apply

# Validate the flake and any OpenTofu configuration that has been added.
validate:
    nix flake check
    bash scripts/tofu-validate

# Build the local NixOS VM target.
vm-build:
    nix build .#nixosConfigurations.local-vm.config.system.build.vm

# Build and run the local application VM with a serial console.
vm-run:
    nix build .#nixosConfigurations.local-vm.config.system.build.vm
    QEMU_KERNEL_PARAMS="console=ttyS0" ./result/bin/run-forge-local-vm -nographic

# Build and run the local observability VM with a serial console.
observability-run:
    nix build .#nixosConfigurations.local-observability.config.system.build.vm -o local-observability-result
    QEMU_KERNEL_PARAMS="console=ttyS0" ./local-observability-result/bin/run-forge-observability-vm -nographic

# Stop only Forge-named local QEMU VMs, if they are running.
vm-stop:
    bash scripts/vm-stop

# Evaluate the production host without deploying it.
host-build target="hetzner-vm":
    nix build .#nixosConfigurations.{{target}}.config.system.build.toplevel

# Run the local NixOS smoke test.
vm-test: test-local

# Run the local application and Forgejo Actions smoke test.
test-local:
    bash scripts/build-checks local

# Run the observability smoke test.
test-observability:
    bash scripts/build-checks observability

# Run the NetBird firewall policy check.
test-network:
    bash scripts/build-checks network

# Run the ZITADEL policy and restore smoke tests.
test-identity:
    bash scripts/build-checks identity

# Run the production host secret and boot-boundary policy check.
test-host:
    bash scripts/build-checks production-host

# Exercise production HTTPS and persistent SOPS secrets in a real local VM.
test-https:
    bash scripts/build-checks https

# Run a local rehearsal of the provider-independent production profile.
https-run:
    nix build .#nixosConfigurations.local-https.config.system.build.vm -o local-https-result
    QEMU_KERNEL_PARAMS="console=ttyS0" ./local-https-result/bin/run-forge-local-https-vm -nographic

# Check Penpot's credential, listener, proxy, and production boundaries.
test-penpot:
    bash scripts/build-checks penpot

# Probe Penpot in an already running interactive local VM.
penpot-smoke:
    bash scripts/penpot-smoke

# Run the local SOPS/age secret round-trip and policy check.
test-secrets:
    bash scripts/secrets-smoke
    bash scripts/build-checks secrets

# Build every extracted flake check.
test:
    bash scripts/build-checks all
    bash scripts/secrets-smoke

# Run fast checks plus full validation.
ci: check validate test

# Install the repository's Git pre-commit hook.
install-hooks:
    pre-commit install

# Run pre-commit against every tracked file.
hooks:
    pre-commit run --all-files

# Generate an ignored local age identity and encrypted fixture.
secrets-init:
    bash scripts/secrets-init

# Decrypt and verify the ignored local secret fixture.
secrets-check:
    bash scripts/secrets-check

# Enter the flake development environment.
dev:
    nix develop
