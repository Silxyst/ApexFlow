-- src/sector_gaps.lua
-- ApexFlow Sector Gaps — v0.25.0
-- Conformidade iRacing/CBA: gaps por setor (delta setorial ao líder).

local M = {}

_G.APEXFLOW_API = _G.APEXFLOW_API or {}

local state = {
  currentSector = 0,
  gapSectorM = 0,
  gapSectorS = 0,
  leaderSector = 0,
  leaderIdx = nil,
  lastUpdate = 0,
}

-- Estimativa simples de gap temporal por setor usando velocidade
local function estimateTimeGap(distM, speedKmh)
  local v = tonumber(speedKmh) or 0
  if v < 5 then return 0 end
  local ms = v / 3.6
  return distM / ms
end

function M.update(dt, sim, cfg)
  if not sim or not sim.isSessionStarted or sim.isOnlineRace then return end
  local okP, pcar = pcall(ac.getCar, 0)
  if not okP or not pcar then return end

  local mySec = tonumber(pcar.currentSector) or 0
  state.currentSector = mySec

  -- Encontrar líder
  local carsCount = sim.carsCount or 0
  local leader = nil
  local leaderIdx = nil
  for i = 0, carsCount - 1 do
    local ok, c = pcall(ac.getCar, i)
    if ok and c and tonumber(c.racePosition) == 1 then
      leader = c
      leaderIdx = i
      break
    end
  end
  if not leader then
    state.gapSectorM = 0
    state.gapSectorS = 0
    state.leaderSector = 0
    state.leaderIdx = nil
    return
  end

  state.leaderIdx = leaderIdx
  state.leaderSector = tonumber(leader.currentSector) or 0

  -- Se mesmo setor, calcular gap em metros via spline
  if mySec == state.leaderSector then
    local mySp = tonumber(pcar.splinePosition)
    local leadSp = tonumber(leader.splinePosition)
    local L = tonumber(sim.trackLengthM) or 0
    if mySp and leadSp and L > 0 then
      local frac = (leadSp - mySp) % 1
      -- Só faz sentido se leader está à frente no mesmo setor (frac < 0.5)
      if frac < 0.5 then
        state.gapSectorM = frac * L
        state.gapSectorS = estimateTimeGap(state.gapSectorM, pcar.speedKmh)
      else
        state.gapSectorM = 0
        state.gapSectorS = 0
      end
    end
  else
    -- Setores diferentes: gap não comparável diretamente
    state.gapSectorM = 0
    state.gapSectorS = 0
  end
  state.lastUpdate = os.clock() or 0
end

function M.getState()
  return {
    currentSector = state.currentSector,
    gapSectorM = state.gapSectorM,
    gapSectorS = state.gapSectorS,
    leaderSector = state.leaderSector,
    leaderIdx = state.leaderIdx,
    lastUpdate = state.lastUpdate,
  }
end

function M.forceReset()
  state.currentSector = 0
  state.gapSectorM = 0
  state.gapSectorS = 0
  state.leaderSector = 0
  state.leaderIdx = nil
  state.lastUpdate = 0
end

return M
