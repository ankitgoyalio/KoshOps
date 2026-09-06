import ArgumentParser
import Foundation

struct StringsImport: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "import", abstract: "Validate returned translations and apply changes to one catalog.",
        discussion: "Examples:\n  koshops strings import translations.json --dry-run\n  koshops strings import translations.json\n  koshops strings import - --destination App --dry-run --json\n  koshops strings import returned.csv --format csv \\\n    --manifest translations.csv.manifest.json \\\n    --status-update needs_review --dry-run\n\nOmit --dry-run to apply changes to one catalog. Use the same catalog root as the export with --destination.\n\nFor JSON, set statusUpdate on each changed record. For CSV, supply the original companion manifest and use --status-update to set the status for changed text. Choose new, needs_review, or translated to reflect its review status."
    )
    @Argument(help: "Returned translation file, or - for stdin (default when stdin is redirected).") var input: String?
    @Option(help: "File format: json or csv.") var format: HandoffFormat = .json
    @Option(help: "Directory containing the exported catalog paths; . is the current directory.") var destination = "."
    @Option(help: "Original companion manifest required for CSV.") var manifest: String?
    @Option(help: "Review status for changed CSV translations: new, needs_review, or translated.") var statusUpdate: String?
    @Flag(help: "Validate and preview changes without changing catalogs.") var dryRun = false
    @Flag(help: "Write the result as JSON for scripts (schema version 1).") var json = false
    @Flag(help: "Run without prompts (this command never prompts).") var noInput = false

    mutating func run() throws {
        var stdinInfo = stat()
        // Incomplete interactive or /dev/null invocation shows help. A redirected
        // file or pipe is an input even when no options accompany the command.
        if input == nil && !dryRun && fstat(STDIN_FILENO, &stdinInfo) == 0 &&
            (stdinInfo.st_mode & S_IFMT) == S_IFCHR {
            throw CleanExit.helpRequest(self)
        }
        guard format == .csv || (manifest == nil && statusUpdate == nil) else {
            throw ValidationError("--manifest and --status-update are only used with CSV. For JSON, remove these options and set statusUpdate on each changed record.")
        }
        guard format != .csv || manifest != nil else { throw ValidationError("CSV requires its original companion manifest. Supply --manifest PATH.") }
        guard statusUpdate == nil || ["new", "needs_review", "translated"].contains(statusUpdate!) else {
            throw ValidationError("Invalid --status-update. Choose new, needs_review, or translated.")
        }
        if (input == nil || input == "-") && isatty(STDIN_FILENO) != 0 {
            throw ValidationError("No translation file supplied. Provide a JSON or CSV file argument, or pipe it to stdin with '-'.")
        }
        let result = try LocalizationWorkflow().importTranslations(input: input ?? "-", format: format, manifest: manifest,
                                                              statusUpdate: statusUpdate, destination: destination, dryRun: dryRun)
        if json {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
            FileHandle.standardOutput.write(try encoder.encode(result) + Data("\n".utf8))
        } else if !dryRun {
            let count = result.changes.count
            if count == 0 { print("Import complete: no changes. No catalogs changed.") }
            else {
                let catalog = String(decoding: try canonicalJSON(result.changes[0].catalog), as: UTF8.self)
                print("Applied \(count) \(count == 1 ? "change" : "changes") to \(catalog).")
            }
        } else {
            for change in result.changes {
                let identity = String(decoding: try canonicalJSON([change.catalog, change.key, change.language]), as: UTF8.self)
                let variant = String(decoding: try canonicalJSON(variantIdentity(change.variant)), as: UTF8.self)
                let value = String(decoding: try canonicalJSON(change.translation), as: UTF8.self)
                print("\(identity) \(variant): \(change.originalStatus) → \(change.status): \(value)")
            }
            let count = result.changes.count
            if count == 0 {
                print("Preview complete: no changes proposed. No catalogs changed.")
            } else {
                print("Preview complete: \(count) proposed \(count == 1 ? "change" : "changes"). No catalogs changed.")
            }
        }
    }
}
