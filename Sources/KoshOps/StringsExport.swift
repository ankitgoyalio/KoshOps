import ArgumentParser
import Foundation

struct StringsExport: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "export", abstract: "Export portable translation handoffs as JSON or CSV.",
        discussion: "Examples:\n  koshops strings export . --language fr\n  koshops strings export . --all-languages --format csv --output translations.csv\n  koshops strings export Labels.xcstrings --language fr --status translated --output -\n\nSelect --language or --all-languages. Defaults to missing, new, and needs_review. Only translation and statusUpdate are editable. See docs/STRINGS.md for the versioned contract."
    )
    @Argument(help: "Catalog files or discovery directories (default: current directory).") var paths: [String] = []
    @Option(help: "Select an existing catalog language; repeat for several.") var language: [String] = []
    @Flag(help: "Select all catalog languages, excluding each catalog's source language.") var allLanguages = false
    @Option(help: "Select missing, new, needs_review, or translated; repeat for OR matching.") var status: [TranslationStatus] = []
    @Option(help: "Handoff format: json (default) or csv.") var format: HandoffFormat = .json
    @Option(name: [.short, .long], help: "Write to a file, or - for stdout (default).") var output = "-"
    @Flag(help: "Allow replacing an existing output file.") var overwrite = false
    @Flag(help: "Disable prompts (export never prompts).") var noInput = false

    mutating func validate() throws {
        guard allLanguages != !language.isEmpty else {
            throw ValidationError("Select --language LANGUAGE (repeatable) or --all-languages, but not both. Run 'koshops strings export --help' for examples.")
        }
    }

    mutating func run() throws {
        let data = try LocalizationWorkflow().export(paths: paths, languages: language, statuses: status.map(\.rawValue), format: format, output: output, overwrite: overwrite)
        if let data { FileHandle.standardOutput.write(data) }
        else { FileHandle.standardError.write(Data("Exported translations to '\(output)'.\n".utf8)) }
    }
}

extension HandoffFormat: ExpressibleByArgument {}
