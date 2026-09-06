import ArgumentParser
import Foundation

struct StringsExport: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "export", abstract: "Export JSON handoffs or a vendor CSV with a companion manifest.",
        discussion: "Examples:\n  koshops strings export . --language fr\n  koshops strings export . --language fr --format csv -o translations.csv\n  koshops strings export . --all-languages --format csv -o translations.csv --manifest private/manifest.json\n  koshops strings export . --language fr --format csv --manifest manifest.json > translations.csv\n\nSelect --language or --all-languages. Defaults to missing, new, and needs_review. Send only the CSV; vendors edit translation. Keep the manifest for the future import workflow. See docs/STRINGS.md."
    )
    @Argument(help: "Catalog files or discovery directories (default: current directory).") var paths: [String] = []
    @Option(help: "Select an existing catalog language; repeat for several.") var language: [String] = []
    @Flag(help: "Select all catalog languages, excluding each catalog's source language.") var allLanguages = false
    @Option(help: "Select missing, new, needs_review, or translated; repeat for OR matching.") var status: [TranslationStatus] = []
    @Option(help: "Export format: json (default) or vendor-friendly csv with a manifest.") var format: HandoffFormat = .json
    @Option(name: [.short, .long], help: "Output file, or - for stdout (CSV requires --manifest).") var output = "-"
    @Option(help: "JSON manifest file to retain locally (default: OUTPUT.manifest.json for file output).") var manifest: String?
    @Flag(help: "Allow replacing existing CSV and manifest files.") var overwrite = false
    @Flag(help: "Disable prompts (export never prompts).") var noInput = false

    mutating func validate() throws {
        guard allLanguages != !language.isEmpty else {
            throw ValidationError("Select --language LANGUAGE (repeatable) or --all-languages, but not both. Run 'koshops strings export --help' for examples.")
        }
        guard format != .csv || output != "-" || manifest != nil else {
            throw ValidationError("CSV on stdout requires a companion manifest. Supply --manifest PATH or --output translations.csv.")
        }
        guard format == .csv || manifest == nil else {
            throw ValidationError("--manifest is only used with CSV. Use --format csv or omit --manifest for JSON export.")
        }
    }

    mutating func run() throws {
        let result = try LocalizationWorkflow().export(paths: paths, languages: language, statuses: status.map(\.rawValue), format: format, output: output, manifest: manifest, overwrite: overwrite)
        if let data = result.data { FileHandle.standardOutput.write(data) }
        let destination = output == "-" ? "stdout" : "'\(output)'"
        if let manifestPath = result.manifestPath {
            FileHandle.standardError.write(Data("Exported CSV to \(destination). Keep manifest '\(manifestPath)' locally; share only the CSV.\n".utf8))
        } else if output != "-" {
            FileHandle.standardError.write(Data("Exported translations to \(destination).\n".utf8))
        }
    }
}

extension HandoffFormat: ExpressibleByArgument {}
