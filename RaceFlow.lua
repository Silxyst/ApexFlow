-- ApexFlow — Independent race suite for Assetto Corsa (v0.29.3)
SCRIPT_NAME = "ApexFlow"
SCRIPT_VERSION = "0.29.3"

_G.RARE2_API = _G.RARE2_API or {}
local RARE2_API = _G.RARE2_API
_G.RACEFLOW_VERSION = "0.29.3"
_G.APEXFLOW_VERSION = "0.13.1"

local function clamp(v,a,b) if v<a then return a end if v>b then return b end return v end
local function lerp(a,b,t) return a + (b-a)*t end

-- Per-module load status, shown in the fallback window so a future
-- require() failure identifies the exact module (no more guessing).
local modStatus = {}
local function safeRequire(name)
  local ok, mod = pcall(require, name)
  if ok and mod then
    modStatus[name] = "OK"
    return mod
  end
  modStatus[name] = "FAIL: " .. tostring(mod)
  if ac and ac.log then ac.log(string.format("[RaceFlow] require('%s') failed: %s", tostring(name), tostring(mod))) end
  return nil
end

-- v0.28.1 extrema: só 1,2,5,7,8 (IA/Corrida/Gaps/Painel/Extras) — 3,4,6 removidos
local ui_root      = safeRequire("src.ui")
local ai           = safeRequire("src.ai_controller")
local rolling      = safeRequire("src.rolling_start")
local strategy     = safeRequire("src.race_strategy")
local webui        = safeRequire("src.webui")
local gap_behind   = safeRequire("src.gap_behind")
local sector_gaps  = safeRequire("src.sector_gaps")
local penalty_sev  = safeRequire("src.penalty_severity")
-- REMOVIDOS 3,4,6: caution/safety/realpenalty/tracklimits/voice/sound/box
-- NOTE v0.5.0+: src/vsc + src/github_update modules are DEPRECATED and no
-- longer required. GitHub check lives in this file (single source of truth)
-- to avoid dual-state bugs.

local RARE2_CFG = {
  enabled      = true,
  aggression   = 50,
  paceEnabled  = true,
  paceStrength = 65,
  difficultyBoost = 100,

  strategy = {
    enabled = true,
    manualRaceLaps = 20,
    forcedStops = 1,
    reserveLaps = 1.2,
    minRefuelLaps = 4.0,
    emergencyFuelLaps = 0.6,
    enforceWindowLaps = 1.0,
  },

  rollingStart = {
    enabled         = false,
    preset          = "Normal",
    limitSpeed      = 80,
    formationGap    = 4,
    maxOffset       = 0.4,
    releaseAtPct    = 50,
    singleFileMeters= 600,
  },

  -- v0.28.1 limpa extrema: REMOVIDOS 3,4,6 (caution/tracklimits/realpenalty/voice/sound) — AC nativo assume
  caution = { removed = true },
  tracklimits = { removed = true },
  realPenalty = { removed = true },
  voice = { removed = true },

  -- Extras mantidos (8)
  githubUpdate = {
    enabled = true,
    repo = "Silxyst/RaceFlow-V2",
    checkIntervalHours = 24,
    notifyOnStartup = true,
  },

  -- HUD limpo extremo v0.29.0: só 1,2,5,7 (sem caution/track/sound/box) — removers 3,4,6
  hudEvents = {
    showStrategy = true,
    showPosition = true,
    showSession = true,
    showLearning = false,
    showMessages = true,
    showExtras = true,
    hideInPits = true,
    compact = false,
    progressBars = true,
    blink = true,
    scale = 1.0,
    showDeltaLive = true,
    showGapBehind = true,
  },

  webui = {
    enabled = false,
    port = 8080,
    authToken = "",
  },

  packs = { pace = true, ers = true, traffic = true, hud = true },

  ui = {
    accent = "cyan",
    bgAlpha = 1.0,
    corner = 6,
    compactHeaders = false,
  },

  categoryPreset = "custom",

  pitSpeedReal = { enabled = true },
  telemetryCSV = { enabled = false, maxLaps = 500 },
  failures = { enabled = false, chancePerHour = 0.08, minLap = 3 },
}

-- Expose config globally for src/* modules (they run in same Lua state
-- but RARE2_CFG is local here). This fixes M.getState() returning nil config.
_G.RARE2_CFG = RARE2_CFG

-- ----------------------------------------------------------
-- Track State & FIA State — limpo extremo v0.29.0: AC nativo assume, mantém GREEN fixo
-- (caution/realpenalty removidos — sem ranger/yellow, só compat)
-- ----------------------------------------------------------
local Track_State = {
  state = "GREEN",
  lastChange = 0,
  yellowDistance = 80,
  flags = {},
}
_G.Track_State = Track_State
_G.RARE2_API.Track_State = Track_State
local FIA_State = {
  mode = "GREEN",
  reason = "",
  timer = 0,
  lastMode = "GREEN",
}
_G.FIA_State = FIA_State
local function updateTrackState(dt, sim, cfg)
  -- peso morto removido: sem caution/realpenalty, mantém GREEN
  if Track_State.state ~= "GREEN" then
    Track_State.state = "GREEN"
    FIA_State.mode = "GREEN"
    FIA_State.reason = ""
  end
  FIA_State.timer = (FIA_State.timer or 0) + dt
  Track_State.flags = { state = Track_State.state, reason = "" }
end
RARE2_API.getTrackState = function() return Track_State end
RARE2_API.getFIAState = function() return FIA_State end

-- ----------------------------------------------------------
-- Category presets (v0.14.0) — one click for GT3/F1/Endurance etc.
-- ----------------------------------------------------------
local CATEGORY_PRESETS = {
  gt3 = { label = "GT3" },
  gt4 = { label = "GT4" },
  tcr = { label = "TCR" },
  f1 = { label = "F1 / Open Wheel" },
  lmp = { label = "LMP / Hypercar" },
  endurance = { label = "Endurance" },
}
local function applyCategoryPreset(catKey)
  local p = CATEGORY_PRESETS[catKey]
  if not p then return false end
  RARE2_CFG.categoryPreset = catKey
  -- v0.29.0 limpo extremo: preset só marca categoria, sem tocar em 3,4,6 (removidos)
  if RARE2_API and RARE2_API.markConfigDirty then RARE2_API.markConfigDirty() end
  ac.log("[RaceFlow] Category preset applied: " .. tostring(p.label))
  if ac.setMessage then pcall(ac.setMessage, "PRESET", p.label .. " aplicado") end
  return true
end
_G.RARE2_API = _G.RARE2_API or {}
RARE2_API.applyCategoryPreset = applyCategoryPreset
RARE2_API.getCategoryPresets = function() return CATEGORY_PRESETS end

-- ----------------------------------------------------------
-- Pit speed — real track limit (v0.14.0)
-- ----------------------------------------------------------
local function getRealPitSpeedLimit(sim)
  -- Try CSP APIs first
  local apis = {
    function() return ac.getPitSpeedLimit and ac.getPitSpeedLimit() end,
    function() return ac.getTrackPitSpeed and ac.getTrackPitSpeed() end,
    function() return sim and sim.pitSpeedLimit end,
  }
  for _, fn in ipairs(apis) do
    local ok, v = pcall(fn)
    v = tonumber(v)
    if ok and v and v >= 20 and v <= 120 then return math.floor(v + 0.5) end
  end
  -- Fallback: try to read from track's data (if available via INI)
  -- Most tracks store it in data/surfaces.ini or ui/track.json, but we
  -- keep it simple: return nil to signal "use manual".
  return nil
end
_G.RARE2_API = _G.RARE2_API or {}
RARE2_API.getRealPitSpeedLimit = getRealPitSpeedLimit

-- ----------------------------------------------------------
-- Helpers de serialização (v0.24.0: declarados CEDO — o save/load
-- per-track os usa; forward-ref em Lua vira global nil e crasha).
-- ----------------------------------------------------------
local function serializeTable(tbl, indent)
  indent = indent or ""
  local nextIndent = indent .. "  "
  local parts = {}
  table.insert(parts, "{\n")

  for k, v in pairs(tbl) do
    local key
    if type(k) == "string" then
      key = string.format("%s[%q] = ", nextIndent, k)
    else
      key = string.format("%s[%d] = ", nextIndent, k)
    end

    local t = type(v)
    local valueStr
    if t == "number" or t == "boolean" then
      valueStr = tostring(v)
    elseif t == "string" then
      valueStr = string.format("%q", v)
    elseif t == "table" then
      valueStr = serializeTable(v, nextIndent)
    else
      valueStr = "nil"
    end

    table.insert(parts, key .. valueStr .. ",\n")
  end

  table.insert(parts, indent .. "}")
  return table.concat(parts)
end

local function deepMerge(dst, src)
  if type(dst) ~= "table" or type(src) ~= "table" then return dst end
  for k, v in pairs(src) do
    if type(v) == "table" and type(dst[k]) == "table" then
      deepMerge(dst[k], v)
    else
      dst[k] = v
    end
  end
  return dst
end

-- ----------------------------------------------------------
-- Auto-save per track (v0.14.0)
-- ----------------------------------------------------------
local lastTrackIdForAutosave = nil
local function getTrackIdForSave(sim)
  if ac.getTrackID then
    local ok, id = pcall(ac.getTrackID)
    if ok and id and id ~= "" then return tostring(id):gsub("[^%w_%-]", "_") end
  end
  if sim and sim.trackName then return tostring(sim.trackName):gsub("[^%w_%-]", "_") end
  return "unknown_track"
end
local function getPerTrackConfigPath(trackId)
  return string.format("RaceFlow_config_%s.lua", tostring(trackId))
end
local function savePerTrackConfig(trackId)
  trackId = trackId or getTrackIdForSave(ac.getSim())
  local path = getPerTrackConfigPath(trackId)
  local f = io.open(path, "w")
  if not f then return false end
  f:write("return ")
  f:write(serializeTable(RARE2_CFG, ""))
  f:write("\n")
  f:close()
  ac.log("[RaceFlow] Per-track config saved: " .. path)
  return true
end
local function loadPerTrackConfig(trackId)
  trackId = trackId or getTrackIdForSave(ac.getSim())
  local path = getPerTrackConfigPath(trackId)
  local chunk = loadfile(path)
  if not chunk then return false end
  local ok, data = pcall(chunk)
  if not ok or type(data) ~= "table" then return false end
  deepMerge(RARE2_CFG, data)
  ac.log("[RaceFlow] Per-track config loaded: " .. path)
  return true
end
_G.RARE2_API = _G.RARE2_API or {}
RARE2_API.savePerTrackConfig = savePerTrackConfig
RARE2_API.loadPerTrackConfig = loadPerTrackConfig

-- ----------------------------------------------------------
-- Telemetry CSV (v0.14.0) — lap-by-lap to Documents
-- ----------------------------------------------------------
local telemetryFile = nil
local lastTelemetryLap = -1
local function telemetryEnsureFile(sim)
  if telemetryFile then return telemetryFile end
  local trackId = getTrackIdForSave(sim)
  local fname = string.format("RaceFlow_telemetry_%s_%s.csv", trackId, os.date("%Y%m%d_%H%M%S"))
  local okD, docs = pcall(ac.getFolder, ac.FolderID.Documents)
  if not okD or not docs or docs=="" then ac.log("[RaceFlow] getFolder Documents failed"); return nil end
  docs = docs .. "/Assetto Corsa/"
  local path = docs .. fname
  local f = io.open(path, "w")
  if not f then return nil end
  f:write("lap,position,speedKmh,fuel,tyreWear,lapTimeMs,valid\n")
  telemetryFile = f
  ac.log("[RaceFlow] Telemetry CSV started: " .. path)
  return f
end
local function telemetryOnLap(sim)
  if not RARE2_CFG.telemetryCSV or not RARE2_CFG.telemetryCSV.enabled then return end
  local ok, pcar = pcall(ac.getCar, 0)
  if not ok or not pcar then return end
  local lap = tonumber(pcar.lapCount) or 0
  if lap == lastTelemetryLap then return end
  if lap < 1 then return end
  lastTelemetryLap = lap
  local f = telemetryEnsureFile(sim)
  if not f then return end
  local wear = 0
  if pcar.wheels and pcar.wheels[0] then wear = tonumber(pcar.wheels[0].tyreWear) or 0 end
  local line = string.format("%d,%d,%.1f,%.1f,%.3f,%d,%s\n",
    lap, tonumber(pcar.racePosition) or 0, tonumber(pcar.speedKmh) or 0,
    tonumber(pcar.fuel) or 0, wear, tonumber(pcar.lapTimeMs) or 0,
    pcar.isLapValid and "1" or "0")
  f:write(line)
  f:flush()
end
local function telemetryClose()
  if telemetryFile then pcall(function() telemetryFile:close() end) telemetryFile = nil end
end

-- ----------------------------------------------------------
-- Voice removido (3,4,6) — AC nativo assume; stubs de peso morto removidos v0.29.0
-- ----------------------------------------------------------
-- playVoiceWarning / voiceSay / voiceTest / voiceGetState / voiceEdge removidos
-- (mantidos apenas comentários; peso morto zero, sem acesso a RARE2_CFG.voice)

-- ----------------------------------------------------------
-- Light mechanical failures / driver errors for AI (v0.14.0)
-- ----------------------------------------------------------
local failureTimers = {}
local function maybeTriggerFailures(dt, sim, cfg)
  if not cfg.failures or not cfg.failures.enabled then return end
  if not sim.isSessionStarted or sim.isOnlineRace then return end
  local chPerHour = tonumber(cfg.failures.chancePerHour) or 0.08
  local minLap = tonumber(cfg.failures.minLap) or 3
  for i = 1, (sim.carsCount or 0) - 1 do
    local ok, car = pcall(ac.getCar, i)
    if ok and car and car.isAIControlled and not car.isInPitlane and not car.isInPit
       and (tonumber(car.lapCount) or 0) >= minLap then
      -- Per-car timer
      failureTimers[i] = (failureTimers[i] or 0) + dt
      -- Chance scaled to dt (per hour -> per second)
      local p = chPerHour / 3600 * dt
      if math.random() < p then
        -- 70% slow puncture / power loss, 30% extra pit for "repair"
        if math.random() < 0.7 then
          -- Slow for 15-30s: cut topspeed/throttle
          pcall(physics.setAITopSpeed, i, 60)
          pcall(physics.setAIThrottleLimit, i, 0.4)
          ac.log(string.format("[RaceFlow] AI #%d mechanical: slow (15s)", i))
          -- Schedule recovery via delayed reset (simple: rely on next AI update to restore)
        else
          if ac.requestPitStop then pcall(ac.requestPitStop, i) end
          ac.log(string.format("[RaceFlow] AI #%d mechanical: extra pit", i))
        end
        if ac.setMessage then pcall(ac.setMessage, "RACE CONTROL", string.format("AI #%d — mechanical issue", i)) end
      end
    end
  end
end

-- ----------------------------------------------------------
-- Learning / safety defaults (can be overridden by config/UI)
-- ----------------------------------------------------------
RARE2_CFG.learningEnabled = true
-- NOTE v0.5.0: disableLearningDuringVSC removed with the VSC system.

-- Hard-event detection
RARE2_CFG.offTrackConfirmSec   = 0.8
RARE2_CFG.overshootTurnX       = 35
RARE2_CFG.overshootMinSpeedKmh = 95
RARE2_CFG.overshootMarginKmh   = 25
RARE2_CFG.overshootMinSamples  = 8
RARE2_CFG.overshootMaxTurnX    = 80

-- Hard-event impact on learning
RARE2_CFG.hardEventDangerAdd       = 2.0
RARE2_CFG.hardEventImprovePenalty  = 4.0
RARE2_CFG.crashSpeedDropKmh        = 55
RARE2_CFG.dangerDecayPerClean  = 0.35
RARE2_CFG.dangerDecayPerSecond = 0.004

RARE2_CFG.dangerGateCleanStreak = 12

RARE2_CFG.dangerOvercapBonusPerEvent = 0.10
RARE2_CFG.dangerOvercapMaxCeiling   = 2.80

RARE2_CFG.dangerRampStartEvent = 4
RARE2_CFG.dangerRampPow        = 1.35
RARE2_CFG.dangerRampGain       = 0.18

RARE2_CFG.brakeBiasAddOnHardEvent   = 0.03
RARE2_CFG.brakeBiasDecayPerClean    = 0.015
RARE2_CFG.brakeBiasMax              = 0.15
RARE2_CFG.brakeBiasThrottleLoss     = 0.06

RARE2_CFG.cornerLockEnabled     = true
RARE2_CFG.cornerLockMinSamples  = 80
RARE2_CFG.cornerLockCleanStreak = 120

RARE2_CFG.entryCapHeadroomKmh           = 6
RARE2_CFG.entryCapLearnUpKmhPerClean    = 1.0
RARE2_CFG.entryCapMinKmh                = 60
RARE2_CFG.entryCapMaxKmh                = 9999

RARE2_CFG.entryCapDropKmhOnOvershoot    = 12
RARE2_CFG.entryCapDropKmhOnContact      = 18
RARE2_CFG.entryCapDropKmhOnSlide        = 22
RARE2_CFG.entryCapDropKmhOnOfftrack     = 28

RARE2_CFG.entryCapPreMarginKmh          = 16
RARE2_CFG.entryCapExcessWindowKmh       = 60
RARE2_CFG.entryCapEarlyKickKmh          = 10
RARE2_CFG.entryCapEarlyStartTurnX       = 85
RARE2_CFG.entryCapEarlyEndTurnX         = 20

RARE2_CFG.entryCapEscalateEvents            = 3
RARE2_CFG.entryCapEscalateDanger            = 18
RARE2_CFG.entryCapPreMarginBonusEscalated   = 10
RARE2_CFG.entryCapWindowTightenEscalated    = 15
RARE2_CFG.entryCapEscalatedStrengthMul      = 1.15

RARE2_CFG.entryCapBrakeGain             = 0.42
RARE2_CFG.entryCapTopSpeedLoss          = 0.22
RARE2_CFG.entryCapThrottleLoss          = 0.16

RARE2_CFG.dangerCap            = 20
RARE2_CFG.dangerOvercapSlope   = 0.15
RARE2_CFG.dangerOvercapMax     = 1.30
RARE2_CFG.dangerBrakeGain      = 0.10
RARE2_CFG.dangerTopSpeedLoss   = 0.08
RARE2_CFG.dangerThrottleLoss   = 0.07

RARE2_CFG.paceBaseChillOverride     = -0.07
RARE2_CFG.paceBaseAttackOverride    =  0.07
RARE2_CFG.jitterScale               = 0.80
RARE2_CFG.singleClassBackCatchup    = 0.008
RARE2_CFG.singleClassBackCurve      = 2.5
RARE2_CFG.earlySpreadFrac           = 0.55
RARE2_CFG.earlySpreadNormalBoost    = 0.085
RARE2_CFG.earlySpreadAttackBoost    = 0.120
RARE2_CFG.multiclassYieldStrength  = 85
RARE2_CFG.multiclassPushStrength   = 75
RARE2_CFG.multiclassYieldDistM     = 120
RARE2_CFG.multiclassPushDistM      = 80

-- v0.10.0: racecraft mais vivo por padrão (mais brigas e ultrapassagens).
RARE2_CFG.stuckBehindDelay           = 0.9
RARE2_CFG.stuckBehindRampTime        = 5.5
RARE2_CFG.draftCommitRampGate        = 0.20
RARE2_CFG.draftCommitTime            = 3.0
RARE2_CFG.stuckBehindAggressionBoost = 0.20
RARE2_CFG.stuckBehindPushBoost       = 0.030
RARE2_CFG.draftCommitAggBoost        = 0.26
RARE2_CFG.draftCommitPushBoost       = 0.045
RARE2_CFG.draftCommitTopSpeedBoost   = 0.030

RARE2_CFG.difficultyTopSpeedScale    = 0.10

RARE2_CFG.lap1SuppressBase = 1.0
RARE2_CFG.lap1RampFrac     = 0.0
RARE2_CFG.lap1PaceBoost    = 0.05

RARE2_CFG.cleanAirTopSpeedBoost    = 0.020
RARE2_CFG.cleanAirPushBoost        = 0.018
RARE2_CFG.huntPaceBoost            = 0.030
RARE2_CFG.huntDuration             = 50.0
RARE2_CFG.tigerChancePerLap        = 0.04

local MEMORY_FILE = "RaceFlow_memory.lua"

local RARE2_MEMORY = {
  tracks = {},
  drivers = {},
}

---------------------------------------------------------------------
-- RACE CONTROL MESSAGE MIRROR (for Events HUD)
-- Intercepts ac.setMessage so the overlay can replay every
-- "Largada em movimento" / "Race Control" / "Caution" banner.
---------------------------------------------------------------------
local raceMsgLog = {}
local MAX_MSG_LOG = 12
local origSetMessage = ac and ac.setMessage or nil
if origSetMessage then
  ac.setMessage = function(title, text)
    local ok, err = pcall(origSetMessage, title, text)
    -- Mirror to HUD log (guarded, never breaks the caller)
    pcall(function()
      table.insert(raceMsgLog, 1, {
        t = os.clock() or 0,
        title = tostring(title or ""),
        text = tostring(text or ""),
      })
      if #raceMsgLog > MAX_MSG_LOG then table.remove(raceMsgLog) end
    end)
    if not ok and ac and ac.log then
      ac.log("[RaceFlow] setMessage failed: " .. tostring(err))
    end
    return ok
  end
end
_G.RARE2_API = _G.RARE2_API or {}
RARE2_API.getRaceMessages = function() return raceMsgLog end

---------------------------------------------------------------------
-- CONFIG SAVE / LOAD
---------------------------------------------------------------------
local CONFIG_FILE = "RaceFlow_config.lua"
local LEGACY_CONFIG_FILE = "RARE_2_0_config.lua"

local function saveConfigToFile()
  local f, err = io.open(CONFIG_FILE, "w")
  if not f then
    ac.log(string.format("[RaceFlow] Failed to save config: %s", tostring(err)))
    return false
  end

  f:write("return ")
  f:write(serializeTable(RARE2_CFG, ""))
  f:write("\n")
  f:close()

  ac.log("[RaceFlow] Config saved to " .. CONFIG_FILE)
  return true
end

local function loadConfigFromFile()
  local chunk, err = loadfile(CONFIG_FILE)
  if not chunk then
    chunk, err = loadfile(LEGACY_CONFIG_FILE)
  end
  if not chunk then
    ac.log(string.format("[RaceFlow] No config file to load or error: %s", tostring(err)))
    return
  end
  local ok, data = pcall(chunk)
  if not ok or type(data) ~= "table" then
    ac.log("[RaceFlow] Failed to load config table: " .. tostring(data))
    return
  end
  deepMerge(RARE2_CFG, data)
  ac.log("[RaceFlow] Config loaded successfully")
end

local function saveMemoryToFile()
  local f, err = io.open(MEMORY_FILE, "w")
  if not f then
    ac.log(string.format("[RaceFlow] Failed to save memory: %s", tostring(err)))
    return
  end

  f:write("return ")
  f:write(serializeTable(RARE2_MEMORY, ""))
  f:write("\n")
  f:close()

  ac.log("[RaceFlow] Memory saved to " .. MEMORY_FILE)
end

local function loadMemoryFromFile()
  local chunk, err = loadfile(MEMORY_FILE)
  if not chunk then
    ac.log(string.format("[RaceFlow] Memory load skipped (%s)", tostring(err)))
    return
  end

  local ok, data = pcall(chunk)
  if not ok or type(data) ~= "table" then
    ac.log("[RaceFlow] Failed to load memory table from " .. MEMORY_FILE)
    return
  end

  for k in pairs(RARE2_MEMORY) do
    RARE2_MEMORY[k] = nil
  end
  for k, v in pairs(data) do
    RARE2_MEMORY[k] = v
  end

  ac.log("[RaceFlow] Memory loaded from " .. MEMORY_FILE)
end

_G.RARE2_API = _G.RARE2_API or {}
RARE2_API.saveConfig = saveConfigToFile
RARE2_API.loadConfig = loadConfigFromFile
RARE2_API.saveMemory = saveMemoryToFile
RARE2_API.loadMemory = loadMemoryFromFile
RARE2_API.getMemory  = function() return RARE2_MEMORY end
RARE2_API.markConfigDirty = function()
  if _G.RARE2_API then RARE2_API._configDirty = true end
end
RARE2_API.resetToDefaults = function()
    RARE2_CFG.aggression = 50
    RARE2_CFG.difficultyBoost = 100
    RARE2_CFG.paceStrength = 65
    -- v0.10.0: racecraft defaults (spicier racing).
    RARE2_CFG.stuckBehindDelay = 0.8
    RARE2_CFG.stuckBehindRampTime = 5.0
    RARE2_CFG.draftCommitRampGate = 0.15
    RARE2_CFG.draftCommitTime = 3.5
    RARE2_CFG.stuckBehindAggressionBoost = 0.26
    RARE2_CFG.stuckBehindPushBoost = 0.034
    RARE2_CFG.draftCommitAggBoost = 0.32
    RARE2_CFG.draftCommitPushBoost = 0.070
    RARE2_CFG.draftCommitTopSpeedBoost = 0.050
    RARE2_CFG.huntDuration = 50.0
    RARE2_CFG.tigerChancePerLap = 0.07
    if RARE2_CFG.strategy then
      RARE2_CFG.strategy.manualRaceLaps = 20
      RARE2_CFG.strategy.forcedStops = 1
      RARE2_CFG.strategy.tireChangeEnabled = true
      RARE2_CFG.strategy.tireFreshnessPct = 50
    end
    -- NOTE v0.5.0: vsc reset block removed with the VSC system.
    -- Old saved configs may still contain cfg.vsc; it is ignored.
    -- v0.29.0: caution/tracklimits removidos (3,4) — reset ignora peso morto
    if RARE2_CFG.hudEvents then
      local h = RARE2_CFG.hudEvents
      h.showStrategy = (h.showStrategy ~= false)
      h.showPosition = (h.showPosition ~= false)
      h.showSession = (h.showSession ~= false)
      h.showLearning = (h.showLearning == true)
      h.showExtras = (h.showExtras ~= false)
      h.hideInPits = (h.hideInPits ~= false)
      h.compact = (h.compact == true)
      h.progressBars = (h.progressBars ~= false)
      h.blink = (h.blink ~= false)
      h.scale = clamp(tonumber(h.scale) or 1.0, 0.7, 1.5)
      h.showDeltaLive = (h.showDeltaLive ~= false)
      h.showGapBehind = (h.showGapBehind ~= false)
    end
    if RARE2_CFG.githubUpdate then
      RARE2_CFG.githubUpdate.enabled = true
      RARE2_CFG.githubUpdate.repo = "Silxyst/RaceFlow-V2"
      RARE2_CFG.githubUpdate.checkIntervalHours = 24
      RARE2_CFG.githubUpdate.notifyOnStartup = true
    end
    if RARE2_CFG.webui then
      RARE2_CFG.webui.enabled = false
      RARE2_CFG.webui.port = 8080
      RARE2_CFG.webui.authToken = ""
    end
    if RARE2_CFG.ui then
      RARE2_CFG.ui.accent = "orange"
      RARE2_CFG.ui.bgAlpha = 1.0
      RARE2_CFG.ui.corner = 8
      RARE2_CFG.ui.compactHeaders = false
    end
    if RARE2_CFG.pitSpeedReal then RARE2_CFG.pitSpeedReal.enabled = true end
    if RARE2_CFG.telemetryCSV then RARE2_CFG.telemetryCSV.enabled = false end
    -- v0.29.0: voice/realPenalty/fia removidos (3,4,6) — não resetar peso morto
    if RARE2_CFG.failures then
      RARE2_CFG.failures.enabled = false
      RARE2_CFG.failures.chancePerHour = 0.08
      RARE2_CFG.failures.minLap = 3
    end
    RARE2_CFG.categoryPreset = "custom"
    saveConfigToFile()
    return true
  end

-- ==========================================================
-- GITHUB UPDATE CHECKER (async, uses ac.webRequest)
-- ==========================================================
local githubState = {
  lastCheck = 0,
  checkInterval = 0,
  latestVersion = nil,
  hasUpdate = false,
  changelog = "",
  checking = false,
  error = nil,
}

-- Cached availability probe: ac.webRequest does not exist in some CSP
-- builds (incl. 0.3.0-preview542). Without this guard the check logs
-- EVERY frame (~400+ lines/session). Probe once, stay silent afterwards.
local webReqMissingLogged = false
local function githubCheckUpdates(cfg, force)
  if not cfg.githubUpdate.enabled then return end
  if not ac.webRequest then
    if not webReqMissingLogged then
      webReqMissingLogged = true
      githubState.error = "ac.webRequest indisponível nesta build do CSP (auto-check desativado; use verificação manual se disponível)"
      ac.log("[RaceFlow GitHub] ac.webRequest not available in this CSP build; automatic checks disabled (logged once)")
    end
    return
  end

  local now = os.clock()
  local interval = (cfg.githubUpdate.checkIntervalHours or 24) * 3600
  if not force and githubState.lastCheck > 0 and (now - githubState.lastCheck) < interval then
    return
  end
  if githubState.checking then return end

  githubState.checking = true
  githubState.error = nil
  githubState.lastCheck = now

  local url = string.format("https://api.github.com/repos/%s/releases/latest", cfg.githubUpdate.repo or "Silxyst/RaceFlow-V2")
  ac.log("[RaceFlow GitHub] Checking for updates: " .. url)

  ac.webRequest({
    url = url,
    method = "GET",
    headers = { ["User-Agent"] = "RaceFlow-AC-App" },
    callback = function(err, response)
      githubState.checking = false
      if err then
        githubState.error = tostring(err)
        ac.log("[RaceFlow GitHub] Request failed: " .. githubState.error)
        return
      end
      if not response or response.status ~= 200 then
        githubState.error = "HTTP " .. tostring(response and response.status or "nil")
        ac.log("[RaceFlow GitHub] " .. githubState.error)
        return
      end

      local body = response.body or response.data
      local ok, data = pcall(function() return ac.decodeJson(body) end)
      if not ok or not data then
        githubState.error = "JSON parse failed"
        ac.log("[RaceFlow GitHub] " .. githubState.error)
        return
      end

      local tag = data.tag_name or data.name or ""
      local version = tag:gsub("^v", "")
      githubState.latestVersion = version
      githubState.changelog = data.body or "No changelog provided."

      -- Compare versions (simple semantic version compare)
      local function parseVer(v)
        local major, minor, patch = v:match("(%d+)%.(%d+)%.(%d+)")
        return tonumber(major or 0), tonumber(minor or 0), tonumber(patch or 0)
      end
      local cM, cm, cP = parseVer(SCRIPT_VERSION)
      local lM, lm, lP = parseVer(version)
      githubState.hasUpdate = (lM > cM) or (lM == cM and lm > cm) or (lM == cM and lm == cm and lP > cP)

      ac.log(string.format("[RaceFlow GitHub] Current: %s, Latest: %s, Update: %s",
        SCRIPT_VERSION, version, githubState.hasUpdate and "YES" or "NO"))
    end
  })
end

-- ==========================================================
-- MAIN UPDATE (GitHub + WebUI + rolling + strategy + AI)
-- NOTE: Pure VSC system removed in v0.5.0 (see CHANGELOG).
-- ==========================================================
local configLoaded = false
local memoryLoaded = false
local githubStartupChecked = false

local memorySaveCooldown = 0.0
local memorySaveInterval = 12.0
local configSaveCooldown = 0.0
local configSaveInterval = 1.0

function script.update(dt)
  local sim = ac.getSim()
  if not sim then return end

  if not configLoaded then
    loadConfigFromFile()
    configLoaded = true
  end

  if not memoryLoaded and _G.RARE2_API and RARE2_API.loadMemory then
    RARE2_API.loadMemory()
    memoryLoaded = true
  end

  -- GitHub update check on startup + periodic (self-throttled inside)
  if RARE2_CFG.githubUpdate and RARE2_CFG.githubUpdate.enabled then
    if not githubStartupChecked and RARE2_CFG.githubUpdate.notifyOnStartup then
      githubStartupChecked = true
      githubCheckUpdates(RARE2_CFG, true) -- force check on startup
    else
      githubCheckUpdates(RARE2_CFG, false) -- interval check
    end
  end

  if sim.isOnlineRace then return end
  if not sim.isSessionStarted then return end
  if not RARE2_CFG.enabled then return end

  -- NOTE v0.5.0: VSC system removed (was here).

  -- Web UI (remote file-based polling)
  if webui and webui.update then
    webui.update(dt, sim, RARE2_CFG)
  end

  -- Rolling Start
  local rollingActive = false
  if rolling and rolling.update then
    rollingActive = (rolling.update(dt, sim, RARE2_CFG) == true)
  end

  if not rollingActive then
    if strategy and strategy.update then
      strategy.update(dt, sim, RARE2_CFG)
    end
  end

  if ai and ai.update then
    local okA, errA = pcall(ai.update, dt, sim, RARE2_CFG)
    if not okA then ac.log("[RaceFlow] ai.update: " .. tostring(errA)) end
  end

  -- v0.29.2: Force AI to overtake QUALQUER carro parado (player ou IA batida) — desvio rápido, sem fila
  do
    local L = tonumber(sim.trackLengthM) or 0
    if L > 0 then
      local blockers = {}
      for j = 0, (sim.carsCount or 0) - 1 do
        local okB, bcar = pcall(ac.getCar, j)
        if okB and bcar and not bcar.isInPitlane and not bcar.isInPit then
          local bSpd = tonumber(bcar.speedKmh) or 99
          local bOff = (tonumber(bcar.wheelsOutside) or 0) >= 2 or bcar.isLapValid == false
          local isBlocking = (bSpd < 3) or (bSpd < 8 and bOff) or (bcar.isRetired == true)
          if isBlocking and bcar.splinePosition then
            blockers[#blockers+1] = { idx=j, pos=bcar.splinePosition, isPlayer=(j==0) }
          end
        end
      end
      if #blockers > 0 then
        for i = 1, (sim.carsCount or 0) - 1 do
          local ok2, car = pcall(ac.getCar, i)
          if ok2 and car and car.isAIControlled and not car.isInPitlane and not car.isInPit then
            local aPos = car.splinePosition
            if aPos ~= nil then
              for _, b in ipairs(blockers) do
                if b.idx ~= i then
                  local gapFwd = (tonumber(b.pos) - tonumber(aPos)) % 1
                  if gapFwd > 0.0015 and gapFwd < 0.045 then -- 6m a 180m atrás do batido
                    pcall(physics.setAITopSpeed, i, 320)
                    pcall(physics.setAIThrottleLimit, i, 1.0)
                    if physics.setAIAggression then pcall(physics.setAIAggression, i, 1.0) end
                    if physics.setAISplineOffset then
                      -- desvio lateral para não enroscar no batido
                      local side = (i % 2 == 0) and 0.9 or -0.9
                      pcall(physics.setAISplineOffset, i, side, false)
                    end
                    break
                  end
                end
              end
            end
          end
        end
      end
    end
  end

  -- v0.29.0 limpa extrema: gaps/penalties mantidos (5) — 3,4,6 removidos (sem peso morto)
  if not rollingActive and gap_behind and gap_behind.update then
    pcall(gap_behind.update, dt, sim, RARE2_CFG)
  end
  if sector_gaps and sector_gaps.update then
    pcall(sector_gaps.update, dt, sim, RARE2_CFG)
  end
  if penalty_sev and penalty_sev.update then
    pcall(penalty_sev.update, dt, sim, RARE2_CFG)
  end
  -- FIA / Track_State — mantiene GREEN (peso morto removido, sem caution/realpenalty)
  pcall(updateTrackState, dt, sim, RARE2_CFG)

  -- Auto-save per track (v0.14.0)
  do
    local curId = getTrackIdForSave(sim)
    if lastTrackIdForAutosave == nil then
      lastTrackIdForAutosave = curId
      -- On first load after track change, try to load per-track config
      loadPerTrackConfig(curId)
    elseif curId ~= lastTrackIdForAutosave then
      savePerTrackConfig(lastTrackIdForAutosave)
      loadPerTrackConfig(curId)
      lastTrackIdForAutosave = curId
    end
  end

  -- Telemetry CSV (v0.14.0)
  if RARE2_CFG.telemetryCSV and RARE2_CFG.telemetryCSV.enabled then
    pcall(telemetryOnLap, sim)
  end

  -- Light failures for AI (v0.14.0)
  if RARE2_CFG.failures and RARE2_CFG.failures.enabled then
    pcall(maybeTriggerFailures, dt, sim, RARE2_CFG)
  end

  memorySaveCooldown = math.max(0.0, memorySaveCooldown - dt)
  if _G.RARE2_API and RARE2_API._memoryDirty and memorySaveCooldown <= 0.0 then
    if RARE2_API.saveMemory then
      pcall(RARE2_API.saveMemory)
    end
    RARE2_API._memoryDirty = false
    memorySaveCooldown = memorySaveInterval
  end

  configSaveCooldown = math.max(0.0, configSaveCooldown - dt)
  if _G.RARE2_API and RARE2_API._configDirty and configSaveCooldown <= 0.0 then
    if RARE2_API.saveConfig then
      pcall(RARE2_API.saveConfig)
    end
    RARE2_API._configDirty = false
    configSaveCooldown = configSaveInterval
  end
end

-- ==========================================================
-- EXPORTS for UI / other modules — limpo extremo v0.29.0: só 1,2,5,7,8
-- NOTE v0.5.0: VSC removido. v0.29.0: caution/tracklimits/voice/box/safety/realpenalty removidos (3,4,6)
-- ==========================================================
-- caution/tracklimits/voice/box/safety/realpenalty exports removidos (peso morto)
RARE2_API.getStrategyState = function(cfg) return strategy and strategy.getState and strategy.getState(cfg or RARE2_CFG) or {} end
-- v0.25.0: conformidade — gaps e penalidades mantidos (5)
RARE2_API.getGapBehindState = function() return gap_behind and gap_behind.getState and gap_behind.getState() or {} end
RARE2_API.getSectorGapsState = function() return sector_gaps and sector_gaps.getState and sector_gaps.getState() or {} end
RARE2_API.getPenaltySeverityState = function() return penalty_sev and penalty_sev.getState and penalty_sev.getState() or {} end
RARE2_API.reportPenaltySeverity = function(level, reason) if penalty_sev and penalty_sev.report then return penalty_sev.report(level, reason) end end
-- RealPenalty/sound/box/safety/voice/caution removidos — AC nativo assume
RARE2_API.githubCheckUpdates = function(cfg, force)
  githubCheckUpdates(cfg or RARE2_CFG, force)
end
RARE2_API.githubGetState = function()
  return {
    checking = githubState.checking,
    lastCheck = githubState.lastCheck,
    latestVersion = githubState.latestVersion,
    currentVersion = SCRIPT_VERSION,
    hasUpdate = githubState.hasUpdate,
    changelog = githubState.changelog,
    error = githubState.error,
    tagName = githubState.tagName,
    publishedAt = githubState.publishedAt,
    htmlUrl = githubState.htmlUrl,
    repo = RARE2_CFG.githubUpdate and RARE2_CFG.githubUpdate.repo or "Silxyst/RaceFlow-V2",
  }
end
RARE2_API.webuiGetState = function() return webui and webui.getState and webui.getState() or {} end

-- ==========================================================
-- WINDOWS
-- ==========================================================
local function drawFallbackIfMissingModules()
  ui.pushFont(ui.Font.Title)
  ui.textAligned("RaceFlow", vec2(0.5, 0.5), vec2(ui.availableSpaceX(), 34))
  ui.popFont()
  ui.newLine(4)
  ui.textWrapped("RaceFlow modules failed to load. Check custom_shaders_patch.log for require() errors.")
  ui.newLine(4)
  ui.separator()
  ui.text("Module status: (v0.28.1 extrema 1,2,5,7,8)")
  local names = {"src.ui", "src.ai_controller", "src.rolling_start", "src.race_strategy", "src.webui", "src.gap_behind", "src.sector_gaps", "src.penalty_severity"}
  for _, n in ipairs(names) do
    ui.text((modStatus[n] == "OK" and "✓ " or "✗ ") .. n .. ": " .. tostring(modStatus[n] or "not attempted"))
  end
end

function script.windowMain()
  local ok, sim = pcall(ac.getSim)
  if not ok or not sim then sim = nil end
  if ui_root and ui_root.draw then
    ui_root.draw(sim, RARE2_CFG)
  else
    drawFallbackIfMissingModules()
  end
end

function script.windowSetup()
  local ok, sim = pcall(ac.getSim)
  if not ok or not sim then sim = nil end
  if ui_root and ui_root.draw then
    ui_root.draw(sim, RARE2_CFG)
  else
    ui.pushFont(ui.Font.Title)
    ui.textAligned("RaceFlow", vec2(0.5, 0.5), vec2(ui.availableSpaceX(), 34))
    ui.popFont()
    drawFallbackIfMissingModules()
  end
end

function script.windowMainSettings()
  if ui.checkbox("Show window in setup", ac.isWindowOpen("main_setup")) then
    ac.setWindowOpen("main_setup", not ac.isWindowOpen("main_setup"))
  end
end

---------------------------------------------------------------------
-- EXTRA HUD: live race events (caution + track limits) - v0.7.0
-- Small overlay window; every read is guarded so it never crashes.
---------------------------------------------------------------------
-- v0.12.0: Full-featured, customizable Race Events HUD.
-- Each section honors RARE2_CFG.hudEvents toggles; visuals degrade gracefully.
local function hudPulse(speed, lo, hi)
  local t = (os.clock() or 0) * (speed or 4)
  local s = (math.sin(t) + 1) / 2
  return lo + (hi - lo) * s
end

local function hudBar(frac, hudCfg)
  if hudCfg and hudCfg.progressBars == false then return end
  frac = math.max(0, math.min(1, tonumber(frac) or 0))
  if ui.progressBar then
    pcall(ui.progressBar, frac, vec2(-1, 10))
  else
    local n = math.floor(frac * 20 + 0.5)
    ui.textDisabled("[" .. string.rep("█", n) .. string.rep("░", 20 - n) .. "]")
  end
end

local function hudBlinkText(text, color, hudCfg, forceStatic)
  local doBlink = hudCfg and hudCfg.blink ~= false and not forceStatic
  if doBlink and math.floor((os.clock() or 0) * 2.5) % 2 == 1 then
    ui.textDisabled(text)
  else
    if color then ui.textColored(text, color) else ui.text(text) end
  end
end

-- v0.24.0 Sug4/Sug5: file-locals do HUD (auto-hide no box + preview fake)
local pitHideSince = nil
local hudPreviewUntil = 0
RARE2_API.hudPreviewStart = function(secs)
  hudPreviewUntil = (os.clock() or 0) + (tonumber(secs) or 10)
  return true
end

-- Barra fina de combustível do herói (usa hudBar p/ respeitar o toggle de barras)
local function animBarPlaceholder(fuel, maxF)
  hudBar(maxF > 0 and (fuel / maxF) or 0, (RARE2_CFG and RARE2_CFG.hudEvents) or {})
end

local function drawRaceEventsBody()
  -- v0.24.0: par-a-par com o app — faixa + herói + pips + IA + jogo +
  -- estratégia estendida + preset/voz/update + ⚙ p/ abrir o app.
  local sim = ac.getSim()
  local inSession = sim and sim.isSessionStarted
  local hudCfg = (RARE2_CFG and RARE2_CFG.hudEvents) or {}
  local showStrategy= hudCfg.showStrategy ~= false
  local showPos     = hudCfg.showPosition ~= false
  local showSess    = hudCfg.showSession ~= false
  local showLearn   = hudCfg.showLearning == true
  local showExtras  = hudCfg.showExtras ~= false
  local compact     = hudCfg.compact == true
  local green = rgbm and rgbm(0.25, 0.95, 0.45, 1.0) or nil
  local cyan  = rgbm and rgbm(0.22, 0.88, 1.00, 1.0) or nil

  local api = _G.RARE2_API or {}
  local st = (showStrategy and api.getStrategyState and api.getStrategyState(RARE2_CFG)) or {}
  local gs = (showExtras and api.githubGetState and api.githubGetState()) or {}

  -- Sug4: box parado +10s => HUD dorme (1 linha explicando, sem poluir)
  local previewOn = (os.clock() or 0) < hudPreviewUntil
  if hudCfg.hideInPits ~= false and inSession and not previewOn then
    local okP, pcar0 = pcall(ac.getCar, 0)
    if okP and pcar0 and (pcar0.isInPitlane or pcar0.isInPit)
        and (tonumber(pcar0.speedKmh) or 99) < 5 then
      if not pitHideSince then pitHideSince = os.clock() end
      if (os.clock() or 0) - (pitHideSince or 0) > 10 then
        ui.textDisabled("🅿 no box — HUD pausado (volte à pista p/ reativar)")
        return
      end
    else
      pitHideSince = nil
    end
  else
    pitHideSince = nil
  end

  -- v0.29.0 limpo: sem caution/tracklimits/voice preview — só gaps/PP (AC nativo assume)
  -- ===== 1. FAIXA DE BANDEIRA (sempre verde — AC nativo) =====
  if green then ui.textColored("🟢  PISTA VERDE", green) else ui.text("PISTA VERDE") end
  if not compact then ui.separator() end

  -- ===== 2. HERÓI: posição / volta / velocidade / marcha / pneus =====
  if showPos and (inSession or previewOn) then
    local ok, pcar = pcall(ac.getCar, 0)
    if ok and pcar then
      local pos = pcar.racePosition or 0
      local lap = pcar.lapCount or 0
      local spd = math.floor(pcar.speedKmh or 0)
      local gear = pcar.gear or 0
      -- Sug3: identidade por categoria (GT3 laranja, F1 vermelho…)
      local heroCol = nil
      if showExtras and rgbm then
        local pk = (_G.RARE2_CFG and _G.RARE2_CFG.categoryPreset) or "custom"
        local pm = { gt3 = {1.0,0.55,0.15}, gt4 = {0.25,0.95,0.45}, tcr = {0.22,0.88,1.0},
                     f1 = {1.0,0.35,0.35}, lmp = {0.70,0.50,1.0}, endurance = {0.20,0.90,0.80} }
        local cc = pm[pk]
        if cc then heroCol = rgbm(cc[1], cc[2], cc[3], 1.0) end
      end
      ui.pushFont(ui.Font.Title)
      local heroTxt = string.format("P%d   ·   V%d   ·   %d km/h   ·   M%d", pos, lap + 1, spd, gear)
      if heroCol then ui.textColored(heroTxt, heroCol) else ui.text(heroTxt) end
      ui.popFont()
      if not compact then
        local fuel = pcar.fuel or 0
        local maxF = pcar.maxFuel or 100
        local pct = maxF > 0 and (fuel / maxF * 100) or 0
        animBarPlaceholder(fuel, maxF)
        ui.textDisabled(string.format("⛽ %.1f L (%d%%)", fuel, math.floor(pct)))
        -- Desgaste dos 4 pneus (leitura guardada, 0 = sem dado)
        local okW, wear = pcall(function()
          local w = pcar.wheels
          if not w then return nil end
          local out = {}
          for i = 0, 3 do
            local tw = w[i] and tonumber(w[i].tyreWear) or 0
            out[#out + 1] = math.floor(math.max(0, 1 - tw) * 100 + 0.5)
          end
          return out
        end)
        if okW and wear then
          ui.textDisabled(string.format("🛞 %d%% %d%% · %d%% %d%%", wear[1], wear[2], wear[3], wear[4]))
        end
        -- Sug2: gap p/ o P1 via splines (1 linha que muda a pilotagem)
        do
          local mySp = tonumber(pcar.splinePosition)
          local myLap = tonumber(pcar.lapCount) or 0
          local myPos = tonumber(pcar.racePosition) or 0
          if myPos == 1 then
            ui.textDisabled("📏 VOCÊ LIDERA")
          elseif mySp and sim and sim.carsCount then
            local lead = nil
            for i = 0, sim.carsCount - 1 do
              local okc, c = pcall(ac.getCar, i)
              if okc and c and tonumber(c.racePosition) == 1 then lead = c break end
            end
            if lead and lead.splinePosition then
              local frac = ((tonumber(lead.splinePosition) or 0) - mySp) % 1
              local lapD = (tonumber(lead.lapCount) or 0) - myLap
              if lapD > 0 then
                ui.textDisabled(string.format("📏 P1 +%d volta(s)", lapD))
              elseif frac <= 0.5 then
                local tlen = tonumber(sim.trackLengthM) or 0
                if tlen > 0 then
                  local m = math.floor(frac * tlen + 0.5)
                  if m > 1 then ui.textDisabled(string.format("📏 +%dm p/ P1", m)) end
                end
              end
            end
          end
        end
      end
    end
  elseif not inSession then
    ui.textDisabled("Sem sessão — o placar acende em pista " .. (hudCfg.blink ~= false and (" " .. (math.floor((os.clock() or 0) * 2) % 2 == 0 and "●" or "○")) or ""))
  end
  if not compact then ui.separator() end

  -- v0.29.0 limpo: 3. LIMITS e 4. CAUTION removidos (3,4,6) — AC nativo assume

  -- ===== 5. ESTRATÉGIA estendida (pit + faltam + total) =====
  if showStrategy and inSession then
    local nextPit, stopsLeft, myLap, perLap, fuelNow = nil, nil, 0, nil, nil
    if st and st.cars then
      for _, c in ipairs(st.cars) do
        if c.index == 0 then
          nextPit = c.nextPit
          stopsLeft = c.stopsLeft
          myLap = c.lap or 0
          perLap = tonumber(c.fuelPerLap) or nil
          fuelNow = tonumber(c.fuel)
          break
        end
      end
    end
    -- Sug1: autonomia real medida (não só "volta X")
    if perLap and perLap > 0 and fuelNow and fuelNow > 0 then
      local lapsLeft = math.floor(fuelNow / perLap)
      if lapsLeft <= 0 then ui.textDisabled("⛽ box AGORA (tanque no fim)")
      else ui.textDisabled(string.format("⛽ box em ~%dv (%.1f L/volta)", lapsLeft, perLap)) end
    end
    local totalTxt = ""
    if st.autoLaps then totalTxt = string.format("de %dv (auto)", st.autoLaps)
    elseif st.totalLaps then totalTxt = string.format("de %dv", st.totalLaps) end
    if nextPit then
      ui.textDisabled(string.format("⛽ Pit: volta %d%s%s", nextPit,
        totalTxt ~= "" and (" " .. totalTxt) or "",
        (stopsLeft and stopsLeft > 0) and string.format(" · faltam %d", stopsLeft) or ""))
    else
      ui.textDisabled("⛽ Sem pit agendado" .. (totalTxt ~= "" and (" · " .. totalTxt) or ""))
    end
    if not compact and myLap > 0 then
      ui.textDisabled(string.format("🏁 Você na volta %d", myLap + 1))
    end
    if not compact then ui.separator() end
  end

  -- ===== 6. CONFORMIDADE v0.29.0 — gaps e severidade mantidos (5), box/safety removidos (3,4,6) =====
  if hudCfg.showGapBehind ~= false and inSession and not compact then
    local gb = (api.getGapBehindState and api.getGapBehindState()) or {}
    local sg = (api.getSectorGapsState and api.getSectorGapsState()) or {}
    local ps = (api.getPenaltySeverityState and api.getPenaltySeverityState()) or {}
    local any = false
    if (gb.gapBehindM or 0) > 1 then
      ui.textDisabled(string.format("🔙 Atrás: %.0fm (P%d)", gb.gapBehindM or 0, gb.carBehindPos or 0))
      any = true
    end
    if (sg.gapSectorS or 0) > 0.05 then
      ui.textDisabled(string.format("⏱ Setor %d: +%.2fs p/ P1", sg.currentSector or 0, sg.gapSectorS or 0))
      any = true
    end
    if (ps.totalPP or 0) > 0 then
      ui.textDisabled(string.format("⚖ PP: %d (L%d %s)", ps.totalPP or 0, ps.level or 0, tostring(ps.lastReason or "")))
      any = true
    end
    if any then ui.separator() end
  end

  -- ===== 7. SESSÃO =====
  if showSess and not compact then
    local track = ""
    if ac.getTrackName then
      local ok, tn = pcall(ac.getTrackName)
      if ok and tn then track = tostring(tn) end
    end
    local sessName = ""
    if sim and ac.getSessionName then
      local ok, n = pcall(ac.getSessionName, sim.currentSessionIndex)
      if ok and n then sessName = tostring(n) end
    end
    local line = sessName
    if track ~= "" then line = line .. (line ~= "" and " • " or "") .. track end
    if sim and tonumber(sim.carsCount) and sim.carsCount > 0 then
      line = line .. (line ~= "" and " • " or "") .. string.format("%d carros", sim.carsCount)
    end
    if line ~= "" then ui.textDisabled(line) end
    if sim and sim.sessionTimeLeft and sim.sessionTimeLeft > 0 then
      local mins = math.floor(sim.sessionTimeLeft / 60000)
      local secs = math.floor((sim.sessionTimeLeft % 60000) / 1000)
      ui.textDisabled(string.format("⏱ %02d:%02d", mins, secs))
    end
    ui.separator()
  end

  -- ===== 7. EXTRAS: preset · update (voz removida 3,4,6) =====
  if showExtras and not compact then
    local bits = {}
    -- Preset atual (mesmo nome da lista do app)
    local presetKey = (_G.RARE2_CFG and _G.RARE2_CFG.categoryPreset) or "custom"
    if presetKey ~= "custom" then
      local label = presetKey:upper()
      if api.getCategoryPresets then
        local ok, presets = pcall(api.getCategoryPresets)
        if ok and presets and presets[presetKey] and presets[presetKey].label then
          label = tostring(presets[presetKey].label)
        end
      end
      bits[#bits + 1] = "🏁 " .. label
    end
    if gs.hasUpdate then
      bits[#bits + 1] = "☁ update v" .. tostring(gs.latestVersion or "?")
    end
    if #bits > 0 then
      ui.textDisabled(table.concat(bits, "   ·   "))
      ui.separator()
    end
  end

  -- ===== 8. RACE CONTROL (2 últimas) =====
  if hudCfg.showMessages ~= false then
    local msgs = api.getRaceMessages and api.getRaceMessages() or {}
    local shown = 0
    for i = 1, #msgs do
      if shown >= 2 then break end
      local m = msgs[i]
      local age = (os.clock() or 0) - (m.t or 0)
      if age < 12 then
        shown = shown + 1
        local line = (m.title ~= "" and m.title .. ": " or "") .. tostring(m.text)
        if #line > 44 then line = line:sub(1, 41) .. "..." end
        if i == 1 and age < 4 then hudBlinkText("▶ " .. line, cyan, hudCfg)
        else ui.text(line) end
      end
    end
  end

  -- ===== 9. LEARNING (opt-in) =====
  if showLearn then
    local mem = api.getMemory and api.getMemory() or nil
    if mem and mem.tracks then
      local cnt = 0
      for _ in pairs(mem.tracks) do cnt = cnt + 1 end
      ui.textDisabled(string.format("📚 %d pista(s)", cnt))
    else
      ui.textDisabled("📚 sem dados")
    end
  end

  -- ===== Rodapé: versão + LIVE + atalho p/ o app =====
  if not compact then
    local v = _G.RACEFLOW_VERSION or SCRIPT_VERSION or "?"
    ui.textDisabled("ApexFlow v" .. tostring(v) .. (previewOn and " • 👁 PREVIEW" or "") .. (inSession and " • LIVE" or ""))
    ui.sameLine(0, 8)
    if ui.button("⚙ App##hud_open_app", vec2(70, 22)) then
      if ac.setWindowOpen then pcall(ac.setWindowOpen, "main", true) end
    end
  end
end

function script.windowRaceEvents()
  -- push/pop always paired; only the data body is protected.
  ui.pushFont(ui.Font.Title)
  ui.text("RACE EVENTS")
  ui.popFont()
  local ok = pcall(drawRaceEventsBody)
  if not ok then
    ui.textDisabled("Events HUD unavailable.")
  end
end