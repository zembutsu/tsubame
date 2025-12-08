import SwiftUI
import Carbon
import Combine
import AppKit
import CryptoKit
import Security
import UserNotifications

// MARK: - Window Matching Data Structure

// MARK: - Language Settings
enum AppLanguage: String, CaseIterable {
    case system = "system"
    case english = "en"
    case japanese = "ja"
    
    var displayName: String {
        switch self {
        case .system: return NSLocalizedString("System Default", comment: "Language option")
        case .english: return "English"
        case .japanese: return "日本語"
        }
    }
}

class LanguageSettings: ObservableObject {
    static let shared = LanguageSettings()
    
    private let languageKey = "AppLanguage"
    
    @Published var selectedLanguage: AppLanguage {
        didSet {
            applyLanguage(selectedLanguage)
        }
    }
    
    private init() {
        // Load saved setting
        if let saved = UserDefaults.standard.string(forKey: languageKey),
           let language = AppLanguage(rawValue: saved) {
            self.selectedLanguage = language
        } else {
            self.selectedLanguage = .system
        }
    }
    
    private func applyLanguage(_ language: AppLanguage) {
        UserDefaults.standard.set(language.rawValue, forKey: languageKey)
        
        switch language {
        case .system:
            // Remove override, use system language
            UserDefaults.standard.removeObject(forKey: "AppleLanguages")
        case .english, .japanese:
            // Set specific language
            UserDefaults.standard.set([language.rawValue], forKey: "AppleLanguages")
        }
        
        UserDefaults.standard.synchronize()
    }
}

/// Salt manager for privacy-protected hashing
class HashSaltManager {
    static let shared = HashSaltManager()
    
    private let saltKey = "WindowMatchInfoSalt"
    private var cachedSalt: String?
    
    private init() {
        // Load or generate salt on first access
        _ = getSalt()
    }
    
    /// Get salt (generate if not exists)
    func getSalt() -> String {
        if let cached = cachedSalt {
            return cached
        }
        
        if let stored = UserDefaults.standard.string(forKey: saltKey) {
            cachedSalt = stored
            return stored
        }
        
        // Generate new random salt (32 bytes = 256 bits)
        var bytes = [UInt8](repeating: 0, count: 32)
        let status = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        
        let newSalt: String
        if status == errSecSuccess {
            newSalt = bytes.map { String(format: "%02x", $0) }.joined()
        } else {
            // Fallback: UUID-based (less secure but functional)
            newSalt = UUID().uuidString + UUID().uuidString
        }
        
        UserDefaults.standard.set(newSalt, forKey: saltKey)
        cachedSalt = newSalt
        return newSalt
    }
}

/// Window identification info (hashed for privacy protection)
struct WindowMatchInfo: Codable, Equatable {
    let appNameHash: String      // SHA256(salt + appName)
    let titleHash: String?       // SHA256(salt + title) - for matching
    let size: CGSize             // for fallback matching
    let frame: CGRect            // restore position
    
    /// Generate salted SHA256 hash
    static func hash(_ input: String) -> String {
        let salt = HashSaltManager.shared.getSalt()
        let saltedInput = salt + input
        let data = Data(saltedInput.utf8)
        let hash = SHA256.hash(data: data)
        return hash.compactMap { String(format: "%02x", $0) }.joined()
    }
    
    /// Create from window info
    init(appName: String, title: String?, size: CGSize, frame: CGRect) {
        self.appNameHash = WindowMatchInfo.hash(appName)
        self.titleHash = title.map { WindowMatchInfo.hash($0) }
        self.size = size
        self.frame = frame
    }
    
    /// Check if size is approximately equal (±20px tolerance)
    func sizeMatches(_ otherSize: CGSize, tolerance: CGFloat = 20) -> Bool {
        return abs(size.width - otherSize.width) <= tolerance &&
               abs(size.height - otherSize.height) <= tolerance
    }
}

// MARK: - Snapshot Slot Data Structure

/// Snapshot slot with metadata for future extensibility (Spaces support, etc.)
struct SnapshotSlot: Codable {
    let id: UUID
    var name: String?
    var windows: [String: [String: WindowMatchInfo]]  // [DisplayID][WindowKey]
    var createdAt: Date?
    var updatedAt: Date?
    var metadata: [String: String]  // Future: spaceID, displayConfig, etc.
    
    init(id: UUID = UUID(), name: String? = nil) {
        self.id = id
        self.name = name
        self.windows = [:]
        self.createdAt = nil
        self.updatedAt = nil
        self.metadata = [:]
    }
    
    var windowCount: Int {
        windows.values.reduce(0) { $0 + $1.count }
    }
    
    var isEmpty: Bool {
        windows.isEmpty || windows.values.allSatisfy { $0.isEmpty }
    }
}

class HotKeySettings: ObservableObject {
    static let shared = HotKeySettings()
    
    /// Notification posted when modifier keys change (hotkeys need re-registration)
    static let modifiersDidChangeNotification = Notification.Name("HotKeyModifiersDidChange")
    
    @Published var useControl: Bool {
        didSet {
            UserDefaults.standard.set(useControl, forKey: "useControl")
            notifyModifiersChanged()
        }
    }
    @Published var useOption: Bool {
        didSet {
            UserDefaults.standard.set(useOption, forKey: "useOption")
            notifyModifiersChanged()
        }
    }
    @Published var useShift: Bool {
        didSet {
            UserDefaults.standard.set(useShift, forKey: "useShift")
            notifyModifiersChanged()
        }
    }
    @Published var useCommand: Bool {
        didSet {
            UserDefaults.standard.set(useCommand, forKey: "useCommand")
            notifyModifiersChanged()
        }
    }
    
    /// Window nudge pixels (10-500, default 100)
    @Published var nudgePixels: Int {
        didSet { UserDefaults.standard.set(nudgePixels, forKey: "nudgePixels") }
    }
    
    /// Flag to prevent notification during initialization
    private var isInitialized = false
    
    private init() {
        // Default: Control + Command (changed in v1.2.7)
        self.useControl = UserDefaults.standard.object(forKey: "useControl") as? Bool ?? true
        self.useOption = UserDefaults.standard.object(forKey: "useOption") as? Bool ?? false
        self.useShift = UserDefaults.standard.object(forKey: "useShift") as? Bool ?? false
        self.useCommand = UserDefaults.standard.object(forKey: "useCommand") as? Bool ?? true
        // Default: 100 pixels
        self.nudgePixels = UserDefaults.standard.object(forKey: "nudgePixels") as? Int ?? 100
        
        isInitialized = true
    }
    
    private func notifyModifiersChanged() {
        guard isInitialized else { return }
        NotificationCenter.default.post(name: Self.modifiersDidChangeNotification, object: nil)
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

// WindowTimingSettings: Window loading timing settings
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
    
    /// Display memory monitoring interval (seconds): 1-30s, default 5s
    @Published var displayMemoryInterval: Double {
        didSet {
            defaults.set(displayMemoryInterval, forKey: displayMemoryIntervalKey)
            // Notify settings change
            NotificationCenter.default.post(
                name: Notification.Name("DisplayMemoryIntervalChanged"),
                object: nil
            )
        }
    }
    
    // Sleep monitoring related
    @Published var lastSleepTime: Date?
    @Published var lastWakeTime: Date?
    @Published var isMonitoringEnabled: Bool = true
    
    /// Sleep duration in hours (computed from lastSleepTime and lastWakeTime)
    var sleepDurationHours: Double {
        guard let sleep = lastSleepTime, let wake = lastWakeTime else { return 0 }
        return wake.timeIntervalSince(sleep) / 3600.0
    }
    
    private var sleepObserver: NSObjectProtocol?
    private var wakeObserver: NSObjectProtocol?
    
    private init() {
        // Default: Post-display-connection wait time is 6.0s
        self.windowRestoreDelay = defaults.object(forKey: windowDelayKey) as? Double ?? 6.0
        // Default: Display change stabilization wait time is 6.0s
        self.displayStabilizationDelay = defaults.object(forKey: displayStabilizationKey) as? Double ?? 6.0
        // Default: Enable monitoring pause during sleep
        self.disableMonitoringDuringSleep = defaults.object(forKey: disableMonitoringKey) as? Bool ?? true
        // Default: Display memory monitoring interval is 5.0s
        self.displayMemoryInterval = defaults.object(forKey: displayMemoryIntervalKey) as? Double ?? 5.0
        
        // Start sleep monitoring
        startSleepMonitoring()
    }
    
    // Start sleep monitoring
    private func startSleepMonitoring() {
        sleepObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.willSleepNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            guard let self = self else { return }
            self.lastSleepTime = Date()
            print("💤 System going to sleep at \(Date())")
            
            // Pause display monitoring during sleep
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
    
    // Wake handling
    private func handleWake() {
        lastWakeTime = Date()
        
        if let sleepTime = lastSleepTime {
            let duration = Date().timeIntervalSince(sleepTime)
            let hours = duration / 3600.0
            print("☀️ System woke from sleep after \(String(format: "%.2f", hours)) hours")
        }
        
        // If monitoring pause feature is enabled
        if disableMonitoringDuringSleep {
            print("⏱️ Waiting for display stabilization...")
            print("   Monitoring will resume automatically after stabilization")
            // Note: Monitoring resume is handled automatically by stabilization logic (AppDelegate)
            // Do nothing here = leave it to display change event stabilization
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

// SnapshotSettings: Auto snapshot settings
class SnapshotSettings: ObservableObject {
    static let shared = SnapshotSettings()
    
    private let defaults = UserDefaults.standard
    private let initialDelayKey = "snapshotInitialDelay"
    private let enablePeriodicKey = "snapshotEnablePeriodic"
    private let periodicIntervalKey = "snapshotPeriodicInterval"
    
    /// Initial snapshot delay (minutes): 0.5-60min, default 5min
    @Published var initialSnapshotDelay: Double {
        didSet {
            defaults.set(initialSnapshotDelay, forKey: initialDelayKey)
        }
    }
    
    /// Enable periodic snapshot
    @Published var enablePeriodicSnapshot: Bool {
        didSet {
            defaults.set(enablePeriodicSnapshot, forKey: enablePeriodicKey)
            // Notify settings change
            NotificationCenter.default.post(
                name: Notification.Name("SnapshotSettingsChanged"),
                object: nil
            )
        }
    }
    
    /// Periodic snapshot interval (minutes): 5-360min, default 30min
    @Published var periodicSnapshotInterval: Double {
        didSet {
            defaults.set(periodicSnapshotInterval, forKey: periodicIntervalKey)
            // Notify settings change
            NotificationCenter.default.post(
                name: Notification.Name("SnapshotSettingsChanged"),
                object: nil
            )
        }
    }
    
    /// Protect existing snapshot (don't overwrite if window count is low)
    @Published var protectExistingSnapshot: Bool {
        didSet {
            defaults.set(protectExistingSnapshot, forKey: protectExistingKey)
        }
    }
    
    /// Minimum window count for protection
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
    private let restoreOnLaunchKey = "snapshotRestoreOnLaunch"
    private let showMillisecondsKey = "debugShowMilliseconds"
    private let maskAppNamesKey = "debugMaskAppNames"
    
    /// Available system sounds
    static let availableSounds = [
        "Blow", "Bottle", "Frog", "Funk", "Glass",
        "Hero", "Morse", "Ping", "Pop", "Purr",
        "Sosumi", "Submarine", "Tink"
    ]
    
    /// Enable sound notification
    @Published var enableSound: Bool {
        didSet {
            defaults.set(enableSound, forKey: enableSoundKey)
        }
    }
    
    /// Notification sound name
    @Published var soundName: String {
        didSet {
            defaults.set(soundName, forKey: soundNameKey)
        }
    }
    
    /// Enable system notification
    @Published var enableNotification: Bool {
        didSet {
            defaults.set(enableNotification, forKey: enableNotificationKey)
        }
    }
    
    /// Auto-restore on app launch
    @Published var restoreOnLaunch: Bool {
        didSet {
            defaults.set(restoreOnLaunch, forKey: restoreOnLaunchKey)
        }
    }
    
    /// Don't persist snapshots (privacy protection mode)
    @Published var disablePersistence: Bool {
        didSet {
            defaults.set(disablePersistence, forKey: disablePersistenceKey)
            // Clear existing data when enabled
            if disablePersistence {
                ManualSnapshotStorage.shared.clear()
            }
        }
    }
    
    /// Output verbose logs (for debugging)
    @Published var verboseLogging: Bool {
        didSet {
            defaults.set(verboseLogging, forKey: verboseLoggingKey)
        }
    }
    
    /// Show milliseconds in logs
    @Published var showMilliseconds: Bool {
        didSet {
            defaults.set(showMilliseconds, forKey: showMillisecondsKey)
        }
    }
    
    /// Mask app names in logs (privacy protection)
    @Published var maskAppNamesInLog: Bool {
        didSet {
            defaults.set(maskAppNamesInLog, forKey: maskAppNamesKey)
            // Clear mapping when setting changes
            DebugLogger.shared.clearAppNameMapping()
        }
    }
    
    private init() {
        self.initialSnapshotDelay = defaults.object(forKey: initialDelayKey) as? Double ?? 15.0
        self.enablePeriodicSnapshot = defaults.object(forKey: enablePeriodicKey) as? Bool ?? false
        self.periodicSnapshotInterval = defaults.object(forKey: periodicIntervalKey) as? Double ?? 30.0
        self.protectExistingSnapshot = defaults.object(forKey: protectExistingKey) as? Bool ?? true
        self.minimumWindowCount = defaults.object(forKey: minimumWindowCountKey) as? Int ?? 3
        self.enableSound = defaults.object(forKey: enableSoundKey) as? Bool ?? false
        self.soundName = defaults.object(forKey: soundNameKey) as? String ?? "Blow"
        self.enableNotification = defaults.object(forKey: enableNotificationKey) as? Bool ?? false
        self.disablePersistence = defaults.object(forKey: disablePersistenceKey) as? Bool ?? false
        self.verboseLogging = defaults.object(forKey: verboseLoggingKey) as? Bool ?? false
        self.restoreOnLaunch = defaults.object(forKey: restoreOnLaunchKey) as? Bool ?? false
        self.showMilliseconds = defaults.object(forKey: showMillisecondsKey) as? Bool ?? false
        self.maskAppNamesInLog = defaults.object(forKey: maskAppNamesKey) as? Bool ?? true
    }
    
    /// Preview sound playback
    func previewSound() {
        NSSound(named: NSSound.Name(soundName))?.play()
    }
    
    /// Get initial delay in seconds
    var initialDelaySeconds: Double {
        return initialSnapshotDelay * 60.0
    }
    
    /// Get periodic interval in seconds
    var periodicIntervalSeconds: Double {
        return periodicSnapshotInterval * 60.0
    }
}

// ManualSnapshotStorage: Snapshot persistence with multiple slots support
class ManualSnapshotStorage {
    static let shared = ManualSnapshotStorage()
    
    private let defaults = UserDefaults.standard
    private let storageKeyV3 = "manualSnapshotDataV3"  // New SnapshotSlot format
    private let storageKeyV2 = "manualSnapshotDataV2"  // Previous format (for migration)
    private let timestampKey = "manualSnapshotTimestamp"  // Legacy, kept for compatibility
    private let legacyStorageKey = "manualSnapshotData"  // Old format (for migration)
    private let activeSlotKey = "activeSnapshotSlot"  // Currently selected slot (1-4)
    
    /// Number of slots (Slot 0 = auto, Slot 1-5 = manual)
    let slotCount = 6
    
    private init() {
        // Remove legacy format data if exists
        if defaults.data(forKey: legacyStorageKey) != nil {
            defaults.removeObject(forKey: legacyStorageKey)
            debugPrint("🔄 Removed legacy snapshot data (v1 migration)")
        }
        
        // Migrate from V2 to V3 if needed
        migrateV2ToV3IfNeeded()
    }
    
    /// Migrate from V2 (array of dictionaries) to V3 (SnapshotSlot array)
    private func migrateV2ToV3IfNeeded() {
        guard let v2Data = defaults.data(forKey: storageKeyV2) else { return }
        guard defaults.data(forKey: storageKeyV3) == nil else { return }  // Already migrated
        
        do {
            let v2Snapshots = try JSONDecoder().decode([[String: [String: WindowMatchInfo]]].self, from: v2Data)
            
            // Convert to SnapshotSlot format
            var slots: [SnapshotSlot] = []
            for (index, windows) in v2Snapshots.enumerated() {
                var slot = SnapshotSlot(name: index == 0 ? "Auto" : nil)
                slot.windows = windows
                if !windows.isEmpty {
                    // Use legacy timestamp for first non-empty slot
                    if let timestamp = defaults.object(forKey: timestampKey) as? Double {
                        slot.updatedAt = Date(timeIntervalSince1970: timestamp)
                    }
                }
                slots.append(slot)
            }
            
            // Ensure we have exactly slotCount slots
            while slots.count < slotCount {
                slots.append(SnapshotSlot())
            }
            
            // Save in V3 format
            let v3Data = try JSONEncoder().encode(slots)
            defaults.set(v3Data, forKey: storageKeyV3)
            
            // Remove V2 data after successful migration
            defaults.removeObject(forKey: storageKeyV2)
            defaults.removeObject(forKey: timestampKey)
            
            debugPrint("🔄 Migrated snapshot data from V2 to V3 (SnapshotSlot format)")
        } catch {
            debugPrint("❌ V2 to V3 migration failed: \(error.localizedDescription)")
        }
    }
    
    /// Get active slot index (1-5 for manual slots)
    var activeSlotIndex: Int {
        get {
            let saved = defaults.integer(forKey: activeSlotKey)
            // Ensure it's within valid range (1-4)
            return (saved >= 1 && saved < slotCount) ? saved : 1
        }
        set {
            // Ensure it's within valid range (1-4)
            let validIndex = (newValue >= 1 && newValue < slotCount) ? newValue : 1
            defaults.set(validIndex, forKey: activeSlotKey)
        }
    }
    
    /// Save all slots (SnapshotSlot format)
    func saveSlots(_ slots: [SnapshotSlot]) {
        // Skip if persistence is disabled
        if SnapshotSettings.shared.disablePersistence {
            debugPrint("🔒 Persistence disabled: Snapshot not saved")
            return
        }
        
        do {
            let data = try JSONEncoder().encode(slots)
            defaults.set(data, forKey: storageKeyV3)
            debugPrint("💾 Snapshot slots persisted (\(slots.count) slots)")
        } catch {
            debugPrint("❌ Failed to encode snapshot slots: \(error.localizedDescription)")
            sendErrorNotification(
                title: NSLocalizedString("Snapshot Save Failed", comment: "Error notification title"),
                body: String(format: NSLocalizedString("Failed to save snapshot data: %@", comment: "Error notification body"), error.localizedDescription)
            )
        }
    }
    
    /// Load all slots (SnapshotSlot format)
    func loadSlots() -> [SnapshotSlot]? {
        guard let data = defaults.data(forKey: storageKeyV3) else {
            return nil
        }
        
        do {
            let slots = try JSONDecoder().decode([SnapshotSlot].self, from: data)
            // Note: No log here as this method is called frequently (e.g., menu updates)
            return slots
        } catch {
            debugPrint("❌ Failed to decode snapshot slots: \(error.localizedDescription)")
            return nil
        }
    }
    
    /// Legacy save method (for backward compatibility during transition)
    func save(_ snapshots: [[String: [String: WindowMatchInfo]]]) {
        // Load existing slots to preserve timestamps
        let existingSlots = loadSlots() ?? []
        
        var slots: [SnapshotSlot] = []
        for (index, windows) in snapshots.enumerated() {
            var slot: SnapshotSlot
            
            if index < existingSlots.count {
                slot = existingSlots[index]
                // Only update timestamp if windows data changed
                let existingWindows = slot.windows
                let windowsChanged = existingWindows != windows
                
                slot.windows = windows
                if windowsChanged && !windows.isEmpty {
                    slot.updatedAt = Date()
                } else if windows.isEmpty {
                    slot.updatedAt = nil
                }
            } else {
                slot = SnapshotSlot(name: index == 0 ? "Auto" : nil)
                slot.windows = windows
                if !windows.isEmpty {
                    slot.updatedAt = Date()
                }
            }
            slots.append(slot)
        }
        
        // Ensure we have exactly slotCount slots
        while slots.count < slotCount {
            slots.append(SnapshotSlot())
        }
        
        saveSlots(slots)
    }
    
    /// Legacy load method (for backward compatibility during transition)
    func load() -> [[String: [String: WindowMatchInfo]]]? {
        guard let slots = loadSlots() else { return nil }
        return slots.map { $0.windows }
    }
    
    /// Get timestamp for a specific slot
    func getTimestamp(for slotIndex: Int) -> Date? {
        guard let slots = loadSlots(), slotIndex < slots.count else { return nil }
        return slots[slotIndex].updatedAt
    }
    
    /// Legacy getTimestamp (returns active slot timestamp)
    func getTimestamp() -> Date? {
        return getTimestamp(for: activeSlotIndex)
    }
    
    /// Get slot info for display
    func getSlotInfo(for slotIndex: Int) -> (windowCount: Int, updatedAt: Date?)? {
        guard let slots = loadSlots(), slotIndex < slots.count else { return nil }
        let slot = slots[slotIndex]
        return (slot.windowCount, slot.updatedAt)
    }
    
    /// Clear all snapshots
    func clear() {
        defaults.removeObject(forKey: storageKeyV3)
        defaults.removeObject(forKey: storageKeyV2)
        defaults.removeObject(forKey: timestampKey)
        debugPrint("🗑️ Persisted snapshot cleared")
    }
    
    /// Clear specific slot
    func clearSlot(_ slotIndex: Int) {
        guard var slots = loadSlots(), slotIndex < slots.count else { return }
        slots[slotIndex] = SnapshotSlot()
        saveSlots(slots)
        debugPrint("🗑️ Slot \(slotIndex) cleared")
    }
    
    /// Send error notification to user
    private func sendErrorNotification(title: String, body: String) {
        guard SnapshotSettings.shared.enableNotification else { return }
        
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        
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
    
    /// Check if any snapshot exists (excluding auto slot)
    var hasSnapshot: Bool {
        guard let slots = loadSlots() else { return false }
        // Check slots 1-4 (manual slots)
        for i in 1..<slots.count {
            if !slots[i].isEmpty {
                return true
            }
        }
        return false
    }
    
    /// Check if specific slot has data
    func hasSnapshot(for slotIndex: Int) -> Bool {
        guard let slots = loadSlots(), slotIndex < slots.count else { return false }
        return !slots[slotIndex].isEmpty
    }
}

struct SettingsView: View {
    @ObservedObject var settings = HotKeySettings.shared
    @ObservedObject var timingSettings = WindowTimingSettings.shared
    @ObservedObject var snapshotSettings = SnapshotSettings.shared
    @ObservedObject var languageSettings = LanguageSettings.shared
    @Environment(\.dismiss) var dismiss
    @State private var selectedTab = 0
    @State private var languageChanged = false
    @State private var initialLanguage: AppLanguage = .system
    
    var body: some View {
        VStack(spacing: 16) {
            Text(NSLocalizedString("Settings", comment: "Settings window title"))
                .font(.title)
                .padding(.top)
            
            // Tab selection
            Picker("", selection: $selectedTab) {
                Text("Basic").tag(0)
                Text("Advanced").tag(1)
            }
            .pickerStyle(.segmented)
            .padding(.horizontal)
            
            // Tab content
            ScrollView {
                if selectedTab == 0 {
                    basicSettingsContent
                } else {
                    advancedSettingsContent
                }
            }
            
            Divider()
            
            // Footer
            HStack {
                Button(NSLocalizedString("Reset to Defaults", comment: "Button to reset settings")) {
                    resetToDefaults()
                }
                
                Spacer()
                
                if languageChanged {
                    HStack(spacing: 8) {
                        Text(NSLocalizedString("🔄 Language change requires restart", comment: "Restart warning for language"))
                            .font(.caption)
                            .foregroundColor(.orange)
                        
                        Button(NSLocalizedString("Restart Now", comment: "Button to restart app")) {
                            restartApp()
                        }
                        .controlSize(.small)
                    }
                    
                    Spacer()
                }
                
                Button(NSLocalizedString("Close", comment: "Button to close window")) {
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
            }
            .padding(.horizontal)
            .padding(.bottom)
        }
        .padding()
        .frame(width: 520, height: 620)
        .onAppear {
            initialLanguage = languageSettings.selectedLanguage
        }
    }
    
    // MARK: - Basic Settings Tab
    
    private var basicSettingsContent: some View {
        VStack(spacing: 16) {
            // Language (requires restart)
            GroupBox(label: HStack {
                Text(NSLocalizedString("Language", comment: ""))
                Text("🔄")
                    .help(NSLocalizedString("Requires app restart", comment: "Tooltip for restart required"))
            }.font(.headline)) {
                HStack {
                    Picker(NSLocalizedString("Display Language:", comment: ""), selection: $languageSettings.selectedLanguage) {
                        ForEach(AppLanguage.allCases, id: \.self) { language in
                            Text(language.displayName).tag(language)
                        }
                    }
                    .pickerStyle(.menu)
                    .onChange(of: languageSettings.selectedLanguage) { oldValue, newValue in
                        languageChanged = (newValue != initialLanguage)
                    }
                    
                    Spacer()
                }
                .padding(.vertical, 4)
            }
            .padding(.horizontal)
            
            // Shortcut keys
            GroupBox(label: Text(NSLocalizedString("Shortcut Keys", comment: "")).font(.headline)) {
                VStack(alignment: .leading, spacing: 10) {
                    Text(NSLocalizedString("Select modifier keys:", comment: ""))
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
                    
                    // Current shortcuts
                    HStack(spacing: 30) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(NSLocalizedString("Move between screens:", comment: ""))
                                .font(.caption)
                                .foregroundColor(.secondary)
                            HStack {
                                Text("\(settings.getModifierString())→←")
                                    .font(.system(.body, design: .monospaced))
                                    .foregroundColor(.blue)
                            }
                        }
                        VStack(alignment: .leading, spacing: 4) {
                            Text(NSLocalizedString("Snapshot:", comment: ""))
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
            
            // Window position adjustment
            GroupBox(label: Text(NSLocalizedString("Window Position Adjustment", comment: "")).font(.headline)) {
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
                            Text(NSLocalizedString("Move amount:", comment: ""))
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
            
            // Auto Snapshot
            GroupBox(label: Text(NSLocalizedString("Auto Snapshot", comment: "")).font(.headline)) {
                VStack(alignment: .leading, spacing: 10) {
                    Toggle(NSLocalizedString("Auto-restore on app launch", comment: ""), isOn: $snapshotSettings.restoreOnLaunch)
                    
                    Text(NSLocalizedString("Restores saved snapshot when the app starts", comment: ""))
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    Divider()
                    
                    HStack {
                        Text(NSLocalizedString("Initial capture delay:", comment: ""))
                            .font(.subheadline)
                        Spacer()
                        Stepper(value: $snapshotSettings.initialSnapshotDelay, in: 0.5...60.0, step: 0.5) {
                            Text(formatMinutes(snapshotSettings.initialSnapshotDelay))
                                .foregroundColor(.blue)
                                .fontWeight(.semibold)
                                .frame(width: 65, alignment: .trailing)
                        }
                    }
                    
                    Toggle(NSLocalizedString("Periodic auto-capture", comment: ""), isOn: $snapshotSettings.enablePeriodicSnapshot)
                    
                    if snapshotSettings.enablePeriodicSnapshot {
                        HStack {
                            Text(NSLocalizedString("Capture interval:", comment: ""))
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
                    
                    Toggle(NSLocalizedString("Protect existing data", comment: ""), isOn: $snapshotSettings.protectExistingSnapshot)
                    
                    if snapshotSettings.protectExistingSnapshot {
                        HStack {
                            Text(NSLocalizedString("Minimum windows:", comment: ""))
                                .font(.caption)
                                .foregroundColor(.secondary)
                            Stepper(value: $snapshotSettings.minimumWindowCount, in: 1...10) {
                                Text("\(snapshotSettings.minimumWindowCount)")
                                    .foregroundColor(.blue)
                                    .frame(width: 25, alignment: .trailing)
                            }
                            Text(NSLocalizedString("(skip if fewer)", comment: ""))
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                    
                    Divider()
                    
                    // Privacy settings
                    Text(NSLocalizedString("Privacy", comment: ""))
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    Toggle(NSLocalizedString("Don't persist snapshots", comment: ""), isOn: $snapshotSettings.disablePersistence)
                    
                    Text(NSLocalizedString("When enabled, all data is cleared on app quit", comment: ""))
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    Divider()
                    
                    // Notification settings
                    Text(NSLocalizedString("Notifications", comment: ""))
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    HStack {
                        Toggle(NSLocalizedString("Sound", comment: ""), isOn: $snapshotSettings.enableSound)
                        Toggle(NSLocalizedString("System notification", comment: ""), isOn: $snapshotSettings.enableNotification)
                    }
                    
                    if snapshotSettings.enableSound {
                        HStack {
                            Text(NSLocalizedString("Sound:", comment: ""))
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
                            .help(NSLocalizedString("Preview sound", comment: ""))
                        }
                    }
                    
                    Divider()
                    
                    // Debug settings
                    Text(NSLocalizedString("Debug", comment: ""))
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    Toggle(NSLocalizedString("Verbose logging", comment: ""), isOn: $snapshotSettings.verboseLogging)

                    Toggle(NSLocalizedString("Show milliseconds", comment: ""), isOn: $snapshotSettings.showMilliseconds)
                    
                    Toggle(NSLocalizedString("Mask app names", comment: ""), isOn: $snapshotSettings.maskAppNamesInLog)

                    Text(NSLocalizedString("Outputs detailed info during snapshot save/restore", comment: ""))
                        .font(.caption)
                        .foregroundColor(.secondary)

                    Divider()
                    
                    // Saved status
                    HStack {
                        if let timestamp = ManualSnapshotStorage.shared.getTimestamp() {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundColor(.green)
                            Text(String(format: NSLocalizedString("Last saved: %@", comment: ""), timestamp.formatted(date: .abbreviated, time: .shortened)))
                                .font(.caption)
                                .foregroundColor(.secondary)
                        } else {
                            Image(systemName: "xmark.circle")
                                .foregroundColor(.orange)
                            Text(NSLocalizedString("No saved data", comment: ""))
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        
                        Spacer()
                        
                        Button(NSLocalizedString("Clear", comment: "")) {
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
            // Window restore timing
            GroupBox(label: Text(NSLocalizedString("Window Restore Timing", comment: "")).font(.headline)) {
                VStack(alignment: .leading, spacing: 12) {
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text(NSLocalizedString("Display change stabilization time:", comment: ""))
                                .font(.subheadline)
                            Spacer()
                            Text(String(format: NSLocalizedString("%.1fs", comment: "seconds"), timingSettings.displayStabilizationDelay))
                                .foregroundColor(.blue)
                                .fontWeight(.semibold)
                        }
                        Slider(value: $timingSettings.displayStabilizationDelay, in: 0.1...15.0, step: 0.1)
                        Text(NSLocalizedString("Wait time for display change events to settle", comment: ""))
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    
                    Divider()
                    
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text(NSLocalizedString("Post-connection delay:", comment: ""))
                                .font(.subheadline)
                            Spacer()
                            Text(String(format: NSLocalizedString("%.1fs", comment: "seconds"), timingSettings.windowRestoreDelay))
                                .foregroundColor(.blue)
                                .fontWeight(.semibold)
                        }
                        Slider(value: $timingSettings.windowRestoreDelay, in: 0.1...15.0, step: 0.1)
                        Text(NSLocalizedString("Wait for macOS to finish updating window coordinates", comment: ""))
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    
                    Divider()
                    
                    HStack {
                        Text(NSLocalizedString("Window position monitoring interval:", comment: ""))
                            .font(.subheadline)
                        Spacer()
                        Stepper(value: $timingSettings.displayMemoryInterval, in: 1.0...30.0, step: 1.0) {
                            Text(String(format: NSLocalizedString("%ds", comment: "seconds"), Int(timingSettings.displayMemoryInterval)))
                                .foregroundColor(.blue)
                                .fontWeight(.semibold)
                                .frame(width: 45, alignment: .trailing)
                        }
                    }
                    Text(NSLocalizedString("For auto-restore on display reconnection", comment: ""))
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .padding(.vertical, 8)
            }
            
            // Sleep behavior
            GroupBox(label: Text(NSLocalizedString("Sleep Behavior", comment: "")).font(.headline)) {
                VStack(alignment: .leading, spacing: 10) {
                    Toggle(NSLocalizedString("Pause display monitoring during sleep", comment: ""), isOn: $timingSettings.disableMonitoringDuringSleep)
                    
                    Text(NSLocalizedString("Ignores display change events during sleep", comment: ""))
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    Divider()
                    
                    HStack {
                        Text(NSLocalizedString("Monitoring status:", comment: ""))
                            .font(.caption)
                        Text(timingSettings.isMonitoringEnabled ? NSLocalizedString("Active", comment: "") : NSLocalizedString("Paused", comment: ""))
                            .font(.caption)
                            .foregroundColor(timingSettings.isMonitoringEnabled ? .green : .orange)
                    }
                    
                    // Sleep debug info
                    if timingSettings.sleepDurationHours > 0 {
                        HStack {
                            Text(NSLocalizedString("Last sleep:", comment: ""))
                                .font(.caption)
                            Text(String(format: NSLocalizedString("%.1f hours", comment: "hours with decimal"), timingSettings.sleepDurationHours))
                                .font(.caption)
                                .foregroundColor(.blue)
                        }
                    }
                    
                    if let wakeTime = timingSettings.lastWakeTime {
                        HStack {
                            Text(NSLocalizedString("Last wake:", comment: ""))
                                .font(.caption)
                            Text(wakeTime.formatted(date: .omitted, time: .shortened))
                                .font(.caption)
                                .foregroundColor(.blue)
                        }
                    }
                }
                .padding(.vertical, 8)
            }
        }
        .padding(.horizontal)
    }
    
    // MARK: - Helper Functions
    
    private func restartApp() {
        let url = URL(fileURLWithPath: Bundle.main.resourcePath!)
        let path = url.deletingLastPathComponent().deletingLastPathComponent().absoluteString
        let task = Process()
        task.launchPath = "/usr/bin/open"
        task.arguments = [path]
        task.launch()
        
        NSApplication.shared.terminate(nil)
    }
    
    private func resetToDefaults() {
        settings.useControl = true
        settings.useOption = false
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
        snapshotSettings.enableSound = false
        snapshotSettings.soundName = "Blow"
        snapshotSettings.enableNotification = false
        snapshotSettings.restoreOnLaunch = false
        snapshotSettings.showMilliseconds = false
        snapshotSettings.maskAppNamesInLog = true
    }
    
    private func formatMinutes(_ minutes: Double) -> String {
        if minutes >= 60 {
            let hours = Int(minutes) / 60
            let mins = Int(minutes) % 60
            if mins == 0 {
                return String(format: NSLocalizedString("%dh", comment: "hours"), hours)
            } else {
                return String(format: NSLocalizedString("%dh %dm", comment: "hours and minutes"), hours, mins)
            }
        } else {
            if minutes == Double(Int(minutes)) {
                return String(format: NSLocalizedString("%dm", comment: "minutes"), Int(minutes))
            } else {
                return String(format: NSLocalizedString("%.1fm", comment: "minutes with decimal"), minutes)
            }
        }
    }
}
