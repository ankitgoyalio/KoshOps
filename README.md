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
swift run koshops strings import returned.csv --format csv --manifest translations.csv.manifest.json --status-update needs_review --dry-run
```

Catalogs remain read-only. Export defaults to JSON. Use `--format csv` for a
five-column vendor CSV and companion JSON manifest. Share the CSV and retain
the manifest locally for import validation. Import requires `--dry-run` and
previews validated changes without writing catalogs. Catalog application is not
available yet. See [the command and schema contracts](docs/STRINGS.md) for
discovery, coverage, variants, Xcode comparisons, exports, and import previews.
