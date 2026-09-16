#!/usr/bin/env python3
"""Check both targets use the shared, overridable URL scheme build setting."""
import pathlib
import plistlib
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent


def main() -> int:
    app = plistlib.loads((ROOT / "Sources/Nifro/Info.plist").read_bytes())
    extension = plistlib.loads((ROOT / "Sources/ShareExtension/Info.plist").read_bytes())
    declared = app["CFBundleURLTypes"][0]["CFBundleURLSchemes"][0]
    source = (ROOT / "Sources/ShareExtension/ShareController.swift").read_text()
    if (declared != "$(NIFRO_URL_SCHEME)"
            or extension.get("NifroURLScheme") != declared
            or 'Bundle.main.object(forInfoDictionaryKey: "NifroURLScheme")' not in source):
        print("Both targets must read NIFRO_URL_SCHEME through their bundle metadata", file=sys.stderr)
        return 1
    print("Both targets use NIFRO_URL_SCHEME")
    return 0


if __name__ == "__main__":
    sys.exit(main())
