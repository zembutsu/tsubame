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
    
    private init() {
        // デフォルト値: ディスプレイ接続後の待機時間は2.5秒
        self.windowRestoreDelay = defaults.object(forKey: windowDelayKey) as? Double ?? 2.5
        // デフォルト値: ディスプレイ変更の落ち着き待ち時間は0.5秒
        self.displayStabilizationDelay = defaults.object(forKey: displayStabilizationKey) as? Double ?? 0.5
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
                    
                    Slider(value: $timingSettings.displayStabilizationDelay, in: 0.1...3.0, step: 0.1)
                    
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
                    
                    Slider(value: $timingSettings.windowRestoreDelay, in: 0.1...10.0, step: 0.1)
                    
                    Text("外部ディスプレイを接続した際に、macOSがウィンドウ座標を更新し終わるまでの待機時間です。ウィンドウが正しく復元されない場合は、この値を大きくしてください。")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
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
                    timingSettings.displayStabilizationDelay = 0.5
                    timingSettings.windowRestoreDelay = 2.5
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
        .frame(width: 500, height: 715)
    }
}
