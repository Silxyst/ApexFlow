-- ApexFlow — Independent race suite for Assetto Corsa (v0.32.9)
SCRIPT_NAME = "ApexFlow"
SCRIPT_VERSION = "0.32.9"

_G.APEXFLOW_API = _G.APEXFLOW_API or {}
local APEXFLOW_API = _G.APEXFLOW_API
_G.APEXFLOW_VERSION = "0.32.9"

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
  if ac and ac.log then ac.log(string.format("[ApexFlow] require('%s') failed: %s", tostring(name), tostring(mod))) end
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

local APEXFLOW_CFG = {
  enabled      = true,
  aggression   = 65,
  paceEnabled  = true,
  paceStrength = 78,
  difficultyBoost = 104,
  physicsPush  = { intensity = 70 },

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
    repo = "Silxyst/ApexFlow",
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
-- but APEXFLOW_CFG is local here). This fixes M.getState() returning nil config.
_G.APEXFLOW_CFG = APEXFLOW_CFG

-- v0.32.1: Track/FIA removidos (AC nativo assume) — stubs estáticos p/ compat externa, sem _G, sem alloc/frame
APEXFLOW_API.getTrackState = function() return { state = "GREEN" } end
APEXFLOW_API.getFIAState = function() return { mode = "GREEN", reason = "" } end

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
  APEXFLOW_CFG.categoryPreset = catKey
  -- v0.29.0 limpo extremo: preset só marca categoria, sem tocar em 3,4,6 (removidos)
  if APEXFLOW_API and APEXFLOW_API.markConfigDirty then APEXFLOW_API.markConfigDirty() end
  ac.log("[ApexFlow] Category preset applied: " .. tostring(p.label))
  if ac.setMessage then pcall(ac.setMessage, "PRESET", p.label .. " aplicado") end
  return true
end
_G.APEXFLOW_API = _G.APEXFLOW_API or {}
APEXFLOW_API.applyCategoryPreset = applyCategoryPreset
APEXFLOW_API.getCategoryPresets = function() return CATEGORY_PRESETS end

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
_G.APEXFLOW_API = _G.APEXFLOW_API or {}
APEXFLOW_API.getRealPitSpeedLimit = getRealPitSpeedLimit

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
  return string.format("ApexFlow_config_%s.lua", tostring(trackId))
end
local function savePerTrackConfig(trackId)
  if not trackId then
    local okS, sim = pcall(ac.getSim)
    trackId = (okS and sim) and getTrackIdForSave(sim) or "unknown_track"
  end
  local path = getPerTrackConfigPath(trackId)
  local f = io.open(path, "w")
  if not f then return false end
  f:write("return ")
  f:write(serializeTable(APEXFLOW_CFG, ""))
  f:write("\n")
  f:close()
  ac.log("[ApexFlow] Per-track config saved: " .. path)
  return true
end
local function loadPerTrackConfig(trackId)
  if not trackId then
    local okS, sim = pcall(ac.getSim)
    trackId = (okS and sim) and getTrackIdForSave(sim) or "unknown_track"
  end
  local path = getPerTrackConfigPath(trackId)
  local chunk = loadfile(path)
  if not chunk then -- pre-rename fallback (v0.31.2)
    chunk = loadfile(string.format("RaceFlow_config_%s.lua", tostring(trackId)))
  end
  if not chunk then return false end
  local ok, data = pcall(chunk)
  if not ok or type(data) ~= "table" then return false end
  deepMerge(APEXFLOW_CFG, data)
  ac.log("[ApexFlow] Per-track config loaded: " .. path)
  return true
end
_G.APEXFLOW_API = _G.APEXFLOW_API or {}
APEXFLOW_API.savePerTrackConfig = savePerTrackConfig
APEXFLOW_API.loadPerTrackConfig = loadPerTrackConfig

-- ----------------------------------------------------------
-- Telemetry CSV (v0.14.0) — lap-by-lap to Documents
-- ----------------------------------------------------------
local telemetryFile = nil
local lastTelemetryLap = -1
local function telemetryEnsureFile(sim)
  if telemetryFile then return telemetryFile end
  local trackId = getTrackIdForSave(sim)
  local fname = string.format("ApexFlow_telemetry_%s_%s.csv", trackId, os.date("%Y%m%d_%H%M%S"))
  local okD, docs = pcall(ac.getFolder, ac.FolderID.Documents)
  if not okD or not docs or docs=="" then ac.log("[ApexFlow] getFolder Documents failed"); return nil end
  docs = docs .. "/Assetto Corsa/"
  local path = docs .. fname
  local f = io.open(path, "w")
  if not f then return nil end
  f:write("lap,position,speedKmh,fuel,tyreWear,lapTimeMs,valid\n")
  telemetryFile = f
  ac.log("[ApexFlow] Telemetry CSV started: " .. path)
  return f
end
local function telemetryOnLap(sim)
  if not APEXFLOW_CFG.telemetryCSV or not APEXFLOW_CFG.telemetryCSV.enabled then return end
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
-- (mantidos apenas comentários; peso morto zero, sem acesso a APEXFLOW_CFG.voice)

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
          ac.log(string.format("[ApexFlow] AI #%d mechanical: slow (15s)", i))
          -- Schedule recovery via delayed reset (simple: rely on next AI update to restore)
        else
          if ac.requestPitStop then pcall(ac.requestPitStop, i) end
          ac.log(string.format("[ApexFlow] AI #%d mechanical: extra pit", i))
        end
        if ac.setMessage then pcall(ac.setMessage, "RACE CONTROL", string.format("AI #%d — mechanical issue", i)) end
      end
    end
  end
end

-- ----------------------------------------------------------
-- Learning / safety defaults (can be overridden by config/UI)
-- ----------------------------------------------------------
APEXFLOW_CFG.learningEnabled = false
-- v0.29.5 teste: danger/memory desligado para IA correr sem amarras

-- Hard-event detection
APEXFLOW_CFG.offTrackConfirmSec   = 0.8
APEXFLOW_CFG.overshootTurnX       = 35
APEXFLOW_CFG.overshootMinSpeedKmh = 95
APEXFLOW_CFG.overshootMarginKmh   = 25
APEXFLOW_CFG.overshootMinSamples  = 8
APEXFLOW_CFG.overshootMaxTurnX    = 80

-- Hard-event impact on learning
APEXFLOW_CFG.hardEventDangerAdd       = 2.0
APEXFLOW_CFG.hardEventImprovePenalty  = 4.0
APEXFLOW_CFG.crashSpeedDropKmh        = 55
APEXFLOW_CFG.dangerDecayPerClean  = 0.35
APEXFLOW_CFG.dangerDecayPerSecond = 0.004

APEXFLOW_CFG.dangerGateCleanStreak = 12

APEXFLOW_CFG.dangerOvercapBonusPerEvent = 0.10
APEXFLOW_CFG.dangerOvercapMaxCeiling   = 2.80

APEXFLOW_CFG.dangerRampStartEvent = 4
APEXFLOW_CFG.dangerRampPow        = 1.35
APEXFLOW_CFG.dangerRampGain       = 0.18

APEXFLOW_CFG.brakeBiasAddOnHardEvent   = 0.03
APEXFLOW_CFG.brakeBiasDecayPerClean    = 0.015
APEXFLOW_CFG.brakeBiasMax              = 0.15
APEXFLOW_CFG.brakeBiasThrottleLoss     = 0.06

APEXFLOW_CFG.cornerLockEnabled     = true
APEXFLOW_CFG.cornerLockMinSamples  = 80
APEXFLOW_CFG.cornerLockCleanStreak = 120

APEXFLOW_CFG.entryCapHeadroomKmh           = 6
APEXFLOW_CFG.entryCapLearnUpKmhPerClean    = 1.0
APEXFLOW_CFG.entryCapMinKmh                = 60
APEXFLOW_CFG.entryCapMaxKmh                = 9999

APEXFLOW_CFG.entryCapDropKmhOnOvershoot    = 12
APEXFLOW_CFG.entryCapDropKmhOnContact      = 18
APEXFLOW_CFG.entryCapDropKmhOnSlide        = 22
APEXFLOW_CFG.entryCapDropKmhOnOfftrack     = 28

APEXFLOW_CFG.entryCapPreMarginKmh          = 16
APEXFLOW_CFG.entryCapExcessWindowKmh       = 60
APEXFLOW_CFG.entryCapEarlyKickKmh          = 10
APEXFLOW_CFG.entryCapEarlyStartTurnX       = 85
APEXFLOW_CFG.entryCapEarlyEndTurnX         = 20

APEXFLOW_CFG.entryCapEscalateEvents            = 3
APEXFLOW_CFG.entryCapEscalateDanger            = 18
APEXFLOW_CFG.entryCapPreMarginBonusEscalated   = 10
APEXFLOW_CFG.entryCapWindowTightenEscalated    = 15
APEXFLOW_CFG.entryCapEscalatedStrengthMul      = 1.15

APEXFLOW_CFG.entryCapBrakeGain             = 0.22
APEXFLOW_CFG.entryCapTopSpeedLoss          = 0.10
APEXFLOW_CFG.entryCapThrottleLoss          = 0.07

APEXFLOW_CFG.dangerCap            = 28
APEXFLOW_CFG.dangerOvercapSlope   = 0.10
APEXFLOW_CFG.dangerOvercapMax     = 1.15
APEXFLOW_CFG.dangerBrakeGain      = 0.04
APEXFLOW_CFG.dangerTopSpeedLoss   = 0.03
APEXFLOW_CFG.dangerThrottleLoss   = 0.03
APEXFLOW_CFG.earlyCapWindowM      = 250
APEXFLOW_CFG.earlyForceWindowM    = 120
APEXFLOW_CFG.dangerZoneDamp       = 0.40
APEXFLOW_CFG.dangerZoneThreshold  = 5.0

APEXFLOW_CFG.paceBaseChillOverride     = -0.05
APEXFLOW_CFG.paceBaseAttackOverride    =  0.13
APEXFLOW_CFG.jitterScale               = 1.10
APEXFLOW_CFG.singleClassBackCatchup    = 0.008
APEXFLOW_CFG.singleClassBackCurve      = 2.5
APEXFLOW_CFG.earlySpreadFrac           = 0.55
APEXFLOW_CFG.earlySpreadNormalBoost    = 0.085
APEXFLOW_CFG.earlySpreadAttackBoost    = 0.120
APEXFLOW_CFG.multiclassYieldStrength  = 85
APEXFLOW_CFG.multiclassPushStrength   = 75
APEXFLOW_CFG.multiclassYieldDistM     = 120
APEXFLOW_CFG.multiclassPushDistM      = 80

-- v0.10.0: racecraft mais vivo por padrão (mais brigas e ultrapassagens).
APEXFLOW_CFG.stuckBehindDelay           = 0.7
APEXFLOW_CFG.stuckBehindRampTime        = 5.0
APEXFLOW_CFG.draftCommitRampGate        = 0.16
APEXFLOW_CFG.draftCommitTime            = 3.2
APEXFLOW_CFG.stuckBehindAggressionBoost = 0.22
APEXFLOW_CFG.stuckBehindPushBoost       = 0.035
APEXFLOW_CFG.draftCommitAggBoost        = 0.28
APEXFLOW_CFG.draftCommitPushBoost       = 0.052
APEXFLOW_CFG.draftCommitTopSpeedBoost   = 0.035

APEXFLOW_CFG.difficultyTopSpeedScale    = 0.22

APEXFLOW_CFG.lap1SuppressBase = 1.0
APEXFLOW_CFG.lap1RampFrac     = 0.0
APEXFLOW_CFG.lap1PaceBoost    = 0.05

APEXFLOW_CFG.cleanAirTopSpeedBoost    = 0.020
APEXFLOW_CFG.cleanAirPushBoost        = 0.018
APEXFLOW_CFG.huntPaceBoost            = 0.030
APEXFLOW_CFG.huntDuration             = 50.0
APEXFLOW_CFG.tigerChancePerLap        = 0.04

local MEMORY_FILE = "ApexFlow_memory.lua"

local APEXFLOW_MEMORY = {
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
      ac.log("[ApexFlow] setMessage failed: " .. tostring(err))
    end
    return ok
  end
end
_G.APEXFLOW_API = _G.APEXFLOW_API or {}
APEXFLOW_API.getRaceMessages = function() return raceMsgLog end

---------------------------------------------------------------------
-- CONFIG SAVE / LOAD
---------------------------------------------------------------------
local CONFIG_FILE = "ApexFlow_config.lua"
local LEGACY_CONFIG_FILE = "RARE_2_0_config.lua"
local LEGACY_RACEFLOW_CONFIG = "RaceFlow_config.lua" -- pre-rename (v0.31.2)

local function saveConfigToFile()
  local f, err = io.open(CONFIG_FILE, "w")
  if not f then
    ac.log(string.format("[ApexFlow] Failed to save config: %s", tostring(err)))
    return false
  end

  f:write("return ")
  f:write(serializeTable(APEXFLOW_CFG, ""))
  f:write("\n")
  f:close()

  ac.log("[ApexFlow] Config saved to " .. CONFIG_FILE)
  return true
end

local function loadConfigFromFile()
  local chunk, err = loadfile(CONFIG_FILE)
  if not chunk then
    chunk, err = loadfile(LEGACY_RACEFLOW_CONFIG)
    if chunk then ac.log("[ApexFlow] Migrated legacy RaceFlow_config.lua") end
  end
  if not chunk then
    chunk, err = loadfile(LEGACY_CONFIG_FILE)
  end
  if not chunk then
    ac.log(string.format("[ApexFlow] No config file to load or error: %s", tostring(err)))
    return
  end
  local ok, data = pcall(chunk)
  if not ok or type(data) ~= "table" then
    ac.log("[ApexFlow] Failed to load config table: " .. tostring(data))
    return
  end
  deepMerge(APEXFLOW_CFG, data)
  -- v0.32.2: migra repo antigo (screenshot mostrava RaceFlow-V2 salvo)
  if APEXFLOW_CFG.githubUpdate and APEXFLOW_CFG.githubUpdate.repo == "Silxyst/RaceFlow-V2" then
    APEXFLOW_CFG.githubUpdate.repo = "Silxyst/ApexFlow"
    ac.log("[ApexFlow] Migrated repo to Silxyst/ApexFlow")
  end
  ac.log("[ApexFlow] Config loaded successfully")
end

local function saveMemoryToFile()
  local f, err = io.open(MEMORY_FILE, "w")
  if not f then
    ac.log(string.format("[ApexFlow] Failed to save memory: %s", tostring(err)))
    return
  end

  f:write("return ")
  f:write(serializeTable(APEXFLOW_MEMORY, ""))
  f:write("\n")
  f:close()

  ac.log("[ApexFlow] Memory saved to " .. MEMORY_FILE)
end

local function loadMemoryFromFile()
  local chunk, err = loadfile(MEMORY_FILE)
  if not chunk then
    chunk, err = loadfile("RaceFlow_memory.lua") -- pre-rename (v0.31.2)
    if chunk then ac.log("[ApexFlow] Migrated legacy RaceFlow_memory.lua") end
  end
  if not chunk then
    ac.log(string.format("[ApexFlow] Memory load skipped (%s)", tostring(err)))
    return
  end

  local ok, data = pcall(chunk)
  if not ok or type(data) ~= "table" then
    ac.log("[ApexFlow] Failed to load memory table from " .. MEMORY_FILE)
    return
  end

  for k in pairs(APEXFLOW_MEMORY) do
    APEXFLOW_MEMORY[k] = nil
  end
  for k, v in pairs(data) do
    APEXFLOW_MEMORY[k] = v
  end

  ac.log("[ApexFlow] Memory loaded from " .. MEMORY_FILE)
end

_G.APEXFLOW_API = _G.APEXFLOW_API or {}
APEXFLOW_API.saveConfig = saveConfigToFile
APEXFLOW_API.loadConfig = loadConfigFromFile
APEXFLOW_API.saveMemory = saveMemoryToFile
APEXFLOW_API.loadMemory = loadMemoryFromFile
APEXFLOW_API.getMemory  = function() return APEXFLOW_MEMORY end
APEXFLOW_API.markConfigDirty = function()
  if _G.APEXFLOW_API then APEXFLOW_API._configDirty = true end
end
APEXFLOW_API.resetToDefaults = function()
    -- v0.31.0: alinhado com os defaults de init (era 50/100/65 defasado)
    APEXFLOW_CFG.aggression = 65
    APEXFLOW_CFG.difficultyBoost = 104
    APEXFLOW_CFG.paceStrength = 78
    APEXFLOW_CFG.stuckBehindDelay = 0.7
    APEXFLOW_CFG.stuckBehindRampTime = 5.0
    APEXFLOW_CFG.draftCommitRampGate = 0.16
    APEXFLOW_CFG.draftCommitTime = 3.2
    APEXFLOW_CFG.stuckBehindAggressionBoost = 0.22
    APEXFLOW_CFG.stuckBehindPushBoost = 0.035
    APEXFLOW_CFG.draftCommitAggBoost = 0.28
    APEXFLOW_CFG.draftCommitPushBoost = 0.052
    APEXFLOW_CFG.draftCommitTopSpeedBoost = 0.035
    APEXFLOW_CFG.huntDuration = 50.0
    APEXFLOW_CFG.tigerChancePerLap = 0.04
    if APEXFLOW_CFG.strategy then
      APEXFLOW_CFG.strategy.manualRaceLaps = 20
      APEXFLOW_CFG.strategy.forcedStops = 1
      APEXFLOW_CFG.strategy.tireChangeEnabled = true
      APEXFLOW_CFG.strategy.tireFreshnessPct = 50
    end
    -- NOTE v0.5.0: vsc reset block removed with the VSC system.
    -- Old saved configs may still contain cfg.vsc; it is ignored.
    -- v0.29.0: caution/tracklimits removidos (3,4) — reset ignora peso morto
    if APEXFLOW_CFG.hudEvents then
      local h = APEXFLOW_CFG.hudEvents
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
    if APEXFLOW_CFG.githubUpdate then
      APEXFLOW_CFG.githubUpdate.enabled = true
      APEXFLOW_CFG.githubUpdate.repo = "Silxyst/ApexFlow"
      APEXFLOW_CFG.githubUpdate.checkIntervalHours = 24
      APEXFLOW_CFG.githubUpdate.notifyOnStartup = true
    end
    if APEXFLOW_CFG.webui then
      APEXFLOW_CFG.webui.enabled = false
      APEXFLOW_CFG.webui.port = 8080
      APEXFLOW_CFG.webui.authToken = ""
    end
    if APEXFLOW_CFG.ui then
      APEXFLOW_CFG.ui.accent = "orange"
      APEXFLOW_CFG.ui.bgAlpha = 1.0
      APEXFLOW_CFG.ui.corner = 8
      APEXFLOW_CFG.ui.compactHeaders = false
    end
    if APEXFLOW_CFG.pitSpeedReal then APEXFLOW_CFG.pitSpeedReal.enabled = true end
    if APEXFLOW_CFG.telemetryCSV then APEXFLOW_CFG.telemetryCSV.enabled = false end
    -- v0.29.0: voice/realPenalty/fia removidos (3,4,6) — não resetar peso morto
    if APEXFLOW_CFG.failures then
      APEXFLOW_CFG.failures.enabled = false
      APEXFLOW_CFG.failures.chancePerHour = 0.08
      APEXFLOW_CFG.failures.minLap = 3
    end
    APEXFLOW_CFG.categoryPreset = "custom"
    saveConfigToFile()
    return true
  end

-- ==========================================================
-- GITHUB UPDATE CHECKER (async, uses web.get / ac.webRequest / file)
-- ==========================================================
-- Parser JSON mínimo em Lua puro (fallback quando ac.decodeJson não existe).
-- Cobre o que a API do GitHub retorna: objetos, arrays, strings com escapes, números.
local function jsonDecodeFallback(s)
  local pos = 1
  local function skip()
    while true do
      local c = s:sub(pos, pos)
      if c == " " or c == "\t" or c == "\n" or c == "\r" then pos = pos + 1 else break end
    end
  end
  local parseValue
  local function parseString()
    pos = pos + 1 -- abre "
    local out = {}
    while true do
      local c = s:sub(pos, pos)
      if c == "" then error("unterminated string") end
      if c == '"' then pos = pos + 1; break end
      if c == "\\" then
        local e = s:sub(pos + 1, pos + 1)
        if e == "n" then out[#out + 1] = "\n"
        elseif e == "t" then out[#out + 1] = "\t"
        elseif e == "r" then out[#out + 1] = "\r"
        elseif e == "b" then out[#out + 1] = "\b"
        elseif e == "f" then out[#out + 1] = "\f"
        elseif e == "u" then
          local hex = s:sub(pos + 2, pos + 5)
          local code = tonumber(hex, 16)
          local function utf8(code)
            if not code then return "?" end
            if code < 0x80 then return string.char(code)
            elseif code < 0x800 then
              return string.char(0xC0 + math.floor(code / 0x40), 0x80 + (code % 0x40))
            elseif code < 0x10000 then
              return string.char(0xE0 + math.floor(code / 0x1000),
                0x80 + (math.floor(code / 0x40) % 0x40), 0x80 + (code % 0x40))
            else
              return string.char(0xF0 + math.floor(code / 0x40000),
                0x80 + (math.floor(code / 0x1000) % 0x40),
                0x80 + (math.floor(code / 0x40) % 0x40),
                0x80 + (code % 0x40))
            end
          end
          -- par surrogate (emoji): \uD83C\uDF89
          if code and code >= 0xD800 and code <= 0xDBFF
             and s:sub(pos + 6, pos + 7) == "\\u" then
            local lo = tonumber(s:sub(pos + 8, pos + 11), 16)
            if lo and lo >= 0xDC00 and lo <= 0xDFFF then
              code = 0x10000 + (code - 0xD800) * 0x400 + (lo - 0xDC00)
              pos = pos + 6
            end
          end
          out[#out + 1] = utf8(code)
          pos = pos + 4
        else out[#out + 1] = e end
        pos = pos + 2
      else
        out[#out + 1] = c
        pos = pos + 1
      end
    end
    return table.concat(out)
  end
  local function parseNumber()
    local num = s:match("^-?%d+%.?%d*[eE]?[+-]?%d*", pos)
    pos = pos + #num
    return tonumber(num)
  end
  parseValue = function()
    skip()
    local c = s:sub(pos, pos)
    if c == "{" then
      pos = pos + 1
      local obj = {}
      skip()
      if s:sub(pos, pos) == "}" then pos = pos + 1; return obj end
      while true do
        skip()
        local k = parseString()
        skip()
        assert(s:sub(pos, pos) == ":", "expected :")
        pos = pos + 1
        obj[k] = parseValue()
        skip()
        local d = s:sub(pos, pos)
        if d == "}" then pos = pos + 1; break end
        assert(d == ",", "expected ,")
        pos = pos + 1
      end
      return obj
    elseif c == "[" then
      pos = pos + 1
      local arr = {}
      skip()
      if s:sub(pos, pos) == "]" then pos = pos + 1; return arr end
      while true do
        arr[#arr + 1] = parseValue()
        skip()
        local d = s:sub(pos, pos)
        if d == "]" then pos = pos + 1; break end
        assert(d == ",", "expected ,")
        pos = pos + 1
      end
      return arr
    elseif c == '"' then
      return parseString()
    elseif s:sub(pos, pos + 3) == "true" then pos = pos + 4; return true
    elseif s:sub(pos, pos + 4) == "false" then pos = pos + 5; return false
    elseif s:sub(pos, pos + 3) == "null" then pos = pos + 4; return nil
    else
      return parseNumber()
    end
  end
  local v = parseValue()
  skip()
  return v
end

local function decodeJsonSafe(body)
  if ac.decodeJson then
    local ok, data = pcall(function() return ac.decodeJson(body) end)
    if ok and type(data) == "table" then return data end
  end
  local ok, data = pcall(jsonDecodeFallback, body)
  if ok and type(data) == "table" then return data end
  return nil
end
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
-- Fallback sem HTTP no jogo: lê ApexFlow_update.json gravado pelo
-- panel_server.py / check_update.py (mesmo formato da API do GitHub).
local function githubCheckFromFile(cfg)
  local okD, docs = pcall(ac.getFolder, ac.FolderID.Documents)
  if not okD or not docs or docs == "" then return false end
  local f = io.open(docs .. "/Assetto Corsa/ApexFlow_update.json", "r")
  if not f then return false end
  local content = f:read("*a")
  f:close()
  if not content or content == "" then return false end
  local data = decodeJsonSafe(content)
  if type(data) ~= "table" then return false end
  -- Só vale para o mesmo repositório
  if data.repo and data.repo ~= (cfg.githubUpdate.repo or "Silxyst/ApexFlow") then return false end
  local version = tostring(data.version or "")
  if version == "" then return false end
  githubState.latestVersion = version
  githubState.changelog = data.changelog or ""
  githubState.tagName = data.tag
  githubState.publishedAt = data.published_at
  githubState.htmlUrl = data.html_url
  githubState.checkedAt = data.checked_at
  githubState.fromFile = true
  local function parseVer(v)
    local major, minor, patch = v:match("(%d+)%.(%d+)%.(%d+)")
    return tonumber(major or 0), tonumber(minor or 0), tonumber(patch or 0)
  end
  local cM, cm, cP = parseVer(SCRIPT_VERSION)
  local lM, lm, lP = parseVer(version)
  githubState.hasUpdate = (lM > cM) or (lM == cM and lm > cm) or (lM == cM and lm == cm and lP > cP)
  githubState.error = nil
  ac.log(string.format("[ApexFlow GitHub] File check: current %s, latest %s, update %s",
    SCRIPT_VERSION, version, githubState.hasUpdate and "YES" or "NO"))
  return true
end

-- HTTP no jogo: CSP expõe o global `web` (web.get), NÃO ac.webRequest.
-- Detectado em outros apps Lua instalados (Advanced Gamepad Assist, SetupExchange).
local function hasWebGet()
  return web ~= nil and type(web.get) == "function"
end

local function githubCheckUpdates(cfg, force)
  if not cfg.githubUpdate.enabled then return end
  if not hasWebGet() and not ac.webRequest then
    -- Sem HTTP no jogo: tenta o arquivo do painel local (atualiza o estado de verdade)
    if githubCheckFromFile(cfg) then
      webReqMissingLogged = false
      return
    end
    if not webReqMissingLogged then
      webReqMissingLogged = true
      githubState.error = "file"
      ac.log("[ApexFlow GitHub] sem HTTP no jogo; rode panel_server.py ou check_update.py (logged once)")
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
  githubState.fromFile = false
  githubState.lastCheck = now

  local url = string.format("https://api.github.com/repos/%s/releases/latest", cfg.githubUpdate.repo or "Silxyst/ApexFlow")
  ac.log("[ApexFlow GitHub] Checking for updates: " .. url)

  local function onResponse(err, response)
      githubState.checking = false
      if err then
        githubState.error = tostring(err)
        ac.log("[ApexFlow GitHub] Request failed: " .. githubState.error)
        return
      end
      local status = tonumber(response and response.status) or 0
      if not response or status ~= 200 then
        githubState.error = "HTTP " .. tostring(response and response.status or "nil")
        ac.log("[ApexFlow GitHub] " .. githubState.error)
        return
      end

      local body = response.body or response.data
      local data = decodeJsonSafe(body)
      if type(data) ~= "table" then
        githubState.error = "JSON parse failed"
        ac.log("[ApexFlow GitHub] " .. githubState.error)
        return
      end

      local tag = tostring(data.tag_name or data.name or "")
      local version = tag:gsub("^v", "")
      githubState.latestVersion = version
      githubState.changelog = data.body or "No changelog provided."
      githubState.tagName = data.tag_name
      githubState.publishedAt = data.published_at
      githubState.htmlUrl = data.html_url

      -- Compare versions (simple semantic version compare)
      local function parseVer(v)
        local major, minor, patch = v:match("(%d+)%.(%d+)%.(%d+)")
        return tonumber(major or 0), tonumber(minor or 0), tonumber(patch or 0)
      end
      local cM, cm, cP = parseVer(SCRIPT_VERSION)
      local lM, lm, lP = parseVer(version)
      githubState.hasUpdate = (lM > cM) or (lM == cM and lm > cm) or (lM == cM and lm == cm and lP > cP)

      ac.log(string.format("[ApexFlow GitHub] Current: %s, Latest: %s, Update: %s",
        SCRIPT_VERSION, version, githubState.hasUpdate and "YES" or "NO"))
  end

  if hasWebGet() then
    -- web.get(url, callback) ou web.get(url, headers, callback)
    local okCall = pcall(web.get, url,
      { ["User-Agent"] = "ApexFlow-AC-App", ["Accept"] = "application/vnd.github+json" },
      onResponse)
    if not okCall then pcall(web.get, url, onResponse) end
  else
    ac.webRequest({
      url = url,
      method = "GET",
      headers = { ["User-Agent"] = "ApexFlow-AC-App" },
      callback = onResponse,
    })
  end
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
  local okS, sim = pcall(ac.getSim)
  if not okS or not sim then return end

  if not configLoaded then
    loadConfigFromFile()
    configLoaded = true
  end

  if not memoryLoaded and _G.APEXFLOW_API and APEXFLOW_API.loadMemory then
    APEXFLOW_API.loadMemory()
    memoryLoaded = true
  end

  -- GitHub update check on startup + periodic (self-throttled inside)
  if APEXFLOW_CFG.githubUpdate and APEXFLOW_CFG.githubUpdate.enabled then
    if not githubStartupChecked and APEXFLOW_CFG.githubUpdate.notifyOnStartup then
      githubStartupChecked = true
      githubCheckUpdates(APEXFLOW_CFG, true) -- force check on startup
    else
      githubCheckUpdates(APEXFLOW_CFG, false) -- interval check
    end
  end

  if sim.isOnlineRace then return end
  if not sim.isSessionStarted then return end
  if not APEXFLOW_CFG.enabled then return end

  -- NOTE v0.5.0: VSC system removed (was here).

  -- Web UI (remote file-based polling)
  if webui and webui.update then
    webui.update(dt, sim, APEXFLOW_CFG)
  end

  -- Rolling Start
  local rollingActive = false
  if rolling and rolling.update then
    rollingActive = (rolling.update(dt, sim, APEXFLOW_CFG) == true)
  end

  if not rollingActive then
    if strategy and strategy.update then
      strategy.update(dt, sim, APEXFLOW_CFG)
    end
  end

  if ai and ai.update then
    local okA, errA = pcall(ai.update, dt, sim, APEXFLOW_CFG)
    if not okA then ac.log("[ApexFlow] ai.update: " .. tostring(errA)) end
  end

  -- v0.31.1: boost anti-fila (só velocidade — offset lateral é só da IA, sem briga dupla)
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
            blockers[#blockers+1] = { idx=j, pos=bcar.splinePosition }
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
                  if gapFwd > 0.0015 and gapFwd < 0.045 then
                    pcall(physics.setAITopSpeed, i, 320)
                    pcall(physics.setAIThrottleLimit, i, 1.0)
                    if physics.setAIAggression then pcall(physics.setAIAggression, i, 1.0) end
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
    pcall(gap_behind.update, dt, sim, APEXFLOW_CFG)
  end
  if sector_gaps and sector_gaps.update then
    pcall(sector_gaps.update, dt, sim, APEXFLOW_CFG)
  end
  if penalty_sev and penalty_sev.update then
    pcall(penalty_sev.update, dt, sim, APEXFLOW_CFG)
  end

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
  if APEXFLOW_CFG.telemetryCSV and APEXFLOW_CFG.telemetryCSV.enabled then
    pcall(telemetryOnLap, sim)
  end

  -- Light failures for AI (v0.14.0)
  if APEXFLOW_CFG.failures and APEXFLOW_CFG.failures.enabled then
    pcall(maybeTriggerFailures, dt, sim, APEXFLOW_CFG)
  end

  memorySaveCooldown = math.max(0.0, memorySaveCooldown - dt)
  if _G.APEXFLOW_API and APEXFLOW_API._memoryDirty and memorySaveCooldown <= 0.0 then
    if APEXFLOW_API.saveMemory then
      pcall(APEXFLOW_API.saveMemory)
    end
    APEXFLOW_API._memoryDirty = false
    memorySaveCooldown = memorySaveInterval
  end

  configSaveCooldown = math.max(0.0, configSaveCooldown - dt)
  if _G.APEXFLOW_API and APEXFLOW_API._configDirty and configSaveCooldown <= 0.0 then
    if APEXFLOW_API.saveConfig then
      pcall(APEXFLOW_API.saveConfig)
    end
    APEXFLOW_API._configDirty = false
    configSaveCooldown = configSaveInterval
  end
end

-- ==========================================================
-- EXPORTS for UI / other modules — limpo extremo v0.29.0: só 1,2,5,7,8
-- NOTE v0.5.0: VSC removido. v0.29.0: caution/tracklimits/voice/box/safety/realpenalty removidos (3,4,6)
-- ==========================================================
-- caution/tracklimits/voice/box/safety/realpenalty exports removidos (peso morto)
APEXFLOW_API.getStrategyState = function(cfg) return strategy and strategy.getState and strategy.getState(cfg or APEXFLOW_CFG) or {} end
-- v0.25.0: conformidade — gaps e penalidades mantidos (5)
APEXFLOW_API.getGapBehindState = function() return gap_behind and gap_behind.getState and gap_behind.getState() or {} end
APEXFLOW_API.getSectorGapsState = function() return sector_gaps and sector_gaps.getState and sector_gaps.getState() or {} end
APEXFLOW_API.getPenaltySeverityState = function() return penalty_sev and penalty_sev.getState and penalty_sev.getState() or {} end
APEXFLOW_API.reportPenaltySeverity = function(level, reason) if penalty_sev and penalty_sev.report then return penalty_sev.report(level, reason) end end
-- RealPenalty/sound/box/safety/voice/caution removidos — AC nativo assume
APEXFLOW_API.githubCheckUpdates = function(cfg, force)
  githubCheckUpdates(cfg or APEXFLOW_CFG, force)
end
APEXFLOW_API.githubGetState = function()
  return {
    checking = githubState.checking,
    lastCheck = githubState.lastCheck,
    latestVersion = githubState.latestVersion,
    currentVersion = SCRIPT_VERSION,
    hasUpdate = githubState.hasUpdate,
    changelog = githubState.changelog,
    error = githubState.error,
    fromFile = githubState.fromFile == true,
    checkedAt = githubState.checkedAt,
    tagName = githubState.tagName,
    publishedAt = githubState.publishedAt,
    htmlUrl = githubState.htmlUrl,
    repo = APEXFLOW_CFG.githubUpdate and APEXFLOW_CFG.githubUpdate.repo or "Silxyst/ApexFlow",
  }
end
APEXFLOW_API.webuiGetState = function() return webui and webui.getState and webui.getState() or {} end

-- ==========================================================
-- WINDOWS
-- ==========================================================
local function drawFallbackIfMissingModules()
  ui.pushFont(ui.Font.Title)
  ui.textAligned("ApexFlow", vec2(0.5, 0.5), vec2(ui.availableSpaceX(), 34))
  ui.popFont()
  ui.newLine(4)
  ui.textWrapped("ApexFlow modules failed to load. Check custom_shaders_patch.log for require() errors.")
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
    ui_root.draw(sim, APEXFLOW_CFG)
  else
    drawFallbackIfMissingModules()
  end
end

function script.windowSetup()
  local ok, sim = pcall(ac.getSim)
  if not ok or not sim then sim = nil end
  if ui_root and ui_root.draw then
    ui_root.draw(sim, APEXFLOW_CFG)
  else
    ui.pushFont(ui.Font.Title)
    ui.textAligned("ApexFlow", vec2(0.5, 0.5), vec2(ui.availableSpaceX(), 34))
    ui.popFont()
    drawFallbackIfMissingModules()
  end
end

function script.windowMainSettings()
  if ui.checkbox("Show window in setup", ac.isWindowOpen("main_setup")) then
    ac.setWindowOpen("main_setup", not ac.isWindowOpen("main_setup"))
  end
end

function script.windowPanel()
  local ok, sim = pcall(ac.getSim)
  if not ok or not sim then sim = nil end
  if ui_root and ui_root.drawPanel then
    ui_root.drawPanel(sim, APEXFLOW_CFG)
  else
    drawFallbackIfMissingModules()
  end
end

---------------------------------------------------------------------
-- EXTRA HUD: live race events (caution + track limits) - v0.7.0
-- Small overlay window; every read is guarded so it never crashes.
---------------------------------------------------------------------
-- v0.12.0: Full-featured, customizable Race Events HUD.
-- Each section honors APEXFLOW_CFG.hudEvents toggles; visuals degrade gracefully.
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
APEXFLOW_API.hudPreviewStart = function(secs)
  hudPreviewUntil = (os.clock() or 0) + (tonumber(secs) or 10)
  return true
end

-- Barra fina de combustível do herói (usa hudBar p/ respeitar o toggle de barras)
local function animBarPlaceholder(fuel, maxF)
  hudBar(maxF > 0 and (fuel / maxF) or 0, (APEXFLOW_CFG and APEXFLOW_CFG.hudEvents) or {})
end

local function drawRaceEventsBody()
  -- v0.24.0: par-a-par com o app — faixa + herói + pips + IA + jogo +
  -- estratégia estendida + preset/voz/update + ⚙ p/ abrir o app.
  local okS, sim = pcall(ac.getSim)
  if not okS then sim = nil end
  local inSession = sim and sim.isSessionStarted
  local hudCfg = (APEXFLOW_CFG and APEXFLOW_CFG.hudEvents) or {}
  local showStrategy= hudCfg.showStrategy ~= false
  local showPos     = hudCfg.showPosition ~= false
  local showSess    = hudCfg.showSession ~= false
  local showLearn   = hudCfg.showLearning == true
  local showExtras  = hudCfg.showExtras ~= false
  local compact     = hudCfg.compact == true
  local green = rgbm and rgbm(0.25, 0.95, 0.45, 1.0) or nil
  local cyan  = rgbm and rgbm(0.22, 0.88, 1.00, 1.0) or nil

  local api = _G.APEXFLOW_API or {}
  local st = (showStrategy and api.getStrategyState and api.getStrategyState(APEXFLOW_CFG)) or {}
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
        local pk = (_G.APEXFLOW_CFG and _G.APEXFLOW_CFG.categoryPreset) or "custom"
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
    local presetKey = (_G.APEXFLOW_CFG and _G.APEXFLOW_CFG.categoryPreset) or "custom"
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
    local v = _G.APEXFLOW_VERSION or SCRIPT_VERSION or "?"
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