# Tsubame - Window Smart Mover for macOS 

[English](README.md) | [日本語](README_ja.md)

A lightweight macOS menu bar app for effortless window management across multiple displays.

![macOS](https://img.shields.io/badge/macOS-14.0+-blue)
![Swift](https://img.shields.io/badge/Swift-6.2-orange)
![License](https://img.shields.io/badge/License-MIT-green)
![GitHub release](https://img.shields.io/github/v/release/zembutsu/tsubame)
![GitHub downloads](https://img.shields.io/github/downloads/zembutsu/tsubame/total)

## Features

### Core Functionality
- **Keyboard Shortcuts**: Move windows between displays instantly
  - `⌃⌘→` Move to next display
  - `⌃⌘←` Move to previous display
- **Customizable Hotkeys**: Configure modifier keys (Control, Option, Shift, Command)
- **Menu Bar Integration**: Lightweight, stays out of your way

### Display Memory (v1.1+)
- **Automatic Position Saving**: Remembers window positions periodically (configurable: 1-30 sec, default 5 sec)
- **Smart Restoration**: Automatically restores windows when external displays reconnect
- **Sleep/Wake Support**: Works seamlessly after waking from sleep
- **Multi-Window Support**: Handles multiple windows per app individually

### Advanced Configuration (v1.2.0+)
- **Two-Stage Display Reconnection**: Intelligent timing for reliable window restoration
  - Stage 1: Wait for display configuration to stabilize (0.5s default)
  - Stage 2: Wait for macOS coordinate updates (2.5s default)
- **Configurable Timing Settings**: Fine-tune both stages independently (0.1-10s range)
  - Adjust for slower/faster display hardware
  - Optimize for your specific multi-monitor setup
  - Settings persist across app restarts

### Manual Snapshot (v1.2.3+)
- **Save & Restore Window Layouts**: User-controlled window position memory
  - `⌃⌘↑` Save current window layout
  - `⌃⌘↓` Restore saved layout
  - Menu bar commands available
- **Independent from Auto-Restore**: Works separately from display reconnection
- **Current Limitations**:
  - Fullscreen/minimized windows excluded

### Auto Snapshot & Persistence (v1.2.4+)
- **Automatic Snapshot**: Never forget to save your layout
  - Initial snapshot taken automatically after app launch (configurable: 0.5-60 min, default 15 min)
  - Also triggers after external display reconnection
  - Optional periodic snapshots (configurable: 5 min - 6 hours, default 30 min)
- **Persistent Storage**: Snapshots survive restarts
  - Saved to UserDefaults, persists across app/macOS restarts
  - Clear saved data option in Settings
  - Last save timestamp displayed
- **Existing Data Protection**: Prevents accidental data loss
  - Skips auto-snapshot if window count is below threshold (default: 3)
  - Protects previous layout during system startup

### Window Nudge (v1.2.4+)
- **Pixel-Perfect Positioning**: Fine-tune window position without mouse/trackpad
  - `⌃⌘W` Move up
  - `⌃⌘A` Move left
  - `⌃⌘S` Move down
  - `⌃⌘D` Move right
- **Configurable Step Size**: 10-500 pixels (default 100 px)
- **Keyboard-Only Workflow**: Complete window management without touching the trackpad

> 💡 **Design Note**: This feature was inspired by "Tsubame" (燕/swallow) - the app's codename. The swift, agile movements of 燕返し (tsubame-gaeshi) suggested that window management should be equally nimble. Moving windows between screens is one thing, but fine-tuning their position should also be keyboard-driven. No more reaching for the trackpad just to nudge a window "a bit to the right." — *Zem, 2025-11-27*

### Privacy & Security (v1.2.6+)
- **Privacy-aware Snapshot Storage**: Your data is protected
  - App names and window titles are hashed (SHA256) before storage
  - Stored data reveals nothing about which apps you use or what content you view
  - Position and size data remain in plaintext (required for restoration)
- **Window Matching After App Restart**: Fixed the CGWindowID limitation
  - Windows can now be restored even after app restart
  - Uses intelligent matching: title hash → size match → app-only match
- **CGWindowID Priority Matching**: Reliable same-session restoration
  - Same-size windows are correctly identified using CGWindowID within session
  - No more window mix-ups when you have multiple windows of the same app
- **Privacy Protection Mode**: For maximum privacy
  - Option to disable snapshot persistence entirely
  - All data cleared on app quit
  - Enable in Settings → Snapshot → "Don't persist snapshots"

### Enhanced Restoration (v1.2.7+)
- **Window Size Restoration**: Complete layout restoration
  - Both position and size are now restored
  - Preserves your exact window dimensions
- **Restore on Launch**: Automatic restoration when app starts
  - Optional: Enable in Settings → Snapshot → "Restore on launch"
  - Requires saved snapshot and external display connected
- **Improved Debug Logging**: Better troubleshooting
  - Optional millisecond timestamps for precise timing analysis
  - Enable in Settings → Debug → "Show milliseconds"

### Internationalization (v1.2.8+)
- **Multi-language Support**: Use Tsubame in your preferred language
  - English as default UI language
  - Japanese localization included
  - In-app language switcher (Settings → Basic → Language)
- **Language Options**:
  - System Default: Follow macOS system language
  - English: Force English UI
  - 日本語: Force Japanese UI
- **Developer-Friendly**: All debug logs in English regardless of UI language
  - Enables international collaboration on bug reports
  - Code comments also in English for contributors

### Coming Soon 🚧

⚠️ **Note**: These features are under active development.

- **Enhanced Snapshot Features**:
  - Multiple snapshot slots with UI selection
  - Snapshot management interface (list, rename, delete)

For detailed development progress, see [CHANGELOG.md](CHANGELOG.md).

## Why Tsubame?

### The Problem with Existing Solutions

Most window management apps are either:
- **Too heavy**: Packed with features you don't need
- **Closed source**: You can't verify what they're doing
- **Cloud-dependent**: Require accounts and subscriptions

Tsubame is:
- ✅ **Simple**: Does one thing well
- ✅ **Open Source**: Full transparency
- ✅ **Privacy-First**: Everything stays on your Mac
- ✅ **Lightweight**: Minimal resource usage
- ✅ **Free**: No subscriptions, no ads

### My Motivation

While aware of competing solutions like Rectangle and Magnet, I deliberately chose to "reinvent the wheel" for several reasons:

**Learning by Doing**
- Deep understanding comes from implementation, not just usage
- SwiftUI and macOS app development require hands-on experience
- Building from scratch reveals architectural decisions and trade-offs

**Right-Sized Solution**
- Existing tools are feature-rich but over-specified for my needs
- Sometimes a focused, minimal solution is more maintainable
- Complete control over features and future direction

This project embodies the philosophy: **understand deeply by building yourself**.

### The Name

"Tsubame" (燕) means "swallow" in Japanese - the bird known for its swift, agile flight. Just as swallows dart effortlessly between locations, this app helps your windows move seamlessly between displays. The name also references "燕返し" (tsubame-gaeshi), a sword technique famous for its quick reversal - fitting for an app that restores windows to their original positions.

## Installation

### Requirements
- macOS 14.0 or later
- Accessibility permissions (required for window control)

### Download & Install

1. Download the latest release from [Releases](https://github.com/zembutsu/tsubame/releases)
2. Move `Tsubame.app` to `/Applications/`
3. Launch the app
4. Grant Accessibility permissions when prompted:
   - System Settings → Privacy & Security → Accessibility
   - Enable Tsubame

## Usage

### Basic Window Movement
1. Make sure a window is active (click on it)
2. Press `⌃⌘→` to move to the next display
3. Press `⌃⌘←` to move to the previous display

### Automatic Window Restoration
1. Use your external display normally
2. When you disconnect (or sleep):
   - Windows automatically move to the main display
3. When you reconnect:
   - Windows automatically restore to their original positions

### Customizing Hotkeys
1. Click the menu bar icon
2. Select "Settings..."
3. Choose your preferred modifier keys
4. Restart the app

### Changing Language
1. Click the menu bar icon
2. Select "Settings..."
3. In the "Language" section, select your preferred language
4. Click "Restart Now" when prompted (or restart later)

### Configuring Display Reconnection Timing
1. Click the menu bar icon
2. Select "Settings..."
3. Adjust timing settings:
   - **Display Change Detection Stabilization Time**: How long to wait for display configuration to settle (0.1-3.0s)
   - **Window Restore Delay**: Additional delay before moving windows (0.1-10.0s)

### Manual Snapshot Usage
1. Arrange your windows as desired on external display
2. Press `⌃⌘↑` to save the layout (or use menu)
3. Later, press `⌃⌘↓` to restore (or use menu)

## Configuration Guide

### Timing Optimization

Default settings (12 second total delay) work for most users, but you can optimize:

**For fast USB-C displays:**
- Display stabilization: 2-3 seconds
- Window restore delay: 3-4 seconds
- Total: 5-7 seconds

**For slower HDMI/DisplayPort:**
- Display stabilization: 6-8 seconds
- Window restore delay: 6-8 seconds  
- Total: 12-16 seconds

**If windows don't restore properly:**
- Increase both values by 2-3 seconds
- Check Debug Log for timing details
- Report your hardware setup in issues

## Troubleshooting

### Windows not moving
- Verify Accessibility permissions are granted
- Try restarting the app
- Some apps don't support programmatic window control

### Automatic restoration not working
- Check debug logs: Menu bar icon → "Show Debug Log"
- Ensure external display is properly detected
- Try manual window movement first to verify permissions
- **Adjust timing settings if needed**:
  - Increase "Display Change Detection Stabilization Time" if your display changes rapidly during wake
  - Increase "Window Restore Delay" if your display hardware needs more initialization time
  - Access via Menu bar → "Settings..." → Timing section

### Using Debug Logs
The debug log viewer helps diagnose issues:
1. Reproduce the problem
2. Open debug logs (Menu bar → "Show Debug Log")
3. Copy logs using the "Copy" button
4. Share logs when reporting issues on GitHub

**Privacy Note**: Debug logs are stored in memory only and contain:
- Display IDs (numeric identifiers, no personal info)
- Application names (masked by default since v1.2.8)
- Window coordinates
- System events

No sensitive information is logged or transmitted.

## Roadmap

### Completed (v1.2.8)
- [x] Internationalization (English UI + Japanese localization) (#2)
- [x] In-app language switcher
- [x] All debug logs in English
- [x] Code comments translated to English
- [x] App name masking in logs (#21)
- [x] Startup information in debug log (#21)

### Completed (v1.2.7)
- [x] Changed default hotkey from ⌃⌥⌘ to ⌃⌘ (#5)
- [x] Window size restoration (position + size)
- [x] Restore on launch option
- [x] Millisecond timestamp option in debug logs
- [x] Fixed floating-point display in logs

### Completed (v1.2.6)
- [x] Privacy-aware window matching (SHA256 hashing for app names and titles)
- [x] Window restoration after app restart (CGWindowID limitation fixed)
- [x] Privacy protection mode (disable persistence option)
- [x] Fallback matching strategy (title → size → app-only)

### Completed (v1.2.5)
- [x] Fixed auto-snapshot false trigger after sleep/wake (#11)
- [x] Display count protection for auto-snapshot
- [x] Window restoration retry mechanism (#13)
- [x] Improved AXUIElement position matching tolerance (10px → 50px)
- [x] Debug log improvements for restoration failures

### Completed (v1.2.4)
- [x] Automatic snapshot (initial + periodic)
- [x] Persistent snapshot storage (UserDefaults)
- [x] Auto-snapshot settings UI
- [x] Post-display-reconnection snapshot scheduling
- [x] Window nudge feature (WASD keys for pixel-level positioning)
- [x] Settings UI improved with Steppers
- [x] Settings UI reorganized with Basic/Advanced tabs
- [x] Existing data protection (prevents overwrite with low window count)
- [x] Sound notification with selectable system sounds (13 options + preview)
- [x] System notification support (optional)
- [x] Enhanced menu bar with snapshot status
- [x] Enhanced About window ("Tsubame" branding, shortcuts reference)
- [x] Automated version management (VERSION file + git commit count)

### Completed (v1.2.3)
- [x] Manual window snapshot & restore (MVP)
- [x] Save/restore hotkeys (Ctrl+Cmd+↑/↓)
- [x] Menu bar integration for snapshot operations

### Completed (v1.2.2)
- [x] Fixed stabilization timer reset issue during continuous display events
- [x] Reliable window restoration after long sleep periods
- [x] Debug log window refresh on each open

### Completed (v1.2.0)
- [x] Two-stage display reconnection timing
- [x] Configurable stabilization and restore delays
- [x] Enhanced window position detection logic
- [x] Debug log viewer with copy functionality

### In Development (v1.3.0)
- [ ] App Store release preparation
- [ ] Binary distribution via GitHub Releases

### Future Considerations (Post v1.3.0)
- [ ] Enhanced snapshot features (multiple slots with UI selection)
- [ ] Snapshot management interface (list, rename, delete)
- [ ] Support for more than 2 displays
- [ ] Per-app window restoration rules
- [ ] Export/Import snapshots as JSON
- [ ] Improved restart UX for settings changes

For detailed development plans, see [CHANGELOG.md](CHANGELOG.md).

## Contributing

Contributions are welcome! This project was created as a practical solution to a real problem, and maintained as a learning resource.

### Development Philosophy
- **Simplicity First**: Resist feature creep
- **Privacy Matters**: No telemetry, no cloud
- **Readable Code**: Clear over clever
- **User Agency**: Give users control

## Development Process & AI Usage

This project was developed with assistance from Claude AI (Anthropic). I want to be transparent about this approach and my reasoning.

### Standing on the Shoulders of Giants

I've been fortunate to work with open source technologies for over 30 years—from the early internet days to Linux, Virtualization, Cloud Computing, Docker, and beyond. The knowledge and code shared freely by countless developers made my career possible. Using AI trained on open source code without acknowledgment would feel like forgetting where I came from.

### Learning, Not Replacing

I used AI as a **learning accelerator** to explore SwiftUI, a framework I hadn't worked with before:

- I identified the problem (display coordinate memory on reconnection)
- I defined all requirements and architectural decisions
- AI generated initial code structures and API examples
- I read and understood every line of generated code
- I debugged, refined, and made all final decisions

This mirrors how I learned in the 1990s: reading others' code, asking questions in forums, and building on shared knowledge. The tools changed, but the learning process remains the same.

### Why Share This?

I'm sharing this development approach for a few reasons:

**Transparency**: The community deserves to know how projects are built, especially when new tools are involved.

**For students**: If you're learning to code, know that using AI as a learning tool is okay—as long as you understand what you're building. Don't copy-paste. Read, understand, modify, and make it yours.

**For fellow developers**: I don't claim this is the "right" way. It's simply my way of balancing learning new technologies with years of experience in software development. Your approach may differ, and that's perfectly valid.

### A Note of Respect

To developers who built their skills entirely through manual effort: I deeply respect that path. This isn't about claiming my approach is superior—it's about being honest regarding the tools I used. The open source community thrives on honesty, sharing, and mutual respect. I hope this project reflects those values, even if the development process looks different from what came before.

---

## Acknowledgments

This project stands on the shoulders of giants and wouldn't exist without:

**Inspiration & Prior Art**
- The creators of [Rectangle](https://rectangleapp.com/) and [Magnet](https://magnet.crowdcafe.com/) for demonstrating excellent window management solutions
- The broader macOS window management community for their innovative approaches
- All open source contributors who share their knowledge and code

**Development Support**
- The macOS developer community for comprehensive documentation and helpful discussions
- Apple's engineering teams for providing powerful APIs (Accessibility, CoreGraphics)

## Author

Masahito Zembutsu ([@zembutsu](https://github.com/zembutsu))

## License

MIT License - see [LICENSE](LICENSE) file for details

---

**Note**: This app requires Accessibility permissions to control windows. All processing happens locally on your Mac. No data is collected or transmitted.
