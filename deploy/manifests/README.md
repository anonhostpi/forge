# deploy/manifests

`scope: cluster` SOPS-encrypted k8s manifests (`*.sops.yaml`) that `scripts/deploy.sh` decrypts in-runner and
pipes to on-box `sudo k3s kubectl apply -f -` over the SSH admin channel (forge#5).

Empty today — U13 (Postgres, #14) and U14 (Forgejo, #15) add the real manifests. `deploy.sh` treats a **missing**
dir as a misconfiguration (fails) but an **existing-but-empty** dir as intentional (nothing to deploy).

Never place `scope: ci-only` material here (e.g. the deploy SSH key) — that is CI's own credential and must never
land in an in-cluster Secret.
