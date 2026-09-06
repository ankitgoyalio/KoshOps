import ArgumentParser
import Foundation

struct StringsImport: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "import", abstract: "Validate a translation handoff and preview catalog changes without writing.",
        discussion: "Examples:\n  koshops strings import translations.json --dry-run\n  koshops strings import - --destination App --dry-run --json\n  koshops strings import returned.csv --format csv --manifest original.json --status-update needs_review --dry-run\n\nApplication is not available yet: --dry-run is required. CSV requires its original manifest; --status-update supplies explicit review intent for changed CSV text. See docs/STRINGS.md."
    )
    @Argument(help: "Handoff file, or - for stdin (default when stdin is redirected).") var input: String?
    @Option(help: "Handoff format: json (default) or csv.") var format: HandoffFormat = .json
    @Option(help: "Destination root for catalog identities (default: current directory).") var destination = "."
    @Option(help: "Original companion manifest required for CSV.") var manifest: String?
    @Option(help: "Explicit state for changed CSV text: new, needs_review, or translated.") var statusUpdate: String?
    @Flag(help: "Validate and preview all changes; required until application is available.") var dryRun = false
    @Flag(help: "Emit the schema-version-1 JSON preview.") var json = false
    @Flag(help: "Disable prompts (import never prompts).") var noInput = false

    mutating func run() throws {
        if input == nil && !dryRun { throw CleanExit.helpRequest(self) }
        guard dryRun else { throw ValidationError("Import application is not available yet. Add --dry-run to validate and preview without writing.") }
        guard format == .csv || (manifest == nil && statusUpdate == nil) else {
            throw ValidationError("--manifest and --status-update are CSV options. Edit each JSON record's statusUpdate instead.")
        }
        guard format != .csv || manifest != nil else { throw ValidationError("CSV requires its original manifest. Supply --manifest PATH.") }
        guard statusUpdate == nil || ["new", "needs_review", "translated"].contains(statusUpdate!) else {
            throw ValidationError("Invalid --status-update. Choose new, needs_review, or translated.")
        }
        if (input == nil || input == "-") && isatty(STDIN_FILENO) != 0 {
            throw ValidationError("No handoff supplied. Provide a file argument or pipe a handoff to stdin with '-'.")
        }
        let result = try LocalizationWorkflow().previewImport(input: input ?? "-", format: format, manifest: manifest,
                                                              statusUpdate: statusUpdate, destination: destination)
        if json {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
            FileHandle.standardOutput.write(try encoder.encode(result) + Data("\n".utf8))
        } else {
            for change in result.changes {
                let identity = String(decoding: try canonicalJSON([change.catalog, change.key, change.language]), as: UTF8.self)
                let variant = String(decoding: try canonicalJSON(variantIdentity(change.variant)), as: UTF8.self)
                let value = String(decoding: try canonicalJSON(change.translation), as: UTF8.self)
                print("\(identity) \(variant): \(change.originalStatus) → \(change.status): \(value)")
            }
            print("Dry run: \(result.changes.count) change(s). No catalogs written.")
        }
    }
}
