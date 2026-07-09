# deploy/manifests

`scope: cluster` SOPS-encrypted k8s manifests (`*.sops.yaml`) that `scripts/deploy.sh` decrypts in-runner and
pipes to on-box `sudo k3s kubectl apply -f -` over the SSH admin channel (forge#5).

Empty today — U13 (Postgres, #14) and U14 (Forgejo, #15) add the real manifests. `deploy.sh` treats a **missing**
dir as a misconfiguration (fails) but an **existing-but-empty** dir as intentional (nothing to deploy).

Never place `scope: ci-only` material here (e.g. the deploy SSH key) — that is CI's own credential and must never
land in an in-cluster Secret.

## Ordering contract (forge#14)

`kubectl apply -f -` streams documents **in order** and does **not** kind-reorder. So plaintext manifests apply in
**NN-prefix (glob-sorted) order** — an explicit contract, not an alphabetical accident:

- `00-namespace.yaml` — the `forge` Namespace, **always first** (a namespaced object applied before its Namespace
  errors and aborts the whole deploy).
- `10-*`, `20-*` … — workloads, in dependency order.
- `*.sops.yaml` — SOPS-encrypted Secrets, streamed **last** (a pod referencing a Secret retries until it lands).
- `*.example.yaml` — templates; excluded from the deploy stream and from k8s-lint.

**Never** put a `kind: Secret` in a plaintext `*.yaml` — `scripts/k8s-lint.sh` fails the build.
