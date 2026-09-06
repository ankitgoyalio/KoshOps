import Darwin
import Foundation
import Testing
@testable import KoshOps

@Test(arguments: ["partialWrite", "interrupted", "replacement", "concurrentEdit", "locked"])
func importWriteFailureKeepsACompleteCatalog(_ failure: String) throws {
    let fixture = try Fixture()
    defer { fixture.remove() }
    let original = #"{"version":"1.0","sourceLanguage":"en","strings":{"Hello":{"localizations":{"fr":{"stringUnit":{"state":"new","value":"Bonjour"}}}}}}"#
    try fixture.write("Labels.xcstrings", original)
    let exported = try fixture.run(["strings", "export", ".", "--language", "fr"])
    #expect(exported.status == 0)
    var object = try #require(JSONSerialization.jsonObject(with: Data(exported.out.utf8)) as? [String: Any])
    var records = object["units"] as! [[String: Any]]
    records[0]["translation"] = "Salut"; records[0]["statusUpdate"] = "needs_review"
    object["units"] = records
    let handoff = fixture.root.appendingPathComponent("returned.json")
    try JSONSerialization.data(withJSONObject: object).write(to: handoff)
    let catalog = fixture.root.appendingPathComponent("Labels.xcstrings")
    let concurrent = original.replacingOccurrences(of: "Bonjour", with: "Coucou")
    var writer = CatalogWriter()
    let normalStage = writer.stage
    switch failure {
    case "partialWrite": writer.stage = { _, staging, _ in
        try Data("{partial".utf8).write(to: staging)
        throw POSIXError(.ENOSPC)
    }
    case "interrupted": writer.stage = { original, staging, data in
        try normalStage(original, staging, data)
        throw POSIXError(.EINTR)
    }
    case "replacement": writer.publish = { _, _ in throw POSIXError(.EACCES) }
    case "concurrentEdit": writer.stage = { original, staging, data in
        try normalStage(original, staging, data)
        try Data(concurrent.utf8).write(to: original)
    }
    default: break
    }
    let lock = open(fixture.root.path, O_RDONLY)
    defer { close(lock) }
    if failure == "locked" { #expect(flock(lock, LOCK_EX | LOCK_NB) == 0) }
    do {
        _ = try LocalizationWorkflow().importTranslations(input: handoff.path, format: .json,
            manifest: nil, statusUpdate: nil, destination: fixture.root.path, dryRun: false, writer: writer)
        Issue.record("Import must report the filesystem failure")
    } catch {
        #expect(String(describing: error).contains("retry"))
        #expect(String(describing: error).contains(failure == "locked" ? "lock" : "Cannot apply"))
    }
    #expect(try String(contentsOf: catalog, encoding: .utf8) == (failure == "concurrentEdit" ? concurrent : original))
    #expect(try FileManager.default.contentsOfDirectory(atPath: fixture.root.path).allSatisfy { !$0.hasPrefix(".koshops-import-") })
    if failure == "locked" { #expect(flock(lock, LOCK_UN) == 0) }
    if failure != "concurrentEdit" {
        let retry = try LocalizationWorkflow().importTranslations(input: handoff.path, format: .json,
            manifest: nil, statusUpdate: nil, destination: fixture.root.path, dryRun: false)
        #expect(retry.changes.count == 1)
        #expect(try String(contentsOf: catalog, encoding: .utf8).contains("Salut"))
    }
}
