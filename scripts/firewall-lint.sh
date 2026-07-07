#!/usr/bin/env bash
# see anonhostpi/forge#10
# Parse-check the RENDERED forge firewall ruleset (the crux U9 could not validate at authoring — review F1). Renders
# write_files/forge-firewall.nft.tmpl from config/seed.yaml exactly as 95-firewall does, then `nft -c -f` (no apply).
# nft -c needs netlink -> run as root (the CI job uses sudo).
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"; ROOT="$(cd "$HERE/.." && pwd)"; cd "$ROOT" || exit 1
ports="$(python3 -c 'import yaml; print(", ".join(str(p) for p in yaml.safe_load(open("config/seed.yaml"))["firewall"]["allowed_input_ports"]))')"
pod="$(python3 -c 'import yaml; print(yaml.safe_load(open("config/seed.yaml"))["firewall"]["pod_cidr"])')"
svc="$(python3 -c 'import yaml; print(yaml.safe_load(open("config/seed.yaml"))["firewall"]["service_cidr"])')"
drop="$(python3 -c 'import yaml; print(str(yaml.safe_load(open("config/seed.yaml"))["firewall"]["drop_metadata"]).lower())')"
meta_rule=""; [ "$drop" = true ] && meta_rule="ip saddr ${pod} ip daddr 169.254.169.254 drop"
tmp="$(mktemp)"; trap 'rm -f "$tmp"' EXIT
sed -e "s|__POD__|${pod}|g" -e "s|__SVC__|${svc}|g" -e "s|__PORTS__|${ports}|g" -e "s|__META__|${meta_rule}|g" \
  write_files/forge-firewall.nft.tmpl > "$tmp"
nft -c -f "$tmp"
echo "firewall-lint OK — the rendered forge ruleset parses (ports=[$ports] pod=$pod svc=$svc drop=$drop)"
