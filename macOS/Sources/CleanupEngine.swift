import AppKit
import Foundation

struct CleanupItem: Identifiable, Hashable {
    let id = UUID()
    let url: URL
    let kind: String
    let size: Int64
    let detail: String
    var selected: Bool

    var displayName: String { kind == "Application" ? url.deletingPathExtension().lastPathComponent : url.lastPathComponent }
}

struct StorageSnapshot {
    let total: Int64
    let freeNow: Int64
    let availableAfterPurge: Int64

    var systemReclaimable: Int64 { max(0, availableAfterPurge - freeNow) }
}

enum CleanupError: LocalizedError {
    case invalidApp
    case protectedApp
    case nothingSelected
    case recycleFailed(String)

    var errorDescription: String? {
        switch self {
        case .invalidApp: return "Choose a macOS application ending in .app."
        case .protectedApp: return "Apps supplied by macOS are protected and cannot be removed here."
        case .nothingSelected: return "Select at least one item first."
        case .recycleFailed(let message): return message
        }
    }
}

enum CleanupEngine {
    private static let fileManager = FileManager.default
    private static let home = fileManager.homeDirectoryForCurrentUser

    static func storageSnapshot() -> StorageSnapshot {
        let root = URL(fileURLWithPath: "/")
        let keys: Set<URLResourceKey> = [
            .volumeTotalCapacityKey,
            .volumeAvailableCapacityKey,
            .volumeAvailableCapacityForImportantUsageKey
        ]
        let values = try? root.resourceValues(forKeys: keys)
        let total = Int64(values?.volumeTotalCapacity ?? 0)
        let free = Int64(values?.volumeAvailableCapacity ?? 0)
        let important = values?.volumeAvailableCapacityForImportantUsage ?? free
        return StorageSnapshot(total: total, freeNow: free, availableAfterPurge: important)
    }

    static func validate(appURL: URL) throws {
        guard appURL.pathExtension.lowercased() == "app",
              Bundle(url: appURL) != nil else { throw CleanupError.invalidApp }
        let normalized = appURL.standardizedFileURL.path
        if normalized.hasPrefix("/System/") {
            throw CleanupError.protectedApp
        }
    }

    static func scanApp(at appURL: URL) throws -> [CleanupItem] {
        try validate(appURL: appURL)
        guard let bundle = Bundle(url: appURL) else { throw CleanupError.invalidApp }

        let bundleID = bundle.bundleIdentifier ?? ""
        let appName = (bundle.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String)
            ?? (bundle.object(forInfoDictionaryKey: "CFBundleName") as? String)
            ?? appURL.deletingPathExtension().lastPathComponent
        let tokens = searchTokens(bundleID: bundleID, appName: appName)
        var candidates: [(URL, String, String, Bool)] = [(appURL, "Application", "The application itself", true)]

        var exactPaths: [(String, String)] = [
            ("Library/Application Support/\(appName)", "Application Support"),
            ("Library/Logs/\(appName)", "Logs")
        ]
        if !bundleID.isEmpty {
            exactPaths += [
                ("Library/Application Support/\(bundleID)", "Application Support"),
                ("Library/Caches/\(bundleID)", "Cache"),
                ("Library/Containers/\(bundleID)", "Container"),
                ("Library/HTTPStorages/\(bundleID)", "Web storage"),
                ("Library/WebKit/\(bundleID)", "Web data"),
                ("Library/Preferences/\(bundleID).plist", "Preferences"),
                ("Library/Saved Application State/\(bundleID).savedState", "Saved state")
            ]
        }

        for (path, kind) in exactPaths {
            let url = home.appendingPathComponent(path)
            if fileManager.fileExists(atPath: url.path) {
                candidates.append((url, kind, "Exact match", true))
            }
        }

        let searchRoots: [(String, String)] = [
            ("Library/Caches", "Cache"),
            ("Library/Preferences", "Preferences"),
            ("Library/Application Support", "Application Support"),
            ("Library/LaunchAgents", "Launch agent"),
            ("Library/Group Containers", "Shared container"),
            ("Library/Logs", "Logs")
        ]

        for (relative, kind) in searchRoots {
            let root = home.appendingPathComponent(relative)
            guard let entries = try? fileManager.contentsOfDirectory(at: root, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]) else { continue }
            for entry in entries where matches(entry.lastPathComponent, tokens: tokens) {
                let shared = kind == "Shared container"
                candidates.append((entry, kind, shared ? "May be shared with related apps; review carefully" : "Name match", !shared))
            }
        }

        var seen = Set<String>()
        return candidates.compactMap { url, kind, detail, selected in
            let path = url.standardizedFileURL.path
            guard seen.insert(path).inserted else { return nil }
            let note = fileManager.isWritableFile(atPath: url.path) ? detail : detail + " · macOS may ask for administrator access"
            return CleanupItem(url: url, kind: kind, size: allocatedSize(at: url), detail: note, selected: selected)
        }.sorted { lhs, rhs in
            if lhs.kind == "Application" { return true }
            if rhs.kind == "Application" { return false }
            return lhs.size > rhs.size
        }
    }

    static func scanReclaimable() -> [CleanupItem] {
        var items: [CleanupItem] = []
        let roots: [(String, String, String)] = [
            ("Library/Caches", "Cache", "Apps recreate caches when needed"),
            ("Library/Logs", "Logs", "Diagnostic history"),
            ("Library/Developer/Xcode/DerivedData", "Developer", "Regenerable Xcode build data"),
            ("Library/Developer/Xcode/Archives", "Developer", "Archived app builds; review before removing"),
            ("Library/Developer/CoreSimulator/Caches", "Developer", "Regenerable Simulator cache")
        ]

        for (relative, kind, detail) in roots {
            let root = home.appendingPathComponent(relative)
            guard fileManager.fileExists(atPath: root.path) else { continue }
            if kind == "Cache" || kind == "Logs" {
                guard let entries = try? fileManager.contentsOfDirectory(at: root, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles]) else { continue }
                let lock = NSLock()
                DispatchQueue.concurrentPerform(iterations: entries.count) { index in
                    let entry = entries[index]
                    let size = allocatedSize(at: entry)
                    if size >= 25_000_000 {
                        let item = CleanupItem(url: entry, kind: kind, size: size, detail: detail, selected: false)
                        lock.lock(); items.append(item); lock.unlock()
                    }
                }
            } else {
                let size = allocatedSize(at: root)
                if size > 0 {
                    items.append(CleanupItem(url: root, kind: kind, size: size, detail: detail, selected: false))
                }
            }
        }
        return items.sorted { $0.size > $1.size }
    }

    static func recycle(_ urls: [URL]) async throws {
        guard !urls.isEmpty else { throw CleanupError.nothingSelected }
        for url in urls {
            guard fileManager.fileExists(atPath: url.path) else { continue }
            do {
                _ = try await NSWorkspace.shared.recycle([url])
            } catch {
                throw CleanupError.recycleFailed("Could not move \(url.lastPathComponent) to Trash: \(error.localizedDescription)")
            }
        }
    }

    static func emptyTrash() -> Bool {
        let script = "tell application \"Finder\" to empty trash"
        var errorInfo: NSDictionary?
        let result = NSAppleScript(source: script)?.executeAndReturnError(&errorInfo)
        return result != nil && errorInfo == nil
    }

    static func allocatedSize(at url: URL) -> Int64 {
        let keys: Set<URLResourceKey> = [.isRegularFileKey, .fileAllocatedSizeKey, .totalFileAllocatedSizeKey]
        if let values = try? url.resourceValues(forKeys: keys), values.isRegularFile == true {
            return Int64(values.totalFileAllocatedSize ?? values.fileAllocatedSize ?? 0)
        }
        let options: FileManager.DirectoryEnumerationOptions = url.pathExtension.lowercased() == "app" ? [] : [.skipsPackageDescendants]
        guard let enumerator = fileManager.enumerator(at: url, includingPropertiesForKeys: Array(keys), options: options, errorHandler: { _, _ in true }) else { return 0 }
        var total: Int64 = 0
        for case let fileURL as URL in enumerator {
            if let values = try? fileURL.resourceValues(forKeys: keys), values.isRegularFile == true {
                total += Int64(values.totalFileAllocatedSize ?? values.fileAllocatedSize ?? 0)
            }
        }
        return total
    }

    private static func searchTokens(bundleID: String, appName: String) -> [String] {
        var tokens = [appName.lowercased().replacingOccurrences(of: " ", with: "")]
        if !bundleID.isEmpty {
            tokens.append(bundleID.lowercased())
            if let last = bundleID.split(separator: ".").last, last.count >= 4 {
                tokens.append(String(last).lowercased())
            }
        }
        return Array(Set(tokens.filter { $0.count >= 4 }))
    }

    private static func matches(_ name: String, tokens: [String]) -> Bool {
        let normalized = name.lowercased().replacingOccurrences(of: " ", with: "")
        return tokens.contains { normalized == $0 || normalized.hasPrefix($0 + ".") || normalized.hasSuffix("." + $0) }
    }
}
