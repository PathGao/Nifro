# Repository governance

Adopted baseline: **2026-09-16** from [PathGao/governance](https://github.com/PathGao/PathGao/tree/main/governance).
Adopted [source snapshot](https://github.com/PathGao/PathGao/tree/efab3e421c6606c1ce0a1c5836e98ba0ff64addb/governance).
Updates are reviewed and copied manually; there is no automatic inheritance.

## Workflow

Use the short PR template. `Closes #123` or `Fixes #123` closes a completed issue
on merge. For partial work, use `Related to #123` and state what remains. There
is no release-confirmation or inactivity-close automation.

`question` is a usage question. `needs info` waits for reporter details,
`awaiting decision` waits for a maintainer decision, and `planned` means accepted.
Type and resolution labels are defined in [labels.json](labels.json).

## Maintenance

[settings.json](settings.json) and [rulesets/](rulesets/) are desired GitHub
configuration, applied through the API as described in the baseline guide.
Committing these files alone does not change repository settings. Main requires
PRs and blocks deletion/force pushes; administrators retain a recovery bypass.
Release tags matching `v*` cannot be updated/deleted, except `v*-test*` tags.

Preview label changes from the repository root:

```sh
./Tools/sync-labels.sh PathGao/Nifro
```

Add `--apply` to create/update the declared labels. Labels outside the manifest
are preserved, including historical labels attached to closed issues.

## Project differences

Nifro retains site submission and other project labels, existing issue forms,
and its five required CI jobs. `Final_Check_Request` remains only as a legacy
GitHub label for historical issues; it is outside the managed manifest.
