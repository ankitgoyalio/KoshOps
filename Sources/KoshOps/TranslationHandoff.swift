import CryptoKit
import Foundation

enum HandoffFormat: String {
    case json, csv
}

private struct SourceKey: Hashable {
    let catalog: String
    let key: String
}

extension LocalizationWorkflow {
    /// Builds and validates the complete handoff before publishing any bytes.
    /// An empty language list means all catalog languages except their sources.
    func export(paths: [String], languages: [String], statuses: [String], format: HandoffFormat,
                output: String, overwrite: Bool) throws -> Data? {
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
        let data: Data
        switch format {
        case .json:
            data = try canonicalJSON(["schemaVersion": 1, "units": records]) + Data("\n".utf8)
        case .csv:
            data = try handoffCSV(records)
        }
        if output == "-" { return data }
        let url = URL(fileURLWithPath: output).standardizedFileURL
        // Atomic replacement preserves other hard links; reject catalog paths and symlinks.
        if url.pathExtension == "xcstrings" {
            throw InspectionError("Output '\(output)' is a catalog path. Choose a .json or .csv handoff file.")
        }
        do {
            if (try? url.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink) == true {
                throw InspectionError("Output is a symbolic link. Choose a regular handoff file.")
            }
            if overwrite {
                try data.write(to: url, options: [.atomic])
            } else {
                // Publish a complete file with an exclusive link, so a race cannot
                // replace an existing handoff or expose a partially written export.
                let staging = url.deletingLastPathComponent().appendingPathComponent(".koshops-export-" + UUID().uuidString)
                defer { try? FileManager.default.removeItem(at: staging) }
                try data.write(to: staging, options: [.withoutOverwriting])
                try FileManager.default.linkItem(at: staging, to: url)
            }
        } catch {
            throw InspectionError("Cannot write export '\(output)': \(error). Choose a writable new path or use --overwrite to replace an existing handoff.")
        }
        return nil
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

private func handoffCSV(_ records: [[String: Any]]) throws -> Data {
    let columns = ["schemaVersion", "catalog", "key", "language", "variant", "sourceLanguage", "source", "developerComments", "status", "originalTranslation", "originalDestination", "sourceFingerprint", "destinationFingerprint", "recordFingerprint", "translation", "statusUpdate"]
    let jsonColumns: Set<String> = ["variant", "source", "developerComments", "originalTranslation", "originalDestination"]
    func quote(_ value: String) -> String { "\"" + value.replacingOccurrences(of: "\"", with: "\"\"") + "\"" }
    var rows = [columns.joined(separator: ",")]
    for record in records {
        rows.append(try columns.map { column in
            let value = record[column]!
            let text = jsonColumns.contains(column)
                ? String(decoding: try canonicalJSON(value), as: UTF8.self) : String(describing: value)
            return quote(text)
        }.joined(separator: ","))
    }
    return Data((rows.joined(separator: "\r\n") + "\r\n").utf8)
}
