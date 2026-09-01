import ArgumentParser
import Testing

@testable import KoshOps

@Test("The root command parses its global options")
func parsesGlobalOptions() throws {
    let command = try KoshOps.parse(["--verbose"])

    #expect(command.verbose)
}

@Test("The root command has stable CLI metadata")
func exposesCommandMetadata() {
    #expect(KoshOps.configuration.commandName == "koshops")
    #expect(KoshOps.configuration.version == "0.1.0")
}
