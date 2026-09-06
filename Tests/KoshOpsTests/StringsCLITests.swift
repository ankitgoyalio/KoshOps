import Foundation
import Testing

private final class TestBundleMarker {}

struct Fixture {
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
    func run(_ arguments: [String], stdin: String? = nil) throws -> (status: Int32, out: String, err: String) {
        let process = Process()
        let executable = Bundle(for: TestBundleMarker.self).bundleURL.deletingLastPathComponent().appendingPathComponent("koshops")
        process.executableURL = executable
        process.arguments = arguments
        process.currentDirectoryURL = root
        if let stdin {
            try write("stdin", stdin)
            process.standardInput = try FileHandle(forReadingFrom: root.appendingPathComponent("stdin"))
        } else { process.standardInput = FileHandle.nullDevice }
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

@Test func vendorExportSeparatesEditableCSVFromManifest() throws {
    let fixture = try Fixture()
    defer { fixture.remove() }
    try fixture.write("Labels.xcstrings", catalog)
    let result = try fixture.run(["strings", "export", "--format", "csv", "--language", "fr", "-o", "translations.csv", "--no-input"])
    #expect(result.status == 0)
    #expect(result.out.isEmpty)
    #expect(result.err.contains("translations.csv"))
    #expect(result.err.contains("translations.csv.manifest.json"))
    let csv = try String(contentsOf: fixture.root.appendingPathComponent("translations.csv"), encoding: .utf8)
    let rows = try parseCSV(csv)
    #expect(rows.first == ["id", "language", "source", "context", "translation"])
    #expect(rows.count == 3)
    #expect(rows[1][1] == "fr")
    #expect(rows[1][2] == "Missing")
    #expect(rows[1][4] == "")
    #expect(rows[2][4] == "Nouveau")
    let manifestData = try Data(contentsOf: fixture.root.appendingPathComponent("translations.csv.manifest.json"))
    let manifest = try #require(JSONSerialization.jsonObject(with: manifestData) as? [String: Any])
    #expect(manifest["schemaVersion"] as? Int == 1)
    #expect(manifest["kind"] as? String == "vendorManifest")
    let entries = try #require(manifest["entries"] as? [[String: Any]])
    #expect(entries.count == 2)
    #expect(entries.map { $0["id"] as? String } == rows.dropFirst().map { Optional($0[0]) })
    let original = try #require(entries[0]["record"] as? [String: Any])
    #expect(original["catalog"] as? String == "Labels.xcstrings")
    #expect(original["originalDestination"] is NSNull)
    #expect(original["sourceFingerprint"] is String)
    #expect(original["destinationFingerprint"] is String)
    #expect(original["statusUpdate"] as? String == "")
    #expect(!csv.contains("Labels.xcstrings"))
    #expect(!String(decoding: manifestData, as: UTF8.self).contains(fixture.root.path))
}

private func manifestEntries(_ fixture: Fixture, path: String = "translations.csv.manifest.json") throws -> [[String: Any]] {
    let data = try Data(contentsOf: fixture.root.appendingPathComponent(path))
    let object = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
    return try #require(object["entries"] as? [[String: Any]])
}

@Test func vendorVariantsAndMultipleCatalogsPreserveContext() throws {
    let fixture = try Fixture()
    defer { fixture.remove() }
    let text = #"""
    {"version":"1.0","sourceLanguage":"en","strings":{
      "Count":{"comment":"Developer, \"note\"\n日本語","localizations":{
        "en":{"variations":{"plural":{
          "one":{"stringUnit":{"state":"translated","value":"One item"}},
          "other":{"stringUnit":{"state":"translated","value":"Many items"}}
        }}},
        "fr":{"variations":{"device":{"iphone":{"variations":{"plural":{
          "one":{"stringUnit":{"state":"new","value":"Un, \"élément\"\n次"}},
          "other":{"stringUnit":{"state":"translated","value":"Plusieurs"}},
          "few":{}
        }}}}}}
      }},
      "Review":{"localizations":{"fr":{"stringUnit":{"state":"needs_review","value":"Revoir"}}}},
      "Excluded":{"shouldTranslate":false,"localizations":{"fr":{"substitutions":{}}}}
    }}
    """#
    try fixture.write("A/Labels.xcstrings", text)
    try fixture.write("B/Labels.xcstrings", text)
    let args = ["strings", "export", "--format", "csv", "A/Labels.xcstrings", "B/Labels.xcstrings", "--all-languages", "-o", "translations.csv"]
    let result = try fixture.run(args)
    #expect(result.status == 0)
    let entries = try manifestEntries(fixture)
    let records = try entries.map { try #require($0["record"] as? [String: Any]) }
    #expect(records.count == 6)
    #expect(Set(records.compactMap { $0["catalog"] as? String }) == ["A/Labels.xcstrings", "B/Labels.xcstrings"])
    #expect(records.allSatisfy { $0["language"] as? String == "fr" })
    #expect(Set(entries.compactMap { $0["id"] as? String }).count == 6)
    let csv = try String(contentsOf: fixture.root.appendingPathComponent("translations.csv"), encoding: .utf8)
    let rows = try parseCSV(csv)
    #expect(rows.count == 7)
    let new = try #require(rows.dropFirst().first { $0[4] == "Un, \"élément\"\n次" })
    #expect(new[2] == "[plural=one] One item\n[plural=other] Many items")
    #expect(new[3] == "Target variant: device=iphone/plural=one\nDeveloper, \"note\"\n日本語")
    #expect(!csv.contains("Labels.xcstrings"))
    let filtered = try fixture.run(args + ["--status", "new", "--status", "translated", "--overwrite"])
    #expect(filtered.status == 0)
    let filteredRecords = try manifestEntries(fixture).map { try #require($0["record"] as? [String: Any]) }
    #expect(filteredRecords.count == 4)
    #expect(Set(filteredRecords.compactMap { $0["status"] as? String }) == ["new", "translated"])
    let source = try fixture.run(["strings", "export", "--format", "csv", "--language", "en", "-o", "translations.csv", "--overwrite"])
    #expect(source.status == 0)
    #expect(try manifestEntries(fixture).isEmpty)
    #expect(try parseCSV(String(contentsOf: fixture.root.appendingPathComponent("translations.csv"), encoding: .utf8)).count == 1)
    #expect(try String(contentsOf: fixture.root.appendingPathComponent("A/Labels.xcstrings"), encoding: .utf8) == text)
}

@Test func vendorOutputPathsAndOverwriteProtection() throws {
    let fixture = try Fixture()
    defer { fixture.remove() }
    try fixture.write("Labels.xcstrings", catalog)
    let args = ["strings", "export", "--format", "csv", "--language", "fr", "--no-input"]
    for flags in [
        ["-o", "translations.json"], ["-o", "translations.JSON"], ["-o", "translations.json", "--overwrite"],
        ["-o", "translations.csv", "--manifest", "manifest.csv"],
        ["-o", "Labels.xcstrings"], ["-o", "Labels.xcstrings", "--overwrite"],
        ["-o", "."], ["-o", "./", "--overwrite"],
        ["-o", "translations.csv", "--manifest", "."],
        ["-o", "same", "--manifest", "./same"], ["-o", "SAME", "--manifest", "same", "--overwrite"], ["--manifest", "-"],
        ["-o", "absent/file.csv"], ["-o", "translations.csv", "--manifest", "absent/manifest.json"]
    ] {
        if flags.contains("SAME"), try fixture.root.resourceValues(forKeys: [.volumeSupportsCaseSensitiveNamesKey]).volumeSupportsCaseSensitiveNames == true { continue }
        let result = try fixture.run(args + flags)
        #expect(result.status == 1)
        #expect(result.out.isEmpty)
        #expect(result.err.contains("Error:"))
        if flags.contains(".") || flags.contains("./") {
            #expect(result.err.contains("is a directory"))
            #expect(result.err.contains("Provide a filename"))
        }
        if flags.contains("translations.json") || flags.contains("translations.JSON") {
            #expect(result.err.contains("requires csv"))
            #expect(result.err.contains("translations.csv"))
        }
        #expect(!result.err.contains("NSCocoaErrorDomain"))
        #expect(!FileManager.default.fileExists(atPath: fixture.root.appendingPathComponent("translations.csv").path))
        #expect(!FileManager.default.fileExists(atPath: fixture.root.appendingPathComponent("translations.csv.manifest.json").path))
    }
    try fixture.write("translations.csv", "previous csv")
    try fixture.write("translations.csv.manifest.json", "previous manifest")
    let protected = try fixture.run(args + ["-o", "translations.csv"])
    #expect(protected.status == 1)
    #expect(protected.err.contains("--overwrite"))
    #expect(try String(contentsOf: fixture.root.appendingPathComponent("translations.csv"), encoding: .utf8) == "previous csv")
    #expect(try String(contentsOf: fixture.root.appendingPathComponent("translations.csv.manifest.json"), encoding: .utf8) == "previous manifest")
    let replaced = try fixture.run(args + ["-o", "translations.csv", "--overwrite"])
    #expect(replaced.status == 0)
    #expect(try manifestEntries(fixture).count == 2)
    // Manifest must remain unchanged when preparing the second file fails.
    let retained = try Data(contentsOf: fixture.root.appendingPathComponent("translations.csv.manifest.json"))
    let failure = try fixture.run(args + ["-o", "absent/file.csv", "--manifest", "translations.csv.manifest.json", "--overwrite"])
    #expect(failure.status == 1)
    #expect(failure.out.isEmpty)
    #expect(try Data(contentsOf: fixture.root.appendingPathComponent("translations.csv.manifest.json")) == retained)
    try FileManager.default.createSymbolicLink(atPath: fixture.root.appendingPathComponent("alias.csv").path, withDestinationPath: "Labels.xcstrings")
    let symlink = try fixture.run(args + ["-o", "alias.csv", "--overwrite"])
    #expect(symlink.status == 1)
    #expect(symlink.err.contains("symbolic link"))
    #expect(try String(contentsOf: fixture.root.appendingPathComponent("Labels.xcstrings"), encoding: .utf8) == catalog)
    #expect(try FileManager.default.contentsOfDirectory(atPath: fixture.root.path).allSatisfy { !$0.hasPrefix(".koshops-export-") })
}

@Test func vendorStdoutAndCLIUsage() throws {
    let fixture = try Fixture()
    defer { fixture.remove() }
    try fixture.write("Labels.xcstrings", catalog)
    for help in ["--help", "-h"] {
        let result = try fixture.run(["strings", "export", "--format", "csv", help])
        #expect(result.status == 0)
        #expect(result.out.contains("--manifest"))
        #expect(result.out.contains("Examples:"))
        #expect(result.err.isEmpty)
    }
    for flags in [[], ["--language"], ["--language", "fr"], ["--language", "fr", "--all-languages"], ["--all-languages", "--format", "xml"], ["--all-languages", "--status", "bogus"]] {
        let result = try fixture.run(["strings", "export", "--format", "csv"] + flags)
        #expect(result.status == 64)
        #expect(result.out.isEmpty)
        #expect(result.err.contains("--help"))
    }
    let unknown = try fixture.run(["strings", "export", "--format", "csv", "--language", "zz", "--manifest", "private.json"])
    #expect(unknown.status == 1)
    #expect(unknown.out.isEmpty)
    #expect(unknown.err.contains("strings languages"))
    let result = try fixture.run(["strings", "export", "--format", "csv", "--language", "fr", "--manifest", "private.json", "--no-input", "-o", "-"])
    #expect(result.status == 0)
    #expect(result.err.contains("private.json"))
    #expect(try parseCSV(result.out).count == 3)
    #expect(try manifestEntries(fixture, path: "private.json").count == 2)
    #expect(!result.out.contains("manifest"))
    for path in ["translations", "translations.CSV", "translations.txt"] {
        let success = try fixture.run(["strings", "export", "--format", "csv", "--language", "fr", "-o", path])
        #expect(success.status == 0)
        #expect(success.out.isEmpty)
        #expect(try parseCSV(String(contentsOf: fixture.root.appendingPathComponent(path), encoding: .utf8)).count == 3)
        #expect(try manifestEntries(fixture, path: path + ".manifest.json").count == 2)
    }
}

@Test(arguments: [
    #"{"localizations":{"fr":{"substitutions":{}}}}"#,
    #"{"localizations":{"en":{"substitutions":{}},"fr":{"stringUnit":{"state":"new","value":"x"}}}}"#,
    #"{"localizations":{"en":{"variations":{"plural":{"other":{"stringUnit":{"state":"translated","value":"Items"}}}}}}}"#,
    #"{"localizations":{"de":{"variations":{"plural":{"other":{"stringUnit":{"state":"translated","value":"Dinge"}}}}}}}"#,
    #"{"comment":42,"localizations":{"fr":{"stringUnit":{"state":"new","value":"x"}}}}"#,
    #"{"localizations":{"fr":{"stringUnit":{"state":"future","value":"x"}}}}"#
])
func vendorUnsupportedSelectionsPreserveBothFiles(_ entry: String) throws {
    let fixture = try Fixture()
    defer { fixture.remove() }
    try fixture.write("A.xcstrings", catalog)
    try fixture.write("Z.xcstrings", "{\"version\":\"1.0\",\"sourceLanguage\":\"en\",\"strings\":{\"Bad\":\(entry),\"Anchor\":{\"localizations\":{\"fr\":{}}}}}")
    try fixture.write("translations.csv", "csv")
    try fixture.write("translations.csv.manifest.json", "manifest")
    let result = try fixture.run(["strings", "export", "--format", "csv", "--language", "fr", "-o", "translations.csv", "--overwrite"])
    #expect(result.status == 1)
    #expect(result.out.isEmpty)
    #expect(result.err.contains("Bad"))
    #expect(result.err.contains("Xcode"))
    #expect(try String(contentsOf: fixture.root.appendingPathComponent("translations.csv"), encoding: .utf8) == "csv")
    #expect(try String(contentsOf: fixture.root.appendingPathComponent("translations.csv.manifest.json"), encoding: .utf8) == "manifest")
}

@Test func vendorIDsBindOriginalRecordsWithoutUnrelatedConflicts() throws {
    let fixture = try Fixture()
    defer { fixture.remove() }
    let original = #"""
    {"version":"1.0","sourceLanguage":"en","strings":{
      "Count":{"comment":"context","localizations":{
        "fr":{"variations":{"plural":{
          "one":{"stringUnit":{"state":"new","value":"Un"}},
          "other":{"stringUnit":{"state":"translated","value":"Plusieurs"}}
        }}}
      }},
      "Unrelated":{}
    }}
    """#
    try fixture.write("Labels.xcstrings", original)
    let args = ["strings", "export", "--format", "csv", "--language", "fr", "--status", "new", "-o", "translations.csv", "--overwrite"]
    #expect(try fixture.run(args).status == 0)
    let firstEntry = try #require(manifestEntries(fixture).first)
    let first = try #require(firstEntry["record"] as? [String: Any])
    #expect((first["originalDestination"] as? [String: [String: String]]) == ["stringUnit": ["state": "new", "value": "Un"]])
    for (old, new, sourceChanges, destinationChanges) in [
        ("Count", "Count", false, false),
        ("Plusieurs", "Beaucoup", false, false),
        ("Unrelated", "OtherKey", false, false),
        ("context", "changed comment", true, false),
        ("Un\"", "Une\"", false, true)
    ] {
        try fixture.write("Labels.xcstrings", original.replacingOccurrences(of: old, with: new))
        #expect(try fixture.run(args).status == 0)
        let entry = try #require(manifestEntries(fixture).first)
        let record = try #require(entry["record"] as? [String: Any])
        #expect((record["sourceFingerprint"] as? String != first["sourceFingerprint"] as? String) == sourceChanges)
        #expect((record["destinationFingerprint"] as? String != first["destinationFingerprint"] as? String) == destinationChanges)
        #expect((entry["id"] as? String != firstEntry["id"] as? String) == (sourceChanges || destinationChanges))
        let rows = try parseCSV(String(contentsOf: fixture.root.appendingPathComponent("translations.csv"), encoding: .utf8))
        #expect(rows[1][0] == entry["id"] as? String)
    }
    #expect(try FileManager.default.contentsOfDirectory(atPath: fixture.root.path).allSatisfy { !$0.hasPrefix(".koshops-") })
}

@Test func jsonExportRemainsDefaultWithoutManifest() throws {
    let fixture = try Fixture()
    defer { fixture.remove() }
    try fixture.write("Labels.xcstrings", catalog)
    let result = try fixture.run(["strings", "export", "--language", "fr", "--no-input"])
    #expect(result.status == 0)
    #expect(result.err.isEmpty)
    let records = try units(result.out)
    #expect(records.count == 2)
    let missing = try #require(records.first { $0["key"] as? String == "Missing" })
    #expect(missing["status"] as? String == "missing")
    #expect(missing["translation"] as? String == "")
    #expect(missing["statusUpdate"] as? String == "")
    #expect(missing["originalDestination"] is NSNull)
    #expect(missing["sourceFingerprint"] is String)
    let file = try fixture.run(["strings", "export", "--language", "fr", "--format", "json", "-o", "translations.json"])
    #expect(file.status == 0)
    #expect(file.out.isEmpty)
    #expect(try String(contentsOf: fixture.root.appendingPathComponent("translations.json"), encoding: .utf8) == result.out)
    #expect(!FileManager.default.fileExists(atPath: fixture.root.appendingPathComponent("translations.json.manifest.json").path))
}

@Test func jsonExportPreservesFileSafetyAndMatchesCSVManifest() throws {
    let fixture = try Fixture()
    defer { fixture.remove() }
    try fixture.write("Labels.xcstrings", catalog)
    let args = ["strings", "export", "--language", "fr"]
    let original = try fixture.run(args)
    #expect(original.status == 0)
    let csv = try fixture.run(args + ["--format", "csv", "-o", "translations.csv"])
    #expect(csv.status == 0)
    let records = try manifestEntries(fixture).map { try #require($0["record"] as? [String: Any]) }
    #expect(NSArray(array: records).isEqual(to: try units(original.out)))
    let invalidManifest = try fixture.run(args + ["--manifest", "unused.json"])
    #expect(invalidManifest.status == 64)
    #expect(invalidManifest.out.isEmpty)
    #expect(invalidManifest.err.contains("only used with CSV"))
    #expect(!FileManager.default.fileExists(atPath: fixture.root.appendingPathComponent("unused.json").path))
    for path in ["invalid.csv", "invalid.CSV", ".", "Labels.xcstrings"] {
        let invalid = try fixture.run(args + ["-o", path, "--overwrite"])
        #expect(invalid.status == 1)
        #expect(invalid.out.isEmpty)
    }
    try fixture.write("export.json", "keep me")
    #expect(try fixture.run(args + ["-o", "export.json"]).status == 1)
    #expect(try String(contentsOf: fixture.root.appendingPathComponent("export.json"), encoding: .utf8) == "keep me")
    #expect(try fixture.run(args + ["-o", "export.json", "--overwrite"]).status == 0)
    #expect(try String(contentsOf: fixture.root.appendingPathComponent("export.json"), encoding: .utf8) == original.out)
}

@Test func helpExplainsWorkflowAndFileEffects() throws {
    let fixture = try Fixture()
    defer { fixture.remove() }
    for command in [[], ["strings"], ["strings", "languages"], ["strings", "list"], ["strings", "export"], ["strings", "import"]] {
        for flag in ["-h", "--help"] {
            let result = try fixture.run(command + [flag])
            #expect(result.status == 0)
            #expect(result.err.isEmpty)
            #expect(result.out.contains("Examples:"))
            #expect(result.out.contains("USAGE:"))
        }
    }
    let export = try fixture.run(["strings", "export", "--help"])
    #expect(export.out.contains("Replace existing JSON, CSV"))
    #expect(export.out.contains("edit only the translation column"))
    #expect(export.out.split(whereSeparator: \.isWhitespace).joined(separator: " ").contains("translations marked missing, new, or needs review"))
    #expect(export.out.contains("needs_review"))
    let preview = try fixture.run(["strings", "import", "--help"])
    #expect(preview.out.contains("apply changes to one catalog"))
    #expect(preview.out.contains("review status"))
    #expect(preview.out.split(whereSeparator: \.isWhitespace).joined(separator: " ").contains("same catalog root"))
}

@Test func emptyHumanResultsExplainScopeWithoutClaimingCompletion() throws {
    let fixture = try Fixture()
    defer { fixture.remove() }
    try fixture.write("Localizable.xcstrings", catalog)
    let filtered = try fixture.run(["strings", "list", "--language", "fr", "--status", "needs_review", "--no-input"])
    #expect(filtered.status == 0)
    #expect(filtered.err.isEmpty)
    #expect(filtered.out.contains("No translations match"))
    #expect(filtered.out.contains("Remove --language or --status"))
    try fixture.write("Localizable.xcstrings", #"{"version":"1.0","sourceLanguage":"en","strings":{}}"#)
    let empty = try fixture.run(["strings", "list"])
    #expect(empty.status == 0)
    #expect(empty.out.contains("--include-excluded"))
    let all = try fixture.run(["strings", "list", "--include-excluded"])
    #expect(all.status == 0)
    #expect(all.out.contains("No translations to list in the selected catalogs"))
    #expect(!all.out.contains("--include-excluded"))
    let coverage = try fixture.run(["strings", "languages"])
    #expect(coverage.status == 0)
    #expect(coverage.err.isEmpty)
    #expect(coverage.out.contains("no translations counted"))
    #expect(!coverage.out.contains("0/0"))
}

@Test func unknownLanguageGuidanceUsesTheSelectedCatalogScope() throws {
    let fixture = try Fixture()
    defer { fixture.remove() }
    try fixture.write("App/Localizable.xcstrings", catalog)
    for command in ["list", "export"] {
        let result = try fixture.run(["strings", command, "App", "--language", "zz", "--no-input"])
        #expect(result.status == (command == "list" ? 64 : 1))
        #expect(result.out.isEmpty)
        #expect(result.err.contains("Languages not found in the selected catalogs: zz"))
        #expect(result.err.contains("same catalog paths"))
    }
}
