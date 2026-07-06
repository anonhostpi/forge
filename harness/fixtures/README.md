# harness fixtures (U2 · #3)

Fixture secrets for the harness — a **test age key** + **fixture SOPS files**, never real
credentials. Populated when U1 (#2) fixes the config/secret schema; `validate-fixtures.sh`
then checks these against that schema so a fixture cannot drift from the real contract.

Empty until U1 lands (declared open item — see `validate-fixtures.sh`).
