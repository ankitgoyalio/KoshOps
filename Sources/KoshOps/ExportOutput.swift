import Darwin
import Foundation

struct ExportFile {
    let path: String
    let data: Data
    let fileExtension: String
}

private struct PreparedExport {
    let destination: URL
    let staging: URL
    let original: URL?
}

/// Validate and stage both artifacts before publication. On a handled failure,
/// restore completed writes; interruption between publications is not atomic.
func publishExport(_ outputs: [ExportFile], overwrite: Bool) throws {
    let files = FileManager.default
    var prepared: [PreparedExport] = []
    var identities = Set<String>()
    var retainedBackups = Set<URL>()
    defer {
        for item in prepared {
            try? files.removeItem(at: item.staging)
            if let original = item.original, !retainedBackups.contains(original) { try? files.removeItem(at: original) }
        }
    }
    // Validation precedes staging so an invalid second path has no file effects.
    for output in outputs {
        let url = URL(fileURLWithPath: output.path).standardizedFileURL
        var directory: ObjCBool = false
        let exists = files.fileExists(atPath: url.path, isDirectory: &directory)
        guard !directory.boolValue else {
            throw InspectionError("Output '\(output.path)' is a directory. Provide a filename, such as '\(url.appendingPathComponent("translations." + output.fileExtension).path)'.")
        }
        let ext = url.pathExtension.lowercased()
        if ["json", "csv"].contains(ext), ext != output.fileExtension {
            let name = url.deletingPathExtension().appendingPathExtension(output.fileExtension).lastPathComponent
            throw InspectionError("Output '\(output.path)' has a .\(ext) extension, but this file requires \(output.fileExtension). Name the file '\(name)'.")
        }
        guard ext != "xcstrings" else {
            throw InspectionError("Output '\(output.path)' is a catalog path. Choose a .\(output.fileExtension) handoff file.")
        }
        let properties = try? url.resourceValues(forKeys: [.isSymbolicLinkKey, .isRegularFileKey])
        guard properties?.isSymbolicLink != true, !exists || properties?.isRegularFile == true else {
            throw InspectionError("Output '\(output.path)' is not a regular file or is a symbolic link. Choose a regular handoff file.")
        }
        let caseSensitive = (try? url.deletingLastPathComponent().resourceValues(forKeys: [.volumeSupportsCaseSensitiveNamesKey]))?.volumeSupportsCaseSensitiveNames == true
        let resolvedPath = url.resolvingSymlinksInPath().path
        let identity = caseSensitive ? resolvedPath : resolvedPath.lowercased()
        guard identities.insert(identity).inserted else {
            throw InspectionError("CSV and manifest resolve to the same output path. Choose separate files with --output and --manifest.")
        }
        guard overwrite || !exists else {
            throw InspectionError("Output '\(output.path)' already exists. Choose a new path or use --overwrite to replace the handoff.")
        }
    }
    do {
        for output in outputs {
            let destination = URL(fileURLWithPath: output.path).standardizedFileURL
            let staging = destination.deletingLastPathComponent().appendingPathComponent(".koshops-export-" + UUID().uuidString)
            let original = files.fileExists(atPath: destination.path)
                ? destination.deletingLastPathComponent().appendingPathComponent(".koshops-backup-" + destination.lastPathComponent + "-" + UUID().uuidString)
                : nil
            prepared.append(PreparedExport(destination: destination, staging: staging, original: original))
            if let original { try files.copyItem(at: destination, to: original) }
            try output.data.write(to: staging, options: [.withoutOverwriting])
        }
    } catch {
        throw InspectionError("Cannot prepare export: \(error.localizedDescription). Choose writable output and manifest paths; no handoff files changed.")
    }
    var published: [PreparedExport] = []
    do {
        for item in prepared {
            if overwrite {
                guard rename(item.staging.path, item.destination.path) == 0 else {
                    throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
                }
            } else {
                try files.linkItem(at: item.staging, to: item.destination)
            }
            published.append(item)
        }
    } catch {
        var recoveryFailures: [String] = []
        for item in published.reversed() {
            do {
                if let original = item.original {
                    guard rename(original.path, item.destination.path) == 0 else {
                        throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
                    }
                } else { try files.removeItem(at: item.destination) }
            } catch {
                var failure = "\(item.destination.path): \(error.localizedDescription)"
                if let original = item.original {
                    retainedBackups.insert(original)
                    failure += "; original retained at '\(original.path)'"
                }
                recoveryFailures.append(failure)
            }
        }
        let recovery = recoveryFailures.isEmpty ? "Earlier writes were restored." : "Recovery failed for " + recoveryFailures.joined(separator: "; ") + "."
        throw InspectionError("Cannot publish export: \(error.localizedDescription). \(recovery) Check both files before retrying with writable paths and --overwrite if needed.")
    }
}
