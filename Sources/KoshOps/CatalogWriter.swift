import Darwin
import Foundation

/// Filesystem operations are injectable for deterministic write/interruption tests.
struct CatalogWriter {
    var stage: (URL, URL, Data) throws -> Void = { original, staging, data in
        // Copy metadata (including permissions) before changing only the staged contents.
        try FileManager.default.copyItem(at: original, to: staging)
        let handle = try FileHandle(forWritingTo: staging)
        defer { try? handle.close() }
        try handle.truncate(atOffset: 0)
        try handle.write(contentsOf: data)
        try handle.synchronize()
        try handle.close()
    }
    var publish: (URL, URL) throws -> Void = { staging, destination in
        guard rename(staging.path, destination.path) == 0 else {
            throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
        }
    }

    func replace(_ destination: URL, original: Data, updated: Data) throws {
        let directory = destination.deletingLastPathComponent()
        // Lock the parent rather than the replaced inode. Other KoshOps imports
        // in this directory fail promptly; closing the descriptor releases the lock.
        let lock = open(directory.path, O_RDONLY | O_CLOEXEC)
        guard lock >= 0 else {
            throw InspectionError("Cannot open catalog directory '\(directory.path)'. Check directory permissions and retry.")
        }
        defer { close(lock) }
        guard flock(lock, LOCK_EX | LOCK_NB) == 0 else {
            throw InspectionError("Cannot lock catalog directory '\(directory.path)'. Wait for other imports to finish, then retry.")
        }
        let staging = directory.appendingPathComponent(".koshops-import-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: staging) }
        do {
            try checkOriginal(destination, original: original)
            try stage(destination, staging, updated)
            try checkOriginal(destination, original: original)
            // Atomic within this directory: process interruption leaves the old
            // catalog or the complete new catalog. No fallible work follows rename.
            try publish(staging, destination)
        } catch {
            throw InspectionError("Cannot apply changes to '\(destination.path)': \(error). No catalog was replaced by this import. Check permissions and available disk space; if the catalog changed, export again and review before retrying.")
        }
    }

    private func checkOriginal(_ destination: URL, original: Data) throws {
        guard destination.resolvingSymlinksInPath() == destination,
              try Data(contentsOf: destination) == original else {
            throw InspectionError("Catalog changed during import. Stop other catalog writers")
        }
    }
}
