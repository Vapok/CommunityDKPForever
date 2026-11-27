--[[
  SelfTest.lua  (CDKP-006 F6-a, AD-7: /dkp test)

  Guild-Leader-only in-game diagnostic. Prints engine telemetry and runs a fixed list of
  pass/fail checks. Deliberately not listed in /dkp help.

  Rules (AD-7.3):
    - Output stays on the local client (CommDKP:PrintAlways only, AD-7.7.1). Nothing is sent over chat or addon channels;
      the wire round trip runs fully in memory.
    - Never throws: every check runs through pcall; an erroring check is a FAIL and the rest still run.
    - Safe in combat / encounters: touches no protected frame and opens no Settings panel.
    - Secret Values are printed as <secret> and never stored.
    - One hidden backdrop test frame, created on first use and reused afterwards.
    - English-only text; the only localized string is L["NOPERMISSION"].
    - AD-7.7.3: listed last in the TOC; at load time this file only defines functions and file locals
      (no CreateFrame, LibStub lookups or core.* data reads at file scope).
]]
local addonName, core = ...;
local CommDKP = core.CommDKP;

-- AD-7.7.1: all output goes through PrintAlways (ignores SuppressNotifications / unchecked chat frames).
local Out = function(...) CommDKP:PrintAlways(...) end

local PASS = "|cff00ff00PASS|r"
local FAIL = "|cffff0000FAIL|r"
local YELLOW = "|cffffff00"
local HEADER = "|cff00cc66[CommunityDKP Forever Self-Test]|r"
local EXPECTED_INTERFACE = 16001
local EXPECTED_ROLES = 22
local MIN_CTL_VERSION = 24.1

local testFrame   -- AD-7.3 rule 5: created once, reused on every run

local function IsSecret(v)
  return issecretvalue ~= nil and v ~= nil and issecretvalue(v) and true or false
end

-- Display form of an engine value; Secret Values are never formatted or kept.
local function Show(v)
  if IsSecret(v) then return "<secret>" end
  return tostring(v)
end

local function Section(title)
  Out("-- " .. title .. " --")
end

local function Info(label, value)
  Out(label .. ": " .. value)
end

local function CountKeys(t)
  local n = 0
  for _ in pairs(t) do n = n + 1 end
  return n
end

local function DeepEqual(a, b)
  if type(a) ~= type(b) then return false end
  if type(a) ~= "table" then return a == b end
  for k, v in pairs(a) do
    if not DeepEqual(v, b[k]) then return false end
  end
  for k in pairs(b) do
    if a[k] == nil then return false end
  end
  return true
end

local function GetMetadata(field)
  if not (C_AddOns and type(C_AddOns.GetAddOnMetadata) == "function") then return nil end
  local ok, v = pcall(C_AddOns.GetAddOnMetadata, addonName, field)
  if ok then return v end
  return nil
end

-- CommDKP:IsPlayerGuildLeader() lives in Core.lua (AD-9.2.4).

---------------------------------------------------------------- AD-7.4 telemetry (information only)
local function PrintTelemetry()
  Section("Engine")
  local ok, ver, build, date, toc = pcall(GetBuildInfo)
  if ok then
    Info("Client build", Show(ver) .. "." .. Show(build) .. " (" .. Show(date) .. ")")
    local iface = Show(toc)
    if tonumber(toc) ~= EXPECTED_INTERFACE then iface = YELLOW .. iface .. " (expected " .. EXPECTED_INTERFACE .. ")|r" end
    Info("Interface", iface)
  else
    Info("Client build", "n/a (" .. tostring(ver) .. ")")
  end

  local allow = GetMetadata("AllowLoadGameType")
  Info("AllowLoadGameType", allow ~= nil and Show(allow) or "nil (engine does not expose this field)")
  Info("Version", Show(GetMetadata("Version")))

  local res = Enum and Enum.SendAddonMessageResult
  if type(res) ~= "table" then
    Info("Enum.SendAddonMessageResult", "missing")
  else
    local list = {}
    for k, v in pairs(res) do list[#list + 1] = { k = tostring(k), v = v } end
    table.sort(list, function(a, b)
      local na, nb = tonumber(a.v), tonumber(b.v)
      if na and nb and na ~= nb then return na < nb end
      return a.k < b.k
    end)
    local parts = {}
    for i = 1, #list do
      local e = list[i]
      local flag = (e.k:find("[Tt]hrottle") or e.k:find("[Ll]ockdown")) and " <<" or ""
      parts[#parts + 1] = e.k .. "=" .. Show(e.v) .. flag
    end
    Info("Enum.SendAddonMessageResult", table.concat(parts, ", "))
  end

  local lockFn = C_ChatInfo and C_ChatInfo.InChatMessagingLockdown
  local lockExists = type(lockFn) == "function"
  local lockLine = "exists=" .. tostring(lockExists)
  if lockExists then
    local okL, v = pcall(lockFn)
    lockLine = lockLine .. " now=" .. (okL and Show(v) or ("error: " .. tostring(v)))
  end
  Info("C_ChatInfo.InChatMessagingLockdown", lockLine)

  if type(IsEncounterInProgress) == "function" then
    local okE, v = pcall(IsEncounterInProgress)
    Info("IsEncounterInProgress()", okE and Show(v) or ("error: " .. tostring(v)))
  else
    Info("IsEncounterInProgress()", "n/a")
  end

  Info("issecretvalue", "exists=" .. tostring(type(issecretvalue) == "function"))

  local okC, combat = pcall(InCombatLockdown)
  Info("InCombatLockdown()", okC and Show(combat) or "n/a")

  local okR, restricted = pcall(CommDKP.IsMessagingRestricted, CommDKP)
  Info("CommDKP:IsMessagingRestricted()", okR and Show(restricted) or ("error: " .. tostring(restricted)))

  -- AD-10.9: information lines only (not checks), so the check count stays the same.
  local okN, rawFirst, rawSecond = pcall(UnitName, "player")
  local okP, pname = pcall(CommDKP.GetPlayerName, CommDKP)
  Info("Player name", (okP and Show(pname) or ("error: " .. tostring(pname)))
    .. " (UnitName: " .. (okN and (Show(rawFirst) .. ", " .. Show(rawSecond)) or "n/a") .. ")")
  Info("Last self-echo sender", Show(core.LastSelfEchoSender))
  -- AD-30.1.8 (BR-22.1): information lines only (not checks), so the check count stays the same.
  local okM1, m1 = pcall(CommDKP.FormatMetaTelemetry, CommDKP, "recv", core.LastRemoteMetaRecv)
  Info("Last remote meta sender", okM1 and m1 or ("error: " .. tostring(m1)))
  local okM2, m2 = pcall(CommDKP.FormatMetaTelemetry, CommDKP, "send", core.LastMetaSend)
  Info("Last meta send result", okM2 and m2 or ("error: " .. tostring(m2)))
  local okM3, m3 = pcall(CommDKP.FormatMetaTelemetry, CommDKP, "bcast", core.LastBroadcastSelfMeta)
  Info("Officer copy of my meta (last broadcast)", okM3 and m3 or ("error: " .. tostring(m3)))
  Info("Comm trace", core.CommTrace and "on" or "off")
end

---------------------------------------------------------------- AD-7.5 checks
-- Each fn returns (passed, detail). Ordered; the summary count comes from #checks (AD-7.5).
local function LibCheck(name)
  return function()
    return LibStub(name, true) ~= nil, ""
  end
end

local function TableCheck(getSV, useLength)
  return function()
    local t = CommDKP:GetTable(getSV(), true)
    if type(t) ~= "table" then return false, "type=" .. type(t) end
    if useLength then return true, "#=" .. #t end
    return true, "entries=" .. CountKeys(t)
  end
end

local spec = {
  -- AD-8.5: init/UI state first, so the report shows how far initialization got.
  { section = "Initialization" },
  { "Addon initialized", function()
      if core.Initialized == true then return true, "" end
      return false, core.InitError or "no error captured"
    end },
  { "Main UI constructed", function()
      if not CommDKP.UIConfig then return false, "missing CommDKP.UIConfig" end
      if not CommDKP.UIConfig.TabMenu then return false, "missing CommDKP.UIConfig.TabMenu" end
      for i = 1, 7 do
        if not CommDKP["ConfigTab" .. i] then return false, "missing CommDKP.ConfigTab" .. i end
      end
      return true, ""
    end },

  { section = "Libraries & CommGate" },
  { "LibStub", function() return type(LibStub) == "table", "type=" .. type(LibStub) end },
  { "AceComm-3.0", LibCheck("AceComm-3.0") },
  { "AceSerializer-3.0", LibCheck("AceSerializer-3.0") },
  { "LibDeflate", LibCheck("LibDeflate") },
  { "LibUIDropDownMenu-4.0", LibCheck("LibUIDropDownMenu-4.0") },
  { "ChatThrottleLib >= " .. MIN_CTL_VERSION, function()
      local v = ChatThrottleLib and tonumber(ChatThrottleLib.version)
      return v ~= nil and v >= MIN_CTL_VERSION, "version=" .. tostring(ChatThrottleLib and ChatThrottleLib.version)
    end },
  { "CommGate installed", function() return CommDKP:IsCommGateInstalled() == true, "" end },
  { "Deferred comm queue", function()
      local n = CommDKP:GetDeferredCommCount()
      return type(n) == "number", "queued=" .. tostring(n)
    end },

  { section = "Backdrops & Palettes" },
  { "BackdropTemplateMixin", function() return type(BackdropTemplateMixin) == "table", "" end },
  { "ApplyBackdrop on test frame", function()
      if not testFrame then
        testFrame = CreateFrame("Frame", nil, UIParent)
        testFrame:Hide()
        testFrame:SetSize(16, 16)
        testFrame:SetPoint("TOPLEFT", UIParent, "TOPLEFT", -10000, 10000)   -- off-screen
      end
      CommDKP:ApplyBackdrop(testFrame, "Card", "bg1", "trimQuiet")   -- CDKP-009c: a live kit key (legacy "Panel" retires in 009d)
      return testFrame.SetBackdrop ~= nil and testFrame:GetBackdrop() ~= nil, ""
    end },
  { "Active palette", function()
      local name = (core.DB and core.DB.defaults and core.DB.defaults.Palette) or core.DefaultPaletteName
      return name ~= nil and core.Palettes[name] ~= nil, "name=" .. tostring(name)
    end },
  { "Palette role parity (Legacy/Forever)", function()
      local legacy, forever = core.Palettes.Legacy, core.Palettes.Forever
      if type(legacy) ~= "table" or type(forever) ~= "table" then return false, "palette missing" end
      local nl, nf = CountKeys(legacy), CountKeys(forever)
      local diff = {}
      for k in pairs(legacy) do if forever[k] == nil then diff[#diff + 1] = "Legacy-only:" .. tostring(k) end end
      for k in pairs(forever) do if legacy[k] == nil then diff[#diff + 1] = "Forever-only:" .. tostring(k) end end
      table.sort(diff)
      local detail = "Legacy=" .. nl .. " Forever=" .. nf
      if #diff > 0 then detail = detail .. " " .. table.concat(diff, ", ") end
      return nl >= EXPECTED_ROLES and nl == nf and #diff == 0, detail
    end },

  { section = "C_* namespaces & Settings" },
  { "C_AddOns.GetAddOnMetadata", function() return type(C_AddOns.GetAddOnMetadata) == "function", "" end },
  { "C_Container.GetContainerNumSlots", function() return type(C_Container.GetContainerNumSlots) == "function", "" end },
  { "C_GuildInfo.GuildRoster", function() return type(C_GuildInfo.GuildRoster) == "function", "" end },
  { "C_Item.GetItemInfo", function() return type(C_Item.GetItemInfo) == "function", "" end },
  { "Settings category registered", function()
      return core.SettingsCategoryID ~= nil, "id=" .. tostring(core.SettingsCategoryID)
    end },

  { section = "SavedVariables & team state" },
  { "Guild / team", function()
      local g = CommDKP:GetGuildName()
      return type(g) == "string" and g ~= "",
        "guild=" .. tostring(g) .. " team=" .. tostring(CommDKP:GetCurrentTeamIndex()) .. " (" .. tostring(CommDKP:GetCurrentTeamName()) .. ")"
    end },
  { "CommDKP_DKPTable", TableCheck(function() return CommDKP_DKPTable end, true) },
  { "CommDKP_Loot", TableCheck(function() return CommDKP_Loot end, true) },
  { "CommDKP_DKPHistory", TableCheck(function() return CommDKP_DKPHistory end, true) },
  { "CommDKP_MinBids", TableCheck(function() return CommDKP_MinBids end, false) },
  { "Schema build", function()
      -- Same field VerifyDBSchema/UpgradeDBSchema read (dbTable.dbinfo.build) on CommDKP_DB.
      local b = CommDKP_DB and CommDKP_DB.dbinfo and CommDKP_DB.dbinfo.build
      local detail = "dbinfo.build=" .. tostring(b) .. " core.BuildNumber=" .. tostring(core.BuildNumber)
      if b ~= core.BuildNumber then detail = YELLOW .. detail .. "|r" end
      return type(b) == "number", detail
    end },

  { section = "Wire round trip" },
  { "Serialize/Compress/Encode round trip (in memory)", function()
      local LibDeflate = LibStub("LibDeflate")
      local LibAceSerializer = LibStub("AceSerializer-3.0")
      local probe = { s = "Test|cffff0000\195\188\226\130\172|r", n = 123.25, neg = -7, b = true, t = { 1, 2, { deep = "x" } } }
      local packet = CommDKP.Sync:SerializeTableToString(probe)
      if type(packet) ~= "string" then return false, "packet type=" .. type(packet) end
      local noNul = packet:find("\0", 1, true) == nil
      local decoded = LibDeflate:DecodeForWoWAddonChannel(packet)
      local inflated = decoded and LibDeflate:DecompressDeflate(decoded)
      local ok, out = false, nil
      if inflated then ok, out = LibAceSerializer:Deserialize(inflated) end
      return (ok and DeepEqual(probe, out) and noNul) and true or false,
        "#packet=" .. #packet .. " noNUL=" .. tostring(noNul) .. " equal=" .. tostring(ok and DeepEqual(probe, out) or false)
    end },
}

-- Fold the section markers into the following check so #checks is exactly the number of checks.
local checks = {}
do
  local pending
  for i = 1, #spec do
    local e = spec[i]
    if e.section then pending = e.section
    else
      checks[#checks + 1] = { e[1], e[2], section = pending }
      pending = nil
    end
  end
end

function CommDKP:RunSelfTest()
  -- AD-8.5: runs even when core.Initialized == false (that's when it helps most); GL gate first.
  local okGL, isGL = pcall(CommDKP.IsPlayerGuildLeader, CommDKP)
  if not (okGL and isGL) then Out(core.L["NOPERMISSION"]) return end

  Out(HEADER)
  local okT, errT = pcall(PrintTelemetry)
  if not okT then Out(FAIL .. " telemetry: " .. tostring(errT)) end

  local passed, failed = 0, 0
  for i = 1, #checks do
    local c = checks[i]
    if c.section then Section(c.section) end
    local ok, result, detail = pcall(c[2])
    local good = ok and result == true
    if not ok then detail = "error: " .. tostring(result) end
    if good then passed = passed + 1 else failed = failed + 1 end
    local line = (good and PASS or FAIL) .. " " .. i .. ". " .. c[1]
    if detail and detail ~= "" then line = line .. " - " .. tostring(detail) end
    Out(line)
  end

  local color = failed == 0 and "|cff00ff00" or "|cffff0000"
  Out(string.format("%s[CommunityDKP Forever Self-Test] %d/%d checks PASSED (%d failed)|r", color, passed, #checks, failed))
end
