#!/usr/bin/env python3
"""Check `Localizable.xcstrings` against what the compiler says the app displays.

The Swift compiler writes a `.stringsdata` file per source file, listing every string it recognised
as user-facing — `Text`, `String(localized:)`, `LocalizedStringResource`, `LocalizedStringKey` and
`AttributedString(localized:)`, with the file and line each came from. That is the same answer Xcode
uses to fill the catalogue, so reading it here asks the question with no regex in the middle.

What that replaces is the point. This used to be a pattern over the sources that knew about
`String(localized: "…")` and `Text("…")` and nothing else, so a string handed to any other display
sink — `NSAlert.messageText`, `addButton(withTitle:)`, a `String` parameter on one of our own views —
was invisible to it, untranslated, and passing CI. Thirteen of them were, and the two paragraphs of
the welcome dialog were among them.

It is checked in both directions, because the two failures are different:

- **In the sources, not in the catalogue** is a string that reaches the user untranslated. Xcode
  writes these into the catalogue when it builds; `xcodebuild` does not, which is why CI has to say
  so rather than assume somebody opened Xcode.
- **In the catalogue, seen by nothing** is a translation being kept in step for text no user can
  reach. `OrphanStringsTests` asks this too, by matching the key's words against the sources, and it
  cannot tell a dead key from one whose words appear inside a live one: "Reload" hid inside "Reload
  interval" and five keys from the status bar menu deleted in #21 survived every run of it. The
  compiler does not match text, so it does not have that ceiling.

Only the app target is read. The share extension is not in the `Nifro` scheme and has no strings of
its own; the package dependencies have strings that are not ours to translate.
"""

import json
import pathlib
import subprocess
import sys

CATALOGUE = pathlib.Path("Nifro/Localizable.xcstrings")

# A view with `.labelsHidden()` still writes an empty label, and an App Intents parameter summary is
# stored as a bare specifier. Neither is text anybody reads.
IGNORED = {"", "%@"}


def displayed_strings(derived_data: pathlib.Path) -> dict[str, set[str]]:
	target = derived_data / "Build/Intermediates.noindex/Nifro.build"

	if not target.is_dir():
		sys.exit(f"::error::No build output at {target}. Build the Nifro scheme first.")

	found: dict[str, set[str]] = {}

	for path in target.rglob("*.stringsdata"):
		# `.stringsdata` is a binary plist; `plutil` is how you read one without a plist library.
		raw = subprocess.run(
			["plutil", "-convert", "json", "-o", "-", str(path)],
			capture_output=True,
		).stdout

		for entries in json.loads(raw or b"{}").get("tables", {}).values():
			for entry in entries:
				key = entry["key"]

				if key in IGNORED:
					continue

				line = entry.get("location", {}).get("startingLine")
				found.setdefault(key, set()).add(f"{path.stem}.swift" + (f":{line}" if line else ""))

	if not found:
		sys.exit("::error::Read no strings at all, so this check is checking nothing.")

	return found


def main() -> int:
	derived_data = pathlib.Path(sys.argv[1] if len(sys.argv) > 1 else ".xcode-build")
	displayed = displayed_strings(derived_data)
	catalogue = set(json.loads(CATALOGUE.read_text())["strings"])

	untranslated = sorted(set(displayed) - catalogue)
	orphaned = sorted(catalogue - set(displayed))

	for key in untranslated:
		where = ", ".join(sorted(displayed[key]))
		print(f"::error::Shown to the user and not in the catalogue: {key[:100]!r} ({where})")

	for key in orphaned:
		print(f"::error::Translated and shown by nothing: {key[:100]!r}")

	if untranslated or orphaned:
		print(
			f"{len(untranslated)} string(s) missing from the catalogue, {len(orphaned)} left in it "
			"with nothing behind them. Build in Xcode to extract the first kind; delete the second."
		)
		return 1

	print(f"{len(displayed)} strings, every one of them in the catalogue and shown by something")
	return 0


if __name__ == "__main__":
	sys.exit(main())
