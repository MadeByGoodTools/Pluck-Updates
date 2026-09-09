import Foundation

@main
enum SmokeTest {
    static func main() throws {
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
        print("Smoke test passed")
    }
}
