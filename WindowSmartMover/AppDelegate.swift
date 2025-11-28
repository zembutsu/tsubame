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
    
    print("🔥 ホットキーが押されました: ID = \(hotKeyID.id)")
    
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
    
    func addLog(_ message: String) {
        let timestamp = DateFormatter.localizedString(from: Date(), dateStyle: .none, timeStyle: .medium)
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
}

// デバッグログ表示用のSwiftUIビュー
struct DebugLogView: View {
    @State private var logs: String
    @Environment(\.dismiss) private var dismiss
    
    init() {
        _logs = State(initialValue: DebugLogger.shared.getAllLogs())
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // ヘッダー
            HStack {
                Text("デバッグログ")
                    .font(.headline)
                Spacer()
                Button("クリア") {
                    DebugLogger.shared.clearLogs()
                    logs = DebugLogger.shared.getAllLogs()
                }
                .disabled(logs.isEmpty)
                Button("コピー") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(logs, forType: .string)
                }
                .disabled(logs.isEmpty)
                Button("閉じる") {
                    dismiss()
                }
            }
            .padding()
            
            Divider()
            
            // ログ表示エリア
            ScrollView {
                Text(logs.isEmpty ? "ログがありません" : logs)
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
    var hotKeyRef3: EventHotKeyRef?  // スナップショット保存（↑）
    var hotKeyRef4: EventHotKeyRef?  // スナップショット復元（↓）
    var hotKeyRef5: EventHotKeyRef?  // ウィンドウ微調整（W: 上）
    var hotKeyRef6: EventHotKeyRef?  // ウィンドウ微調整（A: 左）
    var hotKeyRef7: EventHotKeyRef?  // ウィンドウ微調整（S: 下）
    var hotKeyRef8: EventHotKeyRef?  // ウィンドウ微調整（D: 右）
    var eventHandler: EventHandlerRef?
    var settingsWindow: NSWindow?
    var aboutWindow: NSWindow?
    var debugWindow: NSWindow?
    
    // ディスプレイ記憶機能
    private var windowPositions: [String: [String: CGRect]] = [:]
    private var snapshotTimer: Timer?
    
    // 手動スナップショット機能（5スロット、将来拡張用）
    private var manualSnapshots: [[String: [String: CGRect]]] = Array(repeating: [:], count: 5)
    private var currentSlotIndex: Int = 0  // v1.2.3では常に0
    
    // 自動スナップショット機能
    private var initialSnapshotTimer: Timer?
    private var periodicSnapshotTimer: Timer?
    private var hasInitialSnapshotBeenTaken = false
    
    // ディスプレイ変更の落ち着き待ちタイマー
    private var displayStabilizationTimer: Timer?
    
    // 復元処理のワークアイテム（キャンセル可能）
    private var restoreWorkItem: DispatchWorkItem?
    
    // ディスプレイ監視の有効/無効状態
    private var isDisplayMonitoringEnabled = true
    
    // 最後のディスプレイ変更時刻（安定化検知用）
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
        
        debugPrint("アプリが起動しました")
        debugPrint("接続されている画面数: \(NSScreen.screens.count)")
    }
    
    /// 通知センターのセットアップ
    private func setupNotifications() {
        let center = UNUserNotificationCenter.current()
        center.requestAuthorization(options: [.alert, .sound]) { granted, error in
            if granted {
                debugPrint("✅ 通知権限が許可されました")
            } else if let error = error {
                debugPrint("⚠️ 通知権限のリクエストに失敗: \(error.localizedDescription)")
            }
        }
    }
    
    /// 通知を送信（スナップショット操作用）
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
                debugPrint("⚠️ 通知送信エラー: \(error.localizedDescription)")
            }
        }
    }
    
    func setupMenu() {
        let menu = NSMenu()
        
        let modifierString = HotKeySettings.shared.getModifierString()
        menu.addItem(NSMenuItem(title: "ウィンドウを次の画面へ (\(modifierString)→)", action: #selector(moveWindowToNextScreen), keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: "ウィンドウを前の画面へ (\(modifierString)←)", action: #selector(moveWindowToPrevScreen), keyEquivalent: ""))
        menu.addItem(NSMenuItem.separator())
        
        // スナップショット操作
        menu.addItem(NSMenuItem(title: "📸 配置を保存 (\(modifierString)↑)", action: #selector(saveManualSnapshot), keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: "📥 配置を復元 (\(modifierString)↓)", action: #selector(restoreManualSnapshot), keyEquivalent: ""))
        
        // スナップショット状態
        let snapshotStatusItem = NSMenuItem(title: getSnapshotStatusString(), action: nil, keyEquivalent: "")
        snapshotStatusItem.isEnabled = false
        menu.addItem(snapshotStatusItem)
        
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "設定...", action: #selector(openSettings), keyEquivalent: ","))
        menu.addItem(NSMenuItem(title: "デバッグログを表示", action: #selector(showDebugLog), keyEquivalent: "d"))
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "About Tsubame", action: #selector(openAbout), keyEquivalent: ""))
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "終了", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        
        statusItem?.menu = menu
    }
    
    /// スナップショット状態の文字列を生成
    private func getSnapshotStatusString() -> String {
        if let timestamp = ManualSnapshotStorage.shared.getTimestamp() {
            let formatter = DateFormatter()
            formatter.dateFormat = "HH:mm"
            let timeStr = formatter.string(from: timestamp)
            
            // 保存されているウィンドウ数をカウント
            let snapshot = manualSnapshots[currentSlotIndex]
            let windowCount = snapshot.values.reduce(0) { $0 + $1.count }
            
            return "    💾 \(windowCount)個 @ \(timeStr)"
        } else {
            return "    💾 データなし"
        }
    }
    
    @objc func openSettings() {
        if settingsWindow == nil {
            let settingsView = SettingsView()
            let hostingController = NSHostingController(rootView: settingsView)
            
            let window = NSWindow(contentViewController: hostingController)
            window.title = "設定"
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
        // 毎回新しいウィンドウを作成して最新のログを表示
        let debugView = DebugLogView()
        let hostingController = NSHostingController(rootView: debugView)
        
        let window = NSWindow(contentViewController: hostingController)
        window.title = "デバッグログ"
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
            debugPrint("✅ アクセシビリティ権限が付与されています")
        } else {
            debugPrint("⚠️ アクセシビリティ権限が必要です")
        }
    }
    
    func registerHotKeys() {
        // イベントハンドラーをインストール
        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let status = InstallEventHandler(GetApplicationEventTarget(), hotKeyHandler, 1, &eventType, nil, &eventHandler)
        
        if status == noErr {
            debugPrint("✅ イベントハンドラのインストール成功")
        } else {
            debugPrint("❌ イベントハンドラのインストール失敗: \(status)")
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
            debugPrint("✅ ホットキー1 (\(modifierString)→) の登録成功")
        } else {
            debugPrint("❌ ホットキー1の登録失敗: \(registerStatus1)")
        }
        
        // 2つ目のホットキー: 前の画面へ (左矢印)
        let hotKeyID2 = EventHotKeyID(signature: OSType(0x4D4F5645), id: 2) // 'MOVE' + 2
        let keyCode2 = UInt32(kVK_LeftArrow)
        let registerStatus2 = RegisterEventHotKey(keyCode2, modifiers, hotKeyID2, GetApplicationEventTarget(), 0, &hotKeyRef2)
        
        if registerStatus2 == noErr {
            let modifierString = settings.getModifierString()
            debugPrint("✅ ホットキー2 (\(modifierString)←) の登録成功")
        } else {
            debugPrint("❌ ホットキー2の登録失敗: \(registerStatus2)")
        }
        
        // 3つ目のホットキー: スナップショット保存 (上矢印)
        let hotKeyID3 = EventHotKeyID(signature: OSType(0x4D4F5645), id: 3) // 'MOVE' + 3
        let keyCode3 = UInt32(kVK_UpArrow)
        let registerStatus3 = RegisterEventHotKey(keyCode3, modifiers, hotKeyID3, GetApplicationEventTarget(), 0, &hotKeyRef3)
        
        if registerStatus3 == noErr {
            let modifierString = settings.getModifierString()
            debugPrint("✅ ホットキー3 (\(modifierString)↑) の登録成功")
        } else {
            debugPrint("❌ ホットキー3の登録失敗: \(registerStatus3)")
        }
        
        // 4つ目のホットキー: スナップショット復元 (下矢印)
        let hotKeyID4 = EventHotKeyID(signature: OSType(0x4D4F5645), id: 4) // 'MOVE' + 4
        let keyCode4 = UInt32(kVK_DownArrow)
        let registerStatus4 = RegisterEventHotKey(keyCode4, modifiers, hotKeyID4, GetApplicationEventTarget(), 0, &hotKeyRef4)
        
        if registerStatus4 == noErr {
            let modifierString = settings.getModifierString()
            debugPrint("✅ ホットキー4 (\(modifierString)↓) の登録成功")
        } else {
            debugPrint("❌ ホットキー4の登録失敗: \(registerStatus4)")
        }
        
        // 5つ目のホットキー: ウィンドウ微調整・上 (W)
        let hotKeyID5 = EventHotKeyID(signature: OSType(0x4D4F5645), id: 5) // 'MOVE' + 5
        let keyCode5 = UInt32(kVK_ANSI_W)
        let registerStatus5 = RegisterEventHotKey(keyCode5, modifiers, hotKeyID5, GetApplicationEventTarget(), 0, &hotKeyRef5)
        
        if registerStatus5 == noErr {
            let modifierString = settings.getModifierString()
            debugPrint("✅ ホットキー5 (\(modifierString)W) の登録成功")
        } else {
            debugPrint("❌ ホットキー5の登録失敗: \(registerStatus5)")
        }
        
        // 6つ目のホットキー: ウィンドウ微調整・左 (A)
        let hotKeyID6 = EventHotKeyID(signature: OSType(0x4D4F5645), id: 6) // 'MOVE' + 6
        let keyCode6 = UInt32(kVK_ANSI_A)
        let registerStatus6 = RegisterEventHotKey(keyCode6, modifiers, hotKeyID6, GetApplicationEventTarget(), 0, &hotKeyRef6)
        
        if registerStatus6 == noErr {
            let modifierString = settings.getModifierString()
            debugPrint("✅ ホットキー6 (\(modifierString)A) の登録成功")
        } else {
            debugPrint("❌ ホットキー6の登録失敗: \(registerStatus6)")
        }
        
        // 7つ目のホットキー: ウィンドウ微調整・下 (S)
        let hotKeyID7 = EventHotKeyID(signature: OSType(0x4D4F5645), id: 7) // 'MOVE' + 7
        let keyCode7 = UInt32(kVK_ANSI_S)
        let registerStatus7 = RegisterEventHotKey(keyCode7, modifiers, hotKeyID7, GetApplicationEventTarget(), 0, &hotKeyRef7)
        
        if registerStatus7 == noErr {
            let modifierString = settings.getModifierString()
            debugPrint("✅ ホットキー7 (\(modifierString)S) の登録成功")
        } else {
            debugPrint("❌ ホットキー7の登録失敗: \(registerStatus7)")
        }
        
        // 8つ目のホットキー: ウィンドウ微調整・右 (D)
        let hotKeyID8 = EventHotKeyID(signature: OSType(0x4D4F5645), id: 8) // 'MOVE' + 8
        let keyCode8 = UInt32(kVK_ANSI_D)
        let registerStatus8 = RegisterEventHotKey(keyCode8, modifiers, hotKeyID8, GetApplicationEventTarget(), 0, &hotKeyRef8)
        
        if registerStatus8 == noErr {
            let modifierString = settings.getModifierString()
            debugPrint("✅ ホットキー8 (\(modifierString)D) の登録成功")
        } else {
            debugPrint("❌ ホットキー8の登録失敗: \(registerStatus8)")
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
    
    /// ウィンドウを微調整（指定方向にピクセル単位で移動）
    func nudgeWindow(direction: NudgeDirection) {
        let pixels = HotKeySettings.shared.nudgePixels
        let directionName: String
        switch direction {
        case .up: directionName = "上"
        case .down: directionName = "下"
        case .left: directionName = "左"
        case .right: directionName = "右"
        }
        debugPrint("📐 ウィンドウを\(directionName)に\(pixels)px移動")
        
        // フロントのアプリケーションを取得
        guard let frontApp = NSWorkspace.shared.frontmostApplication else {
            debugPrint("❌ フロントアプリの取得に失敗しました")
            return
        }
        
        // Accessibility APIでウィンドウを取得
        let appRef = AXUIElementCreateApplication(frontApp.processIdentifier)
        var windowRef: AnyObject?
        let result = AXUIElementCopyAttributeValue(appRef, kAXFocusedWindowAttribute as CFString, &windowRef)
        
        guard result == .success, let window = windowRef else {
            debugPrint("❌ フォーカスされたウィンドウの取得に失敗しました")
            return
        }
        
        // 現在の位置を取得
        var positionRef: AnyObject?
        AXUIElementCopyAttributeValue(window as! AXUIElement, kAXPositionAttribute as CFString, &positionRef)
        
        guard let positionValue = positionRef else {
            debugPrint("❌ ウィンドウの位置の取得に失敗しました")
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
        
        // 位置を更新
        if let newPositionValue = AXValueCreate(.cgPoint, &newPosition) {
            let setResult = AXUIElementSetAttributeValue(window as! AXUIElement, kAXPositionAttribute as CFString, newPositionValue)
            if setResult == .success {
                debugPrint("✅ ウィンドウを (\(Int(newPosition.x)), \(Int(newPosition.y))) に移動")
            } else {
                debugPrint("❌ ウィンドウの移動に失敗: \(setResult.rawValue)")
            }
        }
    }
    
    func moveWindow(direction: Direction) {
        debugPrint("=== \(direction == .next ? "次" : "前")の画面への移動を開始 ===")
        
        // フロントのアプリケーションを取得
        guard let frontApp = NSWorkspace.shared.frontmostApplication,
              let appName = frontApp.localizedName else {
            debugPrint("❌ フロントアプリの取得に失敗しました")
            return
        }
        
        debugPrint("フロントアプリ: \(appName)")
        
        // Accessibility APIでウィンドウを取得
        let appRef = AXUIElementCreateApplication(frontApp.processIdentifier)
        var windowRef: AnyObject?
        let result = AXUIElementCopyAttributeValue(appRef, kAXFocusedWindowAttribute as CFString, &windowRef)
        
        guard result == .success, let window = windowRef else {
            debugPrint("❌ フォーカスされたウィンドウの取得に失敗しました")
            return
        }
        
        debugPrint("✅ フォーカスされたウィンドウを取得しました")
        
        // 現在の位置とサイズを取得
        var positionRef: AnyObject?
        var sizeRef: AnyObject?
        
        AXUIElementCopyAttributeValue(window as! AXUIElement, kAXPositionAttribute as CFString, &positionRef)
        AXUIElementCopyAttributeValue(window as! AXUIElement, kAXSizeAttribute as CFString, &sizeRef)
        
        guard let positionValue = positionRef, let sizeValue = sizeRef else {
            debugPrint("❌ ウィンドウの位置・サイズの取得に失敗しました")
            return
        }
        
        var position = CGPoint.zero
        var size = CGSize.zero
        AXValueGetValue(positionValue as! AXValue, .cgPoint, &position)
        AXValueGetValue(sizeValue as! AXValue, .cgSize, &size)
        
        debugPrint("現在のウィンドウ位置: \(position), サイズ: \(size)")
        
        // 利用可能な画面を取得
        let screens = NSScreen.screens
        debugPrint("利用可能な画面数: \(screens.count)")
        
        guard screens.count > 1 else {
            debugPrint("❌ 複数の画面が接続されていません")
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
        
        debugPrint("現在の画面インデックス: \(currentScreenIndex)")
        
        // 次/前の画面のインデックスを計算
        let nextScreenIndex: Int
        switch direction {
        case .next:
            nextScreenIndex = (currentScreenIndex + 1) % screens.count
        case .prev:
            nextScreenIndex = (currentScreenIndex - 1 + screens.count) % screens.count
        }
        
        debugPrint("次の画面インデックス: \(nextScreenIndex)")
        
        let currentScreen = screens[currentScreenIndex]
        let nextScreen = screens[nextScreenIndex]
        
        // ウィンドウの相対位置を維持して移動
        let relativeX = position.x - currentScreen.frame.origin.x
        let relativeY = position.y - currentScreen.frame.origin.y
        
        let newX = nextScreen.frame.origin.x + relativeX
        let newY = nextScreen.frame.origin.y + relativeY
        var newPosition = CGPoint(x: newX, y: newY)
        
        debugPrint("新しい位置: \(newPosition)")
        
        // ウィンドウを移動
        if let positionValue = AXValueCreate(.cgPoint, &newPosition) {
            let setResult = AXUIElementSetAttributeValue(window as! AXUIElement, kAXPositionAttribute as CFString, positionValue)
            
            if setResult == .success {
                debugPrint("✅ ウィンドウの移動に成功しました")
            } else {
                debugPrint("❌ ウィンドウの移動に失敗しました: \(setResult.rawValue)")
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
        debugPrint("✅ ディスプレイ変更の監視を開始しました")
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
        debugPrint("🖥️ ディスプレイ構成が変更されました")
        debugPrint("現在の画面数: \(screenCount)")
        
        // 監視が無効化されている場合
        if !isDisplayMonitoringEnabled {
            // イベントを記録し続ける（これが重要！）
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
            
            debugPrint("✅ ディスプレイが安定したと判断（最後のイベントから\(String(format: "%.1f", elapsed))秒経過）")
            debugPrint("▶️ ディスプレイ安定化により監視を再開します")
            debugPrint("⏳ 次のディスプレイ変更イベントを待機（最大3秒）")
            
            // フォールバック設定（3秒後）
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
            debugPrint("⚠️ ディスプレイイベントが発生しなかったため、手動で復元をトリガーします")
            triggerRestoration()
        } else {
            // イベントが来た → スキップ
            debugPrint("✅ ディスプレイイベントが発生したため、フォールバックはスキップします")
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
        
        debugPrint("復元まで \(totalDelay)秒待機")
        
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
                debugPrint("🔄 復元リトライ予約（\(self.restoreRetryCount)/\(self.maxRestoreRetries)）: \(self.restoreRetryDelay)秒後")
                
                // リトライをスケジュール
                DispatchQueue.main.asyncAfter(deadline: .now() + self.restoreRetryDelay) { [weak self] in
                    self?.triggerRestoration(isRetry: true)
                }
            } else {
                self.restoreRetryCount = 0
                debugPrint("⏭️ スナップショット予約をスキップ（復元数: \(restoredCount), 画面数: \(NSScreen.screens.count)）")
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
        debugPrint("⏸️ ディスプレイ監視を一時停止しました")
    }
    
    /// 監視を再開
    @objc private func resumeMonitoring() {
        debugPrint("⏱️ ディスプレイ変更の安定化を待機中...")
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
        debugPrint("✅ ディスプレイ記憶用の定期監視を開始しました（\(Int(interval))秒間隔）")
    }
    
    /// 現在のウィンドウ配置のスナップショットを取得
    private func takeWindowSnapshot() {
        let options = CGWindowListOption(arrayLiteral: .excludeDesktopElements, .optionOnScreenOnly)
        guard let windowList = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] else {
            return
        }
        
        let screens = NSScreen.screens
        
        // 画面ごとに初期化
        for screen in screens {
            let displayID = getDisplayIdentifier(for: screen)
            if windowPositions[displayID] == nil {
                windowPositions[displayID] = [:]
            }
        }
        
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
            
            let windowID = getWindowIdentifier(appName: ownerName, windowID: cgWindowID)
            
            // このウィンドウがどの画面にあるか判定
            for screen in screens {
                if screen.frame.intersects(frame) {
                    let displayID = getDisplayIdentifier(for: screen)
                    windowPositions[displayID]?[windowID] = frame
                    break
                }
            }
        }
    }
    
    /// 手動スナップショットを保存
    @objc func saveManualSnapshot() {
        debugPrint("📸 手動スナップショット保存を開始（スロット\(currentSlotIndex)）")
        
        let options = CGWindowListOption(arrayLiteral: .excludeDesktopElements, .optionOnScreenOnly)
        guard let windowList = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] else {
            debugPrint("  ❌ ウィンドウリストの取得に失敗")
            return
        }
        
        let screens = NSScreen.screens
        var snapshot: [String: [String: CGRect]] = [:]
        
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
            
            let windowID = getWindowIdentifier(appName: ownerName, windowID: cgWindowID)
            
            // このウィンドウがどの画面にあるか判定
            for screen in screens {
                if screen.frame.intersects(frame) {
                    let displayID = getDisplayIdentifier(for: screen)
                    snapshot[displayID]?[windowID] = frame
                    savedCount += 1
                    debugPrint("  保存: \(ownerName) @ (\(Int(frame.origin.x)), \(Int(frame.origin.y)))")
                    break
                }
            }
        }
        
        manualSnapshots[currentSlotIndex] = snapshot
        
        // 永続化
        ManualSnapshotStorage.shared.save(manualSnapshots)
        
        debugPrint("📸 スナップショット保存完了: \(savedCount)個のウィンドウ")
        
        // 通知
        sendNotification(
            title: "スナップショット保存",
            body: "\(savedCount)個のウィンドウ位置を保存しました"
        )
        
        // メニューを更新
        setupMenu()
    }
    
    /// 手動スナップショットを復元
    @objc func restoreManualSnapshot() {
        debugPrint("📥 手動スナップショット復元を開始（スロット\(currentSlotIndex)）")
        
        let snapshot = manualSnapshots[currentSlotIndex]
        
        if snapshot.isEmpty || snapshot.values.allSatisfy({ $0.isEmpty }) {
            debugPrint("  ⚠️ スナップショットが空です。先に保存してください。")
            return
        }
        
        let options = CGWindowListOption(arrayLiteral: .excludeDesktopElements, .optionOnScreenOnly)
        guard let windowList = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] else {
            debugPrint("  ❌ ウィンドウリストの取得に失敗")
            return
        }
        
        var restoredCount = 0
        
        // 各ディスプレイの保存データを処理
        for (_, savedWindows) in snapshot {
            for (savedWindowID, savedFrame) in savedWindows {
                // windowIDからアプリ名とCGWindowIDを抽出
                let components = savedWindowID.split(separator: "_")
                guard components.count >= 2,
                      let cgWindowID = UInt32(components[1]) else {
                    continue
                }
                let appName = String(components[0])
                
                // 現在のウィンドウリストから該当するものを探す
                for window in windowList {
                    guard let ownerName = window[kCGWindowOwnerName as String] as? String,
                          ownerName == appName,
                          let currentCGWindowID = window[kCGWindowNumber as String] as? CGWindowID,
                          currentCGWindowID == cgWindowID,
                          let layer = window[kCGWindowLayer as String] as? Int,
                          layer == 0,
                          let boundsDict = window[kCGWindowBounds as String] as? [String: CGFloat],
                          let ownerPID = window[kCGWindowOwnerPID as String] as? Int32 else {
                        continue
                    }
                    
                    let currentFrame = CGRect(
                        x: boundsDict["X"] ?? 0,
                        y: boundsDict["Y"] ?? 0,
                        width: boundsDict["Width"] ?? 0,
                        height: boundsDict["Height"] ?? 0
                    )
                    
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
                                            let setResult = AXUIElementSetAttributeValue(axWindow, kAXPositionAttribute as CFString, positionValue)
                                            if setResult == .success {
                                                restoredCount += 1
                                                debugPrint("  ✅ \(appName) を (\(Int(savedFrame.origin.x)), \(Int(savedFrame.origin.y))) に復元")
                                            }
                                        }
                                        break
                                    }
                                }
                            }
                        }
                    }
                    break
                }
            }
        }
        
        debugPrint("📥 スナップショット復元完了: \(restoredCount)個のウィンドウを移動")
        
        // 通知
        if restoredCount > 0 {
            sendNotification(
                title: "スナップショット復元",
                body: "\(restoredCount)個のウィンドウ位置を復元しました"
            )
        } else {
            sendNotification(
                title: "スナップショット復元",
                body: "復元対象のウィンドウがありませんでした"
            )
        }
    }
    
    /// ウィンドウを復元し、復元したウィンドウ数を返す
    @discardableResult // 関数の戻り値がなくても警告を出さない
    private func restoreWindowsIfNeeded() -> Int {
        debugPrint("🔄 ウィンドウ復元処理を開始...")
        
        let currentScreens = NSScreen.screens
        guard currentScreens.count >= 2 else {
            debugPrint("  画面が1つしかないため、復元をスキップします")
            return 0
        }
        
        let currentScreenIDs = Set(currentScreens.map { getDisplayIdentifier(for: $0) })
        let mainScreen = currentScreens[0]
        let mainScreenID = getDisplayIdentifier(for: mainScreen)
        
        // 保存されている画面IDのうち、現在接続されているものを確認
        let savedScreenIDs = Set(windowPositions.keys)
        let externalScreenIDs = savedScreenIDs.intersection(currentScreenIDs).subtracting([mainScreenID])
        
        if externalScreenIDs.isEmpty {
            debugPrint("  復元対象の外部ディスプレイがありません")
            return 0
        }
        
        debugPrint("  復元対象ディスプレイ: \(externalScreenIDs.joined(separator: ", "))")
        
        // 現在の全ウィンドウを取得
        let options = CGWindowListOption(arrayLiteral: .excludeDesktopElements, .optionOnScreenOnly)
        guard let windowList = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] else {
            debugPrint("  ❌ ウィンドウリストの取得に失敗")
            return 0
        }
        
        // デバッグ: 現在のウィンドウリストを表示
        debugPrint("  現在のウィンドウ:")
        for window in windowList {
            if let ownerName = window[kCGWindowOwnerName as String] as? String,
               let cgWindowID = window[kCGWindowNumber as String] as? CGWindowID,
               let layer = window[kCGWindowLayer as String] as? Int, layer == 0 {
                debugPrint("    現在ID: \(ownerName)_\(cgWindowID)")
            }
        }
        
        var restoredCount = 0
        
        // 各外部ディスプレイについて処理
        for externalScreenID in externalScreenIDs {
            guard let savedWindows = windowPositions[externalScreenID], !savedWindows.isEmpty else {
                continue
            }
            
            debugPrint("  画面 \(externalScreenID) に \(savedWindows.count)個の保存情報")
            
            // デバッグ: 保存されているウィンドウIDを表示
            for (savedWindowID, _) in savedWindows {
                debugPrint("    保存ID: \(savedWindowID)")
            }
            
            // 保存されたウィンドウを復元
            for (savedWindowID, savedFrame) in savedWindows {
                debugPrint("    復元試行: \(savedWindowID)")
                
                // windowIDからアプリ名とCGWindowIDを抽出
                let components = savedWindowID.split(separator: "_")
                guard components.count >= 2,
                      let cgWindowID = UInt32(components[1]) else {
                    debugPrint("      ❌ ID解析失敗")
                    continue
                }
                let appName = String(components[0])
                
                // 現在のウィンドウリストから該当するものを探す
                for window in windowList {
                    guard let ownerName = window[kCGWindowOwnerName as String] as? String,
                          ownerName == appName,
                          let currentCGWindowID = window[kCGWindowNumber as String] as? CGWindowID,
                          currentCGWindowID == cgWindowID,
                          let layer = window[kCGWindowLayer as String] as? Int,
                          layer == 0,
                          let boundsDict = window[kCGWindowBounds as String] as? [String: CGFloat],
                          let ownerPID = window[kCGWindowOwnerPID as String] as? Int32 else {
                        continue
                    }
                    
                    debugPrint("      ✓ ウィンドウ発見: \(ownerName)")
                    
                    let currentFrame = CGRect(
                        x: boundsDict["X"] ?? 0,
                        y: boundsDict["Y"] ?? 0,
                        width: boundsDict["Width"] ?? 0,
                        height: boundsDict["Height"] ?? 0
                    )
                    
                    debugPrint("      現在位置: \(currentFrame)")
                    debugPrint("      メイン画面: \(mainScreen.frame)")
                    
                    // メイン画面にあるウィンドウのみを復元対象とする
                    // より確実な判定: ウィンドウのX座標がメイン画面の範囲内にあるか
                    let isOnMainScreen = currentFrame.origin.x >= mainScreen.frame.origin.x &&
                                        currentFrame.origin.x < (mainScreen.frame.origin.x + mainScreen.frame.width)
                    
                    if !isOnMainScreen {
                        debugPrint("      ❌ メイン画面にない(スキップ) - X座標: \(currentFrame.origin.x)")
                        continue
                    }
                    
                    debugPrint("      ✓ メイン画面にある - X座標: \(currentFrame.origin.x)")
                    
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
                                            let setResult = AXUIElementSetAttributeValue(axWindow, kAXPositionAttribute as CFString, positionValue)
                                            if setResult == .success {
                                                restoredCount += 1
                                                debugPrint("    ✅ \(appName) を (\(savedFrame.origin.x), \(savedFrame.origin.y)) に復元")
                                            } else {
                                                debugPrint("    ❌ \(appName) の移動失敗: \(setResult.rawValue)")
                                            }
                                        }
                                        matchFound = true
                                        break
                                    }
                                }
                            }
                        }
                        if !matchFound {
                            debugPrint("      ⚠️ AXUIElement位置マッチング失敗 - CGWindow位置: (\(Int(currentFrame.origin.x)), \(Int(currentFrame.origin.y)))")
                        }
                    }
                    break
                }
            }
        }
        
        debugPrint("✅ 合計 \(restoredCount)個のウィンドウを復元しました\n")
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
                debugPrint("💾 保存済みスナップショットを読み込みました: \(totalWindows)個のウィンドウ")
            }
        } else {
            debugPrint("💾 保存済みスナップショットはありません")
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
        debugPrint("🔄 ディスプレイ記憶用の監視間隔を変更しました（\(Int(interval))秒間隔）")
    }
    
    /// 手動スナップショットをクリア
    private func clearManualSnapshots() {
        manualSnapshots = Array(repeating: [:], count: 5)
        debugPrint("🗑️ メモリ上のスナップショットをクリアしました")
    }
    
    /// 初回自動スナップショットタイマーを開始
    private func startInitialSnapshotTimer() {
        let settings = SnapshotSettings.shared
        let delaySeconds = settings.initialDelaySeconds
        
        debugPrint("⏱️ 初回自動スナップショットタイマーを開始: \(String(format: "%.1f", delaySeconds/60))分後")
        
        // 既存のタイマーをキャンセル
        initialSnapshotTimer?.invalidate()
        initialSnapshotTimer = nil
        
        // Timer を .common モードで RunLoop に追加（UI操作中も動作）
        let timer = Timer(timeInterval: delaySeconds, repeats: false) { [weak self] _ in
            debugPrint("⏱️ 初回自動スナップショットタイマーが発火しました")
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
            debugPrint("⏱️ 定期スナップショットは無効です")
            return
        }
        
        let intervalSeconds = settings.periodicIntervalSeconds
        
        debugPrint("⏱️ 定期スナップショットタイマーを開始: \(String(format: "%.0f", intervalSeconds/60))分間隔")
        
        // 既存のタイマーをキャンセル
        periodicSnapshotTimer?.invalidate()
        periodicSnapshotTimer = nil
        
        // Timer を .common モードで RunLoop に追加（UI操作中も動作）
        let timer = Timer(timeInterval: intervalSeconds, repeats: true) { [weak self] _ in
            debugPrint("⏱️ 定期スナップショットタイマーが発火しました")
            self?.performAutoSnapshot(reason: "定期自動")
        }
        RunLoop.main.add(timer, forMode: .common)
        periodicSnapshotTimer = timer
    }
    
    /// 定期スナップショットタイマーを再設定（設定変更時）
    private func restartPeriodicSnapshotTimerIfNeeded() {
        let settings = SnapshotSettings.shared
        
        periodicSnapshotTimer?.invalidate()
        periodicSnapshotTimer = nil
        
        if settings.enablePeriodicSnapshot && hasInitialSnapshotBeenTaken {
            startPeriodicSnapshotTimer()
        } else if !settings.enablePeriodicSnapshot {
            debugPrint("⏱️ 定期スナップショットを停止しました")
        }
    }
    
    /// 自動スナップショットを実行
    private func performAutoSnapshot(reason: String) {
        debugPrint("📸 \(reason)スナップショットを取得中...")
        
        // ディスプレイ数の確認
        let screenCount = NSScreen.screens.count
        if screenCount < 2 {
            debugPrint("🛡️ ディスプレイ保護: 画面数が\(screenCount)のため自動スナップショットをスキップ")
            return
        }
        
        let options = CGWindowListOption(arrayLiteral: .excludeDesktopElements, .optionOnScreenOnly)
        guard let windowList = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] else {
            debugPrint("  ❌ ウィンドウリストの取得に失敗")
            return
        }
        
        let screens = NSScreen.screens
        var snapshot: [String: [String: CGRect]] = [:]
        
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
            
            let windowID = getWindowIdentifier(appName: ownerName, windowID: cgWindowID)
            
            // このウィンドウがどの画面にあるか判定
            for screen in screens {
                if screen.frame.intersects(frame) {
                    let displayID = getDisplayIdentifier(for: screen)
                    snapshot[displayID]?[windowID] = frame
                    savedCount += 1
                    break
                }
            }
        }
        
        // 既存データ保護チェック
        let snapshotSettings = SnapshotSettings.shared
        if snapshotSettings.protectExistingSnapshot && ManualSnapshotStorage.shared.hasSnapshot {
            if savedCount < snapshotSettings.minimumWindowCount {
                debugPrint("🛡️ 既存データ保護: ウィンドウ数が\(savedCount)個（最小\(snapshotSettings.minimumWindowCount)個）のため上書きをスキップ")
                return
            }
        }
        
        manualSnapshots[currentSlotIndex] = snapshot
        
        // 永続化
        ManualSnapshotStorage.shared.save(manualSnapshots)
        
        debugPrint("📸 \(reason)スナップショット完了: \(savedCount)個のウィンドウ")
        
        // 通知（自動スナップショットはサウンドのみ、システム通知は送らない）
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
        
        debugPrint("⏱️ ディスプレイ認識後スナップショット: \(String(format: "%.1f", delaySeconds/60))分後に予定")
        
        // 既存の初回タイマーをキャンセルして新しく設定
        initialSnapshotTimer?.invalidate()
        initialSnapshotTimer = nil
        
        // Timer を .common モードで RunLoop に追加（UI操作中も動作）
        let timer = Timer(timeInterval: delaySeconds, repeats: false) { [weak self] _ in
            debugPrint("⏱️ ディスプレイ認識後スナップショットタイマーが発火しました")
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

// debugPrint関数の実装
func debugPrint(_ message: String) {
    print(message)
    DebugLogger.shared.addLog(message)
}
