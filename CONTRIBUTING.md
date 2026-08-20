# Contributing

Thanks for helping build Forge. Start with [`README.md`](./README.md) and [`AGENTS.md`](./AGENTS.md) for the project shape and operating rules.

## Local workflow

Enter the flake development shell and run the standard checks:

```sh
nix develop
just check
just install-hooks
```

The pre-commit hook runs the fast `just check` before each commit. Run `just validate` for full flake and infrastructure validation, or `just hooks` to execute the pre-commit hook against every tracked file after changing repository-wide configuration.

Keep changes focused and explain infrastructure impact. Changes involving data, networking, authentication, or storage should include a rollback or recovery note and should not rely on undocumented manual steps.

## Conventional Commits

Commit messages follow this form:

```text
type(scope): imperative summary
```

Use a lower-case type such as `feat`, `fix`, `docs`, `chore`, `refactor`, `test`, or `ci`. Examples:

```text
feat(infra): add Hetzner firewall rules
fix(backup): report failed uploads
docs: document Object Storage state bootstrap
```

Use the body for context, operational impact, migrations, and rollback instructions. Keep unrelated changes in separate commits.

## Safety

Do not commit secrets, private keys, OpenTofu state, `.tfvars` files containing secrets, or production-generated configuration. Review plans carefully before applying changes. A backup feature is not complete until its restore path has been tested or the limitation is clearly documented.
