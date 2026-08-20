# Scripts

Repository scripts hold nontrivial shell used by the `justfile` or the Nix
development shell. Keep the public command interface in `just`; invoke these
scripts through `bash scripts/<name>` so executable-bit differences do not
break fresh checkouts.

Secret scripts create and verify the ignored local SOPS/age fixture. Use the
stable `just secrets-init`, `just secrets-check`, and `just test-secrets`
recipes rather than calling them directly during normal work.
