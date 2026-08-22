#!/usr/bin/env python3
"""Fail if the share extension's URL scheme has drifted from the app's declaration.

`Info.plist` is what makes the system route a URL to the app, so it is the authority. The app reads
it at runtime. The share extension is a separate target and cannot, so it carries a literal, and a
mismatch shows up as the extension doing nothing at all with nothing going red. Hence this check.
"""

import pathlib
import plistlib
import re
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent


def main() -> int:
    plist = plistlib.loads((ROOT / "Nifro/Info.plist").read_bytes())

    try:
        declared = plist["CFBundleURLTypes"][0]["CFBundleURLSchemes"][0]
    except (KeyError, IndexError):
        print("Info.plist declares no URL scheme", file=sys.stderr)
        return 1

    source = (ROOT / "ShareExtension/ShareController.swift").read_text()
    match = re.search(r'components\.scheme = "([^"]+)"', source)

    if not match:
        print("ShareController.swift no longer sets components.scheme as a literal; update this check", file=sys.stderr)
        return 1

    if match.group(1) != declared:
        print(
            f"URL scheme mismatch: Info.plist says {declared!r}, "
            f"ShareController.swift says {match.group(1)!r}",
            file=sys.stderr,
        )
        return 1

    print(f"URL scheme {declared!r} matches in both places")
    return 0


if __name__ == "__main__":
    sys.exit(main())
