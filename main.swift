import Cocoa
import Carbon
import ApplicationServices

// MARK: - Constants
let kMagicUserData: Int64 = 0x58435554 // "XCUT"
let kLaunchAgentID = "com.antigravity.makas"
let kAppName = "Makas"
let kBubbleSoundPath = "/System/Library/Sounds/Pop.aiff"

// MARK: - Launch at Login Helper
class LaunchAtLogin {
    static var plistURL: URL {
        let home = FileManager.default.homeDirectoryForCurrentUser
        return home.appendingPathComponent("Library/LaunchAgents/\(kLaunchAgentID).plist")
    }

    static var isEnabled: Bool {
        return FileManager.default.fileExists(atPath: plistURL.path)
    }

    static func setEnabled(_ enabled: Bool, appPath: String) {
        let launchAgentsDir = plistURL.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: launchAgentsDir, withIntermediateDirectories: true)

        if enabled {
            let plistContent = """
            <?xml version="1.0" encoding="UTF-8"?>
            <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
            <plist version="1.0">
            <dict>
                <key>Label</key>
                <string>\(kLaunchAgentID)</string>
                <key>ProgramArguments</key>
                <array>
                    <string>\(appPath)</string>
                </array>
                <key>RunAtLoad</key>
                <true/>
                <key>KeepAlive</key>
                <false/>
                <key>ProcessType</key>
                <string>Interactive</string>
            </dict>
            </plist>
            """
            try? plistContent.write(to: plistURL, atomically: true, encoding: .utf8)
            // Note: We deliberately do NOT run 'launchctl load' here to prevent
            // launching a duplicate second instance while the app is already running.
        } else {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/bin/launchctl")
            process.arguments = ["unload", plistURL.path]
            try? process.run()
            try? FileManager.default.removeItem(at: plistURL)
        }
    }
}

// MARK: - Cut Paste Engine
class CutPasteEngine {
    static let shared = CutPasteEngine()

    var isEnabled: Bool = true
    private(set) var isCutActive: Bool = false

    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var permissionTimer: Timer?
    private var bubbleSound: NSSound?

    init() {
        bubbleSound = NSSound(contentsOfFile: kBubbleSoundPath, byReference: true) ?? NSSound(named: "Pop")
    }

    func playBubbleSound() {
        bubbleSound?.play()
    }

    func start() {
        if checkAccessibility(prompt: false) {
            setupEventTap()
        } else {
            // First run: trigger the system prompt cleanly without modal loops
            if !UserDefaults.standard.bool(forKey: "HasRequestedAccessibility") {
                UserDefaults.standard.set(true, forKey: "HasRequestedAccessibility")
                _ = checkAccessibility(prompt: true)
            }
            startMonitoringPermission()
        }
    }

    func checkAccessibility(prompt: Bool) -> Bool {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: prompt] as CFDictionary
        return AXIsProcessTrustedWithOptions(options)
    }

    func promptAccessibility() {
        _ = checkAccessibility(prompt: true)
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }

    private func startMonitoringPermission() {
        permissionTimer?.invalidate()
        permissionTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] timer in
            guard let self = self else { return }
            if self.checkAccessibility(prompt: false) {
                timer.invalidate()
                self.permissionTimer = nil
                self.setupEventTap()
                NotificationCenter.default.post(name: .accessibilityStatusChanged, object: nil)
            }
        }
    }

    private func setupEventTap() {
        guard eventTap == nil else { return }

        let mask = (1 << CGEventType.keyDown.rawValue)
        let observer = UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque())

        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: CGEventMask(mask),
            callback: { (proxy, type, event, refcon) -> Unmanaged<CGEvent>? in
                guard let refcon = refcon else { return Unmanaged.passRetained(event) }
                let engine = Unmanaged<CutPasteEngine>.fromOpaque(refcon).takeUnretainedValue()
                return engine.process(proxy: proxy, type: type, event: event)
            },
            userInfo: observer
        ) else {
            print("[Makas] Event tap oluşturulamadı. Erişilebilirlik izni bekleniyor.")
            return
        }

        self.eventTap = tap
        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        self.runLoopSource = source
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        print("[Makas] Event tap başarıyla aktif edildi.")
    }

    private func process(proxy: CGEventTapProxy, type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let tap = eventTap {
                CGEvent.tapEnable(tap: tap, enable: true)
            }
            return Unmanaged.passRetained(event)
        }

        guard type == .keyDown else {
            return Unmanaged.passRetained(event)
        }

        if event.getIntegerValueField(.eventSourceUserData) == kMagicUserData {
            return Unmanaged.passRetained(event)
        }

        guard isEnabled else {
            return Unmanaged.passRetained(event)
        }

        guard let frontApp = NSWorkspace.shared.frontmostApplication,
              frontApp.bundleIdentifier == "com.apple.finder" else {
            return Unmanaged.passRetained(event)
        }

        let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
        let flags = event.flags

        let cmd = flags.contains(.maskCommand)
        let opt = flags.contains(.maskAlternate)
        let ctrl = flags.contains(.maskControl)
        let shift = flags.contains(.maskShift)

        if isEditingTextInFinder() {
            return Unmanaged.passRetained(event)
        }

        if cmd && !opt && !ctrl && !shift {
            if keyCode == 7 { // Cmd + X (Kes)
                isCutActive = true
                playBubbleSound()

                DispatchQueue.main.asyncAfter(deadline: .now() + 0.015) { [weak self] in
                    self?.simulateKey(keyCode: 8, flags: [.maskCommand], modifiers: [55])
                }
                return nil // Suppress Cmd + X
            } else if keyCode == 9 { // Cmd + V (Yapıştır / Taşı)
                if isCutActive {
                    isCutActive = false
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.015) { [weak self] in
                        self?.simulateKey(keyCode: 9, flags: [.maskCommand, .maskAlternate], modifiers: [58, 55])
                    }
                    return nil // Suppress Cmd + V
                }
            } else if keyCode == 8 { // Cmd + C (Kopyala)
                isCutActive = false
            }
        } else if keyCode == 53 { // Escape
            isCutActive = false
        }

        return Unmanaged.passRetained(event)
    }

    private func isEditingTextInFinder() -> Bool {
        let systemWide = AXUIElementCreateSystemWide()
        var focusedElement: AnyObject?
        let err = AXUIElementCopyAttributeValue(systemWide, kAXFocusedUIElementAttribute as CFString, &focusedElement)
        if err == .success, let element = focusedElement {
            let axElement = element as! AXUIElement
            var role: AnyObject?
            if AXUIElementCopyAttributeValue(axElement, kAXRoleAttribute as CFString, &role) == .success,
               let roleStr = role as? String {
                if roleStr == kAXTextFieldRole as String || roleStr == kAXTextAreaRole as String {
                    return true
                }
            }
        }
        return false
    }

    private func simulateKey(keyCode: CGKeyCode, flags: CGEventFlags, modifiers: [CGKeyCode]) {
        let source = CGEventSource(stateID: .hidSystemState)

        for mod in modifiers {
            if let modDown = CGEvent(keyboardEventSource: source, virtualKey: mod, keyDown: true) {
                modDown.flags = flags
                modDown.setIntegerValueField(.eventSourceUserData, value: kMagicUserData)
                modDown.post(tap: .cghidEventTap)
            }
        }

        if let down = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: true),
           let up = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: false) {
            down.flags = flags
            up.flags = flags
            down.setIntegerValueField(.eventSourceUserData, value: kMagicUserData)
            up.setIntegerValueField(.eventSourceUserData, value: kMagicUserData)
            down.post(tap: .cghidEventTap)
            up.post(tap: .cghidEventTap)
        }

        for mod in modifiers.reversed() {
            if let modUp = CGEvent(keyboardEventSource: source, virtualKey: mod, keyDown: false) {
                modUp.setIntegerValueField(.eventSourceUserData, value: kMagicUserData)
                modUp.post(tap: .cghidEventTap)
            }
        }
    }
}

extension Notification.Name {
    static let accessibilityStatusChanged = Notification.Name("MakasAccessibilityStatusChanged")
}

// MARK: - App Delegate & Menu Bar UI
class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private var statusMenuItem: NSMenuItem!
    private var toggleMenuItem: NSMenuItem!
    private var launchAtLoginMenuItem: NSMenuItem!
    private var permissionMenuItem: NSMenuItem!

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Single instance check
        let bundleID = Bundle.main.bundleIdentifier ?? "com.antigravity.makas"
        let runningApps = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID)
        if runningApps.count > 1 {
            print("[Makas] Başka bir Makas örneği zaten çalışıyor. Çıkılıyor.")
            exit(0)
        }

        // Default: Enable launch at login on first launch
        let defaults = UserDefaults.standard
        if !defaults.bool(forKey: "HasConfiguredLaunchAtLoginDefault") {
            defaults.set(true, forKey: "HasConfiguredLaunchAtLoginDefault")
            let appPath = Bundle.main.executablePath ?? "/Applications/Makas.app/Contents/MacOS/Makas"
            LaunchAtLogin.setEnabled(true, appPath: appPath)
        }

        buildMenuBar()
        CutPasteEngine.shared.start()

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(updateMenuState),
            name: .accessibilityStatusChanged,
            object: nil
        )
    }

    private func buildMenuBar() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem.button {
            if #available(macOS 11.0, *), let image = NSImage(systemSymbolName: "scissors", accessibilityDescription: "Makas") {
                button.image = image
            } else {
                button.title = "✂️"
            }
        }

        let menu = NSMenu()
        menu.autoenablesItems = false

        // Status indicator with colored dot
        statusMenuItem = NSMenuItem(title: "", action: #selector(statusClicked), keyEquivalent: "")
        statusMenuItem.target = self
        statusMenuItem.isEnabled = true
        menu.addItem(statusMenuItem)

        menu.addItem(NSMenuItem.separator())

        // Enable / Disable Toggle
        toggleMenuItem = NSMenuItem(title: "Etkin", action: #selector(toggleEnabled), keyEquivalent: "")
        toggleMenuItem.target = self
        toggleMenuItem.isEnabled = true
        toggleMenuItem.state = CutPasteEngine.shared.isEnabled ? .on : .off
        menu.addItem(toggleMenuItem)

        // Launch at login (default enabled)
        launchAtLoginMenuItem = NSMenuItem(title: "Girişte Otomatik Başlat", action: #selector(toggleLaunchAtLogin), keyEquivalent: "")
        launchAtLoginMenuItem.target = self
        launchAtLoginMenuItem.isEnabled = true
        launchAtLoginMenuItem.state = LaunchAtLogin.isEnabled ? .on : .off
        menu.addItem(launchAtLoginMenuItem)

        menu.addItem(NSMenuItem.separator())

        // Permission action
        permissionMenuItem = NSMenuItem(title: "Erişilebilirlik İzni Ver...", action: #selector(openAccessibility), keyEquivalent: "")
        permissionMenuItem.target = self
        permissionMenuItem.isEnabled = true
        menu.addItem(permissionMenuItem)

        menu.addItem(NSMenuItem.separator())

        // Info
        let infoItem = NSMenuItem(title: "Finder: Cmd+X = Kes, Cmd+V = Yapıştır", action: nil, keyEquivalent: "")
        infoItem.isEnabled = false
        menu.addItem(infoItem)

        // Quit
        let quitItem = NSMenuItem(title: "Çıkış", action: #selector(quitApp), keyEquivalent: "q")
        quitItem.target = self
        quitItem.isEnabled = true
        menu.addItem(quitItem)

        statusItem.menu = menu
        updateMenuState()
    }

    @objc private func statusClicked() {
        if !CutPasteEngine.shared.checkAccessibility(prompt: false) {
            CutPasteEngine.shared.promptAccessibility()
        }
        updateMenuState()
    }

    @objc private func updateMenuState() {
        let isTrusted = CutPasteEngine.shared.checkAccessibility(prompt: false)
        let isEnabled = CutPasteEngine.shared.isEnabled

        let attr = NSMutableAttributedString()
        let dotColor: NSColor
        let statusText: String

        if !isTrusted {
            dotColor = NSColor.systemOrange
            statusText = " Makas: İzin Bekleniyor"
            permissionMenuItem.title = "Erişilebilirlik İzni Ver..."
            permissionMenuItem.isEnabled = true
        } else if isEnabled {
            dotColor = NSColor.systemGreen
            statusText = " Makas: Aktif"
            permissionMenuItem.title = "✓ Erişilebilirlik İzni Verildi"
            permissionMenuItem.isEnabled = false
        } else {
            dotColor = NSColor.systemRed
            statusText = " Makas: Devre Dışı"
            permissionMenuItem.title = "✓ Erişilebilirlik İzni Verildi"
            permissionMenuItem.isEnabled = false
        }

        let dotAttr = NSAttributedString(string: "●", attributes: [
            .foregroundColor: dotColor,
            .font: NSFont.boldSystemFont(ofSize: 14)
        ])
        let textAttr = NSAttributedString(string: statusText, attributes: [
            .foregroundColor: NSColor.labelColor,
            .font: NSFont.boldSystemFont(ofSize: 13)
        ])

        attr.append(dotAttr)
        attr.append(textAttr)
        statusMenuItem.attributedTitle = attr
    }

    @objc private func toggleEnabled() {
        CutPasteEngine.shared.isEnabled.toggle()
        toggleMenuItem.state = CutPasteEngine.shared.isEnabled ? .on : .off
        updateMenuState()
    }

    @objc private func toggleLaunchAtLogin() {
        let currentPath = Bundle.main.executablePath ?? "/Applications/Makas.app/Contents/MacOS/Makas"
        let newState = !LaunchAtLogin.isEnabled
        LaunchAtLogin.setEnabled(newState, appPath: currentPath)
        launchAtLoginMenuItem.state = newState ? .on : .off
    }

    @objc private func openAccessibility() {
        CutPasteEngine.shared.promptAccessibility()
    }

    @objc private func quitApp() {
        NSApplication.shared.terminate(nil)
    }
}

// MARK: - Main Entry Point
// Early single instance check
let runningInstances = NSRunningApplication.runningApplications(withBundleIdentifier: "com.antigravity.makas")
if runningInstances.count > 1 {
    exit(0)
}

let app = NSApplication.shared
app.setActivationPolicy(.accessory)
let delegate = AppDelegate()
app.delegate = delegate
app.run()
