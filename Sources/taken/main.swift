import Cocoa
import Carbon.HIToolbox

struct Notebook {
    let name: String
    let isDefault: Bool
}

struct TakenConfig {
    let notebookDirectory: URL
    let defaultNotebook: String?

    static func load() -> TakenConfig {
        let environment = ProcessInfo.processInfo.environment
        let configDir = configDirectory(environment: environment)
        let notebookDir = notebookDirectory(environment: environment, configDir: configDir)
        let defaultNotebook = readTrimmedFile(at: configDir.appendingPathComponent("default_notebook"))
        return TakenConfig(notebookDirectory: notebookDir, defaultNotebook: defaultNotebook)
    }

    private static func configDirectory(environment: [String: String]) -> URL {
        if let custom = environment["TAKEN_CONFIG_DIR"], !custom.isEmpty {
            return URL(fileURLWithPath: custom, isDirectory: true)
        }
        return FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".config", isDirectory: true)
            .appendingPathComponent("taken", isDirectory: true)
    }

    private static func notebookDirectory(environment: [String: String], configDir: URL) -> URL {
        if let override = environment["TAKEN_DIR"], !override.isEmpty {
            return URL(fileURLWithPath: override, isDirectory: true)
        }
        let configFile = configDir.appendingPathComponent("notebooks_dir")
        if let override = readTrimmedFile(at: configFile), !override.isEmpty {
            return URL(fileURLWithPath: override, isDirectory: true)
        }
        return FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".taken", isDirectory: true)
            .appendingPathComponent("notebooks", isDirectory: true)
    }

    private static func readTrimmedFile(at url: URL) -> String? {
        guard let text = try? String(contentsOf: url, encoding: .utf8) else { return nil }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

final class NotebookProvider {
    func loadNotebooks() -> [Notebook] {
        let config = TakenConfig.load()
        let defaultName = config.defaultNotebook
        let fm = FileManager.default

        guard let urls = try? fm.contentsOfDirectory(
            at: config.notebookDirectory,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }

        let ignoredSuffixes = ["~", ".swp", ".swo", ".swx", ".bak", ".tmp", ".orig", ".rej"]
        var names: [String] = []

        for url in urls where url.pathExtension == "md" {
            let filename = url.lastPathComponent
            if ignoredSuffixes.contains(where: { filename.hasSuffix($0) }) {
                continue
            }
            let name = url.deletingPathExtension().lastPathComponent.trimmingCharacters(in: .whitespacesAndNewlines)
            if name.isEmpty {
                continue
            }
            names.append(name)
        }

        names.sort { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }

        let notebooks = names.map { name in
            Notebook(name: name, isDefault: name == defaultName)
        }

        if let defaultName, let index = notebooks.firstIndex(where: { $0.name == defaultName }) {
            var reordered = notebooks
            let defaultNotebook = reordered.remove(at: index)
            reordered.insert(defaultNotebook, at: 0)
            return reordered
        }

        return notebooks
    }
}

final class NotebookTableView: NSTableView {
    var onConfirm: (() -> Void)?
    var onQuickSelect: ((Int) -> Void)?

    override func keyDown(with event: NSEvent) {
        let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        if modifiers.contains(.command), let chars = event.charactersIgnoringModifiers, chars.count == 1 {
            let key = chars.lowercased()
            if let index = shortcutIndex(from: key) {
                onQuickSelect?(index)
                return
            }
        }
        if event.keyCode == 36 || event.keyCode == 76 {
            onConfirm?()
            return
        }
        super.keyDown(with: event)
    }

    private func shortcutIndex(from key: String) -> Int? {
        if let digit = Int(key), digit >= 1 && digit <= 9 {
            return digit - 1
        }
        if key == "0" {
            return 9
        }
        return nil
    }
}

final class NotebookSearchField: NSSearchField {
    var onQuickSelect: ((Int) -> Void)?

    override func keyDown(with event: NSEvent) {
        let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        if modifiers.contains(.command), let chars = event.charactersIgnoringModifiers, chars.count == 1 {
            let key = chars.lowercased()
            if let index = shortcutIndex(from: key) {
                onQuickSelect?(index)
                return
            }
        }
        super.keyDown(with: event)
    }

    private func shortcutIndex(from key: String) -> Int? {
        if let digit = Int(key), digit >= 1 && digit <= 9 {
            return digit - 1
        }
        if key == "0" {
            return 9
        }
        return nil
    }
}

final class NotebookRowView: NSTableRowView {
    override func drawSelection(in dirtyRect: NSRect) {
        guard selectionHighlightStyle != .none else { return }
        let rect = bounds
        let radius = rect.height / 2
        let path = NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius)
        let color = isEmphasized ? NSColor.selectedContentBackgroundColor : NSColor.unemphasizedSelectedContentBackgroundColor
        color.setFill()
        path.fill()
    }
}

final class NotebookPickerViewController: NSViewController, NSTableViewDataSource, NSTableViewDelegate, NSSearchFieldDelegate {
    var onSelectNotebook: ((String) -> Void)?

    private let provider = NotebookProvider()
    private var notebooks: [Notebook] = []
    private var filtered: [Notebook] = []

    private let searchField = NotebookSearchField(frame: .zero)
    private let messageLabel = NSTextField(labelWithString: "")
    private let emptyLabel = NSTextField(labelWithString: "No notebooks found.")
    private let tableView = NotebookTableView(frame: .zero)
    private let quitButton = NSButton(title: "Quit", target: nil, action: nil)
    private var messageClearWorkItem: DispatchWorkItem?

    override func loadView() {
        let containerSize = NSSize(width: 320, height: 340)
        let container = NSView(frame: NSRect(origin: .zero, size: containerSize))
        preferredContentSize = containerSize

        searchField.placeholderString = "Filter notebooks"
        searchField.delegate = self
        searchField.onQuickSelect = { [weak self] index in
            self?.selectShortcut(index: index)
        }

        messageLabel.font = NSFont.systemFont(ofSize: 11, weight: .regular)
        messageLabel.textColor = .secondaryLabelColor
        messageLabel.stringValue = ""

        emptyLabel.font = NSFont.systemFont(ofSize: 12, weight: .medium)
        emptyLabel.textColor = .secondaryLabelColor
        emptyLabel.alignment = .center
        emptyLabel.isHidden = true

        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("NotebookColumn"))
        column.title = "Notebooks"
        tableView.addTableColumn(column)
        tableView.headerView = nil
        tableView.dataSource = self
        tableView.delegate = self
        tableView.rowHeight = 22
        tableView.selectionHighlightStyle = .regular
        tableView.usesAlternatingRowBackgroundColors = false
        tableView.backgroundColor = .clear
        tableView.style = .plain
        tableView.intercellSpacing = .zero
        tableView.target = self
        tableView.doubleAction = #selector(handleDoubleClick)
        tableView.onConfirm = { [weak self] in
            self?.confirmSelection()
        }
        tableView.onQuickSelect = { [weak self] index in
            self?.selectShortcut(index: index)
        }

        let scrollView = NSScrollView(frame: .zero)
        scrollView.hasVerticalScroller = true
        scrollView.documentView = tableView
        scrollView.drawsBackground = false

        quitButton.isBordered = false
        quitButton.attributedTitle = makeQuitTitle()
        quitButton.target = self
        quitButton.action = #selector(quitApp)

        searchField.translatesAutoresizingMaskIntoConstraints = false
        messageLabel.translatesAutoresizingMaskIntoConstraints = false
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        emptyLabel.translatesAutoresizingMaskIntoConstraints = false
        quitButton.translatesAutoresizingMaskIntoConstraints = false

        container.addSubview(searchField)
        container.addSubview(messageLabel)
        container.addSubview(scrollView)
        container.addSubview(emptyLabel)
        container.addSubview(quitButton)

        NSLayoutConstraint.activate([
            searchField.topAnchor.constraint(equalTo: container.topAnchor, constant: 12),
            searchField.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 12),
            searchField.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -12),

            messageLabel.topAnchor.constraint(equalTo: searchField.bottomAnchor, constant: 4),
            messageLabel.leadingAnchor.constraint(equalTo: searchField.leadingAnchor),
            messageLabel.trailingAnchor.constraint(equalTo: searchField.trailingAnchor),

            scrollView.topAnchor.constraint(equalTo: messageLabel.bottomAnchor, constant: 4),
            scrollView.leadingAnchor.constraint(equalTo: searchField.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: searchField.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: quitButton.topAnchor, constant: -10),

            emptyLabel.centerXAnchor.constraint(equalTo: scrollView.centerXAnchor),
            emptyLabel.centerYAnchor.constraint(equalTo: scrollView.centerYAnchor),
            emptyLabel.leadingAnchor.constraint(equalTo: scrollView.leadingAnchor, constant: 8),
            emptyLabel.trailingAnchor.constraint(equalTo: scrollView.trailingAnchor, constant: -8),

            quitButton.trailingAnchor.constraint(equalTo: searchField.trailingAnchor),
            quitButton.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -8)
        ])

        view = container
    }

    func reloadNotebooks() {
        notebooks = provider.loadNotebooks()
        applyFilter()
        messageLabel.stringValue = ""
    }

    func focusSearch() {
        view.window?.makeFirstResponder(searchField)
    }

    func showMessage(_ message: String, color: NSColor = .systemRed) {
        messageClearWorkItem?.cancel()
        messageLabel.textColor = color
        messageLabel.stringValue = message
    }

    func showFlashMessage(_ message: String, color: NSColor = .secondaryLabelColor) {
        showMessage(message, color: color)
        let workItem = DispatchWorkItem { [weak self] in
            self?.messageLabel.stringValue = ""
        }
        messageClearWorkItem?.cancel()
        messageClearWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0, execute: workItem)
    }

    func numberOfRows(in tableView: NSTableView) -> Int {
        filtered.count
    }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        guard row < filtered.count else { return nil }
        let notebook = filtered[row]
        let identifier = NSUserInterfaceItemIdentifier("NotebookCell")
        let cell = tableView.makeView(withIdentifier: identifier, owner: self) as? NSTableCellView ?? {
            let cell = NSTableCellView()
            cell.identifier = identifier
            let textField = NSTextField(labelWithString: "")
            let shortcutField = NSTextField(labelWithString: "")
            textField.translatesAutoresizingMaskIntoConstraints = false
            shortcutField.translatesAutoresizingMaskIntoConstraints = false
            shortcutField.font = NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .medium)
            shortcutField.textColor = .tertiaryLabelColor
            shortcutField.alignment = .right
            cell.addSubview(textField)
            cell.addSubview(shortcutField)
            cell.textField = textField
            cell.objectValue = shortcutField
            NSLayoutConstraint.activate([
                textField.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 7),
                textField.trailingAnchor.constraint(lessThanOrEqualTo: cell.trailingAnchor, constant: -47),
                textField.centerYAnchor.constraint(equalTo: cell.centerYAnchor)
            ])
            NSLayoutConstraint.activate([
                shortcutField.trailingAnchor.constraint(equalTo: cell.trailingAnchor, constant: -7),
                shortcutField.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
                shortcutField.leadingAnchor.constraint(greaterThanOrEqualTo: textField.trailingAnchor, constant: 8)
            ])
            return cell
        }()

        let suffix = notebook.isDefault ? " ★" : ""
        cell.textField?.stringValue = "\(notebook.name)\(suffix)"
        if let shortcutField = cell.objectValue as? NSTextField {
            shortcutField.stringValue = shortcutLabel(for: row)
        }
        return cell
    }

    func tableView(_ tableView: NSTableView, rowViewForRow row: Int) -> NSTableRowView? {
        NotebookRowView()
    }


    func controlTextDidChange(_ obj: Notification) {
        applyFilter()
    }

    @objc private func handleDoubleClick() {
        confirmSelection()
    }

    @objc private func quitApp() {
        NSApp.terminate(nil)
    }

    private func makeQuitTitle() -> NSAttributedString {
        let quitTitle = NSMutableAttributedString(
            string: "Quit",
            attributes: [
                .font: NSFont.systemFont(ofSize: 12, weight: .medium),
                .foregroundColor: NSColor.secondaryLabelColor
            ]
        )
        let shortcutTitle = NSAttributedString(
            string: "  ⌘Q",
            attributes: [
                .font: NSFont.systemFont(ofSize: 11, weight: .regular),
                .foregroundColor: NSColor.tertiaryLabelColor
            ]
        )
        quitTitle.append(shortcutTitle)
        return quitTitle
    }

    private func applyFilter() {
        let query = searchField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        if query.isEmpty {
            filtered = notebooks
        } else {
            filtered = notebooks.filter { $0.name.localizedCaseInsensitiveContains(query) }
        }
        tableView.reloadData()
        emptyLabel.isHidden = !filtered.isEmpty
        if !filtered.isEmpty {
            tableView.selectRowIndexes(IndexSet(integer: 0), byExtendingSelection: false)
        }
    }

    private func shortcutLabel(for row: Int) -> String {
        if row < 9 {
            return "⌘\(row + 1)"
        }
        if row == 9 {
            return "⌘0"
        }
        return ""
    }

    func selectShortcut(index: Int) {
        guard index >= 0, index < filtered.count else {
            NSSound.beep()
            return
        }
        tableView.selectRowIndexes(IndexSet(integer: index), byExtendingSelection: false)
        confirmSelection()
    }

    private func confirmSelection() {
        guard tableView.selectedRow >= 0, tableView.selectedRow < filtered.count else {
            NSSound.beep()
            return
        }
        onSelectNotebook?(filtered[tableView.selectedRow].name)
    }
}

enum TakenCommandResult {
    case success
    case failure(String)
}

final class AppDelegate: NSObject, NSApplicationDelegate, NSPopoverDelegate {
    private var statusItem: NSStatusItem?
    private let popover = NSPopover()
    private let pickerController = NotebookPickerViewController()
    private var hotKeyRefDefault: EventHotKeyRef?
    private var hotKeyRefPicker: EventHotKeyRef?
    private var hotKeyHandlerRef: EventHandlerRef?
    private var hotKeyHandlerUPP: EventHandlerUPP?
    private var keyMonitor: Any?

    func applicationDidFinishLaunching(_ notification: Notification) {
        configureMainMenu()

        pickerController.onSelectNotebook = { [weak self] notebook in
            self?.runTaken(args: [notebook]) { result in
                if case let .failure(message) = result {
                    self?.pickerController.showMessage(message, color: .systemRed)
                    NSSound.beep()
                } else {
                    self?.pickerController.showFlashMessage("Appended to \(notebook)", color: .secondaryLabelColor)
                }
            }
        }

        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let image = NSImage(named: "MenuBarTemplate") {
            image.isTemplate = true
            image.size = NSSize(width: 18, height: 18)
            item.button?.image = image
            item.button?.imagePosition = .imageOnly
        } else {
            item.button?.title = "taken"
        }
        item.button?.target = self
        item.button?.action = #selector(togglePopover)
        statusItem = item

        popover.behavior = .transient
        popover.delegate = self
        popover.contentViewController = pickerController

        registerGlobalHotKeys()
    }

    @objc private func togglePopover() {
        if popover.isShown {
            popover.performClose(nil)
            return
        }
        openPicker()
    }

    private func openPicker() {
        guard let button = statusItem?.button else { return }
        NSApp.activate(ignoringOtherApps: true)
        pickerController.reloadNotebooks()
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        pickerController.focusSearch()
        installKeyMonitorIfNeeded()
    }

    private func runTaken(args: [String], completion: @escaping (TakenCommandResult) -> Void) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = ["tkn"] + args

        var env = ProcessInfo.processInfo.environment
        let defaultPath = "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"
        env["PATH"] = env["PATH"]?.isEmpty == false ? env["PATH"]! + ":\(defaultPath)" : defaultPath
        process.environment = env

        let stderr = Pipe()
        process.standardError = stderr

        process.terminationHandler = { _ in
            let data = stderr.fileHandleForReading.readDataToEndOfFile()
            let message = String(data: data, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            DispatchQueue.main.async {
                if process.terminationStatus == 0 {
                    completion(.success)
                } else {
                    completion(.failure(message.isEmpty ? "tkn failed to run." : message))
                }
            }
        }

        do {
            try process.run()
        } catch {
            completion(.failure("Unable to run tkn. Ensure the Taken CLI is installed."))
        }
    }

    private func configureMainMenu() {
        let mainMenu = NSMenu()
        let appMenuItem = NSMenuItem()
        let appMenu = NSMenu(title: "Taken")
        let quitItem = NSMenuItem(title: "Quit Taken", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        appMenu.addItem(quitItem)
        appMenuItem.submenu = appMenu
        mainMenu.addItem(appMenuItem)
        NSApp.mainMenu = mainMenu
    }

    private func registerGlobalHotKeys() {
        let modifiers: UInt32 = UInt32(controlKey | optionKey | cmdKey)

        let defaultHotKeyID = EventHotKeyID(signature: OSType(0x54414B4E), id: 1) // 'TAKN'
        RegisterEventHotKey(
            17,
            modifiers,
            defaultHotKeyID,
            GetApplicationEventTarget(),
            0,
            &hotKeyRefDefault
        )

        let pickerHotKeyID = EventHotKeyID(signature: OSType(0x54414B4E), id: 2) // 'TAKN'
        RegisterEventHotKey(
            45,
            modifiers,
            pickerHotKeyID,
            GetApplicationEventTarget(),
            0,
            &hotKeyRefPicker
        )

        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard),
                                      eventKind: UInt32(kEventHotKeyPressed))
        let handler: EventHandlerUPP = { _, event, _ in
            var hotKeyID = EventHotKeyID()
            let status = GetEventParameter(
                event,
                EventParamName(kEventParamDirectObject),
                EventParamType(typeEventHotKeyID),
                nil,
                MemoryLayout<EventHotKeyID>.size,
                nil,
                &hotKeyID
            )
            if status == noErr {
                DispatchQueue.main.async {
                    AppDelegate.shared?.handleHotKey(id: hotKeyID.id)
                }
            }
            return noErr
        }

        hotKeyHandlerUPP = handler
        InstallEventHandler(GetApplicationEventTarget(), handler, 1, &eventType, nil, &hotKeyHandlerRef)
    }

    private func handleHotKey(id: UInt32) {
        switch id {
        case 1:
            runTaken(args: []) { [weak self] result in
                if case let .failure(message) = result {
                    self?.pickerController.showMessage(message)
                    NSSound.beep()
                }
            }
        case 2:
            openPicker()
        default:
            break
        }
    }

    private func installKeyMonitorIfNeeded() {
        guard keyMonitor == nil else { return }
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, self.popover.isShown else { return event }
            let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            if modifiers.contains(.command), let chars = event.charactersIgnoringModifiers, chars.count == 1 {
                let key = chars.lowercased()
                if let index = self.shortcutIndex(from: key) {
                    self.pickerController.selectShortcut(index: index)
                    return nil
                }
            }
            return event
        }
    }

    private func removeKeyMonitor() {
        if let monitor = keyMonitor {
            NSEvent.removeMonitor(monitor)
            keyMonitor = nil
        }
    }

    func popoverWillClose(_ notification: Notification) {
        removeKeyMonitor()
    }

    private func shortcutIndex(from key: String) -> Int? {
        if let digit = Int(key), digit >= 1 && digit <= 9 {
            return digit - 1
        }
        if key == "0" {
            return 9
        }
        return nil
    }

    static weak var shared: AppDelegate?
}

let app = NSApplication.shared
let delegate = AppDelegate()
AppDelegate.shared = delegate
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
