-- src/penalty_severity.lua
-- RaceFlow Penalty Severity — v0.25.0
-- Conformidade CBA 5.3-5.14 / iRacing 8.x: classificação gravidade 1-6 e PP.

local M = {}

_G.RARE2_API = _G.RARE2_API or {}

local state = {
  totalPP = 0,
  level = 0, -- 1..6
  lastReason = "",
  history = {}, -- { {t, level, reason, pp} }
  maxHistory = 20,
  lastUpdate = 0,
}

-- Tabela CBA 5.4-5.12: nível -> PP
local PP_BY_LEVEL = { [1]=1, [2]=2, [3]=3, [4]=4, [5]=5, [6]=6 }

local function pushHistory(level, reason)
  local pp = PP_BY_LEVEL[level] or 0
  state.totalPP = state.totalPP + pp
  state.level = level
  state.lastReason = reason or ""
  table.insert(state.history, 1, { t = os.clock() or 0, level = level, reason = reason or "", pp = pp })
  if #state.history > state.maxHistory then table.remove(state.history) end
end

-- v0.28.2: persistência por ac.storage + histórico completo
local ppStorage = nil
local function getStorage()
  if ppStorage then return ppStorage end
  local ok, st = pcall(ac.storage, "RaceFlow_PP_Data")
  if ok and st then ppStorage = st; return ppStorage end
  return nil
end
local function loadPP()
  local st = getStorage()
  if st then
    local ok, data = pcall(st.load, st)
    if ok and type(data)=="table" then
      state.totalPP = tonumber(data.total) or state.totalPP
      state.history = type(data.history)=="table" and data.history or state.history
      if #state.history>0 then state.level = state.history[1].level or 0; state.lastReason = state.history[1].reason or "" end
    end
  end
end
local function savePP()
  local st = getStorage()
  if st then pcall(st.save, st, {total=state.totalPP, history=state.history}) end
end
pcall(loadPP)

function M.report(level, reason)
  level = math.max(1, math.min(6, tonumber(level) or 1))
  pushHistory(level, reason)
  pcall(savePP)
  ac.log(string.format("[RaceFlow PenaltySeverity] L%d +%dPP (%s) total=%d", level, PP_BY_LEVEL[level] or 0, tostring(reason), state.totalPP))
end

function M.update(dt, sim, cfg)
  state.lastUpdate = os.clock() or 0
  -- auto-save a cada 5s se dirty
  M._saveTimer = (M._saveTimer or 0) + dt
  if M._saveTimer > 5 then M._saveTimer = 0; pcall(savePP) end
end

function M.getState()
  return {
    totalPP = state.totalPP,
    level = state.level,
    lastReason = state.lastReason,
    history = state.history,
    lastUpdate = state.lastUpdate,
  }
end

function M.forceReset()
  state.totalPP = 0
  state.level = 0
  state.lastReason = ""
  state.history = {}
  state.lastUpdate = 0
end

return M
