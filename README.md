# MenuBarLG

MenuBarLG is a native macOS menu bar app (Swift + AppKit) that renders a full-width visual overlay behind the menu bar on each connected display.

It supports two rendering modes:

- `Liquid Glass` (`NSGlassEffectView`, macOS 26+)
- `Backdrop Blur` (`NSVisualEffectView` materials + blending)

The app runs as an `LSUIElement` accessory app (no Dock icon) and is controlled from a status item and a settings window.

## Important: First Launch on Unsigned Builds

If macOS shows “Apple could not verify `MenuBarLG-Release`”, use one of these:

1. Finder: right-click `MenuBarLG-Release.app` -> `Open` -> `Open`.
2. `System Settings > Privacy & Security` -> `Open Anyway`.
3. Terminal fallback:

```bash
xattr -dr com.apple.quarantine /path/to/MenuBarLG-Release.app
```

## What It Does

- Renders a non-interactive overlay window per display at the top safe-area/menu-bar region.
- Reacts live to:
  - Theme changes (`Automatic`, `Light`, `Dark`)
  - System appearance switches
  - Accessibility `Reduce Transparency`
  - Display topology/resolution changes
- Supports blur enable/disable without destroying windows.
- Includes launch-at-login support using `SMAppService`.
- Provides live tuning controls with debounced persistence where appropriate.

## Key Features

### 1. Multi-Display Overlay Management

- Creates one borderless overlay window per active `NSScreen`.
- Diffs displays by display ID to avoid tearing down all windows on every screen change.
- Updates window frames on resolution/safe-area changes.

### 2. Notch/Safe-Area Aware Height

Overlay height is computed from:

- Top inset from `screen.frame.maxY - screen.visibleFrame.maxY`
- `NSStatusBar.system.thickness`
- `screen.safeAreaInsets.top`
- `screen.auxiliaryTopLeftArea?.height`
- `screen.auxiliaryTopRightArea?.height`

The maximum of these values is used so notch-area Macs align correctly.

### 3. Two Blur Modes With Mode-Specific Controls

#### Liquid Glass mode

- Primary rendering: `NSGlassEffectView`
- Variant options:
  - `Regular`
  - `Clear`
  - `Dock`
  - `AV Player`
  - `Control Center`
  - `Notification Center`
  - `Monogram`
- Style options: `Clear` / `Regular` (applies to `Regular` and `Clear` variants)
- Extra controls:
  - `Scrim` (adds opaque wash)
  - `Subdued` (flattens highlights)
  - Tint slider (`-2.0 ... 2.0`, black <-> white bias)

#### Backdrop Blur mode

- Rendering: layered `NSVisualEffectView` passes for stronger visible blur while keeping live backdrop sampling.
- Controls:
  - Material (`Menu`, `Sidebar`, `Header View`, `Window Background`, `Under Window Background`, `HUD Window`)
  - Blend mode (`Behind Window`, `Within Window`)
  - `Emphasized` toggle
  - `Alpha` slider (`0...1`)
  - `Intensity` slider (`0...1`)

### 4. Custom Corner Radii

- Optional per-corner radii controls in a dedicated `Corners` tab.
- Independent sliders for top-left/top-right/bottom-left/bottom-right.
- Real-time mask updates with sane clamping (`0...100 px`).

### 5. Accessibility Handling

When **Reduce Transparency** is enabled:

- Blur/glass rendering is replaced by a solid `NSColor.windowBackgroundColor` fallback.

When disabled:

- The selected blur mode is restored immediately.

### 6. Operability-Safe Status Icon Modes

Status icon modes:

- `Always Visible`
- `Show 5s On Startup`

Recovery safeguards for startup-only mode:

- Global shortcut: `⌃⌥⌘M` reveals the icon for 25 seconds and opens the menu.
- Opening Settings forces the icon visible while the settings window is open.
- Menu action: `Show Menu Icon for 25 Seconds`.

### 7. Settings Window (Tabbed)

- **General**
  - Enable Menu Bar Glass
  - Start App at Login
  - Menu Bar Icon visibility mode
  - Recovery shortcut hint
- **Appearance**
  - Theme mode (`Automatic`, `Light`, `Dark`)
  - Blur Type (`Liquid Glass`, `Backdrop Blur`)
  - Mode-specific controls shown contextually
- **Corners**
  - Enable custom corners
  - Per-corner radius sliders
  - Reset all corners
- **Credits**
  - Developer attribution
  - GitHub profile link

### 8. Persistence Model

- `BlurStyleManager` persists blur-mode configuration immediately via `UserDefaults`.
- `GlassTuningManager` persists tint/corner state with a 300ms debounce.
- Pending debounced writes are flushed on app termination.

## Technical Architecture

Each major area is isolated into dedicated classes:

- `AppDelegate.swift`
  - Composes the app graph and long-lived managers/controllers.
- `DisplayManager.swift`
  - Owns overlay windows and handles display diffing + overlay updates.
- `MenuBarOverlayWindow.swift`
  - Configures per-screen transparent overlay window properties.
- `GlassViewController.swift`
  - Applies Liquid Glass or Backdrop Blur appearance and fallback states.
  - Uses coalesced post-layout appearance application to avoid layout recursion.
- `ThemeManager.swift`
  - Maintains effective theme and reduce-transparency state.
  - Observes AppKit KVO + distributed notifications + accessibility notifications.
- `BlurStyleManager.swift`
  - Manages blur mode selection and per-mode controls/state persistence.
- `GlassTuningManager.swift`
  - Manages tint and corner controls with debounced persistence.
- `ToggleManager.swift`
  - Manages blur enabled state.
- `StatusItemVisibilityManager` (inside `ToggleManager.swift`)
  - Manages menu bar icon visibility mode.
- `StatusMenuController.swift`
  - Owns status item, menu actions, and hidden-mode recovery behavior.
- `SettingsWindowController.swift`
  - Builds and binds settings UI tabs and controls.
- `LaunchAtLoginManager.swift`
  - Integrates login item enable/disable/status (`SMAppService`).

## Requirements

- macOS `26.0+`
- Xcode `17+` (for macOS 26 SDK / `NSGlassEffectView`)
- Apple Developer membership is only required for Mac App Store distribution/signing workflows

## Build & Run

### Xcode

1. Open `MenuBarLG.xcodeproj`.
2. Select the `MenuBarLG` scheme.
3. Build and Run (`Cmd + R`).

### CLI (Debug)

```bash
xcodebuild -project MenuBarLG.xcodeproj -scheme MenuBarLG -configuration Debug build
```

## Release Packaging

### Scripted zip (recommended)

```bash
./scripts/create_release_zip.sh v1.0.0
```

This generates:

- `dist/MenuBarLG-v1.0.0.zip`

### Manual release build to repo root

```bash
xcodebuild -project MenuBarLG.xcodeproj -scheme MenuBarLG -configuration Release -sdk macosx -derivedDataPath ./build CODE_SIGNING_ALLOWED=NO build
mv build/Build/Products/Release/MenuBarLG.app MenuBarLG-Release.app
ditto -c -k --sequesterRsrc --keepParent MenuBarLG-Release.app MenuBarLG-Release.zip
```

## GitHub Release Example

Use whichever artifact you generated (`dist/MenuBarLG-v1.0.0.zip` or `MenuBarLG-Release.zip`).

```bash
git tag v1.0.0
git push origin v1.0.0
gh release create v1.0.0 <artifact-path>.zip --title "v1.0.0" --generate-notes
```

Note:

- Unsigned builds (`CODE_SIGNING_ALLOWED=NO`) can require right-click -> Open on first launch.

## Using the App

1. Launch app.
2. Click the status item icon (`menubar.rectangle` symbol).
3. Use:
   - `Open Settings…`
   - `Enable Menu Bar Glass` toggle
   - `Quit`
4. In Settings, tune appearance, corners, and startup/login behavior.

If icon visibility is `Show 5s On Startup` and the icon disappears:

- Press `Control + Option + Command + M` to restore it temporarily.

## Default Behavior

- Blur enabled on first launch.
- Theme mode: `Automatic`.
- Blur type: `Liquid Glass`.
- Liquid defaults:
  - Variant: `Dock`
  - Style: `Clear`
  - Scrim: off
  - Subdued: off
  - Tint: off (`0`)
- Backdrop defaults (when using Backdrop Blur):
  - Material: `HUD Window`
  - Blend mode: `Within Window`
  - Emphasized: on
  - Alpha: `100%`
  - Intensity: `76%`
- Custom corners: disabled, all radii `0 px`.
- Status icon mode: `Always Visible`.

## Window/Overlay Characteristics

Overlay windows are configured to be non-disruptive:

- `.borderless`, transparent, non-opaque
- `ignoresMouseEvents = true`
- Can temporarily become key/main to maintain active appearance rendering
- Collection behavior:
  - `.canJoinAllSpaces`
  - `.stationary`
  - `.ignoresCycle`
- Window level: `CGWindowLevelForKey(.mainMenuWindow)`

## Troubleshooting

### “I can’t see the status icon”

- Press `⌃⌥⌘M` to reveal it for 25 seconds.
- Or relaunch the app and use startup reveal window (if startup-only mode is enabled).

### “Blur disappeared”

- Check `System Settings > Accessibility > Display > Reduce transparency`.
- If enabled, MenuBarLG intentionally uses a solid fallback color.

### “Launch at login says approval required”

- Open `System Settings > General > Login Items`.
- Approve/enable the app entry.

### “Apple could not verify `MenuBarLG-Release`”

For unsigned local/GitHub builds, use one of these trusted-install paths:

1. In Finder, right-click `MenuBarLG-Release.app` -> `Open` -> `Open`.
2. If it is still blocked, go to `System Settings > Privacy & Security`, then click `Open Anyway` for MenuBarLG.
3. Terminal fallback (removes quarantine flag):

```bash
xattr -dr com.apple.quarantine /path/to/MenuBarLG-Release.app
```

### “Appearance changes feel delayed”

- Appearance mode switches apply immediately.
- Tint/corner persistence is debounced (preview remains live).

## Privacy, APIs, and Dependencies

- No third-party dependencies.
- No runtime network requirement.
- Uses standard Apple frameworks (`AppKit`, `ServiceManagement`, `Carbon` for hotkey registration).
- Liquid Glass variant/scrim/subdued controls use private selectors on `NSGlassEffectView`.
  - Practical implication: this can be fragile across macOS updates and may not be appropriate for App Store review.

## Credits

- Developer: Parishkar Singh
- GitHub: https://github.com/parishkar-singh

## Roadmap Ideas

- Export/import appearance profiles.
- Optional onboarding prompt for hidden icon mode recovery.
- Optional keyboard shortcut customization.
