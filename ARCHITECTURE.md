# ARCHITECTURE.md - Tsubame Project Structure

> Last Updated: 2025-12-22 (S003)
> For AI/Developer Navigation

---

## Overview

Tsubame is a macOS menu bar application for window management across multiple displays. Built with Swift/SwiftUI, using Accessibility API and Carbon API for window control and global hotkeys.

---

## File Structure

```
Tsubame/
├── AppDelegate.swift          # Main application logic (~2366 lines)
├── SettingsView.swift         # Settings UI (SwiftUI)
├── TimerManager.swift         # Centralized timer management
├── FocusFollowsMouseManager.swift  # Focus follows mouse feature
├── PauseManager.swift         # Pause/Lock state management
├── WindowTimingSettings.swift # Display timing configuration
├── SnapshotSettings.swift     # Auto-snapshot configuration
├── ManualSnapshotStorage.swift # Snapshot persistence
├── AboutView.swift            # About window
└── Assets/                    # Icons, images
```

---

## AppDelegate.swift - Line Number Map

> **This is the largest file. Use this map for efficient navigation.**

### Global Scope (L1-173)

| Lines | Content | Description |
|-------|---------|-------------|
| L1-8 | Imports & globals | Cocoa, Carbon, SwiftUI, globalAppDelegate |
| L11-71 | `hotKeyHandler()` | C event handler for global hotkeys |
| L74-127 | `DebugLogger` class | Log management, app name masking |
| L130-173 | `DebugLogView` struct | Debug log viewer UI |

### AppDelegate Class (L176-2366)

#### Properties (L176-236)
| Lines | Property | Purpose |
|-------|----------|---------|
| L177-180 | `statusItem`, `menu` | Menu bar integration |
| L182-185 | `settingsWindow`, `aboutWindow` | Window references |
| L187-195 | `windowPositions`, `manualSnapshots` | Snapshot storage |
| L197-210 | Display change tracking | `lastDisplayChangeTime`, `isMonitoringEnabled`, etc. |
| L212-225 | Timing constants | `fallbackWaitDelay`, `restoreCooldown`, etc. |
| L227-235 | Timer & state | `timerManager`, `lastScreenCount` |

#### Initialization (L237-381)
| Lines | Method | Description |
|-------|--------|-------------|
| L237-340 | `applicationDidFinishLaunching()` | **Main entry point** - setup sequence |
| L342-352 | `setupNotifications()` | UNUserNotificationCenter setup |
| L354-381 | `sendNotification()` | Send system notifications |

#### Menu Setup (L383-641)
| Lines | Method | Description |
|-------|--------|-------------|
| L383-506 | `setupMenu()` | **Menu bar construction** |
| L507-537 | `selectSlot()`, `selectSlotByHotkey()` | Slot selection handlers |
| L539-590 | **Pause Control** | `togglePause()`, `resumeFromMenu()`, `pauseForDuration()` |
| L578-590 | `updateMenuBarIcon()` | Icon state management |
| L592-641 | Status string helpers | `getSlotStatusString()`, `getSnapshotStatusString()` |

#### Windows (L643-694)
| Lines | Method | Description |
|-------|--------|-------------|
| L643-660 | `openSettings()` | Settings window |
| L661-677 | `openAbout()` | About window |
| L679-694 | `showDebugLog()` | Debug log window |

#### Hotkey Registration (L696-875)
| Lines | Method | Description |
|-------|--------|-------------|
| L696-707 | `checkAccessibilityPermissions()` | Accessibility API check |
| L709-787 | `registerHotKeys()` | **Hotkey registration** (14 keys) |
| L789-814 | `showHotkeyRegistrationWarning()` | Warning dialog |
| L816-875 | `unregisterHotKeys()` | Cleanup |

#### Window Movement (L876-1141)
| Lines | Method | Description |
|-------|--------|-------------|
| L876-883 | `moveWindowToNextScreen/Prev()` | Display switching |
| L884-896 | `Direction`, `NudgeDirection` enums | Direction definitions |
| L897-987 | `nudgeWindow()` | **Pixel-level positioning** |
| L988-1004 | Nudge menu actions | `nudgeWindowUp/Down/Left/Right()` |
| L1006-1141 | `moveWindow()` | **Core window movement logic** |

#### Display Change Handling (L1143-1329)
| Lines | Method | Description |
|-------|--------|-------------|
| L1143-1152 | `setupDisplayChangeObserver()` | NSNotification observer |
| L1154-1183 | `setupMonitoringControlObservers()` | Sleep/wake observers |
| L1186-1229 | `displayConfigurationChanged()` | **Display event handler** |
| L1232-1237 | `startStabilizationCheck()` | Timer start |
| L1239-1262 | `checkStabilization()` | **Stabilization logic** |
| L1265-1275 | `fallbackRestoration()` | Fallback trigger |
| L1277-1329 | `triggerRestoration()` | **Restore scheduling** |

#### Sleep/Wake (L1332-1400)
| Lines | Method | Description |
|-------|--------|-------------|
| L1332-1343 | `pauseMonitoring()` | Pause display monitoring |
| L1345-1353 | `isUserLoggedIn()` | Login check (SCDynamicStore) |
| L1367-1375 | `handleSystemSleep()` | System sleep handler |
| L1376-1384 | `handleSystemWake()` | System wake handler |
| L1386-1400 | `handleScreensDidSleep/Wake()` | Display sleep handlers |

#### Snapshot Capture (L1402-1523)
| Lines | Method | Description |
|-------|--------|-------------|
| L1402-1409 | `getDisplayIdentifier()` | Screen ID extraction |
| L1411-1420 | `startPeriodicSnapshot()` | Periodic timer start |
| L1422-1523 | `takeWindowSnapshot()` | **Window enumeration & capture** |

#### Manual Snapshot (L1525-1856)
| Lines | Method | Description |
|-------|--------|-------------|
| L1525-1612 | `saveManualSnapshot()` | **Manual save** (Ctrl+Cmd+↑) |
| L1614-1739 | `restoreManualSnapshot()` | **Manual restore** (Ctrl+Cmd+↓) |
| L1741-1856 | `findMatchingWindow()` | Window matching algorithm |

#### Window Restore (L1858-2029)
| Lines | Method | Description |
|-------|--------|-------------|
| L1858-2029 | `restoreWindowsIfNeeded()` | **Auto-restore logic** |

#### Auto Snapshot (L2032-2329)
| Lines | Method | Description |
|-------|--------|-------------|
| L2035-2059 | `loadSavedSnapshots()` | UserDefaults load |
| L2061-2099 | `setupSnapshotSettingsObservers()` | Settings observers |
| L2091-2099 | `setupHotkeySettingsObserver()` | Hotkey change observer |
| L2102-2112 | `setupPauseStateObserver()` | Pause state observer |
| L2114-2133 | `reregisterHotkeys()` | Hotkey re-registration |
| L2135-2148 | `restartDisplayMemoryTimer()` | Timer restart |
| L2150-2199 | Initial/Periodic timer setup | Timer scheduling |
| L2202-2309 | `performAutoSnapshot()` | **Auto-snapshot execution** |
| L2311-2329 | `schedulePostDisplayConnectionSnapshot()` | Post-connection snapshot |

#### Cleanup (L2332-2366)
| Lines | Method | Description |
|-------|--------|-------------|
| L2332-2353 | `applicationWillTerminate()` | App termination cleanup |
| L2355-2359 | `debugPrint()` | Global debug logging |
| L2361-2366 | `verbosePrint()` | Verbose logging (conditional) |

---

## Singleton Managers

| Class | File | Purpose |
|-------|------|---------|
| `PauseManager.shared` | PauseManager.swift | Pause/Lock state |
| `TimerManager.shared` | TimerManager.swift | All timers |
| `FocusFollowsMouseManager.shared` | FocusFollowsMouseManager.swift | Focus follows mouse |
| `WindowTimingSettings.shared` | WindowTimingSettings.swift | Display timing |
| `SnapshotSettings.shared` | SnapshotSettings.swift | Auto-snapshot config |
| `ManualSnapshotStorage.shared` | ManualSnapshotStorage.swift | Snapshot persistence |
| `DebugLogger.shared` | AppDelegate.swift (L74) | Log management |

---

## Data Flow

### Display Reconnection Flow
```
NSApplication.didChangeScreenParametersNotification
    ↓
displayConfigurationChanged() [L1186]
    ├── FocusFollowsMouseManager.suspendForDisplayChange()
    ├── isMonitoringEnabled check
    └── startStabilizationCheck() [L1232]
            ↓
        checkStabilization() [L1239] (every 0.5s)
            ↓ (when stable)
        triggerRestoration() [L1277]
            ↓
        restoreWindowsIfNeeded() [L1858]
            ↓
        FocusFollowsMouseManager.resumeAfterDisplayChange()
```

### Hotkey Flow
```
Carbon Event (hotKeyHandler) [L11]
    ↓
DispatchQueue.main.async
    ↓
PauseManager.isPaused check
    ↓
AppDelegate method call (moveWindow, nudgeWindow, etc.)
```

### Snapshot Flow
```
takeWindowSnapshot() [L1422]
    ↓
CGWindowListCopyWindowInfo (get all windows)
    ↓
Filter by activationPolicy, bounds
    ↓
Store in manualSnapshots[slotIndex]
    ↓
ManualSnapshotStorage.save() (persist)
```

---

## Key APIs Used

| API | Purpose | Location |
|-----|---------|----------|
| `AXUIElementCopyAttributeValue` | Window properties | L1006+, L897+ |
| `AXUIElementSetAttributeValue` | Window position/size | L1006+, L897+ |
| `CGWindowListCopyWindowInfo` | Window enumeration | L1422+ |
| `InstallEventHandler` | Global hotkeys | L709+ |
| `NSEvent.addGlobalMonitorForEvents` | Mouse monitoring | FocusFollowsMouseManager |
| `SCDynamicStoreCopyConsoleUser` | Login check | L1345 |

---

## Settings Architecture

### SettingsView.swift Structure
- **Basic Tab**: Hotkeys, Nudge, Focus Behavior, Auto-snapshot
- **Advanced Tab**: Timing, Sleep behavior, Debug options

### UserDefaults Keys (Partial)
```swift
// Focus Follows Mouse
"focusFollowsMouseEnabled"
"focusFollowsMousePreset"
"focusFollowsMouseUseCustom"
"focusFollowsMouseCustomDelay"

// Pause
"pauseResumeOnRelaunch"
"pauseResumeOnWake"

// Timing
"displayStabilizationDelay"
"windowRestoreDelay"
```

---

## Adding New Features - Checklist

1. **New Singleton Manager?**
   - Create `XxxManager.swift`
   - Initialize in `applicationDidFinishLaunching()`
   - Add to this ARCHITECTURE.md

2. **New Settings?**
   - Add to `SettingsView.swift` (appropriate tab)
   - Add UserDefaults keys
   - Add to `resetToDefaults()` in SettingsView

3. **Integration with Existing Systems?**
   - Check `PauseManager.isPaused`
   - Consider display stabilization flow
   - Update `setupMenu()` if menu item needed

4. **Hotkey?**
   - Add to `registerHotKeys()` HotKeyDef array
   - Add case to `hotKeyHandler` switch

---

## Known Issues / Technical Debt

| Issue | Location | Notes |
|-------|----------|-------|
| AppDelegate too large | AppDelegate.swift | Consider splitting into extensions |
| `layoutSubtreeIfNeeded` warning | Startup | SwiftUI/AppKit layout conflict |
| Hardcoded menu bar height | FocusFollowsMouseManager L200 | 24px assumed |

---

## Document Information

- Version: 1.0
- Created: 2025-12-22 (S003)
- Author: Claude (AI) with Zem
- Purpose: AI/Developer navigation efficiency
