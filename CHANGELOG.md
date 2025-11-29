# Changelog

All notable changes to Tsubame will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]


### Planned: v1.3.0 (Stable Release)
- App Store release preparation
- Binary distribution via GitHub Releases

## [1.2.8] - WIP

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

### Changed
- **Repository renamed** (#10)
  - GitHub repository: `WindowSmartMover` → `tsubame`
  - Display Name: `Window Smart Mover` → `Tsubame`
  - Old URLs automatically redirect to new location
  - Bundle Identifier unchanged (user settings preserved)

### Technical Details
- Implemented NSLocalizedString for all 80+ UI strings
- Created ja.lproj/Localizable.strings for Japanese translations
- Added LanguageSettings class with AppleLanguages UserDefaults
- Fixed deprecated onChange(of:perform:) warning (macOS 14.0+)
- Added `maskAppNamesInLog` property to `SnapshotSettings`
- Added `maskAppName()` and `clearAppNameMapping()` to `DebugLogger`
- Applied masking to all log outputs containing app names


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

## [Planned Features]

### Internationalization (i18n)
Multi-language support to make the app accessible to international users.

**Scope:**
- **User-facing UI and messages** - Menu items, dialogs, buttons, settings, and all user-visible text
- **Debug logs** - Translate to English for global accessibility

**Current state:**
- All UI text is in Japanese
- Debug logs are currently in Japanese, which prevents non-Japanese speakers from independently troubleshooting issues

**Implementation approach:**

**Phase 1: English default (Priority)**
1. Translate all UI strings to English
   - Menu items
   - Settings dialog
   - Debug log viewer
   - About window
   - Alert messages
2. Translate all debug logs to English
   - This enables international users to troubleshoot issues independently
   - Facilitates collaboration on bug reports
   - Enables effective Stack Overflow/GitHub issue searches
3. Translate code comments to English
   - Improves code readability for international contributors
   - Facilitates open-source collaboration
   - Makes the codebase more maintainable globally
4. Implement NSLocalizedString framework for all user-facing text
   - Prepares infrastructure for future localizations

**Phase 2: Japanese localization**
1. Create Japanese .strings files
2. Add language auto-detection based on system preferences
3. Test both English and Japanese interfaces thoroughly

**Phase 3: Additional languages (Future)**
- Community contributions welcome
- Consider: Chinese, Korean, Spanish, French, German

**Rationale:**
- English debug logs are essential for international troubleshooting
- English as the default UI maximizes the global user base
- Phased approach enables stable implementation without major refactoring
- Separating UI localization from debug logging optimizes both developer and user experience
