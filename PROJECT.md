# Tsubame Project

This document is the entry point for developers and automated systems working on this project.

## Document Structure

| Document | Audience | Content |
|----------|----------|---------|
| **PROJECT.md** (this) | Developers, Systems | Project overview, principles, design philosophy |
| README.md | Users | Installation, usage, features |
| ARCHITECTURE.md | Developers, Systems | Technical structure, data flow, design decisions |
| WORKFLOW.md | Developers, Systems | Session workflow, AI collaboration rules |
| CHANGELOG.md | Everyone | Version history, changes |

## Project Vision

Tsubame is a macOS app that solves window position issues when connecting external displays.

**Problems Solved**:
- Windows lose their positions when external displays are disconnected/reconnected
- macOS does not automatically restore window layouts
- Manual repositioning is inefficient and frustrating

**Design Philosophy**:
- Simple, lightweight menu bar app
- Automation first (minimize user interaction)
- Privacy-focused (no data sent externally)

## Current Status

- **Version**: v1.4.0 (in development)
- **Latest Release**: v1.3.0 (Apple notarized)

## Development Principles

### 1. Incremental Refactoring

Large changes are split into Phases:
- Each Phase can be tested and released independently
- Enables easy rollback if issues arise

### 2. Documentation-Driven

- Design decisions are recorded in Issues
- Clarify approach before implementation
- Include reasoning in commit messages

### 3. System-Assisted Development

This project uses Bebop Style Development methodology:
- Session-based development with clear handoff
- AI assists with implementation, human approves
- See WORKFLOW.md for details

## Roadmap

### Completed
- v1.2.11: Emergency fixes (#50, #54, #56 workarounds)
- v1.2.12: Display sleep handling (Phase 1)
- v1.2.13: Architecture refactoring (Phase 2-4)
- v1.3.0: Stable release, Apple notarization, screen topology detection (#67)

### In Progress
- v1.4.0: Focus Follows Mouse (#72, PR #73 merged)

### Planned
- #42: Launch at Login
- #67: Screen topology detection
- #68: Hotkey redesign for directional screen movement
- #75: Display stabilization overlay indicator
- #76: layoutSubtreeIfNeeded warning investigation

## For Automated Systems

When working on this project:

1. Read **WORKFLOW.md** first for session procedures
2. Read **ARCHITECTURE.md** to understand code structure
3. Check **GitHub Issues** for current tasks and plans
4. Propose large changes in Phase units
5. Include design reasoning in commit messages

## Repository

- GitHub: https://github.com/zembutsu/tsubame
- Issues: https://github.com/zembutsu/tsubame/issues
