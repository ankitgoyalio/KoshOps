import Foundation

/// Checks that a localized format string consumes the same arguments as its source.
///
/// The comparison is deliberately conservative: syntax which is not part of the
/// supported printf/Foundation subset is rejected instead of being guessed at.
internal func validatePlaceholders(source: String, translation: String) throws {
    let sourceArguments = try parsePlaceholders(source, label: "source")
    let translationArguments = try parsePlaceholders(translation, label: "translation")

    if sourceArguments != translationArguments {
        throw InspectionError("Incompatible format placeholders between source and translation. Preserve every argument index and type (including width and precision '*' arguments); positional reordering is allowed. Source: \(describe(sourceArguments)); translation: \(describe(translationArguments)).")
    }
}

private struct PlaceholderType: Equatable {
    let name: String

    var description: String {
        return name
    }
}

private struct PlaceholderArguments: Equatable {
    var types: [Int: PlaceholderType] = [:]
}

private func parsePlaceholders(_ value: String, label: String) throws -> PlaceholderArguments {
    let bytes = Array(value.utf8)
    var result = PlaceholderArguments()
    var cursor = 0
    var nextImplicitIndex = 1
    var usesPositional = false
    var usesImplicit = false

    func fail(_ reason: String) throws -> Never {
        throw InspectionError("Unsupported format placeholder in \(label) string: \(reason) Check the '%' syntax and keep the source and translation placeholders compatible.")
    }
    func register(_ index: Int, _ type: PlaceholderType) throws {
        if let existing = result.types[index], existing != type {
            try fail("argument \(index) is used with both \(existing.description) and \(type.description) types")
        }
        result.types[index] = type
    }
    func argumentIndex(_ explicit: Int?) throws -> Int {
        if let explicit {
            usesPositional = true
            return explicit
        }
        usesImplicit = true
        defer { nextImplicitIndex += 1 }
        return nextImplicitIndex
    }
    func readNumber() -> Int? {
        let start = cursor
        while cursor < bytes.count, bytes[cursor] >= 48, bytes[cursor] <= 57 { cursor += 1 }
        return cursor == start ? nil : Int(String(decoding: bytes[start..<cursor], as: UTF8.self))
    }
    func readPositionalIndex() -> Int? {
        let save = cursor
        guard let number = readNumber(), number > 0, cursor < bytes.count, bytes[cursor] == 36 else {
            cursor = save
            return nil
        }
        cursor += 1
        return number
    }

    while cursor < bytes.count {
        guard bytes[cursor] == 37 else { cursor += 1; continue }
        cursor += 1
        guard cursor < bytes.count else { try fail("a '%' must be followed by a conversion") }
        if bytes[cursor] == 37 { cursor += 1; continue }

        let conversionIndex = readPositionalIndex()
        let flags: Set<UInt8> = [45, 43, 32, 35, 48, 39]
        while cursor < bytes.count, flags.contains(bytes[cursor]) { cursor += 1 }

        if cursor < bytes.count, bytes[cursor] == 42 {
            cursor += 1
            let widthIndex = try argumentIndex(readPositionalIndex())
            try register(widthIndex, PlaceholderType(name: "signed-integer:"))
        } else { _ = readNumber() }

        if cursor < bytes.count, bytes[cursor] == 46 {
            cursor += 1
            guard cursor < bytes.count else { try fail("precision is incomplete") }
            if bytes[cursor] == 42 {
                cursor += 1
                let precisionIndex = try argumentIndex(readPositionalIndex())
                try register(precisionIndex, PlaceholderType(name: "signed-integer:"))
            } else { _ = readNumber() }
        }

        let lengthStart = cursor
        if cursor + 1 < bytes.count, (bytes[cursor] == 104 && bytes[cursor + 1] == 104) || (bytes[cursor] == 108 && bytes[cursor + 1] == 108) {
            cursor += 2
        } else if cursor < bytes.count, Set([104, 108, 106, 122, 116, 76, 113]).contains(bytes[cursor]) {
            cursor += 1
        }
        guard cursor < bytes.count else { try fail("conversion is incomplete") }
        let conversionPosition = cursor
        let conversion = bytes[cursor]
        cursor += 1
        var modifier = String(decoding: bytes[lengthStart..<conversionPosition], as: UTF8.self)
        if modifier == "q" { modifier = "ll" }
        if conversion == 102 || conversion == 70 || conversion == 101 || conversion == 69 || conversion == 103 || conversion == 71 || conversion == 97 || conversion == 65, modifier == "l" {
            modifier = ""
        }
        let type: PlaceholderType
        switch conversion {
        case 100, 105, 68:
            guard ["", "h", "hh", "l", "ll", "j", "q", "t", "z"].contains(modifier) else {
                try fail("length modifier '\(modifier)' is invalid for signed integer conversion")
            }
            type = PlaceholderType(name: "signed-integer:\(modifier)")
        case 111, 117, 120, 88, 79, 85:
            guard ["", "h", "hh", "l", "ll", "j", "q", "t", "z"].contains(modifier) else {
                try fail("length modifier '\(modifier)' is invalid for unsigned integer conversion")
            }
            type = PlaceholderType(name: "unsigned-integer:\(modifier)")
        case 99:
            guard modifier.isEmpty else { try fail("length modifier '\(modifier)' is invalid for character conversion") }
            type = PlaceholderType(name: "character")
        case 67:
            guard modifier.isEmpty else { try fail("length modifier '\(modifier)' is invalid for wide character conversion") }
            type = PlaceholderType(name: "character:wide")
        case 97, 65, 101, 69, 102, 70, 103, 71:
            guard modifier.isEmpty || modifier == "L" else { try fail("length modifier '\(modifier)' is invalid for floating conversion") }
            type = PlaceholderType(name: "floating:\(modifier)")
        case 115:
            guard modifier.isEmpty || modifier == "l" else { try fail("length modifier '\(modifier)' is invalid for string conversion") }
            type = PlaceholderType(name: modifier == "l" ? "string:wide" : "string")
        case 83:
            guard modifier.isEmpty else { try fail("length modifier '\(modifier)' is invalid for wide string conversion") }
            type = PlaceholderType(name: "string:wide")
        case 64:
            guard modifier.isEmpty else { try fail("length modifier '\(modifier)' is invalid for %@") }
            type = PlaceholderType(name: "object")
        case 112:
            guard modifier.isEmpty else { try fail("length modifier '\(modifier)' is invalid for %p") }
            type = PlaceholderType(name: "pointer")
        default: try fail("conversion '%\(Character(UnicodeScalar(conversion)))' is unsupported")
        }
        try register(try argumentIndex(conversionIndex), type)
    }
    if usesPositional && usesImplicit { try fail("mixing positional and implicit argument indexes is unsupported") }
    if usesPositional, let maximum = result.types.keys.max(), maximum != result.types.count {
        try fail("positional arguments must include every index from 1 through \(maximum)")
    }
    return result
}

private func describe(_ arguments: PlaceholderArguments) -> String {
    arguments.types.keys.sorted().map { "\($0)=\(arguments.types[$0]!.description)" }.joined(separator: ", ")
}
