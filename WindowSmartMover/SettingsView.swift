import SwiftUI
import Carbon
import Combine
import AppKit
import CryptoKit

// MARK: - Window Matching Data Structure

/// ウィンドウ識別情報（プライバシー保護のためハッシュ化）
struct WindowMatchInfo: Codable, Equatable {
    let appNameHash: String      // SHA256(appName)
    let titleHash: String?       // SHA256(title) - マッチング用
    let size: CGSize             // フォールバックマッチング用
    let frame: CGRect            // 復元位置
    
    /// SHA256ハッシュを生成
    static func hash(_ input: String) -> String {
        let data = Data(input.utf8)
        let hash = SHA256.hash(data: data)
        return hash.compactMap { String(format: "%02x", $0) }.joined()
    }
    
    /// ウィンドウ情報から生成
    init(appName: String, title: String?, size: CGSize, frame: CGRect) {
        self.appNameHash = WindowMatchInfo.hash(appName)
        self.titleHash = title.map { WindowMatchInfo.hash($0) }
        self.size = size
        self.frame = frame
    }
    
    /// サイズが近似しているか（±20px許容）
    func sizeMatches(_ otherSize: CGSize, tolerance: CGFloat = 20) -> Bool {
        return abs(size.width - otherSize.width) <= tolerance &&
               abs(size.height - otherSize.height) <= tolerance
    }
}

class HotKeySettings: ObservableObject {
    static let shared = HotKeySettings()
    
    @Published var useControl: Bool {
        didSet { UserDefaults.standard.set(useControl, forKey: "useControl") }
    }
    @Published var useOption: Bool {
        didSet { UserDefaults.standard.set(useOption, forKey: "useOption") }
    }
    @Published var useShift: Bool {
        didSet { UserDefaults.standard.set(useShift, forKey: "useShift") }
    }
    @Published var useCommand: Bool {
        didSet { UserDefaults.standard.set(useCommand, forKey: "useCommand") }
    }
    
    /// ウィンドウ微調整のピクセル数（10-500、デフォルト100）
    @Published var nudgePixels: Int {
        didSet { UserDefaults.standard.set(nudgePixels, forKey: "nudgePixels") }
    }
    
    private init() {
        // デフォルト値: Ctrl + Option + Command
        self.useControl = UserDefaults.standard.object(forKey: "useControl") as? Bool ?? true
        self.useOption = UserDefaults.standard.object(forKey: "useOption") as? Bool ?? true
        self.useShift = UserDefaults.standard.object(forKey: "useShift") as? Bool ?? false
        self.useCommand = UserDefaults.standard.object(forKey: "useCommand") as? Bool ?? true
        // デフォルト値: 100ピクセル
        self.nudgePixels = UserDefaults.standard.object(forKey: "nudgePixels") as? Int ?? 100
    }
    
    func getModifiers() -> UInt32 {
        var modifiers: UInt32 = 0
        if useControl { modifiers |= UInt32(controlKey) }
        if useOption { modifiers |= UInt32(optionKey) }
        if useShift { modifiers |= UInt32(shiftKey) }
        if useCommand { modifiers |= UInt32(cmdKey) }
        return modifiers
    }
    
    func getModifierString() -> String {
        var parts: [String] = []
        if useControl { parts.append("⌃") }
        if useOption { parts.append("⌥") }
        if useShift { parts.append("⇧") }
        if useCommand { parts.append("⌘") }
        return parts.joined()
    }
}

// WindowTimingSettings: ウィンドウ読み込みタイミング設定
class WindowTimingSettings: ObservableObject {
    static let shared = WindowTimingSettings()
    
    private let defaults = UserDefaults.standard
    private let windowDelayKey = "windowRestoreDelay"
    private let displayStabilizationKey = "displayStabilizationDelay"
    private let disableMonitoringKey = "disableMonitoringDuringSleep"
    private let displayMemoryIntervalKey = "displayMemoryInterval"
    
    @Published var windowRestoreDelay: Double {
        didSet {
            defaults.set(windowRestoreDelay, forKey: windowDelayKey)
        }
    }
    
    @Published var displayStabilizationDelay: Double {
        didSet {
            defaults.set(displayStabilizationDelay, forKey: displayStabilizationKey)
        }
    }
    
    @Published var disableMonitoringDuringSleep: Bool {
        didSet {
            defaults.set(disableMonitoringDuringSleep, forKey: disableMonitoringKey)
        }
    }
    
    /// ディスプレイ記憶用の監視間隔（秒）: 1-30秒、デフォルト5秒
    @Published var displayMemoryInterval: Double {
        didSet {
            defaults.set(displayMemoryInterval, forKey: displayMemoryIntervalKey)
            // 設定変更を通知
            NotificationCenter.default.post(
                name: Notification.Name("DisplayMemoryIntervalChanged"),
                object: nil
            )
        }
    }
    
    // スリープ監視関連
    @Published var lastSleepTime: Date?
    @Published var lastWakeTime: Date?
    @Published var sleepDurationHours: Double = 0
    @Published var isMonitoringEnabled: Bool = true
    
    private var sleepObserver: NSObjectProtocol?
    private var wakeObserver: NSObjectProtocol?
    
    private init() {
        // デフォルト値: ディスプレイ接続後の待機時間は6.0秒
        self.windowRestoreDelay = defaults.object(forKey: windowDelayKey) as? Double ?? 6.0
        // デフォルト値: ディスプレイ変更の落ち着き待ち時間は6.0秒
        self.displayStabilizationDelay = defaults.object(forKey: displayStabilizationKey) as? Double ?? 6.0
        // デフォルト値: スリープ中の監視停止を有効化
        self.disableMonitoringDuringSleep = defaults.object(forKey: disableMonitoringKey) as? Bool ?? true
        // デフォルト値: ディスプレイ記憶用監視間隔は5.0秒
        self.displayMemoryInterval = defaults.object(forKey: displayMemoryIntervalKey) as? Double ?? 5.0
        
        // スリープ監視を開始
        startSleepMonitoring()
    }
    
    // スリープ監視開始
    private func startSleepMonitoring() {
        sleepObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.willSleepNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            guard let self = self else { return }
            self.lastSleepTime = Date()
            print("💤 System going to sleep at \(Date())")
            
            // スリープ時にディスプレイ監視を一時停止
            if self.disableMonitoringDuringSleep {
                self.isMonitoringEnabled = false
                print("⏸️ Display monitoring disabled during sleep")
                NotificationCenter.default.post(
                    name: Notification.Name("DisableDisplayMonitoring"),
                    object: nil
                )
            }
        }
        
        wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.handleWake()
        }
    }
    
    // ウェイク時の処理
    private func handleWake() {
        lastWakeTime = Date()
        if let sleepTime = lastSleepTime {
            let duration = Date().timeIntervalSince(sleepTime)
            sleepDurationHours = duration / 3600.0
            print("☀️ System woke from sleep after \(String(format: "%.2f", sleepDurationHours)) hours")
        }
        
        // 監視一時停止機能が有効な場合
        if disableMonitoringDuringSleep {
            print("⏱️ ディスプレイ変更の安定化を待機中...")
            print("   安定化検出により自動的に監視が再開されます")
            // 注: 監視再開は安定化ロジック（AppDelegate）が自動的に行う
            // ここでは何もしない = ディスプレイ変更イベントの安定化に任せる
        }
    }
    
    // 動的調整された待機時間を取得
    func getAdjustedDisplayDelay() -> Double {
        let baseDelay = displayStabilizationDelay
        
        // スリープ時間に応じて追加の待機時間を決定
        switch sleepDurationHours {
        case 0..<0.5:
            // 30分未満: 変更なし
            return baseDelay
        case 0.5..<1.0:
            // 30分〜1時間: +2秒
            return baseDelay + 2.0
        case 1.0..<2.0:
            // 1〜2時間: +5秒
            return baseDelay + 5.0
        case 2.0..<4.0:
            // 2〜4時間: +10秒
            return baseDelay + 10.0
        default:
            // 4時間以上: +15秒
            return baseDelay + 15.0
        }
    }
    
    deinit {
        if let observer = sleepObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(observer)
        }
        if let observer = wakeObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(observer)
        }
    }
}

// SnapshotSettings: 自動スナップショット設定
class SnapshotSettings: ObservableObject {
    static let shared = SnapshotSettings()
    
    private let defaults = UserDefaults.standard
    private let initialDelayKey = "snapshotInitialDelay"
    private let enablePeriodicKey = "snapshotEnablePeriodic"
    private let periodicIntervalKey = "snapshotPeriodicInterval"
    
    /// 初回スナップショット遅延（分）: 0.5-60分、デフォルト5分
    @Published var initialSnapshotDelay: Double {
        didSet {
            defaults.set(initialSnapshotDelay, forKey: initialDelayKey)
        }
    }
    
    /// 定期スナップショット有効化
    @Published var enablePeriodicSnapshot: Bool {
        didSet {
            defaults.set(enablePeriodicSnapshot, forKey: enablePeriodicKey)
            // 設定変更を通知
            NotificationCenter.default.post(
                name: Notification.Name("SnapshotSettingsChanged"),
                object: nil
            )
        }
    }
    
    /// 定期スナップショット間隔（分）: 5-360分、デフォルト30分
    @Published var periodicSnapshotInterval: Double {
        didSet {
            defaults.set(periodicSnapshotInterval, forKey: periodicIntervalKey)
            // 設定変更を通知
            NotificationCenter.default.post(
                name: Notification.Name("SnapshotSettingsChanged"),
                object: nil
            )
        }
    }
    
    /// 既存スナップショット保護（ウィンドウ数が少ない場合は上書きしない）
    @Published var protectExistingSnapshot: Bool {
        didSet {
            defaults.set(protectExistingSnapshot, forKey: protectExistingKey)
        }
    }
    
    /// 保護時の最小ウィンドウ数
    @Published var minimumWindowCount: Int {
        didSet {
            defaults.set(minimumWindowCount, forKey: minimumWindowCountKey)
        }
    }
    
    private let protectExistingKey = "snapshotProtectExisting"
    private let minimumWindowCountKey = "snapshotMinimumWindowCount"
    private let enableSoundKey = "snapshotEnableSound"
    private let enableNotificationKey = "snapshotEnableNotification"
    private let soundNameKey = "snapshotSoundName"
    private let disablePersistenceKey = "snapshotDisablePersistence"
    private let verboseLoggingKey = "snapshotVerboseLogging"
    
    /// 利用可能なシステムサウンド
    static let availableSounds = [
        "Blow", "Bottle", "Frog", "Funk", "Glass",
        "Hero", "Morse", "Ping", "Pop", "Purr",
        "Sosumi", "Submarine", "Tink"
    ]
    
    /// サウンド通知有効化
    @Published var enableSound: Bool {
        didSet {
            defaults.set(enableSound, forKey: enableSoundKey)
        }
    }
    
    /// 通知サウンド名
    @Published var soundName: String {
        didSet {
            defaults.set(soundName, forKey: soundNameKey)
        }
    }
    
    /// システム通知有効化
    @Published var enableNotification: Bool {
        didSet {
            defaults.set(enableNotification, forKey: enableNotificationKey)
        }
    }
    
    /// スナップショットを永続化しない（プライバシー保護モード）
    @Published var disablePersistence: Bool {
        didSet {
            defaults.set(disablePersistence, forKey: disablePersistenceKey)
            // 有効化時に既存データをクリア
            if disablePersistence {
                ManualSnapshotStorage.shared.clear()
            }
        }
    }
    
    /// 詳細ログを出力（デバッグ用）
    @Published var verboseLogging: Bool {
        didSet {
            defaults.set(verboseLogging, forKey: verboseLoggingKey)
        }
    }
    
    private init() {
        self.initialSnapshotDelay = defaults.object(forKey: initialDelayKey) as? Double ?? 15.0
        self.enablePeriodicSnapshot = defaults.object(forKey: enablePeriodicKey) as? Bool ?? false
        self.periodicSnapshotInterval = defaults.object(forKey: periodicIntervalKey) as? Double ?? 30.0
        self.protectExistingSnapshot = defaults.object(forKey: protectExistingKey) as? Bool ?? true
        self.minimumWindowCount = defaults.object(forKey: minimumWindowCountKey) as? Int ?? 3
        self.enableSound = defaults.object(forKey: enableSoundKey) as? Bool ?? true
        self.soundName = defaults.object(forKey: soundNameKey) as? String ?? "Blow"
        self.enableNotification = defaults.object(forKey: enableNotificationKey) as? Bool ?? false
        self.disablePersistence = defaults.object(forKey: disablePersistenceKey) as? Bool ?? false
        self.verboseLogging = defaults.object(forKey: verboseLoggingKey) as? Bool ?? false
    }
    
    /// サウンドをプレビュー再生
    func previewSound() {
        NSSound(named: NSSound.Name(soundName))?.play()
    }
    
    /// 初回遅延を秒単位で取得
    var initialDelaySeconds: Double {
        return initialSnapshotDelay * 60.0
    }
    
    /// 定期間隔を秒単位で取得
    var periodicIntervalSeconds: Double {
        return periodicSnapshotInterval * 60.0
    }
}

// ManualSnapshotStorage: スナップショットの永続化（プライバシー保護版）
class ManualSnapshotStorage {
    static let shared = ManualSnapshotStorage()
    
    private let defaults = UserDefaults.standard
    private let storageKey = "manualSnapshotDataV2"  // 新形式用のキー
    private let timestampKey = "manualSnapshotTimestamp"
    private let legacyStorageKey = "manualSnapshotData"  // 旧形式のキー（マイグレーション用）
    
    private init() {
        // 旧形式データがあれば削除
        if defaults.data(forKey: legacyStorageKey) != nil {
            defaults.removeObject(forKey: legacyStorageKey)
            print("🔄 旧形式のスナップショットデータを削除しました（v1.3.0移行）")
        }
    }
    
    /// スナップショットを保存（新形式: WindowMatchInfo）
    func save(_ snapshots: [[String: [String: WindowMatchInfo]]]) {
        // 永続化無効の場合はスキップ
        if SnapshotSettings.shared.disablePersistence {
            print("🔒 永続化無効モード: スナップショットは保存されません")
            return
        }
        
        // WindowMatchInfoは直接Codable対応
        if let data = try? JSONEncoder().encode(snapshots) {
            defaults.set(data, forKey: storageKey)
            defaults.set(Date().timeIntervalSince1970, forKey: timestampKey)
            print("💾 スナップショットを永続化しました（プライバシー保護形式）")
        }
    }
    
    /// スナップショットを読み込み（新形式）
    func load() -> [[String: [String: WindowMatchInfo]]]? {
        guard let data = defaults.data(forKey: storageKey),
              let snapshots = try? JSONDecoder().decode([[String: [String: WindowMatchInfo]]].self, from: data) else {
            return nil
        }
        
        if let timestamp = defaults.object(forKey: timestampKey) as? Double {
            let date = Date(timeIntervalSince1970: timestamp)
            print("💾 保存済みスナップショットを読み込みました（保存日時: \(date)）")
        }
        
        return snapshots
    }
    
    /// 保存日時を取得
    func getTimestamp() -> Date? {
        guard let timestamp = defaults.object(forKey: timestampKey) as? Double else {
            return nil
        }
        return Date(timeIntervalSince1970: timestamp)
    }
    
    /// スナップショットをクリア
    func clear() {
        defaults.removeObject(forKey: storageKey)
        defaults.removeObject(forKey: timestampKey)
        print("🗑️ 永続化されたスナップショットをクリアしました")
    }
    
    /// スナップショットが存在するか
    var hasSnapshot: Bool {
        return defaults.data(forKey: storageKey) != nil
    }
}

struct SettingsView: View {
    @ObservedObject var settings = HotKeySettings.shared
    @ObservedObject var timingSettings = WindowTimingSettings.shared
    @ObservedObject var snapshotSettings = SnapshotSettings.shared
    @Environment(\.dismiss) var dismiss
    @State private var selectedTab = 0
    
    var body: some View {
        VStack(spacing: 16) {
            Text("設定")
                .font(.title)
                .padding(.top)
            
            // タブ選択
            Picker("", selection: $selectedTab) {
                Text("Basic").tag(0)
                Text("Advanced").tag(1)
            }
            .pickerStyle(.segmented)
            .padding(.horizontal)
            
            // タブコンテンツ
            ScrollView {
                if selectedTab == 0 {
                    basicSettingsContent
                } else {
                    advancedSettingsContent
                }
            }
            
            Divider()
            
            // フッター
            HStack {
                Button("デフォルトに戻す") {
                    resetToDefaults()
                }
                
                Spacer()
                
                Text("⚠️ 一部の設定は再起動が必要")
                    .font(.caption)
                    .foregroundColor(.orange)
                
                Spacer()
                
                Button("閉じる") {
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
            }
            .padding(.horizontal)
            .padding(.bottom)
        }
        .padding()
        .frame(width: 520, height: 620)
    }
    
    // MARK: - Basic Settings Tab
    
    private var basicSettingsContent: some View {
        VStack(spacing: 16) {
            // ショートカットキー設定
            GroupBox(label: Text("ショートカットキー").font(.headline)) {
                VStack(alignment: .leading, spacing: 10) {
                    Text("修飾キーを選択：")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    
                    HStack(spacing: 20) {
                        Toggle("⌃ Control", isOn: $settings.useControl)
                        Toggle("⌥ Option", isOn: $settings.useOption)
                    }
                    HStack(spacing: 20) {
                        Toggle("⇧ Shift", isOn: $settings.useShift)
                        Toggle("⌘ Command", isOn: $settings.useCommand)
                    }
                    
                    Divider()
                    
                    // 現在のショートカット
                    HStack(spacing: 30) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("画面間移動：")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            HStack {
                                Text("\(settings.getModifierString())→←")
                                    .font(.system(.body, design: .monospaced))
                                    .foregroundColor(.blue)
                            }
                        }
                        VStack(alignment: .leading, spacing: 4) {
                            Text("スナップショット：")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            HStack {
                                Text("\(settings.getModifierString())↑↓")
                                    .font(.system(.body, design: .monospaced))
                                    .foregroundColor(.blue)
                            }
                        }
                    }
                }
                .padding(.vertical, 8)
            }
            
            // ウィンドウ位置微調整
            GroupBox(label: Text("ウィンドウ位置微調整").font(.headline)) {
                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 16) {
                        VStack(spacing: 2) {
                            Text("\(settings.getModifierString())W")
                                .font(.system(.caption, design: .monospaced))
                                .foregroundColor(.blue)
                            Text("↑").font(.caption2)
                        }
                        VStack(spacing: 2) {
                            Text("\(settings.getModifierString())S")
                                .font(.system(.caption, design: .monospaced))
                                .foregroundColor(.blue)
                            Text("↓").font(.caption2)
                        }
                        VStack(spacing: 2) {
                            Text("\(settings.getModifierString())A")
                                .font(.system(.caption, design: .monospaced))
                                .foregroundColor(.blue)
                            Text("←").font(.caption2)
                        }
                        VStack(spacing: 2) {
                            Text("\(settings.getModifierString())D")
                                .font(.system(.caption, design: .monospaced))
                                .foregroundColor(.blue)
                            Text("→").font(.caption2)
                        }
                        
                        Spacer()
                        
                        HStack {
                            Text("移動量:")
                                .font(.subheadline)
                            Stepper(value: $settings.nudgePixels, in: 10...500, step: 10) {
                                Text("\(settings.nudgePixels) px")
                                    .foregroundColor(.blue)
                                    .fontWeight(.semibold)
                                    .frame(width: 55, alignment: .trailing)
                            }
                        }
                    }
                }
                .padding(.vertical, 8)
            }
            
            // 自動スナップショット
            GroupBox(label: Text("自動スナップショット").font(.headline)) {
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Text("初回取得までの時間:")
                            .font(.subheadline)
                        Spacer()
                        Stepper(value: $snapshotSettings.initialSnapshotDelay, in: 0.5...60.0, step: 0.5) {
                            Text(formatMinutes(snapshotSettings.initialSnapshotDelay))
                                .foregroundColor(.blue)
                                .fontWeight(.semibold)
                                .frame(width: 65, alignment: .trailing)
                        }
                    }
                    
                    Toggle("定期的に自動取得", isOn: $snapshotSettings.enablePeriodicSnapshot)
                    
                    if snapshotSettings.enablePeriodicSnapshot {
                        HStack {
                            Text("取得間隔:")
                                .font(.subheadline)
                            Spacer()
                            Stepper(value: $snapshotSettings.periodicSnapshotInterval, in: 5.0...360.0, step: 5.0) {
                                Text(formatMinutes(snapshotSettings.periodicSnapshotInterval))
                                    .foregroundColor(.blue)
                                    .fontWeight(.semibold)
                                    .frame(width: 80, alignment: .trailing)
                            }
                        }
                    }
                    
                    Divider()
                    
                    Toggle("既存データを保護", isOn: $snapshotSettings.protectExistingSnapshot)
                    
                    if snapshotSettings.protectExistingSnapshot {
                        HStack {
                            Text("最小ウィンドウ数:")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            Stepper(value: $snapshotSettings.minimumWindowCount, in: 1...10) {
                                Text("\(snapshotSettings.minimumWindowCount)")
                                    .foregroundColor(.blue)
                                    .frame(width: 25, alignment: .trailing)
                            }
                            Text("個未満は上書きしない")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                    
                    Divider()
                    
                    // プライバシー設定
                    Text("プライバシー")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    Toggle("スナップショットを永続化しない", isOn: $snapshotSettings.disablePersistence)
                    
                    Text("有効にすると、アプリ終了時にすべてのデータが消去されます")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    Divider()
                    
                    // 通知設定
                    Text("通知")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    HStack {
                        Toggle("サウンド", isOn: $snapshotSettings.enableSound)
                        Toggle("システム通知", isOn: $snapshotSettings.enableNotification)
                    }
                    
                    if snapshotSettings.enableSound {
                        HStack {
                            Text("サウンド:")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            Picker("", selection: $snapshotSettings.soundName) {
                                ForEach(SnapshotSettings.availableSounds, id: \.self) { sound in
                                    Text(sound).tag(sound)
                                }
                            }
                            .frame(width: 120)
                            
                            Button("♪") {
                                snapshotSettings.previewSound()
                            }
                            .help("プレビュー再生")
                        }
                    }
                    
                    Divider()
                    
                    // デバッグ設定
                    Text("デバッグ")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    Toggle("詳細ログを出力", isOn: $snapshotSettings.verboseLogging)
                    
                    Text("スナップショット保存・復元時の詳細情報をログに出力します")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    Divider()
                    
                    // 保存状態
                    HStack {
                        if let timestamp = ManualSnapshotStorage.shared.getTimestamp() {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundColor(.green)
                            Text("最終保存: \(timestamp.formatted(date: .abbreviated, time: .shortened))")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        } else {
                            Image(systemName: "xmark.circle")
                                .foregroundColor(.orange)
                            Text("保存データなし")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        
                        Spacer()
                        
                        Button("クリア") {
                            ManualSnapshotStorage.shared.clear()
                            NotificationCenter.default.post(
                                name: Notification.Name("ClearManualSnapshot"),
                                object: nil
                            )
                        }
                        .font(.caption)
                        .disabled(!ManualSnapshotStorage.shared.hasSnapshot)
                    }
                }
                .padding(.vertical, 8)
            }
        }
        .padding(.horizontal)
    }
    
    // MARK: - Advanced Settings Tab
    
    private var advancedSettingsContent: some View {
        VStack(spacing: 16) {
            // ウィンドウ復元タイミング
            GroupBox(label: Text("ウィンドウ復元タイミング").font(.headline)) {
                VStack(alignment: .leading, spacing: 12) {
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text("ディスプレイ変更検出の安定化時間:")
                                .font(.subheadline)
                            Spacer()
                            Text(String(format: "%.1f秒", timingSettings.displayStabilizationDelay))
                                .foregroundColor(.blue)
                                .fontWeight(.semibold)
                        }
                        Slider(value: $timingSettings.displayStabilizationDelay, in: 0.1...15.0, step: 0.1)
                        Text("ディスプレイ変更イベントが落ち着くまでの待機時間")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    
                    Divider()
                    
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text("ディスプレイ接続後の待機時間:")
                                .font(.subheadline)
                            Spacer()
                            Text(String(format: "%.1f秒", timingSettings.windowRestoreDelay))
                                .foregroundColor(.blue)
                                .fontWeight(.semibold)
                        }
                        Slider(value: $timingSettings.windowRestoreDelay, in: 0.1...15.0, step: 0.1)
                        Text("macOSがウィンドウ座標を更新し終わるまでの待機時間")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    
                    Divider()
                    
                    HStack {
                        Text("ウィンドウ位置の監視間隔:")
                            .font(.subheadline)
                        Spacer()
                        Stepper(value: $timingSettings.displayMemoryInterval, in: 1.0...30.0, step: 1.0) {
                            Text("\(Int(timingSettings.displayMemoryInterval))秒")
                                .foregroundColor(.blue)
                                .fontWeight(.semibold)
                                .frame(width: 45, alignment: .trailing)
                        }
                    }
                    Text("ディスプレイ再接続時の自動復元用")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .padding(.vertical, 8)
            }
            
            // スリープ時の動作設定
            GroupBox(label: Text("スリープ時の動作").font(.headline)) {
                VStack(alignment: .leading, spacing: 10) {
                    Toggle("スリープ中はディスプレイ監視を一時停止", isOn: $timingSettings.disableMonitoringDuringSleep)
                    
                    Text("スリープ中のディスプレイ変更イベントを無視します")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    if timingSettings.sleepDurationHours > 0 {
                        Divider()
                        
                        HStack {
                            Text("前回のスリープ:")
                                .font(.caption)
                            Text(String(format: "%.1f時間", timingSettings.sleepDurationHours))
                                .font(.caption)
                                .foregroundColor(.blue)
                            Spacer()
                            Text("調整後の待機:")
                                .font(.caption)
                            Text(String(format: "%.1f秒", timingSettings.getAdjustedDisplayDelay()))
                                .font(.caption)
                                .foregroundColor(.green)
                        }
                        
                        HStack {
                            Text("監視状態:")
                                .font(.caption)
                            Text(timingSettings.isMonitoringEnabled ? "有効" : "一時停止中")
                                .font(.caption)
                                .foregroundColor(timingSettings.isMonitoringEnabled ? .green : .orange)
                        }
                    }
                }
                .padding(.vertical, 8)
            }
        }
        .padding(.horizontal)
    }
    
    // MARK: - Helper Functions
    
    private func resetToDefaults() {
        settings.useControl = true
        settings.useOption = true
        settings.useShift = false
        settings.useCommand = true
        settings.nudgePixels = 100
        timingSettings.displayStabilizationDelay = 6.0
        timingSettings.windowRestoreDelay = 6.0
        timingSettings.disableMonitoringDuringSleep = true
        timingSettings.displayMemoryInterval = 5.0
        snapshotSettings.initialSnapshotDelay = 15.0
        snapshotSettings.enablePeriodicSnapshot = false
        snapshotSettings.periodicSnapshotInterval = 30.0
        snapshotSettings.protectExistingSnapshot = true
        snapshotSettings.minimumWindowCount = 3
        snapshotSettings.enableSound = true
        snapshotSettings.soundName = "Blow"
        snapshotSettings.enableNotification = false
    }
    
    private func formatMinutes(_ minutes: Double) -> String {
        if minutes >= 60 {
            let hours = Int(minutes) / 60
            let mins = Int(minutes) % 60
            if mins == 0 {
                return "\(hours)時間"
            } else {
                return "\(hours)時間\(mins)分"
            }
        } else {
            if minutes == Double(Int(minutes)) {
                return "\(Int(minutes))分"
            } else {
                return String(format: "%.1f分", minutes)
            }
        }
    }
}
