import Cocoa
import Carbon
import SwiftUI

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
    
    func applicationDidFinishLaunching(_ notification: Notification) {
        // グローバル参照を設定
        globalAppDelegate = self
        
        // WindowTimingSettingsを初期化してスリープ監視を開始
        _ = WindowTimingSettings.shared
        
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
        
        // 定期スナップショットを開始(5秒ごと)
        startPeriodicSnapshot()
        
        debugPrint("アプリが起動しました")
        debugPrint("接続されている画面数: \(NSScreen.screens.count)")
    }
    
    func setupMenu() {
        let menu = NSMenu()
        
        let modifierString = HotKeySettings.shared.getModifierString()
        menu.addItem(NSMenuItem(title: "ウィンドウを次の画面へ (\(modifierString)→)", action: #selector(moveWindowToNextScreen), keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: "ウィンドウを前の画面へ (\(modifierString)←)", action: #selector(moveWindowToPrevScreen), keyEquivalent: ""))
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "📸 配置を保存 (\(modifierString)↑)", action: #selector(saveManualSnapshot), keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: "📥 配置を復元 (\(modifierString)↓)", action: #selector(restoreManualSnapshot), keyEquivalent: ""))
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "設定...", action: #selector(openSettings), keyEquivalent: ","))
        menu.addItem(NSMenuItem(title: "デバッグログを表示", action: #selector(showDebugLog), keyEquivalent: "d"))
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "About WindowSmartMover", action: #selector(openAbout), keyEquivalent: ""))
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "終了", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        
        statusItem?.menu = menu
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
            window.title = "About WindowSmartMover"
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
    private func triggerRestoration() {
        // 既存のタイマーをキャンセル
        restoreWorkItem?.cancel()
        
        let settings = WindowTimingSettings.shared
        let totalDelay = settings.windowRestoreDelay
        
        debugPrint("復元まで \(totalDelay)秒待機")
        
        let workItem = DispatchWorkItem { [weak self] in
            self?.restoreWindowsIfNeeded()
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
    
    /// 定期スナップショットを開始
    private func startPeriodicSnapshot() {
        snapshotTimer = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: true) { [weak self] _ in
            self?.takeWindowSnapshot()
        }
        debugPrint("✅ 定期スナップショットを開始しました(5秒間隔)")
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
        debugPrint("📸 スナップショット保存完了: \(savedCount)個のウィンドウ")
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
    }
    
    /// 必要に応じてウィンドウを復元
    private func restoreWindowsIfNeeded() {
        debugPrint("🔄 ウィンドウ復元処理を開始...")
        
        let currentScreens = NSScreen.screens
        guard currentScreens.count >= 2 else {
            debugPrint("  画面が1つしかないため、復元をスキップします")
            return
        }
        
        let currentScreenIDs = Set(currentScreens.map { getDisplayIdentifier(for: $0) })
        let mainScreen = currentScreens[0]
        let mainScreenID = getDisplayIdentifier(for: mainScreen)
        
        // 保存されている画面IDのうち、現在接続されているものを確認
        let savedScreenIDs = Set(windowPositions.keys)
        let externalScreenIDs = savedScreenIDs.intersection(currentScreenIDs).subtracting([mainScreenID])
        
        if externalScreenIDs.isEmpty {
            debugPrint("  復元対象の外部ディスプレイがありません")
            return
        }
        
        debugPrint("  復元対象ディスプレイ: \(externalScreenIDs.joined(separator: ", "))")
        
        // 現在の全ウィンドウを取得
        let options = CGWindowListOption(arrayLiteral: .excludeDesktopElements, .optionOnScreenOnly)
        guard let windowList = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] else {
            debugPrint("  ❌ ウィンドウリストの取得に失敗")
            return
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
                                                debugPrint("    ✅ \(appName) を (\(savedFrame.origin.x), \(savedFrame.origin.y)) に復元")
                                            } else {
                                                debugPrint("    ❌ \(appName) の移動失敗: \(setResult.rawValue)")
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
        
        debugPrint("✅ 合計 \(restoredCount)個のウィンドウを復元しました\n")
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
        if let handler = eventHandler {
            RemoveEventHandler(handler)
        }
        // タイマーの停止
        snapshotTimer?.invalidate()
    }
}

// debugPrint関数の実装
func debugPrint(_ message: String) {
    print(message)
    DebugLogger.shared.addLog(message)
}
