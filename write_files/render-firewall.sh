#!/usr/bin/env bash
# see anonhostpi/forge#10 — the SINGLE renderer for the forge nft ruleset (emits to stdout). Called by BOTH
# write_files/95-firewall (boot) and scripts/firewall-lint.sh (CI nft -c) so the lint validates EXACTLY the ruleset the
# box boots — lint==boot by construction, not by copy-paste (review R2/1). Assumes CWD = repo root (both callers cd there).
set -euo pipefail
ports="$(python3 -c 'import yaml; print(", ".join(str(p) for p in yaml.safe_load(open("config/seed.yaml"))["firewall"]["allowed_input_ports"]))')"
pod="$(python3 -c 'import yaml; print(yaml.safe_load(open("config/seed.yaml"))["firewall"]["pod_cidr"])')"
svc="$(python3 -c 'import yaml; print(yaml.safe_load(open("config/seed.yaml"))["firewall"]["service_cidr"])')"
drop="$(python3 -c 'import yaml; print(str(yaml.safe_load(open("config/seed.yaml"))["firewall"]["drop_metadata"]).lower())')"
# metadata drop covers NON-hostNetwork pods only (hostNetwork reaches IMDS via host OUTPUT, unblocked — trusted infra; review F7). v4-only (F8).
meta_rule=""
[ "$drop" = true ] && meta_rule="ip saddr ${pod} ip daddr 169.254.169.254 drop"
sed -e "s|__POD__|${pod}|g" -e "s|__SVC__|${svc}|g" -e "s|__PORTS__|${ports}|g" -e "s|__META__|${meta_rule}|g" \
  write_files/forge-firewall.nft.tmpl
