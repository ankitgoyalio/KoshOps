import ArgumentParser
import Foundation

struct Strings: ParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Inspect translations, export them for editing, and preview returned changes.",
        discussion: "Examples:\n  koshops strings languages .\n  koshops strings list --language fr --status missing\n\nExport translations with 'koshops strings export', then preview returned changes with 'koshops strings import --dry-run'. Catalogs are never changed. Run a subcommand with --help for examples and options.",
        subcommands: [StringsLanguages.self, StringsList.self, StringsExport.self, StringsImport.self]
    )
    mutating func run() throws { throw CleanExit.helpRequest(self) }
}

struct InspectionOptions: ParsableArguments {
    @Argument(help: "Paths to .xcstrings files or directories to search (default: current directory).")
    var paths: [String] = []

    @Flag(help: "Write results as JSON for scripts (schema version 1).")
    var json = false

    @Flag(help: "Run without prompts (this command never prompts).")
    var noInput = false
}

struct StringsLanguages: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "languages", abstract: "Show each catalog's languages and translation coverage.",
        discussion: "Examples:\n  koshops strings languages . --json\n  koshops strings languages . --check-project App.xcodeproj\n\nCoverage counts individual translations, including each plural or device variant. Entries marked not to translate are excluded. To inspect missing translations, run 'koshops strings list . --language fr --status missing'."
    )
    @OptionGroup var options: InspectionOptions

    @Option(help: "Compare languages with a .xcodeproj or project.pbxproj without changing files; differences exit 1.")
    var checkProject: String?

    mutating func run() throws {
        let workflow = LocalizationWorkflow()
        let inspection = try workflow.inspect(paths: options.paths)
        let check = try checkProject.map { try workflow.checkProject(path: $0, catalogs: inspection.catalogs) }
        if options.json {
            try emitJSON(LanguageReport(catalogs: inspection.catalogs, projectCheck: check))
        } else {
            for catalog in inspection.catalogs {
                print("\(quoted(catalog.catalog)) (source: \(quoted(catalog.sourceLanguage)))")
                for language in catalog.languages {
                    if language.total == 0 {
                        print("  \(quoted(language.language)): no translations counted; the catalog is empty or its entries are marked not to translate.")
                        continue
                    }
                    print("  \(quoted(language.language)): \(language.translated)/\(language.total) translated; \(language.missing) missing, \(language.new) new, \(language.needsReview) needs review, \(language.unsupported) unsupported")
                }
            }
            if let check {
                print("Project languages: " + check.declaredLanguages.map(quoted).joined(separator: ", "))
                for comparison in check.catalogs {
                    print("\(quoted(comparison.catalog)): catalog-only [\(comparison.catalogOnly.map(quoted).joined(separator: ", "))]; project-only [\(comparison.projectOnly.map(quoted).joined(separator: ", "))]")
                }
            }
        }
        if let check, !check.matches {
            FileHandle.standardError.write(Data("Error: Catalog and Xcode language declarations differ. No files changed. Review the languages listed only in the catalog or project, then update the language declarations in Xcode.\n".utf8))
            throw ExitCode.failure
        }
    }
}

struct StringsList: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "list", abstract: "List translations, their statuses, and plural or device variants.",
        discussion: "Examples:\n  koshops strings list . --language fr --status missing --status new\n  koshops strings list Localizable.xcstrings --json\n\nAll languages and statuses are included by default. Unsupported entries remain visible even with --status; inspect them in Xcode. Use --include-excluded to show entries marked not to translate."
    )
    @OptionGroup var options: InspectionOptions
    @Option(help: "Include a catalog language, such as fr; repeat to include several.") var language: [String] = []
    @Option(help: "Include missing, new, needs_review, or translated; repeat to match any selected status.") var status: [TranslationStatus] = []
    @Flag(help: "Show entries marked not to translate; coverage is unchanged.") var includeExcluded = false

    mutating func run() throws {
        let inspection = try LocalizationWorkflow().inspect(paths: options.paths)
        let known = Set(inspection.catalogs.flatMap { $0.languages.map(\.language) })
        let unknown = Set(language).subtracting(known).sorted()
        guard unknown.isEmpty else {
            throw ValidationError("Languages not found in the selected catalogs: \(unknown.joined(separator: ", ")). Run 'koshops strings languages' with the same catalog paths to see available languages.")
        }
        let units = inspection.units.filter {
            (includeExcluded || !$0.excluded) && (language.isEmpty || language.contains($0.language)) &&
            (status.isEmpty || status.map(\.rawValue).contains($0.status.rawValue) || $0.status == .unsupported)
        }
        if options.json {
            try emitJSON(UnitReport(units: units))
        } else {
            for unit in units {
                let variant = unit.variant.map { "\($0.dimension)=\($0.value)" }.joined(separator: "/")
                print("\(quoted(unit.catalog)) \(quoted(unit.key)) [\(quoted(unit.language))\(variant.isEmpty ? "" : "; " + quoted(variant))] \(unit.status.rawValue)\(unit.excluded ? " (excluded)" : ""): \(quoted(unit.value ?? unit.issue ?? ""))")
            }
            if units.isEmpty {
                if !language.isEmpty || !status.isEmpty {
                    print("No translations match the selected languages and statuses. Remove --language or --status filters to broaden the results.")
                } else if !includeExcluded {
                    print("No translations to list. Use --include-excluded to check for entries marked not to translate.")
                } else {
                    print("No translations to list in the selected catalogs.")
                }
            }
        }
    }
}

enum TranslationStatus: String, ExpressibleByArgument {
    case missing, new, needs_review, translated
}

private struct LanguageReport: Encodable {
    let schemaVersion = 1
    let catalogs: [CatalogInspection]
    let projectCheck: ProjectCheck?
}

private struct UnitReport: Encodable {
    let schemaVersion = 1
    let units: [TranslationUnit]
}

private func emitJSON(_ value: some Encodable) throws {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
    print(String(decoding: try encoder.encode(value), as: UTF8.self))
}

private func quoted(_ value: String) -> String {
    String(decoding: try! JSONEncoder().encode(value), as: UTF8.self)
}
