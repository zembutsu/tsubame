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
    var eventHandler: EventHandlerRef?
    var settingsWindow: NSWindow?
    var aboutWindow: NSWindow?
    var debugWindow: NSWindow?
    
    // ディスプレイ記憶機能
    private var windowPositions: [String: [String: CGRect]] = [:]
    private var snapshotTimer: Timer?
    
    // ディスプレイ変更の落ち着き待ちタイマー
    private var displayStabilizationTimer: Timer?
    
    // 復元処理のワークアイテム（キャンセル可能）
    private var restoreWorkItem: DispatchWorkItem?
    
    func applicationDidFinishLaunching(_ notification: Notification) {
        // グローバル参照を設定
        globalAppDelegate = self
        
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
            window.title = "About"
            window.styleMask = [.titled, .closable]
            window.center()
            window.level = .floating
            
            aboutWindow = window
        }
        
        aboutWindow?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
    
    @objc func showDebugLog() {
        let debugView = DebugLogView()
        let hostingController = NSHostingController(rootView: debugView)
        
        if debugWindow == nil {
            let window = NSWindow(contentViewController: hostingController)
            window.title = "デバッグログ"
            window.styleMask = [.titled, .closable, .resizable]
            window.center()
            window.level = .floating
            window.setContentSize(NSSize(width: 700, height: 500))
            
            debugWindow = window
        } else {
            // 既存のウィンドウがある場合は内容を更新
            debugWindow?.contentViewController = hostingController
        }
        
        debugWindow?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
    
    func registerHotKeys() {
        // 既存のホットキーを解除
        if let hotKey = hotKeyRef {
            UnregisterEventHotKey(hotKey)
            hotKeyRef = nil
        }
        if let hotKey = hotKeyRef2 {
            UnregisterEventHotKey(hotKey)
            hotKeyRef2 = nil
        }
        
        // イベントタイプの指定
        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        
        // イベントハンドラをインストール(初回のみ)
        if eventHandler == nil {
            let status = InstallEventHandler(GetApplicationEventTarget(), hotKeyHandler, 1, &eventType, nil, &eventHandler)
            
            if status == noErr {
                debugPrint("✅ イベントハンドラのインストール成功")
            } else {
                debugPrint("❌ イベントハンドラのインストール失敗: \(status)")
            }
        }
        
        // 設定から修飾キーを取得
        let modifiers = HotKeySettings.shared.getModifiers()
        let modifierString = HotKeySettings.shared.getModifierString()
        
        // Ctrl + Option + Command + 右矢印
        let gMyHotKeyID1 = EventHotKeyID(signature: OSType(0x4D4F5652), id: 1) // 'MOVR'
        var hotKey1: EventHotKeyRef?
        let registerStatus1 = RegisterEventHotKey(UInt32(kVK_RightArrow), modifiers, gMyHotKeyID1, GetApplicationEventTarget(), 0, &hotKey1)
        
        if registerStatus1 == noErr {
            hotKeyRef = hotKey1
            debugPrint("✅ ホットキー1 (\(modifierString)→) の登録成功")
        } else {
            debugPrint("❌ ホットキー1 の登録失敗: \(registerStatus1)")
        }
        
        // Ctrl + Option + Command + 左矢印
        let gMyHotKeyID2 = EventHotKeyID(signature: OSType(0x4D4F564C), id: 2) // 'MOVL'
        var hotKey2: EventHotKeyRef?
        let registerStatus2 = RegisterEventHotKey(UInt32(kVK_LeftArrow), modifiers, gMyHotKeyID2, GetApplicationEventTarget(), 0, &hotKey2)
        
        if registerStatus2 == noErr {
            hotKeyRef2 = hotKey2
            debugPrint("✅ ホットキー2 (\(modifierString)←) の登録成功")
        } else {
            debugPrint("❌ ホットキー2 の登録失敗: \(registerStatus2)")
        }
    }
    
    @objc func moveWindowToNextScreen() {
        debugPrint("=== 次の画面への移動を開始 ===")
        moveWindow(direction: 1)
    }
    
    @objc func moveWindowToPrevScreen() {
        debugPrint("=== 前の画面への移動を開始 ===")
        moveWindow(direction: -1)
    }
    
    func moveWindow(direction: Int) {
        guard let frontmostApp = NSWorkspace.shared.frontmostApplication else {
            debugPrint("❌ フロントアプリを取得できませんでした")
            return
        }
        
        debugPrint("フロントアプリ: \(frontmostApp.localizedName ?? "不明")")
        
        let pid = frontmostApp.processIdentifier
        let appRef = AXUIElementCreateApplication(pid)
        
        var focusedWindowRef: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(appRef, kAXFocusedWindowAttribute as CFString, &focusedWindowRef)
        
        guard result == .success, let focusedWindow = focusedWindowRef else {
            debugPrint("❌ フォーカスされたウィンドウがありません")
            return
        }
        
        debugPrint("✅ フォーカスされたウィンドウを取得しました")
        
        // ウィンドウの現在の位置とサイズを取得
        var positionRef: CFTypeRef?
        var sizeRef: CFTypeRef?
        
        guard AXUIElementCopyAttributeValue(focusedWindow as! AXUIElement, kAXPositionAttribute as CFString, &positionRef) == .success,
              AXUIElementCopyAttributeValue(focusedWindow as! AXUIElement, kAXSizeAttribute as CFString, &sizeRef) == .success else {
            debugPrint("❌ ウィンドウの位置またはサイズを取得できませんでした")
            return
        }
        
        var position = CGPoint.zero
        var size = CGSize.zero
        
        guard let positionValue = positionRef, let sizeValue = sizeRef,
              AXValueGetValue(positionValue as! AXValue, .cgPoint, &position),
              AXValueGetValue(sizeValue as! AXValue, .cgSize, &size) else {
            debugPrint("❌ 位置やサイズの値を取得できませんでした")
            return
        }
        
        debugPrint("現在のウィンドウ位置: \(position), サイズ: \(size)")
        
        let screens = NSScreen.screens
        debugPrint("利用可能な画面数: \(screens.count)")
        
        guard screens.count > 1 else {
            debugPrint("❌ 画面が1つしかありません")
            return
        }
        
        // 現在のウィンドウがどの画面にあるかを判定
        var currentScreenIndex = 0
        for (index, screen) in screens.enumerated() {
            if screen.frame.contains(position) {
                currentScreenIndex = index
                debugPrint("現在の画面インデックス: \(index)")
                break
            }
        }
        
        // 次の画面のインデックスを計算
        let nextScreenIndex = (currentScreenIndex + direction + screens.count) % screens.count
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
            let setResult = AXUIElementSetAttributeValue(focusedWindow as! AXUIElement, kAXPositionAttribute as CFString, positionValue)
            
            if setResult == .success {
                debugPrint("✅ ウィンドウの移動に成功しました")
            } else {
                debugPrint("❌ ウィンドウの移動に失敗しました: \(setResult.rawValue)")
            }
        }
    }
    
    func checkAccessibilityPermissions() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true]
        let accessEnabled = AXIsProcessTrustedWithOptions(options as CFDictionary)
        
        if accessEnabled {
            debugPrint("✅ アクセシビリティ権限が付与されています")
        } else {
            debugPrint("⚠️ アクセシビリティ権限が必要です")
        }
    }
    
    // ディスプレイ変更を監視
    private func setupDisplayChangeObserver() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(displayConfigurationChanged),
            name: NSApplication.didChangeScreenParametersNotification,
            object: nil
        )
        debugPrint("✅ ディスプレイ変更の監視を開始しました")
    }
    
    @objc private func displayConfigurationChanged() {
        debugPrint("🖥️ ディスプレイ構成が変更されました")
        debugPrint("現在の画面数: \(NSScreen.screens.count)")
        
        // 既存の復元処理をキャンセル
        restoreWorkItem?.cancel()
        
        // 設定から遅延時間を取得
        let stabilizationDelay = WindowTimingSettings.shared.displayStabilizationDelay
        let restoreDelay = WindowTimingSettings.shared.windowRestoreDelay
        let totalDelay = stabilizationDelay + restoreDelay
        
        debugPrint("復元まで \(totalDelay)秒待機（安定化:\(stabilizationDelay)秒 + 復元:\(restoreDelay)秒）")
        
        // 新しい復元処理を作成
        let workItem = DispatchWorkItem { [weak self] in
            self?.restoreWindowsIfNeeded()
        }
        
        // 保存してスケジュール
        restoreWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + totalDelay, execute: workItem)
    }
    
    /// 定期的にウィンドウ位置のスナップショットを取る
    private func startPeriodicSnapshot() {
        snapshotTimer = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: true) { [weak self] _ in
            self?.snapshotAllWindows()
        }
        debugPrint("✅ 定期スナップショットを開始しました(5秒間隔)")
    }
    
    /// ディスプレイの一意な識別子を取得
    private func getDisplayIdentifier(for screen: NSScreen) -> String {
        // NSScreenのデバイス記述から識別子を生成
        if let screenNumber = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID {
            return "\(screenNumber)"
        }
        // フォールバック: フレーム情報から生成
        return "\(screen.frame.origin.x)_\(screen.frame.origin.y)"
    }
    
    /// ウィンドウの一意な識別子を生成
    private func getWindowIdentifier(appName: String, windowID: CGWindowID) -> String {
        return "\(appName)_\(windowID)"
    }
    
    /// 全ウィンドウの位置をスナップショット
    private func snapshotAllWindows() {
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
