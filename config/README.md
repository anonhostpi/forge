# config & secrets (U1 · #2)

The single secret system + the config schema every downstream unit renders against.
**SOPS + age at rest; CI is the sole decryptor; the box never holds the age key.**

| Path | State | Holds |
| --- | --- | --- |
| `.sops.yaml` | cleartext | SOPS `creation_rules` (age recipient + which paths encrypt) |
| `config/seed.yaml` | cleartext | NON-sensitive config (hostname, version pins, image digests, chart versions) |
| `config/topology.sops.yaml` | **SOPS** | sensitive host posture (ports, firewall, fail2ban, fqdn scheme) — operator-created |
| `secrets/seed.sops.yaml` | **SOPS** | service credentials, `scope`-tagged — operator-created |
| `config/schema.json` | cleartext | JSON Schema for all three (the contract) |
| `deploy/ci_deploy.pub` | cleartext | CI deploy **public** key (public keys are not secret) |
| `*.example.yaml` | cleartext | shape templates with placeholder values (not `.sops.yaml`-matched) |

`AGE_KEY` (age private key) and `HCLOUD_TOKEN` are **GitHub repo Secrets**, referenced by name
(never `toJson`); `AGE_KEY` never leaves the runner.

## Scope tags (the U4 contract)
Every secret group is tagged `scope: ci-only | cluster`. **ci-only** (`deploy_ssh`) is NEVER
rendered into a k8s Secret or mounted in-cluster; **cluster** (`forgejo`/`postgres`/`proton`/`k3s`)
is rendered and SSH-pushed to the box by U4.

## Creating the encrypted files
```
sops -e config/topology.example.yaml > config/topology.sops.yaml   # then edit real values with `sops`
sops -e secrets/seed.example.yaml    > secrets/seed.sops.yaml
```
Set the real CI age recipient in `.sops.yaml` first. The `deploy_ssh.private` key never leaves CI;
its public half is `deploy/ci_deploy.pub` (U3 bakes it into user-data, U6 authorizes it).

## Lint (`scripts/lint-config.sh`)
Enforces: (1) every `.sops.yaml`-matched file is actually SOPS-encrypted (no plaintext secret slips
in); (2) `config/seed.yaml` carries no secret-shaped keys; (3) scope tags present; (4) shapes conform
to `config/schema.json`. `CONFIG_GATE=1` in CI fails if a validator tool is missing (dev skips it).
