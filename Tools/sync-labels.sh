#!/bin/zsh
# Make the repository's labels match .github/labels.yml.
#
# Creates what is missing and updates the colour and description of what is not. It does not delete
# labels it does not know about: GitHub creates a few by default, and a label already in use on an
# issue is somebody's filed state, not ours to remove.
set -euo pipefail

cd "$(dirname "$0")/.."

repository="${1:-$(gh repo view --json nameWithOwner --jq .nameWithOwner)}"

python3 - "$repository" <<'PY'
import json, subprocess, sys, re, pathlib

repository = sys.argv[1]
text = pathlib.Path(".github/labels.yml").read_text()

# A tiny reader for the shape this file actually has, rather than a dependency on PyYAML for it.
labels = []
for block in re.split(r"\n(?=- name: )", text):
    if not block.lstrip().startswith("- name:"):
        continue
    entry = {}
    for key in ("name", "color", "description"):
        match = re.search(rf"^\s*-?\s*{key}: (.*)$", block, re.MULTILINE)
        if match:
            entry[key] = match.group(1).strip().strip('"')
    labels.append(entry)

existing = {
    label["name"]
    for label in json.loads(
        subprocess.run(
            ["gh", "label", "list", "--repo", repository, "--limit", "200", "--json", "name"],
            capture_output=True, text=True, check=True,
        ).stdout
    )
}

for label in labels:
    action = ["--force"] if label["name"] in existing else []
    subprocess.run(
        ["gh", "label", "create", label["name"], "--repo", repository,
         "--color", label["color"], "--description", label.get("description", "")] + action,
        check=True, capture_output=True,
    )
    print(f"  {'updated' if label['name'] in existing else 'created'}  {label['name']}")

print(f"{len(labels)} labels applied to {repository}")
PY
