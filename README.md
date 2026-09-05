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

## Inspect and export localization

```sh
swift run koshops strings languages .
swift run koshops strings list . --language fr --status missing --status new
swift run koshops strings languages . --check-project App.xcodeproj --json
swift run koshops strings export . --language fr --output translations.json
```

Catalogs remain read-only. Export produces editable JSON or CSV handoffs with
source context and conflict metadata. See [the command and schema contracts](docs/STRINGS.md)
for discovery, coverage, variants, Xcode comparisons, and translation exports.
