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
