# Changelog

All notable changes to WindowSmartMover will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Planned (v1.3.0)
- **Manual Window Snapshot & Restore**: User-controlled window layout save/restore
  - Configurable hotkeys for save and restore operations (default: Ctrl+Cmd+↑ for save, Ctrl+Cmd+↓ for restore)
  - Independent snapshot storage separate from automatic restoration
  - Visual notification feedback (success count, failure alerts)
  - Menu bar commands for manual snapshot operations
  - Clear saved snapshot option
  - Fallback solution when automatic restoration fails
- **Internationalization (i18n)**
  - English as default UI language
  - Japanese localization
  - Localized debug logs for international users

### Future Considerations (Post v1.3.0)
- Multiple snapshot slots (save/restore multiple layouts)
- Persistent snapshot storage (UserDefaults)
- Snapshot management interface (list, delete, rename)
- Per-app window restoration rules
- Window size restoration (currently position only)
- Support for more than 2 displays
- Configurable snapshot interval

## [1.2.2] - 2025-11-25

### Fixed
- **Critical**: Stabilization timer reset issue during continuous display events (#7)
  - Changed from one-shot timer to periodic check (0.5s interval)
  - Now properly waits for elapsed time since the last event
  - Resolves window restoration failures after long sleep periods
- Debug log window now shows latest logs on each open
  - Previously cached logs from first open

### Technical Details
- Implemented `stabilizationCheckTimer` with 0.5s repeating interval
- Records display events continuously during monitoring suspension
- Calculates elapsed time from `lastDisplayChangeTime` for true stabilization detection
- Debug log window recreated on each open instead of reusing cached instance

### Testing
- Verified with 1 week of continuous operation testing
- Confirmed reliable window restoration after sleep/wake cycles

## [1.2.1] - 2025-11-15

### Added
- Extended timing configuration range to 15 seconds for slower display hardware
  - Both stabilization and restore delays now configurable from 0.1s to 15.0s
  - Enables support for wide range of display types and connection methods
- Current time display in About dialog
  - Shows real-time timestamp for debugging and version verification
  - Helps correlate app behavior with system logs

### Changed
- **Default timing values significantly increased for better reliability**
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
