# Runbook — provisioning seed from zero

Both workflows are **owner-gated**: `workflow_dispatch` only, behind a protected `production` environment with required
reviewers. They verify that protection at runtime and abort if it is missing.

Nothing here has been executed against a real Hetzner box yet — the full-deploy E2E is dormant
(see [What is actually verified](../README.md#what-is-actually-verified)). Expect to debug the first run.

## 0. One-time setup

**Repo secrets** (Settings → Secrets → Actions):

| Secret | Used by | For |
|---|---|---|
| `HCLOUD_TOKEN` | `provision.yml`, `deploy.yml` | create the server; resolve its IP |
| `AGE_KEY` | `deploy.yml` | decrypt SOPS in-runner. **Never leaves CI.** |

**Repo environment:** create `production` with required reviewers and a default-branch deployment policy. The workflows
assert this and fail closed if it is absent.

**Keys and config:**

1. Generate an age keypair. Put the **private** key in the `AGE_KEY` secret; put the **public** key in `.sops.yaml`,
   replacing every `age1…replace` recipient.
2. Generate the CI deploy SSH keypair. Commit the **public** key to `deploy/ci_deploy.pub`; put the **private** key in
   `secrets/seed.sops.yaml` under `deploy_ssh.private`.
3. Fill `config/seed.yaml` — at minimum `mail.to` and `mail.bridge_user` (see [CONFIG.md](CONFIG.md)).
4. Fill in the values, then encrypt. **sops picks recipients by matching its *input* path against `.sops.yaml`
   `creation_rules` — a shell redirect is invisible to it.** The rules match `*.sops.yaml`, and the templates are
   `*.example.yaml`, so `sops -e template > out.sops.yaml` fails with *no matching creation rules found*. Copy to the
   final name first, then encrypt in place:
   ```sh
   cp secrets/seed.example.yaml secrets/seed.sops.yaml
   sops -e -i secrets/seed.sops.yaml

   cp deploy/manifests/postgres-secret.example.yaml deploy/manifests/postgres.sops.yaml
   cp deploy/manifests/forgejo-secret.example.yaml  deploy/manifests/forgejo.sops.yaml
   sops -e -i deploy/manifests/postgres.sops.yaml
   sops -e -i deploy/manifests/forgejo.sops.yaml
   ```
   (`sops --filename-override <final-name> -e <template>` works too.) `.sops.yaml` carries rules for
   `secrets/*.sops.yaml`, `secrets/*.{key,pem,env,json}`, `config/topology.sops.yaml`, and
   `deploy/manifests/*.sops.yaml` — **not** for `secrets/**` generally.

`config-lint` will fail the build if a placeholder recipient or a cleartext secret survives.

## 1. Provision

Run **Actions → provision → Run workflow**, approve the environment gate.

It pins `hcloud`, renders `cloud-init.yml` against the checked-out commit SHA (never a dispatch input), and creates a
`cx22` Ubuntu 24.04 server named `seed` in `nbg1`.

> Re-running **destroys and recreates** `seed`. That is safe — the box is a stateless bootstrap target whose config
> re-derives from this repo plus the deploy push. It **does** mint a new public IP and a new SSH host key.

cloud-init then clones this repo at the pinned SHA and runs `setup.sh --phase boot`, applying `write_files/NN-*` in
order. The box comes up hardened, firewalled, and running k3s. Nothing secret is on it yet.

## 2. Deploy

Run **Actions → deploy → Run workflow**, approve the gate.

CI decrypts SOPS in-runner, loads the deploy key into `ssh-agent` from stdin, and streams both the plaintext workload
manifests and the decrypted Secrets into on-box `sudo k3s kubectl apply -f -` over SSH.

Forgejo's pod will report `CreateContainerConfigError` until its Secret lands in the same apply. That is expected and
self-heals; no restart is needed.

## 3. The one manual step — Proton Bridge login

**This is the only part of the seed that is not autonomous.** Proton Bridge's first login is interactive (account +
2FA); the image exposes no headless path.

Over an SSH TTY as an admin (`forge-bridge` has `nologin`, so `su -` will not work):

```sh
BRIDGE_UID=$(id -u forge-bridge)
# The repo is cloned to /opt/forge on the box. Use the absolute path: an SSH session starts in your home directory,
# not the repo root, so a relative `config/seed.yaml` would not resolve.
BRIDGE_IMG=$(python3 -c 'import yaml; print(yaml.safe_load(open("/opt/forge/config/seed.yaml"))["images"]["proton_bridge"])')

sudo -u forge-bridge env XDG_RUNTIME_DIR=/run/user/$BRIDGE_UID \
  DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/$BRIDGE_UID/bus \
  podman run -it --rm -v forge-bridge:/root "$BRIDGE_IMG" init
```

Read the image from `seed.yaml` rather than typing a tag — the pin includes a **digest**, and a tag-only pull silently
unpins it. The later commands in this section reuse `$BRIDGE_UID`, so run them in the same SSH session.

Log in. The Bridge writes its credentials into the `forge-bridge` volume and prints a **locally generated** SMTP
password (this is *not* your Proton account password). Give it to msmtp:

```sh
printf '%s' '<bridge-generated-password>' | sudo tee /etc/msmtp-bridge.pass >/dev/null
sudo chmod 600 /etc/msmtp-bridge.pass && sudo chown root:root /etc/msmtp-bridge.pass

sudo -u forge-bridge env XDG_RUNTIME_DIR=/run/user/$BRIDGE_UID \
  DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/$BRIDGE_UID/bus \
  systemctl --user start bridge.service
```

Both environment variables are required: `forge-bridge` has `nologin`, so there is no login session to supply them, and
`systemctl --user` fails to reach the bus without `DBUS_SESSION_BUS_ADDRESS`.

Until this file exists, host mail (unattended-upgrades, fail2ban) **queues** in `/var/spool/msmtpq` rather than being
lost. A flush timer drains it once the Bridge answers.

If the first real send fails on authentication, flip `mail.bridge_starttls` in `config/seed.yaml` and re-run the
fragment — the Bridge's loopback TLS mode is version-dependent
([#38](https://github.com/anonhostpi/forge/issues/38)).

## 4. Verify

Run these **on the box**, in the same SSH session as §3. (`curl`/`ssh-keyscan` against the public IP from the box is
deliberate — it exercises the full ingress path, firewall included, rather than a loopback shortcut.)

```sh
sudo k3s kubectl -n forge get pods                     # postgres + forgejo Running
curl -s -o /dev/null -w '%{http_code}\n' http://<seed-ip>/     # 200
ssh-keyscan -p 2222 <seed-ip>                          # git-SSH answers
sudo k3s kubectl -n forge get cronjob                  # both backup jobs present
sudo msmtp --pretend root                              # mail config parses
```

Then confirm the metadata block actually holds — the assertion the E2E will make for you once it is live:

```sh
sudo k3s kubectl -n forge run probe --rm -i --restart=Never --image=busybox:1.37.0 \
  -- sh -c 'nc -w5 169.254.169.254 80'                 # must FAIL
```

## Recovering

- **Deploy failed midway.** `kubectl apply` is not atomic, but it is re-runnable. Fix and re-dispatch `deploy`.
- **Box is wedged.** Re-dispatch `provision`. It destroys and recreates. Repos and database live on the box's PVCs, so
  **take a backup first** — and note that off-box delivery is not yet wired
  ([#32](https://github.com/anonhostpi/forge/issues/32)).
- **Locked out of SSH.** There is no recovery path but re-provisioning. `30-ssh` validates with `sshd -t` before
  reloading precisely to prevent this.
