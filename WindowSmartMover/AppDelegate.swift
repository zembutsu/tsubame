import Cocoa
import Carbon
import SwiftUI
import UserNotifications
import SystemConfiguration

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
        case 9: // 1 (select slot 1)
            appDelegate.selectSlotByHotkey(1)
        case 10: // 2 (select slot 2)
            appDelegate.selectSlotByHotkey(2)
        case 11: // 3 (select slot 3)
            appDelegate.selectSlotByHotkey(3)
        case 12: // 4 (select slot 4)
            appDelegate.selectSlotByHotkey(4)
        case 13: // 5 (select slot 5)
            appDelegate.selectSlotByHotkey(5)
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
        let formatter = DateFormatter()
        if SnapshotSettings.shared.showMilliseconds {
            formatter.dateFormat = "HH:mm:ss.SSS"
        } else {
            formatter.dateFormat = "HH:mm:ss"
        }
        let timestamp = formatter.string(from: Date())
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
    var hotKeyRef9: EventHotKeyRef?  // Slot 1 (1)
    var hotKeyRef10: EventHotKeyRef? // Slot 2 (2)
    var hotKeyRef11: EventHotKeyRef? // Slot 3 (3)
    var hotKeyRef12: EventHotKeyRef? // Slot 4 (4)
    var hotKeyRef13: EventHotKeyRef? // Slot 5 (5)
    var eventHandler: EventHandlerRef?
    var settingsWindow: NSWindow?
    var aboutWindow: NSWindow?
    var debugWindow: NSWindow?
    
    // Timer management (delegated to TimerManager)
    private let timerManager = TimerManager.shared
    
    // Snapshot storage (6 slots)
    // Slot 0: Auto-snapshot for display memory (updated every 30s, persisted every 30min)
    // Slot 1-5: Manual snapshots (user-triggered)
    // Format: [displayID: [windowKey: WindowMatchInfo]]
    private var manualSnapshots: [[String: [String: WindowMatchInfo]]] = Array(repeating: [:], count: 6)
    
    // Current slot index for manual operations (1-5, Slot 0 is reserved for auto-snapshot)
    private var currentSlotIndex: Int {
        get { ManualSnapshotStorage.shared.activeSlotIndex }
        set { ManualSnapshotStorage.shared.activeSlotIndex = newValue }
    }
    
    // Auto snapshot feature
    private var hasInitialSnapshotBeenTaken = false
    
    // Monitoring enabled/disabled state (unified flag for system sleep, display sleep)
    private var isMonitoringEnabled = true
    
    // Last display change time (for stabilization detection)
    private var lastDisplayChangeTime: Date?
    
    // Event occurred after stabilization flag
    private var eventOccurredAfterStabilization = false
    
    // Restore retry feature
    private var restoreRetryCount: Int = 0
    private let maxRestoreRetries: Int = 2
    private let restoreRetryDelay: TimeInterval = 3.0
    
    // Fallback restoration feature (triggers if no display event after stabilization)
    private let fallbackWaitDelay: TimeInterval = 3.0
    
    // Restore cooldown feature (prevents duplicate restore on rapid display events)
    private var lastRestoreTime: Date?
    private let restoreCooldown: TimeInterval = 5.0
    private var lastScreenCount: Int = 0
    
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
        let failedHotkeys = registerHotKeys()
        
        // Show warning if any hotkey registration failed
        if !failedHotkeys.isEmpty {
            showHotkeyRegistrationWarning(failedHotkeys: failedHotkeys)
        }
        
        // Check accessibility permissions
        checkAccessibilityPermissions()
        
        // Start display change monitoring
        setupDisplayChangeObserver()
        
        // Setup monitoring control observers
        setupMonitoringControlObservers()
        
        // Setup snapshot settings observers
        setupSnapshotSettingsObservers()
        
        // Setup hotkey settings observer
        setupHotkeySettingsObserver()
        
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
        
        // Initialize lastScreenCount for cooldown logic
        lastScreenCount = NSScreen.screens.count
        
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
        
        // Window nudge submenu
        let nudgeMenuItem = NSMenuItem(title: NSLocalizedString("🔀 Nudge Window", comment: "Menu item for window nudge"), action: nil, keyEquivalent: "")
        let nudgeSubmenu = NSMenu()
        
        let nudgeUp = NSMenuItem(title: NSLocalizedString("↑ Up", comment: "Nudge window up"), action: #selector(nudgeWindowUp), keyEquivalent: "w")
        nudgeUp.keyEquivalentModifierMask = [.control, .command]
        nudgeSubmenu.addItem(nudgeUp)
        
        let nudgeDown = NSMenuItem(title: NSLocalizedString("↓ Down", comment: "Nudge window down"), action: #selector(nudgeWindowDown), keyEquivalent: "s")
        nudgeDown.keyEquivalentModifierMask = [.control, .command]
        nudgeSubmenu.addItem(nudgeDown)
        
        let nudgeLeft = NSMenuItem(title: NSLocalizedString("← Left", comment: "Nudge window left"), action: #selector(nudgeWindowLeft), keyEquivalent: "a")
        nudgeLeft.keyEquivalentModifierMask = [.control, .command]
        nudgeSubmenu.addItem(nudgeLeft)
        
        let nudgeRight = NSMenuItem(title: NSLocalizedString("→ Right", comment: "Nudge window right"), action: #selector(nudgeWindowRight), keyEquivalent: "d")
        nudgeRight.keyEquivalentModifierMask = [.control, .command]
        nudgeSubmenu.addItem(nudgeRight)
        
        nudgeMenuItem.submenu = nudgeSubmenu
        menu.addItem(nudgeMenuItem)
        
        menu.addItem(NSMenuItem.separator())
        // Snapshot operations
        let saveTitle = String(format: NSLocalizedString("📸 Save Layout (%@↑)", comment: "Menu item for saving window layout"), modifierString)
        menu.addItem(NSMenuItem(title: saveTitle, action: #selector(saveManualSnapshot), keyEquivalent: ""))
        
        let restoreTitle = String(format: NSLocalizedString("📥 Restore Layout (%@↓)", comment: "Menu item for restoring window layout"), modifierString)
        menu.addItem(NSMenuItem(title: restoreTitle, action: #selector(restoreManualSnapshot), keyEquivalent: ""))
        
        menu.addItem(NSMenuItem.separator())
        
        // Slot selection submenu
        let slotMenuItem = NSMenuItem(title: NSLocalizedString("🎯 Slot", comment: "Menu item for slot selection"), action: nil, keyEquivalent: "")
        let slotSubmenu = NSMenu()
        
        for slotIndex in 1...5 {
            let slotInfo = ManualSnapshotStorage.shared.getSlotInfo(for: slotIndex)
            let isActive = slotIndex == currentSlotIndex
            let statusString = getSlotStatusString(for: slotIndex, info: slotInfo)
            
            let slotItem = NSMenuItem(
                title: statusString,
                action: #selector(selectSlot(_:)),
                keyEquivalent: "\(slotIndex)"
            )
            slotItem.keyEquivalentModifierMask = [.control, .command]
            slotItem.tag = slotIndex
            slotItem.state = isActive ? .on : .off
            slotSubmenu.addItem(slotItem)
        }
        
        slotMenuItem.submenu = slotSubmenu
        menu.addItem(slotMenuItem)
        
        // Current slot status
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
    
    /// Select snapshot slot
    @objc private func selectSlot(_ sender: NSMenuItem) {
        let newSlotIndex = sender.tag
        guard newSlotIndex >= 1 && newSlotIndex <= 5 else { return }
        
        currentSlotIndex = newSlotIndex
        debugPrint("🎯 Switched to Slot \(newSlotIndex)")
        
        // Play sound if enabled
        if SnapshotSettings.shared.enableSound {
            NSSound(named: NSSound.Name(SnapshotSettings.shared.soundName))?.play()
        }
        
        // Update menu to reflect selection
        setupMenu()
    }
    
    /// Select snapshot slot by hotkey (called from hotKeyHandler)
    func selectSlotByHotkey(_ slotIndex: Int) {
        guard slotIndex >= 1 && slotIndex <= 5 else { return }
        
        currentSlotIndex = slotIndex
        debugPrint("🎯 Switched to Slot \(slotIndex) (via hotkey)")
        
        // Play sound if enabled
        if SnapshotSettings.shared.enableSound {
            NSSound(named: NSSound.Name(SnapshotSettings.shared.soundName))?.play()
        }
        
        // Update menu to reflect selection
        setupMenu()
    }
    
    /// Generate slot status string for submenu
    private func getSlotStatusString(for slotIndex: Int, info: (windowCount: Int, updatedAt: Date?)?) -> String {
        let slotLabel = String(format: NSLocalizedString("Slot %d", comment: "Slot label"), slotIndex)
        
        guard let info = info, info.windowCount > 0 else {
            let emptyString = NSLocalizedString("empty", comment: "Slot status when empty")
            return "\(slotLabel) (\(emptyString))"
        }
        
        if let updatedAt = info.updatedAt {
            let formatter = DateFormatter()
            // Show date if not today
            if Calendar.current.isDateInToday(updatedAt) {
                formatter.dateFormat = "HH:mm"
            } else {
                formatter.dateFormat = "MM/dd HH:mm"
            }
            let timeStr = formatter.string(from: updatedAt)
            let format = NSLocalizedString("%d windows @ %@", comment: "Slot status with window count and time")
            return "\(slotLabel) (\(String(format: format, info.windowCount, timeStr)))"
        } else {
            let format = NSLocalizedString("%d windows", comment: "Slot status with window count only")
            return "\(slotLabel) (\(String(format: format, info.windowCount)))"
        }
    }
    
    /// Generate snapshot status string for current slot
    private func getSnapshotStatusString() -> String {
        let slotInfo = ManualSnapshotStorage.shared.getSlotInfo(for: currentSlotIndex)
        
        if let info = slotInfo, info.windowCount > 0 {
            if let updatedAt = info.updatedAt {
                let formatter = DateFormatter()
                // Show date if not today
                if Calendar.current.isDateInToday(updatedAt) {
                    formatter.dateFormat = "HH:mm"
                } else {
                    formatter.dateFormat = "MM/dd HH:mm"
                }
                let timeStr = formatter.string(from: updatedAt)
                let format = NSLocalizedString("    💾 Slot %d: %d windows @ %@", comment: "Snapshot status with slot, window count and time")
                return String(format: format, currentSlotIndex, info.windowCount, timeStr)
            } else {
                let format = NSLocalizedString("    💾 Slot %d: %d windows", comment: "Snapshot status with slot and window count")
                return String(format: format, currentSlotIndex, info.windowCount)
            }
        } else {
            let format = NSLocalizedString("    💾 Slot %d: No data", comment: "Snapshot status when no data exists")
            return String(format: format, currentSlotIndex)
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
    
    /// Register hotkeys and return list of failed registrations
    @discardableResult
    func registerHotKeys() -> [String] {
        var failedHotkeys: [String] = []
        
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
        let modifierString = settings.getModifierString()
        
        // Hotkey definitions: (keyCode, description, hotKeyRef pointer, id)
        struct HotKeyDef {
            let keyCode: UInt32
            let symbol: String
            let description: String
            let id: UInt32
        }
        
        let hotKeyDefs: [HotKeyDef] = [
            HotKeyDef(keyCode: UInt32(kVK_RightArrow), symbol: "→", description: "Move to next screen", id: 1),
            HotKeyDef(keyCode: UInt32(kVK_LeftArrow), symbol: "←", description: "Move to previous screen", id: 2),
            HotKeyDef(keyCode: UInt32(kVK_UpArrow), symbol: "↑", description: "Save snapshot", id: 3),
            HotKeyDef(keyCode: UInt32(kVK_DownArrow), symbol: "↓", description: "Restore snapshot", id: 4),
            HotKeyDef(keyCode: UInt32(kVK_ANSI_W), symbol: "W", description: "Nudge up", id: 5),
            HotKeyDef(keyCode: UInt32(kVK_ANSI_A), symbol: "A", description: "Nudge left", id: 6),
            HotKeyDef(keyCode: UInt32(kVK_ANSI_S), symbol: "S", description: "Nudge down", id: 7),
            HotKeyDef(keyCode: UInt32(kVK_ANSI_D), symbol: "D", description: "Nudge right", id: 8),
            HotKeyDef(keyCode: UInt32(kVK_ANSI_1), symbol: "1", description: "Select Slot 1", id: 9),
            HotKeyDef(keyCode: UInt32(kVK_ANSI_2), symbol: "2", description: "Select Slot 2", id: 10),
            HotKeyDef(keyCode: UInt32(kVK_ANSI_3), symbol: "3", description: "Select Slot 3", id: 11),
            HotKeyDef(keyCode: UInt32(kVK_ANSI_4), symbol: "4", description: "Select Slot 4", id: 12),
            HotKeyDef(keyCode: UInt32(kVK_ANSI_5), symbol: "5", description: "Select Slot 5", id: 13),
        ]
        
        // Array to store hotkey refs (index corresponds to id - 1)
        var hotKeyRefs: [EventHotKeyRef?] = Array(repeating: nil, count: 13)
        
        for def in hotKeyDefs {
            let hotKeyID = EventHotKeyID(signature: OSType(0x4D4F5645), id: def.id) // 'MOVE' + id
            var newHotKeyRef: EventHotKeyRef?
            let registerStatus = RegisterEventHotKey(def.keyCode, modifiers, hotKeyID, GetApplicationEventTarget(), 0, &newHotKeyRef)
            
            if registerStatus == noErr {
                debugPrint("✅ Hotkey \(def.id) (\(modifierString)\(def.symbol)) registered")
                hotKeyRefs[Int(def.id) - 1] = newHotKeyRef
            } else {
                debugPrint("❌ Failed to register hotkey \(def.id): \(registerStatus)")
                failedHotkeys.append("\(modifierString)\(def.symbol) (\(def.description))")
            }
        }
        
        // Assign to instance variables
        hotKeyRef = hotKeyRefs[0]
        hotKeyRef2 = hotKeyRefs[1]
        hotKeyRef3 = hotKeyRefs[2]
        hotKeyRef4 = hotKeyRefs[3]
        hotKeyRef5 = hotKeyRefs[4]
        hotKeyRef6 = hotKeyRefs[5]
        hotKeyRef7 = hotKeyRefs[6]
        hotKeyRef8 = hotKeyRefs[7]
        hotKeyRef9 = hotKeyRefs[8]
        hotKeyRef10 = hotKeyRefs[9]
        hotKeyRef11 = hotKeyRefs[10]
        hotKeyRef12 = hotKeyRefs[11]
        hotKeyRef13 = hotKeyRefs[12]
        
        return failedHotkeys
    }
    
    /// Show alert for failed hotkey registrations
    private func showHotkeyRegistrationWarning(failedHotkeys: [String]) {
        guard !failedHotkeys.isEmpty else { return }
        
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = NSLocalizedString("Hotkey Registration Failed", comment: "Alert title for hotkey registration failure")
        
        let failedList = failedHotkeys.map { "• \($0)" }.joined(separator: "\n")
        let informativeText = String(format: NSLocalizedString(
            "The following shortcuts could not be registered:\n\n%@\n\nThis usually means another app is using the same shortcut. Check System Settings → Keyboard → Shortcuts, or try different modifier keys in Tsubame Settings.",
            comment: "Alert message for hotkey registration failure"
        ), failedList)
        alert.informativeText = informativeText
        
        alert.addButton(withTitle: NSLocalizedString("Open Settings", comment: "Button to open settings"))
        alert.addButton(withTitle: NSLocalizedString("OK", comment: "OK button"))
        
        // Show alert on main thread
        DispatchQueue.main.async { [weak self] in
            let response = alert.runModal()
            if response == .alertFirstButtonReturn {
                self?.openSettings()
            }
        }
    }
    
    /// Unregister all hotkeys (for cleanup or re-registration)
    func unregisterHotKeys() {
        if let hotKey = hotKeyRef {
            UnregisterEventHotKey(hotKey)
            hotKeyRef = nil
        }
        if let hotKey = hotKeyRef2 {
            UnregisterEventHotKey(hotKey)
            hotKeyRef2 = nil
        }
        if let hotKey = hotKeyRef3 {
            UnregisterEventHotKey(hotKey)
            hotKeyRef3 = nil
        }
        if let hotKey = hotKeyRef4 {
            UnregisterEventHotKey(hotKey)
            hotKeyRef4 = nil
        }
        if let hotKey = hotKeyRef5 {
            UnregisterEventHotKey(hotKey)
            hotKeyRef5 = nil
        }
        if let hotKey = hotKeyRef6 {
            UnregisterEventHotKey(hotKey)
            hotKeyRef6 = nil
        }
        if let hotKey = hotKeyRef7 {
            UnregisterEventHotKey(hotKey)
            hotKeyRef7 = nil
        }
        if let hotKey = hotKeyRef8 {
            UnregisterEventHotKey(hotKey)
            hotKeyRef8 = nil
        }
        if let hotKey = hotKeyRef9 {
            UnregisterEventHotKey(hotKey)
            hotKeyRef9 = nil
        }
        if let hotKey = hotKeyRef10 {
            UnregisterEventHotKey(hotKey)
            hotKeyRef10 = nil
        }
        if let hotKey = hotKeyRef11 {
            UnregisterEventHotKey(hotKey)
            hotKeyRef11 = nil
        }
        if let hotKey = hotKeyRef12 {
            UnregisterEventHotKey(hotKey)
            hotKeyRef12 = nil
        }
        if let hotKey = hotKeyRef13 {
            UnregisterEventHotKey(hotKey)
            hotKeyRef13 = nil
        }
        debugPrint("🔑 All hotkeys unregistered")
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
        var axWindow: AXUIElement?
        
        // Try focused window first
        var windowRef: CFTypeRef?
        var result = AXUIElementCopyAttributeValue(appRef, kAXFocusedWindowAttribute as CFString, &windowRef)
        
        if result == .success, windowRef != nil {
            // Note: CoreFoundation type casts always succeed after API success check
            axWindow = (windowRef as! AXUIElement)
            verbosePrint("  ✓ Got focused window")
        } else {
            // Fallback: get first window from all windows
            verbosePrint("  ⚠️ Focused window not available (result: \(result.rawValue)), trying fallback...")
            var windowsRef: CFTypeRef?
            result = AXUIElementCopyAttributeValue(appRef, kAXWindowsAttribute as CFString, &windowsRef)
            
            if result == .success, let windows = windowsRef as? [AXUIElement], !windows.isEmpty {
                axWindow = windows[0]
                verbosePrint("  ✓ Got window via fallback (first of \(windows.count) windows)")
            }
        }
        
        guard let axWindow = axWindow else {
            debugPrint("❌ Failed to get focused window (no fallback available)")
            return
        }
        
        // Get current position
        var positionRef: CFTypeRef?
        let posResult = AXUIElementCopyAttributeValue(axWindow, kAXPositionAttribute as CFString, &positionRef)
        
        guard posResult == .success, let positionValue = positionRef else {
            debugPrint("❌ Failed to get window position (result: \(posResult.rawValue))")
            return
        }
        
        var position = CGPoint.zero
        guard AXValueGetValue(positionValue as! AXValue, .cgPoint, &position) else {
            debugPrint("❌ Failed to extract position value from AXValue")
            return
        }
        
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
            let setResult = AXUIElementSetAttributeValue(axWindow, kAXPositionAttribute as CFString, newPositionValue)
            if setResult == .success {
                debugPrint("✅ Window moved to (\(Int(newPosition.x)), \(Int(newPosition.y)))")
            } else {
                debugPrint("❌ Failed to move window: \(setResult.rawValue)")
            }
        }
    }
    
    // MARK: - Nudge Window Menu Actions
    
    @objc func nudgeWindowUp() {
        nudgeWindow(direction: .up)
    }
    
    @objc func nudgeWindowDown() {
        nudgeWindow(direction: .down)
    }
    
    @objc func nudgeWindowLeft() {
        nudgeWindow(direction: .left)
    }
    
    @objc func nudgeWindowRight() {
        nudgeWindow(direction: .right)
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
        var axWindow: AXUIElement?
        
        // Try focused window first
        var windowRef: CFTypeRef?
        var result = AXUIElementCopyAttributeValue(appRef, kAXFocusedWindowAttribute as CFString, &windowRef)
        
        if result == .success, windowRef != nil {
            // Note: CoreFoundation type casts always succeed after API success check
            axWindow = (windowRef as! AXUIElement)
            debugPrint("✅ Got focused window")
        } else {
            // Fallback: get first window from all windows
            debugPrint("⚠️ Focused window not available (result: \(result.rawValue)), trying fallback...")
            var windowsRef: CFTypeRef?
            result = AXUIElementCopyAttributeValue(appRef, kAXWindowsAttribute as CFString, &windowsRef)
            
            if result == .success, let windows = windowsRef as? [AXUIElement], !windows.isEmpty {
                axWindow = windows[0]
                debugPrint("✅ Got window via fallback (first of \(windows.count) windows)")
            }
        }
        
        guard let axWindow = axWindow else {
            debugPrint("❌ Failed to get focused window (no fallback available)")
            return
        }
        
        // Get current position and size
        var positionRef: CFTypeRef?
        var sizeRef: CFTypeRef?
        
        let posResult = AXUIElementCopyAttributeValue(axWindow, kAXPositionAttribute as CFString, &positionRef)
        let sizeResult = AXUIElementCopyAttributeValue(axWindow, kAXSizeAttribute as CFString, &sizeRef)
        
        guard posResult == .success, let positionValue = positionRef else {
            debugPrint("❌ Failed to get window position (result: \(posResult.rawValue))")
            return
        }
        
        guard sizeResult == .success, let sizeValue = sizeRef else {
            debugPrint("❌ Failed to get window size (result: \(sizeResult.rawValue))")
            return
        }
        
        var position = CGPoint.zero
        var size = CGSize.zero
        
        guard AXValueGetValue(positionValue as! AXValue, .cgPoint, &position) else {
            debugPrint("❌ Failed to extract position value from AXValue")
            return
        }
        
        guard AXValueGetValue(sizeValue as! AXValue, .cgSize, &size) else {
            debugPrint("❌ Failed to extract size value from AXValue")
            return
        }
        
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
            let setResult = AXUIElementSetAttributeValue(axWindow, kAXPositionAttribute as CFString, positionValue)
            
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
        // System sleep/wake notifications
        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(handleSystemSleep),
            name: NSWorkspace.willSleepNotification,
            object: nil
        )
        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(handleSystemWake),
            name: NSWorkspace.didWakeNotification,
            object: nil
        )
        
        // Display sleep/wake notifications (separate from system sleep)
        // Prevents snapshot corruption when display is off but system is running
        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(handleScreensDidSleep),
            name: NSWorkspace.screensDidSleepNotification,
            object: nil
        )
        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(handleScreensDidWake),
            name: NSWorkspace.screensDidWakeNotification,
            object: nil
        )
    }
    
    /// Handle display configuration change
    @objc private func displayConfigurationChanged() {
        // Skip processing when user not logged in (login screen has phantom display IDs)
        guard isUserLoggedIn() else {
            debugPrint("🖥️ Display change ignored - user not logged in")
            return
        }
        
        let screenCount = NSScreen.screens.count
        debugPrint("🖥️ Display configuration changed")
        debugPrint("Current screen count: \(screenCount)")
        
        // Reset cooldown if screen count increased (display reconnected)
        if screenCount > lastScreenCount {
            lastRestoreTime = nil
            debugPrint("🔄 Screen count increased, cooldown reset")
        }
        lastScreenCount = screenCount
        
        // If monitoring is disabled
        if !isMonitoringEnabled {
            // Keep recording events (this is important!)
            lastDisplayChangeTime = Date()
            
            // Start timer if not already running
            if !timerManager.isStabilizationCheckRunning {
                startStabilizationCheck()
            }
            return
        }
        
        // If monitoring is enabled - cancel fallback and restore
        timerManager.cancelFallback()
        eventOccurredAfterStabilization = true
        triggerRestoration()
    }
    
    /// Start stabilization check timer
    private func startStabilizationCheck() {
        timerManager.startStabilizationCheck { [weak self] in
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
            timerManager.stopStabilizationCheck()
            
            isMonitoringEnabled = true
            eventOccurredAfterStabilization = false
            
            debugPrint("✅ Display stabilized (\(String(format: "%.1f", elapsed))s since last event)")
            debugPrint("▶️ Resuming monitoring after display stabilization")
            debugPrint("⏳ Waiting for next display event (max \(Int(fallbackWaitDelay))s)")
            
            // Setup fallback (after fallbackWaitDelay seconds)
            timerManager.scheduleFallback(delay: fallbackWaitDelay) { [weak self] in
                self?.fallbackRestoration()
            }
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
        // Cooldown check (skip for retries)
        if !isRetry, let lastRestore = lastRestoreTime,
           Date().timeIntervalSince(lastRestore) < restoreCooldown {
            debugPrint("⏳ Restore cooldown active, skipping")
            return
        }
        
        // Cancel existing restore task
        timerManager.cancelRestore()
        
        // Reset retry counter when starting a new restore sequence
        if !isRetry {
            restoreRetryCount = 0
        }
        
        let settings = WindowTimingSettings.shared
        let totalDelay = settings.windowRestoreDelay
        
        debugPrint("Waiting \(String(format: "%.1f", totalDelay))s before restore") 
        
        timerManager.scheduleRestore(delay: totalDelay) { [weak self] in
            guard let self = self else { return }
            
            let restoredCount = self.restoreWindowsIfNeeded()
            
            // Record restore time for cooldown
            self.lastRestoreTime = Date()
            
            // If restore succeeded and 2+ screens
            if restoredCount > 0 && NSScreen.screens.count >= 2 {
                self.restoreRetryCount = 0
                self.schedulePostDisplayConnectionSnapshot()
            } else if NSScreen.screens.count >= 2 && self.restoreRetryCount < self.maxRestoreRetries {
                // If restore failed and retry is available
                self.restoreRetryCount += 1
                debugPrint("🔄 Scheduling restore retry (\(self.restoreRetryCount)/\(self.maxRestoreRetries)): in \(String(format: "%.1f", self.restoreRetryDelay))s") 
                
                // Schedule retry (not using TimerManager - this is business logic specific retry)
                DispatchQueue.main.asyncAfter(deadline: .now() + self.restoreRetryDelay) { [weak self] in
                    self?.triggerRestoration(isRetry: true)
                }
            } else {
                self.restoreRetryCount = 0
                debugPrint("⏭️ Skipping snapshot scheduling (restored: \(restoredCount), screens: \(NSScreen.screens.count))")
            }
        }
    }
    
    /// Pause monitoring (idempotent - safe to call multiple times)
    @objc private func pauseMonitoring() {
        guard isMonitoringEnabled else { return }  // Already paused
        isMonitoringEnabled = false
        lastDisplayChangeTime = nil
        timerManager.stopStabilizationCheck()
        timerManager.cancelFallback()
        eventOccurredAfterStabilization = false
        debugPrint("⏸️ Display monitoring paused")
    }
    
    /// Check if user is logged in (not at login screen)
    /// Returns false when at login screen where display IDs may be phantom
    /// See: https://github.com/zembutsu/Tsubame/issues/66
    private func isUserLoggedIn() -> Bool {
        var uid: uid_t = 0
        guard let userName = SCDynamicStoreCopyConsoleUser(nil, &uid, nil) as String?,
              !userName.isEmpty,
              userName != "loginwindow" else {
            return false
        }
        return true
    }
    
    // MARK: - Sleep/Wake Handlers
    // 
    // Sleep monitoring behavior:
    // - System sleep: Controlled by disableMonitoringDuringSleep setting
    //   (default: true = pause monitoring during sleep)
    // - Display sleep: Always pause monitoring to prevent phantom display ID issues
    //
    // Wake resume behavior:
    // - System wake: Do NOT resume immediately (wait for display stabilization)
    // - Display wake: Resume monitoring, then wait for display configuration events
    
    /// Handle system sleep
    @objc private func handleSystemSleep() {
        debugPrint("💤 System going to sleep")
        // Controlled by user setting (default: true)
        if WindowTimingSettings.shared.disableMonitoringDuringSleep {
            pauseMonitoring()
        }
    }
    
    /// Handle system wake
    @objc private func handleSystemWake() {
        debugPrint("☀️ System woke from sleep")
        // Note: Monitoring resume is handled by display stabilization logic
        // (displayConfigurationChanged → checkStabilization)
        // Do not set isMonitoringEnabled = true here
    }
    
    /// Handle display sleep (separate from system sleep)
    @objc private func handleScreensDidSleep() {
        debugPrint("💤 Display going to sleep")
        // Always pause to prevent snapshot corruption from phantom display IDs
        pauseMonitoring()
    }
    
    /// Handle display wake (separate from system wake)
    @objc private func handleScreensDidWake() {
        debugPrint("☀️ Display woke up")
        isMonitoringEnabled = true
        debugPrint("▶️ Monitoring resumed after display wake")
    }
    
    /// Get display identifier
    private func getDisplayIdentifier(for screen: NSScreen) -> String {
        if let screenNumber = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID {
            return String(screenNumber)
        }
        // Fallback: use screen frame
        return "\(Int(screen.frame.origin.x))_\(Int(screen.frame.origin.y))_\(Int(screen.frame.width))_\(Int(screen.frame.height))"
    }
    
    /// Start periodic monitoring for display memory
    private func startPeriodicSnapshot() {
        let interval = WindowTimingSettings.shared.displayMemoryInterval
        timerManager.startDisplayMemoryTimer(interval: interval) { [weak self] in
            self?.takeWindowSnapshot()
        }
        debugPrint("✅ Periodic monitoring started (\(Int(interval))s interval)")
    }
    
    /// Take snapshot of current window layout (for auto-restore)
    /// Note: Writes to manualSnapshots[0] (Slot 0 = auto-snapshot slot)
    /// This is memory-only update; persistence happens in performAutoSnapshot() every 30min
    private func takeWindowSnapshot() {
        // Skip if monitoring is paused (display sleep, system sleep, etc.)
        guard isMonitoringEnabled else {
            return
        }
        
        // Skip when user not logged in (login screen has phantom display IDs)
        guard isUserLoggedIn() else {
            verbosePrint("📸 Snapshot skipped - user not logged in")
            return
        }
        
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
        
        // Backup external display data temporarily (from Slot 0)
        let mainScreenID = getDisplayIdentifier(for: screens[0])
        var externalDisplayBackup: [String: [String: WindowMatchInfo]] = [:]
        for (displayID, windows) in manualSnapshots[0] {
            if displayID != mainScreenID && !windows.isEmpty {
                externalDisplayBackup[displayID] = windows
            }
        }
        
        // Clear old data and initialize per screen (Slot 0)
        manualSnapshots[0].removeAll()
        for screen in screens {
            let displayID = getDisplayIdentifier(for: screen)
            manualSnapshots[0][displayID] = [:]
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
                    manualSnapshots[0][displayID]?[windowKey] = matchInfo
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
            if manualSnapshots[0][displayID] != nil {
                manualSnapshots[0][displayID] = backupWindows
                verbosePrint("🔄 [Auto] Restoring backup for external display \(displayID): \(backupWindows.count) windows")
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
        let modifierString = HotKeySettings.shared.getModifierString()
        debugPrint("📥 [Manual: \(modifierString)↓] Starting manual snapshot restore (slot \(currentSlotIndex))")
        
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
                            // CoreFoundation type cast always succeeds after API success
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
    private func restoreWindowsIfNeeded(trigger: String = "Auto") -> Int {
        debugPrint("🔄 [\(trigger)] Starting window restore process...")
        
        // Skip when user not logged in (login screen has phantom display IDs)
        let loggedIn = isUserLoggedIn()
        verbosePrint("🔐 Login check: result=\(loggedIn)")
        guard loggedIn else {
            debugPrint("  ⏸️ Skipping restore - user not logged in")
            return 0
        }
        
        let currentScreens = NSScreen.screens
        guard currentScreens.count >= 2 else {
            debugPrint("  Only one screen, skipping restore")
            return 0
        }
        
        let currentScreenIDs = Set(currentScreens.map { getDisplayIdentifier(for: $0) })
        let mainScreen = currentScreens[0]
        let mainScreenID = getDisplayIdentifier(for: mainScreen)
        
        // Check which saved screen IDs are currently connected (from Slot 0)
        let savedScreenIDs = Set(manualSnapshots[0].keys)
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
            guard let savedWindows = manualSnapshots[0][externalScreenID], !savedWindows.isEmpty else {
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
                            // CoreFoundation type cast always succeeds after API success
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
                        verbosePrint("      ⚠️ AXUIElement position match failed - expected: (\(Int(savedFrame.origin.x)), \(Int(savedFrame.origin.y))), actual: (\(Int(currentFrame.origin.x)), \(Int(currentFrame.origin.y)))")
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
    
    /// Setup hotkey settings change observer
    private func setupHotkeySettingsObserver() {
        NotificationCenter.default.addObserver(
            forName: HotKeySettings.modifiersDidChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.reregisterHotkeys()
        }
    }
    
    /// Re-register hotkeys after settings change
    private func reregisterHotkeys() {
        debugPrint("🔑 Hotkey modifiers changed, re-registering...")
        
        // Unregister existing hotkeys
        unregisterHotKeys()
        
        // Register with new modifiers
        let failedHotkeys = registerHotKeys()
        
        // Update menu to reflect new shortcuts
        setupMenu()
        
        // Show warning if any registration failed
        if !failedHotkeys.isEmpty {
            showHotkeyRegistrationWarning(failedHotkeys: failedHotkeys)
        } else {
            debugPrint("🔑 All hotkeys re-registered successfully")
        }
    }
    
    /// Restart display memory timer
    private func restartDisplayMemoryTimer() {
        let interval = WindowTimingSettings.shared.displayMemoryInterval
        timerManager.restartDisplayMemoryTimer(interval: interval) { [weak self] in
            self?.takeWindowSnapshot()
        }
        debugPrint("🔄 Display memory interval changed(\(Int(interval))s interval)")
    }
    
    /// Clear manual snapshots
    private func clearManualSnapshots() {
        manualSnapshots = Array(repeating: [:], count: 6)
        debugPrint("🗑️ In-memory snapshot cleared")
    }
    
    /// Start initial auto-snapshot timer
    private func startInitialSnapshotTimer() {
        let settings = SnapshotSettings.shared
        let delaySeconds = settings.initialDelaySeconds
        
        debugPrint("⏱️ Initial auto-snapshot timer started: \(String(format: "%.1f", delaySeconds/60))min")
        
        timerManager.scheduleInitialCapture(delay: delaySeconds) { [weak self] in
            debugPrint("⏱️ Initial auto-snapshot timer fired")
            self?.performAutoSnapshot(reason: "Initial auto")
            self?.hasInitialSnapshotBeenTaken = true
            
            // Start periodic snapshot if enabled
            let snapshotSettings = SnapshotSettings.shared
            if snapshotSettings.enablePeriodicSnapshot {
                self?.startPeriodicSnapshotTimer()
            }
        }
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
        
        timerManager.startPeriodicCapture(interval: intervalSeconds) { [weak self] in
            debugPrint("⏱️ Periodic snapshot timer fired")
            self?.performAutoSnapshot(reason: "Periodic auto")
        }
    }
    
    /// Restart periodic snapshot timer (on settings change)
    private func restartPeriodicSnapshotTimerIfNeeded() {
        let settings = SnapshotSettings.shared
        
        timerManager.stopPeriodicCapture()
        
        if settings.enablePeriodicSnapshot && hasInitialSnapshotBeenTaken {
            startPeriodicSnapshotTimer()
        } else if !settings.enablePeriodicSnapshot {
            debugPrint("⏱️ Periodic snapshot stopped")
        }
    }
    
    /// Perform auto snapshot
    private func performAutoSnapshot(reason: String) {
        // Skip if monitoring is disabled (e.g., during sleep)
        guard isMonitoringEnabled else {
            debugPrint("📸 \(reason)snapshot skipped (monitoring disabled)")
            return
        }
        
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
        
        // Existing data protection check (for auto slot only)
        let snapshotSettings = SnapshotSettings.shared
        if snapshotSettings.protectExistingSnapshot && ManualSnapshotStorage.shared.hasSnapshot(for: 0) {
            if savedCount < snapshotSettings.minimumWindowCount {
                debugPrint("🛡️ Data protection: window count is\(savedCount) (min:\(snapshotSettings.minimumWindowCount)), skipping overwrite")
                return
            }
        }
        
        // Auto snapshot always saves to Slot 0 (reserved for auto)
        manualSnapshots[0] = snapshot
        
        // Persist
        ManualSnapshotStorage.shared.save(manualSnapshots)
        
        debugPrint("📸 \(reason)snapshot complete: \(savedCount) windows (\(screens.count) screens)")
        
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
        
        timerManager.scheduleInitialCapture(delay: delaySeconds) { [weak self] in
            debugPrint("⏱️ Post-display-connection snapshot timer fired")
            self?.performAutoSnapshot(reason: "Post-display auto")
            self?.hasInitialSnapshotBeenTaken = true
            
            // Start periodic snapshot if enabled and not yet started
            let snapshotSettings = SnapshotSettings.shared
            if snapshotSettings.enablePeriodicSnapshot && !(self?.timerManager.isPeriodicCaptureRunning ?? false) {
                self?.startPeriodicSnapshotTimer()
            }
        }
    }
    
    
    
    func applicationWillTerminate(_ notification: Notification) {
        // Stop all timers first
        timerManager.stopAllTimers()
        
        // Clear snapshot on termination if privacy protection mode is enabled
        if SnapshotSettings.shared.disablePersistence {
            ManualSnapshotStorage.shared.clear()
            debugPrint("🔒 App terminating: Clearing snapshot (privacy mode)")
        }
    }
    
    deinit {
        // Unregister hotkeys
        unregisterHotKeys()
        if let handler = eventHandler {
            RemoveEventHandler(handler)
        }
        // Stop all timers
        timerManager.stopAllTimers()
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
