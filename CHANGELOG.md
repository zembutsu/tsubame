# Changelog

All notable changes to Tsubame will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Planned: v1.3.0 (Stable Release)
- Stability improvements and bug fixes based on v1.2.x feedback
- Documentation finalization

### Planned: Future
- App Store release (requires separate investigation - see #49)

## [1.2.14] - 2025-12-20

### Added
- **Pause/Lock feature** (#70)
  - Temporarily disable all Tsubame functions during intentional display input switching
  - Prevents chaotic window movement when using KVM switches or toggling display inputs
  - Duration options: 15 minutes, 1 hour, 6 hours, or until manual resume
  - Hotkey: `⌃⌘P` to toggle pause (always active, even when paused)
  - Menu bar icon changes to pause indicator when paused
  - Settings for pause behavior:
    - Resume on app relaunch (default: ON)
    - Resume on wake from sleep (default: OFF)
  - Pause state persists across sleep/wake cycles
- **Homebrew tap distribution**
  - Install via `brew tap zembutsu/tsubame && brew install --cask tsubame`
  - Official tap repository: [zembutsu/homebrew-tsubame](https://github.com/zembutsu/homebrew-tsubame)

### Fixed
- **Consistent use of Slot 0 for auto-snapshot** (#64)
  - Auto-snapshot operations now correctly use Slot 0 (internal auto-snapshot slot)
  - Previously some code paths incorrectly used `currentSlotIndex` instead of hardcoded `0`
  - Ensures manual snapshot slots (1-5) are never overwritten by auto-snapshot

## [1.2.13] - 2025-12-14

### Changed
- **Architecture refactoring** (#47 Phase 2-4)
  - Unified monitoring flag management (single source of truth)
  - Unified snapshot data to manualSnapshots[0] (fixes data loss on app restart)
  - Made pauseMonitoring() idempotent (fixes duplicate log on sleep)
  - Extracted timing constants for maintainability

### Added
- **Project documentation**
  - ARCHITECTURE.md: Technical structure and data flow
  - PROJECT.md: Entry point for developers and systems

### Fixed
- **AXUIElement position mismatch after long sleep** (#50)
  - Window restoration failed when CGWindowID matched but position coordinates diverged
  - Changed to size-based matching (10px tolerance) when CGWindowID exact match succeeds
  - Position matching remains as fallback for non-CGWindowID cases
- **Monitoring flag not restored on wake** (#54)
  - `WindowTimingSettings.isMonitoringEnabled` was set false on sleep but never restored
  - Added restoration in `checkStabilization()` alongside `isDisplayMonitoringEnabled`
  - Prevents permanent "snapshot skipped (monitoring disabled)" state
- **Phantom display IDs at login screen** (#56)
  - Added `isUserLoggedIn()` check using `SCDynamicStoreCopyConsoleUser`
  - Guards `displayConfigurationChanged()`, `takeWindowSnapshot()`, and `restoreWindowsIfNeeded()`
  - Prevents data corruption from login screen display IDs
- **Window restore fails after app restart during sleep** (#56)
  - `windowPositions` (memory-only) was lost on app restart
  - Phase 3 unified data to `manualSnapshots[0]` (persisted), eliminating this issue

## [1.2.12] - 2025-12-12 

### Added
- **Display sleep/wake handling** (#47 Phase 1)
  - Added `screensDidSleepNotification` observer to pause monitoring when display sleeps
  - Added `screensDidWakeNotification` observer to resume monitoring when display wakes
  - Display sleep is separate from system sleep (e.g., 40min idle setting)

### Fixed
- **Backup restoration loop during display sleep** (#47 P1-1)
  - Added `isDisplayMonitoringEnabled` guard to `takeWindowSnapshot()`
  - Prevents repeated "Restoring backup" when display is off but system is running

### Changed
- disableMonitoringDuringSleep now defaults to true
  - Recommended for most users to prevent sleep-related issues

## [1.2.11] - 2025-12-10

### Added
- **Menu hotkey display improvements** (#48)
  - Display `⌃⌘1-5` shortcuts in Slot submenu items
  - Add "🔀 Nudge Window" submenu with `⌃⌘W/A/S/D` shortcuts
  - Helps users discover features without reading documentation
- **Restored Sleep Behavior debug info** (#48)
  - Re-added "Last sleep" and "Monitoring status" display in Settings
- **Project branding**
  - Added app icon and README logo

### Fixed
- **Auto-snapshot skipped during sleep** (#48)
  - `isMonitoringEnabled` check now properly guards periodic snapshots
  - Prevents unnecessary snapshot attempts when display monitoring is paused

## [1.2.10] - 2025-12-06 

### Removed
- **Dead code cleanup** (#45)
  - `getAdjustedDisplayDelay()`: Displayed in UI but never used in actual restore logic
  - `sleepDurationHours` and `lastWakeTime` properties: Only used for above calculation
  - `ResumeDisplayMonitoring` observer: No code posted this notification
  - `resumeMonitoring()` method: Empty implementation (log only)
  - `getWindowIdentifier()` method: Defined but never called
  - Sleep Behavior UI section showing "Last sleep" and "Adjusted delay" (misleading info)

### Fixed
- **Double window restore when waking from long sleep** (#45)
  - Added 5-second cooldown after restore completion to prevent duplicate restoration
  - macOS fires display events immediately after restore, triggering unnecessary second restore
  - Cooldown is bypassed for intentional retries (restore retry mechanism unaffected)
  - Cooldown resets when screen count increases (ensures restore after display reconnection)

### Changed
- Sleep Behavior settings UI simplified to show only monitoring status (Active/Paused)

## [1.2.9] - 2025-12-03

### Changed
- **Default hotkey modifier** now correctly defaults to `⌃⌘` (Control+Command)
  - Fixed inconsistency between init() and resetToDefaults()
  - v1.2.7 changelog stated this change, but init() still had old values
- **Sound notifications disabled by default**
  - Previously enabled by default (primarily for debugging)
  - Users who want sound feedback can enable in Settings → Snapshot

### Fixed
- Slot index comment typo (1-4 → 1-5)
- **Accessibility API regression from #27** (#40)
  - Restored `CFTypeRef?` type for window reference variables
  - Fixed window operations failing for Chrome and multi-process apps
  - Added fallback to `kAXWindowsAttribute` when `kAXFocusedWindowAttribute` fails
  - Added `AXValueGetValue` return value validation
  - Affected functions: `nudgeWindow()`, `moveWindow()`

## [1.2.8] - 2025-12-02

### Added
- **Internationalization (i18n)** (#2)
  - English as default UI language
  - Japanese localization via Localizable.strings
  - In-app language switcher (Settings → Basic → Language)
    - System Default: Follow macOS system language
    - English: Force English UI
    - 日本語: Force Japanese UI
  - All debug logs output in English regardless of UI language
  - All code comments translated to English for international contributors
- **Startup Information in Debug Log** (#21)
  - Display app version and build number on launch
  - Show current settings summary (hotkey, timing, options)
  - Helps users share configuration when reporting issues
- **App Name Masking for Privacy** (#21)
  - New setting: "Mask app names" in Settings → Debug (default: ON)
  - Replaces app names with generic identifiers (App1, App2, etc.)
  - Maintains consistency within session (same app = same identifier)
  - Users can safely share logs in GitHub issues without exposing app usage
- **Hotkey Registration Failure Warning** (#31)
  - Display alert dialog on startup if any hotkey registration fails
  - Shows which shortcuts failed and suggests solutions
  - "Open Settings" button for quick access to change modifier keys
  - Helps users identify conflicts with other apps or system shortcuts
- **Multiple Snapshot Slots** (#32)
  - 5 manual snapshot slots for different scenarios (Home, Office, Presentation, etc.)
  - Slot selection via menu bar submenu (🎯 Slot) or hotkeys (modifier + 1-5)
  - Each slot shows window count and last update time (with date if not today)
  - Sound feedback on slot switch (when sound is enabled)
  - Auto-snapshot uses dedicated Slot 0 (internal, not shown in menu)
  - Manual snapshots (modifier + ↑/↓) operate on the selected slot (1-5)
  - Selected slot persists across app restarts
  - Data structure designed for future Spaces/virtual desktop support
  - Future: Custom slot naming (data structure ready, UI planned for v1.3.0+)

### Improved
- **Restart UX for Settings Changes** (#25)
  - Hotkey modifier changes now take effect immediately (no restart required)
  - Language changes still require restart, with clear visual indicator (🔄)
  - "Restart Now" button appears only when language is changed
  - Removed confusing static warning text and modal dialog

### Fixed
- **Error logging for snapshot operations** (#29)
  - Replaced silent try? with do-catch blocks in ManualSnapshotStorage
  - Save/load errors now output to debug log with error details
  - Save failure triggers user notification for visibility
- **Crash prevention in Accessibility API calls** (#27)
  - Added nil checks before force casting AXUIElement and AXValue types
  - Validates API success status before accessing return values
  - Prevents crashes when Accessibility API returns unexpected states
  - Affected methods: nudgeWindow, moveWindow, restoreManualSnapshot, restoreWindowsIfNeeded

### Changed
- **Repository renamed** (#10)
  - GitHub repository: `WindowSmartMover` → `tsubame`
  - Display Name: `Window Smart Mover` → `Tsubame`
  - Old URLs automatically redirect to new location
  - Bundle Identifier unchanged (user settings preserved)

### Security
- **Salted hash for WindowMatchInfo** (#26)
  - Added random salt to SHA256 hash function for privacy protection
  - Previous implementation: `SHA256(appName)` - vulnerable to rainbow table attacks
  - New implementation: `SHA256(salt + appName)` - resistant to reverse lookup
  - Salt is generated once per installation using `SecRandomCopyBytes` (256-bit)
  - Stored in UserDefaults (Keychain is overkill for local-only data)
  - Common app names (Safari, Finder, Chrome) can no longer be identified from stored hashes

### Refactored
- **Consolidated timer management into TimerManager class** (#28)
  - Created new `TimerManager.swift` for centralized timer handling
  - Moved 6 timers from AppDelegate to TimerManager:
    - displayMemoryTimer (window position recording)
    - initialCaptureTimer (initial snapshot after launch/connection)
    - periodicCaptureTimer (periodic auto-snapshot)
    - stabilizationCheckTimer (display change polling)
    - restoreWorkItem (window restoration delay)
    - fallbackWorkItem (post-stabilization fallback)
  - Added `isCancelled` check for DispatchWorkItem to prevent duplicate execution
  - Unified Timer creation pattern to `RunLoop.main.add(.common)`
  - Removed unused `displayStabilizationTimer` variable
  - Added `stopAllTimers()` call in `applicationWillTerminate` for clean shutdown
  - Improved debuggability with `activeTimerNames` and `statusDescription` properties

### Technical Details
- Implemented NSLocalizedString for all 80+ UI strings
- Created ja.lproj/Localizable.strings for Japanese translations
- Added LanguageSettings class with AppleLanguages UserDefaults
- Fixed deprecated onChange(of:perform:) warning (macOS 14.0+)
- Added `maskAppNamesInLog` property to `SnapshotSettings`
- Added `maskAppName()` and `clearAppNameMapping()` to `DebugLogger`
- Applied masking to all log outputs containing app names
- Added `HashSaltManager` singleton class for salt generation and caching
- Modified `WindowMatchInfo.hash()` to use salted input
- Added `import Security` for `SecRandomCopyBytes`
- Added guard statements for `positionRef` and `sizeRef` nil checks
- CoreFoundation types require `as!` but are now protected by prior API success validation
- Added `showHotkeyRegistrationWarning()` method with NSAlert
- Modified `registerHotKeys()` to return list of failed registrations
- Added `unregisterHotKeys()` for cleanup (preparation for #25)
- Refactored hotkey registration from repetitive code to loop-based implementation
- Added `HotKeySettings.modifiersDidChangeNotification` for immediate re-registration
- Added `setupHotkeySettingsObserver()` in AppDelegate for hotkey change detection
- TimerManager uses singleton pattern consistent with other Settings classes
- Added `SnapshotSlot` struct with metadata dictionary for future extensibility
- Storage format upgraded from V2 (array) to V3 (SnapshotSlot array) with automatic migration
- `currentSlotIndex` now computed property backed by `ManualSnapshotStorage.activeSlotIndex`
- Auto-snapshot hardcoded to Slot 0, manual operations use Slots 1-4
- Menu bar slot submenu with radio-button style selection
- Added hotkeys 9-13 for slot selection (modifier + 1-5)
- Added `selectSlotByHotkey()` method for hotkey-triggered slot switching
- Total registered hotkeys increased from 8 to 13
- Slot switch plays sound feedback when sound notifications are enabled
- Date display shows MM/dd HH:mm for non-today timestamps

### Migration Notes
- Existing snapshots will not match after upgrade (different hash values)
- Simply save a new snapshot after upgrading - no manual intervention needed
- Snapshot data automatically migrates from V2 to V3 format on first launch
- Existing single slot data moves to Slot 0 (auto); manual slots start empty


## [1.2.7] - 2025-11-29

### Added
- **Window Size Restoration**
  - Both position and size are now restored (previously position-only)
  - Preserves your exact window dimensions after restoration
  - Works for both manual snapshot restore and auto-restore on display reconnection
- **Restore on Launch Option**
  - New setting: "Restore on launch" in Settings → Snapshot
  - Automatically restores saved snapshot when app starts
  - Uses existing window restore delay setting for timing
  - Only triggers when external display is connected
- **Millisecond Timestamp in Debug Logs**
  - New setting: "Show milliseconds" in Settings → Debug
  - Enables `HH:mm:ss.SSS` format for precise timing analysis
  - Useful for troubleshooting timing-related issues

### Changed
- **Default Hotkey Modifier** (#5)
  - Changed from `⌃⌥⌘` (Control+Option+Command) to `⌃⌘` (Control+Command)
  - Simpler key combination, easier to press
  - Existing users' settings are preserved (stored in UserDefaults)
  - New installations will use the new default

### Fixed
- **Floating-point Display in Debug Logs**
  - Fixed display of timing values like `3.0000000000000004` → `3.0`
  - All timing-related log messages now use formatted output

### Removed
- **Unused ContentView.swift**
  - Removed default template file that was not being used

### Technical Details
- Added `restoreOnLaunch` property to `SnapshotSettings`
- Added `showMilliseconds` property to `SnapshotSettings`
- Modified `DebugLogger.addLog()` to support millisecond formatting
- Modified `restoreWindowsIfNeeded()` to restore window size via `kAXSizeAttribute`
- Modified `restoreManualSnapshot()` to restore window size
- Updated `resetToDefaults()` to include new settings

## [1.2.6] - 2025-11-29

### Added
- **Privacy-aware Window Matching** (#14)
  - App names and window titles are now hashed (SHA256) before storage
  - Protects user privacy: stored data reveals no information about opened apps or content
  - Fallback matching strategy: title hash → size match → app-only match
  - Windows can now be restored after app restart (CGWindowID no longer required)
- **Position Proximity Matching**
  - When multiple windows have the same size, the window closest to the saved position is selected
  - Prevents cross-display mismatches when restoring windows
  - Distance (in pixels) shown in verbose logs for debugging
- **Privacy Protection Mode**
  - New setting: "Don't persist snapshots" option
  - When enabled, all snapshot data is cleared on app quit
  - Existing data is immediately cleared when enabling this option
  - For users who want no data written to disk
- **Verbose Logging Option**
  - New setting: "Enable verbose logging" toggle
  - When disabled (default), only essential logs are output
  - When enabled, detailed matching info (targets, candidates, distances) is shown
  - Useful for troubleshooting window restoration issues

### Changed
- **Snapshot data format upgraded to v2**
  - New structure using `WindowMatchInfo` with hashed identifiers
  - Old format data (v1.2.x) is automatically discarded on first launch
  - Users need to save snapshots again after upgrading
- **Unified window matching for auto-restore** (#17)
  - Display reconnection restore now uses `WindowMatchInfo` format (same as manual snapshots)
  - Shares `findMatchingWindow()` logic between manual and auto restore
  - Position proximity matching now applies to auto-restore as well
- **CGWindowID priority matching** (#17)
  - Within the same session, CGWindowID is used for exact window identification
  - Prevents window mix-ups when multiple windows have the same size
  - Falls back to title/size/app matching after app restart

### Fixed
- **Stale window position data in auto-snapshot** (#17)
  - `takeWindowSnapshot()` now clears old data before rebuilding
  - Prevents phantom entries when windows move between displays
  - Only updates when 2+ displays connected (preserves data during disconnection)
  - Backs up and restores external display data if timing causes empty snapshot
- **CGWindowID matching now verifies app name** (#17)
  - Added appNameHash check to prevent theoretical cross-app mismatches
- **Improved duplicate match prevention** (#17)
  - CGWindowID-matched windows are marked as used even if already on external display
  - Prevents same window from matching multiple saved entries
- **Clearer log messages for external display windows** (#17)
  - "Already on external display" vs "Not on main screen (skip)" distinction

### Security
- Position and size data remain in plaintext (required for restoration)
- Threat model consideration: Accessing UserDefaults requires local file system access, 
  at which point an attacker likely has more direct means of observation
- This improvement reduces incidental data exposure in backups and sync scenarios

### Technical Details
- Added `WindowMatchInfo` struct with `appNameHash`, `titleHash`, `size`, and `frame` fields
- Implemented SHA256 hashing using CryptoKit framework
- Added `findMatchingWindow()` with priority-based fallback matching
- Position proximity sorting for same-size window candidates
- Storage key changed from `manualSnapshotData` to `manualSnapshotDataV2`
- Added `disablePersistence` property to `SnapshotSettings`
- Added `verboseLogging` property with `verbosePrint()` function
- Added `applicationWillTerminate()` for cleanup on quit
- `windowPositions` type changed to `[String: [String: WindowMatchInfo]]`
- `takeWindowSnapshot()` includes external display backup mechanism
- `findMatchingWindow()` accepts `preferredCGWindowID` parameter for exact matching

### Migration Notes
- **Breaking change**: Saved snapshots from v1.2.x will be cleared
- After upgrading, use ⌃⌘↑ to save a new snapshot
- Privacy protection mode is OFF by default (existing behavior preserved)

### Planned (Future)
- **Manual Window Snapshot & Restore**: Enhanced features
  - Visual notification feedback (screen flash, sound)
  - Multiple snapshot slots with UI selection
  - Snapshot management interface (list, delete, rename)
- **Internationalization (i18n)**
  - English as default UI language
  - Japanese localization
  - Localized debug logs for international users

### Future Considerations (Post v1.2.6)
- Per-app window restoration rules
- Support for more than 2 displays
- Export/Import snapshots as JSON

## [1.2.5] - 2025-11-28

### Fixed
- **Auto-snapshot false trigger after sleep/wake** (#11)
  - Snapshot now only scheduled when restore count > 0 AND screen count >= 2
  - Prevents overwriting 2-display layout with single-display state
- **Display count protection for auto-snapshot**
  - Skip auto-snapshot when only 1 display connected
  - Protects saved layout during sleep/wake transitions
- **Debug log accuracy for AXUIElement matching**
  - Fixed false warning logs appearing after successful restore
  - Added proper logging when position matching fails
- **Improved AXUIElement position matching tolerance**
  - Increased tolerance from 10px to 50px
  - Absorbs coordinate system fluctuations during sleep/wake

### Added
- **Window restoration retry mechanism** (#13)
  - Automatically retries restoration up to 2 times if initial attempt fails
  - 3 second delay between retry attempts
  - Addresses intermittent failures due to macOS coordinate system instability
  - Retry counter resets on new display events

### Technical Details
- `restoreWindowsIfNeeded()` now returns restored window count
- Added display count validation in `performAutoSnapshot()`
- Added `matchFound` flag in AXUIElement position matching logic
- Added `restoreRetryCount`, `maxRestoreRetries`, `restoreRetryDelay` properties
- Modified `triggerRestoration()` to support retry with `isRetry` parameter

## [1.2.4] - 2025-11-27

### Added
- **Automatic Snapshot Feature**
  - Initial auto-snapshot after app launch or display recognition (configurable: 0.5-60 min, default 15 min)
  - Optional periodic auto-snapshot (configurable: 5-360 min / 6 hours, default 30 min)
  - Settings UI for all auto-snapshot configurations
- **Snapshot Persistence** (UserDefaults)
  - Snapshots now survive app restarts and macOS reboots
  - Automatic loading of saved snapshots on app launch
  - Clear saved snapshot option in Settings
  - Timestamp display showing last save time
- **Existing Data Protection**
  - Prevents auto-snapshot from overwriting when window count is too low
  - Configurable minimum window threshold (default: 3 windows)
  - Protects against data loss during system startup
- **Display Memory Interval Setting**
  - Configurable window position monitoring interval (1-30 sec, default 5 sec)
  - Used for automatic window restoration on display reconnection
  - Real-time update without app restart
- **Window Nudge Feature** (Pixel-level positioning)
  - Move focused window by configurable pixels (10-500 px, default 100 px)
  - Keyboard shortcuts: `⌃⌘W` (up), `⌃⌘A` (left), `⌃⌘S` (down), `⌃⌘D` (right)
  - Eliminates need for trackpad/mouse for fine positioning after screen moves
- **Sound Notification**
  - System sound plays on snapshot save/restore (configurable)
  - Selectable from 13 macOS system sounds (Blow, Glass, Ping, etc.)
  - Preview button to test selected sound
- **System Notification**
  - Optional notification center alerts for snapshot operations
  - Shows window count in notification body
- **Enhanced Menu Bar**
  - Displays snapshot status (window count and last save time)
  - Auto-updates after save operations
- **Enhanced About Window**
  - App name displayed as "Tsubame - Window Smart Mover"
  - Version and build info (auto-generated)
  - Keyboard shortcuts reference
- **Automated Version Management**
  - VERSION file defines major.minor.patch version
  - Build number auto-generated from git commit count
  - Integrated into Xcode build process via script

### Changed
- Unified Settings dialog layout with Basic/Advanced tabs
- Improved Settings UI with Stepper controls for precise value adjustment
- About window now uses DateFormatter for real-time display
- Menu item "About WindowSmartMover" → "About Tsubame"

### Fixed
- Menu bar snapshot status not updating after save operations
- About window showing stale build information

### Technical Details
- Added `SnapshotSettings` class for auto-snapshot configuration
- Added `ManualSnapshotStorage` class for UserDefaults persistence
- Added `performAutoSnapshot()` with existing data protection
- Added `schedulePostDisplayConnectionSnapshot()` for display event handling
- Added `nudgeWindow(direction:)` for pixel-level window movement
- Added notification permission request via `UNUserNotificationCenter`
- Implemented VERSION file parsing and build number generation
- Timer execution uses `.common` RunLoop mode for reliability

## [1.2.3] - 2025-11-27

### Added
- **Manual Window Snapshot & Restore** (MVP implementation)
  - Save: Captures current window positions for all displays
  - Restore: Returns windows to their saved positions
  - Works independently from automatic display reconnection restore
- **Keyboard Shortcuts for Snapshot Operations**
  - `⌃⌘↑` Save current window layout (snapshot)
  - `⌃⌘↓` Restore saved window layout
- **Menu Bar Commands**
  - "📸 Save Layout" - same as keyboard shortcut
  - "📥 Restore Layout" - same as keyboard shortcut

### Known Limitations
- Fullscreen and minimized windows are excluded from snapshot
- Single snapshot slot (slot selection planned for future)
- Snapshot data is not persisted (memory only)

### Technical Details
- Internal slot-based architecture prepared (5 slots, currently using slot 0 only)
- Snapshot stored as `[displayID: [windowKey: CGRect]]` dictionary
- Window identification using app name + CGWindowID combination

## [1.2.2] - 2025-11-26

### Added
- Enhanced debug log for restore delay value tracing
- Detailed screen position information in restore logs

### Changed
- Default timing values increased for maximum compatibility
  - Display stabilization delay: 0.5s → 6.0s (default)
  - Window restore delay: 2.5s → 6.0s (default)
  - Total default wait time: 12 seconds (provides maximum compatibility)
- Simplified display change event handling
  - Replaced Timer-based approach with DispatchWorkItem
  - Prevents RunLoop interference with system processes
  - Cleaner cancellation of pending operations

### Fixed
- Duplicate window restoration attempts during rapid display changes
  - Previous implementation could schedule multiple restoration tasks
  - Now properly cancels pending tasks when new events arrive
  - Reduces unnecessary processing and system load

### Known Issues
- **Dock menu misalignment after sleep/wake** (largely resolved in v1.2.2)
  - Most cases resolved by improved stabilization timing
  - Remaining cases may be caused by other menu bar apps
  - Workaround: Run `killall Dock` in Terminal to reset

### Technical Details
- Removed `displayStabilizationTimer?.invalidate()` pattern
- Implemented `DispatchWorkItem` with explicit cancellation
- Maintains single restoration execution per display change sequence
- AboutView now uses `DateFormatter` for real-time display

### Migration Notes
- Users upgrading from v1.2.0 will notice longer default delays
- Previous custom settings are preserved during upgrade
- To use new defaults: Settings → "Reset to Defaults"
- Faster displays can reduce delays to 3-5 seconds if desired

## [1.2.0] - 2025-11-13

### Added
- Display change detection stabilization timer to handle rapid display configuration events
  - New setting: "Display Change Detection Stabilization Time" (0.1-3.0s, default 0.5s)
  - Prevents premature window restoration during system wake/sleep cycles
- Two-stage timing mechanism for reliable window restoration
  - Stage 1: Wait for display configuration to stabilize
  - Stage 2: Wait for macOS to complete window coordinate updates
- Enhanced Settings dialog with detailed timing configuration explanations
  - Separate sections for each timing setting with dividers
  - Expanded window height to 715px to prevent content clipping

### Changed
- Window restore delay default increased from 1.5s to 2.5s
  - Provides more time for macOS to update window coordinates after display reconnection
- Window position detection logic improved from frame intersection to X-coordinate based
  - More reliable detection of which display a window is currently on
  - Reduces false positives during coordinate system transitions
- Settings dialog "Default" button now resets both timing values

### Fixed
- **Critical**: Windows not restoring to external displays after system wake/sleep
  - Root cause: Rapid display configuration events caused timer overwrites
  - Solution: Stabilization timer cancels and reschedules until display changes settle
- Window restoration logic incorrectly identifying window locations during coordinate updates
  - Changed from `frame.intersects()` to X-coordinate range checking
  - More accurate determination of main vs. external display placement
- Settings window content clipping when displaying both timing configurations
  - Adjusted window height from 650px to 715px to ensure all content is visible

### Technical Details
- Implemented `displayStabilizationTimer` with automatic invalidation on new events
- Modified `displayConfigurationChanged()` to use two-stage delay mechanism
- Enhanced `restoreWindowsIfNeeded()` with improved screen position detection
- All timing values now user-configurable via WindowTimingSettings

## [1.1.0] - 2025-11-08

### Added
- Display memory feature: Auto-restore windows on display reconnect
  - Periodic window position snapshots every 5 seconds
  - Automatic window restoration when external displays reconnect
  - Per-display window position memory using CGWindowID
  - Support for multiple windows per application
- Debug log viewer with clear and copy functionality (in-memory only, no file storage)
- Window restore timing configuration (0.1-10.0 seconds, default 1.5s)
- `debugPrint()` function for centralized logging
- `DebugLogger` class for managing log entries (max 1000 entries)
- `WindowTimingSettings` class for managing restore delay configuration

### Changed
- Unified settings dialog and renamed menu item from "Shortcut Settings..." to "Settings..."
- Settings window now includes both hotkey and timing configurations
- Settings window size increased from 400x400 to 500x600
- "Cancel" button changed to "Reset to Defaults" with full functionality

### Fixed
- Window position calculation bug - restored relative positioning logic instead of center alignment
- Removed all compiler warnings:
  - Deleted unused `found` variable
  - Changed `nextScreenIndex` from `var` to `let`
  - Changed `gMyHotKeyID1` from `var` to `let`
  - Changed `gMyHotKeyID2` from `var` to `let`

### Security
- Debug logs are stored in memory only and cleared on app termination
- No sensitive information is written to disk

### Technical Details
- Implemented CGWindowListCopyWindowInfo for window enumeration
- Display identification using NSScreen device description
- Window matching based on app name + CGWindowID
- NSApplication.didChangeScreenParametersNotification for display change detection

## [1.0.0] - 2025-10-18

### Added
- Initial release
- Multi-display window management with keyboard shortcuts
  - Default hotkeys: Ctrl+Option+Command+Arrow keys
  - Move windows between displays instantly
- Customizable hotkey modifiers (Control, Option, Shift, Command)
- Menu bar integration with system tray icon
- About window with version information

### Technical Details
- Built as macOS menu bar application
- Used Accessibility API for window manipulation
- Implemented in Swift 5.x with SwiftUI for settings interface
- Utilized Carbon API for global hotkey registration
