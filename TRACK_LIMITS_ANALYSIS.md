# RaceFlow - Track Limits Regulation Analysis
## Documentação Técnica para Implementação Futura

---

## 📋 **Visão Geral**

Este documento analisa as abordagens para implementar um sistema completo de **Track Limits** no RaceFlow, baseado nas melhores práticas do Mavil Track Limit Manager, Real Penalty System e CSP API moderno.

---

## 🎯 **Requisitos do Sistema**

### **Detecção**
- ✅ `car.wheelsOutside` (0-4) - rodas fora da pista
- ✅ `car.isOnTrack` / `car.isOffTrack` - flags booleanas
- ✅ `car.surfaceType` - tipo de superfície (opcional)
- ✅ Velocidade mínima para ativar (evita detecção em pits/baixa velocidade)

### **Lógica de Penalidade**
- **Advertências** (warnings) configuráveis (1-10)
- **Tipos de punição**: Slowdown / +5s / Drive-Through
- **Cooldown** entre infrações (evita spam)
- **Cumprimento no pit** com brake hold (estilo Mavil/Real Penalty)

### **IA**
- IA também recebe punições (opcional)
- IA cumpre slowdown no pit (opcional)
- Drive-through para IA via `ac.requestPitStop`

### **Relatórios**
- TXT + CSV pós-corrida
- Classificação ajustada por penalidades não cumpridas
- Detalhes por canto/volta/setor

---

## 🔧 **Arquitetura Sugerida (Módulo Separado)**

```
src/tracklimits.lua
├── State
│   ├── offTrackTime[carIndex]          -- tempo contínuo fora
│   ├── lastInfractionTime[carIndex]    -- timestamp última infração
│   ├── warnings[carIndex]              -- contador advertências
│   ├── activePenalties[carIndex]       -- {type, remaining, served, waitDone}
│   ├── penaltyWaitTimer[carIndex]      -- tempo espera antes cumprir
│   └── sessionStats[carIndex]          -- {warns, penalties, totalTime, details[]}
├── Config (em RARE2_CFG.trackLimits)
│   ├── enabled
│   ├── wheelsThreshold (3 ou 4)
│   ├── minSpeedKmh
│   ├── confirmTime (segundos fora para confirmar)
│   ├── cooldownTime
│   ├── maxWarnings
│   ├── penaltyType ("slowdown"|"time5s"|"dt")
│   ├── slowdownTime
│   ├── strictPit (exige isInPit)
│   ├── penaltyWaitTime
│   ├── penaltyExtraTime
│   ├── aiEnabled
│   ├── aiServeInRace
│   └── writeReport
├── API
│   ├── update(dt, sim, cfg)
│   ├── forceReset(sim, cfg)
│   ├── getState() -> {warnings, penalties, stats}
│   └── manualPenalty(carIndex, type, reason)
└── UI Integration
    ├── drawTrackLimitsSection(sim, cfg)
    └── HUD warnings/penalties (integrar no hudWindow existente)
```

---

## ⚙️ **Algoritmo de Detecção (Pseudocódigo)**

```lua
function update(dt, sim, cfg)
  if not cfg.trackLimits.enabled then return end
  
  for i = 0, sim.carsCount - 1 do
    local car = ac.getCar(i)
    if not car or car.isInPitlane or car.speedKmh < cfg.minSpeedKmh then
      offTrackTime[i] = 0
      goto continue
    end

    local wheelsOut = car.wheelsOutside or 0
    local isOff = wheelsOut >= cfg.wheelsThreshold

    if isOff then
      offTrackTime[i] = (offTrackTime[i] or 0) + dt
      
      if offTrackTime[i] >= cfg.confirmTime then
        local now = os.clock()
        if (now - (lastInfractionTime[i] or 0)) > cfg.cooldownTime then
          lastInfractionTime[i] = now
          warnings[i] = (warnings[i] or 0) + 1
          
          if warnings[i] < cfg.maxWarnings then
            -- Warning
            showHUD("Track Limits: Warning " .. warnings[i] .. "/" .. cfg.maxWarnings)
          else
            -- Penalty
            warnings[i] = 0
            applyPenalty(i, car, cfg)
          end
        end
      end
    else
      offTrackTime[i] = math.max(0, (offTrackTime[i] or 0) - dt * 3)
    end

    ::continue::
    -- Process active penalties (pit serving logic)
    processPenaltyServing(i, car, dt, sim, cfg)
  end
end

function applyPenalty(carIndex, car, cfg)
  local pType = cfg.penaltyType
  local time = cfg.slowdownTime
  
  activePenalties[carIndex] = {
    type = pType,
    remainingSec = time,
    totalSec = time,
    originalTime = time,
    servedInPit = false,
    waitDone = false,
    lap = car.lapCount,
    sector = car.currentSector + 1,
  }
  
  sessionStats[carIndex].penalties++
  sessionStats[carIndex].totalPenaltyTime += time
  table.insert(sessionStats[carIndex].details, {...})
  
  if carIndex == 0 then
    showHUD("PENALTY: " .. pType:upper() .. " - " .. time .. "s")
    if pType == "dt" and physics.teleportCarTo then
      physics.teleportCarTo(0, ac.SpawnSet.Pits)
    end
  else
    if cfg.aiEnabled then
      if pType == "slowdown" then
        physics.setAITopSpeed(carIndex, 50)
        physics.setAIThrottleLimit(carIndex, 0.05)
      elseif pType == "dt" then
        ac.requestPitStop(carIndex)
      end
    end
  end
end

function processPenaltyServing(carIndex, car, dt, sim, cfg)
  local pen = activePenalties[carIndex]
  if not pen or pen.remainingSec <= 0 then return end

  -- Pit entry/exit tracking
  local inPit = car.isInPitlane
  local wasInPit = pen.wasInPit or false
  pen.wasInPit = inPit

  if inPit and not wasInPit then
    -- Entered pits
    pen.waitDone = false
    pen.waitTimer = cfg.penaltyWaitTime or 1.9
  elseif not inPit and wasInPit then
    -- Exited pits
    if pen.remainingSec > 0 then
      -- Didn't serve fully
      pen.remainingSec = pen.remainingSec + (cfg.penaltyExtraTime or 10)
      showHUD("Penalty not served! +" .. cfg.penaltyExtraTime .. "s")
    end
    return
  end

  -- Serving logic
  if inPit and pen.remainingSec > 0 then
    if not pen.waitDone and (cfg.penaltyWaitTime or 0) > 0 then
      pen.waitTimer = (pen.waitTimer or cfg.penaltyWaitTime) - dt
      if pen.waitTimer <= 0 then pen.waitDone = true end
      showHUD("Wait " .. math.ceil(pen.waitTimer) .. "s before serving")
      return
    end

    if car.speedKmh <= 1.0 and car.brake > 0.7 then
      pen.remainingSec = pen.remainingSec - dt
      pen.servedInPit = true
      showHUD("Serving... " .. math.ceil(pen.remainingSec) .. "s")
    else
      showHUD("Stop in pit & HOLD BRAKE")
    end
  end

  -- Countdown when not in pits
  if not inPit and pen.remainingSec > 0 then
    pen.remainingSec = math.max(0, pen.remainingSec - dt)
    if carIndex == 0 then showHUD("Penalty: " .. math.ceil(pen.remainingSec) .. "s") end
  end

  -- Completed
  if pen.remainingSec <= 0 and not inPit then
    activePenalties[carIndex] = nil
    if car.isAIControlled then
      physics.setAITopSpeed(carIndex, 1e9)
      physics.setAIThrottleLimit(carIndex, 1.0)
    end
    showHUD("Penalty served!")
  end
end
```

---

## 📊 **Relatórios Pós-Corrida**

### **TXT Format**
```
RaceFlow - Track Limits Report 2025-12-19 14:30:00
Track: Spa-Francorchamps
Session: Race
============================================================
POS | Driver              | Car# | Warn | Pen# | PenTime | Status
============================================================
1   | Player              | 0    | 2    | 1    | +5s     | FIN
2   | AI #1               | 1    | 4    | 2    | +10s    | FIN
3   | AI #2               | 2    | 0    | 0    | -       | FIN
============================================================

PENALTY DETAILS:
Player (Car #0): Warn=2 Pen=1 (+5s)
  1. +5s on lap 3 / S2 at 2:15.432 - Track limits exceeded

AI #1 (Car #1): Warn=4 Pen=2 (+10s)
  1. +5s on lap 1 / S1 at 1:45.123 - Track limits exceeded
  2. +5s on lap 5 / S3 at 3:22.567 - Track limits exceeded

SETTINGS USED:
Max Warnings: 3
Penalty Type: slowdown
Slowdown Time: 5s
Wheels Threshold: 3
Cooldown: 7s
Strict Pit: false
Penalty Wait: 1.9s
Extra Time: 10s
AI Penalties: ON
AI Serve: ON
```

### **CSV Format**
```csv
POS,Driver,Car#,Warnings,Penalties,PenaltyTime,Unserved,Status
1,Player,0,2,1,5,0,FIN
2,AI #1,1,4,2,10,0,FIN
```

---

## 🎨 **Integração HUD (Sugestão)**

```lua
-- No hudWindow() existente ou novo hudTrackLimits()
local function drawTrackLimitsHUD(sim, cfg)
  local state = getTrackLimitsState()
  if not state or not cfg.trackLimits.showHUD then return end

  local pcar = ac.getCar(0)
  if not pcar then return end

  local warns = state.warnings[0] or 0
  local maxW = cfg.trackLimits.maxWarnings
  local pen = state.activePenalties[0]

  if warns > 0 or pen then
    -- Draw warning/penalty box
    ui.drawRectFilled(...)
    if warns > 0 then
      ui.text("TRACK LIMITS: " .. warns .. "/" .. maxW)
    end
    if pen then
      ui.text(pen.type:upper() .. ": " .. math.ceil(pen.remainingSec) .. "s")
      if pen.servedInPit then ui.text("HOLD BRAKE IN PIT") end
    end
  end
end
```

---

## ⚠️ **Edge Cases & Considerações**

| Cenário | Tratamento |
|---------|------------|
| **Pit entry/exit** | Reset `offTrackTime` quando `isInPitlane` |
| **Safety Car / VSC** | Desativar detecção se `cfg.disableDuringVSC` |
| **Qualifying** | Invalidar volta (teleport to pits) como Mavil |
| **Practice** | Apenas warnings, sem penalty time |
| **Race finish** | Penalty não cumprido → +tempo no resultado final |
| **Disconnect** | Salvar stats no `onDisconnect` |
| **Session restart** | `forceReset()` limpa tudo |
| **Multi-class** | Thresholds diferentes por classe (opcional) |

---

## 🚀 **Roadmap de Implementação**

| Fase | Tasks | Estimativa |
|------|-------|------------|
| **1. Core** | `src/tracklimits.lua` básico (detecção + warnings) | 2-3 dias |
| **2. Penalties** | Slowdown + pit serving (brake hold) | 3-4 dias |
| **3. AI** | IA penalties + pit serving | 2 dias |
| **4. Reports** | TXT/CSV generation | 1-2 dias |
| **5. UI** | Aba "Track Limits" + HUD | 2 dias |
| **6. Polish** | Testes, edge cases, config migration | 2-3 dias |
| **Total** | | **~12-16 dias** |

---

## 📁 **Arquivos a Criar/Modificar**

### **Novos**
- `src/tracklimits.lua` - Módulo principal
- `data/tracklimits_presets.json` - Presets por categoria (GT3, F1, etc.)

### **Modificados**
- `RaceFlow.lua` - Add `trackLimits` config + require + update loop
- `src/ui.lua` - Aba "Track Limits" + HUD integration
- `manifest.ini` - Version bump

---

## 🔗 **Referências de Código Existente**

| Fonte | Arquivo | Função/Conceito |
|-------|---------|-----------------|
| Mavil TLM | `Mavil_Track_Limit_Manager.lua` | `wheelsOutside`, warnings, pit serving, reports |
| FullCourseYellow | `FullCourseYellow.lua` | AI speed capping, give-back warnings |
| RaceFlow atual | `race_director.lua` (removido) | Incident detection, state machine |
| RaceFlow atual | `ai_controller.lua` | Learning module, danger zones |
| RaceFlow atual | `race_strategy.lua` | Fuel forcing pattern (pit detection) |

---

## ✅ **Critérios de Aceite**

- [ ] Detecta 3/4 rodas fora configurável
- [ ] Warnings visuais no HUD
- [ ] 3 tipos de penalty funcionando
- [ ] Pit serving com brake hold (player)
- [ ] IA cumpre slowdown no pit
- [ ] Drive-through teleporta player / requestPitStop IA
- [ ] Extra time se sair do pit sem cumprir
- [ ] Relatórios TXT/CSV gerados automaticamente
- [ ] Classificação final ajustada por penalties
- [ ] Configs persistidas em `RaceFlow_config.lua`
- [ ] Aba UI completa com presets
- [ ] Compatível com VSC/Rolling Start simultâneos

---

*Documento gerado em 2025-12-19 para RaceFlow v0.4.6+*