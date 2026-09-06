import Foundation

struct ImportResult: Encodable {
    let schemaVersion = 1
    let dryRun: Bool
    let changes: [TranslationChange]
}

struct TranslationChange: Encodable {
    let catalog: String
    let key: String
    let language: String
    let variant: [Variant]
    let originalTranslation: String?
    let originalStatus: String
    let translation: String
    let status: String
}

extension LocalizationWorkflow {
    func importTranslations(input: String, format: HandoffFormat, manifest: String?, statusUpdate: String?,
                            destination: String, dryRun: Bool,
                            writer: CatalogWriter = CatalogWriter()) throws -> ImportResult {
        let data = try readHandoff(input)
        let records: [[String: Any]]
        if format == .json { records = try jsonRecords(data) }
        else {
            guard let manifest else { throw InspectionError("CSV requires --manifest PATH.") }
            records = try csvRecords(data, manifest: manifest, statusUpdate: statusUpdate)
        }
        let root = URL(fileURLWithPath: destination).standardizedFileURL.resolvingSymlinksInPath()
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: root.path, isDirectory: &isDirectory), isDirectory.boolValue else {
            throw InspectionError("Invalid destination directory '\(destination)'. Set --destination to the existing directory containing the exported catalog paths.")
        }
        var inspections: [URL: LocalizationInspection] = [:]
        var catalogPaths: [String: URL] = [:]
        var seen = Set<Data>()
        var changes: [TranslationChange] = []
        for record in records {
            do {
                try validateRecord(record)
                let catalog = record["catalog"] as! String
                let key = record["key"] as! String
                let language = record["language"] as! String
                let variant = record["variant"] as! [[String: String]]
                let path = try catalogPath(catalog, beneath: root)
                if let previous = catalogPaths[catalog], previous != path {
                    throw InspectionError("Catalog path changed during validation. Restore the catalog layout and export again.")
                }
                catalogPaths[catalog] = path
                let identity = try canonicalJSON([path.path, key, language, variant])
                guard seen.insert(identity).inserted else { throw InspectionError("Duplicate record identity; keep only one row per translation unit.") }
                if inspections[path] == nil {
                    inspections[path] = try inspect(paths: [path.path])
                }
                let inspection = inspections[path]!
                let document = inspection.documents.values.first!
                let sourceLanguage = document["sourceLanguage"] as! String
                guard language != sourceLanguage else { throw InspectionError("Source-language translations cannot be imported; remove this record.") }
                guard let unit = inspection.units.first(where: {
                    $0.key == key && $0.language == language && variantIdentity($0.variant) == variant
                }) else { throw InspectionError("Unknown key, language, or variant; export existing catalog units again.") }
                guard !unit.excluded, unit.status != .unsupported else {
                    throw InspectionError("Excluded or unsupported translation; inspect this entry in Xcode and export again.")
                }
                let translation = record["translation"] as! String
                let update = record["statusUpdate"] as! String
                let original = record["originalTranslation"] as? String
                let textChanged = translation != (original ?? "")
                guard !textChanged || !update.isEmpty else {
                    throw InspectionError("Changed translation has no review status. Set statusUpdate in JSON or --status-update for CSV to new, needs_review, or translated, then preview again.")
                }
                if !textChanged && (update.isEmpty || update == record["status"] as? String) { continue }
                guard !translation.isEmpty else { throw InspectionError("Empty translation update; provide nonempty text or omit the record.") }
                let sources = inspection.units.filter { $0.key == key && $0.language == sourceLanguage }
                let identified = TranslationUnit(catalog: catalog, key: key, language: language, variant: unit.variant,
                                                 status: unit.status, value: unit.value, excluded: unit.excluded, issue: unit.issue)
                let current = try handoffRecord(identified, document: document, sourceUnits: sources)
                guard current["sourceFingerprint"] as? String == record["sourceFingerprint"] as? String else {
                    throw InspectionError("The source text or context changed since export. Export again, review this translation against the updated source, then preview again.")
                }
                guard current["destinationFingerprint"] as? String == record["destinationFingerprint"] as? String else {
                    throw InspectionError("The catalog translation changed since export. Export again, compare the returned translation with the current catalog text, then preview again.")
                }
                guard current["recordFingerprint"] as? String == record["recordFingerprint"] as? String else {
                    throw InspectionError("Protected record fields do not match the catalog; export a fresh translation file.")
                }
                // Matching source variants are authoritative; otherwise all supplied source
                // variants must permit the translation. Never guess plural-category mappings.
                let matching = sources.filter { variantIdentity($0.variant) == variant }
                for source in matching.isEmpty ? sources : matching {
                    try validatePlaceholders(source: source.value!, translation: translation)
                }
                changes.append(TranslationChange(catalog: catalog, key: key, language: language, variant: unit.variant,
                    originalTranslation: original, originalStatus: record["status"] as! String, translation: translation, status: update))
            } catch {
                let context = String(decoding: (try? canonicalJSON(record.filter { ["catalog", "key", "language", "variant"].contains($0.key) })) ?? Data(), as: UTF8.self)
                throw InspectionError("Cannot validate \(context): \(error)")
            }
        }
        if !dryRun && !changes.isEmpty {
            for change in changes {
                guard try catalogPath(change.catalog, beneath: root) == catalogPaths[change.catalog] else {
                    throw InspectionError("Catalog path changed during import. Restore the catalog layout and export again before retrying.")
                }
            }
            let paths = Set(changes.map { catalogPaths[$0.catalog]! })
            guard paths.count == 1 else {
                throw InspectionError("Applying changes to multiple catalogs is not available yet. Use --dry-run for a complete preview, then return records for one catalog at a time.")
            }
            let path = paths.first!
            let inspection = inspections[path]!
            let snapshot = inspection.contents.values.first!
            var document = inspection.documents.values.first!
            for change in changes {
                let keys = ["strings", change.key, "localizations", change.language] +
                    change.variant.flatMap { ["variations", $0.dimension, $0.value] }
                setTranslation(in: &document, path: keys[...],
                               leaf: ["stringUnit": ["value": change.translation, "state": change.status]])
            }
            let output = try JSONSerialization.data(withJSONObject: document,
                                                    options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]) + Data("\n".utf8)
            try writer.replace(path, original: snapshot, updated: output)
        }
        return ImportResult(dryRun: dryRun, changes: changes)
    }
}

func readHandoff(_ path: String) throws -> Data {
    do { return try path == "-" ? FileHandle.standardInput.readToEnd() ?? Data() : Data(contentsOf: URL(fileURLWithPath: path)) }
    catch { throw InspectionError("Cannot read the translation file or companion manifest: \(error.localizedDescription). Check the file path and read permissions. For translation input from stdin, use '-'; manifests must be files.") }
}

func handoffObject(_ data: Data) throws -> [String: Any] {
    guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
          let version = object["schemaVersion"], (try? canonicalJSON(version)) == Data("1".utf8) else {
        throw InspectionError("Malformed JSON or unsupported schemaVersion. Export a fresh JSON translation file or companion manifest (schema version 1).")
    }
    return object
}

private func jsonRecords(_ data: Data) throws -> [[String: Any]] {
    let object = try handoffObject(data)
    guard Set(object.keys) == ["schemaVersion", "units"], let records = object["units"] as? [[String: Any]] else {
        throw InspectionError("Invalid JSON translation file fields. Supply schemaVersion and a units array from export.")
    }
    return records
}

func validateRecord(_ record: [String: Any]) throws {
    let fields: Set<String> = ["schemaVersion", "catalog", "key", "language", "variant", "sourceLanguage", "source", "developerComments", "status", "originalTranslation", "originalDestination", "sourceFingerprint", "destinationFingerprint", "recordFingerprint", "translation", "statusUpdate"]
    guard Set(record.keys) == fields,
          (try? canonicalJSON(record["schemaVersion"]!)) == Data("1".utf8),
          ["catalog", "key", "language", "sourceLanguage", "status", "translation", "statusUpdate", "sourceFingerprint", "destinationFingerprint", "recordFingerprint"].allSatisfy({ record[$0] is String }),
          let variants = record["variant"] as? [[String: String]],
          validVariants(variants),
          let sources = record["source"] as? [[String: Any]], !sources.isEmpty,
          sources.allSatisfy({ Set($0.keys) == ["variant", "text"] && ($0["variant"] as? [[String: String]]).map(validVariants) == true && $0["text"] is String }),
          record["developerComments"] is NSNull || record["developerComments"] is String,
          record["originalTranslation"] is NSNull || record["originalTranslation"] is String,
          ["missing", "new", "needs_review", "translated"].contains(record["status"] as! String),
          ["", "new", "needs_review", "translated"].contains(record["statusUpdate"] as! String) else {
        throw InspectionError("Invalid record fields, version, or statusUpdate. Restore the exported record; edit only translation and statusUpdate.")
    }
    let status = record["status"] as! String
    let original = record["originalTranslation"] as? String
    let destination = record["originalDestination"]!
    let node = destination as? [String: Any]
    let validDestination: Bool
    if status == "missing" {
        validDestination = original == nil && (destination is NSNull || node?.isEmpty == true)
    } else if let node, Set(node.keys) == ["stringUnit"], let unit = node["stringUnit"] as? [String: Any] {
        validDestination = Set(unit.keys) == ["state", "value"] && unit["state"] as? String == status &&
            original != nil && unit["value"] as? String == original
    } else { validDestination = false }
    let validHashes = ["sourceFingerprint", "destinationFingerprint", "recordFingerprint"].allSatisfy {
        let value = record[$0] as! String
        return value.utf8.count == 64 && value.utf8.allSatisfy { (48...57).contains($0) || (97...102).contains($0) }
    }
    guard validDestination, validHashes, !(record["language"] as! String).isEmpty,
          !(record["sourceLanguage"] as! String).isEmpty else {
        throw InspectionError("Invalid original destination or fingerprint fields. Restore the exported record and retry.")
    }
    let protected = record.filter { !["recordFingerprint", "translation", "statusUpdate"].contains($0.key) }
    guard try fingerprint(protected) == record["recordFingerprint"] as! String,
          try fingerprint(record["originalDestination"]!) == record["destinationFingerprint"] as! String else {
        throw InspectionError("Protected-field changes detected. Restore the exported JSON translation file and edit only translation and statusUpdate.")
    }
}

private func catalogPath(_ identity: String, beneath root: URL) throws -> URL {
    let components = identity.split(separator: "/", omittingEmptySubsequences: false)
    guard !identity.isEmpty, !identity.contains("\0"), !identity.contains("\\"),
          components.allSatisfy({ !$0.isEmpty && $0 != "." && $0 != ".." }),
          identity.hasSuffix(".xcstrings") else {
        throw InspectionError("Invalid catalog identity; use an exported relative .xcstrings path without traversal.")
    }
    let path = root.appendingPathComponent(identity).standardizedFileURL.resolvingSymlinksInPath()
    guard path.path.hasPrefix(root.path == "/" ? "/" : root.path + "/") else {
        throw InspectionError("Catalog path escapes destination through a symlink. Restore the catalog beneath --destination and export again.")
    }
    let properties = try? path.resourceValues(forKeys: [.isRegularFileKey])
    guard properties?.isRegularFile == true else {
        throw InspectionError("Catalog identity is not a readable regular file. Restore the .xcstrings file beneath --destination.")
    }
    return path
}

private func validVariants(_ variants: [[String: String]]) -> Bool {
    variants.allSatisfy {
        Set($0.keys) == ["dimension", "value"] && ["plural", "device"].contains($0["dimension"]!) && !$0["value"]!.isEmpty
    } && Set(variants.map { $0["dimension"]! }).count == variants.count
}

private func setTranslation(in object: inout [String: Any], path: ArraySlice<String>, leaf: [String: Any]) {
    guard let key = path.first else { object = leaf; return }
    var child = object[key] as? [String: Any] ?? [:]
    setTranslation(in: &child, path: path.dropFirst(), leaf: leaf)
    object[key] = child
}
