-- RaceFlow UI – Aggression Pack + Pace Pack

local M = {}

local function hash01(s)
  local h = 0
  for i = 1, #s do
    h = (h * 31 + string.byte(s, i)) % 1000000
  end
  return h / 1000000
end

local function clamp(v, minV, maxV)
  if v < minV then return minV end
  if v > maxV then return maxV end
  return v
end

local function lerp(a, b, t)
  return a + (b - a) * t
end

local function helpMarker(text)
  ui.sameLine()
  ui.textDisabled("(?)")
  if ui.itemHovered() then
    ui.setTooltip(text)
  end
end

local function notifyChange()
  if _G.RARE2_API and _G.RARE2_API.markConfigDirty then
    _G.RARE2_API.markConfigDirty()
  end
end

local function pushDarkTheme()
  if not ui.pushStyleColor or not rgbm then return end
  pcall(function()
    ui.pushStyleColor(ui.StyleColor.WindowBg, rgbm(0.08, 0.10, 0.13, 0.96))
    ui.pushStyleColor(ui.StyleColor.ChildBg, rgbm(0.12, 0.14, 0.18, 0.85))
    ui.pushStyleColor(ui.StyleColor.FrameBg, rgbm(0.15, 0.18, 0.23, 0.90))
    ui.pushStyleColor(ui.StyleColor.FrameBgHovered, rgbm(0.22, 0.28, 0.36, 0.95))
    ui.pushStyleColor(ui.StyleColor.FrameBgActive, rgbm(0.28, 0.36, 0.48, 1.0))
    ui.pushStyleColor(ui.StyleColor.Button, rgbm(0.16, 0.32, 0.54, 0.85))
    ui.pushStyleColor(ui.StyleColor.ButtonHovered, rgbm(0.24, 0.44, 0.76, 0.95))
    ui.pushStyleColor(ui.StyleColor.ButtonActive, rgbm(0.30, 0.54, 0.92, 1.0))
    ui.pushStyleColor(ui.StyleColor.CheckMark, rgbm(0.30, 0.78, 1.0, 1.0))
    ui.pushStyleColor(ui.StyleColor.SliderGrab, rgbm(0.25, 0.65, 0.95, 1.0))
    ui.pushStyleColor(ui.StyleColor.SliderGrabActive, rgbm(0.40, 0.82, 1.0, 1.0))
    ui.pushStyleColor(ui.StyleColor.Header, rgbm(0.18, 0.28, 0.42, 0.80))
    ui.pushStyleColor(ui.StyleColor.HeaderHovered, rgbm(0.26, 0.38, 0.56, 0.90))
    ui.pushStyleColor(ui.StyleColor.HeaderActive, rgbm(0.32, 0.46, 0.68, 1.0))
    ui.pushStyleColor(ui.StyleColor.Separator, rgbm(0.24, 0.29, 0.38, 0.70))
    ui.pushStyleColor(ui.StyleColor.Text, rgbm(0.92, 0.95, 0.98, 1.0))
    ui.pushStyleColor(ui.StyleColor.TextDisabled, rgbm(0.55, 0.62, 0.72, 1.0))
  end)
  pcall(function()
    ui.pushStyleVar(ui.StyleVar.FrameRounding, 5)
    ui.pushStyleVar(ui.StyleVar.GrabRounding, 5)
    ui.pushStyleVar(ui.StyleVar.WindowRounding, 8)
  end)
end

local function popDarkTheme()
  if not ui.popStyleColor then return end
  pcall(function() ui.popStyleVar(3) end)
  pcall(function() ui.popStyleColor(17) end)
end

local function sliderRow(label, id, value, minV, maxV, fmt, labelWidth)
  labelWidth = labelWidth or 170

  ui.alignTextToFramePadding()
  ui.text(label)
  ui.sameLine(labelWidth)

  ui.setNextItemWidth(ui.windowWidth() - labelWidth - 20)
  local v = ui.slider("##" .. id, value, minV, maxV, fmt)
  if v ~= nil and v ~= value then
    notifyChange()
  end
  return v
end

local function safeRequire(mod)
  local ok, res = pcall(require, mod)
  if ok then return res end
  ac.log(string.format("[RaceFlow UI] require('%s') failed: %s", tostring(mod), tostring(res)))
  return nil
end

local aiController = safeRequire("src.ai_controller")

local function computeClassPercentages(a)
  if a <= 0.5 then
    local t = a / 0.5
    local pChill  = lerp(0.80, 0.33, t)
    local pNormal = lerp(0.10, 0.33, t)
    local pAttack = lerp(0.10, 0.33, t)
    local sum = pChill + pNormal + pAttack
    return pChill/sum, pNormal/sum, pAttack/sum
  else
    local t = (a - 0.5) / 0.5
    local pChill  = lerp(0.33, 0.10, t)
    local pNormal = lerp(0.33, 0.10, t)
    local pAttack = lerp(0.33, 0.80, t)
    local sum = pChill + pNormal + pAttack
    return pChill/sum, pNormal/sum, pAttack/sum
  end
end

local function classAggression(class, sliderNorm)
  local baseChill  = 0.15
  local baseNormal = 0.50
  local baseAttack = 0.85

  local scale = lerp(0.8, 1.2, sliderNorm)

  if class == "chill" then
    return clamp(baseChill * (1.0 - 0.3 * sliderNorm), 0.05, 0.3)
  elseif class == "normal" then
    return clamp(baseNormal * scale, 0.3, 0.8)
  else
    return clamp(baseAttack * (0.8 + 0.4 * sliderNorm), 0.6, 1.0)
  end
end

local function computeMulticlassStats(sim, cfg)
  local classForIndex = cfg and cfg._multiclassClassForIndex
  if not sim or not sim.carsCount or sim.carsCount <= 0 then return nil end
  if not classForIndex then return nil end

  local counts = {}
  local total = 0
  local maxClass = 0

  for i = 0, sim.carsCount - 1 do
    local car = ac.getCar(i)
    if car and car.isAIControlled then
      local c = classForIndex[i]
      if c then
        counts[c] = (counts[c] or 0) + 1
        total = total + 1
        if c > maxClass then maxClass = c end
      end
    end
  end

  if total == 0 then return nil end

  return {
    total = total,
    maxClass = maxClass,
    counts = counts
  }
end

local function computeAggressionStats(sim, cfg)
  local stats = { chill = 0, normal = 0, attack = 0, total = 0 }

  if not sim or not sim.carsCount or sim.carsCount <= 0 then
    return stats
  end

  local carsCount = sim.carsCount
  local a = clamp((cfg.aggression or 50) / 100.0, 0, 1)

  local pChill, pNormal, pAttack = computeClassPercentages(a)

  local aiCars = {}
  for i = 0, carsCount - 1 do
    local car = ac.getCar(i)
    if car and car.isAIControlled then
      local name = ac.getDriverName(i) or ("AI" .. i)
      local key  = tostring(i) .. "|" .. name
      table.insert(aiCars, { index = i, r = hash01(key) })
    end
  end

  local N = #aiCars
  if N == 0 then
    return stats
  end

  table.sort(aiCars, function(a_, b_) return a_.r < b_.r end)

  local nChill  = math.floor(pChill  * N + 0.0001)
  local nNormal = math.floor(pNormal * N + 0.0001)
  local nAttack = N - nChill - nNormal
  if nAttack < 0 then nAttack = 0 end
  local used = nChill + nNormal + nAttack
  if used < N then
    nAttack = nAttack + (N - used)
  end

  for idx, info in ipairs(aiCars) do
    local class
    if idx <= nChill then
      class = "chill"
    elseif idx <= nChill + nNormal then
      class = "normal"
    else
      class = "attack"
    end

    stats[class] = stats[class] + 1
    stats.total  = stats.total + 1

    if physics and physics.setAIAggression then
      local aggr = classAggression(class, a)
      physics.setAIAggression(info.index, aggr)
    end
  end

  stats.pChill  = pChill
  stats.pNormal = pNormal
  stats.pAttack = pAttack

  return stats
end

local function drawDifficultyBoostSection(sim, cfg)
  ui.text("Difficulty Boost")
  helpMarker("Stacks on top of AC difficulty.\n\n100% = no change\nHigher = faster AI overall.")

  cfg.difficultyBoost = cfg.difficultyBoost or 100

  ui.setNextItemWidth(ui.windowWidth() - 40)
  local newBoost = ui.slider("##difficultyBoost", cfg.difficultyBoost, 85, 115, "%.0f%%")
  if newBoost ~= nil then
    cfg.difficultyBoost = clamp(newBoost, 85, 115)
  end

  ui.newLine(1)
  ui.separator()
end

local function drawAggressionSection(sim, cfg)
  ui.text("Profile Mix")
  helpMarker("Adjust Ratio of profile mix.\n\nChill,Balanced,Attack")

  local agg = cfg.aggression or 50
  ui.setNextItemWidth(ui.windowWidth() - 40)
  local newAgg = ui.slider("Global aggression", agg, 0, 100, "%.0f")
  if newAgg ~= nil then
    newAgg = clamp(newAgg, 0, 100)
    if math.abs(newAgg - agg) > 0.001 then
      cfg.aggression = newAgg
    end
  end

  ui.newLine(1)
  ui.separator()
  ui.text("Profiles:")

  if not sim or not sim.carsCount or sim.carsCount <= 0 then
    ui.textDisabled("Disponível durante a sessão de corrida.")
    return
  end

  local ok, stats = pcall(computeAggressionStats, sim, cfg)
  if not ok then
    ui.text("Error computing stats:")
    ui.text(tostring(stats))
    return
  end

  if stats.total == 0 then
    ui.text("No AI data yet.")
    return
  end

  ui.text(string.format("Chill:    %d", stats.chill))
  ui.text(string.format("Normal:   %d", stats.normal))
  ui.text(string.format("Attack:   %d", stats.attack))
  ui.text(string.format("Total AI: %d", stats.total))
  ui.text(string.format(
    "Target mix: %.0f%% / %.0f%% / %.0f%%",
    stats.pChill * 100, stats.pNormal * 100, stats.pAttack * 100
  ))

  ui.newLine(1)
end

local function drawFuelStrategySection(sim, cfg)
  ui.text("Estratégia de Corrida & Endurance")
  helpMarker("Configuração de duração da corrida e paradas nos boxes para corridas curtas ou de Endurance (longa duração).")

  cfg.strategy = cfg.strategy or {}

  local enabled = (cfg.strategy.enabled == true)
  if ui.checkbox("Ativar Estratégia de Combustível / Pit-Stops", enabled) then
    cfg.strategy.enabled = not enabled
    notifyChange()
  end

  ui.newLine(2)

  -- Endurance Presets
  ui.textDisabled("Predefinições Rápidas (Endurance & 24 Horas):")
  if ui.button("Sprint (20v / 1 pit)", vec2(130, 22)) then
    cfg.strategy.manualRaceLaps = 20
    cfg.strategy.forcedStops = 1
    notifyChange()
  end
  ui.sameLine()
  if ui.button("Club (40v / 1 pit)", vec2(130, 22)) then
    cfg.strategy.manualRaceLaps = 40
    cfg.strategy.forcedStops = 1
    notifyChange()
  end
  ui.sameLine()
  if ui.button("1h (60v / 2 pits)", vec2(130, 22)) then
    cfg.strategy.manualRaceLaps = 60
    cfg.strategy.forcedStops = 2
    notifyChange()
  end

  if ui.button("2.4h (120v / 4 pits)", vec2(130, 22)) then
    cfg.strategy.manualRaceLaps = 120
    cfg.strategy.forcedStops = 4
    notifyChange()
  end
  ui.sameLine()
  if ui.button("4h (180v / 6 pits)", vec2(130, 22)) then
    cfg.strategy.manualRaceLaps = 180
    cfg.strategy.forcedStops = 6
    notifyChange()
  end
  ui.sameLine()
  if ui.button("6h (250v / 9 pits)", vec2(130, 22)) then
    cfg.strategy.manualRaceLaps = 250
    cfg.strategy.forcedStops = 9
    notifyChange()
  end

  if ui.button("12h Sebring (450v / 15 pits)", vec2(180, 22)) then
    cfg.strategy.manualRaceLaps = 450
    cfg.strategy.forcedStops = 15
    notifyChange()
  end
  ui.sameLine()
  if ui.button("24h Le Mans (800v / 28 pits)", vec2(180, 22)) then
    cfg.strategy.manualRaceLaps = 800
    cfg.strategy.forcedStops = 28
    notifyChange()
  end

  if ui.button("24h Nordschleife (160v / 18 pits)", vec2(180, 22)) then
    cfg.strategy.manualRaceLaps = 160
    cfg.strategy.forcedStops = 18
    notifyChange()
  end
  ui.sameLine()
  if ui.button("1000km / 1000 Milhas (600v)", vec2(180, 22)) then
    cfg.strategy.manualRaceLaps = 600
    cfg.strategy.forcedStops = 22
    notifyChange()
  end

  ui.newLine(2)

  ui.setNextItemWidth(ui.windowWidth() - 40)
  cfg.strategy.manualRaceLaps = cfg.strategy.manualRaceLaps or 20
  local newLaps = ui.slider("Duração da corrida (voltas)", cfg.strategy.manualRaceLaps, 3, 1000, "%.0f")
  if newLaps ~= nil then
    local val = math.floor(clamp(newLaps, 3, 1000) + 0.5)
    if val ~= cfg.strategy.manualRaceLaps then
      cfg.strategy.manualRaceLaps = val
      notifyChange()
    end
  end

  ui.setNextItemWidth(ui.windowWidth() - 40)
  cfg.strategy.forcedStops = cfg.strategy.forcedStops or 1
  local newStops = ui.slider("Paradas obrigatórias nos boxes", cfg.strategy.forcedStops, 0, 50, "%.0f")
  if newStops ~= nil then
    local val = math.floor(clamp(newStops, 0, 50) + 0.5)
    if val ~= cfg.strategy.forcedStops then
      cfg.strategy.forcedStops = val
      notifyChange()
    end
  end

  if cfg.strategy.enabled then
    ui.newLine(2)
    ui.separator()
    ui.text("Troca de Pneus")
    helpMarker("Se ativado, durante a parada forçada nos boxes, a IA verificará o desgaste dos pneus. Se o estado estiver abaixo do limite configurado, pneus novos serão colocados junto com o reabastecimento.")

    if cfg.strategy.tireChangeEnabled == nil then cfg.strategy.tireChangeEnabled = true end
    if cfg.strategy.tireFreshnessPct == nil then cfg.strategy.tireFreshnessPct = 50 end

    local tireEnabled = cfg.strategy.tireChangeEnabled
    if ui.checkbox("Ativar troca de pneus", tireEnabled) then
      cfg.strategy.tireChangeEnabled = not tireEnabled
      notifyChange()
    end

    if cfg.strategy.tireChangeEnabled then
      ui.text("Trocar pneus quando estado ≤")
      ui.setNextItemWidth(ui.windowWidth() - 40)

      local newPct = ui.slider("##tireFreshnessThreshold", cfg.strategy.tireFreshnessPct, 0, 100, "%.0f%%")
      if newPct ~= nil then
        cfg.strategy.tireFreshnessPct = clamp(newPct, 0, 100)
        local pctInt = math.floor(cfg.strategy.tireFreshnessPct + 0.5)
        cfg.strategy.tireWearThreshold = clamp(1.0 - (pctInt / 100.0), 0.0, 1.0)
        notifyChange()
      end
    end

    -- Monitor de Telemetria Endurance ao vivo
    ui.newLine(4)
    ui.separator()
    if rgbm then
      ui.textColored("🏁 Monitor de Endurance & Telemetria", rgbm(0.25, 0.75, 1.0, 1.0))
    else
      ui.text("🏁 Monitor de Endurance & Telemetria")
    end

    if not sim or not sim.isSessionStarted then
      ui.textDisabled("Telemetria disponível durante a sessão de corrida.")
    else
      local okCar, playerCar = pcall(ac.getCar, 0)
      if okCar and playerCar and playerCar.fuel then
        local curFuel = playerCar.fuel or 0
        local maxFuel = playerCar.maxFuel or 100
        local fuelPct = (maxFuel > 0) and (curFuel / maxFuel * 100) or 0

        ui.text(string.format("Combustível Carro 0: %.1f L / %.1f L (%.0f%%)", curFuel, maxFuel, fuelPct))

        if playerCar.wheels and playerCar.wheels[0] and playerCar.wheels[0].tyreWear then
          local w = playerCar.wheels
          local fl = math.max(0, (1 - (w[0].tyreWear or 0)) * 100)
          local fr = math.max(0, (1 - (w[1].tyreWear or 0)) * 100)
          local rl = math.max(0, (1 - (w[2].tyreWear or 0)) * 100)
          local rr = math.max(0, (1 - (w[3].tyreWear or 0)) * 100)

          ui.text("Pneus (Frente): ")
          ui.sameLine()
          if rgbm then
            ui.textColored(string.format("DE: %.0f%%", fl), fl > 60 and rgbm(0.2, 0.9, 0.3, 1) or rgbm(0.9, 0.3, 0.2, 1))
            ui.sameLine(0, 15)
            ui.textColored(string.format("DD: %.0f%%", fr), fr > 60 and rgbm(0.2, 0.9, 0.3, 1) or rgbm(0.9, 0.3, 0.2, 1))
            ui.text("Pneus (Trás):    ")
            ui.sameLine()
            ui.textColored(string.format("TE: %.0f%%", rl), rl > 60 and rgbm(0.2, 0.9, 0.3, 1) or rgbm(0.9, 0.3, 0.2, 1))
            ui.sameLine(0, 15)
            ui.textColored(string.format("TD: %.0f%%", rr), rr > 60 and rgbm(0.2, 0.9, 0.3, 1) or rgbm(0.9, 0.3, 0.2, 1))
          else
            ui.text(string.format("DE: %.0f%% | DD: %.0f%% | TE: %.0f%% | TD: %.0f%%", fl, fr, rl, rr))
          end
        end
      else
        ui.textDisabled("Telemetria do carro ativo disponível durante a sessão.")
      end
    end
  end

local function drawPaceSection(sim, cfg)
  ui.separator()
  ui.text("Profile Gap")
  helpMarker("Adjusts physics ratio of profiles\n0 = Base AC, no gap between Profiles\n100 = Biggest gap between profiles")

  cfg.paceEnabled = true

  ui.setNextItemWidth(ui.windowWidth() - 40)
  local pace = cfg.paceStrength or 50
  local newPace = ui.slider("Pace strength", pace, 0, 100, "%.0f")
  if newPace ~= nil then
    newPace = clamp(newPace, 0, 100)
    if math.abs(newPace - pace) > 0.001 then
      cfg.paceStrength = newPace
    end
  end
end

-- ==========================================================
-- Low Downforce AI (Core tab)
-- ==========================================================
local function drawLowDownforceAISection(sim, cfg)
  ui.separator()
  ui.text("Low-Downforce")
  helpMarker("Adds extra straight-line speed for AI by reducing their downforce profile.\n\nBest used on high-speed tracks. Ex. Monza")

  if cfg.lowDownforceAIEnabled == nil then cfg.lowDownforceAIEnabled = false end
  if cfg.lowDownforceAIStrength == nil then cfg.lowDownforceAIStrength = 35 end

  local enabled = (cfg.lowDownforceAIEnabled == true)
  if ui.checkbox("Enable Low-Downforce AI##lowdf_enable", enabled) then
    cfg.lowDownforceAIEnabled = not enabled
  end

  ui.text("Top-Speed Strength")
  ui.setNextItemWidth(ui.windowWidth() - 40)
  local s = ui.slider("##lowdf_strength", cfg.lowDownforceAIStrength, 0, 100, "%.0f")
  if s ~= nil then
    cfg.lowDownforceAIStrength = clamp(s, 0, 100)
  end
end

-- ==========================================================
-- Learning Module (Core tab)
-- ==========================================================
local function drawLearningModuleSection(sim, cfg)
  ui.newLine(4)
  ui.separator()
  ui.text("Learning Module")
  helpMarker("Enable/disable RaceFlow's adaptive corner memory.\n\nON = hard events update track memory and learned danger/caps are applied.\nOFF = no new learning and learned danger/caps are ignored, while the rest of RaceFlow still runs.")

  if cfg.learningEnabled == nil then
    cfg.learningEnabled = true
  end

  local enabled = (cfg.learningEnabled ~= false)
  if ui.checkbox("Enable learning module##rf_learning_enable", enabled) then
    cfg.learningEnabled = not enabled
  end

  if not cfg.learningEnabled then
    ui.textDisabled("Learning is OFF: existing memory is preserved, but not applied or updated.")
  end

  ui.newLine(4)

  -- Resolve current track ID
  local trackId = nil
  if ac.getTrackID then
    local ok, id = pcall(ac.getTrackID)
    if ok and id and id ~= "" then trackId = id end
  end
  if not trackId and sim then trackId = sim.trackName or nil end

  local clearLabel = trackId
    and string.format("Clear Memory: %s", trackId)
    or  "Clear Memory (this track)"

  if ui.button(clearLabel .. "##rf_clear_track") then
    cfg._confirmClearTrack = true
    cfg._confirmClearAll = false
  end
  ui.sameLine(0, 8)
  if ui.button("Clear All Tracks##rf_clear_all") then
    cfg._confirmClearAll = true
    cfg._confirmClearTrack = false
  end

  -- Track clear confirmation
  if cfg._confirmClearTrack then
    ui.newLine(2)
    ui.text("Clear this track's learned memory?")
    ui.sameLine(0, 8)
    if ui.button("Yes##rf_clear_track_yes") then
      local mem = _G.RARE2_API and _G.RARE2_API.getMemory and _G.RARE2_API.getMemory()
      if mem and mem.tracks and trackId and mem.tracks[trackId] then
        local count = 0
        local t = mem.tracks[trackId]
        if t and t.turns then
          for _ in pairs(t.turns) do count = count + 1 end
        end
        mem.tracks[trackId] = nil
        -- Save immediately — don't wait for the 12s autosave cycle
        if _G.RARE2_API then
          _G.RARE2_API._memoryDirty = false
          if _G.RARE2_API.saveMemory then pcall(_G.RARE2_API.saveMemory) end
        end
        cfg._clearMsg = string.format("Cleared %d corners for %s.", count, tostring(trackId))
        ac.log(string.format("[RaceFlow] Cleared and saved memory for: %s (%d corners)", tostring(trackId), count))
      else
        cfg._clearMsg = string.format("Nothing to clear for %s.", tostring(trackId or "unknown"))
      end
      cfg._confirmClearTrack = false
    end
    ui.sameLine(0, 8)
    if ui.button("Cancel##rf_clear_track_no") then
      cfg._confirmClearTrack = false
    end
  end

  -- All tracks clear confirmation
  if cfg._confirmClearAll then
    ui.newLine(2)
    ui.text("Clear ALL track memory? Cannot be undone.")
    ui.sameLine(0, 8)
    if ui.button("Yes, clear all##rf_clear_all_yes") then
      local mem = _G.RARE2_API and _G.RARE2_API.getMemory and _G.RARE2_API.getMemory()
      if mem and mem.tracks then
        local trackCount, cornerCount = 0, 0
        for _, t in pairs(mem.tracks) do
          trackCount = trackCount + 1
          if t and t.turns then
            for _ in pairs(t.turns) do cornerCount = cornerCount + 1 end
          end
        end
        mem.tracks = {}
        -- Save immediately
        if _G.RARE2_API then
          _G.RARE2_API._memoryDirty = false
          if _G.RARE2_API.saveMemory then pcall(_G.RARE2_API.saveMemory) end
        end
        cfg._clearMsg = string.format("Cleared %d tracks, %d corners total.", trackCount, cornerCount)
        ac.log(string.format("[RaceFlow] Cleared ALL memory: %d tracks, %d corners.", trackCount, cornerCount))
      else
        cfg._clearMsg = "Nothing to clear."
      end
      cfg._confirmClearAll = false
    end
    ui.sameLine(0, 8)
    if ui.button("Cancel##rf_clear_all_no") then
      cfg._confirmClearAll = false
    end
  end

  -- Result message
  if cfg._clearMsg then
    ui.newLine(2)
    ui.textDisabled(cfg._clearMsg)
  end
end

-- ==========================================================
-- Race Intensity + Rolling Start (Core tab)
-- ==========================================================
local function drawPhysicsIntensitySection(sim, cfg)
  ui.newLine(4)
  ui.separator()
  ui.text("Physics Intensity")
  helpMarker("Slider adjusts physics ratio.\n\n0 = Base AC AI\n100 = Full RaceFlow physics")

  cfg.physicsPush = cfg.physicsPush or {}
  local intensity = cfg.physicsPush.intensity or 50
  ui.setNextItemWidth(ui.windowWidth() - 40)
  local newIntensity = ui.slider("Intensity", intensity, 0, 100, "%.0f")
  if newIntensity ~= nil then
    newIntensity = clamp(newIntensity, 0, 100)
    if math.abs(newIntensity - intensity) > 0.001 then
      cfg.physicsPush.intensity = newIntensity
    end
  end
end

local function drawRollingStartSection(sim, cfg)
  ui.newLine(4)
  ui.separator()
  ui.text("Largada em Movimento Realista (Rolling Start)")
  helpMarker("Formação 2x2 lado a lado na volta de apresentação, com velocidade controlada e relargada realista na reta principal ao receber a bandeira verde.")

  cfg.rollingStart = cfg.rollingStart or {}
  local rs = cfg.rollingStart
  local enabledRS = (rs.enabled == true)

  if ui.checkbox("Ativar Largada em Movimento", enabledRS) then
    rs.enabled = not enabledRS
    notifyChange()
  end

  if rs.enabled == true then
    ui.indent(12)

    -- Status do Pace Car
    local director = (_G.RARE2_API and _G.RARE2_API.getDirector and _G.RARE2_API.getDirector())
    local dirState = director and director.getState and director.getState()
    if dirState and dirState.hasSafetyCar then
      if rgbm then
        ui.textColored("🟢 Pace Car Detectado: Toyota ACTC (dj_safety_car) na liderança!", rgbm(0.2, 0.9, 0.4, 1.0))
      else
        ui.text("🟢 Pace Car Detectado: dj_safety_car")
      end
    else
      ui.textDisabled("⚪ Formação liderada pelo Pole Position (ou adicione o dj_safety_car no grid).")
    end

    ui.newLine(2)
    ui.textDisabled("Predefinições Reais de Largada:")
    if ui.button("GT3 / WEC (2x2 - 85 km/h / 94%)", vec2(210, 22)) then
      rs.limitSpeed = 85
      rs.formationGap = 4.2
      rs.maxOffset = 0.45
      rs.releaseAtPct = 94
      notifyChange()
    end
    ui.sameLine()
    if ui.button("IMSA / Indy (2x2 - 95 km/h / 96%)", vec2(210, 22)) then
      rs.limitSpeed = 95
      rs.formationGap = 3.8
      rs.maxOffset = 0.50
      rs.releaseAtPct = 96
      notifyChange()
    end
    ui.sameLine()
    if ui.button("Chuva / Fila Única (70 km/h / 90%)", vec2(210, 22)) then
      rs.limitSpeed = 70
      rs.formationGap = 5.5
      rs.maxOffset = 0.20
      rs.releaseAtPct = 90
      notifyChange()
    end

    ui.newLine(2)
    local LABEL_W = 190

    rs.limitSpeed = rs.limitSpeed or 85
    local newLS = sliderRow("Velocidade Limite (km/h)", "rs_limitSpeed", rs.limitSpeed, 60, 120, "%.0f km/h", LABEL_W)
    ui.sameLine(0, 6)
    helpMarker("Velocidade limite durante a volta de formação.")
    if newLS ~= nil then rs.limitSpeed = clamp(newLS, 60, 120) end

    rs.formationGap = rs.formationGap or 4.2
    local newFG = sliderRow("Espaço entre Carros (m)", "rs_formationGap", rs.formationGap, 3.0, 10, "%.1f m", LABEL_W)
    ui.sameLine(0, 6)
    helpMarker("Espaço para-choque a para-choque. 3.8 a 4.5m é o padrão das categorias reais.")
    if newFG ~= nil then rs.formationGap = clamp(newFG, 3.0, 10) end

    rs.maxOffset = rs.maxOffset or 0.45
    local newMO = sliderRow("Afastamento Lateral (2x2)", "rs_maxOffset", rs.maxOffset, 0.20, 0.80, "%.2f", LABEL_W)
    ui.sameLine(0, 6)
    helpMarker("Distância de separação entre as duas filas (esquerda e direita).")
    if newMO ~= nil then rs.maxOffset = clamp(newMO, 0.20, 0.80) end

    rs.releaseAtPct = rs.releaseAtPct or 94
    local newRA = sliderRow("Ponto de Largada Verde (%)", "rs_releaseAtPct", rs.releaseAtPct, 20, 98, "%.0f%% da pista", LABEL_W)
    ui.sameLine(0, 6)
    helpMarker("Ponto em que a bandeira verde é acionada. 92% a 96% corresponde à entrada da reta principal.")
    if newRA ~= nil then rs.releaseAtPct = clamp(newRA, 20, 98) end

    ui.unindent(12)
  end

  if rs.enabled and not (physics and physics.setAISplineOffset and physics.setAITopSpeed and physics.setAIThrottleLimit) then
    ui.textDisabled("⚠ Rolling Start pode não funcionar: funções de física ausentes nesta build do CSP.")
  end
end

-------------------------------------------------------
-- TAB: ABOUT
-------------------------------------------------------
local function drawMultiClassTab(sim, cfg, aiCtl)
  ui.header("Multi Class")
  helpMarker("Enables multiclass logic so AI recognize class differences and race accordingly.")

  cfg.multiclassEnabled = (cfg.multiclassEnabled == true)
  local enabled = cfg.multiclassEnabled
  if ui.checkbox("Enable multiclass", enabled) then
    cfg.multiclassEnabled = not enabled
  end

  ui.textDisabled("Manual class assignment for this session. Class 1 = fastest.")
  ui.newLine(4)

  if not cfg.multiclassEnabled then
    ui.textDisabled("Multiclass is OFF. Class assignments + class-based AI are not applied.")
    ui.newLine(6)
  end

  cfg._manualClassForIndex = cfg._manualClassForIndex or {}
  cfg._manualOrder = cfg._manualOrder or {}
  cfg.multiclassClassCount = cfg.multiclassClassCount or 3

  local k = clamp(tonumber(cfg.multiclassClassCount or 3) or 3, 1, 5)
  k = math.floor(k + 0.5)

  while #cfg._manualOrder < k do
    cfg._manualOrder[#cfg._manualOrder + 1] = {}
  end
  while #cfg._manualOrder > k do
    local removed = table.remove(cfg._manualOrder)
    for _, idx in ipairs(removed) do
      table.insert(cfg._manualOrder[k], idx)
      cfg._manualClassForIndex[idx] = k
    end
  end

  local rows = {}
  if aiCtl and aiCtl.getSessionCarStats then
    local ok, data = pcall(aiCtl.getSessionCarStats, sim, cfg)
    if ok and type(data) == "table" then
      rows = data
    end
  end

  if #rows == 0 then
    ui.textDisabled("No AI car data found yet (data may still be loading).")
    if aiCtl and aiCtl.multiclassClassifyNow and ui.button("Force Scan AI Drivers", vec2(180, 24)) then
      aiCtl.multiclassClassifyNow(sim, cfg)
    end
    return
  end

  local function removeFromList(list, idx)
    for i = #list, 1, -1 do
      if list[i] == idx then
        table.remove(list, i)
        return true
      end
    end
    return false
  end

  local function moveToClassTop(newClass, idx)
    for c = 1, k do
      removeFromList(cfg._manualOrder[c], idx)
    end
    table.insert(cfg._manualOrder[newClass], 1, idx)
    cfg._manualClassForIndex[idx] = newClass
  end

  local function ensureInSomeOrderList(classId, idx)
    for c = 1, k do
      for _, v in ipairs(cfg._manualOrder[c]) do
        if v == idx then
          return
        end
      end
    end
    table.insert(cfg._manualOrder[classId], idx)
  end

  local rowByIndex = {}
  for _, r in ipairs(rows) do
    rowByIndex[r.index] = r

    local c = cfg._manualClassForIndex[r.index] or 1
    if c < 1 then c = 1 end
    if c > k then c = k end
    cfg._manualClassForIndex[r.index] = c

    ensureInSomeOrderList(c, r.index)
  end

  ui.header("Session Configuration")

  ui.indent(8)

  ui.setNextItemWidth(80)
  local newK = ui.slider("##Classes", cfg.multiclassClassCount, 1, 5, "%.0f")
  if newK then cfg.multiclassClassCount = math.floor(newK + 0.5) end
  ui.sameLine()
  ui.text("Total Classes")

  ui.sameLine(0, 20)

  if ui.button("Auto-fill (even split fastest→slowest)", vec2(260, 24)) then
    for i, r in ipairs(rows) do
      local target = math.min(k, math.floor((i - 1) / (math.max(1, #rows / k))) + 1)
      moveToClassTop(target, r.index)
    end
  end


  ui.unindent(8)

  ui.newLine(4)
  ui.separator()
  ui.newLine(6)

  for currentClass = 1, k do
    local label = (currentClass == 1 and " (Fastest)")
      or (currentClass == k and " (Slowest)")
      or ""

    local classCount = 0
    for _, idx in ipairs(cfg._manualOrder[currentClass]) do
      if rowByIndex[idx] then
        classCount = classCount + 1
      end
    end

    ui.text(string.format("Class %d%s [%d cars]", currentClass, label, classCount))
    ui.separator()

    local rendered = 0

    for _, idx in ipairs(cfg._manualOrder[currentClass]) do
      local r = rowByIndex[idx]
      if r then
        rendered = rendered + 1
        ui.pushID(idx)

        if ui.button("▲", vec2(22, 22)) then
          local newClass = math.max(1, currentClass - 1)
          moveToClassTop(newClass, idx)
          ui.popID()
          break
        end

        ui.sameLine(0, 2)

        if ui.button("▼", vec2(22, 22)) then
          local newClass = math.min(k, currentClass + 1)
          moveToClassTop(newClass, idx)
          ui.popID()
          break
        end

        ui.sameLine(0, 10)

        ui.text(r.name or "AI Driver")
        ui.sameLine()

        local stats = string.format("(%s p2w | %s km/h)",
          r.p2w and string.format("%.3f", r.p2w) or "---",
          r.topSpeedKmh and tostring(r.topSpeedKmh) or "---"
        )
        ui.textDisabled(stats)

        ui.popID()
      end
    end

    if rendered == 0 then
      ui.textDisabled("Empty")
    end

    ui.newLine(10)
  end

  cfg._multiclassClassForIndex = cfg._manualClassForIndex
end

  local function drawAboutSection(sim, cfg)
  ui.text("RaceFlow v" .. (SCRIPT_VERSION or "?"))
  ui.separator()
  ui.newLine(4)

  ui.textWrapped("RaceFlow sets out to fix the weak spots in Assetto Corsa's base AI by making drivers think, react, and race more like humans. It does this by adding personality, improving racecraft, and adapting behavior in real time.")

  ui.newLine(6)
  ui.text("The Core")
  ui.separator()
  ui.newLine(2)
  ui.textWrapped("Every AI driver is assigned a class (Chill, Normal, or Attack) which shapes how they brake, commit to passes, and handle pressure. Pace varies naturally between drivers, spreading the field instead of locking it into a train. Features like hot lap bursts, hunt mode after being passed, and clean air boosts make races feel alive rather than scripted.")

  ui.newLine(6)
  ui.text("Learning Module")
  ui.separator()
  ui.newLine(2)
  ui.textWrapped("RaceFlow watches every car, every frame. When a car overshoots, spins, or runs off track, it logs a hard event for that corner. Danger builds, braking starts earlier, and speed is capped. As drivers clean up their runs, confidence returns and restrictions ease. Memory persists between sessions, so each track evolves over time. Use the Clear buttons to reset a track or wipe everything if needed.")

  ui.newLine(6)
  ui.text("Multiclass")
  ui.separator()
  ui.newLine(2)
ui.newLine(8)
end


-- ==========================================================
-- TAB: VSC (Virtual Safety Car - Pure Delta Time)
-- ==========================================================
local function drawVSCSection(sim, cfg)
  cfg.vsc = cfg.vsc or {}

  ui.text("Virtual Safety Car (Pure Delta Time)")
  helpMarker("Sistema VSC leve sem modelo 3D. Usa apenas setAITopSpeed + setAIThrottleLimit. Detecta carros parados e ativa automaticamente.")

  local vscState = _G.RARE2_API.getVSCState and _G.RARE2_API.getVSCState() or {}

  -- Status banner
  ui.newLine(2)
  if not sim or not sim.isSessionStarted then
    ui.textDisabled("⚪ Status disponível durante a sessão.")
  elseif vscState.active then
    if rgbm then
      ui.textColored(string.format("⚠ VSC ATIVO – MÁX: %d km/h – %s", vscState.deltaKmh or 80, vscState.reason or ""), rgbm(1.0, 0.85, 0.1, 1.0))
    else
      ui.text(string.format("⚠ VSC ATIVO – MÁX %d km/h", vscState.deltaKmh or 80))
    end
    ui.text(string.format("Tempo ativo: %.1fs / Mín: %ds", vscState.timer or 0, cfg.vsc.minDuration or 10))
  else
    ui.textDisabled("⚪ VSC Inativo (Bandeira Verde)")
    if vscState.cooldown and vscState.cooldown > 0 then
      ui.text(string.format("Cooldown: %.1fs", vscState.cooldown))
    end
  end

  ui.newLine(3)
  ui.separator()

  -- Enable toggle
  local vscEnabled = (cfg.vsc.enabled == true)
  if ui.checkbox("Ativar VSC Automático", vscEnabled) then
    cfg.vsc.enabled = not vscEnabled
    notifyChange()
  end

  if cfg.vsc.enabled then
    ui.indent(12)

    cfg.vsc.deltaKmh = cfg.vsc.deltaKmh or 80
    ui.setNextItemWidth(ui.windowWidth() - 60)
    local newDelta = ui.slider("Velocidade Máxima VSC (km/h)", cfg.vsc.deltaKmh, 40, 140, "%.0f km/h")
    if newDelta ~= nil then
      local val = math.floor(clamp(newDelta, 40, 140) + 0.5)
      if val ~= cfg.vsc.deltaKmh then cfg.vsc.deltaKmh = val; notifyChange() end
    end

    cfg.vsc.throttleLimit = cfg.vsc.throttleLimit or 0.55
    ui.setNextItemWidth(ui.windowWidth() - 60)
    local newThrottle = ui.slider("Limite Throttle IA", cfg.vsc.throttleLimit, 0.1, 1.0, "%.2f")
    if newThrottle ~= nil then
      local val = clamp(newThrottle, 0.1, 1.0)
      if val ~= cfg.vsc.throttleLimit then cfg.vsc.throttleLimit = val; notifyChange() end
    end

    cfg.vsc.minDuration = cfg.vsc.minDuration or 10
    ui.setNextItemWidth(ui.windowWidth() - 60)
    local newMin = ui.slider("Duração Mínima (s)", cfg.vsc.minDuration, 5, 60, "%.0f s")
    if newMin ~= nil then
      local val = math.floor(clamp(newMin, 5, 60) + 0.5)
      if val ~= cfg.vsc.minDuration then cfg.vsc.minDuration = val; notifyChange() end
    end

    cfg.vsc.triggerThreshold = cfg.vsc.triggerThreshold or 2.5
    ui.setNextItemWidth(ui.windowWidth() - 60)
    local newTrigger = ui.slider("Tempo Parado p/ Ativar (s)", cfg.vsc.triggerThreshold, 1.0, 10.0, "%.1f s")
    if newTrigger ~= nil then
      local val = math.floor(clamp(newTrigger * 10, 10, 100) + 0.5) / 10
      if val ~= cfg.vsc.triggerThreshold then cfg.vsc.triggerThreshold = val; notifyChange() end
    end

    cfg.vsc.cooldown = cfg.vsc.cooldown or 30
    ui.setNextItemWidth(ui.windowWidth() - 60)
    local newCD = ui.slider("Cooldown entre VSCs (s)", cfg.vsc.cooldown, 10, 120, "%.0f s")
    if newCD ~= nil then
      local val = math.floor(clamp(newCD, 10, 120) + 0.5)
      if val ~= cfg.vsc.cooldown then cfg.vsc.cooldown = val; notifyChange() end
    end

    cfg.vsc.requireYellowClear = (cfg.vsc.requireYellowClear ~= false)
    if ui.checkbox("Só desativa se bandeira amarela sumir", cfg.vsc.requireYellowClear) then
      cfg.vsc.requireYellowClear = not cfg.vsc.requireYellowClear
      notifyChange()
    end

    cfg.vsc.showPlayerDelta = (cfg.vsc.showPlayerDelta ~= false)
    if ui.checkbox("Mostrar delta do jogador no HUD", cfg.vsc.showPlayerDelta) then
      cfg.vsc.showPlayerDelta = not cfg.vsc.showPlayerDelta
      notifyChange()
    end

    ui.unindent(12)
  end

  ui.newLine(3)
  ui.separator()

  -- Manual trigger button
  ui.text("Controle Manual:")
  if ui.button(vscState.active and "🛑 DESATIVAR VSC" or "🚨 ATIVAR VSC (TESTE)", vec2(200, 30)) then
    if _G.RARE2_API.vscManualTrigger then
      _G.RARE2_API.vscManualTrigger(sim, cfg)
    end
  end
  ui.sameLine()
  helpMarker("Força ativação/desativação do VSC para teste. Útil para verificar se o sistema está funcionando.")

  -- Live delta display for player
  if sim and sim.isSessionStarted and vscState.active then
    local pcar = ac.getCar(0)
    if pcar and not pcar.isInPitlane then
      local targetMs = (cfg.vsc.deltaKmh or 80) / 3.6
      local currentMs = pcar.speedMs or 0
      local deltaKmh = (currentMs - targetMs) * 3.6
      ui.newLine(4)
      ui.separator()
      if rgbm then
        if deltaKmh > 2 then
          ui.textColored(string.format("Seu Delta: +%.1f km/h (ACELERE MENOS)", deltaKmh), rgbm(1.0, 0.3, 0.3, 1))
        elseif deltaKmh > 0 then
          ui.textColored(string.format("Seu Delta: +%.1f km/h", deltaKmh), rgbm(1.0, 0.8, 0.2, 1))
        else
          ui.textColored(string.format("Seu Delta: %.1f km/h (OK)", deltaKmh), rgbm(0.3, 1.0, 0.3, 1))
        end
      else
        ui.text(string.format("Seu Delta: %.1f km/h", deltaKmh))
      end
    end
  end
end


-- ==========================================================
-- TAB: GitHub Updates
-- ==========================================================
local function drawGitHubUpdateSection(sim, cfg)
  cfg.githubUpdate = cfg.githubUpdate or {}

  ui.text("GitHub Update Checker")
  helpMarker("Verifica releases no GitHub via API (requer CSP 0.2.7+ com ac.webRequest).")

  local gState = _G.RARE2_API.githubGetState and _G.RARE2_API.githubGetState() or {}

  -- Status
  ui.newLine(2)
  if gState.checking then
    if rgbm then
      ui.textColored("🔄 Verificando atualizações...", rgbm(1.0, 0.8, 0.2, 1))
    else
      ui.text("Verificando atualizações...")
    end
  elseif gState.error then
    if rgbm then
      ui.textColored("❌ Erro: " .. gState.error, rgbm(1.0, 0.3, 0.3, 1))
    else
      ui.text("Erro: " .. gState.error)
    end
  elseif gState.hasUpdate then
    if rgbm then
      ui.textColored(string.format("🎉 Atualização disponível: v%s → v%s", gState.currentVersion or "?", gState.latestVersion or "?"), rgbm(0.3, 1.0, 0.3, 1))
    else
      ui.text(string.format("Atualização disponível: v%s → v%s", gState.currentVersion or "?", gState.latestVersion or "?"))
    end
  elseif gState.latestVersion then
    if rgbm then
      ui.textColored("✓ Versão atualizada (v" .. (gState.latestVersion or "?") .. ")", rgbm(0.3, 1.0, 0.3, 1))
    else
      ui.text("Versão atualizada (v" .. (gState.latestVersion or "?") .. ")")
    end
  else
    ui.textDisabled("Nenhuma verificação realizada ainda.")
  end

  ui.newLine(3)
  ui.separator()

  -- Config
  local ghEnabled = (cfg.githubUpdate.enabled == true)
  if ui.checkbox("Verificação Automática", ghEnabled) then
    cfg.githubUpdate.enabled = not ghEnabled
    notifyChange()
  end

  if cfg.githubUpdate.enabled then
    ui.indent(12)

    cfg.githubUpdate.repo = cfg.githubUpdate.repo or "RaceFlow/RaceFlow"
    ui.text("Repositório: " .. cfg.githubUpdate.repo)

    cfg.githubUpdate.checkIntervalHours = cfg.githubUpdate.checkIntervalHours or 24
    ui.setNextItemWidth(ui.windowWidth() - 60)
    local newInterval = ui.slider("Intervalo (horas)", cfg.githubUpdate.checkIntervalHours, 1, 168, "%.0f h")
    if newInterval ~= nil then
      local val = math.floor(clamp(newInterval, 1, 168) + 0.5)
      if val ~= cfg.githubUpdate.checkIntervalHours then cfg.githubUpdate.checkIntervalHours = val; notifyChange() end
    end

    cfg.githubUpdate.notifyOnStartup = (cfg.githubUpdate.notifyOnStartup ~= false)
    if ui.checkbox("Verificar na inicialização", cfg.githubUpdate.notifyOnStartup) then
      cfg.githubUpdate.notifyOnStartup = not cfg.githubUpdate.notifyOnStartup
      notifyChange()
    end

    ui.unindent(12)
  end

  ui.newLine(3)
  ui.separator()

  -- Manual check button
  if ui.button("🔍 Verificar Agora", vec2(180, 30)) then
    if _G.RARE2_API.githubCheckUpdates then
      _G.RARE2_API.githubCheckUpdates(cfg, true)
    end
  end
  ui.sameLine()
  if gState.htmlUrl and gState.htmlUrl ~= "" and ui.button("🌐 Abrir Release", vec2(180, 30)) then
    if _G.RARE2_API.githubGetState then
      local state = _G.RARE2_API.githubGetState()
      if state.htmlUrl and ac.openWebLink then
        pcall(ac.openWebLink, state.htmlUrl)
      end
    end
  end

  -- Changelog
  if gState.changelog and gState.changelog ~= "" then
    ui.newLine(4)
    ui.separator()
    ui.text("Changelog da v" .. (gState.latestVersion or "latest") .. ":")
    ui.separator()
    ui.textWrapped(gState.changelog)
  end

  if gState.publishedAt and gState.publishedAt ~= "" then
    ui.newLine(2)
    ui.textDisabled("Publicado em: " .. gState.publishedAt)
  end
end


-- ==========================================================
-- TAB: Web UI Remote
-- ==========================================================
local function drawWebUISection(sim, cfg)
  cfg.webui = cfg.webui or {}

  ui.text("Web UI Remota (File-based Polling)")
  helpMarker("Interface remota via arquivos JSON compartilhados. Ferramenta externa lê status e escreve comandos.\nStatus: Documents/Assetto Corsa/RaceFlow_webui_status.json\nComandos: Documents/Assetto Corsa/RaceFlow_webui_cmd.json")

  local wState = _G.RARE2_API.webuiGetState and _G.RARE2_API.webuiGetState() or {
    statusFile = "Documents/Assetto Corsa/RaceFlow_webui_status.json",
    commandFile = "Documents/Assetto Corsa/RaceFlow_webui_cmd.json",
    authToken = "(none)",
    pollInterval = 0.5,
  }

  -- Status
  ui.newLine(2)
  if cfg.webui.enabled then
    if rgbm then
      ui.textColored("🟢 Web UI ATIVA", rgbm(0.3, 1.0, 0.3, 1))
    else
      ui.text("Web UI ATIVA")
    end
    ui.text("Arquivo de Status: " .. wState.statusFile)
    ui.text("Arquivo de Comandos: " .. wState.commandFile)
    ui.text("Token: " .. wState.authToken)
    ui.text("Intervalo de escrita: " .. wState.pollInterval .. "s")
  else
    ui.textDisabled("⚪ Web UI Desativada")
  end

  ui.newLine(3)
  ui.separator()

  -- Enable toggle
  local webuiEnabled = (cfg.webui.enabled == true)
  if ui.checkbox("Ativar Web UI", webuiEnabled) then
    cfg.webui.enabled = not webuiEnabled
    notifyChange()
  end

  if cfg.webui.enabled then
    ui.indent(12)

    cfg.webui.port = cfg.webui.port or 8080
    ui.setNextItemWidth(ui.windowWidth() - 60)
    local newPort = ui.slider("Porta (referência)", cfg.webui.port, 1024, 65535, "%.0f")
    if newPort ~= nil then
      local val = math.floor(clamp(newPort, 1024, 65535) + 0.5)
      if val ~= cfg.webui.port then cfg.webui.port = val; notifyChange() end
    end
    ui.textDisabled("Nota: CSP não tem servidor HTTP. Porta é apenas referência para ferramenta externa.")

    cfg.webui.authToken = cfg.webui.authToken or ""
    ui.text("Bearer Token (opcional):")
    ui.setNextItemWidth(ui.windowWidth() - 60)
    local newToken = ui.inputText("##webui_token", cfg.webui.authToken)
    if newToken ~= nil and newToken ~= cfg.webui.authToken then
      cfg.webui.authToken = newToken
      notifyChange()
    end
    helpMarker("Deixe vazio para desativar autenticação. Ferramenta externa deve enviar header 'Authorization: Bearer <token>'.")

    ui.unindent(12)
  end

  ui.newLine(3)
  ui.separator()

  -- Example client code
  ui.text("Exemplo de Cliente (Python):")
  ui.separator()
  ui.textWrapped([[
import json, time, requests

STATUS_FILE = "RaceFlow_webui_status.json"
CMD_FILE = "RaceFlow_webui_cmd.json"
TOKEN = "seu_token_aqui"  # ou None

def send_command(action, params=None):
    cmd = {
        "commands": [{
            "id": int(time.time() * 1000),
            "action": action,
            "params": params or {},
            "token": TOKEN
        }]
    }
    with open(CMD_FILE, "w") as f:
        json.dump(cmd, f)

# Loop de polling
while True:
    with open(STATUS_FILE) as f:
        status = json.load(f)
    print(f"VSC: {status['vsc']['active']}, Cars: {len(status['cars'])}")
    
    # Exemplo: ativar VSC se não ativo
    # if not status['vsc']['active']:
    #     send_command("vsc_toggle")
    
    time.sleep(0.5)
]])
  end
end
local function drawAboutSection(sim, cfg)
  ui.text("RaceFlow v" .. (SCRIPT_VERSION or "0.4.5"))
  ui.separator()
  ui.newLine(4)

  ui.textWrapped("RaceFlow sets out to fix the weak spots in Assetto Corsa's base AI by making drivers think, react, and race more like humans. It does this by adding personality, improving racecraft, and adapting behavior in real time.")

  ui.newLine(6)
  ui.text("The Core")
  ui.separator()
  ui.newLine(2)
  ui.textWrapped("Every AI driver is assigned a class (Chill, Normal, or Attack) which shapes how they brake, commit to passes, and handle pressure. Pace varies naturally between drivers, spreading the field instead of locking it into a train. Features like hot lap bursts, hunt mode after being passed, and clean air boosts make races feel alive rather than scripted.")

  ui.newLine(6)
  ui.text("Learning Module")
  ui.separator()
  ui.newLine(2)
  ui.textWrapped("RaceFlow watches every car, every frame. When a car overshoots, spins, or runs off track, it logs a hard event for that corner. Danger builds, braking starts earlier, and speed is capped. As drivers clean up their runs, confidence returns and restrictions ease. Memory persists between sessions, so each track evolves over time. Use the Clear buttons to reset a track or wipe everything if needed.")

  ui.newLine(6)
  ui.text("Multiclass")
  ui.separator()
  ui.newLine(2)
  ui.textWrapped("Assign cars to classes in the Multi Class tab (Class 1 = fastest). Faster classes will push through traffic, while slower classes yield naturally. Use Auto-fill to split the grid by performance, or assign classes manually.")

  ui.newLine(6)
  ui.text("Rolling Start")
  ui.separator()
  ui.newLine(2)
  ui.textWrapped("Realistic formation lap with 2x2 grid, pace car speed control, and green flag release on the main straight. Supports dj_safety_car or pole-sitter led formations.")

  ui.newLine(6)
  ui.text("Fuel Strategy")
  ui.separator()
  ui.newLine(2)
  ui.textWrapped("Endurance-style fuel forcing for AI. Set race length and mandatory stops; AI will pit naturally when fuel runs low. Tire change on pit stop based on wear threshold.")

  ui.newLine(8)
end


function M.draw(sim, cfg)
  pushDarkTheme()

  local enabled = cfg.enabled
  if ui.checkbox("Ativar RaceFlow", enabled) then
    cfg.enabled = not enabled
    notifyChange()
  end

  ui.sameLine(0, 15)
  if rgbm then
    ui.textColored("● Tema Dark", rgbm(0.25, 0.75, 1.0, 1.0))
  else
    ui.text("● Tema Dark")
  end

  ui.newLine(1)

  if not cfg.enabled then
    ui.text("RaceFlow está desativado.")
    popDarkTheme()
    return
  end

  cfg.uiTab = cfg.uiTab or "aggr"

  if ui.radioButton("RaceFlow Core", cfg.uiTab == "aggr") then
    cfg.uiTab = "aggr"
  end
  ui.sameLine()
  if ui.radioButton("Multi Class", cfg.uiTab == "multiclass") then
    cfg.uiTab = "multiclass"
  end
  ui.sameLine()
  if ui.radioButton("Estratégia & Endurance", cfg.uiTab == "strategy") then
    cfg.uiTab = "strategy"
  end
  ui.sameLine()
  if ui.radioButton("VSC", cfg.uiTab == "vsc") then
    cfg.uiTab = "vsc"
  end
  ui.sameLine()
  if ui.radioButton("GitHub Updates", cfg.uiTab == "github") then
    cfg.uiTab = "github"
  end
  ui.sameLine()
  if ui.radioButton("Web UI", cfg.uiTab == "webui") then
    cfg.uiTab = "webui"
  end
  ui.sameLine()
  if ui.radioButton("Sobre", cfg.uiTab == "about") then
    cfg.uiTab = "about"
  end
  ui.newLine(1)
  ui.separator()

  if cfg.uiTab == "aggr" then
    drawDifficultyBoostSection(sim, cfg)
    drawPhysicsIntensitySection(sim, cfg)
    drawAggressionSection(sim, cfg)
    drawPaceSection(sim, cfg)
    drawLowDownforceAISection(sim, cfg)
    drawLearningModuleSection(sim, cfg)
    drawRollingStartSection(sim, cfg)

  elseif cfg.uiTab == "strategy" then
    drawFuelStrategySection(sim, cfg)

  elseif cfg.uiTab == "multiclass" then
    drawMultiClassTab(sim, cfg, aiController)

  elseif cfg.uiTab == "vsc" then
    drawVSCSection(sim, cfg)

  elseif cfg.uiTab == "github" then
    drawGitHubUpdateSection(sim, cfg)

  elseif cfg.uiTab == "webui" then
    drawWebUISection(sim, cfg)

  elseif cfg.uiTab == "about" then
    drawAboutSection(sim, cfg)

  end

  -- Barra de Ações Inferior (Persistência e Reset)
  ui.newLine(4)
  ui.separator()
  ui.newLine(2)
  if ui.button("💾 Salvar Configurações", vec2(160, 24)) then
    if _G.RARE2_API and _G.RARE2_API.saveConfig then
      _G.RARE2_API.saveConfig()
      cfg._savedFeedback = 180
    end
  end
  ui.sameLine(0, 8)
  if ui.button("🔄 Restaurar Padrões", vec2(160, 24)) then
    if _G.RARE2_API and _G.RARE2_API.resetToDefaults then
      _G.RARE2_API.resetToDefaults()
      cfg._resetFeedback = 180
    end
  end

  if (cfg._savedFeedback or 0) > 0 then
    cfg._savedFeedback = cfg._savedFeedback - 1
    ui.sameLine(0, 10)
    if rgbm then
      ui.textColored("✓ Salvo com sucesso!", rgbm(0.2, 0.9, 0.4, 1))
    else
      ui.text("✓ Salvo com sucesso!")
    end
  elseif (cfg._resetFeedback or 0) > 0 then
    cfg._resetFeedback = cfg._resetFeedback - 1
    ui.sameLine(0, 10)
    if rgbm then
      ui.textColored("✓ Restaurado para os padrões!", rgbm(0.9, 0.7, 0.2, 1))
    else
      ui.text("✓ Restaurado!")
    end
  else
    ui.sameLine(0, 10)
    ui.textDisabled("Auto-save: Ativo")
  end

  popDarkTheme()
end

return M