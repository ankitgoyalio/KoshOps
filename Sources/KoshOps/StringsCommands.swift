import ArgumentParser
import Foundation

struct Strings: ParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Inspect, export, and preview imports for Xcode String Catalogs.",
        discussion: "Examples:\n  koshops strings languages .\n  koshops strings list --language fr --status missing\n\nRun a subcommand with --help for options.",
        subcommands: [StringsLanguages.self, StringsList.self, StringsExport.self, StringsImport.self]
    )
    mutating func run() throws { throw CleanExit.helpRequest(self) }
}

struct InspectionOptions: ParsableArguments {
    @Argument(help: "Catalog files or directories to discover (default: current directory).")
    var paths: [String] = []

    @Flag(help: "Emit the stable schema-version-1 JSON inspection format.")
    var json = false

    @Flag(help: "Disable prompts (inspection never prompts).")
    var noInput = false
}

struct StringsLanguages: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "languages", abstract: "List source languages and translation-unit coverage per catalog.",
        discussion: "Examples:\n  koshops strings languages . --json\n  koshops strings languages . --check-project App.xcodeproj\n\nCoverage excludes entries marked not to translate. See docs/STRINGS.md for counting and discovery rules."
    )
    @OptionGroup var options: InspectionOptions

    @Option(help: "Compare with an explicit .xcodeproj or project.pbxproj, read-only; mismatches exit 1.")
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
                    print("  \(quoted(language.language)): \(language.translated)/\(language.total) translated; \(language.missing) missing, \(language.new) new, \(language.needsReview) needs_review, \(language.unsupported) unsupported")
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
            FileHandle.standardError.write(Data("Error: Catalog and Xcode language declarations differ. Review catalogOnly/projectOnly in the report and reconcile the languages in Xcode. No files changed.\n".utf8))
            throw ExitCode.failure
        }
    }
}

struct StringsList: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "list", abstract: "Inspect individual translations and plural/device variants.",
        discussion: "Examples:\n  koshops strings list . --language fr --status missing --status new\n  koshops strings list Localizable.xcstrings --json\n\nAll languages and statuses are included by default. Use --include-excluded to audit entries marked not to translate."
    )
    @OptionGroup var options: InspectionOptions
    @Option(help: "Select a catalog language; repeat to select several.") var language: [String] = []
    @Option(help: "Select missing, new, needs_review, or translated; repeat for OR matching.") var status: [TranslationStatus] = []
    @Flag(help: "Include entries marked not to translate in inspection.") var includeExcluded = false

    mutating func run() throws {
        let inspection = try LocalizationWorkflow().inspect(paths: options.paths)
        let known = Set(inspection.catalogs.flatMap { $0.languages.map(\.language) })
        let unknown = Set(language).subtracting(known).sorted()
        guard unknown.isEmpty else {
            throw ValidationError("Unknown catalog language(s): \(unknown.joined(separator: ", ")). Run 'koshops strings languages' to see available languages.")
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
            if units.isEmpty { print("No translation units match.") }
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
