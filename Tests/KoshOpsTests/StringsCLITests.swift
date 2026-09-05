import Foundation
import Testing

private final class TestBundleMarker {}

private struct Fixture {
    let root: URL
    init() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }
    func write(_ path: String, _ text: String) throws {
        let url = root.appendingPathComponent(path)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(text.utf8).write(to: url)
    }
    func run(_ arguments: [String]) throws -> (status: Int32, out: String, err: String) {
        let process = Process()
        let executable = Bundle(for: TestBundleMarker.self).bundleURL.deletingLastPathComponent().appendingPathComponent("koshops")
        process.executableURL = executable
        process.arguments = arguments
        process.currentDirectoryURL = root
        process.standardInput = FileHandle.nullDevice
        let stdout = root.appendingPathComponent("stdout")
        let stderr = root.appendingPathComponent("stderr")
        FileManager.default.createFile(atPath: stdout.path, contents: nil)
        FileManager.default.createFile(atPath: stderr.path, contents: nil)
        let out = try FileHandle(forWritingTo: stdout)
        let err = try FileHandle(forWritingTo: stderr)
        process.standardOutput = out
        process.standardError = err
        try process.run()
        process.waitUntilExit()
        try out.close()
        try err.close()
        return (process.terminationStatus, try String(contentsOf: stdout, encoding: .utf8), try String(contentsOf: stderr, encoding: .utf8))
    }
    func remove() { try? FileManager.default.removeItem(at: root) }
}

private let catalog = #"""
{"version":"1.0","sourceLanguage":"en","strings":{
  "Hello":{"localizations":{"fr":{"stringUnit":{"state":"translated","value":"Bonjour"}}}},
  "New":{"localizations":{"fr":{"stringUnit":{"state":"new","value":"Nouveau"}}}},
  "Missing":{},
  "Excluded":{"shouldTranslate":false,"localizations":{"de":{"stringUnit":{"state":"new","value":"Nein"}}}}
}}
"""#

@Test func languageCoverageAndSource() throws {
    let fixture = try Fixture()
    defer { fixture.remove() }
    try fixture.write("Localizable.xcstrings", catalog)
    let result = try fixture.run(["strings", "languages", "--json", "--no-input"])
    #expect(result.status == 0)
    #expect(result.err.isEmpty)
    let json = try #require(JSONSerialization.jsonObject(with: Data(result.out.utf8)) as? [String: Any])
    #expect(json["schemaVersion"] as? Int == 1)
    let catalogs = try #require(json["catalogs"] as? [[String: Any]])
    let item = try #require(catalogs.first)
    #expect(item["catalog"] as? String == "Localizable.xcstrings")
    #expect(item["sourceLanguage"] as? String == "en")
    let languages = try #require(item["languages"] as? [[String: Any]])
    let french = try #require(languages.first { $0["language"] as? String == "fr" })
    #expect(french["total"] as? Int == 3)
    #expect(french["translated"] as? Int == 1)
    #expect(french["missing"] as? Int == 1)
    #expect(french["new"] as? Int == 1)
    #expect(french["needsReview"] as? Int == 0)
    #expect(french["needs_review"] == nil)
    let source = try #require(languages.first { $0["language"] as? String == "en" })
    #expect(source["isSource"] as? Bool == true)
    #expect(source["total"] as? Int == 3)
    #expect(source["translated"] as? Int == 3)
    #expect(french["isSource"] as? Bool == false)
}

@Test func projectDeclarationsAreComparedReadOnly() throws {
    let fixture = try Fixture()
    defer { fixture.remove() }
    try fixture.write("Localizable.xcstrings", catalog)
    let project = """
    // !$*UTF8*$!
    { archiveVersion = 1; objectVersion = 56; objects = {
      ROOT = { isa = PBXProject; developmentRegion = en; knownRegions = (en, es, Base); };
    }; rootObject = ROOT; }
    """
    try fixture.write("App.xcodeproj/project.pbxproj", project)
    let result = try fixture.run(["strings", "languages", "--check-project", "App.xcodeproj", "--json"])
    #expect(result.status == 1)
    #expect(result.err.contains("language declarations differ"))
    let json = try #require(JSONSerialization.jsonObject(with: Data(result.out.utf8)) as? [String: Any])
    let check = try #require(json["projectCheck"] as? [String: Any])
    #expect(check["declaredLanguages"] as? [String] == ["en", "es"])
    let comparisons = try #require(check["catalogs"] as? [[String: Any]])
    #expect(comparisons.first?["catalogOnly"] as? [String] == ["de", "fr"])
    #expect(comparisons.first?["projectOnly"] as? [String] == ["es"])
    #expect(try String(contentsOf: fixture.root.appendingPathComponent("App.xcodeproj/project.pbxproj"), encoding: .utf8) == project)
    #expect(try String(contentsOf: fixture.root.appendingPathComponent("Localizable.xcstrings"), encoding: .utf8) == catalog)
}

private func units(_ output: String) throws -> [[String: Any]] {
    let json = try #require(JSONSerialization.jsonObject(with: Data(output.utf8)) as? [String: Any])
    return try #require(json["units"] as? [[String: Any]])
}

@Test func filtersPreserveVariantsAndCatalogIdentity() throws {
    let fixture = try Fixture()
    defer { fixture.remove() }
    let variants = #"""
    {"version":"1.0","sourceLanguage":"en","strings":{
      "Count":{"localizations":{"fr":{"variations":{"device":{
        "iphone":{"variations":{"plural":{
          "one":{"stringUnit":{"state":"new","value":"Un"}},
          "other":{"stringUnit":{"state":"translated","value":"Plusieurs"}}
        }}},
        "other":{"stringUnit":{"state":"needs_review","value":"Compte"}}
      }}}}},
      "Missing":{},
      "Excluded":{"shouldTranslate":false},
      "Unsupported":{"localizations":{"fr":{"substitutions":{"arg1":{}}}}}
    }}
    """#
    try fixture.write("A.xcstrings", variants)
    try fixture.write("Nested/B.xcstrings", variants)
    let result = try fixture.run(["strings", "list", "--language", "fr", "--status", "new", "--status", "needs_review", "--json"])
    #expect(result.status == 0)
    #expect(result.err.isEmpty)
    let selected = try units(result.out)
    #expect(selected.count == 6)
    #expect(Set(selected.compactMap { $0["catalog"] as? String }) == ["A.xcstrings", "Nested/B.xcstrings"])
    #expect(selected.filter { $0["status"] as? String == "new" }.count == 2)
    let new = try #require(selected.first { $0["status"] as? String == "new" })
    let variant = try #require(new["variant"] as? [[String: String]])
    #expect(variant == [["dimension": "device", "value": "iphone"], ["dimension": "plural", "value": "one"]])
    #expect(selected.filter { $0["status"] as? String == "unsupported" }.allSatisfy { $0["issue"] is String })
    let missing = try fixture.run(["strings", "list", "--language", "fr", "--status", "missing", "--json"])
    #expect(try units(missing.out).filter { $0["status"] as? String == "missing" }.count == 2)
    let all = try fixture.run(["strings", "list", "--language", "fr", "--include-excluded", "--json"])
    let allUnits = try units(all.out)
    #expect(allUnits.count == 12)
    #expect(allUnits.filter { $0["excluded"] as? Bool == true }.count == 2)
    #expect(allUnits.filter { $0["status"] as? String == "translated" }.count == 2)
    #expect(try String(contentsOf: fixture.root.appendingPathComponent("A.xcstrings"), encoding: .utf8) == variants)
}

@Test func discoveryExclusionsDeduplicationAndExplicitSelection() throws {
    let fixture = try Fixture()
    defer { fixture.remove() }
    try fixture.write("App/Localizable.xcstrings", catalog)
    for directory in [".git", ".build", ".swiftpm", "build", "Build", "DerivedData", "Pods", "Carthage", "node_modules", "vendor"] {
        try fixture.write("\(directory)/Ignored.xcstrings", "invalid")
    }
    try FileManager.default.createSymbolicLink(atPath: fixture.root.appendingPathComponent("loop").path, withDestinationPath: fixture.root.path)
    try FileManager.default.createSymbolicLink(atPath: fixture.root.appendingPathComponent("alias.xcstrings").path, withDestinationPath: fixture.root.appendingPathComponent("App/Localizable.xcstrings").path)
    let result = try fixture.run(["strings", "list", ".", "App/Localizable.xcstrings", "alias.xcstrings", "--language", "fr", "--json"])
    #expect(result.status == 0)
    #expect(result.err.isEmpty)
    let selected = try units(result.out)
    #expect(selected.count == 3)
    #expect(Set(selected.compactMap { $0["catalog"] as? String }) == ["App/Localizable.xcstrings"])
    let explicit = try fixture.run(["strings", "languages", "Pods/Ignored.xcstrings", "--json"])
    #expect(explicit.status == 1)
    #expect(explicit.out.isEmpty)
    #expect(explicit.err.contains("Validate the catalog JSON"))
}

@Test func helpErrorsAndEmptySelections() throws {
    let fixture = try Fixture()
    defer { fixture.remove() }
    for args in [[], ["strings"], ["strings", "languages", "--help"], ["strings", "list", "-h"]] {
        let result = try fixture.run(args)
        #expect(result.status == 0)
        #expect(result.out.contains("USAGE:"))
        #expect(result.err.isEmpty)
    }
    let empty = try fixture.run(["strings", "list", "--json", "--no-input"])
    #expect(empty.status == 1)
    #expect(empty.out.isEmpty)
    #expect(empty.err.contains("No .xcstrings catalogs"))
    try fixture.write("Localizable.xcstrings", catalog)
    for args in [["--status", "wrong"], ["--language", "zz"], ["--language"]] {
        let result = try fixture.run(["strings", "list", "--json"] + args)
        #expect(result.status == 64)
        #expect(result.out.isEmpty)
        #expect(result.err.contains("Error:"))
    }
    let unknown = try fixture.run(["strings", "languages", "absent.xcstrings", "--json"])
    #expect(unknown.status == 1)
    #expect(unknown.out.isEmpty)
    #expect(unknown.err.contains("Supply a catalog or directory"))
    let none = try fixture.run(["strings", "list", "--language", "fr", "--status", "needs_review", "--json"])
    #expect(none.status == 0)
    #expect(try units(none.out).isEmpty)
}

@Test func sourceFallbackAndUnsupportedStates() throws {
    let fixture = try Fixture()
    defer { fixture.remove() }
    try fixture.write("Source.xcstrings", #"""
    {"version":"1.0","sourceLanguage":"ja","strings":{
      "ようこそ\n\"友達\"":{},
      "Unknown":{"localizations":{"fr":{"stringUnit":{"state":"future","value":"?"}}}},
      "Mixed":{"localizations":{"fr":{"stringUnit":{"state":"translated","value":"x"},"substitutions":{}}}},
      "Count":{"localizations":{"ja":{"variations":{"plural":{"other":{"stringUnit":{"state":"translated","value":"個"}}}}}}}
    }}
    """#)
    let result = try fixture.run(["strings", "list", "--language", "ja", "--json"])
    #expect(result.status == 0)
    let selected = try units(result.out)
    let fallback = try #require(selected.first { $0["key"] as? String == "ようこそ\n\"友達\"" })
    #expect(fallback["value"] as? String == "ようこそ\n\"友達\"")
    #expect(fallback["status"] as? String == "translated")
    let french = try fixture.run(["strings", "list", "--language", "fr", "--json"])
    #expect(try units(french.out).filter { $0["status"] as? String == "unsupported" }.count == 3)
    let human = try fixture.run(["strings", "list", "--language", "ja"])
    #expect(human.status == 0)
    #expect(human.err.isEmpty)
    #expect(human.out.split(separator: "\n").count == 4)
}

@Test func matchingAndInvalidProjectChecks() throws {
    let fixture = try Fixture()
    defer { fixture.remove() }
    try fixture.write("Localizable.xcstrings", catalog)
    try fixture.write("project.pbxproj", """
    { objects = {
      ROOT = { isa = PBXProject; developmentRegion = en; knownRegions = (fr, de, Base); };
      OTHER = { isa = PBXProject; developmentRegion = xx; knownRegions = (xx); };
    }; rootObject = ROOT; }
    """)
    let matching = try fixture.run(["strings", "languages", "--check-project", "project.pbxproj", "--json"])
    #expect(matching.status == 0)
    #expect(matching.err.isEmpty)
    let json = try #require(JSONSerialization.jsonObject(with: Data(matching.out.utf8)) as? [String: Any])
    let check = try #require(json["projectCheck"] as? [String: Any])
    #expect(check["declaredLanguages"] as? [String] == ["de", "en", "fr"])
    let human = try fixture.run(["strings", "languages", "--check-project", "project.pbxproj"])
    #expect(human.status == 0)
    #expect(human.out.contains("catalog-only []; project-only []"))
    for invalid in ["not a plist", "{objects = {}; rootObject = BAD;}", "{objects = {R = {isa = PBXProject;};}; rootObject = R;}"] {
        try fixture.write("project.pbxproj", invalid)
        let result = try fixture.run(["strings", "languages", "--check-project", "project.pbxproj", "--json"])
        #expect(result.status == 1)
        #expect(result.out.isEmpty)
        #expect(result.err.contains("Error:"))
    }
}

@Test(arguments: [
    "not JSON",
    #"{"version":"2.0","sourceLanguage":"en","strings":{}}"#,
    #"{"version":"1.0","sourceLanguage":"en","strings":{"Bad":0}}"#,
    #"{"version":"1.0","sourceLanguage":"en","strings":{"Bad":{"shouldTranslate":0}}}"#,
    #"{"version":"1.0","sourceLanguage":"en","strings":{"Bad":{"localizations":[]}}}"#
])
func malformedCatalogsFailWithoutPartialOutput(_ malformed: String) throws {
    let fixture = try Fixture()
    defer { fixture.remove() }
    try fixture.write("A.xcstrings", catalog)
    try fixture.write("Z.xcstrings", malformed)
    let result = try fixture.run(["strings", "languages", "--json"])
    #expect(result.status == 1)
    #expect(result.out.isEmpty)
    #expect(result.err.contains("Z.xcstrings"))
    #expect(try String(contentsOf: fixture.root.appendingPathComponent("A.xcstrings"), encoding: .utf8) == catalog)
}

@Test func exportDefaultsAndReadOnlyContext() throws {
    let fixture = try Fixture()
    defer { fixture.remove() }
    try fixture.write("Localizable.xcstrings", catalog)
    let result = try fixture.run(["strings", "export", "--language", "fr", "--no-input"])
    #expect(result.status == 0)
    #expect(result.err.isEmpty)
    let selected = try units(result.out)
    #expect(selected.count == 2)
    #expect(Set(selected.compactMap { $0["key"] as? String }) == ["Missing", "New"])
    let missing = try #require(selected.first { $0["key"] as? String == "Missing" })
    #expect(missing["status"] as? String == "missing")
    #expect(missing["translation"] as? String == "")
    #expect(missing["originalTranslation"] is NSNull)
    #expect(missing["statusUpdate"] as? String == "")
    #expect(missing["sourceLanguage"] as? String == "en")
    let source = try #require(missing["source"] as? [[String: Any]])
    #expect(source.first?["text"] as? String == "Missing")
    #expect(missing["sourceFingerprint"] is String)
    #expect(missing["destinationFingerprint"] is String)
    #expect(missing["recordFingerprint"] is String)
    #expect(try String(contentsOf: fixture.root.appendingPathComponent("Localizable.xcstrings"), encoding: .utf8) == catalog)
}

@Test func exportDoesNotGuessMissingStructuredDestinations() throws {
    let fixture = try Fixture()
    defer { fixture.remove() }
    try fixture.write("Localizable.xcstrings", #"""
    {"version":"1.0","sourceLanguage":"en","strings":{
      "Count":{"localizations":{"de":{"variations":{"plural":{"other":{"stringUnit":{"state":"new","value":"Dinge"}}}}}}},
      "Anchor":{"localizations":{"fr":{"stringUnit":{"state":"translated","value":"Ancre"}}}}
    }}
    """#)
    let result = try fixture.run(["strings", "export", "--language", "fr"])
    #expect(result.status == 1)
    #expect(result.out.isEmpty)
    #expect(result.err.contains("structure"))
    #expect(result.err.contains("Count"))
}

@Test func exportVariantsCatalogsAndCSVParity() throws {
    let fixture = try Fixture()
    defer { fixture.remove() }
    let text = #"""
    {"version":"1.0","sourceLanguage":"en","strings":{
      "Count,\"項目\"\nnext":{"comment":"Developer, \"note\"\n日本語","localizations":{
        "en":{"variations":{"plural":{
          "one":{"stringUnit":{"state":"translated","value":"One item"}},
          "other":{"stringUnit":{"state":"translated","value":"Many items"}}
        }}},
        "fr":{"variations":{"plural":{
          "one":{"stringUnit":{"state":"new","value":"Un, \"élément\"\n次"}},
          "other":{"stringUnit":{"state":"translated","value":"Plusieurs"}},
          "few":{}
        }}}
      }},
      "Review":{"localizations":{"fr":{"stringUnit":{"state":"needs_review","value":"Revoir"}}}},
      "Excluded":{"shouldTranslate":false,"localizations":{"fr":{"substitutions":{}}}}
    }}
    """#
    try fixture.write("A/Labels.xcstrings", text)
    try fixture.write("B/Labels.xcstrings", text)
    let arguments = ["strings", "export", "A/Labels.xcstrings", "B/Labels.xcstrings", "--all-languages"]
    let json = try fixture.run(arguments)
    #expect(json.status == 0)
    #expect(json.err.isEmpty)
    #expect(!json.out.contains(fixture.root.path))
    let selected = try units(json.out)
    #expect(selected.count == 6)
    #expect(Set(selected.compactMap { $0["catalog"] as? String }) == ["A/Labels.xcstrings", "B/Labels.xcstrings"])
    #expect(selected.allSatisfy { $0["language"] as? String == "fr" })
    let new = try #require(selected.first { $0["status"] as? String == "new" })
    #expect(new["variant"] as? [[String: String]] == [["dimension": "plural", "value": "one"]])
    #expect(new["developerComments"] as? String == "Developer, \"note\"\n日本語")
    #expect(new["translation"] as? String == "Un, \"élément\"\n次")
    #expect((new["source"] as? [[String: Any]])?.count == 2)
    let csv = try fixture.run(arguments + ["--format", "csv", "--output", "-", "--no-input"])
    #expect(csv.status == 0)
    #expect(csv.err.isEmpty)
    let rows = try parseCSV(csv.out)
    #expect(rows.count == selected.count + 1)
    let header = try #require(rows.first)
    let jsonColumns: Set<String> = ["schemaVersion", "variant", "source", "developerComments", "originalTranslation", "originalDestination"]
    let decoded = try rows.dropFirst().map { row -> [String: Any] in
        #expect(row.count == header.count)
        return try Dictionary(uniqueKeysWithValues: zip(header, row).map { column, value in
            (column, jsonColumns.contains(column) ? try JSONSerialization.jsonObject(with: Data(value.utf8), options: [.fragmentsAllowed]) : value as Any)
        })
    }
    #expect(NSArray(array: decoded).isEqual(to: selected))
    let combined = try fixture.run(arguments + ["--status", "new", "--status", "translated"])
    #expect(combined.status == 0)
    let combinedUnits = try units(combined.out)
    #expect(combinedUnits.count == 4)
    #expect(Set(combinedUnits.compactMap { $0["status"] as? String }) == ["new", "translated"])
    let source = try fixture.run(["strings", "export", "--language", "en"])
    #expect(source.status == 0)
    #expect(try units(source.out).isEmpty)
}

// Independent reader used only to verify the public CSV wire format.
private func parseCSV(_ text: String) throws -> [[String]] {
    var rows: [[String]] = []
    var row: [String] = []
    var cell = ""
    var quoted = false
    let characters = Array(text.unicodeScalars)
    var index = 0
    while index < characters.count {
        let character = characters[index]
        if character == "\"" {
            if quoted && index + 1 < characters.count && characters[index + 1] == "\"" {
                cell.append("\"")
                index += 1
            } else { quoted.toggle() }
        } else if !quoted && character == "," {
            row.append(cell)
            cell = ""
        } else if !quoted && (character == "\r" || character == "\n") {
            if character == "\r" && index + 1 < characters.count && characters[index + 1] == "\n" { index += 1 }
            row.append(cell)
            rows.append(row)
            row = []
            cell = ""
        } else { cell.unicodeScalars.append(character) }
        index += 1
    }
    #expect(!quoted)
    if !cell.isEmpty || !row.isEmpty { row.append(cell); rows.append(row) }
    return rows
}

@Test func exportOutputProtectionAndCLIUsage() throws {
    let fixture = try Fixture()
    defer { fixture.remove() }
    try fixture.write("Labels.xcstrings", catalog)
    for option in ["--help", "-h"] {
        let help = try fixture.run(["strings", "export", option])
        #expect(help.status == 0)
        #expect(help.err.isEmpty)
        #expect(help.out.contains("--all-languages"))
        #expect(help.out.contains("--overwrite"))
        #expect(help.out.contains("Examples:"))
    }
    for flags in [[], ["--no-input"], ["--language"], ["--language", "fr", "--all-languages"], ["--all-languages", "--format", "xml"], ["--all-languages", "--status", "missing,translated"]] {
        let result = try fixture.run(["strings", "export"] + flags)
        #expect(result.status == 64)
        #expect(result.out.isEmpty)
        #expect(result.err.contains("Error:"))
        #expect(result.err.contains("--help"))
    }
    let unknown = try fixture.run(["strings", "export", "--language", "zz"])
    #expect(unknown.status == 1)
    #expect(unknown.out.isEmpty)
    #expect(unknown.err.contains("strings languages"))
    let args = ["strings", "export", "--language", "fr", "--output", "handoff.json", "--no-input"]
    let created = try fixture.run(args)
    #expect(created.status == 0)
    #expect(created.out.isEmpty)
    #expect(created.err.contains("handoff.json"))
    let handoff = fixture.root.appendingPathComponent("handoff.json")
    #expect(try units(String(contentsOf: handoff, encoding: .utf8)).count == 2)
    try fixture.write("handoff.json", "previous handoff")
    let protected = try fixture.run(args)
    #expect(protected.status == 1)
    #expect(protected.out.isEmpty)
    #expect(protected.err.contains("--overwrite"))
    #expect(try String(contentsOf: handoff, encoding: .utf8) == "previous handoff")
    let replaced = try fixture.run(args + ["--overwrite"])
    #expect(replaced.status == 0)
    #expect(replaced.out.isEmpty)
    #expect(try units(String(contentsOf: handoff, encoding: .utf8)).count == 2)
    let catalogOutput = try fixture.run(["strings", "export", "--language", "fr", "-o", "Labels.xcstrings", "--overwrite"])
    #expect(catalogOutput.status == 1)
    #expect(catalogOutput.out.isEmpty)
    #expect(catalogOutput.err.contains("Choose a .json or .csv"))
    try FileManager.default.createSymbolicLink(atPath: fixture.root.appendingPathComponent("alias.json").path, withDestinationPath: "Labels.xcstrings")
    let symlink = try fixture.run(["strings", "export", "--language", "fr", "-o", "alias.json", "--overwrite"])
    #expect(symlink.status == 1)
    #expect(symlink.err.contains("symbolic link"))
    #expect(try String(contentsOf: fixture.root.appendingPathComponent("Labels.xcstrings"), encoding: .utf8) == catalog)
    let badOutput = try fixture.run(["strings", "export", "--language", "fr", "-o", "absent/handoff.json"])
    #expect(badOutput.status == 1)
    #expect(badOutput.out.isEmpty)
    #expect(badOutput.err.contains("writable"))
    #expect(try FileManager.default.contentsOfDirectory(atPath: fixture.root.path).allSatisfy { !$0.hasPrefix(".koshops-export-") })
}

@Test(arguments: [
    #"{"localizations":{"fr":{"substitutions":{}}}}"#,
    #"{"localizations":{"en":{"substitutions":{}},"fr":{"stringUnit":{"state":"new","value":"x"}}}}"#,
    #"{"localizations":{"en":{"variations":{"plural":{"other":{"stringUnit":{"state":"translated","value":"Items"}}}}}}}"#,
    #"{"comment":42,"localizations":{"fr":{"stringUnit":{"state":"new","value":"x"}}}}"#,
    #"{"localizations":{"fr":{"stringUnit":{"state":"future","value":"x"}}}}"#
])
func exportUnsupportedSelectionsLeaveOutputUntouched(_ entry: String) throws {
    let fixture = try Fixture()
    defer { fixture.remove() }
    try fixture.write("A.xcstrings", catalog)
    try fixture.write("Z.xcstrings", "{\"version\":\"1.0\",\"sourceLanguage\":\"en\",\"strings\":{\"Bad\":\(entry),\"Anchor\":{\"localizations\":{\"fr\":{}}}}}")
    try fixture.write("handoff.json", "keep me")
    let result = try fixture.run(["strings", "export", "--language", "fr", "--output", "handoff.json", "--overwrite"])
    #expect(result.status == 1)
    #expect(result.out.isEmpty)
    #expect(result.err.contains("Bad"))
    #expect(result.err.contains("Xcode"))
    #expect(try String(contentsOf: fixture.root.appendingPathComponent("handoff.json"), encoding: .utf8) == "keep me")
    let sourceOnly = try fixture.run(["strings", "export", "--language", "en"])
    #expect(sourceOnly.status == 0)
    #expect(try units(sourceOnly.out).isEmpty)
}

@Test func exportNestedLeavesAndConflictMetadata() throws {
    let fixture = try Fixture()
    defer { fixture.remove() }
    let original = #"""
    {"version":"1.0","sourceLanguage":"en","strings":{
      "Count":{"comment":"context","localizations":{
        "fr":{"variations":{"device":{"iphone":{"variations":{"plural":{
          "one":{"stringUnit":{"state":"new","value":"Un"}},
          "other":{"stringUnit":{"state":"translated","value":"Plusieurs"}}
        }}}}}}
      }},
      "Unrelated":{}
    }}
    """#
    try fixture.write("Labels.xcstrings", original)
    let args = ["strings", "export", "--language", "fr", "--status", "new"]
    let initial = try fixture.run(args)
    #expect(initial.status == 0)
    let first = try #require(units(initial.out).first)
    #expect(first["variant"] as? [[String: String]] == [["dimension": "device", "value": "iphone"], ["dimension": "plural", "value": "one"]])
    let destination = try #require(first["originalDestination"] as? [String: [String: String]])
    #expect(destination == ["stringUnit": ["state": "new", "value": "Un"]])
    let repeated = try fixture.run(args)
    #expect(repeated.out == initial.out)
    for (old, new, sourceChanges, destinationChanges) in [
        ("Plusieurs", "Beaucoup", false, false),
        ("Unrelated", "OtherKey", false, false),
        ("context", "changed comment", true, false),
        ("Un\"", "Une\"", false, true)
    ] {
        try fixture.write("Labels.xcstrings", original.replacingOccurrences(of: old, with: new))
        let result = try fixture.run(args)
        #expect(result.status == 0)
        let record = try #require(units(result.out).first)
        #expect((record["sourceFingerprint"] as? String != first["sourceFingerprint"] as? String) == sourceChanges)
        #expect((record["destinationFingerprint"] as? String != first["destinationFingerprint"] as? String) == destinationChanges)
        #expect((record["recordFingerprint"] as? String != first["recordFingerprint"] as? String) == (sourceChanges || destinationChanges))
    }
}

@Test(arguments: ["Desktop", "Desktop/"], [false, true])
func exportDirectoryOutputRequestsFilename(_ output: String, _ overwrite: Bool) throws {
    let fixture = try Fixture()
    defer { fixture.remove() }
    try fixture.write("Labels.xcstrings", catalog)
    try fixture.write("Desktop/keep.txt", "keep me")
    let result = try fixture.run(["strings", "export", "--language", "fr", "--output", output, "--no-input"] + (overwrite ? ["--overwrite"] : []))
    #expect(result.status == 1)
    #expect(result.out.isEmpty)
    #expect(result.err.contains("is a directory"))
    #expect(result.err.contains("Provide a filename"))
    #expect(result.err.contains("--output"))
    #expect(!result.err.contains("NSCocoaErrorDomain"))
    #expect(!result.err.contains(".koshops-export-"))
    #expect(!result.err.contains("--overwrite"))
    #expect(try String(contentsOf: fixture.root.appendingPathComponent("Desktop/keep.txt"), encoding: .utf8) == "keep me")
    #expect(try FileManager.default.contentsOfDirectory(atPath: fixture.root.appendingPathComponent("Desktop").path) == ["keep.txt"])
    #expect(try FileManager.default.contentsOfDirectory(atPath: fixture.root.path).allSatisfy { !$0.hasPrefix(".koshops-export-") })
}

@Test(arguments: ["json", "csv"])
func exportRejectsConflictingFileExtensions(_ format: String) throws {
    let fixture = try Fixture()
    defer { fixture.remove() }
    try fixture.write("Labels.xcstrings", catalog)
    let conflicting = format == "json" ? "csv" : "json"
    // Omit --format for JSON to cover the default format as well.
    let arguments = ["strings", "export", "--language", "fr", "--no-input"] + (format == "json" ? [] : ["--format", format])
    for suffix in [conflicting, conflicting.uppercased()] {
        let path = "translations." + suffix
        let output = fixture.root.appendingPathComponent(path)
        let rejected = try fixture.run(arguments + ["--output", path])
        #expect(rejected.status == 1)
        #expect(rejected.out.isEmpty)
        #expect(rejected.err.contains("selected format is \(format)"))
        #expect(rejected.err.contains("--format \(conflicting)"))
        #expect(rejected.err.contains("translations.\(format)"))
        #expect(!FileManager.default.fileExists(atPath: output.path))
        try fixture.write(path, "existing handoff")
        let overwrite = try fixture.run(arguments + ["--output", path, "--overwrite"])
        #expect(overwrite.status == 1)
        #expect(overwrite.out.isEmpty)
        #expect(try String(contentsOf: output, encoding: .utf8) == "existing handoff")
        try FileManager.default.removeItem(at: output)
    }
    for path in ["translations." + format, "translations." + format.uppercased(), "translations", "translations.txt", "-"] {
        let result = try fixture.run(arguments + ["--output", path])
        #expect(result.status == 0)
        let text = path == "-" ? result.out : try String(contentsOf: fixture.root.appendingPathComponent(path), encoding: .utf8)
        if format == "json" { #expect(try units(text).count == 2) }
        else { #expect(try parseCSV(text).count == 3) }
        if path == "-" { #expect(result.err.isEmpty) }
        else {
            #expect(result.out.isEmpty)
            try FileManager.default.removeItem(at: fixture.root.appendingPathComponent(path))
        }
    }
}
