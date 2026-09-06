import Foundation
import CryptoKit
import Testing

private let importCatalog = #"{"version":"1.0","sourceLanguage":"en","strings":{"Hello":{"localizations":{"fr":{"stringUnit":{"state":"translated","value":"Bonjour"}}}},"Missing":{}}}"#

private func handoff(_ fixture: Fixture) throws -> [[String: Any]] {
    let result = try fixture.run(["strings", "export", ".", "--language", "fr", "--status", "translated", "--status", "missing"])
    #expect(result.status == 0)
    let object = try #require(JSONSerialization.jsonObject(with: Data(result.out.utf8)) as? [String: Any])
    return try #require(object["units"] as? [[String: Any]])
}

private func encoded(_ records: [[String: Any]]) throws -> String {
    String(decoding: try JSONSerialization.data(withJSONObject: ["schemaVersion": 1, "units": records]), as: UTF8.self)
}

@Test func importPreviewsExplicitTextAndStatusWithoutWriting() throws {
    let fixture = try Fixture()
    defer { fixture.remove() }
    try fixture.write("Labels.xcstrings", importCatalog)
    var records = try handoff(fixture)
    records[0]["translation"] = "Salut"
    records[0]["statusUpdate"] = "needs_review"
    let result = try fixture.run(["strings", "import", "-", "--dry-run", "--json", "--no-input"], stdin: encoded(records))
    #expect(result.status == 0)
    #expect(result.err.isEmpty)
    if result.status == 0 {
        let report = try #require(JSONSerialization.jsonObject(with: Data(result.out.utf8)) as? [String: Any])
        let changes = try #require(report["changes"] as? [[String: Any]])
        #expect(changes.count == 1)
        #expect(changes.first?["translation"] as? String == "Salut")
        #expect(changes.first?["status"] as? String == "needs_review")
    }
    #expect(try String(contentsOf: fixture.root.appendingPathComponent("Labels.xcstrings"), encoding: .utf8) == importCatalog)
}

private func preview(_ fixture: Fixture, _ records: [[String: Any]]) throws -> (status: Int32, out: String, err: String) {
    try fixture.write("handoff.json", encoded(records))
    let result = try fixture.run(["strings", "import", "handoff.json", "--dry-run", "--json"])
    #expect(try String(contentsOf: fixture.root.appendingPathComponent("Labels.xcstrings"), encoding: .utf8) == importCatalog)
    return result
}

@Test func importStatusOnlyMissingUnchangedAndOmittedRecords() throws {
    let fixture = try Fixture()
    defer { fixture.remove() }
    try fixture.write("Labels.xcstrings", importCatalog)
    var records = try handoff(fixture)
    #expect(try preview(fixture, records).out.contains("\"changes\":[]"))
    #expect(try preview(fixture, []).status == 0)
    records[0]["statusUpdate"] = "needs_review"
    records[1]["translation"] = "Manquant"
    records[1]["statusUpdate"] = "new"
    let result = try preview(fixture, records)
    #expect(result.status == 0)
    let object = try #require(JSONSerialization.jsonObject(with: Data(result.out.utf8)) as? [String: Any])
    let changes = try #require(object["changes"] as? [[String: Any]])
    #expect(changes.count == 2)
    #expect(changes[0]["translation"] as? String == "Bonjour")
    #expect(changes[1]["originalStatus"] as? String == "missing")
}

@Test(arguments: ["approval", "empty", "status", "protected", "duplicate", "version", "field"])
func importRejectsInvalidRecordsBeforeAnyPreview(_ reason: String) throws {
    let fixture = try Fixture()
    defer { fixture.remove() }
    try fixture.write("Labels.xcstrings", importCatalog)
    var records = try handoff(fixture)
    records[0]["translation"] = "Salut"
    records[0]["statusUpdate"] = "new"
    switch reason {
    case "approval": records[0]["statusUpdate"] = ""
    case "empty": records[0]["translation"] = ""
    case "status": records[0]["statusUpdate"] = "missing"
    case "protected": records[1]["developerComments"] = "edited"
    case "duplicate": records.append(records[0])
    case "version": records[1]["schemaVersion"] = 2
    default: records[1]["extra"] = true
    }
    let result = try preview(fixture, records)
    #expect(result.status == 1)
    #expect(result.out.isEmpty)
    #expect(!result.err.isEmpty)
    #expect(result.err.contains("Labels.xcstrings"))
}

@Test(arguments: ["source", "destination", "unrelated", "unchanged"])
func importScopesStaleConflictsToAffectedRecords(_ edit: String) throws {
    let fixture = try Fixture()
    defer { fixture.remove() }
    try fixture.write("Labels.xcstrings", importCatalog)
    var records = try handoff(fixture)
    if edit != "unchanged" { records[0]["translation"] = "Salut"; records[0]["statusUpdate"] = "new" }
    let changed: String
    switch edit {
    case "source": changed = importCatalog.replacingOccurrences(of: "\"Hello\":{", with: "\"Hello\":{\"comment\":\"New context\",")
    case "destination", "unchanged": changed = importCatalog.replacingOccurrences(of: "Bonjour", with: "Coucou")
    default: changed = importCatalog.replacingOccurrences(of: "\"Missing\":{}", with: "\"Missing\":{\"comment\":\"unrelated\"}")
    }
    try fixture.write("Labels.xcstrings", changed)
    let result = try fixture.run(["strings", "import", "--dry-run", "--json"], stdin: encoded(records))
    #expect(result.status == (["source", "destination"].contains(edit) ? 1 : 0))
    if result.status != 0 { #expect(result.out.isEmpty); #expect(result.err.contains("Stale")); #expect(result.err.contains("export")) }
    #expect(try String(contentsOf: fixture.root.appendingPathComponent("Labels.xcstrings"), encoding: .utf8) == changed)
}

@Test(arguments: [
    ("%@ has %d", "%2$d pour %1$@", true),
    ("%@ has %d", "%d pour %@", false),
    ("%lld", "%d", false),
    ("%*.*f", "%3$*1$.*2$f", true),
    ("%*d", "%d", false),
    ("%% %@", "%@ %%", true),
    ("%@", "%s", false),
    ("%d", "%Ld", false),
    ("%d", "%u", false),
    ("%f", "%lf", true),
    ("%.f", "%.0f", true),
    ("%@", "%L@", false),
    ("%2$@", "%2$@ changed", false),
    ("%d", "%1$*1$d", true),
    ("%D", "%d", true),
    ("%qd", "%lld", true),
    ("%lld", "%Lld", false),
    ("%c", "%Lc", false),
    ("%f", "%llf", false),
    ("%s", "%Ls", false),
    ("%@", "%9223372036854775807$@", false)
])
func importValidatesPlaceholderArguments(_ source: String, _ translation: String, _ success: Bool) throws {
    let fixture = try Fixture()
    defer { fixture.remove() }
    let document: [String: Any] = ["version": "1.0", "sourceLanguage": "en", "strings": [source: ["localizations": ["fr": ["stringUnit": ["state": "translated", "value": source]]]]]]
    let original = String(decoding: try JSONSerialization.data(withJSONObject: document), as: UTF8.self)
    try fixture.write("Labels.xcstrings", original)
    var records = try handoff(fixture)
    records[0]["translation"] = translation
    records[0]["statusUpdate"] = "needs_review"
    let result = try fixture.run(["strings", "import", "-", "--dry-run"], stdin: encoded(records))
    #expect(result.status == (success ? 0 : 1))
    if !success { #expect(result.out.isEmpty); #expect(result.err.contains("placeholder")) }
    #expect(try String(contentsOf: fixture.root.appendingPathComponent("Labels.xcstrings"), encoding: .utf8) == original)
}

private func csv(_ rows: [[String]]) -> String {
    rows.map { $0.map { "\"" + $0.replacingOccurrences(of: "\"", with: "\"\"") + "\"" }.joined(separator: ",") }.joined(separator: "\r\n") + "\r\n"
}

private func vendorRows(_ fixture: Fixture) throws -> [[String]] {
    let export = try fixture.run(["strings", "export", ".", "--language", "fr", "--status", "translated", "--status", "missing", "--format", "csv", "-o", "vendor.csv"])
    #expect(export.status == 0)
    let data = try Data(contentsOf: fixture.root.appendingPathComponent("vendor.csv.manifest.json"))
    let object = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
    let entries = try #require(object["entries"] as? [[String: Any]])
    return [["id", "language", "source", "context", "translation"]] + entries.map { entry in
        let record = entry["record"] as! [String: Any]
        return [entry["id"] as! String, record["language"] as! String, entry["source"] as! String, entry["context"] as! String, record["translation"] as! String]
    }
}

@Test func importCSVMatchesJSONWithQuotedUnicodeAndStdin() throws {
    let fixture = try Fixture()
    defer { fixture.remove() }
    try fixture.write("Labels.xcstrings", importCatalog)
    var rows = try vendorRows(fixture)
    let translation = "Salut, \"été\"\r\n世界"
    rows[1][4] = translation
    var records = try handoff(fixture)
    records[0]["translation"] = translation
    records[0]["statusUpdate"] = "needs_review"
    let json = try preview(fixture, records)
    let result = try fixture.run(["strings", "import", "-", "--format", "csv", "--manifest", "vendor.csv.manifest.json", "--status-update", "needs_review", "--dry-run", "--json"], stdin: csv(rows))
    #expect(result.status == 0)
    #expect(result.err.isEmpty)
    #expect(result.out == json.out)
    #expect(try String(contentsOf: fixture.root.appendingPathComponent("Labels.xcstrings"), encoding: .utf8) == importCatalog)
}

@Test(arguments: ["approval", "protected", "duplicate", "unknown", "empty", "quoting", "header", "omitted", "unchanged"])
func importCSVValidatesEveryRow(_ edit: String) throws {
    let fixture = try Fixture()
    defer { fixture.remove() }
    try fixture.write("Labels.xcstrings", importCatalog)
    var rows = try vendorRows(fixture)
    rows[1][4] = "Salut"
    switch edit {
    case "protected": rows[2][2] = "changed source"
    case "duplicate": rows.append(rows[1])
    case "unknown": rows[1][0] = "unknown"
    case "empty": rows[1][4] = ""
    case "header": rows[0][0] = "key"
    case "omitted": rows = [rows[0]]
    case "unchanged": rows[1][4] = "Bonjour"
    default: break
    }
    let body = edit == "quoting" ? csv(rows) + "\"unclosed" : csv(rows)
    try fixture.write("returned.csv", body)
    var args = ["strings", "import", "returned.csv", "--format", "csv", "--manifest", "vendor.csv.manifest.json", "--dry-run", "--json"]
    if edit != "approval" { args += ["--status-update", "new"] }
    let result = try fixture.run(args)
    #expect(result.status == (["omitted", "unchanged"].contains(edit) ? 0 : 1))
    if result.status != 0 { #expect(result.out.isEmpty); #expect(!result.err.isEmpty) }
    else { #expect(result.out.contains("\"changes\":[]")) }
    #expect(try String(contentsOf: fixture.root.appendingPathComponent("Labels.xcstrings"), encoding: .utf8) == importCatalog)
}

@Test func importHelpIncompleteAndApplicationUnavailable() throws {
    let fixture = try Fixture()
    defer { fixture.remove() }
    for flag in ["-h", "--help"] {
        let result = try fixture.run(["strings", "import", flag])
        #expect(result.status == 0)
        #expect(result.out.contains("--dry-run"))
        #expect(result.out.contains("--destination"))
    }
    #expect(try fixture.run(["strings", "import"]).out.contains("USAGE:"))
    let result = try fixture.run(["strings", "import", "nonexistent.json"])
    #expect(result.status == 64)
    #expect(result.out.isEmpty)
    #expect(result.err.contains("not available"))
    #expect(try fixture.run(["strings", "import", "-", "--dry-run"], stdin: "not json").status == 1)
    #expect(try fixture.run(["strings", "import", "-", "--dry-run"], stdin: "{\"schemaVersion\":true,\"units\":[]}").status == 1)
}

@Test(arguments: ["success", "lateConflict", "symlink"])
func importMultiCatalogDestinationAndImmutability(_ mode: String) throws {
    let fixture = try Fixture()
    let outside = try Fixture()
    defer { fixture.remove(); outside.remove() }
    try fixture.write("A/Labels.xcstrings", importCatalog)
    try fixture.write("B/Labels.xcstrings", importCatalog)
    var records = try handoff(fixture)
    for index in records.indices where records[index]["key"] as? String == "Hello" {
        records[index]["translation"] = "Salut"
        records[index]["statusUpdate"] = "new"
    }
    let changed = mode == "lateConflict" ? importCatalog.replacingOccurrences(of: "Bonjour", with: "Coucou") : importCatalog
    try fixture.write("B/Labels.xcstrings", changed)
    if mode == "symlink" {
        try outside.write("Labels.xcstrings", importCatalog)
        try FileManager.default.removeItem(at: fixture.root.appendingPathComponent("B"))
        try FileManager.default.createSymbolicLink(at: fixture.root.appendingPathComponent("B"), withDestinationURL: outside.root)
    }
    let result = try outside.run(["strings", "import", "-", "--destination", fixture.root.path, "--dry-run", "--json"], stdin: encoded(records))
    #expect(result.status == (mode == "success" ? 0 : 1))
    if mode == "success" {
        let object = try #require(JSONSerialization.jsonObject(with: Data(result.out.utf8)) as? [String: Any])
        let changes = try #require(object["changes"] as? [[String: Any]])
        #expect(changes.compactMap { $0["catalog"] as? String } == ["A/Labels.xcstrings", "B/Labels.xcstrings"])
    } else { #expect(result.out.isEmpty) }
    if mode == "symlink" { #expect(result.err.contains("symlink")) }
    #expect(try String(contentsOf: fixture.root.appendingPathComponent("A/Labels.xcstrings"), encoding: .utf8) == importCatalog)
    #expect(try String(contentsOf: fixture.root.appendingPathComponent("B/Labels.xcstrings"), encoding: .utf8) == changed)
}

@Test(arguments: ["key", "language", "excluded", "unsupported", "missingStructure"])
func importRejectsIneligibleLiveDestinations(_ mode: String) throws {
    let fixture = try Fixture()
    defer { fixture.remove() }
    try fixture.write("Labels.xcstrings", importCatalog)
    var records = try handoff(fixture)
    records[0]["translation"] = "Salut"; records[0]["statusUpdate"] = "new"
    var object = try #require(JSONSerialization.jsonObject(with: Data(importCatalog.utf8)) as? [String: Any])
    var strings = object["strings"] as! [String: Any]
    switch mode {
    case "key": strings.removeValue(forKey: "Hello")
    case "language": strings["Hello"] = [:] as [String: Any]
    case "excluded":
        var entry = strings["Hello"] as! [String: Any]; entry["shouldTranslate"] = false; strings["Hello"] = entry
    case "unsupported": strings["Hello"] = ["localizations": ["fr": ["substitutions": [:]]]]
    default:
        strings["Missing"] = ["localizations": ["de": ["variations": ["plural": ["one": ["stringUnit": ["value": "Ein", "state": "new"]]]]]]]
        records = [records[1]]; records[0]["translation"] = "Manquant"; records[0]["statusUpdate"] = "new"
    }
    object["strings"] = strings
    let data = try JSONSerialization.data(withJSONObject: object)
    try data.write(to: fixture.root.appendingPathComponent("Labels.xcstrings"))
    let result = try fixture.run(["strings", "import", "-", "--dry-run", "--json"], stdin: encoded(records))
    #expect(result.status == 1)
    #expect(result.out.isEmpty)
    #expect(result.err.contains("Labels.xcstrings"))
    #expect(try Data(contentsOf: fixture.root.appendingPathComponent("Labels.xcstrings")) == data)
}

@Test func importPreservesVariantSiblingsAndUnrelatedUnsupportedContent() throws {
    let fixture = try Fixture()
    defer { fixture.remove() }
    let original = #"{"version":"1.0","sourceLanguage":"en","strings":{"Count":{"localizations":{"en":{"variations":{"plural":{"one":{"stringUnit":{"value":"%d item","state":"translated"}},"other":{"stringUnit":{"value":"%d items","state":"translated"}}}}},"fr":{"variations":{"plural":{"one":{"stringUnit":{"value":"%d objet","state":"new"}},"other":{"stringUnit":{"value":"%d objets","state":"translated"}}}}}}}}}"#
    try fixture.write("Labels.xcstrings", original)
    let result = try fixture.run(["strings", "export", "--language", "fr", "--status", "new"])
    let object = try #require(JSONSerialization.jsonObject(with: Data(result.out.utf8)) as? [String: Any])
    var records = object["units"] as! [[String: Any]]
    #expect(records.count == 1)
    records[0]["translation"] = "%d article"; records[0]["statusUpdate"] = "needs_review"
    let changed = original.replacingOccurrences(of: "%d objets", with: "%d autres").replacingOccurrences(of: "\"strings\":{", with: "\"strings\":{\"Unsupported\":{\"localizations\":{\"fr\":{\"substitutions\":{}}}},")
    try fixture.write("Labels.xcstrings", changed)
    let preview = try fixture.run(["strings", "import", "-", "--dry-run", "--json"], stdin: encoded(records))
    #expect(preview.status == 0)
    #expect(preview.out.contains("%d article"))
    #expect(try String(contentsOf: fixture.root.appendingPathComponent("Labels.xcstrings"), encoding: .utf8) == changed)
}

// Public checksums are deliberately recomputed to test semantic validation too.
private func resigned(_ record: [String: Any]) throws -> [String: Any] {
    var result = record
    let protected = record.filter { !["recordFingerprint", "translation", "statusUpdate"].contains($0.key) }
    let data = try JSONSerialization.data(withJSONObject: protected, options: [.sortedKeys, .withoutEscapingSlashes, .fragmentsAllowed])
    result["recordFingerprint"] = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    return result
}

@Test(arguments: ["/Labels.xcstrings", "../Labels.xcstrings", "A/../Labels.xcstrings", "./Labels.xcstrings", "A//Labels.xcstrings", "A\\Labels.xcstrings", "Labels.json"])
func importRejectsUnsafeIdentitiesEvenWithValidChecksums(_ path: String) throws {
    let fixture = try Fixture()
    defer { fixture.remove() }
    try fixture.write("Labels.xcstrings", importCatalog)
    var record = try handoff(fixture)[0]
    record["catalog"] = path
    record["translation"] = "Salut"; record["statusUpdate"] = "new"
    let result = try preview(fixture, [resigned(record)])
    #expect(result.status == 1)
    #expect(result.out.isEmpty)
    #expect(result.err.contains("Invalid catalog identity"))
}

@Test func importRejectsSourceLanguageEvenWithValidChecksum() throws {
    let fixture = try Fixture()
    defer { fixture.remove() }
    try fixture.write("Labels.xcstrings", importCatalog)
    var record = try handoff(fixture)[0]
    record["language"] = "en"
    record["translation"] = "Salut"; record["statusUpdate"] = "new"
    let result = try preview(fixture, [resigned(record)])
    #expect(result.status == 1)
    #expect(result.out.isEmpty)
    #expect(result.err.contains("Source-language"))
}

@Test func importRejectsMalformedManifestContextWithoutCrashing() throws {
    let fixture = try Fixture()
    defer { fixture.remove() }
    try fixture.write("Labels.xcstrings", importCatalog)
    let rows = try vendorRows(fixture)
    let path = fixture.root.appendingPathComponent("vendor.csv.manifest.json")
    var object = try #require(JSONSerialization.jsonObject(with: Data(contentsOf: path)) as? [String: Any])
    var entries = object["entries"] as! [[String: Any]]
    var record = entries[0]["record"] as! [String: Any]
    record["source"] = [["variant": [["unexpected": "plural"]], "text": "Hello"]]
    record = try resigned(record)
    entries[0]["record"] = record
    entries[0]["id"] = "u-" + (record["recordFingerprint"] as! String)
    object["entries"] = entries
    try JSONSerialization.data(withJSONObject: object).write(to: path)
    let result = try fixture.run(["strings", "import", "-", "--format", "csv", "--manifest", path.path, "--dry-run"], stdin: csv(rows))
    #expect(result.status == 1)
    #expect(result.out.isEmpty)
    #expect(result.err.contains("Invalid record"))
    #expect(try String(contentsOf: fixture.root.appendingPathComponent("Labels.xcstrings"), encoding: .utf8) == importCatalog)
}

@Test(arguments: ["source", "destination", "placeholder", "missing"])
func importCSVUsesTheSameLiveValidationAsJSON(_ mode: String) throws {
    let fixture = try Fixture()
    defer { fixture.remove() }
    try fixture.write("Labels.xcstrings", importCatalog)
    var rows = try vendorRows(fixture)
    rows[1][4] = mode == "placeholder" ? "Salut %@" : "Salut"
    if mode == "missing" { rows[2][4] = "Manquant" }
    var live = importCatalog
    if mode == "source" { live = live.replacingOccurrences(of: "\"Hello\":{", with: "\"Hello\":{\"comment\":\"Changed\",") }
    if mode == "destination" { live = live.replacingOccurrences(of: "Bonjour", with: "Coucou") }
    try fixture.write("Labels.xcstrings", live)
    let result = try fixture.run(["strings", "import", "-", "--format", "csv", "--manifest", "vendor.csv.manifest.json", "--status-update", "new", "--dry-run", "--json"], stdin: csv(rows))
    #expect(result.status == (mode == "missing" ? 0 : 1))
    if mode != "missing" { #expect(result.out.isEmpty); #expect(!result.err.isEmpty) }
    #expect(try String(contentsOf: fixture.root.appendingPathComponent("Labels.xcstrings"), encoding: .utf8) == live)
}

@Test func importRejectsDirectoryMasqueradingAsCatalog() throws {
    let fixture = try Fixture()
    defer { fixture.remove() }
    try fixture.write("Labels.xcstrings", importCatalog)
    var records = try handoff(fixture)
    records[0]["translation"] = "Salut"; records[0]["statusUpdate"] = "new"
    try FileManager.default.removeItem(at: fixture.root.appendingPathComponent("Labels.xcstrings"))
    try fixture.write("Labels.xcstrings/Nested.xcstrings", importCatalog)
    let result = try fixture.run(["strings", "import", "-", "--dry-run", "--json"], stdin: encoded(records))
    #expect(result.status == 1)
    #expect(result.out.isEmpty)
    #expect(result.err.contains("regular file"))
    #expect(try String(contentsOf: fixture.root.appendingPathComponent("Labels.xcstrings/Nested.xcstrings"), encoding: .utf8) == importCatalog)
}

@Test func importFillsAnExistingEmptyNestedVariantLeaf() throws {
    let fixture = try Fixture()
    defer { fixture.remove() }
    let original = #"{"version":"1.0","sourceLanguage":"en","strings":{"Hello":{"localizations":{"fr":{"variations":{"device":{"iphone":{"variations":{"plural":{"one":{},"other":{"stringUnit":{"state":"translated","value":"Bonjour"}}}}}}}}}}}}"#
    try fixture.write("Labels.xcstrings", original)
    var records = try handoff(fixture)
    records = records.filter { $0["status"] as? String == "missing" }
    #expect(records.count == 1)
    records[0]["translation"] = "Salut"; records[0]["statusUpdate"] = "new"
    let result = try fixture.run(["strings", "import", "-", "--dry-run", "--json"], stdin: encoded(records))
    #expect(result.status == 0)
    let object = try #require(JSONSerialization.jsonObject(with: Data(result.out.utf8)) as? [String: Any])
    let changes = try #require(object["changes"] as? [[String: Any]])
    #expect(changes.count == 1)
    #expect(changes[0]["variant"] as? [[String: String]] == [["dimension": "device", "value": "iphone"], ["dimension": "plural", "value": "one"]])
    #expect(try String(contentsOf: fixture.root.appendingPathComponent("Labels.xcstrings"), encoding: .utf8) == original)
}
