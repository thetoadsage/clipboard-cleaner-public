# Third-party data

## ClearURLs/Rules

`Sources/ClipboardCleanerCore/Resources/tracking-rules.json` is derived from
the [ClearURLs/Rules](https://github.com/ClearURLs/Rules) catalog, licensed
under the [GNU Lesser General Public License v3.0](ClearURLs-Rules-LGPL-3.0.txt).

Only the `rules` field (query parameter names/patterns to strip) is used,
re-expressed in this project's own JSON schema. Not included: `rawRules`,
`redirections`/`forceRedirection`, `completeProvider`, `exceptions`, or
`referralMarketing` — see `scripts/update_tracking_rules.py` for the full
rationale and the exact filtering logic.

The `localGlobalAdditions` array in `tracking-rules.json` is hand-maintained
by this project and is *not* derived from ClearURLs.

To refresh the ClearURLs-derived portion of the catalog:

```bash
python3 scripts/update_tracking_rules.py
```

This is a manual, offline maintenance step — the app itself never makes
network requests.
