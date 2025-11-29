import Cocoa
import Carbon
import SwiftUI
import UserNotifications

// Global variable to hold AppDelegate reference
private var globalAppDelegate: AppDelegate?

// C event handler
private func hotKeyHandler(nextHandler: EventHandlerCallRef?, event: EventRef?, userData: UnsafeMutableRawPointer?) -> OSStatus {
    var hotKeyID = EventHotKeyID()
    let status = GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID), nil, MemoryLayout<EventHotKeyID>.size, nil, &hotKeyID)
    
    guard status == noErr else {
        return status
    }
    
    guard let appDelegate = globalAppDelegate else {
        return OSStatus(eventNotHandledErr)
    }
    
    print("🔥 Hotkey pressed: ID = \(hotKeyID.id)")
    
    DispatchQueue.main.async {
        switch hotKeyID.id {
        case 1: // Right arrow (next screen)
            appDelegate.moveWindowToNextScreen()
        case 2: // Left arrow (previous screen)
            appDelegate.moveWindowToPrevScreen()
        case 3: // Up arrow (save snapshot)
            appDelegate.saveManualSnapshot()
        case 4: // Down arrow (restore snapshot)
            appDelegate.restoreManualSnapshot()
        case 5: // W (move window up)
            appDelegate.nudgeWindow(direction: .up)
        case 6: // A (move window left)
            appDelegate.nudgeWindow(direction: .left)
        case 7: // S (move window down)
            appDelegate.nudgeWindow(direction: .down)
        case 8: // D (move window right)
            appDelegate.nudgeWindow(direction: .right)
        default:
            break
        }
    }
    
    return noErr
}

// Class to store debug logs
class DebugLogger {
    static let shared = DebugLogger()
    private var logs: [String] = []
    private let maxLogs = 1000
    
    // Mapping for app name masking
    private var appNameMapping: [String: String] = [:]
    private var appCounter = 0
    
    func addLog(_ message: String) {
        let timestamp: String
        if SnapshotSettings.shared.showMilliseconds {
            let formatter = DateFormatter()
            formatter.dateFormat = "HH:mm:ss.SSS"
            timestamp = formatter.string(from: Date())
        } else {
            timestamp = DateFormatter.localizedString(from: Date(), dateStyle: .none, timeStyle: .medium)
        }
        let logEntry = "[\(timestamp)] \(message)"
        logs.append(logEntry)
        
        // Remove old logs if too many
        if logs.count > maxLogs {
            logs.removeFirst(logs.count - maxLogs)
        }
    }
    
    func getAllLogs() -> String {
        return logs.joined(separator: "\n")
    }
    
    func clearLogs() {
        logs.removeAll()
    }
    
    /// Mask app name (based on settings)
    func maskAppName(_ name: String) -> String {
        guard SnapshotSettings.shared.maskAppNamesInLog else {
            return name  // Return original name if masking is OFF
        }
        if let masked = appNameMapping[name] {
            return masked
        }
        appCounter += 1
        let masked = "App\(appCounter)"
        appNameMapping[name] = masked
        return masked
    }
    
    /// Clear app name mapping
    func clearAppNameMapping() {
        appNameMapping.removeAll()
        appCounter = 0
    }
}

// Debug log viewer SwiftUI view
struct DebugLogView: View {
    @State private var logs: String
    @Environment(\.dismiss) private var dismiss
    
    init() {
        _logs = State(initialValue: DebugLogger.shared.getAllLogs())
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text(NSLocalizedString("Debug Log", comment: "Debug log viewer title"))
                    .font(.headline)
                Spacer()
                Button(NSLocalizedString("Clear", comment: "Button to clear logs")) {
                    DebugLogger.shared.clearLogs()
                    logs = DebugLogger.shared.getAllLogs()
                }
                .disabled(logs.isEmpty)
                Button(NSLocalizedString("Copy", comment: "Button to copy logs to clipboard")) {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(logs, forType: .string)
                }
                .disabled(logs.isEmpty)
                Button(NSLocalizedString("Close", comment: "Button to close window")) {
                    dismiss()
                }
            }
            .padding()
            
            Divider()
            
            // Log display area
            ScrollView {
                Text(logs.isEmpty ? NSLocalizedString("No logs available", comment: "Message when log is empty") : logs)
                    .font(.system(.body, design: .monospaced))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding()
                    .textSelection(.enabled)
            }
        }
        .frame(width: 700, height: 500)
    }
}

class AppDelegate: NSObject, NSApplicationDelegate {
    var statusItem: NSStatusItem?
    var hotKeyRef: EventHotKeyRef?
    var hotKeyRef2: EventHotKeyRef?
    var hotKeyRef3: EventHotKeyRef?  // Save snapshot (↑)
    var hotKeyRef4: EventHotKeyRef?  // Restore snapshot (↓)
    var hotKeyRef5: EventHotKeyRef?  // Window nudge (W: up)
    var hotKeyRef6: EventHotKeyRef?  // Window nudge (A: left)
    var hotKeyRef7: EventHotKeyRef?  // Window nudge (S: down)
    var hotKeyRef8: EventHotKeyRef?  // Window nudge (D: right)
    var eventHandler: EventHandlerRef?
    var settingsWindow: NSWindow?
    var aboutWindow: NSWindow?
    var debugWindow: NSWindow?
    
    // Display memory feature (new format: using WindowMatchInfo)
    private var windowPositions: [String: [String: WindowMatchInfo]] = [:]
    private var snapshotTimer: Timer?
    
    // Manual snapshot feature (5 slots, for future expansion)
    // New format: using WindowMatchInfo (hashed for privacy protection)
    private var manualSnapshots: [[String: [String: WindowMatchInfo]]] = Array(repeating: [:], count: 5)
    private var currentSlotIndex: Int = 0  // Always 0 in v1.2.3
    
    // Auto snapshot feature
    private var initialSnapshotTimer: Timer?
    private var periodicSnapshotTimer: Timer?
    private var hasInitialSnapshotBeenTaken = false
    
    // Display change stabilization timer
    private var displayStabilizationTimer: Timer?
    
    // Restore work item (cancellable)
    private var restoreWorkItem: DispatchWorkItem?
    
    // Display monitoring enabled/disabled state
    private var isDisplayMonitoringEnabled = true
    
    // Last display change time (for stabilization detection)
    private var lastDisplayChangeTime: Date?
    
    // Stabilization check timer
    private var stabilizationCheckTimer: Timer?
    
    // Event occurred after stabilization flag
    private var eventOccurredAfterStabilization = false
    
    // Fallback timer
    private var fallbackTimer: DispatchWorkItem?
    
    // Restore retry feature
    private var restoreRetryCount: Int = 0
    private let maxRestoreRetries: Int = 2
    private let restoreRetryDelay: TimeInterval = 3.0
    
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Set global reference
        globalAppDelegate = self
        
        // Initialize WindowTimingSettings to start sleep monitoring
        _ = WindowTimingSettings.shared
        
        // Initialize SnapshotSettings
        _ = SnapshotSettings.shared
        
        // Output startup info to log
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "unknown"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "unknown"
        debugPrint("========== Tsubame v\(version) (build \(build)) ==========")
        debugPrint("Settings:")
        debugPrint("  Hotkey: \(HotKeySettings.shared.getModifierString())")
        debugPrint("  Display stabilization: \(String(format: "%.1f", WindowTimingSettings.shared.displayStabilizationDelay))s")
        debugPrint("  Window restore delay: \(String(format: "%.1f", WindowTimingSettings.shared.windowRestoreDelay))s")
        debugPrint("  Restore on launch: \(SnapshotSettings.shared.restoreOnLaunch ? "ON" : "OFF")")
        debugPrint("  Verbose logging: \(SnapshotSettings.shared.verboseLogging ? "ON" : "OFF")")
        debugPrint("  Mask app names: \(SnapshotSettings.shared.maskAppNamesInLog ? "ON" : "OFF")")
        debugPrint("================================================")
        
        // Load saved snapshots
        loadSavedSnapshots()
        
        // Request notification permission
        setupNotifications()
        
        // Add icon to system bar
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        
        if let button = statusItem?.button {
            button.image = NSImage(systemSymbolName: "rectangle.2.swap", accessibilityDescription: "Window Mover")
            button.image?.isTemplate = true
        }
        
        // Setup menu
        setupMenu()
        
        // Register global hotkeys
        registerHotKeys()
        
        // Check accessibility permissions
        checkAccessibilityPermissions()
        
        // Start display change monitoring
        setupDisplayChangeObserver()
        
        // Setup monitoring control observers
        setupMonitoringControlObservers()
        
        // Setup snapshot settings observers
        setupSnapshotSettingsObservers()
        
        // Start periodic snapshot for display memory
        startPeriodicSnapshot()
        
        // Start initial auto-snapshot timer
        startInitialSnapshotTimer()
        
        // Auto-restore on launch (if enabled and snapshot exists)
        if SnapshotSettings.shared.restoreOnLaunch && ManualSnapshotStorage.shared.hasSnapshot {
            let delay = WindowTimingSettings.shared.windowRestoreDelay
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
                if NSScreen.screens.count >= 2 {
                    debugPrint("🚀 Executing auto-restore on launch")
                    self?.restoreManualSnapshot()
                } else {
                    debugPrint("🚀 Auto-restore on launch: Skipped (no external display connected)")
                }
            }
        }
        
        debugPrint("Application launched")
        debugPrint("Connected screens: \(NSScreen.screens.count)")
    }
    
    /// Setup notification center
    private func setupNotifications() {
        let center = UNUserNotificationCenter.current()
        center.requestAuthorization(options: [.alert, .sound]) { granted, error in
            if granted {
                debugPrint("✅ Notification permission granted")
            } else if let error = error {
                debugPrint("⚠️ Failed to request notification permission: \(error.localizedDescription)")
            }
        }
    }
    
    /// Send notification (for snapshot operations)
    private func sendNotification(title: String, body: String) {
        let settings = SnapshotSettings.shared
        
        // Sound notification
        if settings.enableSound {
            NSSound(named: NSSound.Name(settings.soundName))?.play()
        }
        
        // System notification
        guard settings.enableNotification else { return }
        
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = nil  // Sound is controlled separately
        
        let request = UNNotificationRequest(
            identifier: UUID().uuidString,
            content: content,
            trigger: nil
        )
        
        UNUserNotificationCenter.current().add(request) { error in
            if let error = error {
                debugPrint("⚠️ Notification error: \(error.localizedDescription)")
            }
        }
    }
    
    func setupMenu() {
        let menu = NSMenu()
        
        let modifierString = HotKeySettings.shared.getModifierString()
        
        // Window movement
        let nextScreenTitle = String(format: NSLocalizedString("Move Window to Next Screen (%@→)", comment: "Menu item for moving window to next screen"), modifierString)
        menu.addItem(NSMenuItem(title: nextScreenTitle, action: #selector(moveWindowToNextScreen), keyEquivalent: ""))
        
        let prevScreenTitle = String(format: NSLocalizedString("Move Window to Previous Screen (%@←)", comment: "Menu item for moving window to previous screen"), modifierString)
        menu.addItem(NSMenuItem(title: prevScreenTitle, action: #selector(moveWindowToPrevScreen), keyEquivalent: ""))
        
        menu.addItem(NSMenuItem.separator())
        
        // Snapshot operations
        let saveTitle = String(format: NSLocalizedString("📸 Save Layout (%@↑)", comment: "Menu item for saving window layout"), modifierString)
        menu.addItem(NSMenuItem(title: saveTitle, action: #selector(saveManualSnapshot), keyEquivalent: ""))
        
        let restoreTitle = String(format: NSLocalizedString("📥 Restore Layout (%@↓)", comment: "Menu item for restoring window layout"), modifierString)
        menu.addItem(NSMenuItem(title: restoreTitle, action: #selector(restoreManualSnapshot), keyEquivalent: ""))
        
        // Snapshot status
        let snapshotStatusItem = NSMenuItem(title: getSnapshotStatusString(), action: nil, keyEquivalent: "")
        snapshotStatusItem.isEnabled = false
        menu.addItem(snapshotStatusItem)
        
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: NSLocalizedString("Settings...", comment: "Menu item to open settings"), action: #selector(openSettings), keyEquivalent: ","))
        menu.addItem(NSMenuItem(title: NSLocalizedString("Show Debug Log", comment: "Menu item to show debug log"), action: #selector(showDebugLog), keyEquivalent: "d"))
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: NSLocalizedString("About Tsubame", comment: "Menu item to show about window"), action: #selector(openAbout), keyEquivalent: ""))
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: NSLocalizedString("Quit", comment: "Menu item to quit application"), action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        
        statusItem?.menu = menu
    }
    
    /// Generate snapshot status string
    private func getSnapshotStatusString() -> String {
        if let timestamp = ManualSnapshotStorage.shared.getTimestamp() {
            let formatter = DateFormatter()
            formatter.dateFormat = "HH:mm"
            let timeStr = formatter.string(from: timestamp)
            
            // Count saved windows
            let snapshot = manualSnapshots[currentSlotIndex]
            let windowCount = snapshot.values.reduce(0) { $0 + $1.count }
            
            let format = NSLocalizedString("    💾 %d windows @ %@", comment: "Snapshot status with window count and time")
            return String(format: format, windowCount, timeStr)
        } else {
            return NSLocalizedString("    💾 No data", comment: "Snapshot status when no data exists")
        }
    }
    
    @objc func openSettings() {
        if settingsWindow == nil {
            let settingsView = SettingsView()
            let hostingController = NSHostingController(rootView: settingsView)
            
            let window = NSWindow(contentViewController: hostingController)
            window.title = NSLocalizedString("Settings", comment: "Settings window title")
            window.styleMask = [.titled, .closable]
            window.center()
            window.level = .floating
            
            settingsWindow = window
        }
        
        settingsWindow?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
    
    @objc func openAbout() {
        if aboutWindow == nil {
            let aboutView = AboutView()
            let hostingController = NSHostingController(rootView: aboutView)
            
            let window = NSWindow(contentViewController: hostingController)
            window.title = "About Tsubame - Window Smart Mover"
            window.styleMask = [.titled, .closable]
            window.center()
            window.level = .floating
            
            aboutWindow = window
        }
        
        aboutWindow?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
    
    @objc func showDebugLog() {
        // Create new window each time to show latest logs
        let debugView = DebugLogView()
        let hostingController = NSHostingController(rootView: debugView)
        
        let window = NSWindow(contentViewController: hostingController)
        window.title = NSLocalizedString("Debug Log", comment: "Debug log window title")
        window.styleMask = [.titled, .closable, .resizable]
        window.center()
        window.level = .floating
        
        debugWindow = window
        
        debugWindow?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
    
    func checkAccessibilityPermissions() {
        let options: NSDictionary = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true]
        let accessEnabled = AXIsProcessTrustedWithOptions(options)
        
        if accessEnabled {
            debugPrint("✅ Accessibility permission granted")
        } else {
            debugPrint("⚠️ Accessibility permission required")
        }
    }
    
    func registerHotKeys() {
        // Install event handler
        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let status = InstallEventHandler(GetApplicationEventTarget(), hotKeyHandler, 1, &eventType, nil, &eventHandler)
        
        if status == noErr {
            debugPrint("✅ Event handler installed successfully")
        } else {
            debugPrint("❌ Failed to install event handler: \(status)")
        }
        
        // Register hotkeys
        let settings = HotKeySettings.shared
        let modifiers = settings.getModifiers()
        
        // Hotkey 1: Move to next screen (right arrow)
        let hotKeyID1 = EventHotKeyID(signature: OSType(0x4D4F5645), id: 1) // 'MOVE' + 1
        let keyCode1 = UInt32(kVK_RightArrow)
        let registerStatus1 = RegisterEventHotKey(keyCode1, modifiers, hotKeyID1, GetApplicationEventTarget(), 0, &hotKeyRef)
        
        if registerStatus1 == noErr {
            let modifierString = settings.getModifierString()
            debugPrint("✅ Hotkey 1 (\(modifierString)→) registered")
        } else {
            debugPrint("❌ Failed to register hotkey 1: \(registerStatus1)")
        }
        
        // Hotkey 2: Move to previous screen (left arrow)
        let hotKeyID2 = EventHotKeyID(signature: OSType(0x4D4F5645), id: 2) // 'MOVE' + 2
        let keyCode2 = UInt32(kVK_LeftArrow)
        let registerStatus2 = RegisterEventHotKey(keyCode2, modifiers, hotKeyID2, GetApplicationEventTarget(), 0, &hotKeyRef2)
        
        if registerStatus2 == noErr {
            let modifierString = settings.getModifierString()
            debugPrint("✅ Hotkey 2 (\(modifierString)←) registered")
        } else {
            debugPrint("❌ Failed to register hotkey 2: \(registerStatus2)")
        }
        
        // Hotkey 3: Save snapshot (up arrow)
        let hotKeyID3 = EventHotKeyID(signature: OSType(0x4D4F5645), id: 3) // 'MOVE' + 3
        let keyCode3 = UInt32(kVK_UpArrow)
        let registerStatus3 = RegisterEventHotKey(keyCode3, modifiers, hotKeyID3, GetApplicationEventTarget(), 0, &hotKeyRef3)
        
        if registerStatus3 == noErr {
            let modifierString = settings.getModifierString()
            debugPrint("✅ Hotkey 3 (\(modifierString)↑) registered")
        } else {
            debugPrint("❌ Failed to register hotkey 3: \(registerStatus3)")
        }
        
        // Hotkey 4: Restore snapshot (down arrow)
        let hotKeyID4 = EventHotKeyID(signature: OSType(0x4D4F5645), id: 4) // 'MOVE' + 4
        let keyCode4 = UInt32(kVK_DownArrow)
        let registerStatus4 = RegisterEventHotKey(keyCode4, modifiers, hotKeyID4, GetApplicationEventTarget(), 0, &hotKeyRef4)
        
        if registerStatus4 == noErr {
            let modifierString = settings.getModifierString()
            debugPrint("✅ Hotkey 4 (\(modifierString)↓) registered")
        } else {
            debugPrint("❌ Failed to register hotkey 4: \(registerStatus4)")
        }
        
        // Hotkey 5: Window nudge up (W)
        let hotKeyID5 = EventHotKeyID(signature: OSType(0x4D4F5645), id: 5) // 'MOVE' + 5
        let keyCode5 = UInt32(kVK_ANSI_W)
        let registerStatus5 = RegisterEventHotKey(keyCode5, modifiers, hotKeyID5, GetApplicationEventTarget(), 0, &hotKeyRef5)
        
        if registerStatus5 == noErr {
            let modifierString = settings.getModifierString()
            debugPrint("✅ Hotkey 5 (\(modifierString)W) registered")
        } else {
            debugPrint("❌ Failed to register hotkey 5: \(registerStatus5)")
        }
        
        // Hotkey 6: Window nudge left (A)
        let hotKeyID6 = EventHotKeyID(signature: OSType(0x4D4F5645), id: 6) // 'MOVE' + 6
        let keyCode6 = UInt32(kVK_ANSI_A)
        let registerStatus6 = RegisterEventHotKey(keyCode6, modifiers, hotKeyID6, GetApplicationEventTarget(), 0, &hotKeyRef6)
        
        if registerStatus6 == noErr {
            let modifierString = settings.getModifierString()
            debugPrint("✅ Hotkey 6 (\(modifierString)A) registered")
        } else {
            debugPrint("❌ Failed to register hotkey 6: \(registerStatus6)")
        }
        
        // Hotkey 7: Window nudge down (S)
        let hotKeyID7 = EventHotKeyID(signature: OSType(0x4D4F5645), id: 7) // 'MOVE' + 7
        let keyCode7 = UInt32(kVK_ANSI_S)
        let registerStatus7 = RegisterEventHotKey(keyCode7, modifiers, hotKeyID7, GetApplicationEventTarget(), 0, &hotKeyRef7)
        
        if registerStatus7 == noErr {
            let modifierString = settings.getModifierString()
            debugPrint("✅ Hotkey 7 (\(modifierString)S) registered")
        } else {
            debugPrint("❌ Failed to register hotkey 7: \(registerStatus7)")
        }
        
        // Hotkey 8: Window nudge right (D)
        let hotKeyID8 = EventHotKeyID(signature: OSType(0x4D4F5645), id: 8) // 'MOVE' + 8
        let keyCode8 = UInt32(kVK_ANSI_D)
        let registerStatus8 = RegisterEventHotKey(keyCode8, modifiers, hotKeyID8, GetApplicationEventTarget(), 0, &hotKeyRef8)
        
        if registerStatus8 == noErr {
            let modifierString = settings.getModifierString()
            debugPrint("✅ Hotkey 8 (\(modifierString)D) registered")
        } else {
            debugPrint("❌ Failed to register hotkey 8: \(registerStatus8)")
        }
    }
    
    @objc func moveWindowToNextScreen() {
        moveWindow(direction: .next)
    }
    
    @objc func moveWindowToPrevScreen() {
        moveWindow(direction: .prev)
    }
    
    enum Direction {
        case next
        case prev
    }
    
    enum NudgeDirection {
        case up
        case down
        case left
        case right
    }
    
    /// Nudge window (move by pixels in specified direction)
    func nudgeWindow(direction: NudgeDirection) {
        let pixels = HotKeySettings.shared.nudgePixels
        let directionName: String
        switch direction {
        case .up: directionName = "up"
        case .down: directionName = "down"
        case .left: directionName = "left"
        case .right: directionName = "right"
        }
        debugPrint("📐 Moving window \(directionName) by \(pixels)px")
        
        // Get frontmost application
        guard let frontApp = NSWorkspace.shared.frontmostApplication else {
            debugPrint("❌ Failed to get frontmost application")
            return
        }
        
        // Get window via Accessibility API
        let appRef = AXUIElementCreateApplication(frontApp.processIdentifier)
        var windowRef: AnyObject?
        let result = AXUIElementCopyAttributeValue(appRef, kAXFocusedWindowAttribute as CFString, &windowRef)
        
        guard result == .success, let window = windowRef else {
            debugPrint("❌ Failed to get focused window")
            return
        }
        
        // Get current position
        var positionRef: AnyObject?
        AXUIElementCopyAttributeValue(window as! AXUIElement, kAXPositionAttribute as CFString, &positionRef)
        
        guard let positionValue = positionRef else {
            debugPrint("❌ Failed to get window position")
            return
        }
        
        var position = CGPoint.zero
        AXValueGetValue(positionValue as! AXValue, .cgPoint, &position)
        
        // Calculate new position
        var newPosition = position
        switch direction {
        case .up:
            newPosition.y -= CGFloat(pixels)
        case .down:
            newPosition.y += CGFloat(pixels)
        case .left:
            newPosition.x -= CGFloat(pixels)
        case .right:
            newPosition.x += CGFloat(pixels)
        }
        
        // Update position
        if let newPositionValue = AXValueCreate(.cgPoint, &newPosition) {
            let setResult = AXUIElementSetAttributeValue(window as! AXUIElement, kAXPositionAttribute as CFString, newPositionValue)
            if setResult == .success {
                debugPrint("✅ Window moved to (\(Int(newPosition.x)), \(Int(newPosition.y)))")
            } else {
                debugPrint("❌ Failed to move window: \(setResult.rawValue)")
            }
        }
    }
    
    func moveWindow(direction: Direction) {
        debugPrint("=== Starting move to \(direction == .next ? "next" : "previous") screen ===")
        
        // Get frontmost application
        guard let frontApp = NSWorkspace.shared.frontmostApplication,
              let appName = frontApp.localizedName else {
            debugPrint("❌ Failed to get frontmost application")
            return
        }
        
        debugPrint("Frontmost app: \(DebugLogger.shared.maskAppName(appName))")
        
        // Get window via Accessibility API
        let appRef = AXUIElementCreateApplication(frontApp.processIdentifier)
        var windowRef: AnyObject?
        let result = AXUIElementCopyAttributeValue(appRef, kAXFocusedWindowAttribute as CFString, &windowRef)
        
        guard result == .success, let window = windowRef else {
            debugPrint("❌ Failed to get focused window")
            return
        }
        
        debugPrint("✅ Got focused window")
        
        // Get current position and size
        var positionRef: AnyObject?
        var sizeRef: AnyObject?
        
        AXUIElementCopyAttributeValue(window as! AXUIElement, kAXPositionAttribute as CFString, &positionRef)
        AXUIElementCopyAttributeValue(window as! AXUIElement, kAXSizeAttribute as CFString, &sizeRef)
        
        guard let positionValue = positionRef, let sizeValue = sizeRef else {
            debugPrint("❌ Failed to get window position/size")
            return
        }
        
        var position = CGPoint.zero
        var size = CGSize.zero
        AXValueGetValue(positionValue as! AXValue, .cgPoint, &position)
        AXValueGetValue(sizeValue as! AXValue, .cgSize, &size)
        
        debugPrint("Current window position: \(position), size: \(size)")
        
        // Get available screens
        let screens = NSScreen.screens
        debugPrint("Available screens: \(screens.count)")
        
        guard screens.count > 1 else {
            debugPrint("❌ Multiple screens not connected")
            return
        }
        
        // Identify current screen
        var currentScreenIndex = 0
        for (index, screen) in screens.enumerated() {
            let screenFrame = screen.frame
            if screenFrame.contains(position) {
                currentScreenIndex = index
                break
            }
        }
        
        debugPrint("Current screen index: \(currentScreenIndex)")
        
        // Calculate next/previous screen index
        let nextScreenIndex: Int
        switch direction {
        case .next:
            nextScreenIndex = (currentScreenIndex + 1) % screens.count
        case .prev:
            nextScreenIndex = (currentScreenIndex - 1 + screens.count) % screens.count
        }
        
        debugPrint("Target screen index: \(nextScreenIndex)")
        
        let currentScreen = screens[currentScreenIndex]
        let nextScreen = screens[nextScreenIndex]
        
        // Move window while maintaining relative position
        let relativeX = position.x - currentScreen.frame.origin.x
        let relativeY = position.y - currentScreen.frame.origin.y
        
        let newX = nextScreen.frame.origin.x + relativeX
        let newY = nextScreen.frame.origin.y + relativeY
        var newPosition = CGPoint(x: newX, y: newY)
        
        debugPrint("New position: \(newPosition)")
        
        // Move window
        if let positionValue = AXValueCreate(.cgPoint, &newPosition) {
            let setResult = AXUIElementSetAttributeValue(window as! AXUIElement, kAXPositionAttribute as CFString, positionValue)
            
            if setResult == .success {
                debugPrint("✅ Window moved successfully")
            } else {
                debugPrint("❌ Failed to move window: \(setResult.rawValue)")
            }
        }
    }
    
    /// Setup display change monitoring
    private func setupDisplayChangeObserver() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(displayConfigurationChanged),
            name: NSApplication.didChangeScreenParametersNotification,
            object: nil
        )
        debugPrint("✅ Display change monitoring started")
    }
    
    /// Setup monitoring pause/resume notifications
    private func setupMonitoringControlObservers() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(pauseMonitoring),
            name: NSNotification.Name("DisableDisplayMonitoring"),
            object: nil
        )
        
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(resumeMonitoring),
            name: NSNotification.Name("ResumeDisplayMonitoring"),
            object: nil
        )
    }
    
    /// Handle display configuration change
    @objc private func displayConfigurationChanged() {
        let screenCount = NSScreen.screens.count
        debugPrint("🖥️ Display configuration changed")
        debugPrint("Current screen count: \(screenCount)")
        
        // If monitoring is disabled
        if !isDisplayMonitoringEnabled {
            // Keep recording events (this is important!)
            lastDisplayChangeTime = Date()
            
            // Start timer if not already running
            if stabilizationCheckTimer == nil {
                startStabilizationCheck()
            }
            return
        }
        
        // If monitoring is enabled - cancel fallback and restore
        fallbackTimer?.cancel()
        eventOccurredAfterStabilization = true
        triggerRestoration()
    }
    
    /// Start stabilization check timer
    private func startStabilizationCheck() {
        stabilizationCheckTimer?.invalidate()
        
        // Check stabilization every 0.5 seconds
        stabilizationCheckTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            self?.checkStabilization()
        }
    }
    
    /// Check stabilization
    private func checkStabilization() {
        guard let lastChange = lastDisplayChangeTime else { return }
        
        // Calculate elapsed time since last event
        let elapsed = Date().timeIntervalSince(lastChange)
        let stabilizationDelay = WindowTimingSettings.shared.displayStabilizationDelay
        
        if elapsed >= stabilizationDelay {
            // True stabilization achieved
            stabilizationCheckTimer?.invalidate()
            stabilizationCheckTimer = nil
            
            isDisplayMonitoringEnabled = true
            eventOccurredAfterStabilization = false
            
            debugPrint("✅ Display stabilized (\(String(format: "%.1f", elapsed))s since last event)")
            debugPrint("▶️ Resuming monitoring after display stabilization")
            debugPrint("⏳ Waiting for next display event (max 3s)")
            
            // Setup fallback (after 3 seconds)
            let fallback = DispatchWorkItem { [weak self] in
                self?.fallbackRestoration()
            }
            fallbackTimer = fallback
            DispatchQueue.main.asyncAfter(deadline: .now() + 3.0, execute: fallback)
        }
    }
    
    /// Fallback restoration
    private func fallbackRestoration() {
        if !eventOccurredAfterStabilization {
            // No event came -> trigger manually
            debugPrint("⚠️ No display event occurred, triggering restore manually")
            triggerRestoration()
        } else {
            // Event came -> skip
            debugPrint("✅ Display event occurred, skipping fallback")
        }
    }
    
    /// Trigger restoration process
    private func triggerRestoration(isRetry: Bool = false) {
        // Cancel existing timer
        restoreWorkItem?.cancel()
        
        // Reset retry counter when starting a new restore sequence
        if !isRetry {
            restoreRetryCount = 0
        }
        
        let settings = WindowTimingSettings.shared
        let totalDelay = settings.windowRestoreDelay
        
        debugPrint("Waiting \(String(format: "%.1f", totalDelay))s before restore") 
        
        let workItem = DispatchWorkItem { [weak self] in
            guard let self = self else { return }
            
            let restoredCount = self.restoreWindowsIfNeeded()
            
            // If restore succeeded and 2+ screens
            if restoredCount > 0 && NSScreen.screens.count >= 2 {
                self.restoreRetryCount = 0
                self.schedulePostDisplayConnectionSnapshot()
            } else if NSScreen.screens.count >= 2 && self.restoreRetryCount < self.maxRestoreRetries {
                // If restore failed and retry is available
                self.restoreRetryCount += 1
                debugPrint("🔄 Scheduling restore retry (\(self.restoreRetryCount)/\(self.maxRestoreRetries)): in \(String(format: "%.1f", self.restoreRetryDelay))s") 
                
                // Schedule retry
                DispatchQueue.main.asyncAfter(deadline: .now() + self.restoreRetryDelay) { [weak self] in
                    self?.triggerRestoration(isRetry: true)
                }
            } else {
                self.restoreRetryCount = 0
                debugPrint("⏭️ Skipping snapshot scheduling (restored: \(restoredCount), screens: \(NSScreen.screens.count))")
            }
        }
        
        restoreWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + totalDelay, execute: workItem)
    }
    
    /// Pause monitoring
    @objc private func pauseMonitoring() {
        isDisplayMonitoringEnabled = false
        lastDisplayChangeTime = nil
        stabilizationCheckTimer?.invalidate()
        stabilizationCheckTimer = nil
        fallbackTimer?.cancel()
        eventOccurredAfterStabilization = false
        debugPrint("⏸️ Display monitoring paused")
    }
    
    /// Resume monitoring
    @objc private func resumeMonitoring() {
        debugPrint("⏱️ Waiting for display stabilization...")
    }
    
    /// Get display identifier
    private func getDisplayIdentifier(for screen: NSScreen) -> String {
        if let screenNumber = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID {
            return String(screenNumber)
        }
        // Fallback: use screen frame
        return "\(Int(screen.frame.origin.x))_\(Int(screen.frame.origin.y))_\(Int(screen.frame.width))_\(Int(screen.frame.height))"
    }
    
    /// Create window identifier
    private func getWindowIdentifier(appName: String, windowID: CGWindowID) -> String {
        return "\(appName)_\(windowID)"
    }
    
    /// Start periodic monitoring for display memory
    private func startPeriodicSnapshot() {
        let interval = WindowTimingSettings.shared.displayMemoryInterval
        snapshotTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            self?.takeWindowSnapshot()
        }
        debugPrint("✅ Periodic monitoring started (\(Int(interval))s interval)")
    }
    
    /// Take snapshot of current window layout (for auto-restore)
    private func takeWindowSnapshot() {
        let screens = NSScreen.screens
        
        // Check display count - only update snapshot when 2+ screens
        // Keep existing data when 1 screen (to not lose data on external display disconnect)
        guard screens.count >= 2 else {
            return
        }
        
        let options = CGWindowListOption(arrayLiteral: .excludeDesktopElements, .optionOnScreenOnly)
        guard let windowList = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] else {
            return
        }
        
        // Backup external display data temporarily
        let mainScreenID = getDisplayIdentifier(for: screens[0])
        var externalDisplayBackup: [String: [String: WindowMatchInfo]] = [:]
        for (displayID, windows) in windowPositions {
            if displayID != mainScreenID && !windows.isEmpty {
                externalDisplayBackup[displayID] = windows
            }
        }
        
        // Clear old data and initialize per screen
        windowPositions.removeAll()
        for screen in screens {
            let displayID = getDisplayIdentifier(for: screen)
            windowPositions[displayID] = [:]
        }
        
        // Record all windows (WindowMatchInfo format)
        var windowCountPerDisplay: [String: Int] = [:]
        for window in windowList {
            guard let layer = window[kCGWindowLayer as String] as? Int, layer == 0,
                  let boundsDict = window[kCGWindowBounds as String] as? [String: CGFloat],
                  let ownerName = window[kCGWindowOwnerName as String] as? String,
                  let cgWindowID = window[kCGWindowNumber as String] as? CGWindowID else {
                continue
            }
            
            let frame = CGRect(
                x: boundsDict["X"] ?? 0,
                y: boundsDict["Y"] ?? 0,
                width: boundsDict["Width"] ?? 0,
                height: boundsDict["Height"] ?? 0
            )
            
            // Get window title (nil if not available)
            let windowTitle = window[kCGWindowName as String] as? String
            
            // Generate WindowMatchInfo (hashed)
            let matchInfo = WindowMatchInfo(
                appName: ownerName,
                title: windowTitle,
                size: frame.size,
                frame: frame
            )
            
            // Unique key (hash-based + CGWindowID)
            let windowKey = "\(matchInfo.appNameHash)_\(cgWindowID)"
            
            // Determine which screen this window is on
            for screen in screens {
                if screen.frame.intersects(frame) {
                    let displayID = getDisplayIdentifier(for: screen)
                    windowPositions[displayID]?[windowKey] = matchInfo
                    windowCountPerDisplay[displayID, default: 0] += 1
                    break
                }
            }
        }
        
        // Restore from backup if external display has 0 windows
        for (displayID, backupWindows) in externalDisplayBackup {
            if let currentCount = windowCountPerDisplay[displayID], currentCount > 0 {
                // Use current data if available
                continue
            }
            // Restore from backup if no current data
            if windowPositions[displayID] != nil {
                windowPositions[displayID] = backupWindows
                verbosePrint("🔄 Restoring backup for external display \(displayID): \(backupWindows.count) windows")
            }
        }
    }
    
    /// Save manual snapshot
    @objc func saveManualSnapshot() {
        debugPrint("📸 Starting manual snapshot save (slot \(currentSlotIndex))")
        
        let options = CGWindowListOption(arrayLiteral: .excludeDesktopElements, .optionOnScreenOnly)
        guard let windowList = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] else {
            debugPrint("  ❌ Failed to get window list")
            return
        }
        
        let screens = NSScreen.screens
        var snapshot: [String: [String: WindowMatchInfo]] = [:]
        
        // Initialize per screen
        for screen in screens {
            let displayID = getDisplayIdentifier(for: screen)
            snapshot[displayID] = [:]
        }
        
        var savedCount = 0
        
        // Record all windows
        for window in windowList {
            guard let layer = window[kCGWindowLayer as String] as? Int, layer == 0,
                  let boundsDict = window[kCGWindowBounds as String] as? [String: CGFloat],
                  let ownerName = window[kCGWindowOwnerName as String] as? String,
                  let cgWindowID = window[kCGWindowNumber as String] as? CGWindowID else {
                continue
            }
            
            let frame = CGRect(
                x: boundsDict["X"] ?? 0,
                y: boundsDict["Y"] ?? 0,
                width: boundsDict["Width"] ?? 0,
                height: boundsDict["Height"] ?? 0
            )
            
            // Get window title (nil if not available)
            let windowTitle = window[kCGWindowName as String] as? String
            
            // Generate WindowMatchInfo (hashed)
            let matchInfo = WindowMatchInfo(
                appName: ownerName,
                title: windowTitle,
                size: frame.size,
                frame: frame
            )
            
            // Generate unique key (hash-based)
            let windowKey = "\(matchInfo.appNameHash)_\(cgWindowID)"
            
            // Determine which screen this window is on
            for screen in screens {
                if screen.frame.intersects(frame) {
                    let displayID = getDisplayIdentifier(for: screen)
                    snapshot[displayID]?[windowKey] = matchInfo
                    savedCount += 1
                    // Log with title info (verbose mode)
                    let titleInfo = windowTitle != nil ? "title:✓" : "title:✗"
                    let sizeInfo = "\(Int(frame.width))x\(Int(frame.height))"
                    verbosePrint("  Saved: \(DebugLogger.shared.maskAppName(ownerName)) @ (\(Int(frame.origin.x)), \(Int(frame.origin.y))) [\(sizeInfo)] [\(titleInfo)]")
                    break
                }
            }
        }
        
        manualSnapshots[currentSlotIndex] = snapshot
        
        // Persist
        ManualSnapshotStorage.shared.save(manualSnapshots)
        
        debugPrint("📸 Snapshot saved: \(savedCount) windows")
        
        // Notification
        sendNotification(
            title: "Snapshot Saved",
            body: "Saved \(savedCount) window positions"
        )
        
        // Update menu
        setupMenu()
    }
    
    /// Restore manual snapshot
    @objc func restoreManualSnapshot() {
        debugPrint("📥 Starting manual snapshot restore (slot \(currentSlotIndex))")
        
        let snapshot = manualSnapshots[currentSlotIndex]
        
        if snapshot.isEmpty || snapshot.values.allSatisfy({ $0.isEmpty }) {
            debugPrint("  ⚠️ Snapshot is empty. Please save first.")
            return
        }
        
        let options = CGWindowListOption(arrayLiteral: .excludeDesktopElements, .optionOnScreenOnly)
        guard let windowList = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] else {
            debugPrint("  ❌ Failed to get window list")
            return
        }
        
        var restoredCount = 0
        var usedWindowIDs = Set<CGWindowID>()  // Track matched windows
        
        // Process saved data for each display
        for (displayID, savedWindows) in snapshot {
            verbosePrint("  📍 Display \(displayID): \(savedWindows.count) saved windows")
            for (windowKey, savedInfo) in savedWindows {
                let targetPos = "(\(Int(savedInfo.frame.origin.x)), \(Int(savedInfo.frame.origin.y)))"
                let targetSize = "\(Int(savedInfo.size.width))x\(Int(savedInfo.size.height))"
                let hasTitle = savedInfo.titleHash != nil ? "title:✓" : "title:✗"
                verbosePrint("    → Target: \(targetPos) [\(targetSize)] [\(hasTitle)]")
                
                // Extract CGWindowID from windowKey (format: appNameHash_CGWindowID)
                let components = windowKey.split(separator: "_")
                let savedCGWindowID: CGWindowID? = components.count >= 2 ? CGWindowID(components.last!) : nil
                
                // Matching: try in priority order (CGWindowID first)
                let matchedWindow = findMatchingWindow(
                    for: savedInfo,
                    in: windowList,
                    excluding: usedWindowIDs,
                    preferredCGWindowID: savedCGWindowID
                )
                
                guard let (matchedWindowInfo, ownerPID, ownerName, cgWindowID) = matchedWindow else {
                    verbosePrint("      ⚠️ No matching window found")
                    continue
                }
                
                usedWindowIDs.insert(cgWindowID)
                
                let currentFrame = matchedWindowInfo
                let savedFrame = savedInfo.frame
                
                // Skip if position hasn't changed
                if abs(currentFrame.origin.x - savedFrame.origin.x) < 5 &&
                   abs(currentFrame.origin.y - savedFrame.origin.y) < 5 {
                    continue
                }
                
                // Move window via Accessibility API
                let appRef = AXUIElementCreateApplication(ownerPID)
                var windowListRef: CFTypeRef?
                let result = AXUIElementCopyAttributeValue(appRef, kAXWindowsAttribute as CFString, &windowListRef)
                
                if result == .success, let windows = windowListRef as? [AXUIElement] {
                    for axWindow in windows {
                        var currentPosRef: CFTypeRef?
                        if AXUIElementCopyAttributeValue(axWindow, kAXPositionAttribute as CFString, &currentPosRef) == .success,
                           let currentPosValue = currentPosRef {
                            var currentPoint = CGPoint.zero
                            if AXValueGetValue(currentPosValue as! AXValue, .cgPoint, &currentPoint) {
                                // Check if current position matches current window position
                                if abs(currentPoint.x - currentFrame.origin.x) < 10 &&
                                   abs(currentPoint.y - currentFrame.origin.y) < 10 {
                                    // Move to saved coordinates
                                    var position = CGPoint(x: savedFrame.origin.x, y: savedFrame.origin.y)
                                    if let positionValue = AXValueCreate(.cgPoint, &position) {
                                        let posResult = AXUIElementSetAttributeValue(axWindow, kAXPositionAttribute as CFString, positionValue)
                                        
                                        // Also restore size
                                        var size = CGSize(width: savedFrame.width, height: savedFrame.height)
                                        var sizeRestored = false
                                        if let sizeValue = AXValueCreate(.cgSize, &size) {
                                            let sizeResult = AXUIElementSetAttributeValue(axWindow, kAXSizeAttribute as CFString, sizeValue)
                                            sizeRestored = (sizeResult == .success)
                                        }
                                        
                                        if posResult == .success {
                                            restoredCount += 1
                                            let sizeInfo = sizeRestored ? "+size" : ""
                                            debugPrint("    ✅ \(DebugLogger.shared.maskAppName(ownerName)) restored to (\(Int(savedFrame.origin.x)), \(Int(savedFrame.origin.y)))\(sizeInfo)")
                                        } else {
                                            debugPrint("    ❌ \(DebugLogger.shared.maskAppName(ownerName)) move failed: \(posResult.rawValue)")
                                        }
                                    }
                                    break
                                }
                            }
                        }
                    }
                }
            }
        }
        
        debugPrint("📥 Snapshot restore complete: \(restoredCount) windows moved")
        
        // Notification
        if restoredCount > 0 {
            sendNotification(
                title: "Snapshot Restored",
                body: "Restored \(restoredCount) window positions"
            )
        } else {
            sendNotification(
                title: "Snapshot Restored",
                body: "No windows to restore"
            )
        }
    }
    
    /// Find matching window with fallback matching
    /// Priority: 1. CGWindowID exact match  2. appNameHash + titleHash  3. appNameHash + size approximation  4. appNameHash only
    private func findMatchingWindow(
        for savedInfo: WindowMatchInfo,
        in windowList: [[String: Any]],
        excluding usedIDs: Set<CGWindowID>,
        preferredCGWindowID: CGWindowID? = nil
    ) -> (frame: CGRect, pid: Int32, appName: String, windowID: CGWindowID)? {
        
        var titleMatches: [(CGRect, Int32, String, CGWindowID, String)] = []  // 5th is title (for debug)
        var sizeMatches: [(CGRect, Int32, String, CGWindowID)] = []
        var appOnlyMatches: [(CGRect, Int32, String, CGWindowID)] = []
        
        let savedHasTitle = savedInfo.titleHash != nil
        
        for window in windowList {
            guard let layer = window[kCGWindowLayer as String] as? Int, layer == 0,
                  let boundsDict = window[kCGWindowBounds as String] as? [String: CGFloat],
                  let ownerName = window[kCGWindowOwnerName as String] as? String,
                  let ownerPID = window[kCGWindowOwnerPID as String] as? Int32,
                  let cgWindowID = window[kCGWindowNumber as String] as? CGWindowID else {
                continue
            }
            
            // Skip already used windows
            if usedIDs.contains(cgWindowID) {
                continue
            }
            
            let currentFrame = CGRect(
                x: boundsDict["X"] ?? 0,
                y: boundsDict["Y"] ?? 0,
                width: boundsDict["Width"] ?? 0,
                height: boundsDict["Height"] ?? 0
            )
            
            // Calculate appNameHash first (used for CGWindowID match too)
            let currentAppNameHash = WindowMatchInfo.hash(ownerName)
            
            // CGWindowID exact match (highest priority - reliable within session)
            // Also check appNameHash to avoid mismatching windows from different apps
            if let preferredID = preferredCGWindowID, cgWindowID == preferredID {
                if currentAppNameHash == savedInfo.appNameHash {
                    verbosePrint("    🆔 CGWindowID exact match: \(cgWindowID)")
                    return (currentFrame, ownerPID, ownerName, cgWindowID)
                }
            }
            
            // Check appNameHash (for fallback matching)
            guard currentAppNameHash == savedInfo.appNameHash else {
                continue
            }
            
            let matchData = (currentFrame, ownerPID, ownerName, cgWindowID)
            let currentTitle = window[kCGWindowName as String] as? String
            
            // Match by titleHash
            if let savedTitleHash = savedInfo.titleHash,
               let title = currentTitle {
                let currentTitleHash = WindowMatchInfo.hash(title)
                if currentTitleHash == savedTitleHash {
                    titleMatches.append((currentFrame, ownerPID, ownerName, cgWindowID, title))
                    continue
                }
            }
            
            // Match by size
            if savedInfo.sizeMatches(currentFrame.size) {
                sizeMatches.append(matchData)
                continue
            }
            
            // appName only match (last fallback)
            appOnlyMatches.append(matchData)
        }
        
        // Sort by proximity to saved position (prefer window closest to saved position)
        let savedOrigin = savedInfo.frame.origin
        
        func distanceToSaved(_ frame: CGRect) -> CGFloat {
            let dx = frame.origin.x - savedOrigin.x
            let dy = frame.origin.y - savedOrigin.y
            return sqrt(dx * dx + dy * dy)
        }
        
        // Sort size match candidates by position
        if sizeMatches.count > 1 {
            sizeMatches.sort { distanceToSaved($0.0) < distanceToSaved($1.0) }
        }
        
        // Sort appOnly match candidates by position
        if appOnlyMatches.count > 1 {
            appOnlyMatches.sort { distanceToSaved($0.0) < distanceToSaved($1.0) }
        }
        
        // Return in priority order (with verbose logs)
        if let match = titleMatches.first {
            let shortTitle = String(match.4.prefix(30))
            verbosePrint("    🎯 Title match: \"\(shortTitle)...\" (candidates:\(titleMatches.count))")
            return (match.0, match.1, match.2, match.3)
        }
        if let match = sizeMatches.first {
            let savedSize = "\(Int(savedInfo.size.width))x\(Int(savedInfo.size.height))"
            let titleStatus = savedHasTitle ? "saved title:✓" : "saved title:✗"
            let dist = Int(distanceToSaved(match.0))
            verbosePrint("    📐 Size match: \(savedSize) (candidates:\(sizeMatches.count),  dist:\(dist)px) [\(titleStatus)]")
            return match
        }
        if let match = appOnlyMatches.first {
            let dist = Int(distanceToSaved(match.0))
            verbosePrint("    📱 App name match (candidates:\(appOnlyMatches.count),  dist:\(dist)px)")
            return match
        }
        
        return nil
    }
    
    /// Restore windows and return the number of restored windows
    @discardableResult // Suppress warning when return value is unused
    private func restoreWindowsIfNeeded() -> Int {
        debugPrint("🔄 Starting window restore process...")
        
        let currentScreens = NSScreen.screens
        guard currentScreens.count >= 2 else {
            debugPrint("  Only one screen, skipping restore")
            return 0
        }
        
        let currentScreenIDs = Set(currentScreens.map { getDisplayIdentifier(for: $0) })
        let mainScreen = currentScreens[0]
        let mainScreenID = getDisplayIdentifier(for: mainScreen)
        
        // Check which saved screen IDs are currently connected
        let savedScreenIDs = Set(windowPositions.keys)
        let externalScreenIDs = savedScreenIDs.intersection(currentScreenIDs).subtracting([mainScreenID])
        
        if externalScreenIDs.isEmpty {
            debugPrint("  No external display to restore")
            return 0
        }
        
        debugPrint("  Target displays: \(externalScreenIDs.joined(separator: ", "))")
        
        // Get current all windows
        let options = CGWindowListOption(arrayLiteral: .excludeDesktopElements, .optionOnScreenOnly)
        guard let windowList = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] else {
            debugPrint("  ❌ Failed to get window list")
            return 0
        }
        
        // Debug: show current window list
        verbosePrint("  Current windows:")
        for window in windowList {
            if let ownerName = window[kCGWindowOwnerName as String] as? String,
               let cgWindowID = window[kCGWindowNumber as String] as? CGWindowID,
               let layer = window[kCGWindowLayer as String] as? Int, layer == 0 {
                verbosePrint("    Current: \(DebugLogger.shared.maskAppName(ownerName)) (ID:\(cgWindowID))")
            }
        }
        
        var restoredCount = 0
        var usedWindowIDs = Set<CGWindowID>()  // Track already matched windows
        
        // Process each external display
        for externalScreenID in externalScreenIDs {
            guard let savedWindows = windowPositions[externalScreenID], !savedWindows.isEmpty else {
                continue
            }
            
            verbosePrint("  📍 Screen \(externalScreenID) : \(savedWindows.count) saved windows")
            
            // Restore saved windows
            for (windowKey, savedInfo) in savedWindows {
                let targetPos = "(\(Int(savedInfo.frame.origin.x)), \(Int(savedInfo.frame.origin.y)))"
                verbosePrint("    → Target: \(targetPos)")
                
                // Extract CGWindowID from windowKey (format: appNameHash_CGWindowID)
                let components = windowKey.split(separator: "_")
                let savedCGWindowID: CGWindowID? = components.count >= 2 ? CGWindowID(components.last!) : nil
                
                // Use findMatchingWindow() for matching (CGWindowID priority)
                guard let matchedWindow = findMatchingWindow(
                    for: savedInfo,
                    in: windowList,
                    excluding: usedWindowIDs,
                    preferredCGWindowID: savedCGWindowID
                ) else {
                    verbosePrint("      ⚠️ No matching window found")
                    continue
                }
                
                let (currentFrame, ownerPID, ownerName, cgWindowID) = matchedWindow
                
                // Mark as used if CGWindowID exact match, regardless of position
                // (prevent same window from matching again in other entries)
                let isCGWindowIDMatch = savedCGWindowID != nil && savedCGWindowID == cgWindowID
                if isCGWindowIDMatch {
                    usedWindowIDs.insert(cgWindowID)
                }
                
                // Only restore windows on main screen
                let isOnMainScreen = currentFrame.origin.x >= mainScreen.frame.origin.x &&
                                    currentFrame.origin.x < (mainScreen.frame.origin.x + mainScreen.frame.width)
                
                if !isOnMainScreen {
                    // Already on external display is normal, change log level
                    if isCGWindowIDMatch {
                        verbosePrint("      ✓ Already on external display - X: \(Int(currentFrame.origin.x))")
                    } else {
                        verbosePrint("      ⚠️ Not on main screen (skip) - X: \(Int(currentFrame.origin.x))")
                    }
                    continue
                }
                
                verbosePrint("      ✓ On main screen - X: \(Int(currentFrame.origin.x))")
                
                // For size/title match, add to used here
                if !isCGWindowIDMatch {
                    usedWindowIDs.insert(cgWindowID)
                }
                
                let savedFrame = savedInfo.frame
                
                // Move window via Accessibility API
                let appRef = AXUIElementCreateApplication(ownerPID)
                var windowListRef: CFTypeRef?
                let result = AXUIElementCopyAttributeValue(appRef, kAXWindowsAttribute as CFString, &windowListRef)
                
                if result == .success, let windows = windowListRef as? [AXUIElement] {
                    // Find matching window from all windows
                    var matchFound = false
                    for axWindow in windows {
                        var currentPosRef: CFTypeRef?
                        if AXUIElementCopyAttributeValue(axWindow, kAXPositionAttribute as CFString, &currentPosRef) == .success,
                           let currentPosValue = currentPosRef {
                            var currentPoint = CGPoint.zero
                            if AXValueGetValue(currentPosValue as! AXValue, .cgPoint, &currentPoint) {
                                // Check if current position matches current window position
                                if abs(currentPoint.x - currentFrame.origin.x) < 50 &&
                                   abs(currentPoint.y - currentFrame.origin.y) < 50 {
                                    // Move to saved coordinates
                                    var position = CGPoint(x: savedFrame.origin.x, y: savedFrame.origin.y)
                                    if let positionValue = AXValueCreate(.cgPoint, &position) {
                                        let posResult = AXUIElementSetAttributeValue(axWindow, kAXPositionAttribute as CFString, positionValue)
                                        
                                        // Also restore size
                                        var size = CGSize(width: savedFrame.width, height: savedFrame.height)
                                        var sizeRestored = false
                                        if let sizeValue = AXValueCreate(.cgSize, &size) {
                                            let sizeResult = AXUIElementSetAttributeValue(axWindow, kAXSizeAttribute as CFString, sizeValue)
                                            sizeRestored = (sizeResult == .success)
                                        }
                                        
                                        if posResult == .success {
                                            restoredCount += 1
                                            let sizeInfo = sizeRestored ? "+size" : ""
                                            debugPrint("    ✅ \(DebugLogger.shared.maskAppName(ownerName)) restored to (\(Int(savedFrame.origin.x)), \(Int(savedFrame.origin.y)))\(sizeInfo)")
                                        } else {
                                            debugPrint("    ❌ \(DebugLogger.shared.maskAppName(ownerName)) move failed: \(posResult.rawValue)")
                                        }
                                    }
                                    matchFound = true
                                    break
                                }
                            }
                        }
                    }
                    if !matchFound {
                        verbosePrint("      ⚠️ AXUIElement position match failed - CGWindow pos: (\(Int(currentFrame.origin.x)), \(Int(currentFrame.origin.y)))")
                    }
                }
            }
        }
        
        debugPrint("✅ Total \(restoredCount) windows restored\n")
        return restoredCount
    }
    
    // MARK: - Auto Snapshot Feature
    
    /// Load saved snapshots
    private func loadSavedSnapshots() {
        if let savedSnapshots = ManualSnapshotStorage.shared.load() {
            // Check and adjust slot count
            for (index, snapshot) in savedSnapshots.enumerated() {
                if index < manualSnapshots.count {
                    manualSnapshots[index] = snapshot
                }
            }
            
            // Count saved windows
            var totalWindows = 0
            for snapshot in manualSnapshots {
                for (_, windows) in snapshot {
                    totalWindows += windows.count
                }
            }
            
            if totalWindows > 0 {
                debugPrint("💾 Loaded saved snapshot: \(totalWindows) windows")
            }
        } else {
            debugPrint("💾 No saved snapshot found")
        }
    }
    
    /// Setup snapshot settings change observers
    private func setupSnapshotSettingsObservers() {
        // Monitor settings change notification
        NotificationCenter.default.addObserver(
            forName: Notification.Name("SnapshotSettingsChanged"),
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.restartPeriodicSnapshotTimerIfNeeded()
        }
        
        // Monitor snapshot clear notification
        NotificationCenter.default.addObserver(
            forName: Notification.Name("ClearManualSnapshot"),
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.clearManualSnapshots()
        }
        
        // Monitor display memory interval change notification
        NotificationCenter.default.addObserver(
            forName: Notification.Name("DisplayMemoryIntervalChanged"),
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.restartDisplayMemoryTimer()
        }
    }
    
    /// Restart display memory timer
    private func restartDisplayMemoryTimer() {
        snapshotTimer?.invalidate()
        let interval = WindowTimingSettings.shared.displayMemoryInterval
        snapshotTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            self?.takeWindowSnapshot()
        }
        debugPrint("🔄 Display memory interval changed(\(Int(interval))s interval)")
    }
    
    /// Clear manual snapshots
    private func clearManualSnapshots() {
        manualSnapshots = Array(repeating: [:], count: 5)
        debugPrint("🗑️ In-memory snapshot cleared")
    }
    
    /// Start initial auto-snapshot timer
    private func startInitialSnapshotTimer() {
        let settings = SnapshotSettings.shared
        let delaySeconds = settings.initialDelaySeconds
        
        debugPrint("⏱️ Initial auto-snapshot timer started: \(String(format: "%.1f", delaySeconds/60))min")
        
        // Cancel existing timer
        initialSnapshotTimer?.invalidate()
        initialSnapshotTimer = nil
        
        // Add Timer to RunLoop in .common mode (works during UI operations)
        let timer = Timer(timeInterval: delaySeconds, repeats: false) { [weak self] _ in
            debugPrint("⏱️ Initial auto-snapshot timer fired")
            self?.performAutoSnapshot(reason: "Initial auto")
            self?.hasInitialSnapshotBeenTaken = true
            
            // Start periodic snapshot if enabled
            let snapshotSettings = SnapshotSettings.shared
            if snapshotSettings.enablePeriodicSnapshot {
                self?.startPeriodicSnapshotTimer()
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        initialSnapshotTimer = timer
    }
    
    /// Start periodic snapshot timer
    private func startPeriodicSnapshotTimer() {
        let settings = SnapshotSettings.shared
        
        guard settings.enablePeriodicSnapshot else {
            debugPrint("⏱️ Periodic snapshot is disabled")
            return
        }
        
        let intervalSeconds = settings.periodicIntervalSeconds
        
        debugPrint("⏱️ Periodic snapshot timer started: \(String(format: "%.0f", intervalSeconds/60))min interval")
        
        // Cancel existing timer
        periodicSnapshotTimer?.invalidate()
        periodicSnapshotTimer = nil
        
        // Add Timer to RunLoop in .common mode (works during UI operations)
        let timer = Timer(timeInterval: intervalSeconds, repeats: true) { [weak self] _ in
            debugPrint("⏱️ Periodic snapshot timer fired")
            self?.performAutoSnapshot(reason: "Periodic auto")
        }
        RunLoop.main.add(timer, forMode: .common)
        periodicSnapshotTimer = timer
    }
    
    /// Restart periodic snapshot timer (on settings change)
    private func restartPeriodicSnapshotTimerIfNeeded() {
        let settings = SnapshotSettings.shared
        
        periodicSnapshotTimer?.invalidate()
        periodicSnapshotTimer = nil
        
        if settings.enablePeriodicSnapshot && hasInitialSnapshotBeenTaken {
            startPeriodicSnapshotTimer()
        } else if !settings.enablePeriodicSnapshot {
            debugPrint("⏱️ Periodic snapshot stopped")
        }
    }
    
    /// Perform auto snapshot
    private func performAutoSnapshot(reason: String) {
        debugPrint("📸 \(reason)snapshot in progress...")
        
        // Check display count
        let screenCount = NSScreen.screens.count
        if screenCount < 2 {
            debugPrint("🛡️ Display protection: screen count is\(screenCount), skipping auto-snapshot")
            return
        }
        
        let options = CGWindowListOption(arrayLiteral: .excludeDesktopElements, .optionOnScreenOnly)
        guard let windowList = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] else {
            debugPrint("  ❌ Failed to get window list")
            return
        }
        
        let screens = NSScreen.screens
        var snapshot: [String: [String: WindowMatchInfo]] = [:]
        
        // Initialize per screen
        for screen in screens {
            let displayID = getDisplayIdentifier(for: screen)
            snapshot[displayID] = [:]
        }
        
        var savedCount = 0
        
        // Record all windows
        for window in windowList {
            guard let layer = window[kCGWindowLayer as String] as? Int, layer == 0,
                  let boundsDict = window[kCGWindowBounds as String] as? [String: CGFloat],
                  let ownerName = window[kCGWindowOwnerName as String] as? String,
                  let cgWindowID = window[kCGWindowNumber as String] as? CGWindowID else {
                continue
            }
            
            let frame = CGRect(
                x: boundsDict["X"] ?? 0,
                y: boundsDict["Y"] ?? 0,
                width: boundsDict["Width"] ?? 0,
                height: boundsDict["Height"] ?? 0
            )
            
            // Get window title (nil if not available)
            let windowTitle = window[kCGWindowName as String] as? String
            
            // Generate WindowMatchInfo (hashed)
            let matchInfo = WindowMatchInfo(
                appName: ownerName,
                title: windowTitle,
                size: frame.size,
                frame: frame
            )
            
            // Generate unique key (hash-based)
            let windowKey = "\(matchInfo.appNameHash)_\(cgWindowID)"
            
            // Determine which screen this window is on
            for screen in screens {
                if screen.frame.intersects(frame) {
                    let displayID = getDisplayIdentifier(for: screen)
                    snapshot[displayID]?[windowKey] = matchInfo
                    savedCount += 1
                    break
                }
            }
        }
        
        // Existing data protection check
        let snapshotSettings = SnapshotSettings.shared
        if snapshotSettings.protectExistingSnapshot && ManualSnapshotStorage.shared.hasSnapshot {
            if savedCount < snapshotSettings.minimumWindowCount {
                debugPrint("🛡️ Data protection: window count is\(savedCount) (min:\(snapshotSettings.minimumWindowCount)), skipping overwrite")
                return
            }
        }
        
        manualSnapshots[currentSlotIndex] = snapshot
        
        // Persist
        ManualSnapshotStorage.shared.save(manualSnapshots)
        
        debugPrint("📸 \(reason)snapshot complete: \(savedCount) windows")
        
        // Notification (auto snapshot: sound only, no system notification)
        if SnapshotSettings.shared.enableSound {
            NSSound(named: NSSound.Name(SnapshotSettings.shared.soundName))?.play()
        }
        
        // Update menu
        DispatchQueue.main.async { [weak self] in
            self?.setupMenu()
        }
    }
    
    /// Schedule snapshot timer after external display recognition stabilization
    func schedulePostDisplayConnectionSnapshot() {
        let settings = SnapshotSettings.shared
        let delaySeconds = settings.initialDelaySeconds
        
        debugPrint("⏱️ Post-display-connection snapshot: \(String(format: "%.1f", delaySeconds/60))min scheduled")
        
        // Cancel existing initial timer and set new one
        initialSnapshotTimer?.invalidate()
        initialSnapshotTimer = nil
        
        // Add Timer to RunLoop in .common mode (works during UI operations)
        let timer = Timer(timeInterval: delaySeconds, repeats: false) { [weak self] _ in
            debugPrint("⏱️ Post-display-connection snapshot timer fired")
            self?.performAutoSnapshot(reason: "Post-display auto")
            self?.hasInitialSnapshotBeenTaken = true
            
            // Start periodic snapshot if enabled and not yet started
            let snapshotSettings = SnapshotSettings.shared
            if snapshotSettings.enablePeriodicSnapshot && self?.periodicSnapshotTimer == nil {
                self?.startPeriodicSnapshotTimer()
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        initialSnapshotTimer = timer
    }
    
    
    
    func applicationWillTerminate(_ notification: Notification) {
        // Clear snapshot on termination if privacy protection mode is enabled
        if SnapshotSettings.shared.disablePersistence {
            ManualSnapshotStorage.shared.clear()
            debugPrint("🔒 App terminating: Clearing snapshot (privacy mode)")
        }
    }
    
    deinit {
        // Unregister hotkeys
        if let hotKey = hotKeyRef {
            UnregisterEventHotKey(hotKey)
        }
        if let hotKey = hotKeyRef2 {
            UnregisterEventHotKey(hotKey)
        }
        if let hotKey = hotKeyRef3 {
            UnregisterEventHotKey(hotKey)
        }
        if let hotKey = hotKeyRef4 {
            UnregisterEventHotKey(hotKey)
        }
        if let hotKey = hotKeyRef5 {
            UnregisterEventHotKey(hotKey)
        }
        if let hotKey = hotKeyRef6 {
            UnregisterEventHotKey(hotKey)
        }
        if let hotKey = hotKeyRef7 {
            UnregisterEventHotKey(hotKey)
        }
        if let hotKey = hotKeyRef8 {
            UnregisterEventHotKey(hotKey)
        }
        if let handler = eventHandler {
            RemoveEventHandler(handler)
        }
        // Stop timers
        snapshotTimer?.invalidate()
        initialSnapshotTimer?.invalidate()
        periodicSnapshotTimer?.invalidate()
    }
}

// Implementation of debugPrint function
func debugPrint(_ message: String) {
    print(message)
    DebugLogger.shared.addLog(message)
}

// Verbose log (output only when enabled in settings)
func verbosePrint(_ message: String) {
    guard SnapshotSettings.shared.verboseLogging else { return }
    print(message)
    DebugLogger.shared.addLog(message)
}
