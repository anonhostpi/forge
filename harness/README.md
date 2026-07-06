# forge test harness (U2 · #3)

incus-based verification substrate for the `seed` deploy. Tier-3 non-product tooling —
it *exercises* the product; it is not exercised by it.

| Script | What |
| --- | --- |
| `e2e.sh <clean\|dirty> [image]` | full-deploy E2E in an incus **VM** (real kernel). **The tier-2 grading gate.** |
| `fragment.sh <name> [image]` | fast per-fragment loop in a system-container (applies via `setup.sh`, once U5 lands). |
| `smoke.sh <host> [port] [repo]` | `git clone` over Forgejo git-SSH (:2222). |
| `selfcheck.sh` | negative control — proves the assertion lib detects failure, incl. gate-mode teeth. |
| `validate-fixtures.sh` | checks fixture secrets against U1's schema (staged until #2 lands). |
| `lib/assert.sh`, `lib/incus.sh` | assertion + incus-lifecycle libraries. |

## Gate mode
`e2e.sh` runs in two modes:
- **dev** (default): a missing prerequisite (no incus, no `cloud-init.yml`) **SKIPs** — run it
  incrementally as units land.
- **gate** (`HARNESS_GATE=1`, set in `.github/workflows/e2e.yml`): a missing prerequisite
  **FAILS**, a run that verified nothing (all-skip) **FAILS**, and any unit named in
  **`HARNESS_REQUIRE`** whose assertion is skipped **FAILS**.

So per-unit coverage is enforced two ways: mechanically, by adding the unit's token to
`HARNESS_REQUIRE` (a staged skip for a required unit fails the gate); and by review, since
each tier-2 unit's PR must flip its own `skip` into a real assertion. A bare staged skip
only rides green while its unit is **not yet required** — the moment a unit lands, its token
joins `HARNESS_REQUIRE` and the skip can no longer false-green it.

`vm_create` sets `user.user-data` **before first boot** so the real cloud-init executes.
`dirty` re-applies the deploy on the populated box (`cloud-init clean` + restart) to exercise
idempotent replay.

## Open items (declared, not hidden)
- CI→seed:22 SSH-push deploy assertion (U4); secret scrub-on-boot assertion (U3/U4).
- `validate-fixtures.sh` validator vs U1's schema (#2).
- **`setup.sh --only <fragment>`** — `fragment.sh` imposes this selector on U5's `setup.sh`; U5 must provide it.
- **N-1 upgrade** from a prior-release golden image (needs a released image to restore).
- A **self-hosted KVM runner** for the VM E2E (`full-deploy-e2e` job gated off until then).

**Invariant:** no tier-2 unit merges until its E2E assertion here exists and passes — enforced
by `HARNESS_REQUIRE` (mechanical) + per-unit review (the skip→assert diff).

## Substrates & secrets
- **clean** — fresh VM, first-install. **dirty** — re-apply on a populated box (idempotent replay).
- Fixtures use a **test age key + fixture SOPS** (`fixtures/`), never real credentials.
