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

-- RaceFlow theme engine (v0.8.0): accent + background opacity are user
-- configurable (About tab -> Appearance). THEME is refreshed in M.draw.
local ACCENTS = {
  cyan   = { 0.22, 0.88, 1.00, "Ciano" },
  green  = { 0.25, 0.95, 0.45, "Verde" },
  orange = { 1.00, 0.65, 0.20, "Laranja" },
  purple = { 0.70, 0.50, 1.00, "Roxo" },
  red    = { 1.00, 0.35, 0.35, "Vermelho" },
  teal   = { 0.20, 0.90, 0.80, "Turquesa" },
  pink   = { 1.00, 0.40, 0.70, "Rosa" },
}
local ACCENT_ORDER = { "cyan", "green", "orange", "purple", "red", "teal", "pink" }
local THEME = { accent = "cyan", bgAlpha = 1.0, corner = 6, compactHeaders = false }

local function accentRgb(a)
  local t = ACCENTS[THEME.accent] or ACCENTS.cyan
  return rgbm(t[1], t[2], t[3], a or 1.0)
end

local C = {
  bg       = function() return rgbm(0.05, 0.07, 0.11, 0.97 * THEME.bgAlpha) end,
  card     = function() return rgbm(0.09, 0.12, 0.18, 0.95 * THEME.bgAlpha) end,
  accent   = function() return accentRgb(1.0) end,
  accentDim= function() return accentRgb(0.55) end,
  ok       = function() return rgbm(0.25, 0.95, 0.45, 1.00) end,
  warn     = function() return rgbm(1.00, 0.78, 0.20, 1.00) end,
  danger   = function() return rgbm(1.00, 0.35, 0.35, 1.00) end,
  text     = function() return rgbm(0.93, 0.96, 1.00, 1.00) end,
  dim      = function() return rgbm(0.60, 0.68, 0.78, 1.00) end,
}

local function pushDarkTheme()
  if not ui.pushStyleColor or not rgbm then return end
  local at = ACCENTS[THEME.accent] or ACCENTS.cyan
  local ar, ag, ab = at[1], at[2], at[3]
  local ba = THEME.bgAlpha
  pcall(function()
    ui.pushStyleColor(ui.StyleColor.WindowBg, rgbm(0.05, 0.07, 0.11, 0.97 * ba))
    ui.pushStyleColor(ui.StyleColor.ChildBg, rgbm(0.09, 0.12, 0.18, 0.95 * ba))
    ui.pushStyleColor(ui.StyleColor.FrameBg, rgbm(0.13, 0.17, 0.24, 0.95))
    ui.pushStyleColor(ui.StyleColor.FrameBgHovered, rgbm(0.18, 0.25, 0.35, 1.00))
    ui.pushStyleColor(ui.StyleColor.FrameBgActive, rgbm(0.22, 0.32, 0.45, 1.00))
    ui.pushStyleColor(ui.StyleColor.Button, rgbm(0.12, 0.20, 0.30, 0.95))
    ui.pushStyleColor(ui.StyleColor.ButtonHovered, rgbm(0.16, 0.35, 0.52, 1.00))
    ui.pushStyleColor(ui.StyleColor.ButtonActive, rgbm(ar * 0.7, ag * 0.7, ab * 0.7, 1.00))
    ui.pushStyleColor(ui.StyleColor.CheckMark, rgbm(ar, ag, ab, 1.00))
    ui.pushStyleColor(ui.StyleColor.SliderGrab, rgbm(ar, ag, ab, 1.00))
    ui.pushStyleColor(ui.StyleColor.SliderGrabActive, rgbm(math.min(1, ar + 0.2), math.min(1, ag + 0.2), math.min(1, ab + 0.2), 1.00))
    ui.pushStyleColor(ui.StyleColor.Header, rgbm(0.13, 0.22, 0.34, 0.95))
    ui.pushStyleColor(ui.StyleColor.HeaderHovered, rgbm(0.18, 0.30, 0.45, 1.00))
    ui.pushStyleColor(ui.StyleColor.HeaderActive, rgbm(0.24, 0.40, 0.58, 1.00))
    ui.pushStyleColor(ui.StyleColor.Separator, rgbm(ar, ag, ab, 0.25))
    ui.pushStyleColor(ui.StyleColor.Text, rgbm(0.93, 0.96, 1.00, 1.00))
    ui.pushStyleColor(ui.StyleColor.TextDisabled, rgbm(0.60, 0.68, 0.78, 1.00))
  end)
  local cr = tonumber(THEME.corner) or 6
  pcall(function()
    ui.pushStyleVar(ui.StyleVar.FrameRounding, cr)
    ui.pushStyleVar(ui.StyleVar.GrabRounding, cr)
    ui.pushStyleVar(ui.StyleVar.WindowRounding, cr + 4)
  end)
end

local function popDarkTheme()
  if not ui.popStyleColor then return end
  pcall(function() ui.popStyleVar(3) end)
  pcall(function() ui.popStyleColor(17) end)
end

-- Card header: big colored title + dim subtitle (skipped in compact mode)
local function cardTitle(title, subtitle)
  ui.pushFont(ui.Font.Title)
  if rgbm then ui.textColored(title, C.accent()) else ui.text(title) end
  ui.popFont()
  if subtitle and not THEME.compactHeaders then ui.textDisabled(subtitle) end
  ui.separator()
  ui.newLine(2)
end

-- Status pill line (colored dot + text)
local function statusLine(active, activeText, idleText)
  if active then
    if rgbm then ui.textColored("● " .. activeText, C.ok())
    else ui.text("● " .. activeText) end
  else
    ui.textDisabled("○ " .. idleText)
  end
end

-- Safe tab renderer: never leaves the window blank on runtime error
local function safeTab(label, fn, sim, cfg)
  local ok, err = pcall(fn, sim, cfg)
  if not ok then
    ui.newLine(4)
    if rgbm then ui.textColored("❌ Erro ao desenhar a aba " .. label, C.danger())
    else ui.text("Erro ao desenhar a aba " .. label) end
    ui.textWrapped("Detalhe: " .. tostring(err))
    ui.newLine(2)
    ui.textDisabled("O restante do app continua funcionando. Envie esse texto ao suporte.")
    ac.log("[RaceFlow UI] tab '" .. tostring(label) .. "' draw failed: " .. tostring(err))
  end
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

-- Full-width slider with the label ABOVE (never clipped by the window edge).
-- help: tooltip text shown on the (?) marker (layman + technical).
local function sliderBlock(label, id, value, minV, maxV, fmt, help)
  ui.alignTextToFramePadding()
  ui.text(label)
  if help then helpMarker(help) end
  ui.setNextItemWidth(math.max(120, ui.windowWidth() - 20))
  return ui.slider("##" .. id, value, minV, maxV, fmt)
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
  local newAgg = sliderBlock("Agressividade global", "aggr_mix", agg, 0, 100, "%.0f",
    "Leigo: 0 = grid calmo, 100 = grid brigando por posição.\nTécnico: define o mix Chill/Normal/Attack distribuído por hash do nome.")
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

  cfg.strategy.manualRaceLaps = cfg.strategy.manualRaceLaps or 20
  local newLaps = sliderBlock("Duração da corrida (voltas)", "strat_laps", cfg.strategy.manualRaceLaps, 3, 1000, "%.0f",
    "Leigo: quantas voltas a IA deve planejar (combustível + pits).\nTécnico: base do cálculo de stint e janela de pit.")
  if newLaps ~= nil then
    local val = math.floor(clamp(newLaps, 3, 1000) + 0.5)
    if val ~= cfg.strategy.manualRaceLaps then
      cfg.strategy.manualRaceLaps = val
      notifyChange()
    end
  end

  cfg.strategy.forcedStops = cfg.strategy.forcedStops or 1
  local newStops = sliderBlock("Paradas obrigatórias nos boxes", "strat_stops", cfg.strategy.forcedStops, 0, 50, "%.0f",
    "Leigo: quantas vezes cada IA vai parar para reabastecer.\nTécnico: força o tanque virtual por stint para induzir o pit.")
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
end

local function drawPaceSection(sim, cfg)
  ui.separator()
  ui.text("Profile Gap")
  helpMarker("Adjusts physics ratio of profiles\n0 = Base AC, no gap between Profiles\n100 = Biggest gap between profiles")

  cfg.paceEnabled = true

  local pace = cfg.paceStrength or 50
  local newPace = sliderBlock("Força do ritmo ( Pace )", "pace_strength", pace, 0, 100, "%.0f",
    "Leigo: 0 = pelotão colado igual ao jogo base, 100 = diferença máxima entre pilotos.\nTécnico: escala o jitter e o boost de ritmo por perfil.")
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
  local newIntensity = sliderBlock("Intensidade da física", "phys_intensity", intensity, 0, 100, "%.0f",
    "Leigo: 0 = IA igual ao jogo base, 100 = física RaceFlow total (freadas e tração moldadas).\nTécnico: interpola brakeHint/throttle/topSpeed aplicados por frame.")
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


-- TAB: GitHub Updates
-- ==========================================================
local function drawGitHubUpdateSection(sim, cfg)
  cfg.githubUpdate = cfg.githubUpdate or {}

  ui.text("GitHub Update Checker")
  helpMarker("Verifica releases no GitHub via API (requer CSP com ac.webRequest).")

  -- Graceful degradation: this CSP build has no ac.webRequest, so in-app
  -- checks can never work. Show guidance instead of a red error + dead toggles.
  if ac.webRequest == nil then
    ui.newLine(2)
    if rgbm then ui.textColored("ℹ Verificação automática indisponível", C.accent())
    else ui.text("Verificação automática indisponível") end
    ui.textWrapped("Esta build do CSP não expõe ac.webRequest, então o app não consegue consultar a API do GitHub sozinho. Isso é esperado e não é um defeito do RaceFlow.")
    ui.newLine(2)
    ui.text("Repositório: " .. (cfg.githubUpdate.repo or "Silxyst/RaceFlow-V2"))
    ui.text("Versão instalada: v" .. (SCRIPT_VERSION or _G.RACEFLOW_VERSION or "?"))
    ui.newLine(2)
    ui.textWrapped("Para atualizar: baixe a última release e substitua a pasta apps/lua/RaceFlow.")
    if ac.openWebLink then
      if ui.button("🌐 Abrir página de Releases", vec2(230, 30)) then
        pcall(ac.openWebLink, "https://github.com/" .. (cfg.githubUpdate.repo or "Silxyst/RaceFlow-V2") .. "/releases")
      end
    end
    return
  end

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

    cfg.githubUpdate.repo = cfg.githubUpdate.repo or "Silxyst/RaceFlow-V2"
    ui.text("Repositório: " .. cfg.githubUpdate.repo)

    cfg.githubUpdate.checkIntervalHours = cfg.githubUpdate.checkIntervalHours or 24
    local newInterval = sliderBlock("Intervalo entre verificações (horas)", "gh_interval", cfg.githubUpdate.checkIntervalHours, 1, 168, "%.0f h",
      "Leigo: de quanto em quanto tempo o app checa atualização sozinho.\nTécnico: throttle do ac.webRequest (evita rate-limit da API).")
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
    local newPort = sliderBlock("Porta (referência)", "webui_port", cfg.webui.port, 1024, 65535, "%.0f",
      "Leigo: só um rótulo — o CSP não tem servidor HTTP, a Web UI usa arquivos.\nTécnico: polling em Documents/Assetto Corsa/RaceFlow_webui_*.json a cada 0.5 s.")
    if newPort ~= nil then
      local val = math.floor(clamp(newPort, 1024, 65535) + 0.5)
      if val ~= cfg.webui.port then cfg.webui.port = val; notifyChange() end
    end
    ui.textDisabled("Nota: CSP não tem servidor HTTP. Porta é apenas referência para ferramenta externa.")

    cfg.webui.authToken = cfg.webui.authToken or ""
    ui.text("Bearer Token (opcional):")
    if ui.inputText then
      ui.setNextItemWidth(ui.windowWidth() - 60)
      local newToken = ui.inputText("##webui_token", cfg.webui.authToken)
      if newToken ~= nil and newToken ~= cfg.webui.authToken then
        cfg.webui.authToken = newToken
        notifyChange()
      end
    else
      ui.textDisabled("Edição de texto indisponível nesta build do CSP.")
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
    print(f"Cars: {len(status['cars'])}, leader: {status['leaderboard'][0]['driver'] if status['leaderboard'] else '-'}")

    # Exemplo: alternar rolling start
    # send_command("rolling_toggle")

    time.sleep(0.5)
]])
end


-- ==========================================================
-- TAB: Caution (FCY + Sector Yellow) - v0.6.0
-- Port of Nary's caution core. Player gets HUD messages only.
-- ==========================================================
local function drawCautionSection(sim, cfg)
  cfg.caution = cfg.caution or {}

  ui.text("Caution por incidentes (IA parada)")
  helpMarker("Quando uma IA para na pista fora dos boxes, sorteia FCY (todos lentos) ou bandeira amarela no setor. Só funciona em corrida, offline, com physics scripting ativo. O jogador recebe avisos no HUD (sem limitação de velocidade).")

  local cState = _G.RARE2_API.getCautionState and _G.RARE2_API.getCautionState() or {}

  -- Status banner
  ui.newLine(2)
  if not sim or not sim.isSessionStarted then
    ui.textDisabled("⚪ Status disponível durante a sessão de corrida.")
  elseif cState.active then
    if cState.mode == "FCY" then
      if rgbm then ui.textColored(string.format("🟡 FULL COURSE YELLOW — máx %d km/h (%s)", cfg.caution.fcySpeedKmh or 80, cState.reason or ""), C.warn())
      else ui.text("FULL COURSE YELLOW") end
    else
      if rgbm then ui.textColored(string.format("🟡 YELLOW SETOR %s (%s)", tostring(cState.sector), cState.reason or ""), C.warn())
      else ui.text("YELLOW SETOR " .. tostring(cState.sector)) end
    end
    ui.text(string.format("Tempo: %.0fs / %.0fs", cState.timer or 0, cState.duration or 0))
    if cState.overtake then
      if rgbm then ui.textColored(string.format("⛔ DEVOLVA A POSIÇÃO p/ %s: %.0fs",
        tostring(cState.overtake.name), cState.overtake.timer or 0), C.danger())
      else ui.text(string.format("DEVOLVA A POSIÇÃO: %.0fs", cState.overtake.timer or 0)) end
    end
  else
    ui.textDisabled("⚪ Pista verde — sem caution ativa")
    if cState.cooldown and cState.cooldown > 0 then
      ui.text(string.format("Cooldown: %.0fs", cState.cooldown))
    end
  end

  if not (physics and type(physics.setAITopSpeed) == "function") then
    ui.newLine(2)
    ui.textDisabled("⚠ Physics scripting indisponível nesta pista/sessão — caution ficará inativo.")
  end

  ui.newLine(3)
  ui.separator()

  local cEnabled = (cfg.caution.enabled == true)
  if ui.checkbox("Ativar Caution automático", cEnabled) then
    cfg.caution.enabled = not cEnabled
    notifyChange()
  end
  helpMarker("Leigo: liga o sistema que reage a batidas (IA parada).\nTécnico: só em corrida offline com physics scripting; desligado por padrão.")

  if cfg.caution.enabled then
    ui.indent(12)

    cfg.caution.fcySpeedKmh = cfg.caution.fcySpeedKmh or 80
    local newFcy = sliderBlock("Velocidade máxima no FCY (km/h)", "cau_fcy", cfg.caution.fcySpeedKmh, 40, 140, "%.0f km/h",
      "Leigo: teto de velocidade das IAs durante bandeira amarela total (padrão FIA: 80).\nTécnico: aplicado via physics.setAITopSpeed a cada frame.")
    if newFcy ~= nil then
      local val = math.floor(clamp(newFcy, 40, 140) + 0.5)
      if val ~= cfg.caution.fcySpeedKmh then cfg.caution.fcySpeedKmh = val; notifyChange() end
    end

    cfg.caution.yellowSpeedKmh = cfg.caution.yellowSpeedKmh or 80
    local newYel = sliderBlock("Velocidade no setor neutralizado (km/h)", "cau_yel", cfg.caution.yellowSpeedKmh, 40, 140, "%.0f km/h",
      "Leigo: teto só para as IAs que estão no setor do incidente; o resto corre livre.\nTécnico: cap por currentSector, demais liberadas a 1e9.")
    if newYel ~= nil then
      local val = math.floor(clamp(newYel, 40, 140) + 0.5)
      if val ~= cfg.caution.yellowSpeedKmh then cfg.caution.yellowSpeedKmh = val; notifyChange() end
    end

    cfg.caution.minDuration = cfg.caution.minDuration or 60
    cfg.caution.maxDuration = cfg.caution.maxDuration or 180
    local newMin = sliderBlock("Duração mínima da caution (s)", "cau_min", cfg.caution.minDuration, 10, 300, "%.0f s",
      "Leigo: tempo mínimo que a bandeira fica ativa antes de poder liberar.\nTécnico: sorteio uniforme entre mínima e máxima por ativação.")
    if newMin ~= nil then
      local val = math.floor(clamp(newMin, 10, 300) + 0.5)
      if val ~= cfg.caution.minDuration then cfg.caution.minDuration = val; notifyChange() end
    end
    local newMax = sliderBlock("Duração máxima da caution (s)", "cau_max", cfg.caution.maxDuration, 10, 300, "%.0f s",
      "Leigo: teto do sorteio de duração; nunca passa disso.\nTécnico: se máxima < mínima, é nivelada à mínima.")
    if newMax ~= nil then
      local val = math.floor(clamp(newMax, 10, 300) + 0.5)
      if val ~= cfg.caution.maxDuration then cfg.caution.maxDuration = val; notifyChange() end
    end

    cfg.caution.fcyChance = cfg.caution.fcyChance or 0.5
    local newCh = sliderBlock("Chance de FCY (vs amarela de setor)", "cau_ch", cfg.caution.fcyChance, 0, 1, "%.2f",
      "Leigo: 0 = sempre só o setor, 1 = sempre pista toda.\nTécnico: probabilidade por sorteio math.random() a cada incidente.")
    if newCh ~= nil then
      local val = clamp(newCh, 0, 1)
      if val ~= cfg.caution.fcyChance then cfg.caution.fcyChance = val; notifyChange() end
    end

    cfg.caution.autoTrigger = (cfg.caution.autoTrigger ~= false)
    if ui.checkbox("Disparo automático por IA parada", cfg.caution.autoTrigger) then
      cfg.caution.autoTrigger = not cfg.caution.autoTrigger
      notifyChange()
    end
    helpMarker("Leigo: desligue para usar SÓ o botão manual de teste.\nTécnico: varre IAs <1 km/h fora do pit a cada frame.")

    ui.newLine(2)
    ui.separator()
    ui.text("Ultrapassagem sob caution")

    cfg.caution.overtakeEnabled = (cfg.caution.overtakeEnabled ~= false)
    if ui.checkbox("Punir ultrapassagem (devolver posição)", cfg.caution.overtakeEnabled) then
      cfg.caution.overtakeEnabled = not cfg.caution.overtakeEnabled
      notifyChange()
    end
    helpMarker("Leigo: passou alguém de bandeira amarela? Devolva em X segundos ou toma punição.\nTécnico: monitora racePosition do jogador; ignora pits e carros distantes (>120 m).")

    if cfg.caution.overtakeEnabled then
      cfg.caution.giveBackTime = cfg.caution.giveBackTime or 10
      local newGb = sliderBlock("Tempo p/ devolver (s)", "cau_gb", cfg.caution.giveBackTime, 3, 30, "%.0f s",
        "Leigo: quanto tempo você tem para frear e devolver a posição.\nTécnico: countdown pausado nos boxes; cancela se a caution acabar.")
      if newGb ~= nil then
        local val = math.floor(clamp(newGb, 3, 30) + 0.5)
        if val ~= cfg.caution.giveBackTime then cfg.caution.giveBackTime = val; notifyChange() end
      end

      cfg.caution.overtimePenalty = cfg.caution.overtimePenalty or 5
      local newOp = sliderBlock("Punição por não devolver (s)", "cau_op", cfg.caution.overtimePenalty, 1, 30, "%.0f s",
        "Leigo: punição aplicada se o tempo acabar.\nTécnico: entra no fluxo do Track Limits (cumpre no box) ou ac.addPenaltyTime.")
      if newOp ~= nil then
        local val = math.floor(clamp(newOp, 1, 30) + 0.5)
        if val ~= cfg.caution.overtimePenalty then cfg.caution.overtimePenalty = val; notifyChange() end
      end
    end

    ui.unindent(12)
  end

  ui.newLine(3)
  ui.separator()
  ui.text("Controle manual:")
  if ui.button(cState.active and "🟢 ENCERRAR CAUTION" or "🟡 TESTAR FCY", vec2(200, 30)) then
    if _G.RARE2_API.cautionManualTrigger then
      _G.RARE2_API.cautionManualTrigger(sim, cfg)
    end
  end
  ui.sameLine()
  helpMarker("Força um FCY para testar se o sistema segura as IAs. Clique de novo para encerrar.")
end


-- ==========================================================
-- TAB: Track Limits (port of Mavil core) - v0.7.0
-- ==========================================================
local function drawTrackLimitsSection(sim, cfg)
  cfg.tracklimits = cfg.tracklimits or {}
  local t = cfg.tracklimits

  ui.text("Limites de pista (port do Mavil TLM)")
  helpMarker("Detecção por rodas fora (wheelsOutside). Avisos → punição de tempo cumprida no box com freio pressionado. IA opcional. Desligado por padrão.")

  local st = _G.RARE2_API.getTrackLimitsState and _G.RARE2_API.getTrackLimitsState() or {}

  -- Player status
  ui.newLine(2)
  if st.penaltyActive and (st.timeLeft or 0) > 0 then
    if rgbm then ui.textColored(string.format("🛑 SUA PUNIÇÃO: %.1fs%s", st.timeLeft, st.serving and " (cumprindo)" or ""), C.danger())
    else ui.text(string.format("SUA PUNIÇÃO: %.1fs", st.timeLeft)) end
    if not st.serving then ui.textDisabled("Pare no box e segure o FREIO.") end
  elseif (st.warn or 0) > 0 then
    ui.text(string.format("Suas advertências: %d / %d", st.warn, st.maxWarn or 4))
  else
    ui.textDisabled("⚪ Sem advertências.")
  end
  if st.lastEvent and st.lastEvent ~= "" then ui.textDisabled("Último: " .. st.lastEvent) end
  if (st.aiWithPenalties or 0) > 0 or (st.aiWithWarnings or 0) > 0 then
    ui.textDisabled(string.format("IA: %d com punição, %d com advertência", st.aiWithPenalties or 0, st.aiWithWarnings or 0))
  end

  ui.newLine(3)
  ui.separator()

  local tlEnabled = (t.enabled == true)
  if ui.checkbox("Ativar Track Limits", tlEnabled) then
    t.enabled = not tlEnabled
    notifyChange()
  end

  if t.enabled then
    ui.indent(12)

    t.maxWarnings = t.maxWarnings or 4
    local newW = sliderBlock("Advertências até punir", "tl_warn", t.maxWarnings, 1, 10, "%.0f",
      "Leigo: quantos cortes seguidos antes de virar punição.\nTécnico: contador por carro com cooldown entre registros.")
    if newW ~= nil then
      local val = math.floor(clamp(newW, 1, 10) + 0.5)
      if val ~= t.maxWarnings then t.maxWarnings = val; notifyChange() end
    end

    t.penaltyTime = t.penaltyTime or 5
    local newP = sliderBlock("Tempo da punição (s)", "tl_time", t.penaltyTime, 1, 30, "%.0f s",
      "Leigo: segundos parado no box segurando o freio.\nTécnico: countdown servido com speed ≤1 km/h + brake >0.7.")
    if newP ~= nil then
      local val = math.floor(clamp(newP, 1, 30) + 0.5)
      if val ~= t.penaltyTime then t.penaltyTime = val; notifyChange() end
    end

    t.wheels = t.wheels or 4
    local newWh = sliderBlock("Rodas fora p/ contar corte", "tl_wheels", t.wheels, 2, 4, "%.0f",
      "Leigo: 2 = rigoroso (encostou, contou), 4 = só corte total.\nTécnico: lê car.wheelsOutside; padrão 4 igual ao Mavil.")
    if newWh ~= nil then
      local val = math.floor(clamp(newWh, 2, 4) + 0.5)
      if val ~= t.wheels then t.wheels = val; notifyChange() end
    end

    t.cooldown = t.cooldown or 7
    local newCd = sliderBlock("Cooldown entre avisos (s)", "tl_cd", t.cooldown, 0, 20, "%.0f s",
      "Leigo: tempo mínimo entre um aviso e outro (evita spam numa escapada longa).\nTécnico: janela por os.clock() por carro.")
    if newCd ~= nil then
      local val = math.floor(clamp(newCd, 0, 20) + 0.5)
      if val ~= t.cooldown then t.cooldown = val; notifyChange() end
    end

    t.waitTime = t.waitTime or 1.9
    local newWt = sliderBlock("Espera no box antes de cumprir (s)", "tl_wait", t.waitTime, 0, 15, "%.1f s",
      "Leigo: simula o tempo do pit crew; 0 = começa a cumprir na hora.\nTécnico: estado 'waiting' antes do countdown de serving.")
    if newWt ~= nil then
      local val = math.floor(clamp(newWt * 10, 0, 150) + 0.5) / 10
      if val ~= t.waitTime then t.waitTime = val; notifyChange() end
    end

    t.trackLimitsEnabled = (t.trackLimitsEnabled ~= false)
    if ui.checkbox("Fiscalizar limites de pista", t.trackLimitsEnabled) then
      t.trackLimitsEnabled = not t.trackLimitsEnabled; notifyChange()
    end
    helpMarker("Leigo: desliga só a detecção (serve p/ testar o resto).\nTécnico: pula o bloco de wheelsOutside.")

    t.penaltiesEnabled = (t.penaltiesEnabled ~= false)
    if ui.checkbox("Aplicar punições de tempo", t.penaltiesEnabled) then
      t.penaltiesEnabled = not t.penaltiesEnabled; notifyChange()
    end
    helpMarker("Leigo: desligado = só avisos, sem punição.\nTécnico: warnings acumulam e zeram sem issuePenalty().")

    t.strictPit = (t.strictPit == true)
    if ui.checkbox("Box estrito (exige isInPit)", t.strictPit) then
      t.strictPit = not t.strictPit; notifyChange()
    end
    helpMarker("Leigo: exige estar PARADO na vaga, não só no pitlane.\nTécnico: canServe usa car.isInPit além de isInPitlane.")

    t.aiEnabled = (t.aiEnabled ~= false)
    if ui.checkbox("IA também recebe punições", t.aiEnabled) then
      t.aiEnabled = not t.aiEnabled; notifyChange()
    end
    helpMarker("Leigo: IAs que cortam pista também são punidas.\nTécnico: mesmo ciclo de avisos por carro IA.")

    if t.aiEnabled then
      t.aiServe = (t.aiServe == true)
      if ui.checkbox("IA cumpre no box durante a corrida", t.aiServe) then
        t.aiServe = not t.aiServe; notifyChange()
      end
      helpMarker("Leigo: IA punida para no box até zerar (cuidado: pode causar fila).\nTécnico: throttle 0 + topspeed 0 com carro parado no pitlane.")
    end

    t.qualiReset = (t.qualiReset ~= false)
    if ui.checkbox("Reset p/ boxes na quali (requer physics)", t.qualiReset) then
      t.qualiReset = not t.qualiReset; notifyChange()
    end
    helpMarker("Leigo: estourou avisos na quali = volta invalidada e carro vai p/ boxes.\nTécnico: physics.teleportCarTo com guard physics.allowed().")

    t.finishAdd = (t.finishAdd ~= false)
    if ui.checkbox("Somar não-cumprida no resultado final", t.finishAdd) then
      t.finishAdd = not t.finishAdd; notifyChange()
    end
    helpMarker("Leigo: terminou devendo = tempo somado no resultado.\nTécnico: ac.addPenaltyTime com guard de existência.")

    ui.newLine(2)
    ui.separator()
    ui.text("Compatibilidade com o jogo")

    t.gamePenaltyCompat = (t.gamePenaltyCompat ~= false)
    if ui.checkbox("Não punir 2x (punição nativa do jogo)", t.gamePenaltyCompat) then
      t.gamePenaltyCompat = not t.gamePenaltyCompat; notifyChange()
    end
    helpMarker("Leigo: o jogo já pune corte (5–10 s desacelerando)? O app pausa os avisos enquanto isso.\nTécnico: sonda car.penaltyTime com pcall; sem o campo, não faz nada.")

    ui.textDisabled("Dica: Content Manager → Drive → Race Weekend → Rules → Penalties OFF evita punição dupla.")
    ui.newLine(2)

    -- Live game-penalty indicator (player)
    do
      local st = _G.RARE2_API.getTrackLimitsState and _G.RARE2_API.getTrackLimitsState() or {}
      if st.gamePenApi then
        if (st.gamePen or 0) > 0.5 then
          if rgbm then ui.textColored(string.format("🎮 JOGO punindo: %.1fs (avisos pausados)", st.gamePen), C.warn())
          else ui.text(string.format("JOGO punindo: %.1fs", st.gamePen)) end
        else
          ui.textDisabled("🎮 Sem punição nativa ativa.")
        end
      else
        ui.textDisabled("🎮 Leitura da punição nativa indisponível nesta build (use o modo manual abaixo).")
      end
    end

    ui.unindent(12)
  end
end


-- ==========================================================
-- Appearance (theme customization) - v0.8.0
-- ==========================================================
local function drawAppearanceSection(sim, cfg)
  cfg.ui = cfg.ui or {}
  ui.text("🎨 Aparência")
  helpMarker("Leigo: mude a cor de destaque e a transparência do fundo.\nTécnico: cor de destaque (accent) e alfa do WindowBg/ChildBg.")

  -- Accent swatches (wrapped in rows of 4 to never clip)
  cfg.ui.accent = cfg.ui.accent or "cyan"
  for idx, key in ipairs(ACCENT_ORDER) do
    local a = ACCENTS[key]
    local label = (cfg.ui.accent == key and "● " or "○ ") .. a[4]
    if ui.button(label .. "##accent_" .. key, vec2(140, 24)) then
      cfg.ui.accent = key
      notifyChange()
    end
    if idx % 4 ~= 0 then ui.sameLine(0, 6) end
  end
  ui.newLine(2)

  cfg.ui.bgAlpha = tonumber(cfg.ui.bgAlpha) or 1.0
  local newA = sliderBlock("Transparência do fundo", "ui_bgalpha", cfg.ui.bgAlpha, 0.4, 1.0, "%.2f",
    "Leigo: 1.0 = fundo sólido, 0.4 = bem transparente.\nTécnico: multiplica o alfa de WindowBg/ChildBg.")
  if newA ~= nil then
    local val = clamp(newA, 0.4, 1.0)
    if math.abs(val - cfg.ui.bgAlpha) > 0.001 then
      cfg.ui.bgAlpha = val
      notifyChange()
    end
  end

  cfg.ui.corner = tonumber(cfg.ui.corner) or 6
  local newC = sliderBlock("Arredondamento dos cantos", "ui_corner", cfg.ui.corner, 0, 12, "%.0f",
    "Leigo: 0 = cantos retos, 12 = bem arredondado.\nTécnico: FrameRounding/GrabRounding e WindowRounding +4.")
  if newC ~= nil then
    local val = math.floor(clamp(newC, 0, 12) + 0.5)
    if val ~= cfg.ui.corner then
      cfg.ui.corner = val
      notifyChange()
    end
  end

  cfg.ui.compactHeaders = (cfg.ui.compactHeaders == true)
  if ui.checkbox("Cabeçalhos compactos (sem subtítulo)", cfg.ui.compactHeaders) then
    cfg.ui.compactHeaders = not cfg.ui.compactHeaders
    notifyChange()
  end
  helpMarker("Leigo: esconde as linhas de explicação das abas, deixa tudo menor.\nTécnico: pula o subtitle em cardTitle().")
end

local function drawAboutSection(sim, cfg)
  drawAppearanceSection(sim, cfg)
  ui.newLine(4)
  ui.separator()
  ui.newLine(4)
  ui.text("RaceFlow v" .. (SCRIPT_VERSION or _G.RACEFLOW_VERSION or "?"))

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

  ui.newLine(6)
  ui.text("Caution (FCY + Sector Yellow)")
  ui.separator()
  ui.newLine(2)
  ui.textWrapped("When an AI car stops on track outside the pits, RaceFlow draws FCY (whole field slows) or a sector yellow (only that sector slows) for a configurable duration, then releases to green. Player gets HUD messages only. Needs physics scripting enabled.")

  ui.newLine(6)
  ui.text("Track Limits")
  ui.separator()
  ui.newLine(2)
  ui.textWrapped("Port of the Mavil Track Limit Manager core: warnings for wheels off track, then a time penalty served stopped in the pit box holding the brake. Works for the player and optionally for AI, with quali reset, extra time for early pit exit and unserved time added to the final result.")

  ui.newLine(8)
end


-- v0.6.0: Caution tab (FCY + sector yellow). VSC tab stays removed.
local TABS_ROW1 = {
  { id = "aggr",       label = "🏁 Core" },
  { id = "multiclass", label = "🏎 Multiclass" },
  { id = "strategy",   label = "⛽ Estratégia" },
  { id = "caution",    label = "🟡 Caution" },
}
local TABS_ROW2 = {
  { id = "tracklimits", label = "⚖ Limits" },
  { id = "github",     label = "☁ Updates" },
  { id = "webui",      label = "🌐 Web UI" },
  { id = "about",      label = "ℹ Sobre" },
}

local function tabButton(label, active, w)
  if active and rgbm then
    local at = ACCENTS[THEME.accent] or ACCENTS.cyan
    ui.pushStyleColor(ui.StyleColor.Button, rgbm(at[1] * 0.35, at[2] * 0.35, at[3] * 0.35, 1.00))
  end
  local clicked = ui.button(label, vec2(w, 30))
  if active and rgbm then ui.popStyleColor() end
  return clicked
end

local function drawTabBar(cfg)
  local avail = ui.windowWidth() - 20
  local w1 = (avail - 3 * 8) / 4
  for i, t in ipairs(TABS_ROW1) do
    if i > 1 then ui.sameLine(0, 8) end
    if tabButton(t.label, cfg.uiTab == t.id, w1) then cfg.uiTab = t.id end
  end
  local w2 = (avail - 3 * 8) / 4
  for i, t in ipairs(TABS_ROW2) do
    if i > 1 then ui.sameLine(0, 8) end
    if tabButton(t.label, cfg.uiTab == t.id, w2) then cfg.uiTab = t.id end
  end
end

function M.draw(sim, cfg)
  -- Refresh theme from user config BEFORE pushing style colors.
  cfg.ui = cfg.ui or {}
  local acc = cfg.ui.accent
  local accOk = false
  for _, k in ipairs(ACCENT_ORDER) do if k == acc then accOk = true break end end
  THEME.accent = accOk and acc or "cyan"
  THEME.bgAlpha = clamp(tonumber(cfg.ui.bgAlpha) or 1.0, 0.4, 1.0)
  THEME.corner = math.floor(clamp(tonumber(cfg.ui.corner) or 6, 0, 12) + 0.5)
  THEME.compactHeaders = (cfg.ui.compactHeaders == true)
  pushDarkTheme()

  -- ===== Header: brand + version + master switch =====
  ui.pushFont(ui.Font.Title)
  if rgbm then ui.textColored("RACEFLOW", C.accent()) else ui.text("RACEFLOW") end
  ui.popFont()
  ui.sameLine(0, 10)
  ui.textDisabled("v" .. (SCRIPT_VERSION or _G.RACEFLOW_VERSION or "?"))
  ui.sameLine(0, 12)
  local enabled = cfg.enabled
  if ui.checkbox("Ativo", enabled) then
    cfg.enabled = not enabled
    notifyChange()
  end

  -- Session / status line (works in setup AND in race)
  local sessName = ""
  local trackName = ""
  local carsN = 0
  local inSession = sim and sim.isSessionStarted
  if sim then
    if ac.getSessionName then
      local ok, n = pcall(ac.getSessionName, sim.currentSessionIndex)
      if ok and n then sessName = tostring(n) end
    end
    if ac.getTrackName then
      local ok, t = pcall(ac.getTrackName)
      if ok and t then trackName = tostring(t) end
    end
    carsN = tonumber(sim.carsCount) or 0
  end
  if inSession then
    local info = sessName
    if trackName ~= "" then info = info .. "  •  " .. trackName end
    if carsN > 0 then info = info .. string.format("  •  %d carros", carsN) end
    ui.textDisabled(info ~= "" and info or "Em sessão")
    statusLine(cfg.enabled, "Sistema pronto", "Sistema pausado")
    local gs = _G.RARE2_API and _G.RARE2_API.githubGetState and _G.RARE2_API.githubGetState() or {}
    if gs.hasUpdate then
      if rgbm then ui.textColored("☁ Atualização disponível: v" .. tostring(gs.latestVersion or "?"), C.ok())
      else ui.text("Atualização disponível") end
    end
  else
    ui.textDisabled("Modo setup — ajustes liberados; dados ao vivo aparecem em pista.")
  end

  ui.newLine(2)
  ui.separator()

  if not cfg.enabled then
    ui.newLine(4)
    ui.textDisabled("RaceFlow está desativado. Marque “Ativo” acima para configurar.")
    popDarkTheme()
    return
  end

  cfg.uiTab = cfg.uiTab or "aggr"
  -- Migrate stale tabs from older versions (e.g. "vsc", "rules", "updates")
  do
    local known = { aggr = true, multiclass = true, strategy = true, caution = true, tracklimits = true, github = true, webui = true, about = true }
    if not known[cfg.uiTab] then cfg.uiTab = "aggr" end
  end
  drawTabBar(cfg)
  ui.newLine(2)
  ui.separator()
  ui.newLine(2)

  if cfg.uiTab == "aggr" then
    cardTitle("🏁 RaceFlow Core", "Personalidade da IA • ritmo • largada • aprendizado")
    safeTab("Core", function(s, c)
      drawDifficultyBoostSection(s, c)
      drawPhysicsIntensitySection(s, c)
      drawAggressionSection(s, c)
      drawPaceSection(s, c)
      drawLowDownforceAISection(s, c)
      drawLearningModuleSection(s, c)
      drawRollingStartSection(s, c)
    end, sim, cfg)

  elseif cfg.uiTab == "strategy" then
    cardTitle("⛽ Estratégia & Endurance", "Voltas • pit-stops • pneus • telemetria")
    safeTab("Estratégia", drawFuelStrategySection, sim, cfg)

  elseif cfg.uiTab == "multiclass" then
    cardTitle("🏎 Multiclass", "Classe 1 = mais rápida • yield / push automático")
    safeTab("Multiclass", function(s, c) drawMultiClassTab(s, c, aiController) end, sim, cfg)

  elseif cfg.uiTab == "caution" then
    cardTitle("🟡 Caution — FCY + Sector Yellow", "Incidentes com IA parada • leve, sem modelo 3D")
    safeTab("Caution", drawCautionSection, sim, cfg)

  elseif cfg.uiTab == "tracklimits" then
    cardTitle("⚖ Track Limits", "Avisos → punição de tempo → cumpra no box")
    safeTab("Track Limits", drawTrackLimitsSection, sim, cfg)

  elseif cfg.uiTab == "github" then
    cardTitle("☁ Atualizações GitHub", "Release channel • semver • changelog")
    safeTab("GitHub", drawGitHubUpdateSection, sim, cfg)

  elseif cfg.uiTab == "webui" then
    cardTitle("🌐 Web UI Remota", "Polling por arquivos • comandos externos")
    safeTab("Web UI", drawWebUISection, sim, cfg)

  elseif cfg.uiTab == "about" then
    cardTitle("ℹ Sobre o RaceFlow", "O que cada módulo faz")
    safeTab("Sobre", drawAboutSection, sim, cfg)

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