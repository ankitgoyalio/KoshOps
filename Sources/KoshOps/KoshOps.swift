import ArgumentParser

@main
struct KoshOps: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "koshops",
        abstract: "Automate Xcode asset management.",
        version: "0.1.0",
        subcommands: [Strings.self]
    )

    @Flag(
        name: [.short, .long],
        help: "Include additional diagnostic output."
    )
    var verbose = false

    mutating func run() throws {
        throw CleanExit.helpRequest(self)
    }
}
