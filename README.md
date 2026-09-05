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

## Inspect localization

```sh
swift run koshops strings languages .
swift run koshops strings list . --language fr --status missing --status new
swift run koshops strings languages . --check-project App.xcodeproj --json
```

Inspection is read-only. See [the command and JSON contracts](docs/STRINGS.md)
for discovery exclusions, coverage counting, variants, and Xcode comparisons.
