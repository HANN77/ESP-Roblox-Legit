# 👁 Lightweight ESP v2.7

A lightweight, low-level executor compatible ESP script for Roblox. Designed for **minimal performance impact** and **maximum compatibility** — no Drawing library or high-UNC functions required.

## ⚡ Quick Start

Paste this into **any** executor and run:

```lua
loadstring(game:HttpGet("https://raw.githubusercontent.com/HANN77/ESP-Roblox-Legit/main/LightweightESP.lua"))()
```

## ✨ Features

| Feature | Description |
|---------|-------------|
| **Tracers** | Lines from screen bottom to each enemy |
| **Health Bars** | Color-coded bars (red → yellow → green) |
| **Highlight** | Full-body outline + glow (visible through walls) |
| **Radar** | Mini-map with camera-rotated enemy dots |
| **Names** | Displays player DisplayName above them |
| **Distance** | Shows distance in studs below each player |
| **Team Exclusion** | Toggle to hide your own teammates |
| **Max Distance** | Adjustable range: 50 – 2000 studs |

## 🎮 Default Keybinds

| Key | Action |
|-----|--------|
| `H` | Toggle ESP on/off |
| `Right Shift` | Show/hide settings panel |
| `Z` | FOV Zoom (Hold to zoom) |

> You can customize the key bindings however you like from the settings panel.

## 🖥️ Settings Panel

The draggable GUI panel lets you toggle each feature individually:

- ✅ ESP Enabled
- ✅ Tracers
- ✅ Health Bars
- ✅ Highlight (full-body outline)
- ✅ Names
- ✅ Distance
- ✅ Radar
- ✅ Exclude Team
- 🔧 Max Distance (adjustable with +/− buttons or manual input)
- 🔧 Keybind remapping
- 🎯 Enable Zoom (Combat Tab)
- 🔧 Zoom FOV magnitude
- 💾 Config Save/Load System (JSON serialization)
- ⏻ Unload button for clean teardown

## 🔧 Why Low-Level Executor Compatible?

Most ESP scripts require the `Drawing` library or high-UNC/SUNC functions that only work on premium executors. This script uses **only native Roblox instances**:

- `Frame` / `TextLabel` — for tracers, health bars, radar dots, names, distance
- `Highlight` — native Roblox full-body outline (zero-cost, GPU-rendered)
- `Camera:WorldToViewportPoint()` — for screen-space projection

**No** `Drawing`, **no** `hookfunction`, **no** `getrawmetatable`, **no** `newcclosure`.

Works on: **Solara, Fluxus, Arceus X, Delta, JJSploit**, and any executor that supports `CoreGui` parenting + `HttpGet`.

## ⚡ Performance

Built to be lightweight with **<2% FPS impact**:

- **Object Pooling** — 24 pre-allocated ESP slots, zero runtime `Instance.new` calls
- **Frame Throttling** — renders every 2nd frame instead of every frame
- **Distance Culling** — ignores players beyond your max distance
- **Viewport Culling** — skips off-screen players automatically
- **Fade-by-Distance** — transparency scales with distance

## 🛡️ Anti-Detection

- Random GUI naming (changes every execution)
- No modification of other players' characters
- No remote event hooking or metatable tampering
- Pure client-side screen-space rendering
- Clean unload with full instance teardown

## 📋 Color Legend

| Color | Meaning |
|-------|---------|
| 🟦 Cyan | Tracers / highlight outline / your radar dot |
| 🟪 Magenta | Highlight body fill |
| 🟥 Red | Enemy dots on radar |
| 🟩 Green → 🟨 Yellow → 🟥 Red | Health bar gradient |

## ⚠️ Disclaimer

This script is for **educational purposes only**. Use at your own risk. The developer is not responsible for any bans or consequences resulting from use of this script.

## 📝 Credits

Made by **FusedHann**

---

*If this helped you, give the repo a ⭐!*
