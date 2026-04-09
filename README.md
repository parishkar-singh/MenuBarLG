# MenuBarLG

MenuBarLG is a native macOS menu bar app (Swift + AppKit) that renders a full-width Liquid Glass overlay behind the menu bar on each connected display.

The app runs as an `LSUIElement` accessory app (no Dock icon) and is controlled from a status item and a settings window.

## What It Does

- Renders a non-interactive overlay window per display at the top safe-area/menu-bar region.
- Uses `NSGlassEffectView` (macOS 26+) for Liquid Glass rendering.
- Reacts live to:
  - Theme changes (`Automatic`, `Light`, `Dark`)
  - System appearance switches
  - Accessibility `Reduce Transparency`
  - Display topology/resolution changes
- Supports blur enable/disable without destroying windows.
- Includes launch-at-login support using `SMAppService`.
- Provides per-preset tuning controls with live preview and debounced persistence.

## Key Features

### 1. Multi-Display Overlay Management

- Creates one borderless overlay window per active `NSScreen`.
- Diffs displays by display ID to avoid tearing down all windows on every screen change.
- Updates window frames on resolution/safe-area changes.

### 2. Notch/Safe-Area Aware Height

Overlay height is computed from:

- `NSStatusBar.system.thickness`
- `screen.safeAreaInsets.top`
- `screen.auxiliaryTopLeftArea?.height`
- `screen.auxiliaryTopRightArea?.height`

The maximum of these values is used so notch-area Macs align correctly.

### 3. Liquid Glass Rendering + Edge Treatment

- Primary rendering: `NSGlassEffectView`
- Presets: `More Liquid`, `Normal`, `Frosted`
- Per-preset controls:
  - Alpha (`0...1`)
  - Tint (`-1...1`)
    - Positive = white tint
    - Negative = black tint overlay
- Bottom-only border and shadow layers emulate Dock-like edge separation.

### 4. Accessibility Handling

When **Reduce Transparency** is enabled:

- Liquid Glass is replaced by a solid `NSColor.windowBackgroundColor` fallback.

When disabled:

- Liquid Glass rendering is restored immediately.

### 5. Operability-Safe Status Icon Modes

Status icon modes:

- `Always Visible`
- `Show 5s On Startup`

Recovery safeguards for startup-only mode:

- Global shortcut: `⌃⌥⌘M` reveals the icon for 25 seconds and opens the menu.
- Opening Settings forces the icon visible while the settings window is open.
- Menu action: `Show Menu Icon for 25 Seconds`.

This avoids “no way back” states and removes dependency on Activity Monitor force-kill.

### 6. Settings Window (Structured Sections)

- **General**
  - Enable Menu Bar Glass
  - Start App at Login
  - Menu Bar Icon visibility mode
  - Recovery shortcut hint
- **Appearance**
  - Theme mode (`Automatic`, `Light`, `Dark`)
  - Glass feel preset (`More Liquid`, `Normal`, `Frosted`)
- **Tuning**
  - Per-preset alpha/tint sliders
  - Reset to defaults
- **Credits**
  - Developer attribution
  - GitHub profile link

### 7. Persistence Model

No external JSON file polling is used.

- Live state updates immediately for on-screen preview.
- Persisted state is debounced (300ms) and stored in `UserDefaults`.
- Pending writes are flushed on app termination.

## Technical Architecture

Each major area is isolated into dedicated classes:

- `AppDelegate.swift`
  - Composes the app graph and long-lived managers/controllers.
- `DisplayManager.swift`
  - Owns overlay windows and handles display diffing + overlay updates.
- `MenuBarOverlayWindow.swift`
  - Configures per-screen transparent overlay window properties.
- `GlassViewController.swift`
  - Applies Liquid Glass appearance and fallback states.
  - Uses coalesced post-layout appearance application to avoid layout recursion.
- `ThemeManager.swift`
  - Maintains effective theme and reduce-transparency state.
  - Observes AppKit KVO + distributed notifications + accessibility notifications.
- `BlurStyleManager.swift`
  - Manages selected preset and persistence.
- `GlassTuningManager.swift`
  - Manages per-preset alpha/tint live state and debounced persistence.
- `ToggleManager.swift`
  - Manages blur enabled state.
- `StatusItemVisibilityManager` (inside `ToggleManager.swift`)
  - Manages menu bar icon visibility mode.
- `StatusMenuController.swift`
  - Owns status item, menu actions, and hidden-mode recovery behavior.
- `SettingsWindowController.swift`
  - Builds and binds settings UI sections.
- `LaunchAtLoginManager.swift`
  - Integrates login item enable/disable/status (`SMAppService`).

## Requirements

- macOS `26.0+`
- Xcode `17+` (for macOS 26 SDK / `NSGlassEffectView`)
- Apple Developer membership is only required for Mac App Store distribution

## Build & Run

### Xcode

1. Open `MenuBarLG.xcodeproj`.
2. Select the `MenuBarLG` scheme.
3. Build and Run (`Cmd + R`).

### CLI

```bash
xcodebuild -project MenuBarLG.xcodeproj -scheme MenuBarLG -configuration Debug build
```

## GitHub Releases Distribution

You can distribute builds through GitHub Releases without App Store submission.

### Local release package

```bash
./scripts/create_release_zip.sh v1.0.0
```

This generates:

- `dist/MenuBarLG-v1.0.0.zip`

### Manual GitHub release

1. Build artifact locally:

```bash
./scripts/create_release_zip.sh v1.0.0
```

2. Create release and upload artifact with GitHub CLI:

```bash
gh release create v1.0.0 dist/MenuBarLG-v1.0.0.zip --title "v1.0.0" --generate-notes
```

Tag command example:

```bash
git tag v1.0.0
git push origin v1.0.0
```

Note:

- The ZIP build is unsigned (`CODE_SIGNING_ALLOWED=NO`), so some users may need right-click -> Open on first launch.

## Using the App

1. Launch app.
2. Click status item icon (`menubar.rectangle` symbol).
3. Use:
   - `Settings…`
   - `Enable Menu Bar Glass` toggle
   - `Quit`
4. In Settings, tune appearance and startup/login behavior.

If icon visibility is `Show 5s On Startup` and the icon disappears:

- Press `Control + Option + Command + M` to restore it temporarily.

- <img width="1470" height="99" alt="image" src="https://github.com/user-attachments/assets/71ebef4a-eeba-4d09-942a-ab1d27c5a070" />


## Default Behavior

- Blur enabled on first launch.
- Theme mode: `Automatic`.
- Material preset: `More Liquid`.
- Status icon mode: `Always Visible`.
- Tuning defaults:
  - More Liquid: alpha `0.90`, style `clear`, tint `0.00`
  - Normal: alpha `0.90`, style `regular`, tint `0.05`
  - Frosted: alpha `1.00`, style `regular`, tint `0.50`

## Window/Overlay Characteristics

Overlay windows are configured to be non-disruptive:

- `.borderless`, transparent, non-opaque
- `ignoresMouseEvents = true`
- Cannot become key/main
- Collection behavior:
  - `.canJoinAllSpaces`
  - `.stationary`
  - `.ignoresCycle`
- Window level: `CGWindowLevelForKey(.mainMenuWindow)`

## Troubleshooting

### “I can’t see the status icon”

- Press `⌃⌥⌘M` to reveal it for 25 seconds.
- Or relaunch the app and use startup reveal window (if startup-only mode is enabled).

### “Reduce Transparency is ON and blur is gone”

- Expected behavior. The app intentionally switches to a solid fallback color.

### “Launch at login says approval required”

- Open: `System Settings > General > Login Items`
- Approve/enable the app entry.

### “Appearance changes feel delayed”

- Slider writes are debounced for persistence, but preview updates are immediate.

## Privacy and Dependencies

- No third-party dependencies.
- No private APIs.
- No network requirement for runtime operation.
- Uses only standard Apple frameworks (`AppKit`, `ServiceManagement`, `Carbon` for hotkey registration).

## Credits

- Developer: Parishkar Singh
- GitHub: https://github.com/parishkar-singh

## Roadmap Ideas

- Export/import tuning profiles.
- Optional onboarding prompt for hidden icon mode recovery.
- Optional keyboard shortcut customization.
