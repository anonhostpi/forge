# Config reference

Where a value's *mechanism* matters, the authoritative explanation is the inline comment beside it. This page is a map:
**what each key is for, and which unit reads it.** It does not restate the code.

## `config/seed.yaml` — non-sensitive, cleartext

The box **cannot decrypt SOPS** (the age key stays in CI), so anything a fragment needs at boot must live here in
cleartext. Nothing secret belongs in this file; `config-lint` enforces its shape against `config/schema.json`.

**Read vs mirrored.** Only the fragments load this file at boot. The k8s manifests are applied as plaintext with **no
render step**, so a few keys are *duplicated by hand* into a manifest rather than read from here. Those rows say
**mirrored**: editing `seed.yaml` alone will **not** change the cluster — you must edit the manifest too.

| Key | Purpose | Consumer |
|---|---|---|
| `hostname` | the box's hostname | **read by** `write_files/50-network` |
| `k3s.version` | **the** pin. Reproducible installs; a moving channel would silently upgrade the cluster on re-provision | **read by** `write_files/99-k3s` |
| `k3s.channel` | documented fallback only — `version` is what installs | — |
| `postgres.{host,port,name,user}` | connection coordinates Forgejo is configured with (passwords are *not* here) | **mirrored** in `deploy/manifests/30-forgejo.yaml` (hardcoded; keep in sync) |
| `images.proton_bridge` | Bridge image, pinned by **tag + digest** | **read by** `write_files/97-bridge` |
| `charts.forgejo` | Forgejo Helm chart version | **mirrored** in `deploy/manifests/30-forgejo.yaml` (hardcoded; keep in sync) |
| `mail.to` | operator recipient for host mail. **Set a real deliverable address.** | **read by** `write_files/55-msmtp` |
| `mail.bridge_smtp_port` | the loopback port the Bridge publishes and msmtp relays to | **read by** `55-msmtp`, `97-bridge` |
| `mail.bridge_user` | the Proton address msmtp authenticates as, and the envelope sender. An address, not a secret. | **read by** `write_files/55-msmtp` |
| `mail.bridge_starttls` | the Bridge's loopback TLS mode is **version-dependent**; see the comment beside it | **read by** `write_files/55-msmtp` |
| `firewall.allowed_input_ports` | the only ports admitted from the internet | **read by** `write_files/render-firewall.sh` |
| `firewall.{pod_cidr,service_cidr}` | cluster-internal sources the host firewall must accept, or pods cannot reach the apiserver | **read by** `write_files/render-firewall.sh` |
| `firewall.drop_metadata` | toggles the host-layer IMDS drop | **read by** `write_files/render-firewall.sh` |

The complete set of `seed.yaml` readers is `50-network`, `55-msmtp`, `97-bridge`, `99-k3s`, and `render-firewall.sh`.
Nothing else loads it.

## `secrets/` — SOPS-encrypted

`secrets/seed.example.yaml` is a committed **template** with placeholder values. The real file is
`secrets/seed.sops.yaml`, encrypted per `.sops.yaml`. Only CI decrypts it.

Each block carries a `scope`:

- **`ci-only`** — CI's own credential. It must **never** be rendered into an in-cluster Secret.
- **`cluster`** — pushed into the cluster by `deploy.yml`.

| Block | Scope | Purpose |
|---|---|---|
| `deploy_ssh` | `ci-only` | the private key CI authenticates to `forge-deploy@seed:22` with |
| `postgres.{app_password,superuser_password}` | `cluster` | Postgres credentials. Forgejo authenticates with `app_password`; `superuser_password` is reserved for a future role split |
| `forgejo.*` | `cluster` | admin credentials, `secret_key`, `internal_token`, mailer password |
| `k3s.token` | `cluster` | **not consumed.** Single-node k3s auto-generates its node token, and a secret cannot reach the box at boot anyway. Reserved for a future multi-node join |
| `proton.{username,bridge_password}` | — | **not an input.** The Bridge *generates* these at interactive init and stores them in its own volume. Retained as operator reference only; deliberately **not** schema-required |

## `deploy/manifests/*.sops.yaml` — the k8s Secrets

`*-secret.example.yaml` files are committed **templates**; the operator encrypts them to `*.sops.yaml`. They are the
only place a `kind: Secret` may exist — `k8s-lint` fails the build on a plaintext Secret, or on an inline secret-ish
key smuggled into a Helm `valuesContent`.

Two names are load-bearing:

- Forgejo's admin Secret must expose keys named exactly **`username`** and **`password`** — the chart reads those
  verbatim, and any other name makes admin creation silently no-op.
- Forgejo reads Postgres's password from the **`forgejo-postgres`** Secret's `app_password` key.

## `config/topology.sops.yaml`

Encrypted host posture (`ssh`, `fail2ban`, `network`). The host **firewall** knobs deliberately do *not* live here —
they moved to cleartext `seed.yaml` because the box cannot decrypt SOPS at boot, and ports plus a pod CIDR are
defense-in-depth, not obscurity.
