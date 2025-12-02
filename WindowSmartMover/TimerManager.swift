import Foundation

/// Centralized timer management for Tsubame
/// Consolidates all timer and DispatchWorkItem handling in one place
/// for easier debugging and maintenance.
///
/// Usage note: All action closures should use [weak self] to avoid retain cycles.
///
/// Timer Groups:
/// - Snapshot Group: displayMemoryTimer, initialCaptureTimer, periodicCaptureTimer
/// - Display Change Group: stabilizationCheckTimer, restoreWorkItem, fallbackWorkItem
class TimerManager {
    static let shared = TimerManager()
    
    private init() {}
    
    // MARK: - Snapshot Group
    
    /// Timer for periodic window position recording (default: every 5 seconds)
    private var displayMemoryTimer: Timer?
    
    /// One-shot timer for initial snapshot after app launch or display connection
    private var initialCaptureTimer: Timer?
    
    /// Repeating timer for periodic auto-snapshot (user-configurable interval)
    private var periodicCaptureTimer: Timer?
    
    // MARK: - Display Change Group
    
    /// Polling timer to check display stabilization (every 0.5 seconds)
    private var stabilizationCheckTimer: Timer?
    
    /// Delayed task for window restoration
    private var restoreWorkItem: DispatchWorkItem?
    
    /// Fallback task if no display event occurs after stabilization
    private var fallbackWorkItem: DispatchWorkItem?
    
    // MARK: - Display Memory Timer
    
    /// Start periodic window position monitoring
    /// - Parameters:
    ///   - interval: Monitoring interval in seconds
    ///   - action: Action to perform on each tick (should capture self weakly)
    func startDisplayMemoryTimer(interval: TimeInterval, action: @escaping () -> Void) {
        stopDisplayMemoryTimer()
        
        let timer = Timer(timeInterval: interval, repeats: true) { _ in
            action()
        }
        RunLoop.main.add(timer, forMode: .common)
        displayMemoryTimer = timer
        
        logDebug("Display memory timer started (\(Int(interval))s interval)")
    }
    
    /// Stop display memory timer
    func stopDisplayMemoryTimer() {
        guard displayMemoryTimer != nil else { return }
        displayMemoryTimer?.invalidate()
        displayMemoryTimer = nil
    }
    
    /// Restart display memory timer with new interval
    /// - Parameters:
    ///   - interval: New monitoring interval in seconds
    ///   - action: Action to perform on each tick
    func restartDisplayMemoryTimer(interval: TimeInterval, action: @escaping () -> Void) {
        stopDisplayMemoryTimer()
        startDisplayMemoryTimer(interval: interval, action: action)
        logDebug("Display memory timer restarted (\(Int(interval))s interval)")
    }
    
    // MARK: - Initial Capture Timer
    
    /// Schedule initial snapshot capture after a delay
    /// - Parameters:
    ///   - delay: Delay in seconds before capture
    ///   - action: Action to perform when timer fires
    func scheduleInitialCapture(delay: TimeInterval, action: @escaping () -> Void) {
        cancelInitialCapture()
        
        let timer = Timer(timeInterval: delay, repeats: false) { _ in
            action()
        }
        RunLoop.main.add(timer, forMode: .common)
        initialCaptureTimer = timer
        
        logDebug("Initial capture scheduled (in \(String(format: "%.1f", delay / 60))min)")
    }
    
    /// Cancel pending initial capture
    func cancelInitialCapture() {
        guard initialCaptureTimer != nil else { return }
        initialCaptureTimer?.invalidate()
        initialCaptureTimer = nil
    }
    
    // MARK: - Periodic Capture Timer
    
    /// Start periodic auto-snapshot timer
    /// - Parameters:
    ///   - interval: Snapshot interval in seconds
    ///   - action: Action to perform on each tick
    func startPeriodicCapture(interval: TimeInterval, action: @escaping () -> Void) {
        stopPeriodicCapture()
        
        let timer = Timer(timeInterval: interval, repeats: true) { _ in
            action()
        }
        RunLoop.main.add(timer, forMode: .common)
        periodicCaptureTimer = timer
        
        logDebug("Periodic capture started (\(String(format: "%.0f", interval / 60))min interval)")
    }
    
    /// Stop periodic capture timer
    func stopPeriodicCapture() {
        guard periodicCaptureTimer != nil else { return }
        periodicCaptureTimer?.invalidate()
        periodicCaptureTimer = nil
    }
    
    /// Check if periodic capture is currently running
    var isPeriodicCaptureRunning: Bool {
        periodicCaptureTimer != nil
    }
    
    // MARK: - Stabilization Check Timer
    
    /// Start polling timer to check display stabilization
    /// - Parameter action: Action to perform on each tick (every 0.5 seconds)
    func startStabilizationCheck(action: @escaping () -> Void) {
        stopStabilizationCheck()
        
        let timer = Timer(timeInterval: 0.5, repeats: true) { _ in
            action()
        }
        RunLoop.main.add(timer, forMode: .common)
        stabilizationCheckTimer = timer
    }
    
    /// Stop stabilization check timer
    func stopStabilizationCheck() {
        guard stabilizationCheckTimer != nil else { return }
        stabilizationCheckTimer?.invalidate()
        stabilizationCheckTimer = nil
    }
    
    /// Check if stabilization check is currently running
    var isStabilizationCheckRunning: Bool {
        stabilizationCheckTimer != nil
    }
    
    // MARK: - Restore Task
    
    /// Schedule window restoration after a delay
    /// - Parameters:
    ///   - delay: Delay in seconds before restoration
    ///   - action: Action to perform when task executes
    ///
    /// Note: This method properly handles cancellation by checking `isCancelled`
    /// before executing the action, preventing duplicate executions.
    func scheduleRestore(delay: TimeInterval, action: @escaping () -> Void) {
        cancelRestore()
        
        var workItem: DispatchWorkItem!
        workItem = DispatchWorkItem {
            // Check cancellation flag to prevent execution if cancelled
            guard !workItem.isCancelled else {
                return
            }
            action()
        }
        restoreWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: workItem)
        
        logDebug("Restore scheduled (in \(String(format: "%.1f", delay))s)")
    }
    
    /// Cancel pending restoration
    func cancelRestore() {
        guard restoreWorkItem != nil else { return }
        restoreWorkItem?.cancel()
        restoreWorkItem = nil
    }
    
    // MARK: - Fallback Task
    
    /// Schedule fallback restoration if no display event occurs
    /// - Parameters:
    ///   - delay: Delay in seconds before fallback triggers
    ///   - action: Action to perform when task executes
    ///
    /// Note: This method properly handles cancellation by checking `isCancelled`
    /// before executing the action.
    func scheduleFallback(delay: TimeInterval, action: @escaping () -> Void) {
        cancelFallback()
        
        var workItem: DispatchWorkItem!
        workItem = DispatchWorkItem {
            // Check cancellation flag to prevent execution if cancelled
            guard !workItem.isCancelled else {
                return
            }
            action()
        }
        fallbackWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: workItem)
    }
    
    /// Cancel pending fallback
    func cancelFallback() {
        guard fallbackWorkItem != nil else { return }
        fallbackWorkItem?.cancel()
        fallbackWorkItem = nil
    }
    
    // MARK: - Lifecycle
    
    /// Stop all timers and cancel all pending tasks
    /// Should be called when app terminates
    func stopAllTimers() {
        stopDisplayMemoryTimer()
        cancelInitialCapture()
        stopPeriodicCapture()
        stopStabilizationCheck()
        cancelRestore()
        cancelFallback()
        
        logDebug("All timers stopped")
    }
    
    // MARK: - Debug Support
    
    /// List of currently active timer/task names for debugging
    var activeTimerNames: [String] {
        var names: [String] = []
        if displayMemoryTimer != nil { names.append("displayMemory") }
        if initialCaptureTimer != nil { names.append("initialCapture") }
        if periodicCaptureTimer != nil { names.append("periodicCapture") }
        if stabilizationCheckTimer != nil { names.append("stabilizationCheck") }
        if restoreWorkItem != nil { names.append("restore") }
        if fallbackWorkItem != nil { names.append("fallback") }
        return names
    }
    
    /// Debug description of active timers
    var statusDescription: String {
        let names = activeTimerNames
        if names.isEmpty {
            return "No active timers"
        }
        return "Active: \(names.joined(separator: ", "))"
    }
    
    // MARK: - Private Helpers
    
    /// Log debug message (uses DebugLogger if available)
    private func logDebug(_ message: String) {
        let formatted = "⏱️ [TimerManager] \(message)"
        print(formatted)
        DebugLogger.shared.addLog(formatted)
    }
}
