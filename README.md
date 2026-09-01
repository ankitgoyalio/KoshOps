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

The executable is built with Apple's
[`swift-argument-parser`](https://github.com/apple/swift-argument-parser). Add new
commands as `ParsableCommand` types and register them in `KoshOps.configuration`.
