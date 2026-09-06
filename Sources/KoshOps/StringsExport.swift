import ArgumentParser
import Foundation

struct StringsExport: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "export", abstract: "Export translations for editing as JSON or CSV.",
        discussion: "Examples:\n  koshops strings export . --language fr -o translations.json\n  koshops strings export . --language fr --format csv -o translations.csv\n  koshops strings export . --all-languages -o translations.json\n\nSelect --language or --all-languages. By default, export includes translations marked missing, new, or needs review; source languages and entries marked not to translate are excluded. Catalogs are never changed.\n\nFor JSON, edit only translation and statusUpdate. For CSV, share only the CSV and edit only the translation column. Keep the companion manifest to validate returned translations. Preview them with 'koshops strings import --dry-run'; applying changes is not available yet."
    )
    @Argument(help: "Paths to .xcstrings files or directories to search (default: current directory).") var paths: [String] = []
    @Option(help: "Include a catalog language, such as fr; repeat to include several. Source languages are excluded.") var language: [String] = []
    @Flag(help: "Select all catalog languages, excluding each catalog's source language.") var allLanguages = false
    @Option(help: "Include missing, new, needs_review, or translated; repeat to match any selected status.") var status: [TranslationStatus] = []
    @Option(help: "File format: json or csv. CSV also writes a companion JSON manifest for import validation.") var format: HandoffFormat = .json
    @Option(name: [.short, .long], help: "Output file, or - for stdout. CSV sent to stdout requires --manifest.") var output = "-"
    @Option(help: "Companion manifest for CSV; keep it for import (default: OUTPUT.manifest.json for file output).") var manifest: String?
    @Flag(help: "Replace existing JSON, CSV, or companion manifest files at the selected output paths.") var overwrite = false
    @Flag(help: "Run without prompts (this command never prompts).") var noInput = false

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
            FileHandle.standardError.write(Data("Exported CSV to \(destination). Keep the companion manifest '\(manifestPath)' locally; share only the CSV.\n".utf8))
        } else if output != "-" {
            FileHandle.standardError.write(Data("Exported translations to \(destination). Edit translation and statusUpdate, then preview with 'koshops strings import --dry-run'.\n".utf8))
        }
    }
}

extension HandoffFormat: ExpressibleByArgument {}
