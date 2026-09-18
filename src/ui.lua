-- ApexFlow UI – Aggression Pack + Pace Pack

local M = {}

-- APEXFLOW_API guard (prevents nil errors if called before ApexFlow init)
_G.APEXFLOW_API = _G.APEXFLOW_API or {}
local APEXFLOW_API = _G.APEXFLOW_API


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
  if APEXFLOW_API and APEXFLOW_API.markConfigDirty then
    APEXFLOW_API.markConfigDirty()
  end
end

-- ApexFlow theme engine (v0.13.0): independent palette, warm default.
local ACCENTS = {
  orange = { 1.00, 0.55, 0.15, "Laranja Apex" },
  cyan   = { 0.22, 0.88, 1.00, "Ciano" },
  green  = { 0.25, 0.95, 0.45, "Verde" },
  purple = { 0.70, 0.50, 1.00, "Roxo" },
  red    = { 1.00, 0.35, 0.35, "Vermelho" },
  teal   = { 0.20, 0.90, 0.80, "Turquesa" },
  pink   = { 1.00, 0.40, 0.70, "Rosa" },
}
local ACCENT_ORDER = { "orange", "cyan", "green", "purple", "red", "teal", "pink" }
local THEME = { accent = "orange", bgAlpha = 1.0, corner = 8, compactHeaders = false }

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
    ac.log("[ApexFlow UI] tab '" .. tostring(label) .. "' draw failed: " .. tostring(err))
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
  ac.log(string.format("[ApexFlow UI] require('%s') failed: %s", tostring(mod), tostring(res)))
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
    local ok, car = pcall(ac.getCar, i) if not ok then car = nil end
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
    local ok, car = pcall(ac.getCar, i) if not ok then car = nil end
    if car and car.isAIControlled then
      local okN,name = pcall(ac.getDriverName, i)
      name = (okN and name and tostring(name) ~= "") and tostring(name) or ("AI" .. i)
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
    -- v0.15.1 (Sug3): leitura PURA — a escrita no physics vive em
    -- ai_controller.M.applyProfileAggression (update, com throttle).
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

    -- v0.10.0: monitor de estratégia das IAs (pit + combustível)
    ui.newLine(4)
    ui.separator()
    ui.text("🤖 Estratégia das IAs ao vivo")
    helpMarker("Leigo: mostra quem vai parar e quando.\nTécnico: próximos pitLaps calculados + combustível restante/aprendido.")
    local sState = APEXFLOW_API.getStrategyState and APEXFLOW_API.getStrategyState(cfg) or {}
    if sState.autoLaps then
      ui.textDisabled(string.format("Voltas da prova (auto): %d", sState.autoLaps))
    else
      ui.textDisabled(string.format("Voltas da prova (manual): %d", sState.totalLaps or 0))
    end
    if sim and sim.isSessionStarted and sState.cars and #sState.cars > 0 then
      local shown = 0
      for _, c in ipairs(sState.cars) do
        if shown >= 8 then break end
        shown = shown + 1
        local okN, nm = pcall(ac.getDriverName, c.index)
        if not okN or type(nm) ~= "string" or nm == "" then nm = ("IA " .. tostring(c.index)) end
        if #nm > 16 then nm = nm:sub(1, 15) .. "…" end
        local pitTxt = c.nextPit and ("pit v" .. tostring(c.nextPit)) or "sem pit"
        ui.text(string.format("#%-2d %-17s v%-3d ⛽%.1fL %s",
          c.index, nm, c.lap, c.fuel, pitTxt))
      end
    else
      ui.textDisabled("Dados das IAs aparecem durante a sessão.")
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
-- Racecraft: brigas e ultrapassagens (Core tab) - v0.10.0
-- ==========================================================
local function drawRacecraftSection(sim, cfg)
  ui.newLine(4)
  ui.separator()
  ui.text("Racecraft (brigas e ultrapassagens)")
  helpMarker("Leigo: controla o quanto as IAs brigam por posição em vez de andar em fila.\nTécnico: impaciência atrás (stuckRamp), janela de mergulho (draft commit) e empurrão.")

  ui.textDisabled("Predefinições:")
  if ui.button("Calmo", vec2(110, 22)) then
    cfg.stuckBehindDelay = 1.6
    cfg.draftCommitRampGate = 0.30
    cfg.draftCommitPushBoost = 0.040
    cfg.tigerChancePerLap = 0.03
    notifyChange()
  end
  ui.sameLine()
  if ui.button("Equilibrado", vec2(110, 22)) then
    cfg.stuckBehindDelay = 0.8
    cfg.draftCommitRampGate = 0.15
    cfg.draftCommitPushBoost = 0.070
    cfg.tigerChancePerLap = 0.07
    notifyChange()
  end
  ui.sameLine()
  if ui.button("Agressivo", vec2(110, 22)) then
    cfg.stuckBehindDelay = 0.4
    cfg.draftCommitRampGate = 0.08
    cfg.draftCommitPushBoost = 0.100
    cfg.tigerChancePerLap = 0.12
    notifyChange()
  end

  ui.newLine(2)

  if cfg.stuckBehindDelay == nil then cfg.stuckBehindDelay = 0.8 end
  local newDelay = sliderBlock("Tempo colado até atacar (s)", "rc_delay", cfg.stuckBehindDelay, 0.2, 3.0, "%.1f s",
    "Leigo: menor = a IA tenta passar mais cedo.\nTécnico: stuckBehindDelay antes da rampa de impaciência.")
  if newDelay ~= nil then
    local val = math.floor(clamp(newDelay * 10, 2, 30) + 0.5) / 10
    if math.abs(val - cfg.stuckBehindDelay) > 0.001 then cfg.stuckBehindDelay = val; notifyChange() end
  end

  if cfg.draftCommitRampGate == nil then cfg.draftCommitRampGate = 0.15 end
  local newGate = sliderBlock("Coragem no mergulho", "rc_gate", cfg.draftCommitRampGate, 0.05, 0.50, "%.2f",
    "Leigo: menor = mergulhos mais ousados por dentro.\nTécnico: limiar da rampa p/ estado commit.")
  if newGate ~= nil then
    local val = clamp(newGate, 0.05, 0.50)
    if math.abs(val - cfg.draftCommitRampGate) > 0.0005 then cfg.draftCommitRampGate = val; notifyChange() end
  end

  if cfg.draftCommitPushBoost == nil then cfg.draftCommitPushBoost = 0.070 end
  local newPush = sliderBlock("Empurrão na briga", "rc_push", cfg.draftCommitPushBoost, 0, 0.12, "%.3f",
    "Leigo: maior = lado a lado mais intenso sem bater.\nTécnico: boost de throttle durante commit.")
  if newPush ~= nil then
    local val = clamp(newPush, 0, 0.12)
    if math.abs(val - cfg.draftCommitPushBoost) > 0.0005 then cfg.draftCommitPushBoost = val; notifyChange() end
  end

  if cfg.tigerChancePerLap == nil then cfg.tigerChancePerLap = 0.07 end
  local newTiger = sliderBlock("Chance de volta voadora (%/volta)", "rc_tiger", (cfg.tigerChancePerLap or 0.07) * 100, 0, 20, "%.0f%%",
    "Leigo: volta mágica aleatória que embaralha o grid.\nTécnico: tigerChancePerLap × 100.")
  if newTiger ~= nil then
    local val = clamp(newTiger, 0, 20) / 100
    if math.abs(val - cfg.tigerChancePerLap) > 0.0005 then cfg.tigerChancePerLap = val; notifyChange() end
  end
end

-- ==========================================================
-- Learning Module (Core tab)
-- ==========================================================
local function drawLearningModuleSection(sim, cfg)
  ui.newLine(4)
  ui.separator()
  ui.text("Learning Module")
  helpMarker("Enable/disable ApexFlow's adaptive corner memory.\n\nON = hard events update track memory and learned danger/caps are applied.\nOFF = no new learning and learned danger/caps are ignored, while the rest of ApexFlow still runs.")

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
      local mem = APEXFLOW_API and APEXFLOW_API.getMemory and APEXFLOW_API.getMemory()
      if mem and mem.tracks and trackId and mem.tracks[trackId] then
        local count = 0
        local t = mem.tracks[trackId]
        if t and t.turns then
          for _ in pairs(t.turns) do count = count + 1 end
        end
        mem.tracks[trackId] = nil
        -- Save immediately — don't wait for the 12s autosave cycle
        if APEXFLOW_API then
          APEXFLOW_API._memoryDirty = false
          if APEXFLOW_API.saveMemory then pcall(APEXFLOW_API.saveMemory) end
        end
        cfg._clearMsg = string.format("Cleared %d corners for %s.", count, tostring(trackId))
        ac.log(string.format("[ApexFlow] Cleared and saved memory for: %s (%d corners)", tostring(trackId), count))
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
      local mem = APEXFLOW_API and APEXFLOW_API.getMemory and APEXFLOW_API.getMemory()
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
        if APEXFLOW_API then
          APEXFLOW_API._memoryDirty = false
          if APEXFLOW_API.saveMemory then pcall(APEXFLOW_API.saveMemory) end
        end
        cfg._clearMsg = string.format("Cleared %d tracks, %d corners total.", trackCount, cornerCount)
        ac.log(string.format("[ApexFlow] Cleared ALL memory: %d tracks, %d corners.", trackCount, cornerCount))
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
  helpMarker("Slider adjusts physics ratio.\n\n0 = Base AC AI\n100 = Full ApexFlow physics")

  cfg.physicsPush = cfg.physicsPush or {}
  local intensity = cfg.physicsPush.intensity or 50
  local newIntensity = sliderBlock("Intensidade da física", "phys_intensity", intensity, 0, 100, "%.0f",
    "Leigo: 0 = IA igual ao jogo base, 100 = física ApexFlow total (freadas e tração moldadas).\nTécnico: interpola brakeHint/throttle/topSpeed aplicados por frame.")
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
    local director = (APEXFLOW_API and APEXFLOW_API.getDirector and APEXFLOW_API.getDirector())
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

-- ==========================================================
-- v0.15.1 (Sug1): cards unificados
--  * Ritmo & Dificuldade = Difficulty + Physics Intensity + Pace
--  * Pit Real & Falhas = pitSpeedReal + failures (sai telemetria/voz daqui)
--  * Telemetria & Voz = CSV + modulo de voz (fonte unica, so no HUD)
--  (v0.22.0: movidos p/ depois das seções que usam — forward-ref vira global nil)
-- ==========================================================
local function drawRhythmSection(sim, cfg)
  drawDifficultyBoostSection(sim, cfg)
  drawPhysicsIntensitySection(sim, cfg)
  drawPaceSection(sim, cfg)
end

-- v0.29.0 limpo extremo: drawFailuresSection removido (3,4,6 peso morto — falhas genéricas, não usado)
-- v0.29.0 limpo extremo: drawVoiceSection removido (voice 6 removido)
-- v0.29.0 limpo extremo: drawTelemetryVoiceSection removido (telemetria + voz removidos)
-- Stubs removidos para peso morto zero (mantido só comentário)

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

  local gState = APEXFLOW_API.githubGetState and APEXFLOW_API.githubGetState() or {}

  -- Sem HTTP no jogo: se o painel local (panel_server.py) já gravou o
  -- resultado, o painel funcional abaixo aparece normalmente (via arquivo).
  if ac.webRequest == nil and not gState.latestVersion then
    ui.newLine(2)
    if rgbm then ui.textColored("ℹ Verificação automática indisponível", C.accent())
    else ui.text("Verificação automática indisponível") end
    ui.textWrapped("Esta build do CSP não expõe ac.webRequest. Para checagem automática, rode o painel local: python web/panel_server.py (ele consulta o GitHub e o app lê o resultado).")
    ui.newLine(2)
    ui.text("Repositório: " .. (cfg.githubUpdate.repo or "Silxyst/ApexFlow"))
    ui.text("Versão instalada: v" .. (SCRIPT_VERSION or _G.APEXFLOW_VERSION or "?"))
    ui.newLine(2)
    ui.textWrapped("Para atualizar: baixe a última release e substitua a pasta apps/lua/ApexFlow.")
    if ac.openWebLink then
      if ui.button("🌐 Abrir página de Releases", vec2(230, 30)) then
        pcall(ac.openWebLink, "https://github.com/" .. (cfg.githubUpdate.repo or "Silxyst/ApexFlow") .. "/releases")
      end
    end
    return
  end
  if gState.fromFile then
    ui.textDisabled("Via painel local (panel_server.py) — o jogo não tem HTTP nesta build do CSP")
  end

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

    cfg.githubUpdate.repo = cfg.githubUpdate.repo or "Silxyst/ApexFlow"
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
    if APEXFLOW_API.githubCheckUpdates then
      APEXFLOW_API.githubCheckUpdates(cfg, true)
    end
  end
  ui.sameLine()
  if gState.htmlUrl and gState.htmlUrl ~= "" and ui.button("🌐 Abrir Release", vec2(180, 30)) then
    if APEXFLOW_API.githubGetState then
      local state = APEXFLOW_API.githubGetState()
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


-- v0.29.0 limpo extremo: drawCautionSection removido (caution 3 removido — AC nativo assume)
-- stub removido para peso morto zero (mantido só comentário)


-- v0.29.0 limpo extremo: drawTrackLimitsSection removido (tracklimits 4 removido — AC nativo assume)
-- stub removido para peso morto zero (mantido só comentário)


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
  ui.text("ApexFlow v" .. (SCRIPT_VERSION or _G.APEXFLOW_VERSION or "?"))
  ui.textDisabled("Independent race suite for Assetto Corsa — offline AI, strategy & race control.")

  ui.textWrapped("ApexFlow enhances offline single-player by giving AI personality, racecraft and memory. Every driver has a class and learns corners; the field spreads naturally with hunt, hot laps and clean-air logic.")

  ui.newLine(6)
  ui.text("The Core")
  ui.separator()
  ui.newLine(2)
  ui.textWrapped("Every AI driver is assigned a class (Chill, Normal, or Attack) which shapes how they brake, commit to passes, and handle pressure. Pace varies naturally between drivers, spreading the field instead of locking it into a train. Features like hot lap bursts, hunt mode after being passed, and clean air boosts make races feel alive rather than scripted.")

  ui.newLine(6)
  ui.text("Learning Module")
  ui.separator()
  ui.newLine(2)
  ui.textWrapped("ApexFlow watches every car, every frame. When a car overshoots, spins, or runs off track, it logs a hard event for that corner. Danger builds, braking starts earlier, and speed is capped. As drivers clean up their runs, confidence returns and restrictions ease. Memory persists between sessions, so each track evolves over time. Use the Clear buttons to reset a track or wipe everything if needed.")

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
  ui.text("Gaps & Penalty Severity (v0.25.0+)")
  ui.separator()
  ui.newLine(2)
  ui.textWrapped("Live gaps to the car behind and sector deltas to P1, plus a penalty-severity counter (PP) for regulatory awareness. AC-native race control handles flags and limits.")

  ui.newLine(6)
  ui.text("Race Events HUD")
  ui.separator()
  ui.newLine(2)
  ui.textWrapped("Overlay window with live gaps, PP and strategy. Enable it in Content Manager → Apps → ApexFlow Events. Fully customizable in the HUD tab (gaps/PP only, AC-native flags).")

  ui.newLine(8)
end

-- ==========================================================
-- TAB: HUD Events (personalização) - v0.12.0
-- ==========================================================
local function drawHudEventsSettings(sim, cfg)
  cfg.hudEvents = cfg.hudEvents or {}
  local h = cfg.hudEvents
  -- v0.29.0 limpo: showCaution/showTrackLimits removidos (3,4)
  if h.showStrategy == nil then h.showStrategy = true end
  if h.showPosition == nil then h.showPosition = true end
  if h.showSession == nil then h.showSession = true end
  if h.showLearning == nil then h.showLearning = false end
  if h.showExtras == nil then h.showExtras = true end
  if h.compact == nil then h.compact = false end
  if h.progressBars == nil then h.progressBars = true end
  if h.blink == nil then h.blink = true end
  h.scale = tonumber(h.scale) or 1.0
  h.scale = clamp(h.scale, 0.7, 1.5)
  if h.showGapBehind == nil then h.showGapBehind = true end
  if h.showDeltaLive == nil then h.showDeltaLive = true end

  ui.text("Race Events HUD — Personalização")
  helpMarker("Leigo: escolha o que aparece no overlay ApexFlow Events (gaps/PP).\nTécnico: cada seção lê o estado do seu módulo; desligar esconde só o visual.")

  ui.newLine(2)
  ui.textDisabled("Marque o que quer ver no overlay:")
  if ui.checkbox("Estratégia (próximo pit / combustível)", h.showStrategy) then
    h.showStrategy = not h.showStrategy; notifyChange()
  end
  if ui.checkbox("Posição / volta / velocidade", h.showPosition) then
    h.showPosition = not h.showPosition; notifyChange()
  end
  if ui.checkbox("Sessão (pista / tempo restante)", h.showSession) then
    h.showSession = not h.showSession; notifyChange()
  end
  if ui.checkbox("Gaps (atrás / setor) — PP", h.showGapBehind) then
    h.showGapBehind = not h.showGapBehind; notifyChange()
  end
  if ui.checkbox("Learning (pistas memorizadas)", h.showLearning) then
    h.showLearning = not h.showLearning; notifyChange()
  end
  if ui.checkbox("Extras (preset · update · detalhes)", h.showExtras) then
    h.showExtras = not h.showExtras; notifyChange()
  end
  helpMarker("Leigo: preset atual, aviso de update, marcha/pneus/paradas da IA.\nTécnico: lê githubGetState e strategy.getState (gaps/PP).")

  ui.newLine(2)
  ui.separator()
  ui.text("Estilo")
  if ui.checkbox("Modo compacto (menos espaçamento)", h.compact) then
    h.compact = not h.compact; notifyChange()
  end
  helpMarker("Leigo: deixa o HUD menor e mais denso.\nTécnico: pula separadores e textos secundários.")
  if ui.checkbox("Barras de progresso", h.progressBars) then
    h.progressBars = not h.progressBars; notifyChange()
  end
  if ui.checkbox("Piscar alertas críticos", h.blink) then
    h.blink = not h.blink; notifyChange()
  end
  if h.hideInPits == nil then h.hideInPits = true end
  if ui.checkbox("Esconder parado no box (+10s)", h.hideInPits) then
    h.hideInPits = not h.hideInPits; notifyChange()
  end
  helpMarker("Leigo: no box parado o painel dorme sozinho e volta na pista.\nTécnico: gate por isInPitlane/isInPit + speed < 5 por 10s.")

  ui.newLine(2)
  local newScale = sliderBlock("Escala do HUD", "hud_scale", h.scale, 0.7, 1.5, "%.2f",
    "Leigo: aumenta/diminui o tamanho do texto do overlay.\nTécnico: fator aplicado ao HUD, não à janela.")
  if newScale ~= nil then
    local v = clamp(newScale, 0.7, 1.5)
    if math.abs(v - h.scale) > 0.001 then h.scale = v; notifyChange() end
  end

  ui.newLine(2)
  if ui.button("📺 Abrir ApexFlow Events", vec2(220, 28)) then
    if ac.setWindowOpen then pcall(ac.setWindowOpen, "events", true) end
  end
  ui.sameLine()
  if ui.button("👁 Testar HUD", vec2(150, 28)) then
    if APEXFLOW_API.hudPreviewStart then APEXFLOW_API.hudPreviewStart(10) end
  end
  ui.sameLine()
  helpMarker("Abre a janela overlay. O botão 👁 injeta 10s de FCY + punição fake (com tag PREVIEW) p/ ver o layout sem correr.")
end-- ==========================================================
-- v0.19.0: BROADCAST SKIN — mesma engine ImGui, cara de TV.
-- Faixas coloridas full-width (beginChild + ChildBg, padrão provado),
-- toggles pill ON/OFF, números herói em fonte Title, selos de status,
-- trilho + inspetor + status bar mantidos como esqueleto.
-- ==========================================================

local NAV_RAIL = {
  { id = "dash",   icon = "🏠", label = "Início",   desc = "Telemetria viva da sessão" },
  { id = "ai",     icon = "🤖", label = "Pilotos",  desc = "Personalidade, brigas e aprendizado da IA" },
  { id = "race",   icon = "🏁", label = "Corrida",  desc = "Duração, pits, pneus e largada" },
  { id = "hud",    icon = "📡", label = "Tela&Voz", desc = "Painel na tela, telemetria e voz" },
  { id = "sys",    icon = "⚙️", label = "Ajustes",  desc = "Visual, atualizações e bastidores" },
}

-- ---------------- tempo / animação ----------------
local function animT() return os.clock() or 0 end
local function animPulse(speed, lo, hi)
  local s = (math.sin(animT() * (speed or 3)) + 1) / 2
  return lo + (hi - lo) * s
end
local function animDots()
  local f = math.floor(animT() * 2) % 3
  if f == 0 then return "●○○" elseif f == 1 then return "○●○" else return "○○●" end
end

-- ---------------- toasts ----------------
local function toast(cfg, kind, title, msg)
  cfg._toasts = cfg._toasts or {}
  table.insert(cfg._toasts, { kind = kind or "info", title = title or "", msg = msg or "", t0 = animT() })
  if #cfg._toasts > 4 then table.remove(cfg._toasts, 1) end
end
local function drawToasts(cfg)
  local list = cfg._toasts or {}
  local now = animT()
  local keep = {}
  for _, t in ipairs(list) do
    if (now - (t.t0 or 0)) < 4 then
      keep[#keep + 1] = t
      local mark = "■"
      if t.kind == "ok" then mark = "✅"
      elseif t.kind == "warn" then mark = "⚠️"
      elseif t.kind == "danger" then mark = "🛑"
      else mark = "ℹ️" end
      ui.text(mark .. " " .. (t.title ~= "" and (t.title .. " — ") or "") .. t.msg)
    end
  end
  cfg._toasts = keep
  if #keep > 0 then ui.separator() ui.newLine(2) end
end

-- ---------------- estado ----------------
local function ensureUiState(cfg)
  cfg._ui_state = cfg._ui_state or {}
  cfg._usage = cfg._usage or { nav = {}, sections = {} }
  cfg.ui = cfg.ui or {}
  cfg.uiNav = cfg.uiNav or "dash"
  local migrate = {
    aggr = "ai", multiclass = "ai",
    strategy = "race",
    -- v0.29.0: caution/tracklimits removidos (3,4) — migra para dash
    hud = "hud",
    github = "sys", webui = "sys", about = "sys",
  }
  local known = { dash = true, ai = true, race = true, safety = true, hud = true, sys = true }
  if not known[cfg.uiNav] then
    if cfg.uiTab and migrate[cfg.uiTab] then cfg.uiNav = migrate[cfg.uiTab]
    else cfg.uiNav = "dash" end
  end
  if cfg._wizStep == nil then cfg._wizStep = 1 end
  return cfg._ui_state
end


local function trackNav(cfg, navId)
  cfg._usage = cfg._usage or { nav = {}, sections = {} }
  cfg._usage.nav = cfg._usage.nav or {}
  cfg._usage.nav[navId] = (cfg._usage.nav[navId] or 0) + 1
  cfg._navFlash = animT()
end

local function trackSection(cfg, secId)
  cfg._usage = cfg._usage or { nav = {}, sections = {} }
  cfg._usage.sections = cfg._usage.sections or {}
  cfg._usage.sections[secId] = (cfg._usage.sections[secId] or 0) + 1
end

local function matchesSearch(cfg, haystack)
  local q = cfg._search or ""
  if q == "" then return true end
  return (haystack or ""):lower():find(q:lower(), 1, true) ~= nil
end

local function animBar(frac, label)
  frac = math.max(0, math.min(1, tonumber(frac) or 0))
  local ok = false
  if ui.progressBar then ok = pcall(ui.progressBar, frac, vec2(-1, 12)) end
  if not ok then
    local n = math.floor(frac * 18 + 0.5)
    ui.textDisabled("[" .. string.rep("█", n) .. string.rep("░", 18 - n) .. "] " .. (label or ""))
  elseif label then
    ui.textDisabled(label)
  end
end

-- ---------------- peças broadcast ----------------
-- Faixa full-width colorida (padrão do AC-Engineer: ChildBg + beginChild).
-- id único obrigatório. Blindada: qualquer erro vira fallback sem faixa
-- (e desativa faixas p/ o resto da sessão, sem spam de log).
local bandBroken = false
local function band(id, r, g, b, h, fn)
  if bandBroken or not (ui.beginChild and ui.endChild and ui.pushStyleColor and rgbm) then
    fn()
    return false
  end
  local pushed, begun = false, false
  local okOpen = pcall(function()
    ui.pushStyleColor(ui.StyleColor.ChildBg, rgbm(r, g, b, 1.0))
    pushed = true
    ui.beginChild(id, vec2(0, h), false)
    begun = true
  end)
  if not okOpen then
    if pushed then pcall(ui.popStyleColor) end
    bandBroken = true
    fn()
    return false
  end
  local okFn = pcall(fn)
  if begun then pcall(ui.endChild) end
  if pushed then pcall(ui.popStyleColor) end
  return okFn
end

-- Helpers puros (declarados cedo: usados por view()/pills — evita forward-ref).
-- Raiz do app p/ assets (mesmo truque do AC-Engineer: ScriptOrigin).
local function appRoot()
  if not (ac and ac.getFolder and ac.FolderID) then return nil end
  local ok, dir = pcall(ac.getFolder, ac.FolderID.ScriptOrigin)
  if ok and dir and dir ~= "" then return tostring(dir) end
  return nil
end

-- Título com Segoe UI Bold quando existir (pcall, como o Dream faz);
-- senão cai para a fonte Title. Nunca quebra.
local function titleText(txt, color)
  if ui.pushDWriteFont and ui.popDWriteFont then
    local ok = pcall(ui.pushDWriteFont, "Segoe UI;Weight=Bold")
    if ok then
      if color and rgbm then ui.textColored(txt, color) else ui.text(txt) end
      pcall(ui.popDWriteFont)
      return
    end
  end
  ui.pushFont(ui.Font.Title)
  if color and rgbm then ui.textColored(txt, color) else ui.text(txt) end
  ui.popFont()
end

-- Cursor de mão sobre o último widget (tudo guardado).
local function hand()
  if ui.setMouseCursor and ui.MouseCursor and ui.MouseCursor.Hand and ui.itemHovered then
    local ok, hov = pcall(ui.itemHovered)
    if ok and hov then pcall(ui.setMouseCursor, ui.MouseCursor.Hand) end
  end
end

-- Largura útil (responsivo como o Dream: availableSpaceX com fallback).
local function contentWidth()
  if ui.availableSpaceX then
    local ok, w = pcall(ui.availableSpaceX)
    if ok and tonumber(w) and tonumber(w) > 100 then return tonumber(w) end
  end
  return math.max(300, ui.windowWidth() - 20)
end

local function pillToggle(id, label, val, summary)
  local w = 84
  if val and rgbm then
    ui.pushStyleColor(ui.StyleColor.Button, rgbm(0.12, 0.45, 0.24, 1.00))
  end
  local clicked = ui.button((val and "● ON" or "○ OFF") .. "##" .. id, vec2(w, 28))
  if val and rgbm then ui.popStyleColor() end
  ui.sameLine(0, 8)
  ui.text(label)
  if summary and summary ~= "" then
    ui.newLine(1)
    ui.textDisabled("      " .. summary)
  end
  if clicked then return not val end
  return val
end

-- Linha de visão numerada com barra lateral de acento.
-- opts = { status="" } (modo Leigo/Técnico removido na v0.23.0: tudo visível)
local function view(cfg, id, num, title, summary, opts, fn, sim)
  opts = opts or {}
  local st = ensureUiState(cfg)
  if st[id] == nil then st[id] = true end
  local isOpen = st[id]
  if rgbm then ui.textColored("▌", C.accent()) else ui.text("|") end
  ui.sameLine(0, 4)
  ui.setNextItemWidth(math.max(200, ui.windowWidth() - 30))
  local head = (isOpen and "∨  " or "›  ") .. num .. " · " .. title
  if opts.status and opts.status ~= "" then head = head .. "     ·  " .. opts.status end
  if ui.button(head .. "##view_" .. id, vec2(-1, 32)) then
    st[id] = not isOpen
    if not isOpen then trackSection(cfg, id) end
    isOpen = not isOpen
  end
  hand()
  if summary and summary ~= "" then ui.textDisabled("      " .. summary) end
  if isOpen then
    ui.indent(8)
    safeTab(title, fn, sim, cfg)
    ui.unindent(8)
    ui.newLine(2)
  end
  ui.separator()
  ui.newLine(2)
end

-- ---------------- status do sistema — limpo extremo v0.29.0: só gaps/PP (caution/track removidos) ----------------
local function getSystemStatus(sim, cfg)
  -- v0.29.0: tl/cs removidos (3,4,6) — AC nativo assume
  local stt = APEXFLOW_API.getStrategyState and APEXFLOW_API.getStrategyState(cfg) or {}
  local mem = APEXFLOW_API.getMemory and APEXFLOW_API.getMemory() or nil
  local memCount = 0
  if mem and mem.tracks then for _ in pairs(mem.tracks) do memCount = memCount + 1 end end
  -- retornar stubs compatíveis para callers antigos (tl,cs vazios)
  local tl = {}
  local cs = {}
  return tl, cs, stt, memCount
end

-- Faixa de estado global — limpa: sempre verde (caution/penalty removidos, AC nativo)
local function drawStateBand(sim, cfg)
  local r, g, b, txt = 0.10, 0.38, 0.20, "🟢 PISTA VERDE"
  band("##rf_stateband", r, g, b, 40, function()
    ui.pushFont(ui.Font.Title)
    if rgbm then ui.textColored(txt, rgbm(1, 1, 1, 1)) else ui.text(txt) end
    ui.popFont()
  end)
end

-- ---------------- barra de comando ----------------
local function drawCommandBar(sim, cfg)
  local on = cfg.enabled
  if on and rgbm then ui.pushStyleColor(ui.StyleColor.Button, rgbm(0.12, 0.45, 0.24, 1.00)) end
  if ui.button((on and "⏻ ON" or "⏻ OFF") .. "##power", vec2(84, 32)) then
    cfg.enabled = not on
    notifyChange()
    toast(cfg, cfg.enabled and "ok" or "warn", cfg.enabled and "App ligado" or "App pausado", "")
  end
  if on and rgbm then ui.popStyleColor() end
  ui.sameLine(0, 8)
  if ui.inputText then
    ui.setNextItemWidth(math.max(120, ui.windowWidth() - 140))
    local q = cfg._search or ""
    local newQ = ui.inputText("⌨ filtrar…##cmd_search", q)
    if newQ ~= nil and newQ ~= q then cfg._search = newQ end
    ui.sameLine(0, 8)
  end
  ui.textDisabled("Filtre por nome: “pit”, “gaps”, “PP”…" .. ((cfg._search or "") ~= "" and " · filtro ativo" or ""))
  if (cfg._search or "") ~= "" then
    ui.sameLine(0, 8)
    if ui.button("X##cmd_clear", vec2(28, 22)) then cfg._search = "" end
  end
end

-- ---------------- peças classe-Dream (v0.20.0) ----------------


-- Cabeçalho com logo (icon.png) à esquerda, estilo Dream.
local function drawLogoHeader()
  local shown = false
  if ui.image then
    local root = appRoot()
    if root then
      local f = io.open(tostring(root) .. "/icon.png", "rb")
      if f then
        f:close()
        if rgbm then
          shown = pcall(function()
            ui.image(tostring(root) .. "/icon.png", vec2(46, 46), rgbm(1, 1, 1, 1))
          end)
        else
          shown = pcall(function()
            ui.image(tostring(root) .. "/icon.png", vec2(46, 46))
          end)
        end
      end
    end
  end
  if shown then ui.sameLine(0, 12) end
  titleText("APEXFLOW", C.accent())
  ui.sameLine(0, 10)
  ui.textDisabled("v" .. (SCRIPT_VERSION or "?"))
  ui.newLine(1)
  ui.textDisabled(" central de IA, estratégia e direção de prova ")
end

-- Tab-strip superior estilo Dream (pills + micro-label + badge).
local function drawTabStrip(cfg, badges)
  ui.textDisabled("SEÇÕES")
  local avail = contentWidth()
  local bw = math.max(120, (avail - 4 * 6) / 5)
  for i, cat in ipairs(NAV_RAIL) do
    if i > 1 then ui.sameLine(0, 6) end
    local active = cfg.uiNav == cat.id
    if active then
      local glow = animPulse(3, 0.45, 0.7)
      if rgbm then
        local at = ACCENTS[THEME.accent] or ACCENTS.cyan
        ui.pushStyleColor(ui.StyleColor.Button, rgbm(at[1]*glow*1.6, at[2]*glow*1.6, at[3]*glow*1.6, 1.00))
      end
    end
    local dot = (badges and badges[cat.id]) and " •" or ""
    if ui.button(cat.icon .. " " .. cat.label .. dot .. "##tab_" .. cat.id, vec2(bw, 34)) then
      if cfg.uiNav ~= cat.id then cfg.uiNav = cat.id trackNav(cfg, cat.id) end
    end
    hand()
    if active and rgbm then ui.popStyleColor() end
  end
  for _, cat in ipairs(NAV_RAIL) do
    if cfg.uiNav == cat.id then
      if rgbm then ui.textColored("━━━ " .. cat.label, C.accent())
      else ui.text(cat.label) end
      ui.sameLine(0, 8)
      ui.textDisabled(cat.desc)
      break
    end
  end
end

-- ---------------- trilho (legado) — limpo extremo v0.29.0: sem caution/track/realPenalty ----------------
local function railBadges(sim, cfg)
  local gs = APEXFLOW_API.githubGetState and APEXFLOW_API.githubGetState() or {}
  -- v0.29.0: HUD badge baseado em gaps/PP (5), não em caution/track
  local gb = APEXFLOW_API.getGapBehindState and APEXFLOW_API.getGapBehindState() or {}
  local ps = APEXFLOW_API.getPenaltySeverityState and APEXFLOW_API.getPenaltySeverityState() or {}
  return {
    dash = false,
    ai = (cfg.multiclassEnabled == true),
    race = (cfg.strategy and cfg.strategy.enabled == true),
    hud = ((gb.gapBehindM or 0) > 1 or (ps.totalPP or 0) > 0),
    sys = (gs.hasUpdate == true),
  }
end

-- (navegação lateral removida na v0.20.0: agora é tab-strip superior estilo Dream)

-- ---------------- barra de status — limpa v0.29.0: gaps/PP (caution/track removidos) ----------------
local function drawStatusBar(sim, cfg)
  local live = sim and sim.isSessionStarted
  local parts = {}
  parts[#parts + 1] = live and "● LIVE" or "○ box"
  -- gaps e PP (5) no lugar de warnings/caution
  local gb = APEXFLOW_API.getGapBehindState and APEXFLOW_API.getGapBehindState() or {}
  local ps = APEXFLOW_API.getPenaltySeverityState and APEXFLOW_API.getPenaltySeverityState() or {}
  if (gb.gapBehindM or 0) > 1 then
    parts[#parts + 1] = string.format("🔙 %.0fm", gb.gapBehindM or 0)
  end
  if (ps.totalPP or 0) > 0 then
    parts[#parts + 1] = string.format("⚖ PP:%d", ps.totalPP or 0)
  end
  parts[#parts + 1] = "💾 auto"
  parts[#parts + 1] = "v" .. (SCRIPT_VERSION or "?")
  local line = table.concat(parts, "   ")
  if live and rgbm then ui.textColored(line, C.ok()) else ui.textDisabled(line) end
end

-- ---------------- presets (faixa por preset) ----------------
local PRESET_ROWS = {
  { key = "gt3",       desc = "Corrida GT equilibrada — comece aqui" },
  { key = "gt4",       desc = "GT de base, mais permissivo" },
  { key = "tcr",       desc = "Turismo tração dianteira" },
  { key = "f1",        desc = "Fórmula: rigoroso, pune rápido" },
  { key = "lmp",       desc = "Protótipos velozes" },
  { key = "endurance", desc = "Provas longas, tolerante" },
}
local function drawPresetList(cfg)
  local presets = APEXFLOW_API.getCategoryPresets and APEXFLOW_API.getCategoryPresets() or {}
  if not next(presets) then return end
  if not matchesSearch(cfg, "preset gt3 f1 tcr categoria corrida") then return end
  ui.textDisabled("PRESET")
  local cur = cfg.categoryPreset or "custom"
  local first = true
  for _, row in ipairs(PRESET_ROWS) do
    local pr = presets[row.key]
    if pr then
      if not first then ui.sameLine(0, 6) end
      first = false
      local isCur = cur == row.key
      if isCur and rgbm then ui.pushStyleColor(ui.StyleColor.Button, rgbm(1.00, 0.55, 0.15, 1.00)) end
      if ui.button((isCur and "● " or "") .. row.key:upper() .. "##p_" .. row.key, vec2(92, 28)) then
        if APEXFLOW_API.applyCategoryPreset then APEXFLOW_API.applyCategoryPreset(row.key) end
        notifyChange()
        if ac.setMessage then pcall(ac.setMessage, "PRESET", pr.label .. " aplicado") end
        toast(cfg, "ok", "Preset", pr.label .. " aplicado")
        trackSection(cfg, "preset_" .. row.key)
      end
      hand()
      if isCur and rgbm then ui.popStyleColor() end
    end
  end
  ui.sameLine(0, 6)
  if ui.button("Custom##p_custom", vec2(92, 28)) then
    cfg.categoryPreset = "custom"
    notifyChange()
  end
  hand()
  for _, row in ipairs(PRESET_ROWS) do
    if cur == row.key then ui.textDisabled(row.desc) break end
  end
  if cur == "custom" then ui.textDisabled("Ajustes manuais (sem preset)") end
end

-- ---------------- inspetores ----------------
local function heroNumbers(sim, cfg)
  if not (sim and sim.isSessionStarted) then
    ui.textDisabled("Sem sessão — números vivos aparecem em pista " .. animDots())
    return
  end
  local ok, pcar = pcall(ac.getCar, 0)
  if not (ok and pcar) then return end
  local fuel = tonumber(pcar.fuel) or 0
  band("##hero_num", 0.08, 0.13, 0.22, 54, function()
    ui.pushFont(ui.Font.Title)
    local txt = string.format("P%d   ·   V%d   ·   %d km/h   ·   %.1fL",
      pcar.racePosition or 0, (pcar.lapCount or 0) + 1, math.floor(pcar.speedKmh or 0), fuel)
    if rgbm then ui.textColored(txt, rgbm(1, 1, 1, 1)) else ui.text(txt) end
    ui.popFont()
  end)
end

local function drawDashInspector(sim, cfg)
  -- Telemetria viva — limpa v0.29.0: só gaps/PP (caution/track removidos)
  heroNumbers(sim, cfg)
  ui.newLine(2)
  local _, _, stt, memCount = getSystemStatus(sim, cfg)
  -- Gaps e severidade (5) no lugar de warnings/caution
  local gb = APEXFLOW_API.getGapBehindState and APEXFLOW_API.getGapBehindState() or {}
  local sg = APEXFLOW_API.getSectorGapsState and APEXFLOW_API.getSectorGapsState() or {}
  local ps = APEXFLOW_API.getPenaltySeverityState and APEXFLOW_API.getPenaltySeverityState() or {}
  if (gb.gapBehindM or 0) > 1 then
    ui.textDisabled(string.format("🔙 Atrás: %.0fm (P%d)", gb.gapBehindM or 0, gb.carBehindPos or 0))
  else
    ui.textDisabled("🔙 sem carro atrás")
  end
  if (sg.gapSectorS or 0) > 0.05 then
    ui.textDisabled(string.format("⏱ Setor %d: +%.2fs p/ P1", sg.currentSector or 0, sg.gapSectorS or 0))
  end
  if (ps.totalPP or 0) > 0 then
    ui.textDisabled(string.format("⚖ PP: %d (L%d %s)", ps.totalPP or 0, ps.level or 0, tostring(ps.lastReason or "")))
  else
    ui.textDisabled("⚖ PP: limpo")
  end
  ui.textDisabled("🟢 pista verde — AC nativo")
  if sim and sim.isSessionStarted and stt and stt.cars then
    for _, c in ipairs(stt.cars) do
      if c.index == 0 then
        local pit = c.nextPit and ("pit v" .. tostring(c.nextPit)) or "sem pit"
        ui.textDisabled(string.format("⛽ %.1fL  ·  %s", tonumber(c.fuel) or 0, pit))
        break
      end
    end
    local sessName, trackName = "", ""
    if ac.getSessionName then
      local ok, n = pcall(ac.getSessionName, sim.currentSessionIndex)
      if ok and n then sessName = tostring(n) end
    end
    if ac.getTrackName then
      local ok, tn = pcall(ac.getTrackName)
      if ok and tn then trackName = tostring(tn) end
    end
    local info = sessName
    if trackName ~= "" then info = info .. "  ·  " .. trackName end
    if sim.sessionTimeLeft and sim.sessionTimeLeft > 0 then
      info = info .. string.format("  ·  %02d:%02d",
        math.floor(sim.sessionTimeLeft / 60000), math.floor((sim.sessionTimeLeft % 60000) / 1000))
    end
    if info ~= "" then ui.textDisabled(info) end
  end
  ui.textDisabled(string.format("🧠 %d pista(s)", memCount))
  ui.newLine(2)
  ui.separator()
  ui.newLine(2)
  drawPresetList(cfg)
end

local function drawAiInspector(sim, cfg)
  ui.textDisabled("Dê personalidade à IA. Padrões servem p/ quase tudo.")
  ui.newLine(4)
  if matchesSearch(cfg, "agressividade perfis calmo briga") then
    view(cfg, "ai_profiles", "01", "Quanto o grid briga",
      "0 = desfile calmo · 100 = todo mundo atacando. 50 é o meio-termo.",
      { status = tostring(cfg.aggression or 50) },
      function(s, c) drawAggressionSection(s, c) end, sim)
  end
  if matchesSearch(cfg, "ritmo pace dificuldade rapido devagar") then
    view(cfg, "ai_rhythm", "02", "Ritmo e dificuldade",
      "Deixa a IA mais rápida ou devagar no geral. 100% = jogo original.",
      {},
      function(s, c) drawRhythmSection(s, c) end, sim)
  end
  if matchesSearch(cfg, "ultrapassagem mergulho lado a lado fila") then
    view(cfg, "ai_racecraft", "03", "Ultrapassagens de verdade",
      "A IA tenta passar em vez de andar em fila.",
      {},
      function(s, c) drawRacecraftSection(s, c) end, sim)
  end
  if matchesSearch(cfg, "multiclasse categoria lmp gt classe") then
    view(cfg, "ai_multi", "04", "Várias categorias juntas",
      "Ex: protótipos + GT. Classe 1 = mais rápida.",
      {},
      function(s, c) drawMultiClassTab(s, c, aiController) end, sim)
  end
  if matchesSearch(cfg, "reta monza velocidade final downforce") then
    view(cfg, "ai_lowdf", "05", "Pistas de reta (Monza)",
      "Só mexa p/ pistas de alta velocidade.",
      {},
      function(s, c) drawLowDownforceAISection(s, c) end, sim)
  end
  -- v0.29.0: ai_fail removido (peso morto — sem UI)
  if matchesSearch(cfg, "aprende memoria curva erro") then
    view(cfg, "ai_learn", "07", "IA que aprende",
      "Lembra onde erra e melhora com o tempo.",
      {},
      function(s, c) drawLearningModuleSection(s, c) end, sim)
  end
end

local function drawRaceInspector(sim, cfg)
  ui.textDisabled("Antes de largar: duração, paradas e formação.")
  ui.newLine(4)
  if matchesSearch(cfg, "combustivel pit pneu volta endurance") then
    local st = "manual"
    if cfg.strategy and cfg.strategy.enabled then st = tostring(cfg.strategy.manualRaceLaps or 20) .. "v/" .. tostring(cfg.strategy.forcedStops or 1) .. " pits" end
    view(cfg, "race_fuel", "01", "Combustível e pits",
      "Diga as voltas; a IA calcula paradas e pneus sozinha.",
      { status = st },
      function(s, c) drawFuelStrategySection(s, c) end, sim)
  end
  if matchesSearch(cfg, "largada movimento fila formacao") then
    view(cfg, "race_rolling", "02", "Largada em movimento",
      "Volta de apresentação em fila antes da verde. Vem desligado.",
      { status = (cfg.rollingStart and cfg.rollingStart.enabled) and "armado" or "off" },
      function(s, c) drawRollingStartSection(s, c) end, sim)
  end
end

-- v0.29.0 limpo extremo: drawSafetyInspector removido (caution/tracklimits 3,4 removidos)
-- v0.29.0 limpo extremo: drawRealPenaltySection removido (realPenalty 6 removido — AC nativo assume)
-- stubs removidos para peso morto zero (mantido só comentário)

-- v0.29.0 limpo: Regulation/HUD — só gaps/PP (voice/telemetria removidos 3,4,6)
local function drawHudInspector(sim, cfg)
  ui.textDisabled("O que aparece correndo.")
  ui.newLine(4)
  if matchesSearch(cfg, "painel hud overlay mostrar tela") then
    view(cfg, "hud_events", "01", "Painel na tela",
      "Escolha o que o overlay mostra na corrida (gaps/PP).",
      {},
      function(s, c) drawHudEventsSettings(s, c) end, sim)
  end
  -- hud_tel removido (telemetria + voz peso morto — AC nativo)
end

local function drawSysInspector(sim, cfg)
  ui.textDisabled("Visual, updates e bastidores. Mexa uma vez e esqueça.")
  ui.newLine(4)
  if matchesSearch(cfg, "aparencia tema cor transparencia") then
    view(cfg, "sys_theme", "01", "Visual",
      "Cor de destaque e transparência.",
      {},
      function(s, c) drawAppearanceSection(s, c) end, sim)
  end
  if matchesSearch(cfg, "github update release versao baixar") then
    local gs = APEXFLOW_API.githubGetState and APEXFLOW_API.githubGetState() or {}
    view(cfg, "sys_gh", "02", "Atualizações",
      "Ver se saiu versão nova.",
      { status = gs.hasUpdate and "nova!" or "" },
      function(s, c) drawGitHubUpdateSection(s, c) end, sim)
  end
  if matchesSearch(cfg, "ajuda sobre como funciona") then
    view(cfg, "sys_about", "03", "Ajuda",
      "O que cada parte faz, em linguagem simples.",
      {},
      function(s, c) drawAboutSection(s, c) end, sim)
  end
end

-- ---------------- moldura principal ----------------
function M.draw(sim, cfg)
  cfg.ui = cfg.ui or {}
  local acc = cfg.ui.accent
  local accOk = false
  for _, k in ipairs(ACCENT_ORDER) do if k == acc then accOk = true break end end
  THEME.accent = accOk and acc or "orange"
  THEME.bgAlpha = clamp(tonumber(cfg.ui.bgAlpha) or 1.0, 0.4, 1.0)
  THEME.corner = math.floor(clamp(tonumber(cfg.ui.corner) or 8, 0, 12) + 0.5)
  THEME.compactHeaders = (cfg.ui.compactHeaders == true)
  pushDarkTheme()
  ensureUiState(cfg)
  if sim and sim.isSessionStarted then cfg._everInSession = true end

  drawLogoHeader()
  ui.newLine(4)
  drawStateBand(sim, cfg)
  ui.newLine(2)
  drawCommandBar(sim, cfg)
  ui.newLine(2)
  drawToasts(cfg)
  ui.separator()

  drawTabStrip(cfg, railBadges(sim, cfg))
  ui.newLine(2)
  ui.separator()
  ui.newLine(2)

  local nav = cfg.uiNav or "dash"
  -- v0.27.0: peso morto removido — safety inspector saiu do NAV_RAIL (5 itens), fica só em Regulation
  -- v0.27.5 fix 2662: legacy drawRealPenaltySection guard
  if false then
    -- legacy path disabled: drawRealPenaltySection(sim, cfg)
  end
  local flash = (animT() - (cfg._navFlash or -10)) < 0.8
  if nav == "dash" then
    safeTab("Início", drawDashInspector, sim, cfg)
  elseif nav == "ai" then
    if flash and rgbm then ui.textColored("🤖 Pilotos", C.accent()) end
    safeTab("Pilotos", drawAiInspector, sim, cfg)
  elseif nav == "race" then
    if flash and rgbm then ui.textColored("🏁 Corrida", C.accent()) end
    safeTab("Corrida", drawRaceInspector, sim, cfg)
  elseif nav == "hud" then
    if flash and rgbm then ui.textColored("📡 Tela & Voz", C.accent()) end
    safeTab("Tela & Voz", drawHudInspector, sim, cfg)
  elseif nav == "sys" then
    if flash and rgbm then ui.textColored("⚙️ Ajustes", C.accent()) end
    safeTab("Sistema", drawSysInspector, sim, cfg)
  else
    -- compat: old saves with "safety" nav -> redirect to Regulation window
    if nav == "safety" then
      cfg.uiNav = "dash"
      if ac.setWindowOpen then pcall(ac.setWindowOpen, "regulation", true) end
    end
    cfg.uiNav = cfg.uiNav or "dash"
    if cfg.uiNav == "dash" then safeTab("Início", drawDashInspector, sim, cfg)
    elseif cfg.uiNav == "ai" then safeTab("Pilotos", drawAiInspector, sim, cfg)
    elseif cfg.uiNav == "race" then safeTab("Corrida", drawRaceInspector, sim, cfg)
    elseif cfg.uiNav == "hud" then safeTab("Tela & Voz", drawHudInspector, sim, cfg)
    elseif cfg.uiNav == "sys" then safeTab("Sistema", drawSysInspector, sim, cfg)
    else cfg.uiNav = "dash"; safeTab("Início", drawDashInspector, sim, cfg) end
  end

  ui.newLine(4)
  ui.separator()
  ui.newLine(2)
  if ui.button("💾 Salvar", vec2(110, 26)) then
    if APEXFLOW_API.saveConfig then
      APEXFLOW_API.saveConfig()
      cfg._savedFeedback = 180
      toast(cfg, "ok", "Salvo", "")
    end
  end
  ui.sameLine(0, 8)
  if ui.button("🔄 Padrões", vec2(110, 26)) then
    cfg._confirmReset = true
  end
  hand()
  ui.sameLine(0, 8)
  if ui.button("📊 Painel", vec2(100, 26)) then
    if ac.setWindowOpen then pcall(ac.setWindowOpen, "events", true) end
  end
  if (cfg._savedFeedback or 0) > 0 then
    cfg._savedFeedback = cfg._savedFeedback - 1
    ui.sameLine(0, 8)
    if rgbm then ui.textColored("✓ " .. animDots(), rgbm(0.2, 0.9, 0.4, animPulse(4, 0.6, 1.0)))
    else ui.text("✓") end
  elseif (cfg._resetFeedback or 0) > 0 then
    cfg._resetFeedback = cfg._resetFeedback - 1
    ui.sameLine(0, 8)
    ui.textDisabled("✓ padrões")
  end

  -- Modal de confirmação estilo Dream (passo explícito, sem desfazer)
  if cfg._confirmReset then
    ui.newLine(4)
    ui.separator()
    ui.newLine(2)
    titleText("⚠️ Voltar aos padrões?", C.warn())
    ui.textDisabled("Apaga TODOS os ajustes (perfis, limites, voz, tema). Sem desfazer.")
    ui.newLine(2)
    if ui.button("Sim, restaurar##cf_yes", vec2(170, 30)) then
      if APEXFLOW_API.resetToDefaults then APEXFLOW_API.resetToDefaults() end
      cfg._confirmReset = false
      cfg._resetFeedback = 180
      toast(cfg, "warn", "Padrões de volta", "")
    end
    ui.sameLine(0, 8)
    if ui.button("Cancelar##cf_no", vec2(130, 30)) then cfg._confirmReset = false end
  end

  ui.newLine(2)
  ui.separator()
  drawStatusBar(sim, cfg)

  popDarkTheme()
end

return M
