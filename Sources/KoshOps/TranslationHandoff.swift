import CryptoKit
import Foundation

enum HandoffFormat: String {
    case json, csv
}

struct TranslationExport {
    let data: Data?
    let manifestPath: String?
}

private struct SourceKey: Hashable {
    let catalog: String
    let key: String
}

extension LocalizationWorkflow {
    /// Builds and validates the complete handoff before publishing any bytes.
    /// An empty language list means all catalog languages except their sources.
    func export(paths: [String], languages: [String], statuses: [String], format: HandoffFormat,
                output: String, manifest: String?, overwrite: Bool) throws -> TranslationExport {
        guard format != .csv || output != "-" || manifest != nil else {
            throw InspectionError("CSV on stdout requires a companion manifest. Supply --manifest PATH or --output translations.csv.")
        }
        guard format == .csv || manifest == nil else {
            throw InspectionError("--manifest is only used with CSV. Use --format csv or omit --manifest for JSON export.")
        }
        let manifestPath = manifest ?? output + ".manifest.json"
        guard manifestPath != "-" else {
            throw InspectionError("The manifest must be retained as a file. Supply --manifest PATH; stdout is reserved for CSV.")
        }
        let inspection = try inspect(paths: paths)
        let unknown = Set(languages).subtracting(inspection.catalogs.flatMap { $0.languages.map(\.language) })
        guard unknown.isEmpty else {
            throw InspectionError("Unknown catalog language(s): \(unknown.sorted().joined(separator: ", ")). Run 'koshops strings languages' to see available languages.")
        }
        let selectedStatuses = statuses.isEmpty ? ["missing", "new", "needs_review"] : statuses
        let sourceLanguages = Dictionary(uniqueKeysWithValues: inspection.catalogs.map { ($0.catalog, $0.sourceLanguage) })
        let sources = Dictionary(grouping: inspection.units.filter { $0.language == sourceLanguages[$0.catalog] }) {
            SourceKey(catalog: $0.catalog, key: $0.key)
        }
        var records: [[String: Any]] = []
        for unit in inspection.units where !unit.excluded && (languages.isEmpty || languages.contains(unit.language)) {
            let document = inspection.documents[unit.catalog]!
            let sourceLanguage = document["sourceLanguage"] as! String
            if unit.language == sourceLanguage { continue }
            guard unit.status != .unsupported else {
                throw handoffError(unit, unit.issue ?? "Unsupported translation structure.")
            }
            if !selectedStatuses.contains(unit.status.rawValue) { continue }
            let entry = (document["strings"] as! [String: Any])[unit.key] as! [String: Any]
            guard entry["comment"] == nil || entry["comment"] is String else {
                throw handoffError(unit, "The developer comment is not text.")
            }
            let sourceUnits = sources[SourceKey(catalog: unit.catalog, key: unit.key)] ?? []
            guard !sourceUnits.isEmpty, sourceUnits.allSatisfy({ $0.value != nil && $0.status != .unsupported }) else {
                throw handoffError(unit, "Source context contains missing or unsupported structures.")
            }
            let source: [[String: Any]] = sourceUnits.map {
                ["variant": variantIdentity($0.variant), "text": $0.value!]
            }
            let localizations = entry["localizations"] as? [String: Any] ?? [:]
            if unit.status == .missing && unit.variant.isEmpty && localizations.values.contains(where: {
                guard let node = $0 as? [String: Any] else { return true }
                return node["variations"] != nil || node["substitutions"] != nil
            }) {
                throw handoffError(unit, "Missing destination structure cannot safely be inferred from other localizations.")
            }
            var destination: Any = localizations[unit.language] ?? NSNull()
            for variant in unit.variant {
                destination = ((destination as? [String: Any])?["variations"] as? [String: Any])?[variant.dimension]
                    .flatMap { ($0 as? [String: Any])?[variant.value] } ?? NSNull()
            }
            let sourceContext: [String: Any] = [
                "sourceLanguage": sourceLanguage, "source": source,
                "sourceLocalization": localizations[sourceLanguage] ?? NSNull(),
                "developerComments": entry["comment"] ?? NSNull()
            ]
            var record: [String: Any] = [
                "schemaVersion": 1, "catalog": unit.catalog, "key": unit.key, "language": unit.language,
                "variant": variantIdentity(unit.variant), "sourceLanguage": sourceLanguage, "source": source,
                "developerComments": entry["comment"] ?? NSNull(), "status": unit.status.rawValue,
                "originalTranslation": unit.value as Any? ?? NSNull(),
                "originalDestination": destination,
                "sourceFingerprint": try fingerprint(sourceContext),
                "destinationFingerprint": try fingerprint(destination)
            ]
            record["recordFingerprint"] = try fingerprint(record)
            record["translation"] = unit.value ?? ""
            record["statusUpdate"] = ""
            records.append(record)
        }
        if format == .json {
            let data = try canonicalJSON(["schemaVersion": 1, "units": records]) + Data("\n".utf8)
            if output != "-" { try publishExport([ExportFile(path: output, data: data, fileExtension: "json")], overwrite: overwrite) }
            return TranslationExport(data: output == "-" ? data : nil, manifestPath: nil)
        }
        let handoff = try vendorHandoff(records)
        var outputs = [ExportFile(path: manifestPath, data: handoff.manifest, fileExtension: "json")]
        if output != "-" { outputs.append(ExportFile(path: output, data: handoff.csv, fileExtension: "csv")) }
        try publishExport(outputs, overwrite: overwrite)
        return TranslationExport(data: output == "-" ? handoff.csv : nil, manifestPath: manifestPath)
    }
}

private func handoffError(_ unit: TranslationUnit, _ reason: String) -> InspectionError {
    InspectionError("Cannot export '\(unit.catalog)' key '\(unit.key)' language '\(unit.language)' variant '\(unit.variant.map { "\($0.dimension)=\($0.value)" }.joined(separator: "/"))': \(reason) Inspect this entry in Xcode or select other languages/statuses.")
}

private func variantIdentity(_ variants: [Variant]) -> [[String: String]] {
    variants.map { ["dimension": $0.dimension, "value": $0.value] }
}

private func canonicalJSON(_ value: Any) throws -> Data {
    try JSONSerialization.data(withJSONObject: value, options: [.sortedKeys, .withoutEscapingSlashes, .fragmentsAllowed])
}

private func fingerprint(_ value: Any) throws -> String {
    SHA256.hash(data: try canonicalJSON(value)).map { String(format: "%02x", $0) }.joined()
}

/// Render readable context without requiring vendors to edit or understand JSON.
private func variantLabel(_ variant: [[String: String]]) -> String {
    variant.map { "\($0["dimension"]!)=\($0["value"]!)" }.joined(separator: "/")
}

private func vendorHandoff(_ records: [[String: Any]]) throws -> (csv: Data, manifest: Data) {
    var rows = [["id", "language", "source", "context", "translation"]]
    var entries: [[String: Any]] = []
    for record in records {
        let id = "u-" + (record["recordFingerprint"] as! String)
        let sourceUnits = record["source"] as! [[String: Any]]
        let source = sourceUnits.map { unit in
            let label = variantLabel(unit["variant"] as! [[String: String]])
            let text = unit["text"] as! String
            return label.isEmpty ? text : "[\(label)] \(text)"
        }.joined(separator: "\n")
        let variant = variantLabel(record["variant"] as! [[String: String]])
        var context: [String] = []
        if !variant.isEmpty { context.append("Target variant: " + variant) }
        if let comment = record["developerComments"] as? String, !comment.isEmpty { context.append(comment) }
        let contextText = context.joined(separator: "\n")
        rows.append([id, record["language"] as! String, source, contextText, record["translation"] as! String])
        entries.append(["id": id, "source": source, "context": contextText, "record": record])
    }
    func quote(_ value: String) -> String { "\"" + value.replacingOccurrences(of: "\"", with: "\"\"") + "\"" }
    let csv = rows.map { $0.map(quote).joined(separator: ",") }.joined(separator: "\r\n") + "\r\n"
    let manifest = try canonicalJSON(["schemaVersion": 1, "kind": "vendorManifest", "entries": entries]) + Data("\n".utf8)
    return (Data(csv.utf8), manifest)
}
