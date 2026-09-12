import AppKit
import Foundation
import UniformTypeIdentifiers

private func birdHeadImage(pointSize: CGFloat) -> NSImage {
    let image = NSImage(size: NSSize(width: pointSize, height: pointSize), flipped: false) { rect in
        let w = rect.width
        let h = rect.height
        NSColor.black.setFill()
        NSBezierPath(ovalIn: NSRect(x: 0.10 * w, y: 0.15 * h, width: 0.70 * w, height: 0.70 * h)).fill()
        let beak = NSBezierPath()
        beak.move(to: NSPoint(x: 0.68 * w, y: 0.64 * h))
        beak.line(to: NSPoint(x: 0.98 * w, y: 0.50 * h))
        beak.line(to: NSPoint(x: 0.68 * w, y: 0.42 * h))
        beak.close()
        beak.fill()

        NSGraphicsContext.current?.cgContext.setBlendMode(.clear)
        NSBezierPath(ovalIn: NSRect(x: 0.48 * w, y: 0.61 * h, width: 0.10 * w, height: 0.10 * h)).fill()
        NSGraphicsContext.current?.cgContext.setBlendMode(.normal)
        return true
    }
    image.isTemplate = true
    image.accessibilityDescription = "Pluck bird head"
    return image
}

private func birdBadgeImage(pointSize: CGFloat) -> NSImage {
    let image = NSImage(size: NSSize(width: pointSize, height: pointSize), flipped: false) { rect in
        let w = rect.width
        let h = rect.height
        NSColor(calibratedRed: 0.64, green: 0.28, blue: 0.68, alpha: 1).setFill()
        NSBezierPath(roundedRect: rect.insetBy(dx: 0.5, dy: 0.5), xRadius: 0.22 * w, yRadius: 0.22 * h).fill()

        NSColor.white.setFill()
        NSBezierPath(ovalIn: NSRect(x: 0.20 * w, y: 0.20 * h, width: 0.58 * w, height: 0.58 * h)).fill()
        let beak = NSBezierPath()
        beak.move(to: NSPoint(x: 0.66 * w, y: 0.58 * h))
        beak.line(to: NSPoint(x: 0.90 * w, y: 0.48 * h))
        beak.line(to: NSPoint(x: 0.66 * w, y: 0.39 * h))
        beak.close()
        beak.fill()

        NSColor.black.setFill()
        NSBezierPath(ovalIn: NSRect(x: 0.45 * w, y: 0.59 * h, width: 0.09 * w, height: 0.09 * h)).fill()
        return true
    }
    image.accessibilityDescription = "Pluck"
    return image
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private let popover = NSPopover()

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.appearance = NSAppearance(named: .darkAqua)
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let button = statusItem.button {
            button.image = birdHeadImage(pointSize: 18)
            button.title = ""
            button.target = self
            button.action = #selector(togglePopover)
            button.toolTip = "Pluck — pull out apps and their leftovers"
        }
        popover.contentSize = NSSize(width: 560, height: 680)
        popover.appearance = NSAppearance(named: .darkAqua)
        popover.behavior = .transient
        popover.animates = true
        popover.contentViewController = PanelController()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { [weak self] in
            NSApp.activate(ignoringOtherApps: true)
            self?.showPopover()
        }
    }

    @objc private func togglePopover() {
        guard let button = statusItem.button else { return }
        if popover.isShown { popover.performClose(nil) }
        else { popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY) }
    }

    private func showPopover() {
        guard let button = statusItem.button, !popover.isShown else { return }
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        popover.contentViewController?.view.window?.makeKey()
    }
}

final class PanelController: NSViewController, NSTableViewDataSource, NSTableViewDelegate {
    private let segmented = NSSegmentedControl(labels: ["Uninstall", "Reclaim"], trackingMode: .selectOne, target: nil, action: nil)
    private let permissionLabel = NSTextField(labelWithString: "")
    private let storageLabel = NSTextField(wrappingLabelWithString: "")
    private let storageCard = NSView()
    private let messageLabel = NSTextField(wrappingLabelWithString: "Drop an app here, or choose one below. Related files are shown before anything moves.")
    private let table = NSTableView()
    private let scroll = NSScrollView()
    private let primary = NSButton(title: "Choose App…", target: nil, action: nil)
    private let utility = NSButton(title: "Permissions", target: nil, action: nil)
    private let refresh = NSButton(title: "Refresh", target: nil, action: nil)
    private let quit = NSButton(title: "Quit", target: nil, action: nil)
    private let emptyTrash = NSButton(title: "Empty Trash…", target: nil, action: nil)
    private let progress = NSProgressIndicator()
    private let dropView = DropView()

    private var appItems: [CleanupItem] = []
    private var installedApps: [CleanupItem] = []
    private var reclaimItems: [CleanupItem] = []
    private var systemPurgeableBytes: Int64 = 0
    private var busy = false { didSet { updateUI() } }
    private var reclaimMode: Bool { segmented.selectedSegment == 1 }

    override func loadView() {
        view = NSView(frame: NSRect(x: 0, y: 0, width: 560, height: 680))
        makeUI()
        refreshPermission()
        refreshStorage()
        loadInstalledApps()
    }

    override func viewDidAppear() {
        super.viewDidAppear()
        refreshPermission()
        refreshStorage()
    }

    private func makeUI() {
        let icon = NSImageView(image: birdBadgeImage(pointSize: 36))
        icon.imageScaling = .scaleProportionallyUpOrDown
        icon.translatesAutoresizingMaskIntoConstraints = false
        icon.widthAnchor.constraint(equalToConstant: 36).isActive = true
        icon.heightAnchor.constraint(equalToConstant: 36).isActive = true
        let title = NSTextField(labelWithString: "Pluck")
        title.font = .systemFont(ofSize: 22, weight: .bold)
        let brand = NSTextField(labelWithString: "by Good Tools")
        brand.textColor = .secondaryLabelColor
        let heading = NSStackView(views: [icon, title, brand, NSView(), quit])
        heading.orientation = .horizontal
        heading.alignment = .centerY
        heading.spacing = 8

        quit.isBordered = false
        quit.font = .systemFont(ofSize: 11)
        quit.target = self
        quit.action = #selector(quitApp)

        segmented.selectedSegment = 0
        segmented.target = self
        segmented.action = #selector(modeChanged)

        permissionLabel.font = .systemFont(ofSize: 11, weight: .medium)
        utility.font = .systemFont(ofSize: 11)
        utility.bezelStyle = .inline
        utility.target = self
        utility.action = #selector(openPermissions)
        let permissionRow = NSStackView(views: [permissionLabel, NSView(), utility])
        permissionRow.orientation = .horizontal
        permissionRow.alignment = .centerY

        storageLabel.font = .monospacedDigitSystemFont(ofSize: 12, weight: .regular)
        storageLabel.textColor = .secondaryLabelColor
        storageLabel.maximumNumberOfLines = 2
        storageLabel.alignment = .center
        storageLabel.translatesAutoresizingMaskIntoConstraints = false
        storageCard.wantsLayer = true
        storageCard.layer?.cornerRadius = 10
        storageCard.layer?.backgroundColor = NSColor.controlAccentColor.withAlphaComponent(0.16).cgColor
        storageCard.layer?.borderColor = NSColor.controlAccentColor.withAlphaComponent(0.24).cgColor
        storageCard.layer?.borderWidth = 1
        storageCard.addSubview(storageLabel)
        NSLayoutConstraint.activate([
            storageCard.heightAnchor.constraint(equalToConstant: 60),
            storageLabel.centerXAnchor.constraint(equalTo: storageCard.centerXAnchor),
            storageLabel.centerYAnchor.constraint(equalTo: storageCard.centerYAnchor),
            storageLabel.leadingAnchor.constraint(greaterThanOrEqualTo: storageCard.leadingAnchor, constant: 10),
            storageLabel.trailingAnchor.constraint(lessThanOrEqualTo: storageCard.trailingAnchor, constant: -10)
        ])

        messageLabel.alignment = .center
        messageLabel.textColor = .secondaryLabelColor
        messageLabel.maximumNumberOfLines = 3

        dropView.onDrop = { [weak self] url in self?.scanApp(url) }
        let emptyState = NSStackView(views: [NSImageView(image: NSImage(systemSymbolName: "app.dashed", accessibilityDescription: nil)!), messageLabel])
        emptyState.orientation = .vertical
        emptyState.alignment = .centerX
        emptyState.spacing = 14
        emptyState.edgeInsets = NSEdgeInsets(top: 45, left: 25, bottom: 35, right: 25)
        dropView.addPinnedSubview(emptyState)

        let check = NSTableColumn(identifier: .init("check")); check.width = 34; check.minWidth = 34; check.maxWidth = 34; check.resizingMask = []
        let item = NSTableColumn(identifier: .init("item")); item.width = 340; item.minWidth = 260; item.maxWidth = 340; item.resizingMask = []
        let size = NSTableColumn(identifier: .init("size")); size.width = 110; size.minWidth = 110; size.maxWidth = 110; size.resizingMask = []
        table.addTableColumn(check); table.addTableColumn(item); table.addTableColumn(size)
        table.columnAutoresizingStyle = .noColumnAutoresizing
        table.headerView = nil
        table.rowHeight = 56
        table.usesAlternatingRowBackgroundColors = false
        table.selectionHighlightStyle = .none
        table.backgroundColor = .clear
        table.delegate = self
        table.dataSource = self
        scroll.documentView = table
        scroll.hasVerticalScroller = true
        scroll.hasHorizontalScroller = false
        scroll.horizontalScrollElasticity = .none
        scroll.borderType = .bezelBorder

        progress.style = .spinning
        progress.controlSize = .small
        refresh.target = self
        refresh.action = #selector(refreshAction)
        emptyTrash.target = self
        emptyTrash.action = #selector(emptyTrashAction)
        primary.target = self
        primary.action = #selector(primaryAction)
        primary.keyEquivalent = "\r"
        let actions = NSStackView(views: [progress, refresh, NSView(), emptyTrash, primary])
        actions.orientation = .horizontal
        actions.alignment = .centerY
        actions.spacing = 8

        let root = NSStackView(views: [heading, segmented, permissionRow, storageCard, dropView, scroll, actions])
        root.orientation = .vertical
        root.alignment = .leading
        root.spacing = 12
        root.edgeInsets = NSEdgeInsets(top: 16, left: 18, bottom: 20, right: 18)
        root.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(root)
        for child in [heading, segmented, permissionRow, storageCard, dropView, scroll, actions] {
            child.widthAnchor.constraint(equalTo: root.widthAnchor, constant: -36).isActive = true
        }
        NSLayoutConstraint.activate([
            root.leadingAnchor.constraint(equalTo: view.leadingAnchor), root.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            root.topAnchor.constraint(equalTo: view.topAnchor), root.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            dropView.heightAnchor.constraint(greaterThanOrEqualToConstant: 350),
            scroll.heightAnchor.constraint(greaterThanOrEqualToConstant: 350)
        ])
        updateUI()
    }

    @objc private func modeChanged() {
        if reclaimMode && reclaimItems.isEmpty { scanReclaimable() }
        if !reclaimMode && installedApps.isEmpty { loadInstalledApps() }
        table.reloadData()
        updateUI()
    }

    @objc private func primaryAction() {
        if reclaimMode {
            let items = reclaimItems.filter { $0.selected && $0.kind != "Trash" }
            guard !items.isEmpty else { return }
            let bytes = items.reduce(0) { $0 + $1.size }
            let alert = NSAlert()
            alert.messageText = "Reclaim \(format(bytes))?"
            alert.informativeText = "Pluck will move the safe cache, log, and developer items shown below to Trash. macOS continues to manage the rest of its purgeable space automatically."
            alert.addButton(withTitle: "Reclaim Space")
            alert.addButton(withTitle: "Cancel")
            if alert.runModal() == .alertFirstButtonReturn { recycle(items, appMode: false) }
        } else {
            uninstallSelectedApps()
        }
    }

    @objc private func refreshAction() {
        if reclaimMode { scanReclaimable() }
        else { loadInstalledApps() }
    }

    private func loadInstalledApps() {
        busy = true
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let manager = FileManager.default
            let roots = [URL(fileURLWithPath: "/Applications"), manager.homeDirectoryForCurrentUser.appendingPathComponent("Applications")]
            var seen = Set<String>()
            var apps: [CleanupItem] = []
            for root in roots {
                guard let entries = try? manager.contentsOfDirectory(at: root, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]) else { continue }
                for url in entries where url.pathExtension.lowercased() == "app" {
                    guard Bundle(url: url)?.bundleIdentifier != "ca.goodtools.pluck" else { continue }
                    let path = url.standardizedFileURL.path
                    guard seen.insert(path).inserted else { continue }
                    apps.append(CleanupItem(url: url, kind: "Application", size: 0, detail: root.path == "/Applications" ? "Applications" : "Your Applications", selected: false))
                }
            }
            apps.sort { $0.displayName.localizedStandardCompare($1.displayName) == .orderedAscending }
            let discovered = apps
            var sizes = Array(repeating: Int64(0), count: discovered.count)
            let sizeLock = NSLock()
            let sizeQueue = OperationQueue()
            sizeQueue.name = "ca.goodtools.pluck.app-sizes"
            sizeQueue.qualityOfService = .utility
            sizeQueue.maxConcurrentOperationCount = 4
            for index in discovered.indices {
                let url = discovered[index].url
                sizeQueue.addOperation {
                    let measured = CleanupEngine.allocatedSize(at: url)
                    sizeLock.lock()
                    sizes[index] = measured
                    sizeLock.unlock()
                }
            }
            sizeQueue.waitUntilAllOperationsAreFinished()
            apps = discovered.enumerated().map { index, item in
                CleanupItem(url: item.url, kind: item.kind, size: sizes[index], detail: item.detail, selected: item.selected)
            }
            DispatchQueue.main.async {
                guard let self else { return }
                self.installedApps = apps
                self.appItems = []
                self.busy = false
                self.table.reloadData()
                self.updateUI()
            }
        }
    }

    private func uninstallSelectedApps() {
        let selected = installedApps.filter(\.selected)
        guard !selected.isEmpty else { return }
        busy = true
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            var results: [CleanupItem] = []
            var seen = Set<String>()
            for app in selected {
                guard let found = try? CleanupEngine.scanApp(at: app.url) else { continue }
                for item in found where seen.insert(item.url.standardizedFileURL.path).inserted {
                    results.append(item)
                }
            }
            DispatchQueue.main.async {
                guard let self else { return }
                self.appItems = results
                let chosen = results.filter(\.selected)
                let relatedCount = chosen.filter { $0.kind != "Application" }.count
                let bytes = chosen.reduce(0) { $0 + $1.size }
                let alert = NSAlert()
                alert.messageText = "Uninstall \(selected.count == 1 ? selected[0].displayName : "\(selected.count) apps")?"
                alert.informativeText = "Pluck found \(relatedCount) high-confidence related item\(relatedCount == 1 ? "" : "s"). About \(self.format(bytes)) will move to Trash and remain recoverable until Trash is emptied."
                alert.addButton(withTitle: "Uninstall")
                alert.addButton(withTitle: "Cancel")
                alert.alertStyle = .warning
                if alert.runModal() == .alertFirstButtonReturn {
                    self.recycle(chosen, appMode: true)
                } else {
                    self.busy = false
                    self.updateUI()
                }
            }
        }
    }

    private func chooseApp() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.application]
        panel.allowsMultipleSelection = false
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        if panel.runModal() == .OK, let url = panel.url { scanApp(url) }
    }

    private func scanApp(_ url: URL) {
        busy = true
        messageLabel.stringValue = "Scanning \(url.deletingPathExtension().lastPathComponent)…"
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let result = Result { try CleanupEngine.scanApp(at: url) }
            DispatchQueue.main.async {
                guard let self else { return }
                switch result {
                case .success(let items):
                    self.appItems = items
                    self.messageLabel.stringValue = "Found \(max(0, items.count - 1)) related items. Review the list."
                case .failure(let error): self.messageLabel.stringValue = error.localizedDescription
                }
                self.busy = false
                self.table.reloadData()
                self.updateUI()
            }
        }
    }

    private func scanReclaimable() {
        busy = true
        DispatchQueue.global(qos: .utility).async { [weak self] in
            let items = CleanupEngine.scanReclaimable()
            DispatchQueue.main.async {
                guard let self else { return }
                self.reclaimItems = items
                for index in self.reclaimItems.indices where self.reclaimItems[index].kind != "Trash" {
                    self.reclaimItems[index].selected = true
                }
                self.busy = false
                self.refreshStorage()
                self.table.reloadData()
                self.updateUI()
            }
        }
    }

    private func recycle(_ items: [CleanupItem], appMode: Bool) {
        guard !items.isEmpty else { return }
        busy = true
        Task { @MainActor in
            do {
                try await CleanupEngine.recycle(items.map(\.url))
                if appMode { loadInstalledApps() } else { scanReclaimable() }
            } catch {
                let alert = NSAlert(); alert.messageText = "Couldn’t move an item"; alert.informativeText = error.localizedDescription; alert.runModal()
            }
            busy = false
            refreshStorage(); table.reloadData(); updateUI()
        }
    }

    @objc private func emptyTrashAction() {
        let alert = NSAlert()
        alert.messageText = "Empty Trash permanently?"
        alert.informativeText = "Every item currently in Trash will be deleted. This cannot be undone."
        alert.addButton(withTitle: "Empty Trash"); alert.addButton(withTitle: "Cancel")
        alert.alertStyle = .warning
        if alert.runModal() == .alertFirstButtonReturn { _ = CleanupEngine.emptyTrash(); refreshStorage(); scanReclaimable() }
    }

    @objc private func openPermissions() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles") { NSWorkspace.shared.open(url) }
    }

    @objc private func quitApp() { NSApp.terminate(nil) }

    private func refreshPermission() {
        let test = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Mail")
        if (try? FileManager.default.contentsOfDirectory(atPath: test.path)) != nil {
            permissionLabel.stringValue = "✓ Full Disk Access enabled"
            permissionLabel.textColor = .systemGreen
            utility.isHidden = true
        } else {
            permissionLabel.stringValue = "Full Disk Access recommended"
            permissionLabel.textColor = .labelColor
            utility.isHidden = false
        }
    }

    private func refreshStorage() {
        let s = CleanupEngine.storageSnapshot()
        systemPurgeableBytes = s.systemReclaimable
        storageLabel.stringValue = "FREE  \(format(s.freeNow))     PURGEABLE  \(format(s.systemReclaimable))\nAVAILABLE WHEN NEEDED  \(format(s.availableAfterPurge))"
    }

    private func updateUI() {
        let uninstallRows = installedApps
        let hasRows = reclaimMode ? !reclaimItems.isEmpty : !uninstallRows.isEmpty
        dropView.isHidden = hasRows || reclaimMode || !installedApps.isEmpty
        scroll.isHidden = !hasRows
        storageCard.isHidden = false
        emptyTrash.isHidden = !reclaimMode
        refresh.title = "Scan"
        refresh.isHidden = !reclaimMode
        let selected = (reclaimMode ? reclaimItems : uninstallRows).contains { $0.selected && $0.kind != "Trash" }
        primary.title = reclaimMode ? "Reclaim" : "Uninstall"
        primary.isEnabled = !busy && selected
        progress.isHidden = !busy
        if busy { progress.startAnimation(nil) } else { progress.stopAnimation(nil) }
        segmented.isEnabled = !busy
    }

    func numberOfRows(in tableView: NSTableView) -> Int { reclaimMode ? reclaimItems.count : installedApps.count }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let id = tableColumn?.identifier.rawValue ?? ""
        let index = row
        let value = reclaimMode ? reclaimItems[index] : installedApps[index]
        if id == "check" {
            let check = NSButton(checkboxWithTitle: "", target: self, action: #selector(toggle(_:)))
            check.state = value.selected ? .on : .off; check.tag = row
            check.isEnabled = value.kind != "Trash"
            return check
        }
        if id == "item" { return ItemCell(item: value) }
        let text = value.size == 0 ? "" : format(value.size)
        return SizeCell(text: text)
    }

    @objc private func toggle(_ sender: NSButton) {
        if reclaimMode {
            reclaimItems[sender.tag].selected = sender.state == .on
        } else { installedApps[sender.tag].selected = sender.state == .on }
        updateUI()
    }

    private func format(_ bytes: Int64) -> String { ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file) }
}

final class SizeCell: NSTableCellView {
    init(text: String) {
        super.init(frame: .zero)
        let label = NSTextField(labelWithString: text)
        label.font = .monospacedDigitSystemFont(ofSize: 12, weight: .regular)
        label.textColor = .secondaryLabelColor
        label.alignment = .right
        label.lineBreakMode = .byTruncatingTail
        label.translatesAutoresizingMaskIntoConstraints = false
        addSubview(label)
        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 4),
            label.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -22),
            label.centerYAnchor.constraint(equalTo: centerYAnchor)
        ])
    }
    required init?(coder: NSCoder) { fatalError() }
}

final class ItemCell: NSTableCellView {
    init(item: CleanupItem) {
        super.init(frame: .zero)
        let icon = NSImageView(image: NSWorkspace.shared.icon(forFile: item.url.path))
        icon.imageScaling = .scaleProportionallyUpOrDown
        icon.translatesAutoresizingMaskIntoConstraints = false
        let name = NSTextField(labelWithString: item.displayName)
        name.font = .systemFont(ofSize: 14, weight: .semibold)
        name.lineBreakMode = .byTruncatingTail
        let detail = NSTextField(labelWithString: item.kind == "Application" ? item.detail : "\(item.kind) · \(item.detail)")
        detail.font = .systemFont(ofSize: 11)
        detail.textColor = .secondaryLabelColor
        detail.lineBreakMode = .byTruncatingTail
        let labels = NSStackView(views: [name, detail])
        labels.orientation = .vertical
        labels.alignment = .leading
        labels.spacing = 1
        let row = NSStackView(views: [icon, labels])
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = 9
        row.translatesAutoresizingMaskIntoConstraints = false
        addSubview(row)
        NSLayoutConstraint.activate([
            icon.widthAnchor.constraint(equalToConstant: 34), icon.heightAnchor.constraint(equalToConstant: 34),
            row.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 4), row.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -4),
            row.centerYAnchor.constraint(equalTo: centerYAnchor)
        ])
    }
    required init?(coder: NSCoder) { fatalError() }
}

final class DropView: NSView {
    var onDrop: ((URL) -> Void)?
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true; layer?.cornerRadius = 12; layer?.borderWidth = 2
        layer?.borderColor = NSColor.separatorColor.cgColor; layer?.backgroundColor = NSColor.controlBackgroundColor.cgColor
        registerForDraggedTypes([.fileURL])
    }
    required init?(coder: NSCoder) { fatalError() }
    func addPinnedSubview(_ child: NSView) {
        child.translatesAutoresizingMaskIntoConstraints = false; addSubview(child)
        NSLayoutConstraint.activate([child.leadingAnchor.constraint(equalTo: leadingAnchor), child.trailingAnchor.constraint(equalTo: trailingAnchor), child.topAnchor.constraint(equalTo: topAnchor), child.bottomAnchor.constraint(equalTo: bottomAnchor)])
    }
    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation { layer?.borderColor = NSColor.controlAccentColor.cgColor; return .copy }
    override func draggingExited(_ sender: NSDraggingInfo?) { layer?.borderColor = NSColor.separatorColor.cgColor }
    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        layer?.borderColor = NSColor.separatorColor.cgColor
        guard let url = NSURL(from: sender.draggingPasteboard) as URL? else { return false }
        onDrop?(url); return true
    }
}
