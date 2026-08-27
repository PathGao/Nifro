#!/usr/bin/env python3
"""Validate every entry in sites/ against sites/schema.json.

A site entry is the lowest-barrier way to contribute here, so the failure
message has to name the file, the field, and what was expected — a contributor
who has never opened Xcode should be able to fix it from the CI log alone.
"""

import json
import pathlib
import sys

import jsonschema
import yaml

ROOT = pathlib.Path(__file__).resolve().parent.parent
SITES = ROOT / "sites"


def main() -> int:
    schema = json.loads((SITES / "schema.json").read_text())
    validator = jsonschema.Draft7Validator(schema)

    entries = sorted(SITES.glob("*.yml")) + sorted(SITES.glob("*.yaml"))
    if not entries:
        print("no site entries found in sites/", file=sys.stderr)
        return 1

    failures = 0
    ranks: dict[int, list[str]] = {}

    for path in entries:
        name = path.relative_to(ROOT)

        try:
            data = yaml.safe_load(path.read_text())
        except yaml.YAMLError as error:
            print(f"{name}: not valid YAML — {error}", file=sys.stderr)
            failures += 1
            continue

        if not isinstance(data, dict):
            print(f"{name}: expected a mapping of fields, got {type(data).__name__}", file=sys.stderr)
            failures += 1
            continue

        for error in sorted(validator.iter_errors(data), key=lambda e: list(e.path)):
            where = ".".join(str(part) for part in error.path) or "(top level)"
            print(f"{name}: {where}: {error.message}", file=sys.stderr)
            failures += 1

        rank = data.get("featured")
        if isinstance(rank, int) and not isinstance(rank, bool):
            ranks.setdefault(rank, []).append(str(name))

    # The one thing the schema cannot see, because it validates one file at a time. Two entries
    # claiming the same position leave the shipped order to whatever the sort happens to do with a
    # tie, and the first entry is the wallpaper somebody sees before they have chosen anything.
    for rank, holders in sorted(ranks.items()):
        if len(holders) > 1:
            print(f"featured: {rank} is claimed by {', '.join(holders)} — ranks must be unique", file=sys.stderr)
            failures += 1

    print(f"checked {len(entries)} site entries, {failures} problem(s)")
    return 1 if failures else 0


if __name__ == "__main__":
    sys.exit(main())
