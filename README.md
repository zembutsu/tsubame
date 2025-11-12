# WindowSmartMover

[English](README.md) | [日本語](README_ja.md)

A lightweight macOS menu bar app for effortless window management across multiple displays.


> **⚠️ Note**: v1.1.0 is not yet notarized by Apple. macOS 15+ users may experience security blocks. 
> A notarized version (v1.1.1) is coming soon.


![macOS](https://img.shields.io/badge/macOS-14.0+-blue)
![Swift](https://img.shields.io/badge/Swift-6.2-orange)
![License](https://img.shields.io/badge/License-MIT-green)
![GitHub release](https://img.shields.io/github/v/release/zembutsu/WindowSmartMover)
![GitHub downloads](https://img.shields.io/github/downloads/zembutsu/WindowSmartMover/total)

## Features

### Core Functionality
- **Keyboard Shortcuts**: Move windows between displays instantly
  - `⌃⌥⌘→` Move to next display
  - `⌃⌥⌘←` Move to previous display
- **Customizable Hotkeys**: Configure modifier keys (Control, Option, Shift, Command)
- **Menu Bar Integration**: Lightweight, stays out of your way

### Display Memory (v1.1+)
- **Automatic Position Saving**: Remembers window positions every 5 seconds
- **Smart Restoration**: Automatically restores windows when external displays reconnect
- **Sleep/Wake Support**: Works seamlessly after waking from sleep
- **Multi-Window Support**: Handles multiple windows per app individually

### Coming Soon (v1.2.0 - In Development) 🚧

⚠️ **Note**: These features are under active development and not yet available in stable releases.

- **Debug Log Viewer**: Real-time logging for troubleshooting
  - View all system events and window operations
  - Copy logs to clipboard for issue reporting
  - Clear logs on demand
  - Memory-only storage (no disk writes)
- **Configurable Window Restore Timing**: Fine-tune display reconnection behavior
  - Adjustable delay from 0.1 to 10.0 seconds (default: 1.5s)
  - Helps with displays that need extra stabilization time
  - Per-user customization in Settings dialog
- **Enhanced Settings Dialog**: Unified configuration interface
  - Combined hotkey and timing settings
  - One-click reset to defaults

For detailed development progress, see [CHANGELOG.md](CHANGELOG.md).

## Why WindowSmartMover?

### The Problem with Existing Solutions

Most window management apps are either:
- **Too heavy**: Packed with features you don't need
- **Closed source**: You can't verify what they're doing
- **Cloud-dependent**: Require accounts and subscriptions

WindowSmartMover is:
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

## Installation

### Requirements
- macOS 14.0 or later
- Accessibility permissions (required for window control)

### Download & Install

1. Download the latest release from [Releases](https://github.com/zembutsu/WindowSmartMover/releases)
2. Move `WindowSmartMover.app` to `/Applications/`
3. Launch the app
4. Grant Accessibility permissions when prompted:
   - System Settings → Privacy & Security → Accessibility
   - Enable WindowSmartMover

## Usage

### Basic Window Movement
1. Make sure a window is active (click on it)
2. Press `⌃⌥⌘→` to move to the next display
3. Press `⌃⌥⌘←` to move to the previous display

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

### Debug Log Viewer (v1.2.0+) 🚧
> **Note**: This feature is in development. Available in v1.2.0-beta and later.

1. Click the menu bar icon
2. Select "Show Debug Log"
3. View real-time logs of window operations
4. Use "Copy" to save logs for issue reporting
5. Use "Clear" to reset the log buffer

### Configuring Window Restore Timing (v1.2.0+) 🚧
> **Note**: This feature is in development. Available in v1.2.0-beta and later.

1. Click the menu bar icon
2. Select "Settings..."
3. Adjust "Window Restore Delay" slider (0.1-10.0 seconds)
4. Changes take effect immediately on next display reconnection

## Building from Source

### Prerequisites
- Xcode 15.0 or later
- macOS 14.0+ SDK

### Build Steps

```bash
# Clone the repository
git clone https://github.com/zembutsu/WindowSmartMover.git
cd WindowSmartMover

# Open in Xcode
open WindowSmartMover.xcodeproj

# Build and run (⌘R)
```

### Creating a Release Build

1. In Xcode: `Product → Archive`
2. Click `Distribute App`
3. Select `Copy App`
4. Choose export location

## How It Works

### Display Memory Technology
- **Periodic Snapshots**: Window positions saved every 5 seconds
- **CGWindowID Identification**: Each window uniquely identified
- **Display Detection**: Monitors display configuration changes via `NSApplication.didChangeScreenParametersNotification`
- **Smart Matching**: Restores windows based on app name + window ID

### Technical Stack
- **Language**: Swift 6.2
- **UI Framework**: SwiftUI
- **Window Control**: Accessibility API (AXUIElement)
- **Display Management**: CoreGraphics (CGWindow, NSScreen)
- **Hotkey Registration**: Carbon Event Manager

## Known Limitations

- Some apps (e.g., system preferences) may not support window movement via Accessibility API
- Fullscreen windows cannot be moved
- Display reconnection timing may vary by hardware (1.5-2s stabilization delay)

## Troubleshooting

### Windows not moving
- Verify Accessibility permissions are granted
- Try restarting the app
- Some apps don't support programmatic window control

### Automatic restoration not working
- **(v1.2.0+)** Check debug logs: Menu bar icon → "Show Debug Log" 🚧
- Ensure external display is properly detected
- Try manual window movement first to verify permissions
- Adjust window restore timing if displays need more stabilization time

### Using Debug Logs (v1.2.0+) 🚧
> **Note**: Debug log feature is available in v1.2.0-beta and later.

The debug log viewer helps diagnose issues:
1. Reproduce the problem
2. Open debug logs (Menu bar → "Show Debug Log")
3. Copy logs using the "Copy" button
4. Share logs when reporting issues on GitHub

**Privacy Note**: Debug logs are stored in memory only and contain:
- Display IDs (numeric identifiers, no personal info)
- Application names
- Window coordinates
- System events

No sensitive information is logged or transmitted.

## Roadmap

### In Development (v1.2.0)
- [x] Debug log viewer
- [x] Configurable window restore timing
- [ ] Internationalization (English UI + Japanese localization)

### Future Considerations
- [ ] Window size restoration (currently position only)
- [ ] Support for more than 2 displays
- [ ] Preferences for snapshot interval
- [ ] Per-app window restoration rules

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
