# forge

A public Hetzner cloud-init that bootstraps **seed**: a single-node k3s host running **Forgejo**.

Everything provisions from an empty box. The bar is **reliably administerable and reproducible** — explicitly *not*
durable-under-load. HA, DR, TLS, and networked storage are deliberately out of scope (see [Known limits](#known-limits)).

- **Runbook** — [`docs/RUNBOOK.md`](docs/RUNBOOK.md): provision → deploy → the one manual step → verify.
- **Config reference** — [`docs/CONFIG.md`](docs/CONFIG.md): every key, and what reads it.
- **Epic** — [#1](https://github.com/anonhostpi/forge/issues/1).

## How it fits together

```
GitHub Actions (owner-gated, protected environment)
  ├─ provision.yml   renders cloud-init.yml  →  hcloud creates the box
  └─ deploy.yml      decrypts SOPS in-runner →  ssh forge-deploy@seed:22 → `sudo k3s kubectl apply -f -`
                                                        │
seed (Ubuntu 24.04)                                     │
  cloud-init → setup.sh → write_files/NN-*  ────────────┤  host: hardening, msmtp, fail2ban, auditd,
                                                        │        podman, nftables firewall, Bridge, k3s
  k3s (stock: kine/SQLite, local-path, Traefik,         │
       Klipper ServiceLB, kube-router NetworkPolicy)    │
       └─ deploy/manifests/NN-*  ←─────────────────────-┘  Namespace, Postgres, Forgejo, NetworkPolicies, backups
```

Two ordered conventions carry the system, and both are contracts rather than conveniences:

- **`write_files/NN-*`** — cloud-init fragments applied in `NN` order by `setup.sh`. Each is executable, idempotent, and
  declares a `# phase:` header.
- **`deploy/manifests/NN-*`** — k8s manifests applied in `NN` order in **one** `kubectl apply -f -` stream.
  `00-namespace.yaml` comes first because `kubectl apply` does not reorder by kind, and a namespaced object applied
  before its Namespace aborts the whole deploy. Plaintext workloads stream first, then `*.sops.yaml` secrets.

## The security model

Three decisions shape everything. Each is stated at the precision it actually holds.

### The age key never leaves CI, and no secrets ride user-data

cloud-init carries only the CI deploy *public* key. Secrets live SOPS-encrypted in-repo; CI decrypts them in-runner.
Compromising `seed` therefore leaks the box's own service credentials — never the master age key.

This is a claim about **delivery**, not about disk. The box does hold plaintext-at-rest credentials it generated or was
handed locally — notably `/etc/msmtp-bridge.pass` (`0600 root`), which is a **Bridge-generated local password**, never
the Proton account password.

### Secrets arrive by SSH-push; the apiserver is not internet-facing

`scripts/deploy.sh` loads the deploy key into `ssh-agent` from **stdin** (never a file on disk), decrypts SOPS to a
pipe, and streams plaintext into on-box `sudo k3s kubectl apply -f -` over port 22. The host firewall admits only
`22`, `2222`, `80` from the internet, so **6443 is not reachable from outside** — which is precisely *why* the
SSH-push design exists.

It is **not** globally closed: pods reach the apiserver over `cni0` and the pod CIDR, because on a single node they
must (CoreDNS, metrics-server, Forgejo all talk to it). That is an intentional tradeoff, not an oversight.

### Metadata is blocked at two layers, because either alone has a hole

| Layer | Mechanism | Covers |
|---|---|---|
| Host | nft `FORWARD` drop, pod-CIDR → `169.254.169.254` | **every** pod, including ones with no NetworkPolicy |
| k8s | NetworkPolicy `ipBlock: 0.0.0.0/0 except 169.254.169.254/32` | pods in namespace `forge` |

A pod with no NetworkPolicy is unprotected by the k8s layer; a host-firewall reconcile gap is unprotected by the host
layer. Two residuals remain, and are not papered over: **`hostNetwork` pods bypass both** (they use the host's OUTPUT
path and are exempt from NetworkPolicy), and the baseline policy is **namespace-scoped to `forge`**, so `kube-system`
workloads are protected by the **host layer alone**.

## What is actually verified

Being precise here matters more than looking finished.

**Live and green on every PR** — lint, schema, and self-test CI:

| Check | What it proves |
|---|---|
| `shellcheck`, `actionlint` | fragments, scripts, and workflows parse and avoid common shell/CI bugs |
| `config-lint` | `seed.yaml` validates against `schema.json`; no cleartext secrets; no placeholder recipient |
| `firewall-lint` | the **rendered** nftables ruleset parses (`nft -c`) — through the same renderer the box runs |
| `k8s-lint` | manifests pass `kubeconform`; no plaintext `Secret`, no inline secret-ish key |
| `render-selftest`, `setup-selftest`, `deploy-selftest` | the cloud-init renderer, fragment runner, and deploy pipeline run against fixtures — and are proven to *bite* |
| `harness/selfcheck.sh` | the assertion library itself detects failure (a negative control) |

**Not yet exercised** — the **full-deploy E2E is dormant**. `e2e.yml`'s deploy job is gated on `vars.ENABLE_FULL_E2E`
(unset by default) and a `[self-hosted, kvm]` runner, neither of which exists yet. Every tier-2 assertion — Forgejo
serving HTTP 200, the git-SSH host key surviving a pod restart, Postgres data surviving a reboot, the metadata block
dropping traffic — is **written and staged, but has never run against a real box**. `HARNESS_REQUIRE` fails closed, so
those units cannot false-green once the gate is switched on.

So: this repository is thoroughly **reviewed** and statically **checked**. It has not yet been **deployed**.

## Tiers

Verification effort is spent by cost × blast-radius, not uniformly.

- **Tier 1 — product logic.** Full gate: tests first, unit + property, formal hardening. Only
  [#36](https://github.com/anonhostpi/forge/issues/36) (the agentive summariser) qualifies, and it is not built.
- **Tier 2 — full-deploy E2E.** Deploy config, migrations, IaC. The deploy E2E *is* the test; no unit tests. Nearly
  everything here.
- **Tier 3 — non-product.** Tooling, methodology, and these docs. Review-only.

## Known limits

Stated plainly, each tracked:

- **The seed is not fully hands-off.** Proton Bridge's first login is **interactive** (account + 2FA); the image has no
  headless path. Everything else provisions autonomously — see the [runbook](docs/RUNBOOK.md).
- **msmtp's cleartext `AUTH LOGIN` over `tls off` is unverified** against the pinned Bridge. It fails safe (mail queues
  rather than being lost), but it has never been exercised. [#38](https://github.com/anonhostpi/forge/issues/38)
- **SSH host-key first-contact MITM window** — a re-provisioned box has a new host key, so the first deploy is
  trust-on-first-use. [#25](https://github.com/anonhostpi/forge/issues/25)
- **Supply chain** — the `hcloud` checksum is same-origin, and the fallback tarball is not content-addressed.
  [#24](https://github.com/anonhostpi/forge/issues/24)
- **Backups are staged, not delivered off-box**, and have never been restore-tested.
  [#32](https://github.com/anonhostpi/forge/issues/32)
- **Security kernel updates need a manual reboot** — auto-reboot is deliberately off on a bootstrap box.
  [#27](https://github.com/anonhostpi/forge/issues/27)
- **No repo-wide secret scanning** beyond the `secrets/**` contract. [#19](https://github.com/anonhostpi/forge/issues/19)
- **`hostNetwork` pods bypass both metadata layers**, and `kube-system` is covered by the host layer only (above).
