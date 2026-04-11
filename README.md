# 👁️ Lightweight ESP & LegitBot v3.1 (Premium)

A lightweight, high-performance, and low-level executor compatible utility for Roblox. Designed for **zero performance impact** and **maximum compatibility** — no Drawing library or high-UNC functions required.

## ⚡ Quick Start

Paste this into **any** executor and run:

```lua
loadstring(game:HttpGet("https://raw.githubusercontent.com/HANN77/ESP-Roblox-Legit/main/LightweightESP.lua"))()
```

---

## ✨ Features

| Feature | Description |
|---------|-------------|
| **Legit Aim Assist** | Smooth tracking with FOV check and Head/Body target selection |
| **JSON Configs** | Save and Load multiple setting profiles as JSON files |
| **Tracers** | Optimized lines from screen bottom to each enemy |
| **Health Bars** | Dynamic, color-coded bars (red → yellow → green) |
| **Bounding Boxes** | Standard and **Corner** box options with distance fading |
| **High-Tier Chams** | GPU-rendered full-body highlights (Bypasses 31-Highlight limit) |
| **Mini Radar** | Mini-map with smooth camera rotation and enemy tracking |
| **Names & Dist** | High-visibility player info rendered via native labels |
| **HSV Customization**| Full Color Picker for all visual elements |

---

## 🎮 Controls

| Key/Input | Action |
|-----|--------|
| `H` | Toggle ESP System on/off |
| `Right Shift` | Show/Hide Settings Panel |
| `Right Click` | **Aim Assist** (Hold to track target) |
| `Z` | FOV Zoom (Hold to zoom) |

---

## 🖥️ UI Tabs

### 🏠 Home
*   Overview of the script version and features.
*   System status and credits.

### 👁️ Visuals
*   **ESP Toggles**: Tracers, Boxes, Names, Distance, Radar.
*   **Box Style**: Toggle between Standard and **Corner** boxes.
*   **Distance Culling**: Adjustable range from 50 to 2000 studs.
*   **Team Options**: Exclude teammates or use Team Colors for ESP.
*   **HSV Color Picker**: Real-time color adjustment for all visual elements.

### 🎯 Combat
*   **Aim Assist**: Smoothly assists your aim toward the nearest target in FOV.
*   **Target Selection**: Switch between **Head** and **Body** targeting.
*   **Smoothing**: Adjustable interpolation (1–25) for human-like movement.
*   **Aim FOV**: Adjustable FOV circle size on screen.

### 🌫️ Misc
*   **Fullbright**: Adjustable world brightness (Gamma boost).
*   **Remove Fog**: Removes standard Roblox lighting fog for clear visibility.
*   **Unload**: Cleanly destroys all GUI and rendering threads.

### 💾 Config
*   **Save/Load**: Save your custom settings to `LightweightESP/Configs/*.json`.
*   **Auto-Load**: The `default` profile automatically loads on every execution.

---

## 🔧 Why Native-Instance Oriented?

Most ESP scripts require the `Drawing` library or high-UNC functions that only work on premium executors. This script uses **only native Roblox instances**:

- `Frame` / `TextLabel` — for tracers, health bars, radar dots, boxes, names, distance.
- `Highlight` — native Roblox full-body outline (zero-cost, GPU-rendered).
- `workspace:Raycast` — for accurate visibility checks behind walls.

Works on: **Solara, Fluxus, Arceus X, Delta, JJSploit**, and any executor that supports `CoreGui` parenting + `HttpGet`.

---

## ⚡ Performance

Built to be lightweight with **<2% FPS impact**:

- **Object Pooling**: 24 pre-allocated ESP slots, zero runtime `Instance.new` calls.
- **Frame Throttling**: Intelligent render-loop throttling to save CPU cycles.
- **Distance-Based Sorting**: Intelligently prioritizes Highlights for the closest 31 players to stay within engine limits.
- **Viewport Culling**: Skips off-screen player calculations automatically.

---

## 🛡️ Anti-Detection

- **Random GUI Naming**: Bypasses many simple GUI-scanning anti-cheats.
- **No Metatable Tampering**: Does not hook `Index`, `NewIndex`, or `Namecall`.
- **Screen-Space Only**: Pure rendering without modifying game memory or player characters.
- **Clean Teardown**: Leaves zero traces in CoreGui after unloading.

---

## 📝 Credits

Made by **FusedHann** (v3.1)

---

*If this script helped you, give the repository a ⭐!*
