<p align="center">
  <img src="icon.png" alt="ApexFlow Logo" width="180"/>
</p>

<h1 align="center">ApexFlow</h1>

<p align="center">
  <strong>Independent AI & Race Control for Assetto Corsa</strong><br/>
  2 Apps: Principal (IA/Corrida/Gaps/PP) + Events HUD — leve (AC nativo cuida de bandeira/corte)
</p>

<p align="center">
  <a href="https://github.com/Silxyst/RaceFlow-V2/releases/latest">
    <img src="https://img.shields.io/github/v/release/Silxyst/RaceFlow-V2?style=for-the-badge&label=Latest%20Release&color=ff6a15" alt="Latest Release"/>
  </a>
  <img src="https://img.shields.io/badge/Version-v0.29.3-ff6a15?style=for-the-badge" alt="App Version"/>
  <a href="https://github.com/Silxyst/RaceFlow-V2/blob/main/LICENSE">
    <img src="https://img.shields.io/github/license/Silxyst/RaceFlow-V2?style=for-the-badge&color=8b5cf6" alt="License"/>
  </a>
</p>

---

## 🎯 Overview

**ApexFlow v0.29.3** foca no essencial: IA pensada + chuva grip 45% menos sensível, largada 2x2, gaps delta, PP persistente. AC nativo cuida de bandeira/corte.

2 janelas: **RaceFlow** + **RaceFlow Events**.

---

## ✨ Sistemas mantidos (1,2,5,7,8) — 10 src leves

| # | Sistema | O que faz | Estado |
|---|---|---|---|
| 1 | 🧠 IA `ai_controller` 109KB | Mix Chill/Normal/Attack (0-100), multiclass 5, racecraft gap 8-120m + 0.8m/s, rampa 0.20, anti-kamikaze | ✅ |
| 2 | 🏁 Corrida `rolling_start` + `race_strategy` | Largada 2x2 paridade 380m single, estratégia `adaptiveFuel` `safetyCarAware`, pits `pitSpeedReal`, `telemetryCSV` | ✅ |
| 5 | 📏 Gaps `gap_behind` + `sector_gaps` | Gap atrás `deltaBehind/isLapped` azul + setor `gapSectorS` anti-wrap `-120/+400` | ✅ |
| 7 | 📊 Painel `penalty_severity` + `webui` | PP L1-6 `ac.storage` persistente + `panel.html` `http://localhost:8080/panel.html` | ✅ |
| 8 | ☁️ Extras `github_update` `memory` `ui` | Update GitHub `ac.webRequest` probe, memória 500 curvas, UI 80KB 5 tabs | ✅ |

**Removidos 3,4,6 (AC nativo assume, -45KB, -6 arqs):** `caution`/`safety_car`/`tracklimits`/`realpenalty_core`/`voice`/`sound_cues`/`box_penalty_timer` — sem `caution/FCY/VSC`, sem `cutting 3 rodas`, sem `beep` duplicado. `hudEvents showCaution/showTrackLimits/sound/box=false`.

---

## 📦 Installation

- AC + CSP 0.3.0.619+ (`dwrite.dll 0.3.0`), Content Manager, offline.
1. Download `RaceFlow_0.29.2_GitHub.zip` de Releases
2. Extrair para `Assetto Corsa/apps/lua/RaceFlow/`
3. Ativar em CM → Apps → `RaceFlow` + `RaceFlow Events`

---

## ⚙️ Configuration

`RaceFlow_config.lua` auto-salvo. 5 tabs: `Início (gaps/PP) | Pilotos (mix) | Corrida (largada+estratégia) | Tela (HUD gaps) | Sistema (update/web)`. `Regulamento` removido — sem `Caution/Limits` para configurar.

---

## 🎮 Uso

- **IA:** `Pilotos → Profile Mix 65-70` para 2-3 carros brigando sem kamikaze.
- **Corrida:** `Corrida → Rolling 2x2` + `Strategy → 20v/1 pit` + `Pit Real ON`.
- **Gaps/PP:** `Events` HUD `P3|Volta 7|gap atrás 12m|PP 3` + `panel.html` no celular.
- **Chuva:** IA `grip 45%` menos sensível, corta só 2% (era 8%) — mantém ritmo no molhado.

---

## 🛠️ API

```lua
_G.RARE2_API.getGapBehindState() -- {gapBehindM, deltaBehind, isLappedBehind}
_G.RARE2_API.getSectorGapsState() -- {gapSectorS}
_G.RARE2_API.getPenaltySeverityState() -- {totalPP, level, history}
```

---

## 📄 License MIT

ApexFlow by **Silxyst** — offline.

<p align="center"><sub>RaceFlow v0.29.3 — 2 Apps leves, 10 src, chuva fix, 0 FAIL</sub></p>
