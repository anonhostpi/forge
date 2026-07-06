# forge test harness (U2 · #3)

incus-based verification substrate for the `seed` deploy. Tier-3 non-product tooling —
it *exercises* the product; it is not exercised by it.

| Script | What |
| --- | --- |
| `e2e.sh <clean\|dirty> [image]` | full-deploy E2E in an incus **VM** (real kernel). **The tier-2 grading gate.** |
| `fragment.sh <name> [image]` | fast per-fragment loop in a system-container (applies via `setup.sh`, once U5 lands). |
| `smoke.sh <host> [port] [repo]` | `git clone` over Forgejo git-SSH (:2222). |
| `selfcheck.sh` | negative control — proves the assertion library actually detects failure. |
| `validate-fixtures.sh` | checks fixture secrets against U1's schema (staged until #2 lands). |
| `lib/assert.sh`, `lib/incus.sh` | assertion + incus-lifecycle libraries. |

## Gate mode (the honest part)
`e2e.sh` runs in two modes:
- **dev** (default): a missing prerequisite (no incus, no `cloud-init.yml`) **SKIPs** — you
  can run it incrementally as units land.
- **gate** (`HARNESS_GATE=1`, set in CI): a missing prerequisite **FAILS**, and a run that
  verified nothing (all-skip) **FAILS**. A skipped assertion can therefore never
  false-green the tier-2 gate.

`vm_create` sets `user.user-data` **before first boot**, so the real cloud-init executes
(not a stale first-boot state). `dirty` snapshots the deployed box and **re-applies** the
deploy (`cloud-init clean` + restart) to exercise the idempotent-replay / upgrade path.

## Staging & open items
Assertions are staged: each SKIPs until the unit that produces its target lands (U5 boots →
U11 k3s → U14 Forgejo). Explicit **open items** still to wire (declared, not hidden):
CI→seed:22 SSH-push deploy assertion (U4), secret scrub-on-boot assertion (U3/U4),
fixture-vs-U1-schema validator (#2), N-1 upgrade compat, and a **self-hosted KVM runner**
for the VM E2E (recorded lean; `.github/workflows/e2e.yml` gates the job off until then).

**Invariant:** no tier-2 unit merges until its E2E assertion here exists and passes — now
mechanized by gate mode (all-skip fails), not just prose.

## Substrates & secrets
- **clean** — fresh VM, first-install (migrate-from-zero).
- **dirty** — snapshot + re-apply on a populated system (idempotent replay; reboot-persistence).
- Fixtures use a **test age key + fixture SOPS** (`fixtures/`), never real credentials.
