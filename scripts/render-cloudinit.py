#!/usr/bin/env python3
# see anonhostpi/forge#4
# Render U5's cloud-init.yml template with per-context escaping (spec #4 F4): shell-double-quote for the
# runcmd vars, YAML-double-quote for the pubkey scalar. No sed/envsubst (both injectable). Reads values
# from the environment; writes the rendered cloud-config to stdout.
import os, sys, re, yaml

def esc_shell_dq(v):   # safe inside a "double-quoted" shell string
    if "\n" in v:
        raise SystemExit("shell-context value contains a newline")
    return v.replace("\\", "\\\\").replace('"', '\\"').replace("$", "\\$").replace("`", "\\`")

def esc_yaml_dq(v):    # safe inside a "double-quoted" YAML scalar
    if "\n" in v:
        raise SystemExit("YAML-scalar value contains a newline")
    return v.replace("\\", "\\\\").replace('"', '\\"')

def main():
    tmpl = open("cloud-init.yml").read()
    pub = os.environ["DEPLOY_PUBKEY"]
    if "REPLACE" in pub or not pub.strip():
        raise SystemExit("DEPLOY_PUBKEY is the placeholder/empty — would provision an unreachable box (spec #4 F8)")
    ref = os.environ["REF"]
    if len(ref) != 40 or any(c not in "0123456789abcdef" for c in ref.lower()):
        raise SystemExit(f"REF must be a full 40-char SHA (spec #4 F6), got: {ref!r}")
    subst = {
        "{{DEPLOY_PUBKEY}}":  esc_yaml_dq(pub),
        "{{REPO_URL}}":       esc_shell_dq(os.environ["REPO_URL"]),
        "{{REF}}":            esc_shell_dq(ref),
        "{{TARBALL_URL}}":    esc_shell_dq(os.environ["TARBALL_URL"]),
        "{{TARBALL_SHA256}}": esc_shell_dq(os.environ["TARBALL_SHA256"]),
    }
    out = tmpl
    for k, v in subst.items():
        out = out.replace(k, v)
    m = re.search(r"\{\{[A-Z0-9_]+\}\}", out)   # placeholder grammar, so the template's `{{...}}` comment isn't a false positive
    if m:
        raise SystemExit("unsubstituted placeholder remains: " + m.group(0))
    yaml.safe_load(out)                                  # must be valid YAML
    n = len(out.encode())
    if n >= 32768:
        raise SystemExit(f"rendered cloud-init {n} bytes >= 32 KiB cap (spec #4 / U5 finding 8)")
    sys.stdout.write(out)

if __name__ == "__main__":
    main()
