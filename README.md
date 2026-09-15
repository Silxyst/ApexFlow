<p align="center">
  <img src="icon.png" alt="RaceFlow Logo" width="180"/>
</p>

<h1 align="center">RaceFlow</h1>

<p align="center">
  <strong>AI Enhancement Suite for Assetto Corsa</strong><br/>
  Profiles • Learning • Rolling Start • Endurance Strategy • Multiclass • GitHub Updates • Web UI
</p>

<p align="center">
  <a href="https://github.com/Silxyst/RaceFlow-V2/releases/latest">
    <img src="https://img.shields.io/github/v/release/Silxyst/RaceFlow-V2?style=for-the-badge&label=Latest%20Release&color=00d4aa" alt="Latest Release"/>
  </a>
  <a href="https://github.com/Silxyst/RaceFlow-V2/releases">
    <img src="https://img.shields.io/github/downloads/Silxyst/RaceFlow-V2/total?style=for-the-badge&color=3b82f6" alt="Downloads"/>
  </a>
  <a href="https://github.com/Silxyst/RaceFlow-V2/blob/main/LICENSE">
    <img src="https://img.shields.io/github/license/Silxyst/RaceFlow-V2?style=for-the-badge&color=8b5cf6" alt="License"/>
  </a>
  <a href="https://discord.gg/assettocorsa">
    <img src="https://img.shields.io/badge/Discord-Assetto%20Corsa-7289da?style=for-the-badge&logo=discord" alt="Discord"/>
  </a>
</p>

---

## 🎯 Overview

**RaceFlow** transforms Assetto Corsa's base AI into competitive, human-like opponents. Every driver has a personality, learns from mistakes, and races with purpose — not just follow a racing line.

Built for **offline single-player** and **offline championships**. No online dependencies.

---

## ✨ Features

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

> **NOTE v0.5.0:** the Pure VSC system was **removed** to eliminate a recurring
> source of instability (dual-state bugs, log spam, setup-screen interference).
> It may return in a future release as an isolated optional module. See CHANGELOG.

### 🔄 **GitHub Update Checker**
- **Auto-checks** releases on startup + configurable interval
- **Semantic version compare** — knows when update exists
- **One-click** manual check + open release page
- **Changelog rendered** in-app

### 🌐 **Web UI Remote (File-Based)**
- **No HTTP server needed** — uses shared JSON files
- **Status file**: `Documents/Assetto Corsa/RaceFlow_webui_status.json`
- **Command file**: `Documents/Assetto Corsa/RaceFlow_webui_cmd.json`
- **Bearer token auth** optional
- **Python example client** included in UI

---

## 📦 Installation

### Requirements
- **Assetto Corsa** + **CSP 0.2.7+** (for `ac.webRequest`, `physics.setAITopSpeed`, etc.)
- **Content Manager** recommended

### Steps
1. **Download** latest release from [Releases](https://github.com/Silxyst/RaceFlow-V2/releases)
2. **Extract** to `Assetto Corsa/apps/lua/RaceFlow/`
3. **Enable** in Content Manager → Apps → RaceFlow
4. **Launch** AC → Apps sidebar → RaceFlow

---

## ⚙️ Configuration

All settings persist in `RaceFlow_config.lua` (auto-saved). UI tabs:

| Tab | Key Settings |
|-----|--------------|
| **RaceFlow Core** | Aggression mix, Pace strength, Physics intensity, Learning, Rolling Start |
| **Multi Class** | Class count, manual assignment, auto-fill |
| **Strategy** | Race laps, forced stops, tire wear threshold |
| **GitHub Updates** | Repo, check interval, notify on startup |
| **Web UI** | Enable, port, auth token |

---

## 🎮 Usage Tips

### First Race Setup
1. **RaceFlow Core** → set Aggression to 50 (balanced)
2. **Rolling Start** → enable, pick "GT3 / WEC" preset
3. **Strategy** → enable, set laps/stops for your race length
4. **Start race** — watch AI form up behind pace car!

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

| Core UI | Strategy | Learning Module |
|---------|----------|-----------------|
| ![Core](docs/core.png) | ![Strategy](docs/strategy.png) | ![Learning](docs/learning.png) |

*(Add screenshots to `docs/` folder)*

---

## 🗺️ Roadmap

- [ ] **Track Limits System** — warnings, penalties, pit serving, reports
- [ ] **CrewChief Integration** — voice callouts for penalties, rolling start
- [ ] **Championship Mode** — points, standings, calendar
- [ ] **Live Timing Overlay** — OBS-compatible WebSocket feed
- [ ] **AI Driver Market** — hire/fire, contracts, development

---

## 🤝 Contributing

1. Fork → feature branch → PR
2. Follow existing code style (Lua, tabs, Portuguese/English comments)
3. Test offline races before submitting

---

## 📄 License

**MIT License** — free for personal and commercial use.  
See [LICENSE](LICENSE) for details.

---

## 🙏 Credits

- **AntiGravity AI** — original architecture & learning concepts
- **FullCourseYellow** — VSC/SC techniques, AI queue logic
- **Mavil Track Limit Manager** — penalty serving, reports
- **CSP Team** — `ac.webRequest`, `physics.*` APIs
- **Assetto Corsa Modding Community** — endless inspiration

---

## 💬 Support

- **Issues**: [GitHub Issues](https://github.com/Silxyst/RaceFlow-V2/issues)
- **Discord**: [Assetto Corsa Modding](https://discord.gg/assettocorsa) `#lua-apps`
- **Discussions**: [GitHub Discussions](https://github.com/Silxyst/RaceFlow-V2/discussions)

---

<p align="center">
  <sub>Built with ❤️ for the Assetto Corsa community</sub><br/>
  <sub>RaceFlow v0.5.0 — stability release (VSC removed)</sub>
</p>