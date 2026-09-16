-- src/voice.lua
-- RaceFlow Voice (v0.15.1) — fila de áudio por eventos, inspirada no
-- AC-Engineer-Spotter-Audio (fila FIFO, prioridade, cooldown por grupo,
-- timeout anti-travamento, legendas via ac.setMessage).
--
-- Regras anti-regressão:
--  * 100% escopo local, retorna M (zero globais).
--  * Clips 100% opcionais: sfx/voice/<CATEGORIA>/*.mp3|wav|ogg.
--    Sem clips ou sem ac.AudioEvent => beep + mensagem (nunca quebra).
--  * Roda via M.update a partir de script.update (nunca de janela).
--  * Categorias com toggle: limits | pit | caution | penalty.

local M = {}

_G.RARE2_API = _G.RARE2_API or {}
local RARE2_API = _G.RARE2_API

local KINDS = {
  limits  = { dir = "LIMITS",  caption = "Track limits — advertência", cooldown = 3.0, priority = false },
  pit     = { dir = "PIT",     caption = "Pit speed — reduza",          cooldown = 5.0, priority = false },
  caution = { dir = "CAUTION", caption = "Caution — bandeira amarela",  cooldown = 5.0, priority = true  },
  penalty = { dir = "PENALTY", caption = "Punição — cumpra no box",     cooldown = 5.0, priority = true  },
}

local queue = {}
local playing = nil
local clock = 0
local cooldowns = {}
local libCache = {}
local lastKind, lastAt = "", 0
local audioProbe = nil -- nil = não sondado; true/false após probe
local beepWarned = false

local QUEUE_MAX = 20
local HARD_TIMEOUT = 12

local function ensureCfg(cfg)
  cfg.voice = cfg.voice or {}
  local v = cfg.voice
  if v.enabled == nil then v.enabled = true end
  v.volume = tonumber(v.volume) or 0.8
  if v.volume < 0 then v.volume = 0 end
  if v.volume > 1 then v.volume = 1 end
  v.speed = tonumber(v.speed) or 1.0
  if v.speed < 0.75 then v.speed = 0.75 end
  if v.speed > 1.5 then v.speed = 1.5 end
  v.categories = v.categories or {}
  for _, k in ipairs({ "limits", "pit", "caution", "penalty" }) do
    if v.categories[k] == nil then v.categories[k] = true end
  end
  return v
end

local function audioAvailable()
  if audioProbe ~= nil then return audioProbe end
  audioProbe = ac ~= nil and ac.AudioEvent ~= nil
    and type(ac.AudioEvent.fromFile) == "function"
  return audioProbe
end

local function appRoot()
  local ok, dir = pcall(function() return ac.getFolder(ac.FolderID.ScriptOrigin) end)
  if ok and dir and dir ~= "" then return tostring(dir) end
  return nil
end

local function scanDirClips(dir)
  local out = {}
  if not io or not io.scanDir then return out end
  for _, ext in ipairs({ "*.mp3", "*.wav", "*.ogg" }) do
    local ok, files = pcall(io.scanDir, dir, ext)
    if ok and type(files) == "table" then
      for _, n in ipairs(files) do out[#out + 1] = dir .. "/" .. tostring(n) end
    end
  end
  return out
end

local function clipsFor(kindDir)
  if libCache[kindDir] then return libCache[kindDir] end
  local list = {}
  local root = appRoot()
  if root then
    list = scanDirClips(root .. "/sfx/voice/" .. kindDir)
  end
  libCache[kindDir] = list
  return list
end

local function pickClip(kindDir)
  local list = clipsFor(kindDir)
  if #list == 0 then return nil end
  return list[math.random(1, #list)]
end

local function makeEvent(path, looped)
  local params = { filename = path, use3D = false, loop = looped == true }
  local ok, ev = pcall(ac.AudioEvent.fromFile, params, false)
  if not ok then
    ac.log("[RaceFlow Voice] fromFile falhou: " .. tostring(ev))
    return nil
  end
  return ev
end

local function playBeepFallback(vol)
  -- Mesmo beep histórico do app (rs_beep.wav). Tudo com pcall.
  pcall(function()
    if ui == nil or ui.MediaPlayer == nil then return end
    local ok, mp = pcall(ui.MediaPlayer, "apps/lua/RaceFlow/sfx/rs_beep.wav")
    if ok and mp then
      if mp.setVolume then mp:setVolume((tonumber(vol) or 0.8) * 10) end
      if mp.play then mp:play() end
    end
  end)
end

local function push(entry, priority)
  if priority then
    local idx = #queue + 1
    for i, q in ipairs(queue) do
      if not q.priority then idx = i break end
    end
    table.insert(queue, idx, entry)
  else
    queue[#queue + 1] = entry
  end
  while #queue > QUEUE_MAX do table.remove(queue, 1) end
end

--- Diz um aviso. Retorna true se enfileirou.
function M.say(kind, cfg, opts)
  opts = opts or {}
  cfg = cfg or (_G.RARE2_CFG or {})
  local v = ensureCfg(cfg)
  if not v.enabled and not opts.force then return false end
  local def = KINDS[kind]
  if not def then return false end
  if not opts.force and v.categories and v.categories[kind] == false then return false end
  if not opts.force and not opts.bypassCooldown then
    local last = cooldowns[kind] or -100
    if (clock - last) < (def.cooldown or 3.0) then return false end
  end
  cooldowns[kind] = clock
  lastKind, lastAt = kind, clock
  local path = pickClip(def.dir)
  push({
    kind = kind,
    path = path, -- nil => beep+mensagem
    caption = opts.caption or def.caption,
    vol = tonumber(v.volume) or 0.8,
    speed = tonumber(v.speed) or 1.0,
    priority = opts.priority ~= nil and opts.priority or def.priority,
    isBeep = path == nil,
  }, opts.priority ~= nil and opts.priority or def.priority)
  return true
end

--- Teste manual (ignora cooldown e categoria).
function M.test(kind, cfg)
  return M.say(kind, cfg, { force = true, bypassCooldown = true, priority = true })
end

function M.clear()
  queue = {}
  if playing and playing.event then pcall(function() playing.event:stop() end) end
  playing = nil
end

function M.rescan()
  libCache = {}
end

local function evEnded(ev, startedAt, maxDur)
  if not ev then return true end
  local elapsed = clock - startedAt
  if elapsed > HARD_TIMEOUT then return true end
  local ok, val = pcall(function() return ev.isPlaying end)
  if ok and type(val) == "boolean" and not val then return true end
  ok, val = pcall(function() return ev:isPlaying() end)
  if ok and type(val) == "boolean" and not val then return true end
  ok, val = pcall(function() return ev.stopped end)
  if ok and val == true then return true end
  return elapsed > (maxDur or 6)
end

local function startNext()
  local entry = table.remove(queue, 1)
  if not entry then
    playing = nil
    return
  end
  -- Legenda sempre (mensagem AC), com ou sem áudio.
  if entry.caption and entry.caption ~= "" and ac and ac.setMessage then
    pcall(ac.setMessage, "VOZ", entry.caption)
  end
  if entry.isBeep or not audioAvailable() then
    if not audioAvailable() and not beepWarned then
      beepWarned = true
      ac.log("[RaceFlow Voice] ac.AudioEvent indisponível; usando beep+mensagem.")
    end
    playBeepFallback(entry.vol)
    playing = { event = nil, startedAt = clock, maxDur = 1.2, entry = entry }
    return
  end
  local ev = makeEvent(entry.path, false)
  if not ev then
    playBeepFallback(entry.vol)
    playing = { event = nil, startedAt = clock, maxDur = 1.2, entry = entry }
    return
  end
  local ok, err = pcall(function()
    ev.volume = math.max(0, math.min(30, (tonumber(entry.vol) or 0.8) * 10))
    ev.pitch = math.max(0.5, math.min(2.0, tonumber(entry.speed) or 1.0))
    ev:start()
  end)
  if not ok then
    ac.log("[RaceFlow Voice] start falhou: " .. tostring(err))
    playBeepFallback(entry.vol)
    playing = { event = nil, startedAt = clock, maxDur = 1.2, entry = entry }
    return
  end
  playing = { event = ev, startedAt = clock, maxDur = 8, entry = entry }
end

function M.update(dt)
  clock = clock + math.max(0, math.min(tonumber(dt) or 0, 0.25))
  if not playing then
    if #queue > 0 then startNext() end
    return
  end
  if evEnded(playing.event, playing.startedAt, playing.maxDur) then
    if playing.event then pcall(function() playing.event:stop() end) end
    startNext()
  end
end

function M.getState()
  local clips = {}
  for kind, def in pairs(KINDS) do
    clips[kind] = #clipsFor(def.dir)
  end
  return {
    available = audioAvailable(),
    clips = clips,
    busy = playing ~= nil or #queue > 0,
    queue = #queue,
    lastKind = lastKind,
    lastAt = lastAt,
  }
end

function M.getKinds()
  local out = {}
  for k, d in pairs(KINDS) do out[k] = d.caption end
  return out
end

return M
