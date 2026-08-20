# Local secrets

This directory is intentionally ignored except for this file. Initialize a
disposable local workflow with:

```sh
just secrets-init
just secrets-check
```

That creates an age identity and an encrypted SOPS fixture under `secrets/`.
The private identity is never committed and must remain outside the Nix store.

Production secret files may be committed only in encrypted form after their
recipient and recovery procedure have been reviewed. Production keys must be
kept in the deployment environment, not in this repository or its backups.
