<p align="center">
  <img src="icon.png" alt="ApexFlow Logo" width="180"/>
</p>

<h1 align="center">ApexFlow</h1>

<p align="center">
  <strong>The Ultimate AI & Race Control Suite for Assetto Corsa</strong><br/>
  <em>2 Lightweight Apps: RaceFlow Principal + RaceFlow Events HUD</em><br/>
  IA pensada • Largada 2x2 perfeita • Gaps delta • PP persistente — AC cuida de bandeira/corte
</p>

<p align="center">
  <a href="https://github.com/Silxyst/RaceFlow-V2/releases/latest">
    <img src="https://img.shields.io/github/v/release/Silxyst/RaceFlow-V2?style=for-the-badge&label=Download&color=ff6a15&logo=github" alt="Latest Release"/>
  </a>
  <img src="https://img.shields.io/badge/Version-v0.31.2-ff6a15?style=for-the-badge&label=App" alt="Version"/>
  <img src="https://img.shields.io/badge/CSP-0.3.0.619-00d4ff?style=for-the-badge&logo=assettocorsa" alt="CSP"/>
  <img src="https://img.shields.io/badge/Platform-Windows-0078d6?style=for-the-badge&logo=windows" alt="Platform"/>
  <a href="https://github.com/Silxyst/RaceFlow-V2/blob/main/LICENSE">
    <img src="https://img.shields.io/github/license/Silxyst/RaceFlow-V2?style=for-the-badge&color=8b5cf6" alt="License"/>
  </a>
  <img src="https://img.shields.io/badge/Apps-2-22c55e?style=for-the-badge" alt="Apps"/>
  <img src="https://img.shields.io/badge/src-10%20files-22c55e?style=for-the-badge" alt="src"/>
</p>

<p align="center">
  <a href="#-destaques">Destaques</a> •
  <a href="#-instalação">Instalação</a> •
  <a href="#-configuração">Configuração</a> •
  <a href="#-como-usar">Como Usar</a> •
  <a href="#-painel-remoto">Painel Remoto</a> •
  <a href="#-api">API</a> •
  <a href="#-roadmap">Roadmap</a>
</p>

<p align="center">
  <img src="https://img.shields.io/badge/Testado-CSP%200.3.0-00d4ff?style=flat-square" alt="Testado"/>
  <img src="https://img.shields.io/badge/Offline-Sim-22c55e?style=flat-square" alt="Offline"/>
  <img src="https://img.shields.io/badge/PP-Persistente-ff6a15?style=flat-square" alt="PP"/>
  <img src="https://img.shields.io/badge/Chuva-Fix-22c55e?style=flat-square" alt="Chuva"/>
</p>

---

## 🎯 Por que ApexFlow?

> **IA que pensa, não que bate.** Cada piloto tem personalidade, disputa lado-a-lado na reta (gap 8-120m + 0.8 m/s), freia tarde mas com rampa 0.20 — sem kamikaze. Na chuva, corta só 2% (era 8%) e mantém ritmo.

- **Leve:** 10 `src` (era 17) • 80KB `ui` • 3 janelas • 0 `FAIL` em `custom_shaders_patch.log` • AC nativo cuida de bandeira/corte (sem duplicar punição)
- **Offline 100%:** sem dependência online, salva `RaceFlow_config.lua` + `RaceFlow_memory.lua` por pista
- **2 Apps:** `RaceFlow` (Principal `1024x760` + Setup) + `RaceFlow Events` HUD `360x260` (P|Volta|Marcha|gap/PP)

---

## ✨ Destaques

| Sistema | O que faz na prática | Onde ver |
|---|---|---|
| 🧠 **IA Pensada** `ai_controller 109KB` | Mix `Chill/Normal/Attack` 0-100 (recom. 65-70) • multiclass 5 • `stuckDelay 0.9` `gate 0.20` `push 0.045` — briga limpa 2-3 carros | `Pilotos` |
| 🏁 **Corrida** `rolling_start 25KB` + `race_strategy 13KB` | Largada 2x2 paridade `380m` single `gap*0.8` anti-sanfona + Estratégia `adaptiveFuel` `safetyCarAware` + `pitSpeedReal` | `Corrida` |
| 📏 **Gaps** `gap_behind 3KB` `sector_gaps 2.5KB` | `+12m P1` `12m atrás P4 +1.2s azul se retardatário` `Setor +0.8s` anti-wrap `-120/+400` | `Events` + `Início` |
| 📊 **PP** `penalty_severity 1.7KB` | L1=1PP … L6=6PP `ac.storage` persiste entre sessões • `Total PP: 3 L3` | `Events` + `panel.html` |
| 🌐 **Painel Remoto** `webui 10KB` | `http://localhost:8080/panel.html` + celular mesma Wi-Fi `http://seu-ip:8080/panel.html` • `gapBehind{delta,isLapped}` | `Sistema` |
| ☁️ **Extras** `github_update` `memory` | Update `ac.webRequest` probe `0.3.0` • Memória 500 curvas • `telemetryCSV` | `Sistema` |

> **Removidos 3,4,6 (-45KB, -6 arqs):** `caution`/`safety_car`/`tracklimits`/`realpenalty_core`/`voice`/`sound_cues`/`box_penalty_timer` — AC nativo assume.

---

## 📦 Instalação

**Requisitos:** `Assetto Corsa` + `CSP 0.3.0.619+` (`dwrite.dll 0.3.0`) + `Content Manager` + offline.

```bash
1. Baixe RaceFlow_v0.31.2.zip em https://github.com/Silxyst/RaceFlow-V2/releases/latest
2. Extraia para Assetto Corsa/apps/lua/RaceFlow/ (substitua)
3. Content Manager → Apps → ative RaceFlow + RaceFlow Events
4. AC → Apps barra lateral → RaceFlow
```

<details>
<summary><strong>📁 Estrutura v0.31.2 (10 src leves)</strong></summary>

```
RaceFlow/
├─ manifest.ini (3 janelas)
├─ RaceFlow.lua (1319 linhas, 8 safeRequire)
├─ icon.png
├─ sfx/rs_beep.wav
├─ src/
│  ├─ ai_controller.lua (IA pensada)
│  ├─ gap_behind.lua (delta/isLapped)
│  ├─ github_update.lua
│  ├─ memory.lua
│  ├─ penalty_severity.lua (PP persistente)
│  ├─ race_strategy.lua (adaptiveFuel)
│  ├─ rolling_start.lua (2x2 paridade)
│  ├─ sector_gaps.lua
│  ├─ ui.lua (80KB, 5 tabs)
│  └─ webui.lua (gap delta)
├─ web/panel.html + panel_server.py
└─ data/car_scan_config.json
```
</details>

---

## ⚙️ Configuração

`RaceFlow_config.lua` auto-salvo. 5 abas no Principal:

| Aba | O que mexe |
|---|---|
| **Início** | Gaps ao vivo + PP total + `gapBehindM/deltaBehind` |
| **Pilotos** | `Profile Mix` 0-100 (70 = 2-3 brigando) + `Pace Pack` |
| **Corrida** | `Rolling 2x2` `limitSpeed/gap` + `Strategy laps/stops` `pitSpeedReal` |
| **Tela** | `HUD` `showGapBehind/showDeltaLive` `progressBars/blink` |
| **Sistema** | `GitHub` `WebUI port/authToken` `Appearance` `accent/cyan` |

Sem `Caution/Limits/Voz` — removidos.

---

## 🎮 Como Usar

**1ª corrida (2 min):**
1. `Pilotos → Profile Mix 68` + `Pace 55`
2. `Corrida → Rolling ON` + `Strategy 20v/1 pit`
3. Largue — veja `Events: P3 | Volta 2 | 12m atrás P4 +1.2s | PP 0` + `Pneus 98%` + `+12m P1`

**Chuva:** IA já compensa `grip 45%` menos sensível — não precisa mexer.

**Gaps:** `Events` mostra `Carro atrás: 12m (P4) +1.2s` azul se retardatário.

**PP:** `Events` `PP 3 L3 Corte` persiste via `ac.storage` — `Zerar PP` em `Regulação` (se reativar) ou `webui`.

**Painel no celular:** `Sistema → WebUI ON` + `python web/panel_server.py` → `http://seu-ip:8080/panel.html`

---

## 📊 Painel Remoto

| Recurso | URL |
|---|---|
| PC | `http://localhost:8080/panel.html` |
| Celular mesma Wi-Fi | `http://<ip-do-pc>:8080/panel.html` |
| OBS Browser | adicione `panel.html` como fonte |

`panel.html` mostra `P/Volta/km/h | gapBehind delta/isLapped | PP | estratégia` a cada `0.5s` via `RaceFlow_webui_status.json`.

---

## 🛠️ API

```lua
_G.RARE2_API.getGapBehindState() -- {gapBehindM, gapBehindKm, carBehindPos, deltaBehind, isLappedBehind}
_G.RARE2_API.getSectorGapsState() -- {gapSectorM, gapSectorS, currentSector}
_G.RARE2_API.getPenaltySeverityState() -- {totalPP, level, lastReason, history}
_G.RARE2_API.getStrategyState(cfg) -- {nextPit, stopsLeft, fuelPerLap}
```

```python
# Python webui
STATUS = "Documents/Assetto Corsa/RaceFlow_webui_status.json"
CMD = "Documents/Assetto Corsa/RaceFlow_webui_cmd.json"
import json, time
def cmd(action, params=None):
    with open(CMD,"w") as f:
        json.dump({"commands":[{"id":int(time.time()*1000),"action":action,"params":params or {}}]}, f)
cmd("set_aggression", {"value":68})
```

---

## 🗺️ Roadmap

- [x] `v0.31.2` IA Race Logic suave: linhas ±0.30 sem tranco + freada progressiva nas lentas
- [x] `v0.30.0` IA nova Race Logic: pensa antes de passar, sem trem, sem kamikaze
- [x] `v0.29.3` Chuva grip 2% + PP persistente + Gaps delta
- [x] `v0.29.1` IA pensada gap 8-120m + anti-kamikaze
- [x] `v0.28.1` Extrema 2 Apps leves
- [ ] Radar helicorsa + telemetry CSV gráfico
- [ ] Campeonato PP por temporada

---

## 📄 License MIT — Silxyst

<p align="center"><sub>RaceFlow v0.31.2 — 2 Apps • 10 src • CSP 0.3.0 • 0 FAIL • AC nativo bandeira/corte</sub></p>
