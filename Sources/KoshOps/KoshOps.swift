import ArgumentParser

@main
struct KoshOps: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "koshops",
        abstract: "Inspect and exchange translations in Xcode String Catalogs.",
        discussion: "Examples:\n  koshops strings languages .\n  koshops strings export . --language fr -o translations.json\n\nStart with 'koshops strings languages' to see languages and coverage. Run 'koshops strings --help' for the translation workflow. Catalogs are never changed.",
        version: "0.1.0",
        subcommands: [Strings.self]
    )

    @Flag(
        name: [.short, .long],
        help: "Reserved for additional diagnostics; currently has no effect."
    )
    var verbose = false

    mutating func run() throws {
        throw CleanExit.helpRequest(self)
    }
}
