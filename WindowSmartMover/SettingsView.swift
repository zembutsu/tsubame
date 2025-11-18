import SwiftUI
import Carbon
import Combine

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
    
    private init() {
        // デフォルト値: Ctrl + Option + Command
        self.useControl = UserDefaults.standard.object(forKey: "useControl") as? Bool ?? true
        self.useOption = UserDefaults.standard.object(forKey: "useOption") as? Bool ?? true
        self.useShift = UserDefaults.standard.object(forKey: "useShift") as? Bool ?? false
        self.useCommand = UserDefaults.standard.object(forKey: "useCommand") as? Bool ?? true
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

struct SettingsView: View {
    @ObservedObject var settings = HotKeySettings.shared
    @ObservedObject var timingSettings = WindowTimingSettings.shared
    @Environment(\.dismiss) var dismiss
    
    var body: some View {
        VStack(spacing: 20) {
            Text("設定")
                .font(.title)
                .padding(.top)
            
            // ショートカットキー設定セクション
            VStack(alignment: .leading, spacing: 12) {
                Text("ショートカットキー")
                    .font(.headline)
                
                Text("修飾キーを選択してください：")
                    .font(.subheadline)
                
                Toggle("⌃ Control", isOn: $settings.useControl)
                Toggle("⌥ Option", isOn: $settings.useOption)
                Toggle("⇧ Shift", isOn: $settings.useShift)
                Toggle("⌘ Command", isOn: $settings.useCommand)
            }
            .padding()
            .background(Color.gray.opacity(0.1))
            .cornerRadius(8)
            
            VStack(alignment: .leading, spacing: 8) {
                Text("現在のショートカット：")
                    .font(.subheadline)
                HStack {
                    Text("\(settings.getModifierString())→")
                        .font(.title2)
                        .foregroundColor(.blue)
                    Text("次の画面へ")
                        .font(.body)
                }
                HStack {
                    Text("\(settings.getModifierString())←")
                        .font(.title2)
                        .foregroundColor(.blue)
                    Text("前の画面へ")
                        .font(.body)
                }
            }
            .padding()
            
            // ウィンドウ復元タイミング設定セクション
            VStack(alignment: .leading, spacing: 12) {
                Text("ウィンドウ復元タイミング")
                    .font(.headline)
                
                // ディスプレイ変更の落ち着き待ち時間
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("ディスプレイ変更検出の安定化時間:")
                            .font(.subheadline)
                        Spacer()
                        Text(String(format: "%.1f秒", timingSettings.displayStabilizationDelay))
                            .foregroundColor(.blue)
                            .fontWeight(.semibold)
                    }
                    
                    Slider(value: $timingSettings.displayStabilizationDelay, in: 0.1...15.0, step: 0.1)
                    
                    Text("サスペンド復帰時など、ディスプレイ変更イベントが連続して発生した際に、変更が落ち着くまで待つ時間です。復元処理が早すぎる場合は、この値を大きくしてください。")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.bottom, 8)
                
                Divider()
                
                // ディスプレイ接続後の待機時間
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("ディスプレイ接続後の待機時間:")
                            .font(.subheadline)
                        Spacer()
                        Text(String(format: "%.1f秒", timingSettings.windowRestoreDelay))
                            .foregroundColor(.blue)
                            .fontWeight(.semibold)
                    }
                    
                    Slider(value: $timingSettings.windowRestoreDelay, in: 0.1...15.0, step: 0.1)
                    
                    Text("外部ディスプレイを接続した際に、macOSがウィンドウ座標を更新し終わるまでの待機時間です。ウィンドウが正しく復元されない場合は、この値を大きくしてください。")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding()
            .background(Color.gray.opacity(0.1))
            .cornerRadius(8)
            
            // スリープ情報セクション（デバッグ）
            VStack(alignment: .leading, spacing: 12) {
                Text("スリープ時の動作設定")
                    .font(.headline)
                
                Toggle("スリープ中はディスプレイ監視を一時停止", isOn: $timingSettings.disableMonitoringDuringSleep)
                    .toggleStyle(SwitchToggleStyle())
                
                Text("有効にすると、スリープ中に発生するディスプレイ変更イベントを無視します。Dock位置ずれ問題の軽減に役立つ可能性があります。")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.bottom, 8)
                
                Divider()
                
                Text("デバッグ情報")
                    .font(.subheadline)
                    .fontWeight(.semibold)
                
                if timingSettings.sleepDurationHours > 0 {
                    HStack {
                        Text("前回のスリープ:")
                            .font(.subheadline)
                        Spacer()
                        Text(String(format: "%.2f時間", timingSettings.sleepDurationHours))
                            .foregroundColor(.blue)
                            .fontWeight(.semibold)
                    }
                    
                    HStack {
                        Text("調整後の待機時間:")
                            .font(.subheadline)
                        Spacer()
                        Text(String(format: "%.1f秒", timingSettings.getAdjustedDisplayDelay()))
                            .foregroundColor(.green)
                            .fontWeight(.semibold)
                    }
                    
                    HStack {
                        Text("監視状態:")
                            .font(.subheadline)
                        Spacer()
                        Text(timingSettings.isMonitoringEnabled ? "有効" : "一時停止中")
                            .foregroundColor(timingSettings.isMonitoringEnabled ? .green : .orange)
                            .fontWeight(.semibold)
                    }
                    
                    if let wakeTime = timingSettings.lastWakeTime {
                        Text("最終復帰: \(wakeTime.formatted(date: .omitted, time: .standard))")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                } else {
                    Text("スリープ情報なし")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
            }
            .padding()
            .background(Color.gray.opacity(0.1))
            .cornerRadius(8)
            
            Text("⚠️ 設定を変更したらアプリを再起動してください")
                .font(.caption)
                .foregroundColor(.orange)
            
            HStack {
                Button("デフォルトに戻す") {
                    settings.useControl = true
                    settings.useOption = true
                    settings.useShift = false
                    settings.useCommand = true
                    timingSettings.displayStabilizationDelay = 6.0
                    timingSettings.windowRestoreDelay = 6.0
                    timingSettings.disableMonitoringDuringSleep = true
                }
                
                Spacer()
                
                Button("閉じる") {
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
            }
            .padding(.bottom)
        }
        .padding()
        .frame(width: 500, height: 980)
    }
}
