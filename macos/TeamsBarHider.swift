import AppKit
import ApplicationServices

enum ToolbarPolicy {
    static func matches(bundle: String, title: String) -> Bool {
        guard ["com.microsoft.teams2", "com.microsoft.teams"].contains(bundle) else { return false }
        let value = title.lowercased()
        return ["sharing control bar", "screen sharing toolbar", "paylaşım denetim çubuğu"].contains {
            value == $0 || value.hasPrefix($0 + " |")
        }
    }
}

func attribute(_ element: AXUIElement, _ name: String) -> CFTypeRef? {
    var result: CFTypeRef?
    guard AXUIElementCopyAttributeValue(element, name as CFString, &result) == .success else { return nil }
    return result
}

func point(_ element: AXUIElement) -> CGPoint? {
    guard let raw = attribute(element, kAXPositionAttribute), CFGetTypeID(raw) == AXValueGetTypeID() else { return nil }
    var result = CGPoint.zero
    guard AXValueGetValue(raw as! AXValue, .cgPoint, &result) else { return nil }
    return result
}

func setPoint(_ element: AXUIElement, _ value: CGPoint) -> Bool {
    var value = value
    guard let wrapped = AXValueCreate(.cgPoint, &value) else { return false }
    return AXUIElementSetAttributeValue(element, kAXPositionAttribute as CFString, wrapped) == .success
}

struct HiddenToolbar {
    let window: AXUIElement
    let pid: pid_t
    let originalPoint: CGPoint?
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    var statusItem: NSStatusItem!
    var timer: Timer?
    var enabled = true
    var hidden: [HiddenToolbar] = []
    var lastStatus = ""
    let stateItem = NSMenuItem(title: "Waiting for Teams toolbar", action: nil, keyEquivalent: "")
    let toggleItem = NSMenuItem(title: "Automatically hide toolbar", action: #selector(toggle), keyEquivalent: "")
    let loginItem = NSMenuItem(title: "Start at login", action: #selector(toggleLogin), keyEquivalent: "")
    let label = "local.teamsbarhider.agent"
    var agentURL: URL { FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/LaunchAgents/" + label + ".plist") }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.button?.image = NSImage(systemSymbolName: "rectangle.topthird.inset.filled", accessibilityDescription: "Teams Bar Hider")
        statusItem.button?.toolTip = "Teams Bar Hider"
        let menu = NSMenu()
        stateItem.isEnabled = false
        menu.addItem(stateItem)
        toggleItem.target = self
        toggleItem.state = .on
        menu.addItem(toggleItem)
        let restore = NSMenuItem(title: "Restore toolbar and pause", action: #selector(pause), keyEquivalent: "")
        restore.target = self
        menu.addItem(restore)
        loginItem.target = self
        loginItem.state = FileManager.default.fileExists(atPath: agentURL.path) ? .on : .off
        menu.addItem(loginItem)
        let permission = NSMenuItem(title: "Allow Accessibility…", action: #selector(requestPermission), keyEquivalent: "")
        permission.target = self
        menu.addItem(permission)
        menu.addItem(.separator())
        let quit = NSMenuItem(title: "Quit", action: #selector(quitApp), keyEquivalent: "q")
        quit.target = self
        menu.addItem(quit)
        statusItem.menu = menu
        if CommandLine.arguments.contains("--install") {
            do { try setLogin(true); loginItem.state = .on }
            catch { stateItem.title = "Login setup failed: \(error.localizedDescription)" }
        }
        DistributedNotificationCenter.default().addObserver(self, selector: #selector(quitApp), name: Notification.Name(label + ".stop"), object: nil)
        scan()
        timer = Timer.scheduledTimer(withTimeInterval: 1.5, repeats: true) { [weak self] _ in self?.scan() }
        if !AXIsProcessTrusted() { requestPermission() }
    }

    func setLogin(_ value: Bool) throws {
        if value {
            try FileManager.default.createDirectory(at: agentURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            let plist: [String: Any] = ["Label": label, "ProgramArguments": [Bundle.main.executableURL!.path], "RunAtLoad": true, "LimitLoadToSessionType": "Aqua"]
            try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0).write(to: agentURL, options: .atomic)
        } else if FileManager.default.fileExists(atPath: agentURL.path) {
            try FileManager.default.removeItem(at: agentURL)
        }
    }

    @objc func toggleLogin() {
        do {
            let enable = loginItem.state != .on
            try setLogin(enable)
            loginItem.state = enable ? .on : .off
        } catch { stateItem.title = "Login setup failed: \(error.localizedDescription)" }
    }
    @objc func requestPermission() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
    }
    @objc func toggle() { enabled.toggle(); toggleItem.state = enabled ? .on : .off; if !enabled { restore() }; scan() }
    @objc func pause() { enabled = false; toggleItem.state = .off; restore(); scan() }
    @objc func quitApp() { NSApp.terminate(nil) }
    func applicationWillTerminate(_ notification: Notification) { timer?.invalidate(); restore() }

    func restore() {
        for item in hidden where NSRunningApplication(processIdentifier: item.pid) != nil {
            let bundle = NSRunningApplication(processIdentifier: item.pid)?.bundleIdentifier ?? ""
            let title = attribute(item.window, kAXTitleAttribute) as? String ?? ""
            guard ToolbarPolicy.matches(bundle: bundle, title: title) else { continue }
            if let position = item.originalPoint { _ = setPoint(item.window, position) }
            else { _ = AXUIElementSetAttributeValue(item.window, kAXMinimizedAttribute as CFString, kCFBooleanFalse) }
        }
        hidden.removeAll()
    }

    func scan() {
        defer { writeStatus() }
        guard enabled else { stateItem.title = "Paused"; return }
        guard AXIsProcessTrusted() else { stateItem.title = "Accessibility permission required"; return }
        hidden.removeAll { NSRunningApplication(processIdentifier: $0.pid) == nil || attribute($0.window, kAXRoleAttribute) == nil }
        var unsupported = false
        for application in NSWorkspace.shared.runningApplications {
            guard let bundle = application.bundleIdentifier, ["com.microsoft.teams2", "com.microsoft.teams"].contains(bundle) else { continue }
            let app = AXUIElementCreateApplication(application.processIdentifier)
            AXUIElementSetMessagingTimeout(app, 0.25)
            guard let windows = attribute(app, kAXWindowsAttribute) as? [AXUIElement] else { continue }
            for window in windows {
                let title = attribute(window, kAXTitleAttribute) as? String ?? ""
                guard ToolbarPolicy.matches(bundle: bundle, title: title) else { continue }
                if hidden.contains(where: { CFEqual($0.window, window) }) { continue }
                if (attribute(window, kAXMinimizedAttribute) as? Bool) == true { continue }
                var settable: DarwinBoolean = false
                if AXUIElementIsAttributeSettable(window, kAXMinimizedAttribute as CFString, &settable) == .success,
                   settable.boolValue,
                   AXUIElementSetAttributeValue(window, kAXMinimizedAttribute as CFString, kCFBooleanTrue) == .success,
                   (attribute(window, kAXMinimizedAttribute) as? Bool) == true {
                    hidden.append(HiddenToolbar(window: window, pid: application.processIdentifier, originalPoint: nil))
                    continue
                }
                // Some Teams floating windows cannot be minimized. Try a reversible move.
                // Accessibility coordinates start at the top left of the primary display.
                let primaryHeight = NSScreen.screens.first?.frame.height ?? 0
                let rightEdge = NSScreen.screens.map { $0.frame.maxX }.max() ?? 0
                let topEdge = NSScreen.screens.map { primaryHeight - $0.frame.maxY }.min() ?? 0
                if let original = point(window) {
                    if setPoint(window, CGPoint(x: rightEdge + 100, y: topEdge)),
                       let moved = point(window), moved.x >= rightEdge {
                        hidden.append(HiddenToolbar(window: window, pid: application.processIdentifier, originalPoint: original))
                        continue
                    }
                    _ = setPoint(window, original)
                }
                // Do not close a window or hide the entire Teams app as a fallback.
                unsupported = true
            }
        }
        stateItem.title = unsupported ? "This Teams toolbar cannot be hidden via Accessibility"
            : hidden.isEmpty ? "Waiting for Teams toolbar" : "Sharing toolbar hidden"
    }

    func writeStatus() {
        let value: [String: Any] = ["pid": ProcessInfo.processInfo.processIdentifier,
            "enabled": enabled, "accessibilityTrusted": AXIsProcessTrusted(),
            "hiddenToolbars": hidden.count, "state": stateItem.title]
        guard let data = try? JSONSerialization.data(withJSONObject: value, options: [.sortedKeys]),
              let text = String(data: data, encoding: .utf8), text != lastStatus else { return }
        let folder = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support/TeamsBarHider")
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            try data.write(to: folder.appendingPathComponent("status.json"), options: .atomic)
            lastStatus = text
        } catch { /* The helper remains usable if diagnostics cannot be written. */ }
    }
}

if CommandLine.arguments.contains("--self-test") {
    let cases: [(String, String, Bool)] = [
        ("com.microsoft.teams2", "Sharing control bar | Microsoft Teams", true),
        ("com.microsoft.teams", "Screen sharing toolbar", true),
        ("com.microsoft.teams2", "Paylaşım denetim çubuğu | Microsoft Teams", true),
        ("com.apple.Safari", "Sharing control bar | Microsoft Teams", false),
        ("com.microsoft.teams2", "Daily meeting | Microsoft Teams", false),
        ("com.microsoft.teams2", "Sharing control bar fake title", false),
        ("com.apple.controlcenter", "Screen sharing toolbar", false)
    ]
    for (bundle, title, expected) in cases {
        guard ToolbarPolicy.matches(bundle: bundle, title: title) == expected else { fatalError("Toolbar targeting check failed") }
    }
    print("7 macOS target-isolation checks passed")
    exit(0)
}
if CommandLine.arguments.contains("--stop") {
    DistributedNotificationCenter.default().postNotificationName(Notification.Name("local.teamsbarhider.agent.stop"), object: nil, userInfo: nil, deliverImmediately: true)
    exit(0)
}
if CommandLine.arguments.contains("--inspect") {
    print("Accessibility trusted: \(AXIsProcessTrusted())")
    let teams = NSWorkspace.shared.runningApplications.filter { ["com.microsoft.teams", "com.microsoft.teams2"].contains($0.bundleIdentifier ?? "") }
    print("Teams processes: \(teams.count)")
    for application in teams {
        let app = AXUIElementCreateApplication(application.processIdentifier)
        AXUIElementSetMessagingTimeout(app, 0.25)
        let windows = attribute(app, kAXWindowsAttribute) as? [AXUIElement] ?? []
        print("Accessible windows: \(windows.count)")
        for window in windows {
            let title = attribute(window, kAXTitleAttribute) as? String ?? ""
            print("Recognized toolbar: \(ToolbarPolicy.matches(bundle: application.bundleIdentifier ?? "", title: title))")
        }
    }
    exit(0)
}
let running = NSRunningApplication.runningApplications(withBundleIdentifier: "local.teamsbarhider.app")
if running.contains(where: { $0.processIdentifier != ProcessInfo.processInfo.processIdentifier }) { exit(0) }
let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.run()
