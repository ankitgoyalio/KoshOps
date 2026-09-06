# KoshOps

KoshOps automates Xcode asset management.

## Requirements

- Swift 6.0 or newer
- macOS 13 or newer

## Build and run

```sh
swift build
swift run koshops --help
```

Run the tests with:

```sh
swift test
```

## Inspect and exchange localization

```sh
swift run koshops strings languages .
swift run koshops strings list . --language fr --status missing --status new
swift run koshops strings languages . --check-project App.xcodeproj --json
swift run koshops strings export . --language fr --format csv --output translations.csv
swift run koshops strings import translations.json --dry-run
swift run koshops strings import translations.json
swift run koshops strings import returned.csv --format csv --manifest translations.csv.manifest.json --status-update needs_review --dry-run
```

Inspection and export are read-only. Export defaults to JSON. Use `--format csv` for a
five-column vendor CSV and companion JSON manifest. Share the CSV and retain
the manifest locally for import validation. Import with `--dry-run` previews validated changes without writing catalogs.
Omit `--dry-run` to apply changes to one catalog with atomic replacement.
Multi-catalog preview is supported; apply each catalog separately. See [the command and schema contracts](docs/STRINGS.md) for
discovery, coverage, variants, Xcode comparisons, exports, imports, and retry behavior.

Start with `strings languages` to find the language codes in your catalogs.
Use `strings list` to inspect individual translations, including plural and
device variants. Export includes translations marked missing, new, or needs review
by default; add `--status translated` to export completed translations instead.

For JSON, edit only `translation` and `statusUpdate`. For CSV, edit only the
`translation` column and supply `--status-update` when previewing or applying changed text.
Use `new`, `needs_review`, or `translated` to reflect the translation's review
status. If your catalogs are elsewhere, set `--destination` to the catalog root
used for export when running import.
