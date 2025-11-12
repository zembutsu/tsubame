# Changelog

All notable changes to WindowSmartMover will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added
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

## [Planned]

### Internationalization (i18n)
Multi-language support to make the app accessible to international users.

**Scope:**
- **User-facing UI and messages** - Menu items, dialogs, buttons, settings, and all user-visible text
- **Debug logs** - Convert to English for global accessibility

**Current state:**
- All UI text is in Japanese
- Debug logs are in Japanese, preventing non-Japanese speakers from troubleshooting issues independently

**Implementation approach:**

**Phase 1: English default (Priority)**
1. Convert all UI strings to English
   - Menu items
   - Settings dialog
   - Debug log viewer
   - About window
   - Alert messages
2. Convert all debug logs to English
   - This is critical for enabling international users to troubleshoot issues
   - Enables easier collaboration on bug reports
   - Makes Stack Overflow/GitHub issue searches effective
3. Convert code comments to English
   - Improves code readability for international contributors
   - Facilitates open-source collaboration
   - Makes the codebase more maintainable globally
4. Implement NSLocalizedString framework for all user-facing text
   - Prepare infrastructure for future localizations

**Phase 2: Japanese localization**
1. Create Japanese .strings files
2. Add language auto-detection based on system preferences
3. Test both English and Japanese interfaces thoroughly

**Phase 3: Additional languages (Future)**
- Community contributions welcome
- Consider: Chinese, Korean, Spanish, French, German

**Rationale:**
- **English debug logs are essential** - Without English logs, non-Japanese users cannot diagnose issues, severely limiting the app's reach
- English as default UI maximizes potential user base globally
- Phased approach allows for stable implementation without major refactoring
- Separating UI localization from debug logs provides optimal developer and user experience

## [1.1.0] - 2025-10-18

### Added
- Initial release
- Multi-display window management with keyboard shortcuts
- Customizable hotkey modifiers (Control, Option, Shift, Command)
- Window position memory across display configurations
- Automatic window restoration when external displays reconnect
- Menu bar integration with system tray icon

### Technical Details
- macOS menu bar application
- Uses Accessibility API for window manipulation
- Swift 5.x with SwiftUI for settings interface
- Carbon API for global hotkey registration
