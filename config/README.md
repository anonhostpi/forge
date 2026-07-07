# config & secrets (U1 · #2)

The single secret system + the config schema every downstream unit renders against.
**SOPS + age at rest; CI is the sole decryptor; the box never holds the age key.**

| Path | State | Holds |
| --- | --- | --- |
| `.sops.yaml` | cleartext | SOPS `creation_rules` (age recipient + which paths encrypt) |
| `config/seed.yaml` | cleartext | NON-sensitive config (hostname, version pins, image digest, chart version, postgres coords) |
| `config/topology.sops.yaml` | **SOPS** | sensitive host posture (ports, firewall, fail2ban, fqdn) — operator-created |
| `secrets/seed.sops.yaml` | **SOPS** | service credentials, `scope`-keyed — operator-created |
| `config/schema.json` | cleartext | JSON Schema for all three (the contract) |
| `deploy/ci_deploy.pub` | cleartext | CI deploy **public** key |
| `*.example.yaml` | cleartext | shape templates (placeholder values) |

`AGE_KEY` + `HCLOUD_TOKEN` are **GitHub repo Secrets** (by name, never `toJson`); `AGE_KEY` never leaves the runner.

## Scope (the U4 contract) — a DATA key, not a comment
Every secret group carries `scope: ci-only | cluster` as a **real key** — comments are invisible to
`yaml.safe_load` (which U4 uses to filter). **ci-only** (`deploy_ssh`) is NEVER rendered into a k8s
Secret / mounted in-cluster; **cluster** (`forgejo`/`postgres`/`proton`/`k3s`) is rendered and SSH-pushed by U4.

## Creating the encrypted files
Set the real CI age recipient in `.sops.yaml` first, then:
```
sops -e config/topology.example.yaml > config/topology.sops.yaml
sops -e secrets/seed.example.yaml    > secrets/seed.sops.yaml
```
`deploy_ssh.private` never leaves CI; its public half is `deploy/ci_deploy.pub` (U3 bakes it into user-data, U6 authorizes it).

## Lint (`scripts/config-lint.sh`)
Coverage is keyed to **location, not filename**: every non-`*.example.yaml` file in the secret area
(`secrets/**`, `config/topology*`) must pass **`sops --verify`** — a misnamed plaintext secret
(`secrets/seed.yaml`) cannot evade it. Also enforced: no secret-shaped key in **any** cleartext config,
`scope` present on every group, shapes conform to `config/schema.json`, and the placeholder recipient is
rejected once real secrets exist. `CONFIG_GATE=1` in CI fails on a missing tool (`sops`/validator).
`scripts/config-lint-selftest.sh` proves the lint rejects a planted plaintext secret — run in CI so it can't rot broken.
