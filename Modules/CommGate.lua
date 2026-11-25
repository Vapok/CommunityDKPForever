--[[
  CommGate.lua  (CDKP-003, AD-1 Layer A: application-level messaging gate)

  Wraps CommDKP.Sync:SendCommMessage once so every addon-comm call site (SendData and the
  raw SendCommMessage calls in comm.lua) is covered. While messaging is restricted (encounter
  lockdown), sends are deferred in a FIFO queue and flushed once the restriction clears.

  This is the main control: it lives in our code, so it still works when another addon has
  replaced our patched ChatThrottleLib with a different upstream copy.

  Bidding is NOT deferred here: bid open/submit/cancel/award check
  CommDKP:IsMessagingRestricted() before the user action and refuse with L["BIDDINGLOCKED"].
]]
local _, core = ...;
local CommDKP = core.CommDKP;

local Sync = CommDKP.Sync
local rawSend = Sync.SendCommMessage
local deferred = {}            -- FIFO of { prefix, text, distribution, target, prio, cb, cbArg }
local flushTicker
local FLUSH_INTERVAL = 2

-- Prefixes whose payload is a complete snapshot, so a newer queued copy fully supersedes an
-- older one and earlier duplicates (same prefix + distribution + target + team key) can be dropped.
-- Every other prefix carries deltas (e.g. CommDKPDKPDist / CommDKPLootDist send a single new
-- history entry) and must be delivered in full, in order, or other officers lose data.
-- Final list per AD-5.1 (13). Deliberately NOT here:
--   CommDKPPreBroad        payload names the broadcast that follows (AllTabs vs Merge); key can't see it
--   CommDKPMinBid/MaxBid   receivers upsert and the two senders produce different shapes
local SNAPSHOT_PREFIXES = {
  CommDKPAllTabs  = true,   -- full table broadcast
  CommDKPMerge    = true,   -- full 2-week merge window
  CommDKPStand    = true,   -- whole standby table
  CDKPWhitelist   = true,   -- whole whitelist
  CommDKPBidShare = true,   -- whole Bids_Submitted table
  CommDKPBossLoot = true,   -- current boss loot table
  CommDKPBuild    = true,   -- addon build number
  CommDKPTalents  = true,   -- own spec
  CommDKPRoles    = true,   -- own role
  CDKProfileSend  = true,   -- own profile
  CommDKPTeams    = true,   -- TeamsReceived replaces the whole teams table
  CommDKPDKPModes = true,   -- DKPModesReceived replaces modes / DKPBonus / raiders
  CommDKPZSumBank = true,   -- ZSumBankReceived replaces modes.ZeroSumBank
}

-- Encounter / messaging lockdown. Guarded lookups: either API may be absent on 1.60.1.
-- Fallback order: C_ChatInfo.InChatMessagingLockdown -> IsEncounterInProgress -> core.InEncounter.
function CommDKP:IsMessagingRestricted()
  local C = C_ChatInfo
  if C and type(C.InChatMessagingLockdown) == "function" then
    if C.InChatMessagingLockdown() then return true end
  end
  if type(IsEncounterInProgress) == "function" then
    return IsEncounterInProgress() and true or false
  end
  return core.InEncounter == true
end

local function SameTarget(a, b)
  return a == b or (type(a) == "string" and type(b) == "string" and a:lower() == b:lower())
end

local function StopTicker()
  if flushTicker then
    flushTicker:Cancel()
    flushTicker = nil
  end
end

local function Flush()
  if #deferred == 0 then
    StopTicker()
    return
  end
  if CommDKP:IsMessagingRestricted() then return end
  StopTicker()
  -- Swap the queue out first so a send that re-enters the gate can't loop on this list.
  local queue = deferred
  deferred = {}
  for i = 1, #queue do
    local e = queue[i]
    local ok, err = pcall(rawSend, Sync, e[1], e[2], e[3], e[4], e[5], e[6], e[7])
    if not ok then geterrorhandler()(err) end
  end
end

local function StartTicker()
  if not flushTicker and C_Timer and C_Timer.NewTicker then
    flushTicker = C_Timer.NewTicker(FLUSH_INTERVAL, Flush)
  end
end

-- AD-5.1 change C: a collapsed entry is never sent, so report it to its AceComm progress callback as
-- finished (bytesSent == bytesTotal) or broadcast progress state would stay visible forever.
local function DropDeferred(i)
  local e = deferred[i]
  if e[6] then
    local ok, err = pcall(e[6], e[7], 0, 0)
    if not ok then geterrorhandler()(err) end
  end
  table.remove(deferred, i)
end

local function Defer(prefix, text, distribution, target, prio, cb, cbArg)
  -- AD-5.1 change B: team key stamped by CommDKP.Sync:SendData. Raw SendCommMessage calls carry no
  -- stamp and are never collapsed (fail safe).
  local teamKey = Sync._gateTeamKey
  if SNAPSHOT_PREFIXES[prefix] and teamKey then
    for i = #deferred, 1, -1 do
      local e = deferred[i]
      if e[1] == prefix and e[3] == distribution and SameTarget(e[4], target) and e[8] == teamKey then
        DropDeferred(i)
      end
    end
  end
  deferred[#deferred + 1] = { prefix, text, distribution, target, prio, cb, cbArg, teamKey }
  StartTicker()
end

local function GatedSendCommMessage(self, prefix, text, distribution, target, prio, cb, cbArg)
  if CommDKP:IsMessagingRestricted() then
    Defer(prefix, text, distribution, target, prio, cb, cbArg)
    return
  end
  return rawSend(self, prefix, text, distribution, target, prio, cb, cbArg)
end

-- (Re)install the wrapper. A newer AceComm-3.0 loaded by another addon re-embeds itself into
-- every target and would silently overwrite our wrapper; re-wrapping keeps the gate in place.
local function InstallGate()
  if Sync.SendCommMessage ~= GatedSendCommMessage then
    rawSend = Sync.SendCommMessage
    Sync.SendCommMessage = GatedSendCommMessage
  end
end
InstallGate()

function CommDKP:GetDeferredCommCount()
  return #deferred
end

-- CDKP-006 F6-a (AD-7.1): lets /dkp test confirm the wrapper is still in place.
function CommDKP:IsCommGateInstalled()
  return CommDKP.Sync.SendCommMessage == GatedSendCommMessage
end

-- Flush triggers. ENCOUNTER_END is deferred one frame so the engine's encounter state (and
-- init.lua's core.InEncounter) has settled before we re-check the restriction.
local gate = CreateFrame("Frame")
gate:RegisterEvent("ENCOUNTER_END")
gate:RegisterEvent("PLAYER_REGEN_ENABLED")
gate:RegisterEvent("ZONE_CHANGED_NEW_AREA")
gate:RegisterEvent("PLAYER_LOGIN")
gate:SetScript("OnEvent", function(self, event)
  if event == "PLAYER_LOGIN" then
    InstallGate()   -- all non-LoD addons (and any newer AceComm) have loaded by now
    return
  end
  if #deferred == 0 then return end
  C_Timer.After(0, Flush)
end)
