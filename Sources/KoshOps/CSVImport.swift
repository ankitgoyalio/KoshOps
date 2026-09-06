import Foundation

func csvRecords(_ data: Data, manifest: String, statusUpdate: String?) throws -> [[String: Any]] {
    guard manifest != "-" else { throw InspectionError("CSV stdin needs a separate manifest file. Supply --manifest PATH.") }
    let object = try handoffObject(readHandoff(manifest))
    guard Set(object.keys) == ["schemaVersion", "kind", "entries"], object["kind"] as? String == "vendorManifest",
          let entries = object["entries"] as? [[String: Any]] else {
        throw InspectionError("Invalid CSV manifest. Use the original companion JSON manifest created by the CSV export.")
    }
    var originals: [String: [String: Any]] = [:]
    for entry in entries {
        guard Set(entry.keys) == ["id", "source", "context", "record"], let id = entry["id"] as? String,
              entry["source"] is String, entry["context"] is String,
              let record = entry["record"] as? [String: Any] else {
            throw InspectionError("Malformed manifest entry. Restore the original companion manifest.")
        }
        try validateRecord(record)
        guard id == "u-" + (record["recordFingerprint"] as! String), originals[id] == nil,
              record["statusUpdate"] as? String == "",
              record["translation"] as? String == ((record["originalTranslation"] as? String) ?? "") else {
            throw InspectionError("Duplicate or edited manifest entry '\(id)'. Restore the original companion manifest.")
        }
        // Rebuild protected display cells too: the manifest is not an editable side channel.
        let cells = vendorCells(record)
        guard entry["source"] as? String == cells.source, entry["context"] as? String == cells.context else {
            throw InspectionError("Protected manifest context changed for '\(id)'. Restore the original manifest.")
        }
        originals[id] = entry
    }
    let rows = try parseCSV(data)
    guard rows.first == ["id", "language", "source", "context", "translation"] else {
        throw InspectionError("Invalid CSV header. Retain id,language,source,context,translation in that order.")
    }
    var seen = Set<String>()
    var records: [[String: Any]] = []
    for (offset, row) in rows.dropFirst().enumerated() {
        guard row.count == 5 else { throw InspectionError("CSV row \(offset + 2) must have five columns. Restore the exported columns and CSV quoting.") }
        guard let entry = originals[row[0]], seen.insert(row[0]).inserted else {
            throw InspectionError("Unknown or duplicate CSV id at row \(offset + 2). Restore original IDs and keep one row per unit.")
        }
        var record = entry["record"] as! [String: Any]
        guard row[1] == record["language"] as! String, row[2] == entry["source"] as! String, row[3] == entry["context"] as! String else {
            throw InspectionError("Protected CSV cells changed at row \(offset + 2) (\(row[0])). Restore language, source, and context; edit only translation.")
        }
        if row[4] != record["translation"] as! String { record["statusUpdate"] = statusUpdate ?? "" }
        record["translation"] = row[4]
        records.append(record)
    }
    return records
}

private func parseCSV(_ data: Data) throws -> [[String]] {
    guard let text = String(data: data, encoding: .utf8) else { throw InspectionError("CSV is not UTF-8. Save it as UTF-8 and retry.") }
    let characters = Array(text.unicodeScalars)
    var rows: [[String]] = [], row: [String] = []
    var cell = "", quoted = false, closed = false, started = false
    var index = 0
    func malformed() -> InspectionError { InspectionError("Malformed CSV quoting near row \(rows.count + 1). Save valid quoted CSV and retry.") }
    while index < characters.count {
        let char = characters[index]
        if quoted {
            if char == "\"" {
                if index + 1 < characters.count && characters[index + 1] == "\"" {
                    cell.append("\""); index += 1
                } else { quoted = false; closed = true }
            } else { cell.unicodeScalars.append(char) }
        } else if char == "," {
            row.append(cell); cell = ""; closed = false; started = false
        } else if char == "\r" || char == "\n" {
            row.append(cell); rows.append(row); row = []; cell = ""; closed = false; started = false
            if char == "\r" && index + 1 < characters.count && characters[index + 1] == "\n" { index += 1 }
        } else if char == "\"" {
            guard !started && !closed else { throw malformed() }
            quoted = true; started = true
        } else {
            guard !closed else { throw malformed() }
            cell.unicodeScalars.append(char); started = true
        }
        index += 1
    }
    guard !quoted else { throw malformed() }
    if started || closed || !row.isEmpty { row.append(cell); rows.append(row) }
    return rows
}
