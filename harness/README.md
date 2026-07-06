# forge test harness (U2 · #3)

incus-based verification substrate for the `seed` deploy. Tier-3 non-product tooling —
it *exercises* the product; it is not exercised by it.

| Script | What |
| --- | --- |
| `e2e.sh <clean\|dirty> [image]` | full-deploy E2E in an incus **VM** (real kernel). **The tier-2 grading gate.** |
| `fragment.sh <name> [image]` | fast per-fragment loop in an incus **system-container**. Dev inner-loop. |
| `smoke.sh <host> [port] [repo]` | `git clone` over Forgejo git-SSH (:2222). |
| `selfcheck.sh` | negative control — proves the assertion library actually detects failure. |
| `lib/assert.sh`, `lib/incus.sh` | assertion + incus-lifecycle libraries. |

## Staging
Assertions are **staged**: each is guarded and SKIPs until the unit that produces its
target lands (spec #3). The harness is usable incrementally and graded fully once `seed`
is deployable (U5 boots → U11 k3s → U14 Forgejo).

**Invariant:** no tier-2 unit merges until its E2E assertion here exists and passes —
the gate is not bypassed by schedule.

## Substrates
- **clean** — fresh empty VM (migrate-from-zero / first-install).
- **dirty** — restored snapshot / re-run (upgrade path: reboot-persistence, idempotency, N-1).

## Fixtures & secrets
Fixtures use a **test age key + fixture SOPS files**, CI-validated against U1's schema
(#2) so they cannot drift from the real contract. Never real credentials.

## Runner
The VM E2E needs **nested KVM** → a **self-hosted KVM runner** (GitHub-hosted nested-virt
is limited; #3 RISK). The fragment loop and `selfcheck.sh` need no nested virt and always run.
