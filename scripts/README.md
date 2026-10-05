# Scripts

`penpot-smoke` probes the interactive VM's Penpot frontend, backend readiness,
and browser origin through HAProxy. Run it with `just penpot-smoke` after
`just vm-run`.

Repository scripts hold nontrivial shell used by the `justfile` or the Nix
development shell. Keep the public command interface in `just`; invoke these
scripts through `bash scripts/<name>` so executable-bit differences do not
break fresh checkouts.

Secret scripts create and verify the ignored local SOPS/age fixture. Use the
stable `just secrets-init`, `just secrets-check`, and `just test-secrets`
recipes rather than calling them directly during normal work.

`forgejo-runner-bootstrap` performs the local VM's idempotent Actions runner
registration. It stores the generated UUID and token in the VM's persistent
state directory; those credentials never enter the Nix store or repository.
