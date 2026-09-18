<p align="center">
  <img src="icon.png" alt="ApexFlow Logo" width="180"/>
</p>

<h1 align="center">ApexFlow</h1>

<p align="center">
  <strong>Human-like AI & Race Control for Assetto Corsa</strong><br/>
  <em>2 lightweight apps: ApexFlow Core + ApexFlow Events HUD</em><br/>
  Thinking AI • Clean 2×2 starts • Live delta gaps • Persistent penalty points
</p>

<p align="center">
  <a href="https://github.com/Silxyst/ApexFlow/releases/latest">
    <img src="https://img.shields.io/github/v/release/Silxyst/ApexFlow?style=for-the-badge&label=DOWNLOAD&color=ff6a15&logo=github" alt="Latest Release"/>
  </a>
  <img src="https://img.shields.io/badge/Version-v0.32.6-ff6a15?style=for-the-badge&label=App" alt="Version"/>
  <img src="https://img.shields.io/badge/CSP-0.3.0-00d4ff?style=for-the-badge" alt="CSP"/>
  <img src="https://img.shields.io/badge/Platform-Windows-0078d6?style=for-the-badge&logo=windows" alt="Platform"/>
  <a href="https://github.com/Silxyst/ApexFlow/blob/main/LICENSE">
    <img src="https://img.shields.io/github/license/Silxyst/ApexFlow?style=for-the-badge&color=8b5cf6" alt="License"/>
  </a>
</p>

<p align="center">
  <img src="https://img.shields.io/badge/Apps-2-22c55e?style=flat-square" alt="Apps"/>
  <img src="https://img.shields.io/badge/Modules-10-22c55e?style=flat-square" alt="Modules"/>
  <img src="https://img.shields.io/badge/Offline-100%25-22c55e?style=flat-square" alt="Offline"/>
  <img src="https://img.shields.io/badge/Errors-0-22c55e?style=flat-square" alt="Errors"/>
  <img src="https://img.shields.io/badge/Rain-Supported-00d4ff?style=flat-square" alt="Rain"/>
  <img src="https://img.shields.io/badge/Language-EN-ff6a15?style=flat-square" alt="Language"/>
</p>

<p align="center">
  <a href="#-why-apexflow">Why ApexFlow?</a> •
  <a href="#-features">Features</a> •
  <a href="#-installation">Installation</a> •
  <a href="#-configuration">Configuration</a> •
  <a href="#-quick-start">Quick Start</a> •
  <a href="#-remote-panel">Remote Panel</a> •
  <a href="#-api">API</a> •
  <a href="#-roadmap">Roadmap</a>
</p>

---

## 🎯 Why ApexFlow?

> **AI that thinks instead of crashing.** Every driver has a personality, picks its own line, brakes progressively into slow corners, and only attacks on straights with a real gap — no kamikaze dives, no train formation.

- 🪶 **Lightweight:** 10 modules • ~260 KB • 3 windows • zero errors in `custom_shaders_patch.log`
- 🔌 **Offline-first:** no online dependencies, per-track `ApexFlow_config.lua` auto-save
- 🏁 **2 apps:** `ApexFlow` core (`1024×760` + setup) + `ApexFlow Events` HUD overlay (`360×260`)
- 🌧️ **Rain-aware:** grip logic desensitized in the wet, AI keeps its pace instead of crawling
- 🚩 **No conflicts:** flags and track limits are handled by AC itself — no double penalties

---

## ✨ Features

| System | What it does | Where |
|---|---|---|
| 🧠 **Thinking AI** | `Chill / Normal / Attack` mix (0–100, try 65–70) • 5-class multiclass support • attacks only on straights with a 6–150 m gap and closing speed • aborts dives before braking zones • own line per driver, yields side-by-side in corners | `Drivers` tab |
| 🏁 **Race & Starts** | Aligned 2×2 rolling formation • adaptive fuel strategy with mandatory stops • real pit speed limit • endurance presets (Sprint → 24h) | `Race` tab |
| 📏 **Live gaps** | Gap to leader in meters • gap + time delta to the car behind (blue when lapped) • per-sector delta, wrap-safe | `Events` HUD |
| 📊 **Penalty points** | L1 = 1 PP … L6 = 6 PP, persisted across sessions via `ac.storage` | `Events` HUD |
| 🌐 **Remote panel** | Live dashboard on PC + phone over Wi-Fi (`panel.html`, 0.5 s refresh) + OBS browser source | `System` tab |
| ☁️ **Extras** | GitHub update checker • per-track learning memory • lap telemetry CSV | `System` tab |

---

## 📦 Installation

**Requirements:** `Assetto Corsa` + `Custom Shaders Patch 0.3.0+` + `Content Manager` + offline session.

```bash
1. Download ApexFlow_v0.32.2.zip from https://github.com/Silxyst/ApexFlow/releases/latest
2. Extract into Assetto Corsa/apps/lua/  (creates/updates the ApexFlow/ folder)
3. Content Manager → Apps → enable ApexFlow + ApexFlow Events
4. In AC → Apps sidebar → ApexFlow
```

<details>
<summary><strong>📁 Package contents (v0.32.2)</strong></summary>

```
ApexFlow/
├─ manifest.ini (3 windows)
├─ ApexFlow.lua (core loop, 8 guarded modules)
├─ icon.png
├─ sfx/rs_beep.wav
├─ src/
│  ├─ ai_controller.lua  (thinking race AI)
│  ├─ gap_behind.lua     (gap + delta + lapped flag)
│  ├─ github_update.lua  (release checker)
│  ├─ memory.lua         (per-track memory)
│  ├─ penalty_severity.lua (persistent PP)
│  ├─ race_strategy.lua  (adaptive fuel)
│  ├─ rolling_start.lua  (aligned 2×2)
│  ├─ sector_gaps.lua    (sector delta)
│  ├─ ui.lua             (5 tabs)
│  └─ webui.lua          (remote panel bridge)
├─ web/panel.html + panel_server.py
└─ data/car_scan_config.json
```
</details>

---

## ⚙️ Configuration

Settings auto-save to `ApexFlow_config.lua` (per track). Five tabs in the main app:

| Tab | Controls |
|---|---|
| **Home** | Live gaps, penalty points, session info |
| **Drivers** | `Profile Mix` 0–100 (68 ≈ 2–3 cars fighting) + pace pack |
| **Race** | Rolling start `limitSpeed/gap` + strategy `laps/stops` + real pit limit |
| **Screen** | HUD toggles (`gapBehind/deltaLive`), progress bars, blink |
| **System** | GitHub updates, remote panel `port/token`, accent theme |

---

## 🏎️ Quick Start

**First race (2 minutes):**
1. `Drivers → Profile Mix 68` + `Pace 55`
2. `Race → Rolling ON` + `Strategy 20 laps / 1 stop`
3. Green flag — watch the Events HUD: `P3 | Lap 2 | 12 m behind P4 +1.2 s | PP 0`

**Rain:** nothing to configure — the AI automatically desensitizes grip sliding and keeps its rhythm instead of crawling.

**Backmarkers:** the car behind shows **blue** when lapped, with time delta.

**Penalty points:** `PP 3 · L3` persists across qualifying and race — check `Events` or the remote panel.

**Phone dashboard:** `System → Web UI ON`, then run `python web/panel_server.py` and open `http://<your-pc-ip>:8080/panel.html` on your phone (same Wi-Fi).

---

## 📊 Remote Panel

| Device | URL |
|---|---|
| PC | `http://localhost:8080/panel.html` |
| Phone (same Wi-Fi) | `http://<pc-ip>:8080/panel.html` |
| OBS | add `panel.html` as a browser source |

Live `position / lap / speed | gap + delta | PP | strategy` every `0.5 s` via `ApexFlow_webui_status.json`.

---

## 🛠️ API

```lua
_G.APEXFLOW_API.getGapBehindState()      -- {gapBehindM, gapBehindKm, carBehindPos, deltaBehind, isLappedBehind}
_G.APEXFLOW_API.getSectorGapsState()     -- {gapSectorM, gapSectorS, currentSector}
_G.APEXFLOW_API.getPenaltySeverityState()-- {totalPP, level, lastReason, history}
_G.APEXFLOW_API.getStrategyState(cfg)    -- {nextPit, stopsLeft, fuelPerLap}
```

```python
# Remote control example (Python)
STATUS = "Documents/Assetto Corsa/ApexFlow_webui_status.json"
CMD    = "Documents/Assetto Corsa/ApexFlow_webui_cmd.json"
import json, time
def cmd(action, params=None):
    with open(CMD, "w") as f:
        json.dump({"commands": [{"id": int(time.time()*1000), "action": action, "params": params or {}}]}, f)
cmd("set_aggression", {"value": 68})
```

---

## 🗺️ Roadmap

- [x] `v0.32.2` GitHub auto-update on new CSP + repo migration
- [x] `v0.31.2` Smooth race lines (±0.30 cap, no mid-corner crossing) + progressive slow-corner braking
- [x] `v0.30.0` New Race Logic AI: thinks before passing, no trains, no kamikaze
- [x] `v0.29.3` Rain grip fix + persistent PP + delta gaps
- [x] `v0.28.1` Lightweight 2-app split
- [ ] Helicorsa-style radar + graphical telemetry CSV
- [ ] Season championship with PP standings

---

## 📄 License

MIT — **Silxyst**. Free for personal and commercial use, see [LICENSE](LICENSE).

<p align="center">
  <sub>ApexFlow v0.32.6 — 2 apps • 10 modules • CSP 0.3.0 • zero errors</sub><br/>
  <sub>Built with ❤️ for the Assetto Corsa community</sub>
</p>
