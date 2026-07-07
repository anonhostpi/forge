# write_files/ — host bootstrap fragments (U5 · #6)

`setup.sh` applies the `NN-name` fragments here in **lexical (numeric-prefix) order**. Only files
matching `[0-9][0-9]-*` are fragments; this README (and any non-NN file) is ignored.

## Fragment-author contract (U6–U9)
- **Executable** — a fragment is a script. `chmod +x`, and `git update-index --chmod=+x` on this
  `core.fileMode=false` mount (the bit is otherwise dropped). A non-executable `NN-` file is an error.
- **Idempotent / re-run-safe** — the dirty-substrate replay re-runs `setup.sh`, and U4 re-runs
  `--phase full` after its SSH push, so every fragment must be safe to run twice.
- **Unique numeric prefix** — order is the full lexical name; keep `NN` prefixes unique to avoid surprise.
- **Phase header** — `# phase: boot` (needs only cleartext `config/seed.yaml`) or `# phase: full`
  (needs the U4-pushed topology/secrets; the default). `setup.sh --phase boot|full|all` filters on it.
