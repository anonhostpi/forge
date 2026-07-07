#!/usr/bin/env python3
# see anonhostpi/forge#2
import sys, json
import yaml, jsonschema

root = sys.argv[1]
schema = json.load(open(f"{root}/config/schema.json"))
defs = schema["$defs"]
checks = [
    ("config/seed.yaml", "seed"),
    ("config/topology.example.yaml", "topology"),
    ("secrets/seed.example.yaml", "secrets"),
]
rc = 0
for path, d in checks:
    data = yaml.safe_load(open(f"{root}/{path}"))
    try:
        jsonschema.validate(data, defs[d])
    except jsonschema.ValidationError as e:
        print(f"  {path} !~ {d}: {e.message}", file=sys.stderr)
        rc = 1
sys.exit(rc)
