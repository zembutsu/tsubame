import Cocoa
import Carbon
import SwiftUI
import UserNotifications

// グローバル変数としてAppDelegateの参照を保持
private var globalAppDelegate: AppDelegate?

// Cイベントハンドラー
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
        case 1: // 右矢印(次の画面)
            appDelegate.moveWindowToNextScreen()
        case 2: // 左矢印(前の画面)
            appDelegate.moveWindowToPrevScreen()
        case 3: // 上矢印(スナップショット保存)
            appDelegate.saveManualSnapshot()
        case 4: // 下矢印(スナップショット復元)
            appDelegate.restoreManualSnapshot()
        case 5: // W(ウィンドウを上に移動)
            appDelegate.nudgeWindow(direction: .up)
        case 6: // A(ウィンドウを左に移動)
            appDelegate.nudgeWindow(direction: .left)
        case 7: // S(ウィンドウを下に移動)
            appDelegate.nudgeWindow(direction: .down)
        case 8: // D(ウィンドウを右に移動)
            appDelegate.nudgeWindow(direction: .right)
        default:
            break
        }
    }
    
    return noErr
}

// デバッグログを保存するクラス
class DebugLogger {
    static let shared = DebugLogger()
    private var logs: [String] = []
    private let maxLogs = 1000
    
    // アプリ名マスク用のマッピング
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
        
        // ログが多すぎる場合は古いものを削除
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
    
    /// アプリ名をマスクする(設定に応じて)
    func maskAppName(_ name: String) -> String {
        guard SnapshotSettings.shared.maskAppNamesInLog else {
            return name  // マスクOFFなら元の名前
        }
        if let masked = appNameMapping[name] {
            return masked
        }
        appCounter += 1
        let masked = "App\(appCounter)"
        appNameMapping[name] = masked
        return masked
    }
    
    /// アプリ名マッピングをクリア
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
    var hotKeyRef3: EventHotKeyRef?  // スナップショット保存(↑)
    var hotKeyRef4: EventHotKeyRef?  // スナップショット復元(↓)
    var hotKeyRef5: EventHotKeyRef?  // ウィンドウ微調整(W: 上)
    var hotKeyRef6: EventHotKeyRef?  // ウィンドウ微調整(A: 左)
    var hotKeyRef7: EventHotKeyRef?  // ウィンドウ微調整(S: 下)
    var hotKeyRef8: EventHotKeyRef?  // ウィンドウ微調整(D: 右)
    var eventHandler: EventHandlerRef?
    var settingsWindow: NSWindow?
    var aboutWindow: NSWindow?
    var debugWindow: NSWindow?
    
    // ディスプレイ記憶機能(新形式: WindowMatchInfo使用)
    private var windowPositions: [String: [String: WindowMatchInfo]] = [:]
    private var snapshotTimer: Timer?
    
    // 手動スナップショット機能(5スロット、将来拡張用)
    // 新形式: WindowMatchInfo使用(プライバシー保護のためハッシュ化)
    private var manualSnapshots: [[String: [String: WindowMatchInfo]]] = Array(repeating: [:], count: 5)
    private var currentSlotIndex: Int = 0  // v1.2.3では常に0
    
    // 自動スナップショット機能
    private var initialSnapshotTimer: Timer?
    private var periodicSnapshotTimer: Timer?
    private var hasInitialSnapshotBeenTaken = false
    
    // ディスプレイ変更の落ち着き待ちタイマー
    private var displayStabilizationTimer: Timer?
    
    // 復元処理のワークアイテム(キャンセル可能)
    private var restoreWorkItem: DispatchWorkItem?
    
    // ディスプレイ監視の有効/無効状態
    private var isDisplayMonitoringEnabled = true
    
    // 最後のディスプレイ変更時刻(安定化検知用)
    private var lastDisplayChangeTime: Date?
    
    // 安定化確認タイマー
    private var stabilizationCheckTimer: Timer?
    
    // 安定化後のイベント発生フラグ
    private var eventOccurredAfterStabilization = false
    
    // フォールバックタイマー
    private var fallbackTimer: DispatchWorkItem?
    
    // 復元リトライ機能
    private var restoreRetryCount: Int = 0
    private let maxRestoreRetries: Int = 2
    private let restoreRetryDelay: TimeInterval = 3.0
    
    func applicationDidFinishLaunching(_ notification: Notification) {
        // グローバル参照を設定
        globalAppDelegate = self
        
        // WindowTimingSettingsを初期化してスリープ監視を開始
        _ = WindowTimingSettings.shared
        
        // SnapshotSettingsを初期化
        _ = SnapshotSettings.shared
        
        // 起動時情報をログに出力
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
        
        // 保存済みスナップショットを読み込み
        loadSavedSnapshots()
        
        // 通知権限をリクエスト
        setupNotifications()
        
        // システムバーにアイコンを追加
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        
        if let button = statusItem?.button {
            button.image = NSImage(systemSymbolName: "rectangle.2.swap", accessibilityDescription: "Window Mover")
            button.image?.isTemplate = true
        }
        
        // メニューを設定
        setupMenu()
        
        // グローバルホットキーを登録
        registerHotKeys()
        
        // アクセシビリティ権限をチェック
        checkAccessibilityPermissions()
        
        // ディスプレイ変更の監視を開始
        setupDisplayChangeObserver()
        
        // 監視停止/再開の通知を設定
        setupMonitoringControlObservers()
        
        // スナップショット設定変更の監視を設定
        setupSnapshotSettingsObservers()
        
        // ディスプレイ記憶用の定期監視を開始
        startPeriodicSnapshot()
        
        // 初回自動スナップショットタイマーを開始
        startInitialSnapshotTimer()
        
        // 起動時自動復元(設定が有効 かつ スナップショットが存在する場合)
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
    
    /// 通知センターのセットアップ
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
    
    /// 通知を送信(スナップショット操作用)
    private func sendNotification(title: String, body: String) {
        let settings = SnapshotSettings.shared
        
        // サウンド通知
        if settings.enableSound {
            NSSound(named: NSSound.Name(settings.soundName))?.play()
        }
        
        // システム通知
        guard settings.enableNotification else { return }
        
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = nil  // サウンドは別途制御
        
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
        // イベントハンドラーをインストール
        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let status = InstallEventHandler(GetApplicationEventTarget(), hotKeyHandler, 1, &eventType, nil, &eventHandler)
        
        if status == noErr {
            debugPrint("✅ Event handler installed successfully")
        } else {
            debugPrint("❌ Failed to install event handler: \(status)")
        }
        
        // ホットキーを登録
        let settings = HotKeySettings.shared
        let modifiers = settings.getModifiers()
        
        // 1つ目のホットキー: 次の画面へ (右矢印)
        let hotKeyID1 = EventHotKeyID(signature: OSType(0x4D4F5645), id: 1) // 'MOVE' + 1
        let keyCode1 = UInt32(kVK_RightArrow)
        let registerStatus1 = RegisterEventHotKey(keyCode1, modifiers, hotKeyID1, GetApplicationEventTarget(), 0, &hotKeyRef)
        
        if registerStatus1 == noErr {
            let modifierString = settings.getModifierString()
            debugPrint("✅ Hotkey 1 (\(modifierString)→) registered")
        } else {
            debugPrint("❌ Failed to register hotkey 1: \(registerStatus1)")
        }
        
        // 2つ目のホットキー: 前の画面へ (左矢印)
        let hotKeyID2 = EventHotKeyID(signature: OSType(0x4D4F5645), id: 2) // 'MOVE' + 2
        let keyCode2 = UInt32(kVK_LeftArrow)
        let registerStatus2 = RegisterEventHotKey(keyCode2, modifiers, hotKeyID2, GetApplicationEventTarget(), 0, &hotKeyRef2)
        
        if registerStatus2 == noErr {
            let modifierString = settings.getModifierString()
            debugPrint("✅ Hotkey 2 (\(modifierString)←) registered")
        } else {
            debugPrint("❌ Failed to register hotkey 2: \(registerStatus2)")
        }
        
        // 3つ目のホットキー: スナップショット保存 (上矢印)
        let hotKeyID3 = EventHotKeyID(signature: OSType(0x4D4F5645), id: 3) // 'MOVE' + 3
        let keyCode3 = UInt32(kVK_UpArrow)
        let registerStatus3 = RegisterEventHotKey(keyCode3, modifiers, hotKeyID3, GetApplicationEventTarget(), 0, &hotKeyRef3)
        
        if registerStatus3 == noErr {
            let modifierString = settings.getModifierString()
            debugPrint("✅ Hotkey 3 (\(modifierString)↑) registered")
        } else {
            debugPrint("❌ Failed to register hotkey 3: \(registerStatus3)")
        }
        
        // 4つ目のホットキー: スナップショット復元 (下矢印)
        let hotKeyID4 = EventHotKeyID(signature: OSType(0x4D4F5645), id: 4) // 'MOVE' + 4
        let keyCode4 = UInt32(kVK_DownArrow)
        let registerStatus4 = RegisterEventHotKey(keyCode4, modifiers, hotKeyID4, GetApplicationEventTarget(), 0, &hotKeyRef4)
        
        if registerStatus4 == noErr {
            let modifierString = settings.getModifierString()
            debugPrint("✅ Hotkey 4 (\(modifierString)↓) registered")
        } else {
            debugPrint("❌ Failed to register hotkey 4: \(registerStatus4)")
        }
        
        // 5つ目のホットキー: ウィンドウ微調整・上 (W)
        let hotKeyID5 = EventHotKeyID(signature: OSType(0x4D4F5645), id: 5) // 'MOVE' + 5
        let keyCode5 = UInt32(kVK_ANSI_W)
        let registerStatus5 = RegisterEventHotKey(keyCode5, modifiers, hotKeyID5, GetApplicationEventTarget(), 0, &hotKeyRef5)
        
        if registerStatus5 == noErr {
            let modifierString = settings.getModifierString()
            debugPrint("✅ Hotkey 5 (\(modifierString)W) registered")
        } else {
            debugPrint("❌ Failed to register hotkey 5: \(registerStatus5)")
        }
        
        // 6つ目のホットキー: ウィンドウ微調整・左 (A)
        let hotKeyID6 = EventHotKeyID(signature: OSType(0x4D4F5645), id: 6) // 'MOVE' + 6
        let keyCode6 = UInt32(kVK_ANSI_A)
        let registerStatus6 = RegisterEventHotKey(keyCode6, modifiers, hotKeyID6, GetApplicationEventTarget(), 0, &hotKeyRef6)
        
        if registerStatus6 == noErr {
            let modifierString = settings.getModifierString()
            debugPrint("✅ Hotkey 6 (\(modifierString)A) registered")
        } else {
            debugPrint("❌ Failed to register hotkey 6: \(registerStatus6)")
        }
        
        // 7つ目のホットキー: ウィンドウ微調整・下 (S)
        let hotKeyID7 = EventHotKeyID(signature: OSType(0x4D4F5645), id: 7) // 'MOVE' + 7
        let keyCode7 = UInt32(kVK_ANSI_S)
        let registerStatus7 = RegisterEventHotKey(keyCode7, modifiers, hotKeyID7, GetApplicationEventTarget(), 0, &hotKeyRef7)
        
        if registerStatus7 == noErr {
            let modifierString = settings.getModifierString()
            debugPrint("✅ Hotkey 7 (\(modifierString)S) registered")
        } else {
            debugPrint("❌ Failed to register hotkey 7: \(registerStatus7)")
        }
        
        // 8つ目のホットキー: ウィンドウ微調整・右 (D)
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
        
        // 新しい位置を計算
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
        
        // 現在の画面を特定
        var currentScreenIndex = 0
        for (index, screen) in screens.enumerated() {
            let screenFrame = screen.frame
            if screenFrame.contains(position) {
                currentScreenIndex = index
                break
            }
        }
        
        debugPrint("Current screen index: \(currentScreenIndex)")
        
        // 次/前の画面のインデックスを計算
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
        
        // ウィンドウの相対位置を維持して移動
        let relativeX = position.x - currentScreen.frame.origin.x
        let relativeY = position.y - currentScreen.frame.origin.y
        
        let newX = nextScreen.frame.origin.x + relativeX
        let newY = nextScreen.frame.origin.y + relativeY
        var newPosition = CGPoint(x: newX, y: newY)
        
        debugPrint("New position: \(newPosition)")
        
        // ウィンドウを移動
        if let positionValue = AXValueCreate(.cgPoint, &newPosition) {
            let setResult = AXUIElementSetAttributeValue(window as! AXUIElement, kAXPositionAttribute as CFString, positionValue)
            
            if setResult == .success {
                debugPrint("✅ Window moved successfully")
            } else {
                debugPrint("❌ Failed to move window: \(setResult.rawValue)")
            }
        }
    }
    
    /// ディスプレイ変更の監視を設定
    private func setupDisplayChangeObserver() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(displayConfigurationChanged),
            name: NSApplication.didChangeScreenParametersNotification,
            object: nil
        )
        debugPrint("✅ Display change monitoring started")
    }
    
    /// 監視停止/再開の通知を設定
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
    
    /// ディスプレイ構成が変更されたときの処理
    @objc private func displayConfigurationChanged() {
        let screenCount = NSScreen.screens.count
        debugPrint("🖥️ Display configuration changed")
        debugPrint("Current screen count: \(screenCount)")
        
        // 監視が無効化されている場合
        if !isDisplayMonitoringEnabled {
            // イベントを記録し続ける(これが重要！)
            lastDisplayChangeTime = Date()
            
            // タイマーがまだ動いていなければ開始
            if stabilizationCheckTimer == nil {
                startStabilizationCheck()
            }
            return
        }
        
        // 監視が有効な場合 - フォールバックをキャンセルして復元
        fallbackTimer?.cancel()
        eventOccurredAfterStabilization = true
        triggerRestoration()
    }
    
    /// 安定化確認タイマーを開始
    private func startStabilizationCheck() {
        stabilizationCheckTimer?.invalidate()
        
        // 0.5秒ごとに安定化をチェック
        stabilizationCheckTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            self?.checkStabilization()
        }
    }
    
    /// 安定化を確認
    private func checkStabilization() {
        guard let lastChange = lastDisplayChangeTime else { return }
        
        // 最後のイベントからの経過時間を計算
        let elapsed = Date().timeIntervalSince(lastChange)
        let stabilizationDelay = WindowTimingSettings.shared.displayStabilizationDelay
        
        if elapsed >= stabilizationDelay {
            // 真の安定化を達成
            stabilizationCheckTimer?.invalidate()
            stabilizationCheckTimer = nil
            
            isDisplayMonitoringEnabled = true
            eventOccurredAfterStabilization = false
            
            debugPrint("✅ Display stabilized (\(String(format: "%.1f", elapsed))s since last event)")
            debugPrint("▶️ Resuming monitoring after display stabilization")
            debugPrint("⏳ Waiting for next display event (max 3s)")
            
            // フォールバック設定(3秒後)
            let fallback = DispatchWorkItem { [weak self] in
                self?.fallbackRestoration()
            }
            fallbackTimer = fallback
            DispatchQueue.main.asyncAfter(deadline: .now() + 3.0, execute: fallback)
        }
    }
    
    /// フォールバック復元
    private func fallbackRestoration() {
        if !eventOccurredAfterStabilization {
            // イベントが来なかった → 手動トリガー
            debugPrint("⚠️ No display event occurred, triggering restore manually")
            triggerRestoration()
        } else {
            // イベントが来た → スキップ
            debugPrint("✅ Display event occurred, skipping fallback")
        }
    }
    
    /// 復元処理をトリガー
    private func triggerRestoration(isRetry: Bool = false) {
        // 既存のタイマーをキャンセル
        restoreWorkItem?.cancel()
        
        // 新しいリストアシーケンスの開始時はリトライカウンターをリセット
        if !isRetry {
            restoreRetryCount = 0
        }
        
        let settings = WindowTimingSettings.shared
        let totalDelay = settings.windowRestoreDelay
        
        debugPrint("Waiting \(String(format: "%.1f", totalDelay))s before restore") 
        
        let workItem = DispatchWorkItem { [weak self] in
            guard let self = self else { return }
            
            let restoredCount = self.restoreWindowsIfNeeded()
            
            // 復元成功かつ2画面以上の場合
            if restoredCount > 0 && NSScreen.screens.count >= 2 {
                self.restoreRetryCount = 0
                self.schedulePostDisplayConnectionSnapshot()
            } else if NSScreen.screens.count >= 2 && self.restoreRetryCount < self.maxRestoreRetries {
                // 復元失敗でリトライ可能な場合
                self.restoreRetryCount += 1
                debugPrint("🔄 Scheduling restore retry (\(self.restoreRetryCount)/\(self.maxRestoreRetries)): in \(String(format: "%.1f", self.restoreRetryDelay))s") 
                
                // リトライをスケジュール
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
    
    /// 監視を一時停止
    @objc private func pauseMonitoring() {
        isDisplayMonitoringEnabled = false
        lastDisplayChangeTime = nil
        stabilizationCheckTimer?.invalidate()
        stabilizationCheckTimer = nil
        fallbackTimer?.cancel()
        eventOccurredAfterStabilization = false
        debugPrint("⏸️ Display monitoring paused")
    }
    
    /// 監視を再開
    @objc private func resumeMonitoring() {
        debugPrint("⏱️ Waiting for display stabilization...")
    }
    
    /// ディスプレイ識別子を取得
    private func getDisplayIdentifier(for screen: NSScreen) -> String {
        if let screenNumber = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID {
            return String(screenNumber)
        }
        // フォールバック: 画面のフレームを使用
        return "\(Int(screen.frame.origin.x))_\(Int(screen.frame.origin.y))_\(Int(screen.frame.width))_\(Int(screen.frame.height))"
    }
    
    /// ウィンドウ識別子を作成
    private func getWindowIdentifier(appName: String, windowID: CGWindowID) -> String {
        return "\(appName)_\(windowID)"
    }
    
    /// ディスプレイ記憶用の定期監視を開始
    private func startPeriodicSnapshot() {
        let interval = WindowTimingSettings.shared.displayMemoryInterval
        snapshotTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            self?.takeWindowSnapshot()
        }
        debugPrint("✅ Periodic monitoring started (\(Int(interval))s interval)")
    }
    
    /// 現在のウィンドウ配置のスナップショットを取得(自動復元用)
    private func takeWindowSnapshot() {
        let screens = NSScreen.screens
        
        // ディスプレイ数の確認 - 2画面以上の時のみスナップショットを更新
        // 1画面の時は既存データを保持(外部ディスプレイ切断時にデータを失わないため)
        guard screens.count >= 2 else {
            return
        }
        
        let options = CGWindowListOption(arrayLiteral: .excludeDesktopElements, .optionOnScreenOnly)
        guard let windowList = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] else {
            return
        }
        
        // 外部ディスプレイのデータを一時保存(バックアップ)
        let mainScreenID = getDisplayIdentifier(for: screens[0])
        var externalDisplayBackup: [String: [String: WindowMatchInfo]] = [:]
        for (displayID, windows) in windowPositions {
            if displayID != mainScreenID && !windows.isEmpty {
                externalDisplayBackup[displayID] = windows
            }
        }
        
        // 古いデータをクリアして画面ごとに初期化
        windowPositions.removeAll()
        for screen in screens {
            let displayID = getDisplayIdentifier(for: screen)
            windowPositions[displayID] = [:]
        }
        
        // 全ウィンドウを記録(WindowMatchInfo形式)
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
            
            // ウィンドウタイトルを取得(存在しない場合はnil)
            let windowTitle = window[kCGWindowName as String] as? String
            
            // WindowMatchInfoを生成(ハッシュ化)
            let matchInfo = WindowMatchInfo(
                appName: ownerName,
                title: windowTitle,
                size: frame.size,
                frame: frame
            )
            
            // ユニークキー(ハッシュベース + CGWindowID)
            let windowKey = "\(matchInfo.appNameHash)_\(cgWindowID)"
            
            // このウィンドウがどの画面にあるか判定
            for screen in screens {
                if screen.frame.intersects(frame) {
                    let displayID = getDisplayIdentifier(for: screen)
                    windowPositions[displayID]?[windowKey] = matchInfo
                    windowCountPerDisplay[displayID, default: 0] += 1
                    break
                }
            }
        }
        
        // 外部ディスプレイのウィンドウが0の場合、バックアップから復元
        for (displayID, backupWindows) in externalDisplayBackup {
            if let currentCount = windowCountPerDisplay[displayID], currentCount > 0 {
                // 現在のデータがあればそのまま使用
                continue
            }
            // 現在のデータがなければバックアップから復元
            if windowPositions[displayID] != nil {
                windowPositions[displayID] = backupWindows
                verbosePrint("🔄 Restoring backup for external display \(displayID): \(backupWindows.count) windows")
            }
        }
    }
    
    /// 手動スナップショットを保存
    @objc func saveManualSnapshot() {
        debugPrint("📸 Starting manual snapshot save (slot \(currentSlotIndex))")
        
        let options = CGWindowListOption(arrayLiteral: .excludeDesktopElements, .optionOnScreenOnly)
        guard let windowList = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] else {
            debugPrint("  ❌ Failed to get window list")
            return
        }
        
        let screens = NSScreen.screens
        var snapshot: [String: [String: WindowMatchInfo]] = [:]
        
        // 画面ごとに初期化
        for screen in screens {
            let displayID = getDisplayIdentifier(for: screen)
            snapshot[displayID] = [:]
        }
        
        var savedCount = 0
        
        // 全ウィンドウを記録
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
            
            // ウィンドウタイトルを取得(存在しない場合はnil)
            let windowTitle = window[kCGWindowName as String] as? String
            
            // WindowMatchInfoを生成(ハッシュ化)
            let matchInfo = WindowMatchInfo(
                appName: ownerName,
                title: windowTitle,
                size: frame.size,
                frame: frame
            )
            
            // ユニークキー(ハッシュベース)を生成
            let windowKey = "\(matchInfo.appNameHash)_\(cgWindowID)"
            
            // このウィンドウがどの画面にあるか判定
            for screen in screens {
                if screen.frame.intersects(frame) {
                    let displayID = getDisplayIdentifier(for: screen)
                    snapshot[displayID]?[windowKey] = matchInfo
                    savedCount += 1
                    // タイトル情報を含めてログ出力(詳細モード)
                    let titleInfo = windowTitle != nil ? "title:✓" : "title:✗"
                    let sizeInfo = "\(Int(frame.width))x\(Int(frame.height))"
                    verbosePrint("  Saved: \(DebugLogger.shared.maskAppName(ownerName)) @ (\(Int(frame.origin.x)), \(Int(frame.origin.y))) [\(sizeInfo)] [\(titleInfo)]")
                    break
                }
            }
        }
        
        manualSnapshots[currentSlotIndex] = snapshot
        
        // 永続化
        ManualSnapshotStorage.shared.save(manualSnapshots)
        
        debugPrint("📸 Snapshot saved: \(savedCount) windows")
        
        // 通知
        sendNotification(
            title: "スナップショット保存",
            body: "\(savedCount) windows位置を保存しました"
        )
        
        // メニューを更新
        setupMenu()
    }
    
    /// 手動スナップショットを復元
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
                
                // windowKeyからCGWindowIDを抽出(形式: appNameHash_CGWindowID)
                let components = windowKey.split(separator: "_")
                let savedCGWindowID: CGWindowID? = components.count >= 2 ? CGWindowID(components.last!) : nil
                
                // マッチング: 優先順位順に試行(CGWindowID優先)
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
                
                // 位置が変わっていない場合はスキップ
                if abs(currentFrame.origin.x - savedFrame.origin.x) < 5 &&
                   abs(currentFrame.origin.y - savedFrame.origin.y) < 5 {
                    continue
                }
                
                // Accessibility APIでウィンドウを移動
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
                                // 現在の位置が現在のウィンドウ位置と一致するか確認
                                if abs(currentPoint.x - currentFrame.origin.x) < 10 &&
                                   abs(currentPoint.y - currentFrame.origin.y) < 10 {
                                    // 保存された座標に移動
                                    var position = CGPoint(x: savedFrame.origin.x, y: savedFrame.origin.y)
                                    if let positionValue = AXValueCreate(.cgPoint, &position) {
                                        let posResult = AXUIElementSetAttributeValue(axWindow, kAXPositionAttribute as CFString, positionValue)
                                        
                                        // サイズも復元
                                        var size = CGSize(width: savedFrame.width, height: savedFrame.height)
                                        var sizeRestored = false
                                        if let sizeValue = AXValueCreate(.cgSize, &size) {
                                            let sizeResult = AXUIElementSetAttributeValue(axWindow, kAXSizeAttribute as CFString, sizeValue)
                                            sizeRestored = (sizeResult == .success)
                                        }
                                        
                                        if posResult == .success {
                                            restoredCount += 1
                                            let sizeInfo = sizeRestored ? "+サイズ" : ""
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
        
        // 通知
        if restoredCount > 0 {
            sendNotification(
                title: "スナップショット復元",
                body: "\(restoredCount) windows位置を復元しました"
            )
        } else {
            sendNotification(
                title: "スナップショット復元",
                body: "復元対象のウィンドウがありませんでした"
            )
        }
    }
    
    /// フォールバックマッチングでウィンドウを探す
    /// 優先順位: 1. CGWindowID完全一致  2. appNameHash + titleHash  3. appNameHash + サイズ近似  4. appNameHash単体
    private func findMatchingWindow(
        for savedInfo: WindowMatchInfo,
        in windowList: [[String: Any]],
        excluding usedIDs: Set<CGWindowID>,
        preferredCGWindowID: CGWindowID? = nil
    ) -> (frame: CGRect, pid: Int32, appName: String, windowID: CGWindowID)? {
        
        var titleMatches: [(CGRect, Int32, String, CGWindowID, String)] = []  // 5番目はタイトル(デバッグ用)
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
            
            // 既に使用済みのウィンドウはスキップ
            if usedIDs.contains(cgWindowID) {
                continue
            }
            
            let currentFrame = CGRect(
                x: boundsDict["X"] ?? 0,
                y: boundsDict["Y"] ?? 0,
                width: boundsDict["Width"] ?? 0,
                height: boundsDict["Height"] ?? 0
            )
            
            // appNameHashを先に計算(CGWindowIDマッチでも使用)
            let currentAppNameHash = WindowMatchInfo.hash(ownerName)
            
            // CGWindowID完全一致(最優先 - セッション中は確実にマッチ)
            // appNameHashも確認して異なるアプリのウィンドウを誤マッチしないようにする
            if let preferredID = preferredCGWindowID, cgWindowID == preferredID {
                if currentAppNameHash == savedInfo.appNameHash {
                    verbosePrint("    🆔 CGWindowID exact match: \(cgWindowID)")
                    return (currentFrame, ownerPID, ownerName, cgWindowID)
                }
            }
            
            // appNameHashをチェック(フォールバックマッチング用)
            guard currentAppNameHash == savedInfo.appNameHash else {
                continue
            }
            
            let matchData = (currentFrame, ownerPID, ownerName, cgWindowID)
            let currentTitle = window[kCGWindowName as String] as? String
            
            // titleHashでマッチ
            if let savedTitleHash = savedInfo.titleHash,
               let title = currentTitle {
                let currentTitleHash = WindowMatchInfo.hash(title)
                if currentTitleHash == savedTitleHash {
                    titleMatches.append((currentFrame, ownerPID, ownerName, cgWindowID, title))
                    continue
                }
            }
            
            // サイズでマッチ
            if savedInfo.sizeMatches(currentFrame.size) {
                sizeMatches.append(matchData)
                continue
            }
            
            // appName単体マッチ(最後のフォールバック)
            appOnlyMatches.append(matchData)
        }
        
        // 位置近接でソート(保存時の位置に最も近いウィンドウを優先)
        let savedOrigin = savedInfo.frame.origin
        
        func distanceToSaved(_ frame: CGRect) -> CGFloat {
            let dx = frame.origin.x - savedOrigin.x
            let dy = frame.origin.y - savedOrigin.y
            return sqrt(dx * dx + dy * dy)
        }
        
        // サイズマッチ候補を位置でソート
        if sizeMatches.count > 1 {
            sizeMatches.sort { distanceToSaved($0.0) < distanceToSaved($1.0) }
        }
        
        // appOnlyマッチ候補も位置でソート
        if appOnlyMatches.count > 1 {
            appOnlyMatches.sort { distanceToSaved($0.0) < distanceToSaved($1.0) }
        }
        
        // 優先順位順に返す(詳細ログ付き)
        if let match = titleMatches.first {
            let shortTitle = String(match.4.prefix(30))
            verbosePrint("    🎯 Title match: \"\(shortTitle)...\" (candidates:\(titleMatches.count))")
            return (match.0, match.1, match.2, match.3)
        }
        if let match = sizeMatches.first {
            let savedSize = "\(Int(savedInfo.size.width))x\(Int(savedInfo.size.height))"
            let titleStatus = savedHasTitle ? "保存時title:✓" : "保存時title:✗"
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
    
    /// ウィンドウを復元し、復元したウィンドウ数を返す
    @discardableResult // 関数の戻り値がなくても警告を出さない
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
        
        // 保存されている画面IDのうち、現在接続されているものを確認
        let savedScreenIDs = Set(windowPositions.keys)
        let externalScreenIDs = savedScreenIDs.intersection(currentScreenIDs).subtracting([mainScreenID])
        
        if externalScreenIDs.isEmpty {
            debugPrint("  No external display to restore")
            return 0
        }
        
        debugPrint("  Target displays: \(externalScreenIDs.joined(separator: ", "))")
        
        // 現在の全ウィンドウを取得
        let options = CGWindowListOption(arrayLiteral: .excludeDesktopElements, .optionOnScreenOnly)
        guard let windowList = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] else {
            debugPrint("  ❌ Failed to get window list")
            return 0
        }
        
        // デバッグ: 現在のウィンドウリストを表示
        verbosePrint("  Current windows:")
        for window in windowList {
            if let ownerName = window[kCGWindowOwnerName as String] as? String,
               let cgWindowID = window[kCGWindowNumber as String] as? CGWindowID,
               let layer = window[kCGWindowLayer as String] as? Int, layer == 0 {
                verbosePrint("    Current: \(DebugLogger.shared.maskAppName(ownerName)) (ID:\(cgWindowID))")
            }
        }
        
        var restoredCount = 0
        var usedWindowIDs = Set<CGWindowID>()  // 既にマッチしたウィンドウを追跡
        
        // 各外部ディスプレイについて処理
        for externalScreenID in externalScreenIDs {
            guard let savedWindows = windowPositions[externalScreenID], !savedWindows.isEmpty else {
                continue
            }
            
            verbosePrint("  📍 Screen \(externalScreenID) : \(savedWindows.count) saved windows")
            
            // 保存されたウィンドウを復元
            for (windowKey, savedInfo) in savedWindows {
                let targetPos = "(\(Int(savedInfo.frame.origin.x)), \(Int(savedInfo.frame.origin.y)))"
                verbosePrint("    → Target: \(targetPos)")
                
                // windowKeyからCGWindowIDを抽出(形式: appNameHash_CGWindowID)
                let components = windowKey.split(separator: "_")
                let savedCGWindowID: CGWindowID? = components.count >= 2 ? CGWindowID(components.last!) : nil
                
                // findMatchingWindow()でマッチングを行う(CGWindowID優先)
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
                
                // CGWindowIDで完全一致した場合は、位置に関係なく使用済みにマーク
                // (同じウィンドウが他のエントリで再度マッチするのを防ぐ)
                let isCGWindowIDMatch = savedCGWindowID != nil && savedCGWindowID == cgWindowID
                if isCGWindowIDMatch {
                    usedWindowIDs.insert(cgWindowID)
                }
                
                // メイン画面にあるウィンドウのみを復元対象とする
                let isOnMainScreen = currentFrame.origin.x >= mainScreen.frame.origin.x &&
                                    currentFrame.origin.x < (mainScreen.frame.origin.x + mainScreen.frame.width)
                
                if !isOnMainScreen {
                    // 既に外部ディスプレイにある場合は正常なのでログレベルを変更
                    if isCGWindowIDMatch {
                        verbosePrint("      ✓ Already on external display - X: \(Int(currentFrame.origin.x))")
                    } else {
                        verbosePrint("      ⚠️ Not on main screen (skip) - X: \(Int(currentFrame.origin.x))")
                    }
                    continue
                }
                
                verbosePrint("      ✓ On main screen - X: \(Int(currentFrame.origin.x))")
                
                // サイズ/タイトルマッチの場合はここで使用済みに追加
                if !isCGWindowIDMatch {
                    usedWindowIDs.insert(cgWindowID)
                }
                
                let savedFrame = savedInfo.frame
                
                // Accessibility APIでウィンドウを移動
                let appRef = AXUIElementCreateApplication(ownerPID)
                var windowListRef: CFTypeRef?
                let result = AXUIElementCopyAttributeValue(appRef, kAXWindowsAttribute as CFString, &windowListRef)
                
                if result == .success, let windows = windowListRef as? [AXUIElement] {
                    // 全ウィンドウから該当するものを探す
                    var matchFound = false
                    for axWindow in windows {
                        var currentPosRef: CFTypeRef?
                        if AXUIElementCopyAttributeValue(axWindow, kAXPositionAttribute as CFString, &currentPosRef) == .success,
                           let currentPosValue = currentPosRef {
                            var currentPoint = CGPoint.zero
                            if AXValueGetValue(currentPosValue as! AXValue, .cgPoint, &currentPoint) {
                                // 現在の位置が現在のウィンドウ位置と一致するか確認
                                if abs(currentPoint.x - currentFrame.origin.x) < 50 &&
                                   abs(currentPoint.y - currentFrame.origin.y) < 50 {
                                    // 保存された座標に移動
                                    var position = CGPoint(x: savedFrame.origin.x, y: savedFrame.origin.y)
                                    if let positionValue = AXValueCreate(.cgPoint, &position) {
                                        let posResult = AXUIElementSetAttributeValue(axWindow, kAXPositionAttribute as CFString, positionValue)
                                        
                                        // サイズも復元
                                        var size = CGSize(width: savedFrame.width, height: savedFrame.height)
                                        var sizeRestored = false
                                        if let sizeValue = AXValueCreate(.cgSize, &size) {
                                            let sizeResult = AXUIElementSetAttributeValue(axWindow, kAXSizeAttribute as CFString, sizeValue)
                                            sizeRestored = (sizeResult == .success)
                                        }
                                        
                                        if posResult == .success {
                                            restoredCount += 1
                                            let sizeInfo = sizeRestored ? "+サイズ" : ""
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
    
    // MARK: - 自動スナップショット機能
    
    /// 保存済みスナップショットを読み込み
    private func loadSavedSnapshots() {
        if let savedSnapshots = ManualSnapshotStorage.shared.load() {
            // スロット数を確認して調整
            for (index, snapshot) in savedSnapshots.enumerated() {
                if index < manualSnapshots.count {
                    manualSnapshots[index] = snapshot
                }
            }
            
            // 保存されているウィンドウ数をカウント
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
    
    /// スナップショット設定変更の監視を設定
    private func setupSnapshotSettingsObservers() {
        // 設定変更の通知を監視
        NotificationCenter.default.addObserver(
            forName: Notification.Name("SnapshotSettingsChanged"),
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.restartPeriodicSnapshotTimerIfNeeded()
        }
        
        // スナップショットクリアの通知を監視
        NotificationCenter.default.addObserver(
            forName: Notification.Name("ClearManualSnapshot"),
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.clearManualSnapshots()
        }
        
        // ディスプレイ記憶用監視間隔変更の通知を監視
        NotificationCenter.default.addObserver(
            forName: Notification.Name("DisplayMemoryIntervalChanged"),
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.restartDisplayMemoryTimer()
        }
    }
    
    /// ディスプレイ記憶用タイマーを再起動
    private func restartDisplayMemoryTimer() {
        snapshotTimer?.invalidate()
        let interval = WindowTimingSettings.shared.displayMemoryInterval
        snapshotTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            self?.takeWindowSnapshot()
        }
        debugPrint("🔄 Display memory interval changed(\(Int(interval))s interval)")
    }
    
    /// 手動スナップショットをクリア
    private func clearManualSnapshots() {
        manualSnapshots = Array(repeating: [:], count: 5)
        debugPrint("🗑️ In-memory snapshot cleared")
    }
    
    /// 初回自動スナップショットタイマーを開始
    private func startInitialSnapshotTimer() {
        let settings = SnapshotSettings.shared
        let delaySeconds = settings.initialDelaySeconds
        
        debugPrint("⏱️ Initial auto-snapshot timer started: \(String(format: "%.1f", delaySeconds/60))min")
        
        // 既存のタイマーをキャンセル
        initialSnapshotTimer?.invalidate()
        initialSnapshotTimer = nil
        
        // Timer を .common モードで RunLoop に追加(UI操作中も動作)
        let timer = Timer(timeInterval: delaySeconds, repeats: false) { [weak self] _ in
            debugPrint("⏱️ Initial auto-snapshot timer fired")
            self?.performAutoSnapshot(reason: "初回自動")
            self?.hasInitialSnapshotBeenTaken = true
            
            // 定期スナップショットが有効なら開始
            let snapshotSettings = SnapshotSettings.shared
            if snapshotSettings.enablePeriodicSnapshot {
                self?.startPeriodicSnapshotTimer()
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        initialSnapshotTimer = timer
    }
    
    /// 定期スナップショットタイマーを開始
    private func startPeriodicSnapshotTimer() {
        let settings = SnapshotSettings.shared
        
        guard settings.enablePeriodicSnapshot else {
            debugPrint("⏱️ Periodic snapshot is disabled")
            return
        }
        
        let intervalSeconds = settings.periodicIntervalSeconds
        
        debugPrint("⏱️ Periodic snapshot timer started: \(String(format: "%.0f", intervalSeconds/60))min interval")
        
        // 既存のタイマーをキャンセル
        periodicSnapshotTimer?.invalidate()
        periodicSnapshotTimer = nil
        
        // Timer を .common モードで RunLoop に追加(UI操作中も動作)
        let timer = Timer(timeInterval: intervalSeconds, repeats: true) { [weak self] _ in
            debugPrint("⏱️ Periodic snapshot timer fired")
            self?.performAutoSnapshot(reason: "定期自動")
        }
        RunLoop.main.add(timer, forMode: .common)
        periodicSnapshotTimer = timer
    }
    
    /// 定期スナップショットタイマーを再設定(設定変更時)
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
    
    /// 自動スナップショットを実行
    private func performAutoSnapshot(reason: String) {
        debugPrint("📸 \(reason)snapshot in progress...")
        
        // ディスプレイ数の確認
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
        
        // 画面ごとに初期化
        for screen in screens {
            let displayID = getDisplayIdentifier(for: screen)
            snapshot[displayID] = [:]
        }
        
        var savedCount = 0
        
        // 全ウィンドウを記録
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
            
            // ウィンドウタイトルを取得(存在しない場合はnil)
            let windowTitle = window[kCGWindowName as String] as? String
            
            // WindowMatchInfoを生成(ハッシュ化)
            let matchInfo = WindowMatchInfo(
                appName: ownerName,
                title: windowTitle,
                size: frame.size,
                frame: frame
            )
            
            // ユニークキー(ハッシュベース)を生成
            let windowKey = "\(matchInfo.appNameHash)_\(cgWindowID)"
            
            // このウィンドウがどの画面にあるか判定
            for screen in screens {
                if screen.frame.intersects(frame) {
                    let displayID = getDisplayIdentifier(for: screen)
                    snapshot[displayID]?[windowKey] = matchInfo
                    savedCount += 1
                    break
                }
            }
        }
        
        // 既存データ保護チェック
        let snapshotSettings = SnapshotSettings.shared
        if snapshotSettings.protectExistingSnapshot && ManualSnapshotStorage.shared.hasSnapshot {
            if savedCount < snapshotSettings.minimumWindowCount {
                debugPrint("🛡️ Data protection: window count is\(savedCount) (min:\(snapshotSettings.minimumWindowCount)), skipping overwrite")
                return
            }
        }
        
        manualSnapshots[currentSlotIndex] = snapshot
        
        // 永続化
        ManualSnapshotStorage.shared.save(manualSnapshots)
        
        debugPrint("📸 \(reason)snapshot complete: \(savedCount) windows")
        
        // 通知(自動スナップショットはサウンドのみ、システム通知は送らない)
        if SnapshotSettings.shared.enableSound {
            NSSound(named: NSSound.Name(SnapshotSettings.shared.soundName))?.play()
        }
        
        // メニューを更新
        DispatchQueue.main.async { [weak self] in
            self?.setupMenu()
        }
    }
    
    /// 外部ディスプレイ認識安定後のスナップショットタイマーを開始
    func schedulePostDisplayConnectionSnapshot() {
        let settings = SnapshotSettings.shared
        let delaySeconds = settings.initialDelaySeconds
        
        debugPrint("⏱️ Post-display-connection snapshot: \(String(format: "%.1f", delaySeconds/60))min scheduled")
        
        // 既存の初回タイマーをキャンセルして新しく設定
        initialSnapshotTimer?.invalidate()
        initialSnapshotTimer = nil
        
        // Timer を .common モードで RunLoop に追加(UI操作中も動作)
        let timer = Timer(timeInterval: delaySeconds, repeats: false) { [weak self] _ in
            debugPrint("⏱️ Post-display-connection snapshot timer fired")
            self?.performAutoSnapshot(reason: "ディスプレイ認識後自動")
            self?.hasInitialSnapshotBeenTaken = true
            
            // 定期スナップショットが有効で、まだ開始していなければ開始
            let snapshotSettings = SnapshotSettings.shared
            if snapshotSettings.enablePeriodicSnapshot && self?.periodicSnapshotTimer == nil {
                self?.startPeriodicSnapshotTimer()
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        initialSnapshotTimer = timer
    }
    
    
    
    func applicationWillTerminate(_ notification: Notification) {
        // プライバシー保護モードの場合、終了時にスナップショットをクリア
        if SnapshotSettings.shared.disablePersistence {
            ManualSnapshotStorage.shared.clear()
            debugPrint("🔒 App terminating: Clearing snapshot (privacy mode)")
        }
    }
    
    deinit {
        // ホットキーの登録解除
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
        // タイマーの停止
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

// 詳細ログ用(設定で有効時のみ出力)
func verbosePrint(_ message: String) {
    guard SnapshotSettings.shared.verboseLogging else { return }
    print(message)
    DebugLogger.shared.addLog(message)
}
