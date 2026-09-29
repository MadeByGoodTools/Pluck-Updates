import Foundation

@main
enum SmokeTest {
    static func main() async throws {
        let snapshot = CleanupEngine.storageSnapshot()
        precondition(snapshot.total > 0)
        precondition(snapshot.freeNow >= 0)
        precondition(snapshot.availableAfterPurge >= snapshot.freeNow)

        let candidates = [
            "/Applications/Dia.app",
            "/Applications/Utilities/Terminal.app",
            "/System/Applications/Calculator.app"
        ]
        guard let sample = candidates.map(URL.init(fileURLWithPath:)).first(where: { FileManager.default.fileExists(atPath: $0.path) }) else {
            throw NSError(domain: "SmokeTest", code: 1, userInfo: [NSLocalizedDescriptionKey: "No sample app found"])
        }
        if sample.path.hasPrefix("/System/") {
            do {
                try CleanupEngine.validate(appURL: sample)
                preconditionFailure("System app was not protected")
            } catch CleanupError.protectedApp { }
        } else {
            let results = try CleanupEngine.scanApp(at: sample)
            precondition(results.first?.kind == "Application")
            precondition(results.first?.url == sample)
        }

        let temporaryTrash = FileManager.default.temporaryDirectory
            .appendingPathComponent("Pluck-Smoke-Trash-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: temporaryTrash, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: temporaryTrash) }
        try Data("test".utf8).write(to: temporaryTrash.appendingPathComponent("ordinary.txt"))
        try Data("hidden".utf8).write(to: temporaryTrash.appendingPathComponent(".hidden"))
        let nested = temporaryTrash.appendingPathComponent("Folder", isDirectory: true)
        try FileManager.default.createDirectory(at: nested, withIntermediateDirectories: true)
        try Data("nested".utf8).write(to: nested.appendingPathComponent("nested.txt"))
        let removed = try await CleanupEngine.emptyTrash(
            at: [temporaryTrash],
            requestAdministratorIfNeeded: false
        )
        precondition(removed == 3)
        let remaining = try FileManager.default.contentsOfDirectory(atPath: temporaryTrash.path)
        precondition(remaining.isEmpty)
        print("Smoke test passed")
    }
}
