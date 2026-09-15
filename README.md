<p align="center">
  <img src="icon.png" alt="RaceFlow Logo" width="180"/>
</p>

<h1 align="center">RaceFlow</h1>

<p align="center">
  <strong>AI Enhancement Suite for Assetto Corsa</strong><br/>
  Profiles • Learning • Rolling Start • Endurance • Multiclass • Caution FCY • Track Limits • Themes
</p>

<p align="center">
  <a href="https://github.com/Silxyst/RaceFlow-V2/releases/latest">
    <img src="https://img.shields.io/github/v/release/Silxyst/RaceFlow-V2?style=for-the-badge&label=Latest%20Release&color=00d4aa" alt="Latest Release"/>
  </a>
  <img src="https://img.shields.io/badge/Version-v0.12.0-3b82f6?style=for-the-badge" alt="App Version"/>
  <a href="https://github.com/Silxyst/RaceFlow-V2/blob/main/LICENSE">
    <img src="https://img.shields.io/github/license/Silxyst/RaceFlow-V2?style=for-the-badge&color=8b5cf6" alt="License"/>
  </a>
  <a href="https://discord.gg/assettocorsa">
    <img src="https://img.shields.io/badge/Discord-Assetto%20Corsa-7289da?style=for-the-badge&logo=discord" alt="Discord"/>
  </a>
</p>

<p align="center">
  <a href="#-features">Features</a> •
  <a href="#-installation">Installation</a> •
  <a href="#️-configuration">Configuration</a> •
  <a href="#-usage-tips">Usage</a> •
  <a href="#️-for-developers">Developers</a> •
  <a href="#-roadmap">Roadmap</a>
</p>

---

## 🎯 Overview

**RaceFlow** transforms Assetto Corsa's base AI into competitive, human-like opponents. Every driver has a personality, learns from mistakes, and races with purpose — not just follow a racing line.

Built for **offline single-player** and **offline championships**. No online dependencies. All systems are **disabled by default** — you turn on only what you want.

> 🆕 **New in v0.8.0:** overtake control under caution (give-back countdown + time penalty), interface themes (5 accent colors + background opacity), hardened update loop.

---

## ✨ Features

| System | What it does | Default |
|---|---|---|
| 🧠 AI Personalities | Chill / Normal / Attack mix + Pace Pack field spread | ✅ On |
| 📚 Learning Module | Per-corner memory: danger, entry caps, brake bias, corner lock | ✅ On |
| 🏁 Rolling Start | 2×2 formation lap, pace car, green-flag release | ❌ Off |
| ⛽ Endurance Strategy | Fuel forcing, mandatory stops, tire changes | ❌ Off |
| 🏎️ Multiclass | Manual classes, yield/push logic | ❌ Off |
| 🟡 Caution FCY | Full-course + sector yellow on stopped AI | ❌ Off |
| ⛔ Overtake Control | Give-back countdown + penalty under caution | ✅ On¹ |
| ⚖️ Track Limits | Warnings → pit-box time penalty (player + optional AI) | ❌ Off |
| 🎨 Themes | 5 accent colors + background opacity | ✅ On |
| 🌐 Web UI Remote | File-based status + commands for external tools | ❌ Off |
| ☁️ GitHub Updates | Release checker (needs CSP with `ac.webRequest`) | ✅ On² |

¹ Active only while a caution is running. ² Gracefully disabled on CSP builds without the API.

### 🧠 **AI Personality System**
| Profile | Behavior | Best For |
|---------|----------|----------|
| **Chill** | Early braking, conservative overtakes, gives space | Backmarkers, gentleman drivers |
| **Normal** | Balanced, realistic racecraft | Majority of grid |
| **Attack** | Late braking, aggressive passes, defends hard | Front-runners, champions |

- **Adjustable mix** via single slider (0–100%)
- **Per-driver variation** — no two AI drive identically
- **Pace Pack** spreads field naturally (no train effect)

### 📚 **Adaptive Learning Module**
- **Remembers every corner** — persists across sessions
- **Hard events** (overshoot, contact, spin, off-track) → increases danger
- **Clean laps** → decays danger, raises entry speed caps
- **Corner Lock** — freezes learned values once stable
- **Visual debug** in UI: danger zones, entry caps, brake bias

### 🏁 **Rolling Start (Formation Lap)**
- **2×2 grid formation** with configurable gap/offset
- **Pace car support** — detects `dj_safety_car` or uses pole-sitter
- **Green flag release** at configurable track percentage (92–96%)
- **Realistic presets**: GT3/WEC, IMSA/Indy, Wet/Single-file

### ⛽ **Endurance Fuel Strategy**
- **Forced pit stops** — set race length + mandatory stops
- **Fuel forcing** — AI pits naturally when fuel runs low
- **Tire changes** based on wear threshold
- **Presets**: Sprint, 1h, 4h, 12h Sebring, 24h Le Mans, Nordschleife

### 🏎️ **Multiclass Racing**
- **Manual class assignment** (Class 1 = fastest)
- **Auto-fill** by performance gap detection
- **Yield/Push logic** — faster classes push through, slower yield
- **Class-aware** overtakes and blue flags

### 🟡 **Caution — FCY + Sector Yellow** *(port of Nary's caution core)*
- **Auto-trigger** on stopped AI outside the pits (configurable)
- **FCY** (whole field capped) or **sector yellow** (only incident sector)
- **Randomized duration** with "GET READY" warning before green
- **Manual TEST FCY button** for instant validation
- **Player gets HUD messages only** — no speed enforcement on you
- Requires physics scripting enabled (read-only check, never modifies files)

### ⛔ **Overtake Control under Caution** *(v0.8.0)*
- **Pass someone under yellow?** A give-back countdown starts (default 10 s)
- **Give the position back** in time → cancelled, no harm done
- **Ignore it** → time penalty through the Track Limits serving flow (pit box + brake), or `ac.addPenaltyTime` as fallback
- **Smart filtering**: ignores pits, distant cars (>120 m) and caution end
- Live countdown in the app tab **and** the Race Events HUD

### ⚖️ **Track Limits** *(v0.7.0, port of Mavil TLM core)*
- **Warnings** for wheels off track (configurable 2–4 wheels, cooldown)
- **Sustained-cut debounce** (v0.10.0): brief kerb touches don't count
- **Pit-lane speeding** detection (v0.10.0, default 80 km/h)
- **Game-penalty compat**: pauses our warnings while AC punishes (no double penalty)
- **Time penalty** served stopped in the pit box holding the brake
- **Quali reset** (guarded teleport), **extra time** for early pit exit
- **Unserved time** added to the final result (guarded API)
- **Optional AI** warnings + pit serving
- **Extra HUD window**: live race events (caution + warnings/penalties)

### 🤝 **CMRT HUD Compatibility** *(v0.10.0)*
- Verified: CMRT Complete/Essential HUDs are **read-only** (no physics writes, no shared globals) — zero conflicts
- They visualize `wheelsOutside`; we enforce — complementary systems
- Our Web UI status file (`RaceFlow_webui_status.json`) can feed external overlays

### 🎨 **Interface Themes** *(v0.8.0)*
- **5 accent colors**: cyan, green, orange, purple, red — applied live
- **Background opacity** slider (0.4–1.0)
- Every control labeled + `(?)` tooltips with **layman + technical** explanations

### 🌐 **Web UI Remote (File-Based)**
- **No HTTP server needed** — uses shared JSON files
- **Status file**: `Documents/Assetto Corsa/RaceFlow_webui_status.json`
- **Command file**: `Documents/Assetto Corsa/RaceFlow_webui_cmd.json`
- **Bearer token auth** optional
- **Python example client** included in UI

### 🔄 **GitHub Update Checker**
- **Auto-checks** releases on startup + configurable interval
- **Semantic version compare** — knows when update exists
- **Graceful degradation**: on CSP builds without `ac.webRequest`, shows a guide panel instead of an error
- **Changelog rendered** in-app (when the API is available)

---

## 📦 Installation

### Requirements
- **Assetto Corsa** + **Custom Shaders Patch** (physics features need per-track scripting enabled)
- **Content Manager** recommended
- Offline sessions (online races are ignored by design)

### Steps
1. **Download** latest release from [Releases](https://github.com/Silxyst/RaceFlow-V2/releases)
2. **Extract** to `Assetto Corsa/apps/lua/RaceFlow/`
3. **Enable** in Content Manager → Apps → RaceFlow (main window + optional **RaceFlow Events** overlay)
4. **Launch** AC → Apps sidebar → RaceFlow

---

## ⚙️ Configuration

All settings persist in `RaceFlow_config.lua` (auto-saved). UI tabs:

| Tab | Key Settings |
|-----|--------------|
| **🏁 Core** | Aggression mix, Pace strength, Physics intensity, Learning, Rolling Start |
| **🏎 Multiclass** | Class count, manual assignment, auto-fill |
| **⛽ Strategy** | Race laps, forced stops, tire wear threshold |
| **🟡 Caution** | Speeds, durations, FCY chance, overtake control |
| **⚖ Limits** | Warnings, penalty time, wheels, AI, quali reset |
| **☁ Updates** | Repo, check interval, notify on startup |
| **🌐 Web UI** | Enable, port, auth token |
| **ℹ About** | Docs + 🎨 Appearance (accent color, background opacity) |

---

## 🎮 Usage Tips

### First Race Setup
1. **RaceFlow Core** → set Aggression to 50 (balanced)
2. **Rolling Start** → enable, pick "GT3 / WEC" preset
3. **Strategy** → enable, set laps/stops for your race length
4. **Start race** — watch AI form up behind pace car!

### Caution + Overtakes
1. **Caution tab** → enable + TEST FCY to see AI bunch up
2. Pass someone under yellow → give the position back before the countdown ends
3. Miss it → serve the time penalty stopped in your pit box, brake held

### Track Limits
1. **Limits tab** → enable, set 2 warnings for quick testing
2. Cut the track → warning → cut again → time penalty
3. Pit, stop, hold brake → countdown → "Cumprida!"
4. Enable the **RaceFlow Events** window for a live overlay

### Learning Module
- **Leave ON** — AI improves every session
- **UI → Learning Module** → see danger zones per track
- **Clear buttons** — reset single track or all memory

### Endurance Races
1. **Strategy** → pick preset (e.g., "4h 180 laps / 6 pits")
2. **Fuel** — AI calculates stint lengths automatically
3. **Tires** — enable changes, set wear threshold (50% default)

---

## 🛠️ For Developers

### API (via `_G.RARE2_API`)
```lua
-- Caution
_G.RARE2_API.getCautionState()              -- {active, mode, timer, ...}
_G.RARE2_API.cautionManualTrigger(sim, cfg)

-- Track Limits
_G.RARE2_API.getTrackLimitsState()          -- {warn, penaltyActive, ...}

-- GitHub
_G.RARE2_API.githubCheckUpdates(cfg, true)
_G.RARE2_API.githubGetState()

-- Web UI
_G.RARE2_API.webuiGetState()

-- Config
_G.RARE2_API.saveConfig()
_G.RARE2_API.resetToDefaults()
```

### Web UI Integration (Python)
```python
import json, time

STATUS = "Documents/Assetto Corsa/RaceFlow_webui_status.json"
CMD    = "Documents/Assetto Corsa/RaceFlow_webui_cmd.json"

def send(action, params=None):
    with open(CMD, "w") as f:
        json.dump({"commands": [{"id": int(time.time()*1000), "action": action, "params": params or {}}]}, f)

# Example: toggle rolling start
send("rolling_toggle")

# Poll status
while True:
    with open(STATUS) as f:
        status = json.load(f)
    print(f"Cars: {len(status['cars'])}")
    time.sleep(0.5)
```

---

## 📸 Screenshots

| Core UI | Caution + Limits | Learning Module |
|---------|------------------|-----------------|
| ![Core](docs/core.png) | ![Caution](docs/caution.png) | ![Learning](docs/learning.png) |

*(Add screenshots to `docs/` folder)*

---

## 🗺️ Roadmap

- [x] **Track Limits System** — warnings, penalties, pit serving *(v0.7.0)*
- [x] **Caution FCY + overtake control** *(v0.6.0 + v0.8.0)*
- [ ] **CrewChief Integration** — voice callouts for penalties, rolling start
- [ ] **Championship Mode** — points, standings, calendar
- [ ] **Live Timing Overlay** — OBS-compatible feed
- [ ] **AI Driver Market** — hire/fire, contracts, development

<details>
<summary><strong>📜 Changelog (clique para expandir)</strong></summary>

### v0.8.0 — Overtake control + themes
- Caution overtake monitor: give-back countdown → time penalty
- Interface themes: 5 accents + background opacity
- Update loop hardened with per-module `pcall`

### v0.7.x — Track Limits port
- Mavil TLM core: warnings → pit-box time penalty, AI support
- Race Events HUD window, sliderBlock UI (no clipped labels)

### v0.6.0 — Caution port
- Nary FCY + sector yellow core (formation lap and file-writing not ported)

### v0.5.0 — Stability
- VSC system removed (dual-state bugs); syntax fixes; spam guards

</details>

---

## 🤝 Contributing

1. Fork → feature branch → PR
2. Follow existing code style (Lua, tabs, Portuguese/English comments)
3. Run the block-balance check on every edited `.lua` before committing
4. Test offline races before submitting

---

## 📄 License

**MIT License** — free for personal and commercial use.  
See [LICENSE](LICENSE) for details.

---

## 🙏 Credits & Attribution

This project is an **enhanced fork** of the original **RaceFlow AI Enhancement (Beta)**.

- **Original RaceFlow** — by the author of [RaceFlow on Overtake.gg](https://www.overtake.gg/downloads/raceflow-ai-enhancement-beta.83987/) — all original rights reserved to the original author
- **RaceFlow-V2 enhancements** — by **Silxyst** (this repository): caution system, track limits port, HUD, themes, Web UI, GitHub updater, CMRT sync, racecraft tuning
- **AntiGravity AI** — original architecture & learning concepts (base)
- **Nary (AssettoCorsaRacingCarsMods)** — caution FCY/sector-yellow core
- **Mavil** — track limit penalty serving flow
- **FullCourseYellow** — VSC/SC techniques, AI queue logic
- **CSP Team** — `physics.*` APIs

> **Disclaimer:** RaceFlow-V2 builds upon the original RaceFlow. Original concepts, assets and code remain property of their respective authors. Enhancements in this fork are provided under the MIT License (see `LICENSE`). If you are the original author and wish attribution changed or removed, please open an Issue.
- **Assetto Corsa Modding Community** — endless inspiration

---

## 💬 Support

- **Issues**: [GitHub Issues](https://github.com/Silxyst/RaceFlow-V2/issues)
- **Discord**: [Assetto Corsa Modding](https://discord.gg/assettocorsa) `#lua-apps`
- **Discussions**: [GitHub Discussions](https://github.com/Silxyst/RaceFlow-V2/discussions)

---

<p align="center">
  <sub>Built with ❤️ for the Assetto Corsa community</sub><br/>
  <sub>RaceFlow v0.10.0 — precise penalties, pit speed, spicier AI, CMRT-friendly</sub>
</p>
