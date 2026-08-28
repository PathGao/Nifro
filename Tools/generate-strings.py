#!/usr/bin/env python3
"""Writes Nifro/Support/Strings.generated.swift from Localizable.xcstrings.

The catalogue stays the source of truth for the text; this turns it into Swift so
that a missing translation is a compile error rather than a CI check, and so that
changing language does not need the process restarted.

Field names are derived from the English text and nothing else. That is the whole
reason this is a script: a name chosen by hand for 271 strings is 271 chances to
point a field at the wrong sentence, and nothing downstream would notice — it
compiles, and it ships the wrong words. Derived, the mapping is reproducible, and
`StringsMigrationTests` asserts every field still carries the English it was made
from.
"""
import json, pathlib, re, sys

ROOT = pathlib.Path(__file__).resolve().parent.parent
CATALOGUE = ROOT / "Nifro/Localizable.xcstrings"
OUT = ROOT / "Nifro/Support/Strings.generated.swift"

# Swift keywords a field name must not collide with.
RESERVED = {
    "as", "in", "is", "for", "if", "else", "let", "var", "func", "class", "struct",
    "enum", "case", "self", "default", "return", "where", "while", "do", "try",
    "catch", "throw", "true", "false", "nil", "import", "static", "public", "open",
    "internal", "private", "operator", "protocol", "extension", "init", "deinit",
    "subscript", "typealias", "guard", "repeat", "switch", "break", "continue", "any",
}

# `%%` first, so an escaped percent is never read as the start of a specifier.
TOKEN = re.compile(r"%%|%(\d+)\$?(?:ll)?[@aAdDefgGiousxX]|%(?:ll)?[@aAdDefgGiousxX]")
SPECIFIER = re.compile(r"%(?:\d+\$)?(?:ll)?[@aAdDefgGiousxX]")

# Two strings that are the same words in different capitalisation, which macOS
# distinguishes on purpose: title case names a control or a command, sentence case
# is what gets spoken or described. The derived name cannot see that difference, so
# these two say what they are for instead.
#
# A collision that is not in here stops the run, and that is the point — it asks for
# a decision while somebody still knows why the two strings differ.
NAMES = {
    "Add website": "addWebsiteAccessibilityAction",
    "Reload website": "reloadWebsiteShortcutDescription",
    # Every word in this one is a format specifier: "3× at 40%, 60%".
    "%@× at %lld%%, %lld%%": "zoomSummary",
}

# Trailing punctuation macOS gives a meaning to, and the suffix that keeps it in the
# field name. A rule rather than more entries in the table above, because it is the
# rule the next string somebody adds will follow too.
SUFFIXES = {
    "…": "Ellipsis",   # Pressing this asks something further before it acts.
    "?": "Question",   # The title of the sheet doing the asking.
}


def field_name(text: str) -> str:
    """A camelCase identifier from the first words of the English text.

    Long enough to stay readable at the call site and to keep collisions rare;
    collisions are not resolved by adding a number, they are reported and stop the
    run, because a silently disambiguated name is exactly the kind of mapping
    nobody re-reads.
    """
    if text in NAMES:
        return NAMES[text]

    suffix = SUFFIXES.get(text.rstrip()[-1:], "")
    cleaned = SPECIFIER.sub(" ", text)
    words = re.findall(r"[A-Za-z0-9]+", cleaned)[:7]
    if not words:
        raise SystemExit(f"no usable words in key: {text!r}")

    name = words[0].lower() + "".join(w.capitalize() for w in words[1:]) + suffix
    if name[0].isdigit():
        name = "n" + name
    return name + "_" if name in RESERVED else name


def swift_literal(text: str) -> str:
    escaped = (
        text.replace("\\", "\\\\")
        .replace('"', '\\"')
        .replace("\n", "\\n")
        .replace("\t", "\\t")
    )
    return f'"{escaped}"'


def parameters(text: str):
    """One `String` parameter per format specifier, in order."""
    return SPECIFIER.findall(text)


def english(entry, key):
    """The English text, which is not always the key.

    A catalogue entry can carry an `en` unit that differs from its key — the
    positional forms Xcode writes, `%1$@` where the key has `%@`. Reading the key
    would put the wrong text in the English struct, and nothing downstream would
    say so.
    """
    unit = entry.get("localizations", {}).get("en", {}).get("stringUnit")
    return unit["value"] if unit else key


def main() -> int:
    catalogue = json.loads(CATALOGUE.read_text())
    entries = catalogue["strings"]
    languages = sorted({l for v in entries.values() for l in v.get("localizations", {})} | {"en"})

    # An entry with nothing in it at all — no localizations, no comment, no
    # extraction state — is residue Xcode left behind, not a string the app shows.
    # Reported rather than dropped quietly, because the same shape would be how a
    # real string looked if the catalogue were ever half-written.
    dead = sorted(k for k, v in entries.items() if not v)
    for key in dead:
        print(f"skipping empty catalogue entry {key!r}", file=sys.stderr)

    fields, seen = [], {}
    for key in sorted(k for k in entries if entries[k]):
        name = field_name(key)
        if name in seen:
            print(
                f"COLLISION on {name!r}:\n  {seen[name]!r}\n  {key!r}\n"
                "Add one of them to NAMES with a comment saying how the two differ.",
                file=sys.stderr,
            )
            return 1
        seen[name] = key
        fields.append((name, key))

    out = [
        "// Generated by Tools/generate-strings.py. Do not edit.",
        "//",
        "// Every user-facing string in the app, one field per catalogue key, one value per",
        "// language. A language that is missing a field does not compile, which is what this",
        "// replaces the CI completeness gate with.",
        "",
        "// `Sendable` because the two values below are `static let` and read from every actor in",
        "// the app. The closures are `@Sendable` for the same reason: they close over nothing.",
        "struct Strings: Sendable {",
    ]

    # Declarations.
    for name, key in fields:
        specifiers = parameters(key)
        if specifiers:
            args = ", ".join(f"_ a{i}: String" for i in range(len(specifiers)))
            out.append(f"\tlet {name}: @Sendable ({args}) -> String")
        else:
            out.append(f"\tlet {name}: String")
    out.append("}")
    out.append("")

    # One value per language.
    for language in languages:
        out.append(f"extension Strings {{")
        out.append(f"\tstatic let {swift_language_name(language)} = Self(")
        rows = []
        for name, key in fields:
            value = english(entries[key], key) if language == "en" else translation(entries[key], language, key)
            specifiers = parameters(key)
            if specifiers:
                args = ", ".join(f"a{i}" for i in range(len(specifiers)))
                body = interpolate(value, len(specifiers))
                rows.append(f"\t\t{name}: {{ ({args}) in {body} }}")
            else:
                rows.append(f"\t\t{name}: {swift_literal(value)}")
        out.append(",\n".join(rows))
        out.append("\t)")
        out.append("}")
        out.append("")

    # The mapping, so a test can hold every field against the catalogue it came from
    # rather than against the generator that wrote it. Emitted here rather than
    # rebuilt in Swift because a second implementation of the naming rules would
    # agree with this one by construction and prove nothing.
    # Every field's text as plain data, with each argument written as a marker, so a
    # test can compare it against the catalogue without reflecting over the struct.
    # `Mirror` was the obvious way and it segfaults: casting a closure back out of an
    # `Any` is not something the runtime does reliably, and 13 of these are closures.
    for language in languages:
        out.append("extension Strings {")
        out.append(f"\tstatic let rendered{swift_language_name(language).capitalize()}: [String: String] = [")
        rows = []
        for name, key in fields:
            value = english(entries[key], key) if language == "en" else translation(entries[key], language, key)
            count = len(parameters(key))
            text = markers(value, count) if count else value
            rows.append(f"\t\t{swift_literal(name)}: {swift_literal(text)}")
        out.append(",\n".join(rows))
        out.append("\t]")
        out.append("}")
        out.append("")

    out.append("extension Strings {")
    out.append("\t/// Which catalogue key each field was generated from.")
    out.append("\tstatic let catalogueKeys: [String: String] = [")
    out.append(",\n".join(f"\t\t{swift_literal(name)}: {swift_literal(key)}" for name, key in fields))
    out.append("\t]")
    out.append("}")
    out.append("")

    OUT.write_text("\n".join(out))
    print(f"{len(fields)} fields, {len(languages)} languages -> {OUT.relative_to(ROOT)}")
    return 0


MARKERS = ["\u20390\u203a", "\u20391\u203a", "\u20392\u203a", "\u20393\u203a"]


def markers(value: str, count: int) -> str:
    """The value with each argument replaced by the marker the test will pass in."""
    body, index, end = "", 0, 0

    for match in TOKEN.finditer(value):
        body += value[end:match.start()]
        end = match.end()

        if match.group(0) == "%%":
            body += "%"
            continue

        position = match.group(1)
        body += MARKERS[int(position) - 1 if position else index]
        index += 1

    return body + value[end:]


def swift_language_name(language: str) -> str:
    return {"en": "english", "zh-Hans": "simplifiedChinese"}.get(language, language.replace("-", ""))


def translation(entry, language, key):
    unit = entry.get("localizations", {}).get(language, {}).get("stringUnit")
    # An untranslated string falls back to the English, which is the key — the same
    # answer the catalogue gives today, kept so this migration changes no text.
    return unit["value"] if unit else key


def interpolate(value: str, count: int) -> str:
    """Turn a printf-style value into a Swift interpolated literal.

    Two things printf does that Swift interpolation does not. `%%` is an escaped
    per cent and has to become one, or the text ships with two. And a positional
    specifier — `%2$lld` — names which argument it wants, which translations use to
    put them in a different order than the English; taken in encounter order the
    Chinese would read the English's arguments in the English's order.
    """
    body, index, seen = "", 0, set()
    end = 0

    for match in TOKEN.finditer(value):
        body += swift_literal(value[end:match.start()])[1:-1]
        end = match.end()

        if match.group(0) == "%%":
            body += "%"
            continue

        position = match.group(1)
        argument = int(position) - 1 if position else index
        index += 1
        seen.add(argument)

        if not 0 <= argument < count:
            raise SystemExit(f"specifier {match.group(0)} has no argument in: {value!r}")

        body += f"\\(a{argument})"

    body += swift_literal(value[end:])[1:-1]

    if len(seen) != count:
        # A translation that drops or repeats an argument is a defect in the
        # catalogue, and silently emitting it would ship a sentence with a hole.
        raise SystemExit(f"uses {len(seen)} of {count} arguments: {value!r}")

    return f'"{body}"'


if __name__ == "__main__":
    raise SystemExit(main())
