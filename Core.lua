--[[
	Core.lua is intended to store all core functions and variables to be used throughout the addon. 
	Don't put anything in here that you don't want to be loaded immediately after the Libs but before initialization.
--]]

local _, core = ...;
local _G = _G;
local L = core.L;   -- English fallback for untranslated keys is attached in Localization/Fallback.lua (AD-6.5)

-- AD-7.7.2: roster name without the realm. Handles "Name-Realm", a bare "Name" (no dash), and nil entries
-- (GetGuildRosterInfo can return nil while the roster refreshes).
local function StripRealm(name)
	if type(name) ~= "string" then return nil end
	return (name:match("^([^%-]+)")) or name
end

local LibDD = LibStub:GetLibrary("LibUIDropDownMenu-4.0");

core.CommDKP = {};       -- UI Frames global
core.CommDKPApi = { __version = 1, pricelist = nil }
local CommDKP = core.CommDKP;
local CommDKPApi = core.CommDKPApi;

-- AD-9.2.1: public wrapper so every module strips realms the same nil-safe way (NAME-001).
function CommDKP:StripRealm(name) return StripRealm(name) end

-- AD-10.3: Forever characters are "First Last"; UnitName returns first, last. Roster/table names are the full name.
local function Trim(s) return type(s) == "string" and (s:gsub("^%s+", ""):gsub("%s+$", "")) or nil end

function CommDKP:GetPlayerName()
	if core.PlayerFullName then return core.PlayerFullName end
	local first, second = (UnitNameUnmodified or UnitName)("player")
	if type(first) ~= "string" or first == "" or first == UNKNOWNOBJECT then return nil end
	local realm = GetRealmName() or ""
	if type(second) == "string" and second ~= "" and second ~= realm then
		core.PlayerFullName = first .. " " .. second          -- cache only once the last name is known
		core.PlayerFirstName = first
		return core.PlayerFullName
	end
	core.PlayerFirstName = first
	return first                                            -- not cached: retry until the last name arrives
end

-- Same rule as GetPlayerName for any unit token ("target", "raid1", ...). Not cached.
function CommDKP:GetUnitFullName(unit)
	local first, second = (UnitNameUnmodified or UnitName)(unit)
	if type(first) ~= "string" or first == "" or first == UNKNOWNOBJECT then return nil end
	if type(second) == "string" and second ~= "" and second ~= (GetRealmName() or "") then
		return first .. " " .. second
	end
	return first
end

function CommDKP:NormalizeName(name)                      -- "Bank Robbers-Realm" / "Bank Robbers-" -> "Bank Robbers"
	return Trim(CommDKP:StripRealm(name))
end

function CommDKP:SamePlayer(a, b)
	local na, nb = CommDKP:NormalizeName(a), CommDKP:NormalizeName(b)
	return na ~= nil and na ~= "" and na == nb
end

function CommDKP:IsSelf(name)
	local n = CommDKP:NormalizeName(name); if not n or n == "" then return false end
	local full = CommDKP:GetPlayerName(); if not full then return false end
	if n == full then return true end
	-- Bare first name ("Bank") counts as self only if the input has no last name of its own.
	return core.PlayerFirstName ~= nil and n == core.PlayerFirstName and not n:find(" ", 1, true)
end

-- Maps a legacy bare first name (old history indexes like "Bank-1732...") to the roster's full name,
-- only when exactly one roster member has that first name. Otherwise returns the input unchanged.
function CommDKP:ResolveRosterName(name)
	local n = CommDKP:NormalizeName(name); if not n or n == "" or not IsInGuild() then return n end
	-- AD-15.4(c): case-insensitive (chat arguments arrive lowercased); returns the roster's casing.
	-- A full "first last" input only matches a whole roster name ("bank robbers" -> "Bank Robbers").
	local ln, hit = n:lower()
	local full = n:find(" ", 1, true) ~= nil
	for i = 1, (GetNumGuildMembers() or 0) do
		local r = CommDKP:NormalizeName((GetGuildRosterInfo(i)))
		if r then
			local lr = r:lower()
			if lr == ln or (not full and lr:match("^(%S+)") == ln) then
				if hit and hit ~= r then return n end           -- ambiguous: two members share the first name
				hit = r
			end
		end
	end
	return hit or n
end

-- AD-15.1: normalized names of the current group, including the player. Never uses name-as-unit APIs.
local function IsSecret(v) return issecretvalue ~= nil and v ~= nil and issecretvalue(v) end

function CommDKP:GetGroupRosterNames()
	local set = {}
	if IsInRaid() then
		for i = 1, (GetNumGroupMembers() or 0) do
			local rName = GetRaidRosterInfo(i)
			if rName and not IsSecret(rName) then
				local n = CommDKP:NormalizeName(rName); if n and n ~= "" then set[n] = true end
			end
		end
	elseif IsInGroup() then
		local me = CommDKP:GetPlayerName(); if me then set[me] = true end   -- party1..4 excludes the player
		for i = 1, (GetNumSubgroupMembers() or 0) do
			local full = CommDKP:GetUnitFullName("party" .. i)              -- AD-10.3 First+Last rule
			if full and not IsSecret(full) then
				local n = CommDKP:NormalizeName(full); if n and n ~= "" then set[n] = true end
			end
		end
	end
	return set
end

function CommDKP:IsPlayerInGroup(name)
	if not (IsInRaid() or IsInGroup()) then return false end
	if CommDKP:IsSelf(name) then return true end
	local n = CommDKP:NormalizeName(CommDKP:ResolveRosterName(name) or name)
	if not n or n == "" then return false end
	local roster = CommDKP:GetGroupRosterNames()
	if roster[n] then return true end
	-- Legacy bare first name ("Bank"): accept only if exactly one group member has that first name.
	if not n:find(" ", 1, true) then
		local hit
		for r in pairs(roster) do
			if r:match("^(%S+)") == n then if hit then return false end; hit = r end
		end
		return hit ~= nil
	end
	return false
end

-- AD-15.7: guild-roster online lookup (UnitIsConnected only resolves group units; standby players are not grouped).
function CommDKP:IsGuildMemberOnline(name)
	if not IsInGuild() then return false end
	local n = CommDKP:NormalizeName(name); if not n or n == "" then return false end
	for i = 1, (GetNumGuildMembers() or 0) do
		local rName, _, _, _, _, _, _, _, online = GetGuildRosterInfo(i)
		if rName and not IsSecret(rName) and CommDKP:SamePlayer(rName, n) then
			return online and true or false
		end
	end
	return false
end

-- AD-9.4: every .toc ## SavedVariables global that is passed through InitializeGuild
-- (InitializeCommDKPDB: CommDKP_DB, CommDKP_DKPTable, CommDKP_Loot, CommDKP_DKPHistory, CommDKP_MinBids,
--  CommDKP_MaxBids, CommDKP_Whitelist, CommDKP_Standby, CommDKP_Archive, CommDKP_Profiles).
core.GuildScopedSavedVariables = {
	"CommDKP_DB", "CommDKP_Loot", "CommDKP_DKPTable", "CommDKP_DKPHistory", "CommDKP_MinBids",
	"CommDKP_MaxBids", "CommDKP_Whitelist", "CommDKP_Standby", "CommDKP_Archive", "CommDKP_Profiles",
};

-------------------------------------
-- Shared backdrops (CDKP-005, AD-4 / AD-5.4)
-- Call sites reference keys only; the visual refresh (Decision 4) edits these entries, never call sites.
-- Pixel-identical legacy variants share one key (BackdropTemplate defaults missing insets to 0, and the
-- tileSize of a solid WHITE8X8 fill does not change pixels).
-------------------------------------
local MEDIA = "Interface\\AddOns\\CommunityDKPForever\\Media\\Textures\\"
local WHITE = "Interface\\Buttons\\WHITE8X8"
local NO_INSETS = { left = 0, right = 0, top = 0, bottom = 0 }

core.Backdrops = {
	-- 2px edgefile border on a solid fill: scrolling tables, table headers, edit boxes
	TableBorder  = { bgFile = WHITE, edgeFile = MEDIA.."edgefile.tga", tile = true, tileSize = 1, edgeSize = 2, insets = NO_INSETS },
	-- 3px edgefile border on a solid fill: main windows, dialogs, close-button containers
	Panel        = { bgFile = WHITE, edgeFile = MEDIA.."edgefile.tga", tile = true, tileSize = 1, edgeSize = 3, insets = NO_INSETS },
	-- 2px edgefile border, no fill: tab menu, bordered containers
	BorderOnly   = { edgeFile = MEDIA.."edgefile.tga", tile = true, tileSize = 1, edgeSize = 2, insets = NO_INSETS },
	-- 2px solid border on a solid fill: DKP mode edit boxes
	SolidEdge    = { bgFile = WHITE, edgeFile = "Interface\\ChatFrame\\ChatFrameBackground", tile = true, tileSize = 1, edgeSize = 2, insets = NO_INSETS },
	-- Blizzard slider bar (what the legacy sliders actually rendered; see AD-5 escalation)
	Slider       = { bgFile = "Interface\\Buttons\\UI-SliderBar-Background", edgeFile = "Interface\\Buttons\\UI-SliderBar-Border",
	                 tile = true, tileSize = 8, edgeSize = 8, insets = { left = 3, right = 3, top = 6, bottom = 6 } },
	-- fill only
	StatusBg     = { bgFile = "Interface\\ChatFrame\\ChatFrameBackground", tile = true },
	Fill         = { bgFile = WHITE, tile = true, insets = NO_INSETS },
	-- class graph bars
	GraphBar     = { bgFile = MEDIA.."graph-bar.tga", tile = false, insets = { left = 1, right = 1, top = 1, bottom = 1 } },
	-- zero-sum bank balance box
	BalanceBox   = { bgFile = WHITE, edgeFile = MEDIA.."slider-border.tga", tile = true, tileSize = 1, edgeSize = 2, insets = NO_INSETS },
	-- export window
	ExportDialog = { bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background", edgeFile = "Interface\\PVPFrame\\UI-Character-PVP-Highlight",
	                 edgeSize = 17, insets = { left = 8, right = 6, top = 8, bottom = 8 } },
}

-------------------------------------
-- Color palettes (CDKP-005, AD-6.3)
-- Keys in core.Backdrops hold geometry/textures only; colors are named by the frame's *role* and
-- resolved through core.Palette. Both palettes must define exactly the same role names.
--   Legacy  = the exact RGBA literals the legacy call sites used (pixel parity with CommunityDKP)
--   Forever = Gate 2 palette (ux_design_spec §2/§4; architect mapping, ux-designer may tune values here)
-------------------------------------
local OBSIDIAN = { 0.078, 0.078, 0.102 }
local DEEP     = { 0.051, 0.051, 0.071 }
local SLATE    = { 0.227, 0.227, 0.290 }
local ROW_ALT  = { 0.12,  0.12,  0.16  }
local ARCANE   = { 0.64,  0.21,  0.93  }
local function rgba(rgb, a) return { rgb[1], rgb[2], rgb[3], a } end

core.Palettes = {
	Legacy = {
		WindowBg          = { 0, 0, 0, 0.9 },
		WindowBgOpaque    = { 0, 0, 0, 1 },
		WindowBgSoft      = { 0, 0, 0, 0.8 },
		WindowBorder      = { 1, 1, 1, 1 },
		CloseBg           = { 0, 0, 0, 0.9 },
		CloseBorder       = { 1, 1, 1, 0.2 },
		TitleBg           = { 0, 0, 0, 0.9 },
		InputBg           = { 0, 0, 0, 0.9 },
		InputBgSoft       = { 0, 0, 0, 0.6 },
		InputBorder       = { 1, 1, 1, 0.6 },
		InputBorderAccent = { 0.12, 0.12, 0.34, 1 },
		ContainerBg       = { 0, 0, 0, 0.9 },
		ContainerBorder   = { 1, 1, 1, 0.5 },
		TableBg           = { 0, 0, 0, 0.4 },
		TableBgSubtle     = { 0, 0, 0, 0.2 },
		TableBorder       = { 1, 1, 1, 0.5 },
		TableBorderSubtle = { 1, 1, 1, 0.4 },
		HeaderBg          = { 0, 0, 0, 0.8 },
		HeaderBgSolid     = { 0, 0, 0, 1 },
		StatusBg          = { 0, 0, 0, 0.7 },
		Clear             = { 0, 0, 0, 0 },
		ExportBorder      = { 0, 0.44, 0.87, 0.5 },
	},
	Forever = {
		WindowBg          = rgba(OBSIDIAN, 0.93),
		WindowBgOpaque    = rgba(OBSIDIAN, 1),
		WindowBgSoft      = rgba(OBSIDIAN, 0.85),
		WindowBorder      = rgba(SLATE, 1),
		CloseBg           = rgba(OBSIDIAN, 0.93),
		CloseBorder       = rgba(SLATE, 0.6),
		TitleBg           = rgba(OBSIDIAN, 0.93),
		InputBg           = rgba(DEEP, 0.88),
		InputBgSoft       = rgba(DEEP, 0.75),
		InputBorder       = rgba(SLATE, 1),
		InputBorderAccent = rgba(ARCANE, 0.6),
		ContainerBg       = rgba(DEEP, 0.88),
		ContainerBorder   = rgba(SLATE, 1),
		TableBg           = rgba(DEEP, 0.88),
		TableBgSubtle     = rgba(DEEP, 0.6),
		TableBorder       = rgba(SLATE, 1),
		TableBorderSubtle = rgba(SLATE, 0.8),
		HeaderBg          = rgba(ROW_ALT, 0.9),
		HeaderBgSolid     = rgba(ROW_ALT, 1),
		StatusBg          = rgba(DEEP, 0.8),
		Clear             = { 0, 0, 0, 0 },
		ExportBorder      = { 0, 0.44, 0.87, 0.5 },
	},
}
core.DefaultPaletteName = "Forever"   -- Gate 2 approved by Vapok
core.Palette = core.Palettes[core.DefaultPaletteName]

-- Selects the active palette ("Legacy" / "Forever", case-insensitive) and persists the choice in
-- core.DB.defaults.Palette when the DB is available. Frames already built keep their colors until /reload.
-- Returns the canonical palette name, or nil for an unknown name.
function CommDKP:SetPalette(name)
	if type(name) ~= "string" then return nil end
	for paletteName, palette in pairs(core.Palettes) do
		if paletteName:lower() == name:lower() then
			core.Palette = palette
			if core.DB and core.DB.defaults then core.DB.defaults.Palette = paletteName end
			return paletteName
		end
	end
	return nil
end

-- bg/border accept a palette role name, nil (leave the template default), or an RGBA table
-- (only for data-driven colors such as class/quality colors, marked "-- data color" at the call site).
local function ResolveColor(c)
	if type(c) == "string" then
		local v = core.Palette[c]
		if not v then error("CommDKP: unknown palette role '"..c.."'", 3) end
		return v
	end
	return c
end

-- Applies a shared backdrop. Frames created without "BackdropTemplate" (XML/third-party frames) get the
-- mixin plus the OnSizeChanged hook the template would have installed, so borders re-layout on resize/scale.
function CommDKP:ApplyBackdrop(frame, key, bg, border)
	local info = core.Backdrops[key]
	if not info then error("CommDKP:ApplyBackdrop: unknown backdrop key '"..tostring(key).."'", 2) end
	local bgColor, borderColor = ResolveColor(bg), ResolveColor(border)
	if not frame.SetBackdrop then
		Mixin(frame, BackdropTemplateMixin)
		frame:HookScript("OnSizeChanged", frame.OnBackdropSizeChanged)
	end
	frame:SetBackdrop(info)
	if bgColor then frame:SetBackdropColor(unpack(bgColor)) end
	if borderColor then frame:SetBackdropBorderColor(unpack(borderColor)) end
end

-- Re-colors an existing backdrop by role (hover/selected/state changes after setup). nil leaves a color as is.
function CommDKP:SetBackdropRole(frame, bgRole, borderRole)
	local bgColor, borderColor = ResolveColor(bgRole), ResolveColor(borderRole)
	if bgColor then frame:SetBackdropColor(unpack(bgColor)) end
	if borderColor then frame:SetBackdropBorderColor(unpack(borderColor)) end
end

_G.CommDKPApi = CommDKPApi;

core.faction = UnitFactionGroup("player")


API_CLASSES = LOCALIZED_CLASS_NAMES_MALE;

core.CColors = {
	["UNKNOWN"] = { r = 0.627, g = 0.627, b = 0.627, hex = "A0A0A0" }
}
core.classes = {}

for class,friendlyClass in pairs(API_CLASSES) do
	local colorTable = {};
	local addColor = false;

	-- There appears to be no WoW API that lists out specific classes to a single faction
	-- Nor is there an API that identifies a specific class to a specific faction.
	-- I'd love to not hard code this though, but I seem to be out of luck.
	
	-- if core.faction == "Horde" then
	-- 	if class ~= "PALADIN" then
	-- 		addColor = true;
	-- 	end
	-- end

	-- if core.faction == "Alliance" then
	-- 	if class ~= "SHAMAN" then
	-- 		addColor = true;
	-- 	end
	-- end
	addColor = true;

	if addColor then
		colorTable.class = friendlyClass;
		colorTable.r, colorTable.g, colorTable.b, colorTable.hex = GetClassColor(class);

		core.CColors[class] = colorTable;
		table.insert(core.classes, class)
	end
end

--------------------------------------
-- Addon Defaults
--------------------------------------
local defaults = {
	theme = { r = 0.6823, g = 0.6823, b = 0.8666, hex = "aeaedd" },
	theme2 = { r = 1, g = 0.37, b = 0.37, hex = "ff6060" }
}

--------------------------------------
-- Encounter ID's Library
--------------------------------------


core.PriceSortButtons = {}
core.WorkingTable = {};       -- table of all entries from CommDKP:GetTable(CommDKP_DKPTable, true) that are currently visible in the window. From CommDKP:GetTable(CommDKP_DKPTable, true)
core.EncounterList = {      -- Event IDs must be in the exact same order as core.BossList declared in localization files
	MC = {
		663, 664, 665,
		666, 668, 667, 669, 
		670, 671, 672
	},
	BWL = {
		610, 611, 612,
		613, 614, 615, 616, 
		617
	},
	AQ = {
		709, 711, 712,
		714, 715, 717, 
		710, 713, 716
	},
	NAXX = {
		1107, 1110, 1116,
		1117, 1112, 1115, 
		1113, 1109, 1121,
		1118, 1111, 1108, 1120,
		1119, 1114
	},
	ZG = {
		787, 790, 793, 789, 784, 791,
		785, 792, 786, 788
	},
	AQ20 = {
		722, 721, 719, 718, 720, 723
	},
	ONYXIA = {1084},
	SCARLETENCLAVE = {          -- Forever 1.60.1 DungeonEncounter.db2, map 2856
		3185, 3187, 3196, 3186, 3197, 3188, 3190, 3189
	},
	WORLD = {                   -- Forever 1.60.1 DungeonEncounter.db2 (maps 2789, 2791, 2832, 2804)
		3027, 3026, 3111, 3112, 3114, 3113, 3079
	},
}

-- AD-11.2 / AD-12.2: Maps the EncounterList/BossList key to its index in core.ZoneList.
core.RaidZoneIndex = { MC = 1, BWL = 2, AQ = 3, NAXX = 4, ZG = 5, AQ20 = 6, ONYXIA = 7, WORLD = 8, SCARLETENCLAVE = 9 }
-- Order of the "Boss Killed" dropdown.
core.RaidMenuOrder = { "MC", "BWL", "AQ", "NAXX", "ONYXIA", "ZG", "AQ20", "SCARLETENCLAVE", "WORLD" }

core.CommDKPUI = {}        -- global storing entire Configuration UI to hide/show UI
core.MonVersion = "v3.2.9";
core.BuildNumber = 30209;
core.ReleaseNumber = 73
core.defaultTable = "__default";
core.SemVer = core.MonVersion.."-r"..tostring(core.ReleaseNumber);
core.UpgradeSchema = false;
core.TableWidth, core.TableRowHeight, core.TableNumRows, core.PriceNumRows = 500, 18, 27, 22; -- width, row height, number of rows
core.SelectedData = { player="none"};         -- stores data of clicked row for manipulation.
core.classFiltered = {};   -- tracks classes filtered out with checkboxes
core.IsOfficer = nil;
core.ShowState = false;
core.StandbyActive = false;
core.currentSort = "dkp"		-- stores current sort selection
core.BidInProgress = false;   -- flagged true if bidding in progress. else; false.
core.BidAuctioneer = false;
core.RaidInProgress = false;
core.RaidInPause = false;
core.InEncounter = false;     -- true between ENCOUNTER_START and ENCOUNTER_END (CDKP-003)
core.NumLootItems = 0;        -- updates on LOOT_OPENED event
core.Initialized = false
core.InitStart = false
core.CurrentRaidZone = ""
core.LastKilledBoss = ""
core.ArchiveActive = false
core.CurView = "all"
core.CurSubView = "all"
core.LastVerCheck = 0
core.CenterSort = "class";
core.OOD = false
core.RealmName = nil;
core.FactionName = nil;
core.RepairWorking = false;

function CommDKP:GetCColors(class)
	if core.CColors then 
	local c
		if class then
		c = core.CColors[class] or core.CColors["UNKNOWN"];
	else
		c = core.CColors
	end
		return c;
	else
		return false;
	end
end

function CommDKP_round(number, decimals)
		number = number or 0;
		decimals = decimals or 0;
		return tonumber((("%%.%df"):format(decimals)):format(number))
end

function CommDKP:ResetPosition()
	core.DB.bidpos = nil;
	core.DB.timerpos = nil;
	CommDKP.UIConfig:ClearAllPoints();
	CommDKP.UIConfig:SetPoint("CENTER", UIParent, "CENTER", -250, 100);
	CommDKP.UIConfig:SetSize(550, 590);
	CommDKP.UIConfig.TabMenu:Hide()
	CommDKP.UIConfig.expandtab:SetTexture("Interface\\AddOns\\CommunityDKPForever\\Media\\Textures\\expand-arrow");
	core.ShowState = false;
	CommDKP.BidTimer:ClearAllPoints()
	CommDKP.BidTimer:SetPoint("CENTER", UIParent)
	CommDKP:Print(L["POSITIONRESET"])
end

function CommDKP:GetGuildRank(player)
	local name, rank, rankIndex;
	local guildSize;

	if IsInGuild() then
		guildSize = GetNumGuildMembers();
		for i=1, guildSize do
			name, rank, rankIndex = GetGuildRosterInfo(i)
			name = StripRealm(name)  -- AD-7.7.2: realm suffix is optional; nil while the roster refreshes
			if name and name == player then
				return rank, rankIndex;
			end
		end
		return L["NOTINGUILD"];
	end
	return L["NOGUILD"]
end

function CommDKP:GetDefaultEntity()
	local entityProfile = {}
	entityProfile = {
		player = "",
		class = "None",
		dkp = 0,
		previous_dkp = 0,
		lifetime_gained = 0,
		lifetime_spent = 0,
		rank = 20,
		rankName = "None",
		spec = "No Spec Reported",
		role = "No Role Reported",
		version = "Unknown"
  };
  return entityProfile;
end

-- AD-10.6 (replaces AD-9.2.2): realm is NOT required -- GetRealmName() is "" permanently on Forever.
function CommDKP:IsIdentityReady()
	local faction = UnitFactionGroup("player")
	if not faction or faction == "" then return false end
	if not CommDKP:GetPlayerName() then return false end
	if IsInGuild() and not GetGuildInfo("player") then return false end
	return true
end

-- AD-9.2.2 / AD-10.6: keyed by GetRealmName() (not the normalized name) to match legacy SavedVariables.
-- Only the faction decides caching; an empty realm is valid, so the Forever key is "-Horde".
function CommDKP:GetRealmName()
	if not core.FactionName or core.FactionName == "" then
		local faction = UnitFactionGroup("player")
		core.RealmName = GetRealmName() or ""
		if faction and faction ~= "" then core.FactionName = faction end
	end
	return (core.RealmName or "") .. "-" .. (core.FactionName or "")
end

function CommDKP:GetGuildName()
	local name;

	if IsInGuild() then
		name = GetGuildInfo("player")  -- AD-9.2.3: unit token, not a character name (UNIT-001)
		if name then
			return name;
		else
			return L["NOGUILD"]
		end
	end
	return L["NOTINGUILD"];	
end

-- AD-9.4: one-time move of data written under the poisoned "-" realm key / "No Guild" guild key
-- (identity not yet loaded at init) into the real <Realm>-<Faction> / <Guild> bucket. Never overwrites.
-- An empty real bucket (created by an early GetTable/InitializeGuild) counts as absent.
function CommDKP:RepairIdentityBuckets()
	local realKey, realGuild = CommDKP:GetRealmName(), CommDKP:GetGuildName()
	if realKey == "-" or realGuild == L["NOGUILD"] or realGuild == L["NOTINGUILD"] then return end
	for _, tblName in ipairs(core.GuildScopedSavedVariables) do
		local sv = _G[tblName]; local bad = type(sv) == "table" and sv["-"]
		if type(bad) == "table" then
			for gi, gKey in ipairs({ L["NOGUILD"], "No Guild" }) do
				if bad[gKey] ~= nil and not (gi == 2 and gKey == L["NOGUILD"]) then
					sv[realKey] = sv[realKey] or {}
					local existing = sv[realKey][realGuild]
					if existing == nil or (type(existing) == "table" and next(existing) == nil) then
						sv[realKey][realGuild] = bad[gKey]; bad[gKey] = nil
					else
						CommDKP:PrintAlways("CommunityDKP Forever: "..tblName.." already has data for this guild; stale '-' bucket kept.")
					end
				end
			end
			if next(bad) == nil then sv["-"] = nil end
		end
	end
end

function CommDKP:GetGuildRankIndex(player)
	local name, rank;
	local guildSize,_,_ = GetNumGuildMembers();

	if IsInGuild() then
		for i=1, tonumber(guildSize) do
			name,_,rank = GetGuildRosterInfo(i)
			name = CommDKP:StripRealm(name)  -- AD-7.7.2: realm suffix is optional; nil while the roster refreshes
			if name and CommDKP:SamePlayer(name, player) and rank then  -- AD-10.3
				return rank+1;
			end
		end
		return false;
	end
end

-- AD-7.2: IsGuildLeader() first (independent of the roster); rank-index scan only as a fallback.
-- AD-7.7.2: named IsPlayerGuildLeader so it can't be confused with (or aliased over) the global IsGuildLeader.
-- AD-9.2.4: moved here from SelfTest.lua unchanged.
function CommDKP:IsPlayerGuildLeader()
  if not IsInGuild() then return false end
  if IsGuildLeader then return IsGuildLeader() and true or false end
  local ok, rank = pcall(CommDKP.GetGuildRankIndex, CommDKP, CommDKP:GetPlayerName())
  return ok and rank == 1
end

function CommDKP:CheckOfficer()      -- checks if user is an officer IF core.IsOfficer is empty. Use before checks against core.IsOfficer
	if not core.InitStart then 
		return
	end

	if core.IsOfficer == nil then      -- used as a redundency as it should be set on load in init.lua GUILD_ROSTER_UPDATE event
		if CommDKP:IsPlayerGuildLeader() then       -- automatically gives permissions above all settings if player is guild leader (AD-9.2.5)
			core.IsOfficer = true
			return;
		end
		if IsInGuild() then
			if #CommDKP:GetTable(CommDKP_Whitelist) > 0 then
				core.IsOfficer = false;
				for i=1, #CommDKP:GetTable(CommDKP_Whitelist) do
					if CommDKP:SamePlayer(CommDKP:GetTable(CommDKP_Whitelist)[i], CommDKP:GetPlayerName()) then
						core.IsOfficer = true;
					end
				end
			else
				if GetNumGuildMembers() == 0 then return end  -- AD-9.2.5: roster not loaded yet; leave IsOfficer nil so the next call retries
				local curPlayerRank = CommDKP:GetGuildRankIndex(CommDKP:GetPlayerName())
				if curPlayerRank then
					core.IsOfficer = C_GuildInfo.GuildControlGetRankFlags(curPlayerRank)[12]
				end
			end
		else
			core.IsOfficer = false;
		end
	end
	
end

function CommDKP:GetGuildRankGroup(index)                -- returns all members within a specific rank index as well as their index in the guild list (for use with GuildRosterSetPublicNote(index, "msg") and GuildRosterSetOfficerNote)
	local name, rank --, seed;                               -- local temp = CommDKP:GetGuildRankGroup(1)
	local group = {}                                      -- print(temp[1]["name"])
	local guildSize,_,_ = GetNumGuildMembers();

	if IsInGuild() then
		for i=1, tonumber(guildSize) do
			name,_,rank = GetGuildRosterInfo(i)
			--seed = CommDKP:RosterSeedExtract(i)
			name = CommDKP:StripRealm(name)  -- AD-9.2.6: realm suffix optional; nil while the roster refreshes
			if name and rank then
				rank = rank+1;
				if rank == index then
					--tinsert(group, { name = name, index = i, seed = seed })
					tinsert(group, { name = name, index = i })
				end
			end
		end
		return group;
	end
end

function CommDKP:CheckRaidLeader()
	local tempName,tempRank, subgroup, level, class, fileName, zone, online, isDead, role, isML, combatRole;

	for i=1, 40 do
		 
		 tempName, tempRank, subgroup, level, class, fileName, zone, online, isDead, role, isML, combatRole = GetRaidRosterInfo(i);

		if CommDKP:IsSelf(tempName) and tempRank == 2 then
			return true
		elseif CommDKP:IsSelf(tempName) and tempRank < 2 then
			return false
		end
	end
	return false;
end

function CommDKP:GetThemeColor()
	local c = {defaults.theme, defaults.theme2};
	return c;
end

function CommDKP:GetPlayerDKP(player)
	local search = CommDKP:Table_Search(CommDKP:GetTable(CommDKP_DKPTable, true), player)

	if search then
		return CommDKP:GetTable(CommDKP_DKPTable, true)[search[1][1]].dkp
	else
		return false;
	end
end

function CommDKP:PurgeLootHistory()     -- cleans old loot history beyond history limit to reduce native system load
	local limit = core.DB.defaults.HistoryLimit

	if #CommDKP:GetTable(CommDKP_Loot, true) > limit then
		while #CommDKP:GetTable(CommDKP_Loot, true) > limit do
			CommDKP:SortLootTable()
			local path = CommDKP:GetTable(CommDKP_Loot, true)[#CommDKP:GetTable(CommDKP_Loot, true)]

			if not CommDKP:GetTable(CommDKP_Archive, true)[path.player] then
				CommDKP:GetTable(CommDKP_Archive, true)[path.player] = { dkp=path.cost, lifetime_spent=path.cost, lifetime_gained=0 }
			else
				CommDKP:GetTable(CommDKP_Archive, true)[path.player].dkp = CommDKP:GetTable(CommDKP_Archive, true)[path.player].dkp + path.cost
				CommDKP:GetTable(CommDKP_Archive, true)[path.player].lifetime_spent = CommDKP:GetTable(CommDKP_Archive, true)[path.player].lifetime_spent + path.cost
			end
			if not CommDKP:GetTable(CommDKP_Archive, true).LootMeta or CommDKP:GetTable(CommDKP_Archive, true).LootMeta < path.date then
				CommDKP:GetTable(CommDKP_Archive, true).LootMeta = path.date
			end

			tremove(CommDKP:GetTable(CommDKP_Loot, true), #CommDKP:GetTable(CommDKP_Loot, true))
		end
	end
end

function CommDKP:PurgeDKPHistory()     -- purges old entries and stores relevant data in each users CommDKP:GetTable(CommDKP_Archive, true) entry (dkp, lifetime spent, and lifetime gained) 
	local limit = core.DB.defaults.DKPHistoryLimit

	if #CommDKP:GetTable(CommDKP_DKPHistory, true) > limit then
		while #CommDKP:GetTable(CommDKP_DKPHistory, true) > limit do
			CommDKP:SortDKPHistoryTable()
			local path = CommDKP:GetTable(CommDKP_DKPHistory, true)[#CommDKP:GetTable(CommDKP_DKPHistory, true)]

			local players = {strsplit(",", strsub(path.players, 1, -2))}
			local dkp = {strsplit(",", path.dkp)}

			if #dkp == 1 then
				for i=1, #players do
					dkp[i] = tonumber(dkp[1])
				end
			else
				for i=1, #dkp do
					dkp[i] = tonumber(dkp[i])
				end
			end

			for i=1, #players do
				if not CommDKP:GetTable(CommDKP_Archive, true)[players[i]] then
					if ((dkp[i] > 0 and not path.deletes) or (dkp[i] < 0 and path.deletes)) and not strfind(path.dkp, "%-%d*%.?%d+%%") then
						CommDKP:GetTable(CommDKP_Archive, true)[players[i]] = { dkp=dkp[i], lifetime_spent=0, lifetime_gained=dkp[i] }
					else
						CommDKP:GetTable(CommDKP_Archive, true)[players[i]] = { dkp=dkp[i], lifetime_spent=0, lifetime_gained=0 }
					end
				else
					local dkpAmount = dkp[i] or 0
					CommDKP:GetTable(CommDKP_Archive, true)[players[i]].dkp = CommDKP:GetTable(CommDKP_Archive, true)[players[i]].dkp + dkpAmount
					if ((dkpAmount > 0 and not path.deletes) or (dkpAmount < 0 and path.deletes)) and not strfind(path.dkp, "%-%d*%.?%d+%%") then 	--lifetime gained if dkp addition and not a delete entry, dkp decrease and IS a delete entry
						CommDKP:GetTable(CommDKP_Archive, true)[players[i]].lifetime_gained = CommDKP:GetTable(CommDKP_Archive, true)[players[i]].lifetime_gained + path.dkp 				--or is NOT a decay
					end
				end
			end
			if not CommDKP:GetTable(CommDKP_Archive, true).DKPMeta or CommDKP:GetTable(CommDKP_Archive, true).DKPMeta < path.date then
				CommDKP:GetTable(CommDKP_Archive, true).DKPMeta = path.date
			end

			tremove(CommDKP:GetTable(CommDKP_DKPHistory, true), #CommDKP:GetTable(CommDKP_DKPHistory, true))
		end
	end
end

function CommDKP:FormatTime(time)
	local str = date("%y/%m/%d %H:%M:%S", time)

	return str;
end

function CommDKP:Print(...)        --print function to add "CommunityDKP:" to the beginning of print() outputs.
	if core.DB == nil or not core.DB.defaults.SuppressNotifications then
		local defaults = CommDKP:GetThemeColor();
		local prefix = string.format("|cff%s%s|r|cff%s", defaults[1].hex:upper(), "CommunityDKP:", defaults[2].hex:upper());
		local suffix = "|r";

		for i = 1, NUM_CHAT_WINDOWS do
			local name = GetChatWindowInfo(i)

			if core.DB == nil or core.DB.defaults.ChatFrames[name] then
				-- AD-7.7.1: a non-final `...` is cut to one value in Lua 5.1, so join the varargs first.
				_G["ChatFrame"..i]:AddMessage(prefix.." "..strjoin(" ", tostringall(...)).." "..suffix);
			end
		end
	end
end

-- AD-7.7: for output the user explicitly asked for (/dkp test). Ignores SuppressNotifications;
-- falls back to DEFAULT_CHAT_FRAME if no configured frame matched. Never call it from event handlers.
-- Read-only with respect to saved settings: it never changes core.DB.defaults.
function CommDKP:PrintAlways(...)
	-- CDKP-006 F6-b (AD-8.4): must work before core.DB exists (init failure path).
	local text = strjoin(" ", tostringall(...))
	local okC, msg = pcall(function()
		local c = CommDKP:GetThemeColor()
		return string.format("|cff%sCommunityDKP:|r|cff%s %s|r", c[1].hex:upper(), c[2].hex:upper(), text)
	end)
	if not okC then msg = "|cff00cc66CommunityDKP:|r " .. text end
	local sent = false
	if core.DB and core.DB.defaults and core.DB.defaults.ChatFrames then
		for i = 1, NUM_CHAT_WINDOWS do
			local name = GetChatWindowInfo(i)
			if name and core.DB.defaults.ChatFrames[name] and _G["ChatFrame"..i] then
				_G["ChatFrame"..i]:AddMessage(msg); sent = true
			end
		end
	end
	if not sent then
		local frame = DEFAULT_CHAT_FRAME or _G["ChatFrame1"]
		if frame then frame:AddMessage(msg) end
	end
end

-------------------------------------
-- CommDKP:SendChat (CDKP-004, AD-3): single entry point for all first-party chat output.
-- CommDKP:IsMessagingRestricted() is provided by Modules/CommGate.lua (resolved at call time).
-------------------------------------
-- Channels that need a hardware event outside instances; never queue them.
local DIRECT_ONLY = { SAY = true, YELL = true, CHANNEL = true }

function CommDKP:SendChat(msg, chatType, languageID, target, prio)
	if type(msg) ~= "string" or msg == "" then return false end
	if issecretvalue and (issecretvalue(msg) or (target ~= nil and issecretvalue(target))) then return false end
	-- AD-14.3: route group chat to a channel that exists; never raise "not in a raid/party" errors.
	local requested = chatType
	if chatType == "RAID_WARNING" and not (IsInRaid() and (UnitIsGroupLeader("player") or UnitIsGroupAssistant("player"))) then
		chatType = "RAID"
	end
	if chatType == "RAID" and not IsInRaid() then chatType = "PARTY" end
	if chatType == "PARTY" and not IsInGroup() then
		local guildOn = core.DB and core.DB.modes and core.DB.modes.channels and core.DB.modes.channels.guild
		if requested ~= "PARTY" and IsInGuild() and guildOn then
			chatType = "GUILD"
		else
			CommDKP:Print(msg); return true                 -- solo: show it locally only
		end
	end
	if chatType == "WHISPER" and target and CommDKP:IsSelf(target) then
		CommDKP:Print(msg); return true                   -- AD-14.2 loopback replies
	end
	if CommDKP:IsMessagingRestricted() then
		CommDKP:Print(L["CHATLOCKED"])            -- "Announcement suppressed during encounter."
		return false
	end
	if DIRECT_ONLY[chatType] then
		local send = (C_ChatInfo and C_ChatInfo.SendChatMessage) or SendChatMessage
		send(msg, chatType, languageID, target)
	else
		ChatThrottleLib:SendChatMessage(prio or "NORMAL", "CommDKP", msg, chatType, languageID, target)
	end
	return true
end

function CommDKP:CreateButton(point, relativeFrame, relativePoint, xOffset, yOffset, text)
	local btn = CreateFrame("Button", nil, relativeFrame, "CommunityDKPButtonTemplate")
	btn:SetPoint(point, relativeFrame, relativePoint, xOffset, yOffset);
	btn:SetSize(100, 30);
	btn:SetText(text);
	btn:GetFontString():SetTextColor(1, 1, 1, 1)
	btn:SetNormalFontObject("CommDKPSmallCenter");
	btn:SetHighlightFontObject("CommDKPSmallCenter");
	return btn; 
end

function CommDKP:BroadcastTimer(seconds, ...)       -- broadcasts timer and starts it natively
	if IsInRaid() and core.IsOfficer == true then
		local title = ...;
		if not tonumber(seconds) then       -- cancels the function if the command was entered improperly (eg. no number for time)
			CommDKP:Print(L["INVALIDTIMER"]);
			return;
		end
		CommDKP:StartTimer(seconds, ...)
		CommDKP.Sync:SendData("CommDKPCommand", "StartTimer#"..seconds.."#"..title)
	end
end

function CommDKP:CreateContainer(parent, name, header)

	local f;

	f = CreateFrame("Frame", "CommDKP"..name, parent, "BackdropTemplate");

	
	CommDKP:ApplyBackdrop(f, "BorderOnly", "ContainerBg", "ContainerBorder")
	f.header = CreateFrame("Frame", "CommDKP"..name.."Header", f, "BackdropTemplate")
	
	CommDKP:ApplyBackdrop(f.header, "Fill", "HeaderBgSolid")
	f.header:SetPoint("LEFT", f, "TOPLEFT", 20, 0)
	f.header.text = f.header:CreateFontString(nil, "OVERLAY")
	f.header.text:SetFontObject("CommDKPSmallCenter");
	f.header.text:SetPoint("CENTER", f.header, "CENTER", 0, 0);
	f.header.text:SetText(header);
	f.header:SetWidth(f.header.text:GetWidth() + 30)
	f.header:SetHeight(f.header.text:GetHeight() + 4)

	return f;
end

-- UX §10.1.1: native template title accessor (shared by every BasicFrameTemplateWithInset window).
function CommDKP:SetForeverTitle(f, text)
	local t = f.TitleLabel or f.TitleText or (f.TitleContainer and f.TitleContainer.TitleText)
	if not t then
		t = f:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
		t:SetPoint("CENTER", f.TitleBg or f, f.TitleBg and "CENTER" or "TOP", 0, f.TitleBg and 0 or -12)
	end
	t:SetText(text); f.TitleLabel = t
	return t
end

-- UX §10.1.2: native secondary window (NineSlice border, metallic title, red CloseButton, InsetBg).
-- opts: { group = "bidding" | nil, escape (default true), floater (default true), movable (default true) }
-- Created hidden: the first Show() fires OnShow -> floater registry focus (§10.1.3).
-- NOTE: callers must use HookScript (not SetScript) for OnShow/OnHide/OnMouseDown afterwards,
-- otherwise SetScript would wipe the registry hooks.
function CommDKP:CreateForeverWindow(name, w, h, title, opts)
	opts = opts or {}
	local f = CreateFrame("Frame", name, UIParent, "BasicFrameTemplateWithInset")
	f:SetSize(w, h)
	f:SetClampedToScreen(true); f:SetToplevel(true)
	f:SetFrameStrata("MEDIUM")                           -- real strata assigned by FocusWindow
	f:EnableMouse(true)
	if opts.movable ~= false then
		f:SetMovable(true); f:RegisterForDrag("LeftButton")
		f:SetScript("OnDragStart", f.StartMoving)        -- OnMouseDown (registry hook) already focused it
		f:SetScript("OnDragStop",  f.StopMovingOrSizing)
	end
	if opts.escape ~= false and name then
		local present = false
		for _, n in ipairs(UISpecialFrames) do
			if n == name then present = true; break end
		end
		if not present then tinsert(UISpecialFrames, name) end
	end
	CommDKP:SetForeverTitle(f, title)
	f.ContentInset = f.InsetBg or f.Inset or f
	f:Hide()
	if opts.floater ~= false and CommDKP.RegisterFloater then CommDKP:RegisterFloater(f, opts.group) end
	return f, f.ContentInset
end

function CommDKP:StartTimer(seconds, ...)
	local duration = tonumber(seconds)
	local alpha = 1;

	if not tonumber(seconds) then       -- cancels the function if the command was entered improperly (eg. no number for time)
		CommDKP:Print(L["INVALIDTIMER"]);
		return;
	end

	CommDKP.BidTimer = CommDKP.BidTimer or CommDKP:CreateTimer();    -- recycles timer frame so multiple instances aren't created
	CommDKP.BidTimer:SetShown(not CommDKP.BidTimer:IsShown())         -- shows if not shown
	if CommDKP.BidTimer:IsShown() == false then                    -- terminates function if hiding timer
		return;
	end

	CommDKP.BidTimer:SetMinMaxValues(0, duration)
	CommDKP.BidTimer.timerTitle:SetText(...)
	PlaySound(8959)

	if core.DB.timerpos then
		local a = core.DB.timerpos                   -- retrieves timer's saved position from SavedVariables
		CommDKP.BidTimer:SetPoint(a.point, a.relativeTo, a.relativePoint, a.x, a.y)
	else
		CommDKP.BidTimer:SetPoint("CENTER")                      -- sets to center if no position has been saved
	end

	local timer = 0             -- timer starts at 0
	local timerText;            -- count down when below 1 minute
	local modulo                -- remainder after divided by 60
	local timerMinute           -- timerText / 60 to get minutes.
	local audioPlayed = false;  -- so audio only plays once
	local expiring;             -- determines when red blinking bar starts. @ 30 sec if timer > 120 seconds, @ 10 sec if below 120 seconds

	CommDKP.BidTimer:SetScript("OnUpdate", function(self, elapsed)   -- timer loop
		timer = timer + elapsed
		timerText = CommDKP_round(duration - timer, 1)
		if tonumber(timerText) > 60 then
			timerMinute = math.floor(tonumber(timerText) / 60, 0);
			modulo = tonumber(timerText) % 60;
			if tonumber(modulo) < 10 then modulo = "0"..modulo end
			CommDKP.BidTimer.timertext:SetText(timerMinute..":"..modulo)
		else
			CommDKP.BidTimer.timertext:SetText(timerText)
		end
		if duration >= 120 then
			expiring = 30;
		else
			expiring = 10;
		end
		if tonumber(timerText) < expiring then
			if audioPlayed == false then
				PlaySound(23639);
			end
			if tonumber(timerText) < 10 then
				audioPlayed = true
				StopSound(23639)
			end
			CommDKP.BidTimer:SetStatusBarColor(0.8, 0.1, 0, alpha)
			if alpha > 0 then
				alpha = alpha - 0.005
			elseif alpha <= 0 then
				alpha = 1
			end
		else
			CommDKP.BidTimer:SetStatusBarColor(0, 0.8, 0)
		end
		self:SetValue(timer)
		if timer >= duration then
			CommDKP.BidTimer:SetScript("OnUpdate", nil)
			CommDKP.BidTimer:Hide();
		end
	end)
end

function CommDKP:StatusVerify_Update()
	if (CommDKP.UIConfig and not CommDKP.UIConfig:IsShown()) or 
	   (#CommDKP:GetTable(CommDKP_DKPHistory, true, CommDKP:GetCurrentTeamIndex()) == 0 and #CommDKP:GetTable(CommDKP_Loot, true, CommDKP:GetCurrentTeamIndex()) == 0) then
		-- blocks update if dkp window is closed. Updated when window is opened anyway
		return;
	end

	if IsInGuild() and core.Initialized then
		core.OOD = false

		local missing = {}

		if (CommDKP:GetTable(CommDKP_Loot, true, CommDKP:GetCurrentTeamIndex()).seed and strfind(CommDKP:GetTable(CommDKP_Loot, true, CommDKP:GetCurrentTeamIndex()).seed, "-")) or
		   (CommDKP:GetTable(CommDKP_DKPHistory, true, CommDKP:GetCurrentTeamIndex()).seed and strfind(CommDKP:GetTable(CommDKP_DKPHistory, true, CommDKP:GetCurrentTeamIndex()).seed, "-"))
		then

			local search_dkp = CommDKP:Table_Search(CommDKP:GetTable(CommDKP_DKPHistory, true, CommDKP:GetCurrentTeamIndex()), CommDKP:GetTable(CommDKP_DKPHistory, true, CommDKP:GetCurrentTeamIndex()).seed, "index")
			local search_loot = CommDKP:Table_Search(CommDKP:GetTable(CommDKP_Loot, true, CommDKP:GetCurrentTeamIndex()), CommDKP:GetTable(CommDKP_Loot, true, CommDKP:GetCurrentTeamIndex()).seed, "index")
	
			if not search_dkp then
				core.OOD = true
				local officer1, date1 = strsplit("-", CommDKP:GetTable(CommDKP_DKPHistory, true, CommDKP:GetCurrentTeamIndex()).seed)
				if (date1 and tonumber(date1) < (time() - 1209600)) or not CommDKP:ValidateSender(officer1) then   -- does not consider if claimed entry was made more than two weeks ago or name is not an officer
					core.OOD = false
				else
					date1 = date("%m/%d/%y %H:%M:%S", tonumber(date1))
					missing[officer1] = date1 			-- if both missing seeds identify the same officer, it'll only list once
				end
			end
			
			if not search_loot and not core.OOD then
				core.OOD = true
				local officer2, date2 = strsplit("-", CommDKP:GetTable(CommDKP_Loot, true, CommDKP:GetCurrentTeamIndex()).seed)
				if (date2 and tonumber(date2) < (time() - 1209600)) or not CommDKP:ValidateSender(officer2) then   -- does not consider if claimed entry was made more than two weeks ago or name is not an officer
					core.OOD = false
				else
					date2 = date("%m/%d/%y %H:%M:%S", tonumber(date2))
					missing[officer2] = date2
				end
			end
		end

		if not core.OOD then
			CommDKP.DKPTable.SeedVerifyIcon:SetTexture("Interface\\AddOns\\CommunityDKPForever\\Media\\Textures\\up-to-date")
			CommDKP.DKPTable.SeedVerify:SetScript("OnEnter", function(self)
				GameTooltip:SetOwner(self, "ANCHOR_RIGHT", 0, 0);
				GameTooltip:SetText(L["DKPSTATUS"], 0.25, 0.75, 0.90, 1, true);
				GameTooltip:AddLine(L["ALLTABLES"].." |cff00ff00"..L["UPTODATE"].."|r.", 1.0, 1.0, 1.0, false);
				if core.IsOfficer then
					GameTooltip:AddLine(" ")
					GameTooltip:AddLine("|cffff0000"..L["CLICKQUERYGUILD"].."|r", 1.0, 1.0, 1.0, true);
				end
				GameTooltip:Show()
			end)
			CommDKP.DKPTable.SeedVerify:SetScript("OnLeave", function(self)
				GameTooltip:Hide()
			end)

			return true;
		else
			CommDKP.DKPTable.SeedVerifyIcon:SetTexture("Interface\\AddOns\\CommunityDKPForever\\Media\\Textures\\out-of-date")
			CommDKP.DKPTable.SeedVerify:SetScript("OnEnter", function(self)
				GameTooltip:SetOwner(self, "ANCHOR_RIGHT", 0, 0);
				GameTooltip:SetText(L["DKPSTATUS"], 0.25, 0.75, 0.90, 1, true);
				if #CommDKP:GetTable(CommDKP_Loot, true, CommDKP:GetCurrentTeamIndex()) == 0 and #CommDKP:GetTable(CommDKP_DKPHistory, true, CommDKP:GetCurrentTeamIndex()) == 0 then
					GameTooltip:AddLine(L["TABLESAREEMPTY"], 1.0, 1.0, 1.0, false);
				else
					GameTooltip:AddLine(L["ONETABLEOOD"].." |cffff0000"..L["OUTOFDATE"].."|r.", 1.0, 1.0, 1.0, false);
				end
				GameTooltip:AddLine(" ")
				GameTooltip:AddLine(L["MISSINGENT"]..":", 0.25, 0.75, 0.90, 1, true);
				GameTooltip:AddLine(" ")
				GameTooltip:AddDoubleLine(L["PLAYER"], L["CREATED"],1,1,1,1,1,1)
				for k,v in pairs(missing) do
					local classSearch = CommDKP:Table_Search(CommDKP:GetTable(CommDKP_DKPTable, true, CommDKP:GetCurrentTeamIndex()), k)

					if classSearch then
						c = CommDKP:GetCColors(CommDKP:GetTable(CommDKP_DKPTable, true, CommDKP:GetCurrentTeamIndex())[classSearch[1][1]].class)
					else
						c = { hex="ffffffff" }
					end
					GameTooltip:AddDoubleLine("|c"..c.hex..k.."|r",v,1,1,1,1,1,1);
				end
				if core.IsOfficer then
					GameTooltip:AddLine(" ")
					GameTooltip:AddLine("|cffff0000"..L["CLICKQUERYGUILD"].."|r", 1.0, 1.0, 1.0, true);
				end
				GameTooltip:Show()
			end)
			CommDKP.DKPTable.SeedVerify:SetScript("OnLeave", function(self)
				GameTooltip:Hide()
			end)

			return false;
		end
	elseif core.Initialized then
		CommDKP.DKPTable.SeedVerify:SetScript("OnEnter", function(self)
			GameTooltip:SetOwner(self, "ANCHOR_RIGHT", 0, 0);
			GameTooltip:SetText(L["DKPSTATUS"], 0.25, 0.75, 0.90, 1, true);
			GameTooltip:AddLine(L["CURRNOTINGUILD"], 1.0, 1.0, 1.0, true);
			GameTooltip:Show()
		end)
		CommDKP.DKPTable.SeedVerify:SetScript("OnLeave", function(self)
			GameTooltip:Hide()
		end)

		return false;
	end
end

-------
-- TEAM FUNCTIONS
-------
function CommDKP:tablelength(T)
	local count = 0
	for _ in pairs(T) do
		count = count + 1 
	end
	return count
end

function CommDKP:GetCurrentTeamIndex() 
	local _tmpString = CommDKP:GetTable(CommDKP_DB, false)["defaults"]["CurrentTeam"] or "0"
	return _tmpString
end

function CommDKP:GetCurrentTeamName()
	local _string = "Unguilded";
	local teams = CommDKP:GetTable(CommDKP_DB, false)["teams"];

	if CommDKP:tablelength(teams) > 0 then
		_string = CommDKP:GetTable(CommDKP_DB, false)["teams"][CommDKP:GetCurrentTeamIndex()].name
	end

	return _string
end

function CommDKP:GetTeamName(index)
	local _string = "Unguilded";
	if index == nil then return _string end
	local teamName = CommDKP:GetTable(CommDKP_DB, false)["teams"][index]["name"];

	if teamName == nil then return "no team" end;

	return teamName;
end

function CommDKP:GetGuildTeamList(asObject) 
	local asObject = asObject or false
	local _list = {};
	local _tmp = CommDKP:GetTable(CommDKP_DB, false)["teams"]

	for k,v in pairs(_tmp) do
		if(type(v) == "table") then
			if asObject then
				local team = v;
				team["index"] = tonumber(k);
				table.insert(_list, team);
			else
				table.insert(_list, {tonumber(k), v.name})
			end
		end
	end
	-- so, because team "index" is a string Lua doesn't give a flying fuck
	-- about order of adding elements to "string" indexed table so we have to unfuck it
	table.sort(_list,  
		function(a, b)
			if asObject then
				return a.index < b.index
			else
				return a[1] < b[1]
			end
		end
	)

	return _list
end

function CommDKP:FormatPriceTable(minBids, convertToTable)
	minBids = minBids or CommDKP:GetTable(CommDKP_MinBids, true);
	convertToTable = convertToTable or false; --false means it will convert to an array
	local priceTable = {}

	if withIds then
		for i=1, #minBids do
			priceTable[minBids[i].itemID] = minBids[i];
		end
	else
		for key, value in pairs(minBids) do
			tinsert(priceTable, value);
		end
	end
	return priceTable;
end

-- moved to core from ManageEntries as this is called from comm.lua aswell
function CommDKP:SetCurrentTeam(index)
	CommDKP:GetTable(CommDKP_DB, false)["defaults"]["CurrentTeam"] = tostring(index);
	CommDKP:StatusVerify_Update();
	LibDD:UIDropDownMenu_SetText(CommDKP.UIConfig.TeamViewChangerDropDown, CommDKP:GetCurrentTeamName());

	-- reset dkp table and update it
	core.WorkingTable = CommDKP:GetTable(CommDKP_DKPTable, true);
	core.PriceTable	= CommDKP:FormatPriceTable();

	CommDKP:DKPTable_Update();

	-- reset dkp history table and update it
	CommDKP:DKPHistory_Update(true);
	-- reset loot history
	CommDKP:LootHistory_Update(L["NOFILTER"]);
	-- update class graph
	CommDKP:ClassGraph_Update();
	-- update price table
	CommDKP:PriceTable_Update(0);
	-- broadcast Talents and Roles
	CommDKP:SendTalentsAndRole();
end

function CommDKP:SendTalentsAndRole()

	if not CommDKP:GetPlayerName() then return end  -- AD-10.4: identity not loaded yet
	--Does a Profile Exist? If no, exit, nothing to do here.
	local oldProfile = CommDKP:Table_Search(CommDKP:GetTable(CommDKP_DKPTable, true), CommDKP:GetPlayerName(), "player")
	local newProfile = CommDKP:GetTable(CommDKP_Profiles, true)[CommDKP:GetPlayerName()]
	if newProfile == nil and not oldProfile then
		return;
	end

	-- talents check
	local TalTrees={}; table.insert(TalTrees, {GetTalentTabInfo(1)}); table.insert(TalTrees, {GetTalentTabInfo(2)}); table.insert(TalTrees, {GetTalentTabInfo(3)});
	local talBuild = "("..TalTrees[1][3].."/"..TalTrees[2][3].."/"..TalTrees[3][3]..")"
	local talRole;
	table.sort(TalTrees, function(a, b)
		return a[3] > b[3]
	end) 

	talBuild = TalTrees[1][1].." "..talBuild;
	talRole = TalTrees[1][4];

	local profile = newProfile or CommDKP:GetDefaultEntity();
	profile.player=CommDKP:GetPlayerName();
	profile.version=core.SemVer;

	CommDKP:GetTable(CommDKP_Profiles, true)[CommDKP:GetPlayerName()] = profile;

	if oldProfile then
		CommDKP:GetTable(CommDKP_DKPTable, true)[oldProfile[1][1]].version = core.SemVer;
	end

	CommDKP.Sync:SendData("CDKProfileSend", profile)
	CommDKP.Sync:SendData("CommDKPTalents", talBuild)
	CommDKP.Sync:SendData("CommDKPRoles", talRole)

	table.wipe(TalTrees);
end

-------
-- TEAM FUNCTIONS END
-------

-------------------------------------
-- Recursively searches tar (table) for val (string) as far as 4 nests deep (use field only if you wish to search a specific key IE: CommDKP:GetTable(CommDKP_DKPTable, true), "Vapok", "player" would only search for Vapok in the player key)
-- returns an indexed array of the keys to get to searched value
-- First key is the result (ie if it's found 8 times, it will return 8 tables containing results).
-- Second key holds the path to the value searched. So to get to a player searched on DKPTable that returned 1 result, CommDKP:GetTable(CommDKP_DKPTable, true)[search[1][1]][search[1][2]] would point at the "player" field
-- if the result is 1 level deeper, it would be CommDKP:GetTable(CommDKP_DKPTable, true)[search[1][1]][search[1][2]][search[1][3]].  CommDKP:GetTable(CommDKP_DKPTable, true)[search[2][1]][search[2][2]][search[2][3]] would locate the second return, if there is one.
-- use to search for players in SavedVariables. Only two possible returns is the table or false.
-------------------------------------
function CommDKP:Table_Search(tar, val, field, limit)
	local value = string.upper(tostring(val));
	local location = {}
	local tableLimit = limit or -1;
	for k,v in pairs(tar) do
		if(type(v) == "table") then
			local temp1 = k
			for k,v in pairs(v) do
				if(type(v) == "table") then
					local temp2 = k;
					for k,v in pairs(v) do
						if(type(v) == "table") then
							local temp3 = k
							for k,v in pairs(v) do
								if string.upper(tostring(v)) == value then
									if field then
										if k == field then
											tinsert(location, {temp1, temp2, temp3, k} )
											if tableLimit ~= -1 and #location >= tableLimit then
												return location;
											end;
										end
									else
										tinsert(location, {temp1, temp2, temp3, k} )
										if tableLimit ~= -1 and #location >= tableLimit then
											return location;
										end;
									end
								end;
							end
						end
						if string.upper(tostring(v)) == value then
							if field then
								if k == field then
									tinsert(location, {temp1, temp2, k} )
									if tableLimit ~= -1 and #location >= tableLimit then
										return location;
									end;
								end
							else
								tinsert(location, {temp1, temp2, k} )
								if tableLimit ~= -1 and #location >= tableLimit then
									return location;
								end;
							end
						end;
					end
				end
				if string.upper(tostring(v)) == value then
					if field then
						if k == field then
							tinsert(location, {temp1, k} )
							if tableLimit ~= -1 and #location >= tableLimit then
								return location;
							end;
						end
					else
						tinsert(location, {temp1, k} )
						if tableLimit ~= -1 and #location >= tableLimit then
							return location;
						end;
					end
				end;
			end
		end
		if string.upper(tostring(v)) == value then
			if field then
				if k == field then
					tinsert(location, k)
					if tableLimit ~= -1 and #location >= tableLimit then
						return location;
					end;
				end
			else
				tinsert(location, k)
				if tableLimit ~= -1 and #location >= tableLimit then
					return location;
				end;
			end
		end;
	end
	if (#location > 0) then
		return location;
	else
		return false;
	end
end

-------------------------------------
-- AD-11.3: Encounter resolution (static EncounterList + discovered core.DB.CustomEncounters)
-------------------------------------
local function IsSecretValue(v)
	return issecretvalue ~= nil and v ~= nil and issecretvalue(v) and true or false
end

-- Pure lookup. Returns zoneName, bossName, source ("static" | "custom"), or nil.
function CommDKP:ResolveEncounter(id)
	if id == nil or IsSecretValue(id) then return nil end
	local search = CommDKP:Table_Search(core.EncounterList, id)
	if search and search[1] then
		local key, idx = search[1][1], search[1][2]
		local zi, list = core.RaidZoneIndex[key], core.BossList[key]
		if zi and list and list[idx] then return core.ZoneList[zi], list[idx], "static" end
	end
	local nid, ce = tonumber(id), core.DB and core.DB.CustomEncounters
	if nid and type(ce) == "table" then
		for zone, bosses in pairs(ce) do
			if type(bosses) == "table" and type(bosses[nid]) == "string" then return zone, bosses[nid], "custom" end
		end
	end
	return nil
end

-- Returns zoneName, bossName, source, isNew, or nil when the kill is not a DKP raid encounter.
function CommDKP:ResolveOrRegisterEncounter(encounterID, encounterName)
	if IsSecretValue(encounterID) or IsSecretValue(encounterName) then return nil end
	local zone, boss, source = CommDKP:ResolveEncounter(encounterID)
	if zone then return zone, boss, source, false end

	if type(encounterName) ~= "string" or encounterName == "" then return nil end
	for _, name in ipairs(core.BossList.WORLD or {}) do		-- name fallback if Forever renumbers a world boss
		if name == encounterName then return core.ZoneList[core.RaidZoneIndex.WORLD], name, "world", false end
	end

	local nid = tonumber(encounterID)
	if not nid or not core.DB then return nil end
	local _, instanceType = IsInInstance()
	if instanceType == "raid" then
		zone = GetRealZoneText()
		if not zone or zone == "" then zone = (GetInstanceInfo()) end
		if not zone or zone == "" then zone = "Forever Raid" end
	elseif instanceType == nil or instanceType == "none" then
		zone = core.ZoneList[core.RaidZoneIndex.WORLD]				-- new outdoor (world) boss
	else
		return nil													-- party, scenario, pvp, arena: no DKP
	end

	core.DB.CustomEncounters = core.DB.CustomEncounters or {}
	core.DB.CustomEncounters[zone] = core.DB.CustomEncounters[zone] or {}
	core.DB.CustomEncounters[zone][nid] = encounterName
	return zone, encounterName, "custom", true
end

-- Sets the boss context everywhere. Safe to call before CreateMenu() has built ConfigTab2.
function CommDKP:ApplyBossContext(zone, boss)
	core.CurrentRaidZone, core.LastKilledBoss = zone, boss
	core.DB.bossargs.CurrentRaidZone, core.DB.bossargs.LastKilledBoss = zone, boss
	local dd = CommDKP.ConfigTab2 and CommDKP.ConfigTab2.BossKilledDropdown
	if dd and dd.RefreshBossContext then dd:RefreshBossContext() end
end

-- Discovered zones that are not static raid zones, sorted by name.
function CommDKP:GetCustomEncounterZones()
	local out, ce, static = {}, core.DB and core.DB.CustomEncounters, {}
	if type(ce) ~= "table" then return out end
	for i = 1, #core.ZoneList do static[core.ZoneList[i]] = true end
	for zone, bosses in pairs(ce) do
		if not static[zone] and type(bosses) == "table" and next(bosses) then out[#out + 1] = zone end
	end
	table.sort(out)
	return out
end

-- Discovered bosses of one zone as { {id=, name=}, ... }, sorted by ID. Names in skipNames are left out.
function CommDKP:GetCustomBosses(zone, skipNames)
	local out, ce = {}, core.DB and core.DB.CustomEncounters
	local bosses = type(ce) == "table" and ce[zone]
	if type(bosses) ~= "table" then return out end
	for id, name in pairs(bosses) do
		if type(id) == "number" and type(name) == "string" and not (skipNames and skipNames[name]) then
			out[#out + 1] = { id = id, name = name }
		end
	end
	table.sort(out, function(a, b) return a.id < b.id end)
	return out
end

-------------------------------------
-- AD-12.5: Confirm Award zone/boss helpers
-------------------------------------
-- Static raid key for a localized zone name, or nil.
function CommDKP:GetRaidKeyForZone(zone)
	for _, key in ipairs(core.RaidMenuOrder) do
		if core.ZoneList[core.RaidZoneIndex[key]] == zone then return key end
	end
end

-- Every boss name of a zone (static first, then discovered), without duplicates.
function CommDKP:GetZoneBossNames(zone)
	local out, seen, key = {}, {}, CommDKP:GetRaidKeyForZone(zone)
	if key then
		for _, name in ipairs(core.BossList[key]) do out[#out + 1] = name; seen[name] = true end
	end
	for _, e in ipairs(CommDKP:GetCustomBosses(zone, seen)) do out[#out + 1] = e.name; seen[e.name] = true end
	return out, seen
end

-- Every zone choice: static raids in menu order, then discovered zones, then extras (recent/current) not yet listed.
function CommDKP:GetAwardZoneNames(extra)
	local out, seen = {}, {}
	local function add(z) if type(z) == "string" and z ~= "" and not seen[z] then out[#out + 1] = z; seen[z] = true end end
	for _, key in ipairs(core.RaidMenuOrder) do add(core.ZoneList[core.RaidZoneIndex[key]]) end
	for _, z in ipairs(CommDKP:GetCustomEncounterZones()) do add(z) end
	for _, z in ipairs(extra or {}) do add(z) end
	return out
end

-------------------------------------
-- AD-12.3: Shared item-link parser
-- Never errors and works on a cold cache.
-- Returns itemName, itemLink, itemIcon, itemID (number), itemKey (string).
-- itemKey is the CommDKP_MinBids key. Existing tables are keyed by the STRING captured by string.find,
-- so never index MinBids with the numeric itemID.
-------------------------------------
function CommDKP:ParseItemLink(item)
	if type(item) ~= "string" or item == "" then return nil end
	local name, link, _, _, _, _, _, _, _, icon = C_Item.GetItemInfo(item)
	local id, _, _, _, instIcon = C_Item.GetItemInfoInstant(item)
	id = id or tonumber(item:match("item:(%d+)"))
	if not link and item:find("|Hitem:", 1, true) then link = item end
	name = name or item:match("|h%[(.-)%]|h")
	icon = icon or instIcon or (id and C_Item.GetItemIconByID and C_Item.GetItemIconByID(id)) or nil
	if id and not (C_Item.GetItemInfo(item)) and C_Item.RequestLoadItemDataByID then
		C_Item.RequestLoadItemDataByID(id)              -- warm the cache for the next lookup; no callback needed
	end
	return name, link, icon, id, id and tostring(id) or nil
end

-------------------------------------
-- AD-13.1: replacement for the ActionButton overlay-glow globals (removed in 10.1.5+).
-- Adds a texture to an addon-owned, non-secure Button only.
-------------------------------------
function CommDKP:ShowButtonGlow(button)
	if not button then return end
	if not button.cdkpGlow then
		local g = button:CreateTexture(nil, "OVERLAY")
		g:SetTexture("Interface\\Buttons\\UI-ActionButton-Border")
		g:SetBlendMode("ADD")
		g:SetAlpha(0.8)
		g:SetPoint("CENTER", button, "CENTER", 0, 0)
		local w, h = button:GetWidth() or 0, button:GetHeight() or 0
		if w <= 0 or h <= 0 then g:SetSize(60, 60) else g:SetSize(1.7 * w, 1.7 * h) end
		button.cdkpGlow = g
	end
	button.cdkpGlow:Show()
end

function CommDKP:HideButtonGlow(button)
	if button and button.cdkpGlow then button.cdkpGlow:Hide() end
end

function CommDKP:TableStrFind(tar, val, field, limit)             -- same function as above, but searches values that contain the searched string rather than exact string matches
	local value = string.upper(tostring(val));        -- ex. CommDKP:TableStrFind(CommDKP:GetTable(CommDKP_DKPHistory, true), "Vapok") will return the path to any table element that contains "Vapok"
	local location = {}
	local tableLimit = limit or -1 -- so some functions dont operate on huge tables when they need like last 20 records...
	for k,v in pairs(tar) do
		if(type(v) == "table") then
			local temp1 = k
			for k,v in pairs(v) do
				if(type(v) == "table") then
					local temp2 = k;
					for k,v in pairs(v) do
						if(type(v) == "table") then
							local temp3 = k
							for k,v in pairs(v) do
								if (field ~= "players" and field ~= "player" and strfind(string.upper(tostring(v)), value)) or ((field == "players" or field == "player") and (strfind(string.upper(tostring(v)), ","..value..",") or strfind(string.upper(tostring(v)), value..",") == 1)) then
									if field then
										if k == field then
											tinsert(location, {temp1, temp2, temp3, k} )
											if tableLimit ~= -1 and #location >= tableLimit then
												return location;
											end;
										end
									else
										tinsert(location, {temp1, temp2, temp3, k} )
										if tableLimit ~= -1 and #location >= tableLimit then
											return location;
										end;
									end
								end;
							end
						end
						if (field ~= "players" and field ~= "player" and strfind(string.upper(tostring(v)), value)) or ((field == "players" or field == "player") and (strfind(string.upper(tostring(v)), ","..value..",") or strfind(string.upper(tostring(v)), value..",") == 1)) then
							if field then
								if k == field then
									tinsert(location, {temp1, temp2, k} )
									if tableLimit ~= -1 and #location >= tableLimit then
										return location;
									end;
								end
							else
								tinsert(location, {temp1, temp2, k} )
								if tableLimit ~= -1 and #location >= tableLimit then
									return location;
								end;
							end
						end;
					end
				end
				if (field ~= "players" and field ~= "player" and strfind(string.upper(tostring(v)), value)) or ((field == "players" or field == "player") and (strfind(string.upper(tostring(v)), ","..value..",") or strfind(string.upper(tostring(v)), value..",") == 1)) then
					if field then
						if k == field then
							tinsert(location, {temp1, k} )
							if tableLimit ~= -1 and #location >= tableLimit then
								return location;
							end;
						end
					else
						tinsert(location, {temp1, k} )
						if tableLimit ~= -1 and #location >= tableLimit then
							return location;
						end;
					end
				end;
			end
		end
		if (field ~= "players" and field ~= "player" and strfind(string.upper(tostring(v)), value)) or ((field == "players" or field == "player") and (strfind(string.upper(tostring(v)), ","..value..",") or strfind(string.upper(tostring(v)), value..",") == 1)) then
			if field then
				if k == field then
					tinsert(location, k)
					if tableLimit ~= -1 and #location >= tableLimit then
						return location;
					end;
				end
			else
				tinsert(location, k)
				if tableLimit ~= -1 and #location >= tableLimit then
					return location;
				end;
			end
		end;
	end
	if (#location > 0) then
		return location;
	else
		return false;
	end
end

function CommDKP:DKPTable_Set(tar, field, value, loot)                -- updates field with value where tar is found (IE: CommDKP:DKPTable_Set("Vapok", "dkp", 10) adds 10 dkp to user Vapok). loot = true/false if it's to alter lifetime_spent
	local result = CommDKP:Table_Search(CommDKP:GetTable(CommDKP_DKPTable, true), tar);
	for i=1, #result do
		local current = CommDKP:GetTable(CommDKP_DKPTable, true)[result[i][1]][field];
		if(field == "dkp") then
			CommDKP:GetTable(CommDKP_DKPTable, true)[result[i][1]][field] = CommDKP_round(tonumber(current + value), core.DB.modes.rounding)
			if value > 0 and loot == false then
				CommDKP:GetTable(CommDKP_DKPTable, true)[result[i][1]]["lifetime_gained"] = CommDKP_round(tonumber(CommDKP:GetTable(CommDKP_DKPTable, true)[result[i][1]]["lifetime_gained"] + value), core.DB.modes.rounding)
			elseif value < 0 and loot == true then
				CommDKP:GetTable(CommDKP_DKPTable, true)[result[i][1]]["lifetime_spent"] = CommDKP_round(tonumber(CommDKP:GetTable(CommDKP_DKPTable, true)[result[i][1]]["lifetime_spent"] + value), core.DB.modes.rounding)
			end
		else
			CommDKP:GetTable(CommDKP_DKPTable, true)[result[i][1]][field] = value
		end
	end
	CommDKP:DKPTable_Update()
end
