# Tools

Everything the repository is maintained with. Nothing here ships in the app.

| | What it does |
| --- | --- |
| `setup-signing.sh` | Creates the self-signed certificate builds are signed with. `--export` writes the `.p12` for CI |
| `build-local.sh` | Builds a test copy signed the way releases are, and refuses to install one that lost its sandbox |
| `sync-labels.sh` | Makes the repository's labels match `.github/labels.yml` |
| `validate-sites.py` | Checks every `sites/*.yml` against `sites/schema.json`. CI runs this |
| `generate-site-catalog.py` | Writes `sites/index.json` and the bundled Swift copy from the YAML. CI fails if they disagree |
| `check-strings.py` | Reconciles `Localizable.xcstrings` with the strings the compiler says the app displays, in both directions. CI runs this after the build |
| `check-url-scheme.py` | Fails the build if the URL scheme in `Info.plist` drifts from the one the code handles |

The Python ones want `jsonschema` and `PyYAML`. CI pins Python 3.12 and installs the two with
`pip install jsonschema pyyaml`. Locally there is nothing to inherit — `.venv/` is gitignored and
nothing in the repository creates one — so make it yourself:

```sh
python3 -m venv .venv
.venv/bin/pip install jsonschema pyyaml
.venv/bin/python Tools/validate-sites.py
```
