import Foundation
import CoreFoundation


struct InspectionError: Error, CustomStringConvertible {
    let description: String
    init(_ description: String) { self.description = description }
}

enum UnitStatus: String, Encodable {
    case missing, new, needsReview = "needs_review", translated, unsupported
}

struct TranslationUnit: Encodable {
    let catalog: String
    let key: String
    let language: String
    let variant: [Variant]
    let status: UnitStatus
    let value: String?
    let excluded: Bool
    let issue: String?
}

struct Variant: Encodable {
    let dimension: String
    let value: String
}

struct LanguageCoverage: Encodable {
    let language: String
    let isSource: Bool
    var total = 0
    var missing = 0
    var new = 0
    var needsReview = 0
    var translated = 0
    var unsupported = 0

}

struct CatalogInspection: Encodable {
    let catalog: String
    let sourceLanguage: String
    let languages: [LanguageCoverage]
}

struct LocalizationInspection {
    let catalogs: [CatalogInspection]
    let units: [TranslationUnit]
}

/// The single entry point for localization workflows; parsing and discovery stay here.
struct LocalizationWorkflow {
    private let files = FileManager.default
    private let exclusions: Set<String> = [".git", ".build", ".swiftpm", "build", "Build", "DerivedData", "Pods", "Carthage", "node_modules", "vendor"]

    func inspect(paths: [String]) throws -> LocalizationInspection {
        let selected = (paths.isEmpty ? ["."] : paths).map {
            URL(fileURLWithPath: $0).standardizedFileURL.resolvingSymlinksInPath()
        }
        var catalogs = Set<URL>()
        var roots: [URL] = []
        for url in selected {
            var directory: ObjCBool = false
            guard files.fileExists(atPath: url.path, isDirectory: &directory) else {
                throw InspectionError("Path '\(url.path)' does not exist. Supply a catalog or directory.")
            }
            if directory.boolValue {
                roots.append(url)
                try discover(url, catalogs: &catalogs)
            } else {
                guard url.pathExtension == "xcstrings" else {
                    throw InspectionError("'\(url.path)' is not a .xcstrings catalog. Supply a catalog or directory.")
                }
                roots.append(url.deletingLastPathComponent())
                catalogs.insert(url)
            }
        }
        guard !catalogs.isEmpty else {
            throw InspectionError("No .xcstrings catalogs found. Supply an explicit catalog path or another directory.")
        }
        var root = roots[0]
        while !roots.allSatisfy({ $0.path == root.path || $0.path.hasPrefix(root.path == "/" ? "/" : root.path + "/") }) {
            root.deleteLastPathComponent()
        }
        var summaries: [CatalogInspection] = []
        var units: [TranslationUnit] = []
        for url in catalogs.sorted(by: { $0.path < $1.path }) {
            let prefix = root.path == "/" ? "/" : root.path + "/"
            let identity = String(url.path.dropFirst(prefix.count))
            let result = try readCatalog(url, identity: identity)
            summaries.append(result.0)
            units += result.1
        }
        return LocalizationInspection(catalogs: summaries, units: units)
    }

    private func discover(_ directory: URL, catalogs: inout Set<URL>) throws {
        let children: [URL]
        do {
            children = try files.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey])
        } catch {
            throw InspectionError("Cannot read directory '\(directory.path)': \(error.localizedDescription). Check directory permissions.")
        }
        for child in children.sorted(by: { $0.path < $1.path }) {
            let properties = try child.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
            // Explicit symlink selections are resolved, but discovery never follows links.
            if properties.isSymbolicLink == true { continue }
            if properties.isDirectory == true {
                if !exclusions.contains(child.lastPathComponent) { try discover(child, catalogs: &catalogs) }
            } else if child.pathExtension == "xcstrings" {
                catalogs.insert(child.standardizedFileURL)
            }
        }
    }

    private func readCatalog(_ url: URL, identity: String) throws -> (CatalogInspection, [TranslationUnit]) {
        let object: [String: Any]
        do {
            guard let decoded = try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any] else {
                throw InspectionError("Expected a JSON object")
            }
            object = decoded
        } catch {
            throw InspectionError("Cannot read catalog '\(identity)': \(error). Validate the catalog JSON and file permissions.")
        }
        guard object["version"] as? String == "1.0",
              let source = object["sourceLanguage"] as? String, !source.isEmpty,
              let strings = object["strings"] as? [String: Any] else {
            throw InspectionError("Invalid or unsupported catalog '\(identity)'. Supply version 1.0 with sourceLanguage and strings.")
        }
        var languages: Set<String> = [source]
        for (key, raw) in strings {
            guard let entry = raw as? [String: Any],
                  entry["localizations"] == nil || entry["localizations"] is [String: Any],
                  entry["shouldTranslate"] == nil || isBoolean(entry["shouldTranslate"]) else {
                throw InspectionError("Invalid entry '\(key)' in '\(identity)'. Fix its object, localizations, or shouldTranslate field.")
            }
            languages.formUnion((entry["localizations"] as? [String: Any] ?? [:]).keys)
        }
        var units: [TranslationUnit] = []
        for key in strings.keys.sorted() {
            let entry = strings[key] as! [String: Any]
            let localizations = entry["localizations"] as? [String: Any] ?? [:]
            let excluded = entry["shouldTranslate"] as? Bool == false
            for language in languages.sorted() {
                let node = localizations[language]
                if node == nil && language == source {
                    units.append(TranslationUnit(catalog: identity, key: key, language: language, variant: [], status: .translated, value: key, excluded: excluded, issue: nil))
                } else if node == nil, let sourceNode = localizations[source] as? [String: Any],
                          sourceNode["variations"] != nil || sourceNode["substitutions"] != nil {
                    units.append(TranslationUnit(catalog: identity, key: key, language: language, variant: [], status: .unsupported, value: nil, excluded: excluded, issue: "Missing localization has a structured source; variant structure cannot be inferred."))
                } else {
                    units += flatten(node, catalog: identity, key: key, language: language, excluded: excluded)
                }
            }
        }
        let coverage = languages.sorted().map { language in
            var result = LanguageCoverage(language: language, isSource: language == source)
            for unit in units where unit.language == language && !unit.excluded {
                result.total += 1
                switch unit.status {
                case .missing: result.missing += 1
                case .new: result.new += 1
                case .needsReview: result.needsReview += 1
                case .translated: result.translated += 1
                case .unsupported: result.unsupported += 1
                }
            }
            return result
        }
        return (CatalogInspection(catalog: identity, sourceLanguage: source, languages: coverage), units)
    }

    private func isBoolean(_ value: Any?) -> Bool {
        guard let number = value as? NSNumber else { return false }
        return CFGetTypeID(number) == CFBooleanGetTypeID()
    }

    private func flatten(_ raw: Any?, catalog: String, key: String, language: String, excluded: Bool, variant: [Variant] = []) -> [TranslationUnit] {
        func unit(_ status: UnitStatus, value: String? = nil, issue: String? = nil) -> [TranslationUnit] {
            [TranslationUnit(catalog: catalog, key: key, language: language, variant: variant, status: status, value: value, excluded: excluded, issue: issue)]
        }
        guard let raw else { return unit(.missing) }
        guard let node = raw as? [String: Any] else {
            return unit(.unsupported, issue: "Expected a localization object; inspect this entry in Xcode.")
        }
        if node.isEmpty { return unit(.missing) }
        guard Set(node.keys).isSubset(of: ["stringUnit", "variations"]), node.count == 1 else {
            return unit(.unsupported, issue: "Unsupported localization fields or combined structures; inspect this entry in Xcode.")
        }
        if let string = node["stringUnit"] as? [String: Any],
           let rawState = string["state"] as? String, let state = UnitStatus(rawValue: rawState),
           [.new, .needsReview, .translated].contains(state),
           let value = string["value"] as? String,
           Set(string.keys).isSubset(of: ["state", "value"]) {
            return unit(state, value: value)
        }
        if let variations = node["variations"] as? [String: Any], variations.count == 1,
           let dimension = variations.keys.first, ["plural", "device"].contains(dimension),
           !variant.contains(where: { $0.dimension == dimension }),
           let cases = variations[dimension] as? [String: Any], !cases.isEmpty {
            return cases.keys.sorted().flatMap { name in
                flatten(cases[name], catalog: catalog, key: key, language: language, excluded: excluded,
                        variant: variant + [Variant(dimension: dimension, value: name)])
            }
        }
        return unit(.unsupported, issue: "Unsupported variant structure or string state; inspect this entry in Xcode.")
    }
}

struct ProjectCheck: Encodable {
    let declaredLanguages: [String]
    let catalogs: [CatalogLanguageComparison]
    var matches: Bool { catalogs.allSatisfy { $0.catalogOnly.isEmpty && $0.projectOnly.isEmpty } }
}

struct CatalogLanguageComparison: Encodable {
    let catalog: String
    let catalogOnly: [String]
    let projectOnly: [String]
}

extension LocalizationWorkflow {
    func checkProject(path: String, catalogs: [CatalogInspection]) throws -> ProjectCheck {
        var url = URL(fileURLWithPath: path)
        if url.pathExtension == "xcodeproj" { url.appendPathComponent("project.pbxproj") }
        let project: [String: Any]
        do {
            guard let plist = try PropertyListSerialization.propertyList(from: Data(contentsOf: url), format: nil) as? [String: Any],
                  let root = plist["rootObject"] as? String,
                  let objects = plist["objects"] as? [String: Any],
                  let object = objects[root] as? [String: Any], object["isa"] as? String == "PBXProject" else {
                throw InspectionError("Expected a PBXProject root object")
            }
            project = object
        } catch {
            throw InspectionError("Cannot read Xcode project '\(path)': \(error). Supply a readable .xcodeproj or project.pbxproj file.")
        }
        guard let regions = project["knownRegions"] as? [String],
              let source = project["developmentRegion"] as? String, !source.isEmpty,
              regions.allSatisfy({ !$0.isEmpty }) else {
            throw InspectionError("Invalid Xcode language declarations in '\(path)'. Set knownRegions and developmentRegion in Xcode before checking.")
        }
        let declared = Set(regions + [source]).subtracting(["Base"])
        return ProjectCheck(declaredLanguages: declared.sorted(), catalogs: catalogs.map { catalog in
            let languages = Set(catalog.languages.map(\.language))
            return CatalogLanguageComparison(catalog: catalog.catalog, catalogOnly: languages.subtracting(declared).sorted(), projectOnly: declared.subtracting(languages).sorted())
        })
    }
}
