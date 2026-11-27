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

-- CDKP-009d (AD-16.5 (a)): the 7 legacy edge keys (the UI-003 set) are retired; edges come from Card / Plaque.
core.Backdrops = {
	-- fill only
	StatusBg     = { bgFile = "Interface\\ChatFrame\\ChatFrameBackground", tile = true },
	Fill         = { bgFile = WHITE, tile = true, insets = NO_INSETS },
	-- class graph bars
	GraphBar     = { bgFile = MEDIA.."graph-bar.tga", tile = false, insets = { left = 1, right = 1, top = 1, bottom = 1 } },
	-- CDKP-009 (UX §12.2.2 / §12.2.3): UI v2 card and plaque panel (white fill + tooltip edge, 12 px, insets 3).
	Card         = { bgFile = WHITE, edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border", tile = true, tileSize = 8, edgeSize = 12,
	                 insets = { left = 3, right = 3, top = 3, bottom = 3 } },
}
core.Backdrops.Plaque = core.Backdrops.Card

-------------------------------------
-- Color palettes (CDKP-005, AD-6.3)
-- Keys in core.Backdrops hold geometry/textures only; colors are named by the frame's *role* and
-- resolved through core.Palette. Both palettes must define exactly the same role names.
--   Legacy  = the exact RGBA literals the legacy call sites used (pixel parity with CommunityDKP)
--   Forever = Gate 2 palette (ux_design_spec §2/§4; architect mapping, ux-designer may tune values here)
-------------------------------------
-- UX §11.2.1: warm "Treasurer's Ledger" bronze & gold tokens (replace the cold blue-slate / purple accent set).
-- Both palettes carry the tokens so the AD-6.3 role-name parity holds; only Forever maps the roles onto them.
local BG0          = { 0.071, 0.055, 0.039 }   -- #120E0A window interior, gutters
local BG1          = { 0.102, 0.078, 0.059 }   -- #1A140F cards, tables, inputs, side-tab rest
local BG2          = { 0.141, 0.110, 0.078 }   -- #241C14 header bands, button rest
local BG3          = { 0.184, 0.145, 0.098 }   -- #2F2519 hover, selected tab/row
local BG4          = { 0.231, 0.180, 0.122 }   -- #3B2E1F pressed
local TRIM         = { 0.851, 0.678, 0.200 }   -- #D9AD33 focus / hover / selected accent
local TRIM_QUIET   = { 0.478, 0.373, 0.165 }   -- #7A5F2A card / table / container border
local LINE         = { 0.353, 0.278, 0.192 }   -- #5A4731 rules, rest borders
local TEXT         = { 0.949, 0.902, 0.812 }   -- #F2E6CF body text
local TEXT_MUTED   = { 0.725, 0.655, 0.537 }   -- #B9A789 hints, version suffix
local TEXT_DISABLED= { 0.494, 0.435, 0.349 }   -- #7E6F59 disabled text
local GOLD         = { 1.0,   0.82,  0.0   }   -- #FFD100 header text (= GameFontNormal)
-- UX §12.2.0 (CDKP-009, AD-16.1 B9): UI v2 tokens, identical in both palettes.
local RULE         = { 0.239, 0.188, 0.141 }   -- #3D3024 hairlines inside cards, rail track edge
local POSITIVE     = { 0.424, 0.796, 0.373 }   -- #6CCB5F sync pip "in sync"
local NEGATIVE     = { 0.910, 0.341, 0.290 }   -- #E8574A sync pip "out of date", ruby base
local WARNING      = { 0.941, 0.635, 0.231 }   -- #F0A23B warning note, caution tone
local STRIPE       = { 1, 0.94, 0.78 }         -- #FFF0C7 @ 4% alternate table row
local function rgba(rgb, a) return { rgb[1], rgb[2], rgb[3], a } end
local function V2Tokens(p)
	p.rule       = rgba(RULE, 1)
	p.lineStrong = rgba(LINE, 1)                -- ForeverGold's name for our `line`
	p.positive   = rgba(POSITIVE, 1)
	p.negative   = rgba(NEGATIVE, 1)
	p.warning    = rgba(WARNING, 1)
	p.ruby       = rgba(NEGATIVE, 0.42)         -- primary-tone fill wash
	p.stripe     = rgba(STRIPE, 0.04)
	p.rowStripe  = rgba(STRIPE, 0.04)           -- alias of stripe
	p.edgeShadow = { 0, 0, 0, 0.40 }            -- card drop shadow
	return p
end

core.Palettes = {
	Legacy = {
		bg0               = rgba(BG0, 0.96),
		bg1               = rgba(BG1, 0.95),
		bg2               = rgba(BG2, 1),
		bg3               = rgba(BG3, 1),
		bg4               = rgba(BG4, 1),
		trim              = rgba(TRIM, 1),
		trimQuiet         = rgba(TRIM_QUIET, 1),
		line              = rgba(LINE, 1),
		text              = rgba(TEXT, 1),
		textMuted         = rgba(TEXT_MUTED, 1),
		textDisabled      = rgba(TEXT_DISABLED, 1),
		gold              = rgba(GOLD, 1),
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
		ButtonBgHover     = { 0.2, 0.2, 0.2, 1 },
		ButtonBgPushed    = { 0.3, 0.3, 0.3, 1 },
		RowSelected       = { 0.2, 0.2, 0.2, 1 },
		StatusBg          = { 0, 0, 0, 0.7 },
		Clear             = { 0, 0, 0, 0 },
		ExportBorder      = { 0, 0.44, 0.87, 0.5 },
	},
	Forever = {
		-- UX §11.2.1 tokens
		bg0               = rgba(BG0, 0.96),
		bg1               = rgba(BG1, 0.95),
		bg2               = rgba(BG2, 1),
		bg3               = rgba(BG3, 1),
		bg4               = rgba(BG4, 1),
		trim              = rgba(TRIM, 1),
		trimQuiet         = rgba(TRIM_QUIET, 1),
		line              = rgba(LINE, 1),
		text              = rgba(TEXT, 1),
		textMuted         = rgba(TEXT_MUTED, 1),
		textDisabled      = rgba(TEXT_DISABLED, 1),
		gold              = rgba(GOLD, 1),
		-- roles (aliases per the §11.2.1 table; call sites keep using these names)
		WindowBg          = rgba(BG0, 0.96),
		WindowBgOpaque    = rgba(BG0, 1),
		WindowBgSoft      = rgba(BG0, 0.88),
		WindowBorder      = rgba(TRIM_QUIET, 1),
		CloseBg           = rgba(BG0, 0.96),
		CloseBorder       = rgba(TRIM_QUIET, 0.6),
		TitleBg           = rgba(BG2, 1),
		InputBg           = rgba(BG1, 0.95),
		InputBgSoft       = rgba(BG1, 0.75),
		InputBorder       = rgba(LINE, 1),
		InputBorderAccent = rgba(TRIM, 1),
		ContainerBg       = rgba(BG1, 0.95),
		ContainerBorder   = rgba(TRIM_QUIET, 1),
		TableBg           = rgba(BG1, 0.95),
		TableBgSubtle     = rgba(BG1, 0.6),
		TableBorder       = rgba(TRIM_QUIET, 1),
		TableBorderSubtle = rgba(LINE, 1),
		HeaderBg          = rgba(BG2, 1),
		HeaderBgSolid     = rgba(BG2, 1),
		ButtonBgHover     = rgba(BG3, 1),
		ButtonBgPushed    = rgba(BG4, 1),
		RowSelected       = rgba(BG3, 1),
		StatusBg          = rgba(BG0, 0.8),
		Clear             = { 0, 0, 0, 0 },
		ExportBorder      = rgba(TRIM_QUIET, 0.8),
	},
}
V2Tokens(core.Palettes.Legacy)
V2Tokens(core.Palettes.Forever)
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
	if (border == "InputBorder" or border == "InputBorderAccent") and frame.GetObjectType
		and frame:GetObjectType() == "EditBox" then
		CommDKP:HookInputFocusBorder(frame)
	end
end

-- UX §11.2.1: edit boxes rest on the `line` border (InputBorder) and light `trim` gold (InputBorderAccent)
-- only while focused. Hooked one frame later: call sites SetScript their own focus handlers right after
-- ApplyBackdrop, and SetScript would wipe an earlier HookScript.
function CommDKP:HookInputFocusBorder(eb)
	if eb.cdkpFocusBorder then return end
	eb.cdkpFocusBorder = true
	CommDKP:SetBackdropRole(eb, nil, "InputBorder")
	local function hook()
		eb:HookScript("OnEditFocusGained", function(self) CommDKP:SetBackdropRole(self, nil, "InputBorderAccent") end)
		eb:HookScript("OnEditFocusLost", function(self) CommDKP:SetBackdropRole(self, nil, "InputBorder") end)
	end
	if C_Timer and C_Timer.After then C_Timer.After(0, hook) else hook() end
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
-- AD-18.2 (CDKP-011): verified WoW Forever launch tier. Keys == core.BossList keys == core.RaidMenuOrder.
-- A non-empty list holds per-boss encounter IDs in the SAME order as core.BossList[key] (positional).
-- An EMPTY list means "no verified per-boss IDs": that raid resolves by boss name, then by core.EncounterRangeList (PM-11.2).
core.EncounterList = {
	BARROWDEEPS = {},           -- IDs 3483-3491 are TACT-encrypted until 2026-12-09; ID->boss order unknown (BL-11.1)
	HYJALSUMMIT = {},           -- IDs 3337-3349; ID->boss order unknown (BL-11.1)
	ONYXIA = { 1084 },
	WORLD = {                   -- Forever 1.60.1 DungeonEncounter.db2 (maps 2789, 2791, 2832, 2804)
		3027, 3026, 3111, 3112, 3114, 3113, 3079
	},
}

-- AD-18.2: inclusive { first, last } DungeonEncounter ID range per raid. Decides the ZONE only, never the boss.
core.EncounterRangeList = {
	BARROWDEEPS = { 3483, 3491 },
	HYJALSUMMIT = { 3337, 3349 },
}

-- AD-11.2 / AD-12.2 / AD-18.2: Maps the EncounterList/BossList key to its index in core.ZoneList.
core.RaidZoneIndex = { BARROWDEEPS = 1, HYJALSUMMIT = 2, ONYXIA = 3, WORLD = 4 }
-- Order of the "Boss Killed" dropdown (PM-11.1: smallest raid first, World Bosses last).
core.RaidMenuOrder = { "BARROWDEEPS", "HYJALSUMMIT", "ONYXIA", "WORLD" }

core.CommDKPUI = {}        -- global storing entire Configuration UI to hide/show UI
core.MonVersion = "1.0.0";
core.BuildNumber = 10000;    -- AD-19 epoch: BuildNumber = MAJOR*10000 + MINOR*100 + PATCH (MINOR, PATCH <= 99). Numeric literal (test_regression.lua:89).
core.defaultTable = "__default";
core.SemVer = "v1.0.0";      -- PM-12.2: no -r suffix. Display sites use SemVer, never MonVersion.
core.UpgradeSchema = false;
-- UX §11.1.3: 26 rows (18*26+3 = 471 px). The native 24 px title bar + corner medallion push the roster header
-- down to y -47, so 27 rows would no longer leave room for the bottom strip (seed / search / counter / team).
core.TableWidth, core.TableRowHeight, core.TableNumRows, core.PriceNumRows = 500, 18, 23, 22; -- width, row height, number of rows (AD-16 B12: 23 roster rows fit the §12.3.1 Roster Card)
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
	CommDKP.UIConfig:SetPoint("TOPLEFT", UIParent, "TOPLEFT", 200, -120);   -- UX §11.1.3: always a TOPLEFT anchor
	CommDKP:SetWorkspaceShown(core.ShowState)                               -- width / TabMenu / side-tab state
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

-- AD-20.2.1 (CDKP-013a): resolves core.IsOfficer (nil = unresolved, true, false). Use before checks against core.IsOfficer.
-- force = re-evaluate a cached true/false (guild events only). A resolved value is never overwritten by an unresolved one.
function CommDKP:CheckOfficer(force)
	if not IsInGuild() then
		-- BR-13.1.1 / BR-13.2.5: decide "unguilded" only once identity is ready (DoInitWhenReady) or on PLAYER_GUILD_UPDATE.
		if core.GuildStateReady then core.IsOfficer = false end
		return
	end
	if not core.InitStart then return end                 -- guilded but DoGuildUpdate not run yet: stay as-is
	if core.IsOfficer ~= nil and not force then return end

	local v                                                -- nil = could not resolve now
	if CommDKP:IsPlayerGuildLeader() then
		v = true                                           -- AD-9.2.5: GL beats every setting
	elseif #CommDKP:GetTable(CommDKP_Whitelist) > 0 then
		v = false
		for _, name in ipairs(CommDKP:GetTable(CommDKP_Whitelist)) do
			if CommDKP:SamePlayer(name, CommDKP:GetPlayerName()) then v = true; break end
		end
	elseif type(CanEditOfficerNote) == "function" and CanEditOfficerNote() then
		v = true
	elseif GetNumGuildMembers() > 0 then                   -- AD-9.2.5: roster loaded
		local rank = CommDKP:GetGuildRankIndex(CommDKP:GetPlayerName())
		if rank then
			local ok, flags = pcall(function() return C_GuildInfo and C_GuildInfo.GuildControlGetRankFlags and C_GuildInfo.GuildControlGetRankFlags(rank) end)
			if ok and type(flags) == "table" and flags[12] ~= nil then
				v = flags[12] and true or false
			else
				v = false                                      -- AD-34.4: unresolvable rank flags fail closed (BR-26.3)
				if core.CommTrace then CommDKP:CommTrace("CheckOfficer: rank flags unresolved for rank %s -> false", tostring(rank)) end
			end
		elseif core.GuildStateReady then
			v = false                                      -- non-GL member whose row is filtered or offline: resolve false so comms never block
		end
	end
	if v ~= nil then core.IsOfficer = v end                -- unresolved never clobbers a resolved value
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
	CommDKP:StyleButton(btn)   -- AD-16.2 (a): flat bronze kit button + CommDKPButtonFont (idempotent after the XML OnLoad)
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

-- CDKP-009c: CommDKP:CreateContainer (edgefile "BorderOnly" box + legacy font header) is retired; its last callers
-- (Broadcast, DKP Modes Misc) now use W.CreateCard.

-------------------------------------
-- UX §11: Character Screen / ForeverGold chrome helpers
-------------------------------------
-- CDKP-009 (AD-16.2 (a)): ApplyForeverChrome, CreatePixelBorder, SetPixelBorderColor, the CommDKPButtonFont*
-- objects, StyleButton, SetForeverTitle, CreateForeverWindow and HasTemplate live in Modules/UI/Widgets.lua
-- (loaded right after this file; same public names). Only the side-tab helpers stay here.

-- §11.1.4: side-tab widget (LargeSideTabButtonTemplate on Forever 1.60.1, plain Button fallback / headless).
local QUESTION_MARK = "Interface\\Icons\\INV_Misc_QuestionMark"

local function HasTemplate(name)          -- AD-16.4 (d): the probe moved to Widgets.lua (W.HasTemplate)
	return CommDKP.Widgets ~= nil and CommDKP.Widgets.HasTemplate(name)
end

-- AD-32.3.1 / AD-32.8.1 (BR-24.6c): 3 kinds of entry, tried in order:
--   1. native CASC FileDataID: a positive integer (or a digit-only string), returned as a number with no
--      GetFileIDFromPath check; Texture:SetTexture(fileDataID) draws the client's own mipmapped BLP;
--   2. addon-owned texture: loose files are never in the client's file-ID list, so GetFileIDFromPath returns nil
--      for them on 1.60.1; accept them by prefix (case-insensitive, \ or /);
--   3. stock Interface\Icons path: keeps the check, so an unresolvable stock icon falls through to the next one.
local ADDON_TEX_PREFIX = "^interface[\\/]addons[\\/]communitydkpforever[\\/]"
function CommDKP:ResolveIcon(paths)
	for _, p in ipairs(paths or {}) do
		if type(p) == "string" and p:find("^%d+$") then p = tonumber(p) end   -- "4624666" -> 4624666
		if type(p) == "number" then
			if p > 0 and p % 1 == 0 then return p end                          -- 0, negative, 1.5, NaN: skipped
		elseif type(p) == "string" and p ~= "" then
			if p:lower():find(ADDON_TEX_PREFIX) then return p end
			if not GetFileIDFromPath or GetFileIDFromPath(p) then return p end   -- headless: first path wins
		end
	end
	return QUESTION_MARK
end

local function SideTab_OnEnter(self)
	GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
	GameTooltip:SetText(self.cdkpTitle, 1, 0.82, 0)
	GameTooltip:Show()
end

local function SideTab_OnLeave()
	GameTooltip:Hide()
end

-- Returns a tab with :cdkpSetSelected(bool), .cdkpIndex and .cdkpTitle. The caller stacks it (StackSideTabs).
function CommDKP:CreateSideTab(parent, frameName, i, iconPaths, title, onClick)
	local P, icon, tab = core.Palettes.Forever, CommDKP:ResolveIcon(iconPaths), nil
	local name = frameName and (frameName .. "SideTab" .. i) or nil

	if HasTemplate("LargeSideTabButtonTemplate") then                          -- Forever 1.60.1 (ForeverGold Widgets.lua)
		local ok, t = pcall(CreateFrame, "Frame", name, parent, "LargeSideTabButtonTemplate")
		if ok and t and t.Icon then tab = t elseif ok and t then t:Hide() end
	end

	if tab then
		tab.Icon:SetTexture(icon)
		if tab.SetFillToInterior then tab:SetFillToInterior(true) end
		if tab.SetCustomOnMouseUpHandler then
			tab:SetCustomOnMouseUpHandler(function(self, button, upInside)
				if button == "LeftButton" and upInside then onClick(self) end
			end)
		else
			tab:SetScript("OnMouseUp", function(self, button)
				if button == "LeftButton" and self:IsMouseOver() then onClick(self) end
			end)
		end
		tab.cdkpSetSelected = function(self, sel)
			self.selected = sel and true or false
			if self.SetChecked then self:SetChecked(self.selected) end
		end
		-- The template is a Frame whose SidePanelTabButtonMixin OnEnter anchors self.tooltipText above the tab.
		-- Replace (not hook) both scripts so only our right-anchored gold tooltip shows.
		tab.tooltipText = nil
		if tab.OnEnter then tab.OnEnter = SideTab_OnEnter end
		if tab.OnLeave then tab.OnLeave = SideTab_OnLeave end
	else                                                                        -- fallback / headless
		tab = CreateFrame("Button", name, parent)
		tab:SetSize(36, 36)
		tab.Fill = tab:CreateTexture(nil, "BACKGROUND"); tab.Fill:SetAllPoints(); tab.Fill:SetColorTexture(unpack(P.bg1))
		tab.Icon = tab:CreateTexture(nil, "ARTWORK")
		tab.Icon:SetSize(28, 28); tab.Icon:SetPoint("CENTER")
		tab.Icon:SetTexture(icon); tab.Icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
		tab.Edges = CommDKP:CreatePixelBorder(tab, P.line)
		tab:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")
		if tab.RegisterForClicks then tab:RegisterForClicks("LeftButtonUp") end
		tab:SetScript("OnClick", function(self, button) if button == nil or button == "LeftButton" then onClick(self) end end)
		tab:SetScript("OnMouseDown", function(self) self.Fill:SetColorTexture(unpack(P.bg4)) end)
		tab:SetScript("OnMouseUp", function(self) self.Fill:SetColorTexture(unpack(self.selected and P.bg3 or P.bg1)) end)
		tab.cdkpSetSelected = function(self, sel)
			self.selected = sel and true or false
			CommDKP:SetPixelBorderColor(self.Edges, self.selected and P.trim or P.line)
			self.Fill:SetColorTexture(unpack(self.selected and P.bg3 or P.bg1))
			self.Icon:SetDesaturated(not self.selected); self.Icon:SetAlpha(self.selected and 1 or 0.85)
		end
	end

	tab.cdkpIndex, tab.cdkpTitle = i, title
	if tab.SetID then tab:SetID(i) end
	tab:EnableMouse(true)
	tab:SetScript("OnEnter", SideTab_OnEnter)
	tab:SetScript("OnLeave", SideTab_OnLeave)
	tab:cdkpSetSelected(false)
	return tab
end

-- Stacks the visible tabs down the right edge of f (hidden tabs are skipped, e.g. officer-only tabs).
-- AD-31 (CDKP-023): optional display order. `order` (or f.sideTabOrder) is a list of tab INDEXES in top-to-bottom rail
-- order, e.g. { 1, 3, 2, 4, 5, 6, 7 }. It changes position only: tabs[i] keeps its index, pane, global and click target.
-- Indexes missing from the order are appended in index order; unknown / duplicate indexes are ignored. No order -> 1..n.
function CommDKP:StackSideTabs(f, tabs, topOffset, order)
	local ord, seq = order or (type(f) == "table" and f.sideTabOrder) or nil, tabs
	if type(ord) == "table" and #ord > 0 then
		local seen = {}
		seq = {}
		for _, idx in ipairs(ord) do
			local tab = tabs[idx]
			if tab and not seen[idx] then seen[idx] = true; seq[#seq + 1] = tab end
		end
		for i, tab in ipairs(tabs) do
			if not seen[i] then seq[#seq + 1] = tab end
		end
	end
	local prev, w = nil, 36
	for _, tab in ipairs(seq) do
		if tab:IsShown() then
			tab:ClearAllPoints()
			if not prev then tab:SetPoint("TOPLEFT", f, "TOPRIGHT", 0, topOffset or -42)
			else tab:SetPoint("TOP", prev, "BOTTOM", 0, -2) end
			prev = tab
			w = math.max(w, tab:GetWidth() or 0)
		end
	end
	if f.GetClampRectInsets and f.SetClampRectInsets then
		local l, _, t, b = f:GetClampRectInsets()
		f:SetClampRectInsets(l or 0, math.max(42, math.ceil(w) + 6), t or 0, b or 0)   -- 36 px fallback -> 42
	end
end

-- end of the UX §11 side-tab helpers

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
	if CommDKP.UIConfig and not CommDKP.UIConfig:IsShown() then
		-- blocks update if dkp window is closed. Updated when window is opened anyway
		return;
	end

	if IsInGuild() and core.Initialized then
		-- AD-29.1 (CDKP-021, BR-21.1): empty current-team histories in a guild = out of date. Evaluated here (not as an
		-- early exit) so core.OOD, the pip and the tooltip are always set together (BR-21.2). Skips the .seed search.
		local dkpHist = CommDKP:GetTable(CommDKP_DKPHistory, true, CommDKP:GetCurrentTeamIndex())
		local lootHist = CommDKP:GetTable(CommDKP_Loot, true, CommDKP:GetCurrentTeamIndex())
		local tablesEmpty = (#dkpHist == 0 and #lootHist == 0)

		if tablesEmpty then
			core.OOD = true
			CommDKP.Widgets.SetPipState(CommDKP.DKPTable.SeedVerifyIcon, core.OOD)   -- §12.2.11: negative pip
			CommDKP.DKPTable.SeedVerify:SetScript("OnEnter", function(self)
				GameTooltip:SetOwner(self, "ANCHOR_RIGHT", 0, 0);
				GameTooltip:SetText(L["DKPSTATUS"], 0.25, 0.75, 0.90, 1, true);
				GameTooltip:AddLine(L["TABLESAREEMPTY"], 1.0, 1.0, 1.0, false);
				GameTooltip:AddLine(L["TABLESEMPTYRECOVERY"], 1.0, 1.0, 1.0, true);   -- AD-29.3 (BR-21.4)
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

		core.OOD = false

		local missing = {}

		if (CommDKP:GetTable(CommDKP_Loot, true, CommDKP:GetCurrentTeamIndex()).seed and strfind(CommDKP:GetTable(CommDKP_Loot, true, CommDKP:GetCurrentTeamIndex()).seed, "-")) or
		   (CommDKP:GetTable(CommDKP_DKPHistory, true, CommDKP:GetCurrentTeamIndex()).seed and strfind(CommDKP:GetTable(CommDKP_DKPHistory, true, CommDKP:GetCurrentTeamIndex()).seed, "-"))
		then

			local search_dkp = CommDKP:Table_Search(CommDKP:GetTable(CommDKP_DKPHistory, true, CommDKP:GetCurrentTeamIndex()), CommDKP:GetTable(CommDKP_DKPHistory, true, CommDKP:GetCurrentTeamIndex()).seed, "index")
			local search_loot = CommDKP:Table_Search(CommDKP:GetTable(CommDKP_Loot, true, CommDKP:GetCurrentTeamIndex()), CommDKP:GetTable(CommDKP_Loot, true, CommDKP:GetCurrentTeamIndex()).seed, "index")
			local dSeed = CommDKP:GetTable(CommDKP_DKPHistory, true, CommDKP:GetCurrentTeamIndex()).seed   -- AD-35.2.2 (F-35.1)
			local lSeed = CommDKP:GetTable(CommDKP_Loot, true, CommDKP:GetCurrentTeamIndex()).seed

			if not search_dkp and type(dSeed) == "string" then
				core.OOD = true
				local officer1, date1 = strsplit("-", dSeed)
				local d1 = tonumber(date1)                                         -- AD-36.4.2 (BR-28.12, CM-07): R-SEED
				if not d1 or d1 < (time() - 1209600) or not CommDKP:ValidateSender(officer1) then   -- malformed / > 2 weeks / not an officer: ignored
					core.OOD = false
				else
					missing[officer1] = date("%m/%d/%y %H:%M:%S", d1)		-- if both missing seeds identify the same officer, it'll only list once
				end
			end
			
			if not search_loot and not core.OOD and type(lSeed) == "string" then
				core.OOD = true
				local officer2, date2 = strsplit("-", lSeed)
				local d2 = tonumber(date2)                                         -- AD-36.4.2 (BR-28.12, CM-07): R-SEED
				if not d2 or d2 < (time() - 1209600) or not CommDKP:ValidateSender(officer2) then   -- malformed / > 2 weeks / not an officer: ignored
					core.OOD = false
				else
					missing[officer2] = date("%m/%d/%y %H:%M:%S", d2)
				end
			end
		end

		if not core.OOD then
			CommDKP.Widgets.SetPipState(CommDKP.DKPTable.SeedVerifyIcon, core.OOD)   -- §12.2.11: positive pip
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
			CommDKP.Widgets.SetPipState(CommDKP.DKPTable.SeedVerifyIcon, core.OOD)   -- §12.2.11: negative pip
			CommDKP.DKPTable.SeedVerify:SetScript("OnEnter", function(self)
				GameTooltip:SetOwner(self, "ANCHOR_RIGHT", 0, 0);
				GameTooltip:SetText(L["DKPSTATUS"], 0.25, 0.75, 0.90, 1, true);
				GameTooltip:AddLine(L["ONETABLEOOD"].." |cffff0000"..L["OUTOFDATE"].."|r.", 1.0, 1.0, 1.0, false);
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
-- AD-36.5.1 (CDKP-028, C-28.5): never errors without the main window. With CommDKP.UIConfig nil (sandboxes, or a
-- CreateMenu that failed; see F-36.1) only the stored team, core.WorkingTable and the price data change; the views draw
-- when the window is built / opened. opts.noTalentSend = true skips the debounced talents/roles send (login default
-- only: the startup SendTalentsAndRole follows it).
function CommDKP:SetCurrentTeam(index, opts)
	CommDKP:GetTable(CommDKP_DB, false)["defaults"]["CurrentTeam"] = tostring(index);
	local ui = CommDKP.UIConfig
	if ui then
		CommDKP:StatusVerify_Update();
		if ui.TeamViewChangerDropDown then
			CommDKP.DD:UIDropDownMenu_SetText(ui.TeamViewChangerDropDown, CommDKP:GetCurrentTeamName());   -- AD-16.3: Forever selector
		end
	end

	-- reset dkp table and update it
	core.WorkingTable = CommDKP:GetTable(CommDKP_DKPTable, true);

	if ui then
		CommDKP:DKPTable_Update();
		-- reset dkp history table and update it
		CommDKP:DKPHistory_Update(true);
		-- reset loot history
		CommDKP:LootHistory_Update(L["NOFILTER"]);
		-- update class graph
		CommDKP:ClassGraph_Update();
	end
	-- update price table (data always; PriceTable_Redraw no-ops until Tab 7 exists)
	CommDKP:RefreshPriceTable(true); -- AD-25 (S7, C-25.5)
	-- broadcast Talents and Roles (AD-26.5.1: debounced; also the full-broadcast re-send, BR-18.4(b))
	if not (type(opts) == "table" and opts.noTalentSend) then CommDKP:QueueTalentSend("team", 1) end
end

-------------------------------------
-- AD-17.3 (CDKP-010) + AD-19.2 (CDKP-012g): talBuild, talRole = the player's talent summary, or nil, nil. Never errors.
-- (1) Legacy Classic GetTalentTabInfo path first while that global exists (byte-identical to AD-17.3; R12: falls
--     through on nil). (2) WoW Forever 1.60.1: one C_Traits tree, Classic trees = posX bands (BR-12.14.1).
-- Self-contained (no file-local upvalues): the headless tests extract it verbatim.
-------------------------------------
function CommDKP:GetPlayerTalentSummary()
	local isSecret = _G.issecretvalue
	local function secret(v) return isSecret ~= nil and v ~= nil and isSecret(v) and true or false end
	-- (1) Legacy Classic path, byte-identical to AD-17.3; first while the global exists (R12: falls through on nil).
	local fn = _G.GetTalentTabInfo
	if type(fn) == "function" then
		local function legacy()
			local TalTrees = {}
			for i = 1, 3 do
				local ok, name, icon, points, fileName = pcall(fn, i)
				if not ok then return nil, nil end
				if secret(name) or secret(points) or secret(fileName) then return nil, nil end
				if type(name) ~= "string" or name == "" then return nil, nil end
				if type(points) ~= "number" then return nil, nil end
				if type(fileName) ~= "string" or fileName == "" then return nil, nil end
				TalTrees[i] = { name, icon, points, fileName }
			end
			-- byte-identical to legacy CommunityDKP Core.lua:853-861 (same initial order, same comparator)
			local talBuild = "("..TalTrees[1][3].."/"..TalTrees[2][3].."/"..TalTrees[3][3]..")"
			table.sort(TalTrees, function(a, b) return a[3] > b[3] end)
			return TalTrees[1][1].." "..talBuild, TalTrees[1][4]
		end
		local b, r = legacy()
		if b and r then return b, r end
	end
	-- (2) WoW Forever 1.60.1: ONE C_Traits tree; Classic trees = posX bands (BR-12.14.1, probe Katniss-HUNTER 11/5/0).
	local CT, CCT = _G.C_Traits, _G.C_ClassTalents
	if type(CT) ~= "table" or type(CCT) ~= "table" or type(_G.UnitClass) ~= "function" then return nil, nil end
	local TREES = {   -- BR-12.14.2: enUS wire data matched by RolesReceived, NOT display text
		WARRIOR = { "Arms", "Fury", "Protection" },                PALADIN = { "Holy", "Protection", "Retribution" },
		HUNTER  = { "Beast Mastery", "Marksmanship", "Survival" }, ROGUE   = { "Assassination", "Combat", "Subtlety" },
		PRIEST  = { "Discipline", "Holy", "Shadow" },              SHAMAN  = { "Elemental", "Enhancement", "Restoration" },
		MAGE    = { "Arcane", "Fire", "Frost" },                   WARLOCK = { "Affliction", "Demonology", "Destruction" },
		DRUID   = { "Balance", "Feral Combat", "Restoration" },
	}
	local okC, _, classToken = pcall(_G.UnitClass, "player")
	if not okC or secret(classToken) then return nil, nil end
	local names = type(classToken) == "string" and TREES[classToken]
	if not names then return nil, nil end
	local okA, configID = pcall(CCT.GetActiveConfigID)
	if not okA or configID == nil or secret(configID) then return nil, nil end
	local okI, info = pcall(CT.GetConfigInfo, configID)
	local treeID = okI and type(info) == "table" and type(info.treeIDs) == "table" and info.treeIDs[1]
	if not treeID or secret(treeID) then return nil, nil end
	local okN, nodes = pcall(CT.GetTreeNodes, treeID)
	if not okN or type(nodes) ~= "table" then return nil, nil end
	local pts, cnt = { 0, 0, 0 }, { 0, 0, 0 }
	for _, nodeID in ipairs(nodes) do
		local okG, n = pcall(CT.GetNodeInfo, configID, nodeID)
		if not okG then return nil, nil end                        -- API error -> no send
		if type(n) == "table" then
			local x, r = n.posX, n.ranksPurchased
			if secret(x) or secret(r) then return nil, nil end
			if type(x) == "number" and type(r) == "number" then    -- missing / non-numeric -> skipped
				local band = (x < 4000 and 1) or (x < 8000 and 2) or 3 -- Tree 3 has NO upper bound (Lightning Reflexes 102800)
				cnt[band] = cnt[band] + 1
				pts[band] = pts[band] + r
			end
		end
	end
	if cnt[1] == 0 or cnt[2] == 0 or cnt[3] == 0 then return nil, nil end   -- PM-12.12 layout guard
	local tally = "("..pts[1].."/"..pts[2].."/"..pts[3]..")"
	if pts[1] + pts[2] + pts[3] == 0 then local s = "No Spec "..tally; return s, s end   -- PM-12.11
	local top = 1
	for i = 2, 3 do if pts[i] > pts[top] then top = i end end   -- strict >: a tie goes to the lower tree index
	local s = names[top].." "..tally
	return s, s                                                   -- PM-12.10: talRole == talBuild
end

-- AD-17.3 (CDKP-010) + AD-26.3.1 (CDKP-018a): profile + version always broadcast (also guildless / no row, RC-1);
-- spec/role only when the talent probe gives real strings, or the AD-26.3.2 fallback. opts = { talentsOnly, final } or nil.
function CommDKP:SendTalentsAndRole(opts)
	return xpcall(function()
		-- (1) Identity (BR-18.8): never send under a bare first name; wait up to 15 x 2 s for the full name.
		local me = CommDKP:GetPlayerName()
		if not me then return end  -- AD-10.4: identity not loaded yet
		if not CommDKP:HasFullPlayerName() then
			if not core.TalentNameWaitPending and (core.TalentNameWaitTries or 0) < 15 then
				core.TalentNameWaitPending = true
				core.TalentNameWaitTries = (core.TalentNameWaitTries or 0) + 1
				C_Timer.After(2, function() core.TalentNameWaitPending = false; CommDKP:SendTalentsAndRole(opts) end)
			end
			return
		end
		core.TalentNameWaitTries = 0
		local now = (type(GetTime) == "function" and GetTime()) or 0
		local sent = false

		-- (3) Own profile + version in every team (BR-18.14, RC-14).
		local _, myClass = UnitClass("player")
		local cur = CommDKP:GetTable(CommDKP_Profiles, true)
		local profile = cur[me] or CommDKP:GetDefaultEntity();
		profile.player = me;
		profile.version = core.SemVer;
		if myClass and (profile.class == nil or profile.class == "None" or profile.class == "NONE") then profile.class = myClass end
		cur[me] = profile;
		for _, team in ipairs(CommDKP:GetTeamIndexList()) do
			local rows = CommDKP:GetTable(CommDKP_DKPTable, true, team)
			for i = 1, #rows do
				local row = rows[i]
				if type(row) == "table" and row.player == me then
					row.version = core.SemVer
					local profs = CommDKP:GetTable(CommDKP_Profiles, true, team)
					if type(profs[me]) ~= "table" then profs[me] = CommDKP:GetDefaultEntity() end
					profs[me].player = me
					profs[me].version = core.SemVer
					break
				end
			end
		end

		-- (4) CDKProfileSend is always the first message of the burst (BR-18.1, F4); retries skip it.
		if not (opts and opts.talentsOnly) then
			CommDKP.Sync:SendData("CDKProfileSend", profile)
			sent = true
		end

		-- (5) Talent read + AD-26.3.2 retry / fallback (BR-18.6).
		local talBuild, talRole = CommDKP:GetPlayerTalentSummary()
		if not talBuild then
			local lvl = type(UnitLevel) == "function" and UnitLevel("player") or nil
			if _G.issecretvalue and lvl ~= nil and _G.issecretvalue(lvl) then lvl = nil end
			local low   = type(lvl) == "number" and lvl < 10
			local final = (opts and opts.final) or core.TalentRetryExhausted
			if low or final then
				local known = CommDKP:BuildKnownMetaIndex(me)[me]
				if known and CommDKP:IsRealSpec(known.spec) then        -- BR-18.6(d): never "No Spec (0/0/0)" over a real spec
					talBuild, talRole = nil, nil
				else
					talBuild = "No Spec (0/0/0)"; talRole = talBuild    -- BR-18.6(b); the receiver gives the class default (PM-12.11)
				end
				if final then core.TalentRetryExhausted = true end
			else
				CommDKP:ScheduleTalentRetry()                          -- BR-18.6(a); sends nothing now (AC-18.6c)
			end
		end

		-- (6)
		if talBuild and talRole then
			-- BR-12.14.5: write my own spec/role into EVERY team where I have a roster row, before any echo.
			local me = CommDKP:GetPlayerName()
			local _, myClass = UnitClass("player")
			for _, teamIndex in ipairs(CommDKP:GetTeamIndexList()) do
				local rows = CommDKP:GetTable(CommDKP_DKPTable, true, teamIndex)
				local hit = CommDKP:Table_Search(rows, me, "player")
				if hit then
					local row = rows[hit[1][1]]
					local role = CommDKP:ResolveRoleForClassAndSpec(row.class or myClass, talRole)
					row.spec, row.role = talBuild, role
					local profs = CommDKP:GetTable(CommDKP_Profiles, true, teamIndex)
					if profs[me] == nil then profs[me] = CommDKP:GetDefaultEntity() end
					profs[me].spec, profs[me].role = talBuild, role
				end
			end
			core.LastTalBuildSent = talBuild
			core.LastTalRoleSent = talRole                                -- AD-26.3.1: self overlay for BuildKnownMetaIndex
			CommDKP.Sync:SendData("CommDKPTalents", talBuild)
			CommDKP.Sync:SendData("CommDKPRoles", talRole)
			if CommDKP.UIConfig and CommDKP.UIConfig:IsShown() then
				if CommDKP.FilterDKPTable then CommDKP:FilterDKPTable(core.currentSort, "reset")
				elseif CommDKP.DKPTable_Update then CommDKP:DKPTable_Update() end
			end
			sent = true
			core.TalentSend = core.TalentSend or {}
			core.TalentSend.lastPairAt = now
			CommDKP:CancelTalentRetry()
		end

		-- (7) BR-18.10 pair window bookkeeping.
		if sent then
			core.TalentSend = core.TalentSend or {}
			core.TalentSend.lastSentAt = now
		end
	end, function(e) geterrorhandler()(e); return e end)
end

-- AD-19.2 (012g): TRAIT_CONFIG_UPDATED -> one re-broadcast ~2 s after the last event, only if the summary changed.
function CommDKP:QueueTalentRefresh()
	core.TalentRefreshGen = (core.TalentRefreshGen or 0) + 1
	local gen = core.TalentRefreshGen
	C_Timer.After(2, function()
		if gen ~= core.TalentRefreshGen or not core.Initialized then return end
		local b = CommDKP:GetPlayerTalentSummary()
		if b and b ~= core.LastTalBuildSent then CommDKP:SendTalentsAndRole() end
	end)
end

-------------------------------------
-- AD-26.2 / AD-26.3 (CDKP-018a): shared player-meta contract, talent retry & debounced re-send.
-- Every helper is a top-level CommDKP method with a column-0 `end`, no file-local upvalues (harness extract()).
-------------------------------------

-- AD-26.2.1 (BR-18.3): one placeholder rule for spec / role / version. Non-strings and "" are placeholders.
function CommDKP:IsPlaceholderMeta(field, value)
	if type(value) ~= "string" or value == "" then return true end
	if field == "spec" then
		return value == "No Spec Reported" or value == L["NOSPECREPORTED"]
	elseif field == "role" then
		return value == "No Role Reported" or value == "No Role Detected" or value == L["NOROLEDETECTED"]
	elseif field == "version" then
		return value == "Unknown"
	end
	return false
end

-- AD-26.2.1 (BR-18.6d / AC-18.9): a spec with points spent. "No Spec (0/0/0)" is a valid report, but NOT real.
function CommDKP:IsRealSpec(spec)
	if CommDKP:IsPlaceholderMeta("spec", spec) then return false end
	local a, b, c = spec:match("%((%d+)/(%d+)/(%d+)%)")
	if a then return (tonumber(a) + tonumber(b) + tonumber(c)) > 0 end
	return spec:find("^No Spec") == nil
end

-- AD-26.2.2 (BR-18.2): session-only cache of player-reported meta, capped at 300 names (oldest `t` evicted).
-- AD-34.6 (F-34.2): fillOnly (officer-relayed meta) writes a field only when the cache has no value for it yet.
function CommDKP:CachePlayerMeta(name, meta, fillOnly)   -- meta: spec, roleData, version, class (placeholders ignored)
	if type(name) ~= "string" or name == "" or type(meta) ~= "table" then return end
	core.PlayerMeta = core.PlayerMeta or {}; core.PlayerMetaCount = core.PlayerMetaCount or 0
	local e = core.PlayerMeta[name]
	if not e then
		if core.PlayerMetaCount >= 300 then
			local oldK, oldT
			for k, v in pairs(core.PlayerMeta) do if oldT == nil or (v.t or 0) < oldT then oldK, oldT = k, (v.t or 0) end end
			if oldK then core.PlayerMeta[oldK] = nil; core.PlayerMetaCount = core.PlayerMetaCount - 1 end
		end
		e = {}; core.PlayerMeta[name] = e; core.PlayerMetaCount = core.PlayerMetaCount + 1
	end
	if not CommDKP:IsPlaceholderMeta("spec", meta.spec) and (not fillOnly or e.spec == nil) then e.spec = meta.spec end
	if type(meta.roleData) == "string" and meta.roleData ~= "" and (not fillOnly or e.roleData == nil) then e.roleData = meta.roleData end
	if not CommDKP:IsPlaceholderMeta("version", meta.version) and (not fillOnly or e.version == nil) then e.version = meta.version end
	if type(meta.class) == "string" and meta.class ~= "" and meta.class ~= "None" and meta.class ~= "NONE" and (not fillOnly or e.class == nil) then e.class = meta.class end
	if e.roleData or e.spec then
		local r = CommDKP:ResolveRoleForClassAndSpec(e.class, e.roleData or e.spec)
		if not CommDKP:IsPlaceholderMeta("role", r) then e.role = r end
	end
	e.t = (type(GetTime) == "function" and GetTime()) or 0
end

-- AD-26.2.3 (BR-18.2/18.9/18.14/18.15): the only receive-side writer. Player-reported, so it overwrites non-placeholders.
-- AD-30.1.5 (CDKP-022): returns hit, teamsMatched (number of teams whose row matched; callers using only hit unaffected).
function CommDKP:ApplyReportedPlayerMeta(name, meta, extraTeams)
	if type(name) ~= "string" or name == "" or type(meta) ~= "table" then return false, 0 end
	local spec    = not CommDKP:IsPlaceholderMeta("spec", meta.spec) and meta.spec or nil
	local roleDat = type(meta.roleData) == "string" and meta.roleData ~= "" and meta.roleData or nil
	local version = not CommDKP:IsPlaceholderMeta("version", meta.version) and meta.version or nil
	local class   = type(meta.class) == "string" and meta.class ~= "" and meta.class ~= "None" and meta.class ~= "NONE" and meta.class or nil
	local hit, teamsMatched = false, 0
	for _, team in ipairs(CommDKP:GetTeamIndexList(extraTeams)) do
		local rows = CommDKP:GetTable(CommDKP_DKPTable, true, team)
		for i = 1, #rows do
			local row = rows[i]
			if type(row) == "table" and row.player == name then
				hit = true
				teamsMatched = teamsMatched + 1                          -- AD-30.1.5: one per team (break below)
				if class and (row.class == nil or row.class == "None" or row.class == "NONE") then row.class = class end
				if spec then row.spec = spec end
				if roleDat then
					local r = CommDKP:ResolveRoleForClassAndSpec(row.class or class, roleDat)
					if not CommDKP:IsPlaceholderMeta("role", r) then row.role = r end
				end
				if version then row.version = version end
				local profs = CommDKP:GetTable(CommDKP_Profiles, true, team)
				if type(profs[name]) ~= "table" then profs[name] = CommDKP:GetDefaultEntity() end
				local p = profs[name]; p.player = name
				if spec then p.spec = row.spec end
				if roleDat and row.role then p.role = row.role end
				if version then p.version = version end
				if class and (p.class == nil or p.class == "None" or p.class == "NONE") then p.class = class end
				break
			end
		end
	end
	CommDKP:CachePlayerMeta(name, { spec = spec, roleData = roleDat, version = version, class = class })
	if hit then CommDKP:QueueRosterRedraw() end
	return hit, teamsMatched
end

-- AD-26.2.4 (BR-18.3/18.13/18.16): { [name] = { spec, role, roleData, version, class, reported = { <field> = true } } }.
-- Precedence: (1) self overlay, (2) core.PlayerMeta [both reported], (3) rows, (4) Profiles of every team [not reported].
-- A non-placeholder fills a missing field; for spec, a real spec also replaces a non-real, non-reported one.
-- onlyName: collect that name only (single-row path, O(rows), no Table_Search). nil: all names (batch path).
function CommDKP:BuildKnownMetaIndex(onlyName)
	local index = {}
	local function badClass(v) return type(v) ~= "string" or v == "" or v == "None" or v == "NONE" end
	local function merge(name, src, reported)
		if type(name) ~= "string" or name == "" or type(src) ~= "table" then return end
		if onlyName ~= nil and name ~= onlyName then return end
		local m = index[name]
		if not m then m = { reported = {} }; index[name] = m end
		local rep = m.reported
		if not CommDKP:IsPlaceholderMeta("spec", src.spec) then
			if m.spec == nil or (not rep.spec and CommDKP:IsRealSpec(src.spec) and not CommDKP:IsRealSpec(m.spec)) then
				m.spec = src.spec; rep.spec = reported or nil
			end
		end
		if m.roleData == nil and type(src.roleData) == "string" and src.roleData ~= "" then
			m.roleData = src.roleData; rep.roleData = reported or nil
		end
		if m.role == nil and not CommDKP:IsPlaceholderMeta("role", src.role) then
			m.role = src.role; rep.role = reported or nil
		end
		if m.version == nil and not CommDKP:IsPlaceholderMeta("version", src.version) then
			m.version = src.version; rep.version = reported or nil
		end
		if m.class == nil and not badClass(src.class) then
			m.class = src.class; rep.class = reported or nil
		end
	end
	-- (1) Self overlay (fixes RC-13: an officer adding themselves gets their own version at once).
	if CommDKP:HasFullPlayerName() then
		local me = CommDKP:GetPlayerName()
		local myClass
		if type(UnitClass) == "function" then
			local ok, _, token = pcall(UnitClass, "player")
			if ok and not (_G.issecretvalue and token ~= nil and _G.issecretvalue(token)) then myClass = token end
		end
		merge(me, { version = core.SemVer, spec = core.LastTalBuildSent, roleData = core.LastTalRoleSent, class = myClass }, true)
	end
	-- (2) Session cache of player-reported values.
	if type(core.PlayerMeta) == "table" then
		if onlyName ~= nil then
			merge(onlyName, core.PlayerMeta[onlyName], true)
		else
			for name, e in pairs(core.PlayerMeta) do merge(name, e, true) end
		end
	end
	-- (3) Rows, then (4) Profiles, of every team.
	local teams = CommDKP:GetTeamIndexList()
	for _, team in ipairs(teams) do
		local rows = CommDKP:GetTable(CommDKP_DKPTable, true, team)
		if type(rows) == "table" then
			for i = 1, #rows do
				local row = rows[i]
				if type(row) == "table" then merge(row.player, row, false) end
			end
		end
	end
	for _, team in ipairs(teams) do
		local profs = CommDKP:GetTable(CommDKP_Profiles, true, team)
		if type(profs) == "table" then
			if onlyName ~= nil then
				merge(onlyName, profs[onlyName], false)
			else
				for name, p in pairs(profs) do merge(name, p, false) end
			end
		end
	end
	return index
end

-- AD-26.2.4: fill a row from known meta. Never inserts rows, sends messages or redraws (safe inside any loop).
function CommDKP:HydratePlayerRow(row, index)
	if type(row) ~= "table" then return row end
	if type(row.player) == "string" and row.player ~= "" then
		index = index or CommDKP:BuildKnownMetaIndex(row.player)
		local m = index[row.player]
		if m then
			local rep = m.reported or {}
			if m.class and (row.class == nil or row.class == "None" or row.class == "NONE") then row.class = m.class end
			local specChanged = false
			if m.spec and (CommDKP:IsPlaceholderMeta("spec", row.spec) or rep.spec
					or (CommDKP:IsRealSpec(m.spec) and not CommDKP:IsRealSpec(row.spec))) then
				if row.spec ~= m.spec then specChanged = true end
				row.spec = m.spec
			end
			if CommDKP:IsPlaceholderMeta("role", row.role) or specChanged or rep.roleData or rep.spec then
				local src = m.roleData or m.spec
				local r = src and CommDKP.ResolveRoleForClassAndSpec and CommDKP:ResolveRoleForClassAndSpec(row.class, src) or nil
				if not CommDKP:IsPlaceholderMeta("role", r) then row.role = r
				elseif not CommDKP:IsPlaceholderMeta("role", m.role) then row.role = m.role end
			end
			if m.version and (CommDKP:IsPlaceholderMeta("version", row.version) or rep.version) then row.version = m.version end
		end
	end
	if row.version == nil then row.version = "Unknown" end   -- BR-18.13
	return row
end

-- AD-26.2.4: hydrate every row of one team (broadcast heal; index = pre-overwrite snapshot).
function CommDKP:RestoreKnownPlayerMeta(team, index)
	local rows = CommDKP:GetTable(CommDKP_DKPTable, true, team)
	if type(rows) ~= "table" then return end
	for i = 1, #rows do
		if type(rows[i]) == "table" then CommDKP:HydratePlayerRow(rows[i], index) end
	end
end

-- AD-26.2.5 (BR-18.9): leading-edge 1 s batched roster redraw; refreshes WorkingTable + DKPTable_Update.
function CommDKP:QueueRosterRedraw()
	if core.RosterRedrawPending then return end
	core.RosterRedrawPending = true
	C_Timer.After(1, function()
		core.RosterRedrawPending = false
		if CommDKP.UIConfig then
			if CommDKP.FilterDKPTable then CommDKP:FilterDKPTable(core.currentSort, "reset") end
			if CommDKP.UIConfig:IsShown() and CommDKP.DKPTable_Update then CommDKP:DKPTable_Update() end
		end
	end)
end

-- AD-26.2.6 (F1/F2): sorted, de-duplicated string team keys: DB teams + extraTeams keys + current team. Never empty.
function CommDKP:GetTeamIndexList(extraTeams)
	local seen, list = {}, {}
	local db = CommDKP:GetTable(CommDKP_DB, false)
	if type(db) == "table" and type(db.teams) == "table" then
		for k in pairs(db.teams) do
			local s = tostring(k); if not seen[s] then seen[s] = true; list[#list + 1] = s end
		end
	end
	if type(extraTeams) == "table" then
		for k in pairs(extraTeams) do
			local s = tostring(k); if not seen[s] then seen[s] = true; list[#list + 1] = s end
		end
	end
	local cur = tostring(CommDKP:GetCurrentTeamIndex())
	if not seen[cur] then seen[cur] = true; list[#list + 1] = cur end
	table.sort(list)
	return list
end

-- AD-26.2.7 (BR-18.8): true once the player's "First Last" name is known (never send under a bare first name).
function CommDKP:HasFullPlayerName()
	local n = CommDKP:GetPlayerName()
	return n ~= nil and n == core.PlayerFullName
end

-- AD-26.2.7 (F4): canonical sender name. A claimedName is trusted only if it extends the sender's first name (anti-spoof).
-- AD-30.1.5 (CDKP-022, BR-22.4): (1) "Sky-Stormsong" (surname in the realm slot) -> "Sky Stormsong" when that whole name
-- is a guild member or a row.player in any team; (2) a still-bare first name -> the unique row.player with that first word.
function CommDKP:ResolveSenderName(sender, claimedName)
	if type(sender) == "string" then                                      -- AD-30.1.5 (1): surname-in-realm-slot form
		local first, second = sender:match("^([^%s%-]+)%-([^%s%-]+)$")
		if first then
			local lc = (first .. " " .. second):lower()
			if type(IsInGuild) == "function" and IsInGuild() and type(GetNumGuildMembers) == "function" then
				for i = 1, (GetNumGuildMembers() or 0) do
					local r = CommDKP:NormalizeName((GetGuildRosterInfo(i)))
					if type(r) == "string" and r:lower() == lc then return r end
				end
			end
			for _, team in ipairs(CommDKP:GetTeamIndexList()) do
				local rows = CommDKP:GetTable(CommDKP_DKPTable, true, team)
				if type(rows) == "table" then
					for i = 1, #rows do
						local p = type(rows[i]) == "table" and rows[i].player
						if type(p) == "string" and p:lower() == lc then return p end
					end
				end
			end
		end
	end
	local n = CommDKP:ResolveRosterName(sender) or CommDKP:NormalizeName(sender) or sender
	core.SenderAlias = core.SenderAlias or {}
	if type(n) ~= "string" then return n end
	if claimedName ~= nil then
		local c = CommDKP:NormalizeName(claimedName)
		if type(c) == "string" and c ~= "" and (c == n or (not n:find(" ", 1, true) and c:match("^(%S+)") == n)) then
			core.SenderAlias[n] = c
			return c
		end
	end
	if n:find(" ", 1, true) then return n end
	if core.SenderAlias[n] then return core.SenderAlias[n] end
	local hit, count = nil, 0
	for r in pairs(CommDKP:GetGroupRosterNames()) do
		if type(r) == "string" and r:match("^(%S+)") == n then hit = r; count = count + 1 end
	end
	if count == 1 then return hit end
	if not n:find(" ", 1, true) then                                      -- AD-30.1.5 (2): row first-name fallback
		local ln, found = n:lower(), nil
		for _, team in ipairs(CommDKP:GetTeamIndexList()) do
			local rows = CommDKP:GetTable(CommDKP_DKPTable, true, team)
			if type(rows) == "table" then
				for i = 1, #rows do
					local p = type(rows[i]) == "table" and rows[i].player
					if type(p) == "string" and p:find(" ", 1, true) and p ~= found then
						local fw = p:match("^(%S+)")
						if fw and fw:lower() == ln then
							if found then return n end                  -- ambiguous: two distinct full names
							found = p
						end
					end
				end
			end
		end
		if found then return found end
	end
	return n
end

-- AD-26.3.2 (BR-18.6a): talents-only retries at about +10 / +30 / +60 s; the 3rd is final (fallback allowed).
function CommDKP:ScheduleTalentRetry()
	if core.TalentRetryPending or core.TalentRetryExhausted then return end
	local n = (core.TalentRetryCount or 0) + 1
	if n > 3 then return end
	core.TalentRetryCount = n
	core.TalentRetryPending = true
	core.TalentRetryGen = (core.TalentRetryGen or 0) + 1
	local gen = core.TalentRetryGen
	local delays = { 10, 20, 30 }
	C_Timer.After(delays[n], function()
		if gen ~= core.TalentRetryGen then return end
		core.TalentRetryPending = false
		CommDKP:SendTalentsAndRole({ talentsOnly = true, final = (n == 3) })
	end)
end

-- AD-26.3.2: invalidates any pending retry timer and resets the retry count.
function CommDKP:CancelTalentRetry()
	core.TalentRetryGen = (core.TalentRetryGen or 0) + 1
	core.TalentRetryPending = false
	core.TalentRetryCount = 0
end

-- AD-30.1.1 (CDKP-022; BR-18.4/18.10, BR-22.3): one debounced send timer. Seed: jitter 1-15 s, at most one reply per
-- seed SENDER per 60 s (map pruned on every seed, so it never outgrows the live seed senders). Toggle: skipped within
-- 300 s of the last pair. A request already covered by a later send is dropped; otherwise a timer that fires inside the
-- 10 s window is POSTPONED to the end of the window (BR-18.10 kept: <= 1 pair / 10 s). Re-arms (2 s, max 10) before init.
function CommDKP:QueueTalentSend(reason, delay, senderKey)
	local MIN_INTERVAL, SEED_COOLDOWN, MAX_POSTPONES = 10, 60, 6
	core.TalentSend = core.TalentSend or {}
	local st = core.TalentSend
	local now = (type(GetTime) == "function" and GetTime()) or 0
	if reason == "seed" then
		st.lastSeedBySender = st.lastSeedBySender or {}
		for k, at in pairs(st.lastSeedBySender) do
			if now - at >= SEED_COOLDOWN then st.lastSeedBySender[k] = nil end
		end
		local key = (type(senderKey) == "string" and senderKey ~= "") and senderKey or "?"
		if st.lastSeedBySender[key] then return false end
		st.lastSeedBySender[key] = now
		delay = 1 + math.random() * 14
	elseif reason == "toggle" then
		if st.lastPairAt and now - st.lastPairAt < 300 then return false end
	end
	delay = delay or 2
	-- newest request time wins: the timer must cover every request coalesced into it
	if not st.pendingRequestedAt or st.pendingRequestedAt < now then st.pendingRequestedAt = now end
	local due = now + delay
	if st.pendingDue and st.pendingDue <= due then return true end
	st.gen = (st.gen or 0) + 1
	local gen = st.gen
	st.pendingDue, st.pendingReason = due, reason
	C_Timer.After(delay, function()
		if gen ~= st.gen then return end
		st.pendingDue = nil
		-- AD-31.6 F-1: re-queues never re-run the seed (per-sender cooldown + jitter) or toggle (300 s) gates; those were
		-- decided when the request was accepted.
		local again = (reason == "seed" or reason == "toggle") and "requeue" or reason
		local reqAt = st.pendingRequestedAt
		if not core.Initialized then
			st.rearm = (st.rearm or 0) + 1
			if st.rearm <= 10 then CommDKP:QueueTalentSend(again, 2) end
			return
		end
		st.rearm = 0
		local t = (type(GetTime) == "function" and GetTime()) or 0
		if st.lastSentAt and reqAt and st.lastSentAt >= reqAt then   -- a send at/after the newest request covered it
			st.pendingRequestedAt, st.postpones = nil, 0
			return
		end
		if st.lastSentAt and t - st.lastSentAt < MIN_INTERVAL then     -- BR-18.10 window: postpone, never drop
			st.postpones = (st.postpones or 0) + 1
			if st.postpones <= MAX_POSTPONES then
				CommDKP:QueueTalentSend(again, MIN_INTERVAL - (t - st.lastSentAt) + 0.05)
			end
			return
		end
		st.pendingRequestedAt, st.postpones = nil, 0
		CommDKP:SendTalentsAndRole()
	end)
	return true
end

-- AD-30.1.3 (CDKP-022): what an incoming broadcast says about MY row. rows = array of row tables (DKPTable / Profiles).
-- "placeholder" if my row exists with a placeholder spec, role or version; "ok" if it is complete; "absent" if no row.
function CommDKP:IncomingSelfMetaState(rows)
	local me = CommDKP:HasFullPlayerName() and CommDKP:GetPlayerName() or nil
	if not me or type(rows) ~= "table" then return "absent" end
	for i = 1, #rows do
		local row = rows[i]
		if type(row) == "table" and row.player == me then
			if CommDKP:IsPlaceholderMeta("spec", row.spec) or CommDKP:IsPlaceholderMeta("role", row.role)
				or CommDKP:IsPlaceholderMeta("version", row.version) then return "placeholder" end
			return "ok"
		end
	end
	return "absent"
end

-- AD-30.1.7 (BR-22.1): session-only comm trace. core.CommTrace is never read from or written to SavedVariables.
function CommDKP:ToggleCommTrace()
	core.CommTrace = not core.CommTrace
	CommDKP:PrintAlways("Comm trace " .. (core.CommTrace and "ON" or "OFF") .. " (this session only): CDKProfileSend, CommDKPTalents, CommDKPRoles, CommDKPSeed.")
end

function CommDKP:CommTrace(fmt, ...)
	if not core.CommTrace then return end
	local ok, s = pcall(string.format, fmt, ...)
	CommDKP:PrintAlways("|cff9d9d9d[trace]|r " .. (ok and s or tostring(fmt)))
end

-- Enum.SendAddonMessageResult value -> name ("Success", "GeneralError", ...). true/nil (legacy senders) -> "Success".
function CommDKP:SendResultName(result)
	if result == nil or result == true then return "Success" end
	if result == false then return "Failed" end
	if not core.SendResultNames then
		core.SendResultNames = {}
		local e = _G.Enum and _G.Enum.SendAddonMessageResult
		if type(e) == "table" then for k, v in pairs(e) do core.SendResultNames[v] = tostring(k) end end
	end
	return core.SendResultNames[result] or ("Result" .. tostring(result))
end

-- Always recorded (cheap, session-only); traced only when core.CommTrace.
function CommDKP:RecordMetaSend(prefix, channel, resultName)
	core.LastMetaSend = { prefix = prefix, channel = channel, result = resultName, t = (type(GetTime) == "function" and GetTime()) or 0 }
	CommDKP:CommTrace("SEND %s ch=%s result=%s", tostring(prefix), tostring(channel), tostring(resultName))
end

function CommDKP:RecordMetaRecv(prefix, sender, name, teamsMatched, distribution)
	local selfEcho = CommDKP:IsSelf(sender)
	if not selfEcho then
		core.LastRemoteMetaRecv = { prefix = prefix, raw = sender, name = name, matched = teamsMatched or 0,
			dist = distribution, t = (type(GetTime) == "function" and GetTime()) or 0 }
	end
	CommDKP:CommTrace("RECV %s ch=%s from=%s -> %s matched=%s%s", tostring(prefix), tostring(distribution), tostring(sender),
		tostring(name), (teamsMatched or 0) > 0 and ("yes(" .. teamsMatched .. " team" .. (teamsMatched == 1 and "" or "s") .. ")") or "no",
		selfEcho and " (self echo)" or "")
end

-- /dkp test line formatter (headless-testable). rec = core.LastMetaSend / core.LastRemoteMetaRecv / core.LastBroadcastSelfMeta.
function CommDKP:FormatMetaTelemetry(kind, rec)
	if type(rec) ~= "table" then return "none" end
	local age = math.floor(((type(GetTime) == "function" and GetTime()) or 0) - (rec.t or 0))
	if kind == "send" then
		return string.format("%s ch=%s result=%s (%ds ago)", tostring(rec.prefix), tostring(rec.channel), tostring(rec.result), age)
	elseif kind == "recv" then
		return string.format("%s -> %s, matched=%s, %s ch=%s (%ds ago)", tostring(rec.raw), tostring(rec.name),
			(rec.matched or 0) > 0 and ("yes(" .. rec.matched .. ")") or "no", tostring(rec.prefix), tostring(rec.dist), age)
	end
	return string.format("%s (%s, from %s, %ds ago)", tostring(rec.state), tostring(rec.kind), tostring(rec.from or "?"), age)
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
-- AD-11.3 / AD-18.3: Encounter resolution
-- Precedence (BR-11.3.5): static ID -> static name -> static range -> stored custom ID -> new discovery.
-------------------------------------
local function IsSecretValue(v)
	return issecretvalue ~= nil and v ~= nil and issecretvalue(v) and true or false
end

-- Static positional ID (ONYXIA, WORLD) -> zone, boss.
local function StaticByID(id)
	if id == nil then return nil end
	local search = CommDKP:Table_Search(core.EncounterList, id)
	if search and search[1] then
		local key, idx = search[1][1], search[1][2]
		local zi, list = core.RaidZoneIndex[key], core.BossList[key]
		if zi and list and list[idx] then return core.ZoneList[zi], list[idx] end
	end
end

-- Byte-exact name against ALL static BossList lists, in RaidMenuOrder -> zone, static name.
local function StaticByName(name)
	for _, key in ipairs(core.RaidMenuOrder) do
		local list, zi = core.BossList[key], core.RaidZoneIndex[key]
		if list and zi then
			for _, n in ipairs(list) do if n == name then return core.ZoneList[zi], n end end
		end
	end
end

-- Localized zone of the static ID range (inclusive) containing nid, or nil.
local function RangeZone(nid)
	local ranges = core.EncounterRangeList
	if type(nid) ~= "number" or type(ranges) ~= "table" then return nil end
	for _, key in ipairs(core.RaidMenuOrder) do
		local r, zi = ranges[key], core.RaidZoneIndex[key]
		if type(r) == "table" and zi and nid >= r[1] and nid <= r[2] then return core.ZoneList[zi] end
	end
end

-- Stored discovered ID -> zone, name. A range ID prefers its range zone so the lookup is deterministic.
local function CustomByID(nid)
	local ce = core.DB and core.DB.CustomEncounters
	if type(nid) ~= "number" or type(ce) ~= "table" then return nil end
	local rz = RangeZone(nid)
	if rz and type(ce[rz]) == "table" and type(ce[rz][nid]) == "string" then return rz, ce[rz][nid] end
	for zone, bosses in pairs(ce) do
		if type(bosses) == "table" and type(bosses[nid]) == "string" then return zone, bosses[nid] end
	end
end

-- Pure lookup by ID (no writes). Returns zoneName, bossName, source ("static" | "custom"), or nil.
function CommDKP:ResolveEncounter(id)
	if id == nil or IsSecretValue(id) then return nil end
	local zone, boss = StaticByID(id)
	if zone then return zone, boss, "static" end
	zone, boss = CustomByID(tonumber(id))
	if zone then return zone, boss, "custom" end
	return nil
end

-- Returns zoneName, bossName, source ("static" | "name" | "range" | "custom"), isNew; or nil (not a DKP encounter).
function CommDKP:ResolveOrRegisterEncounter(encounterID, encounterName)
	if IsSecretValue(encounterID) or IsSecretValue(encounterName) then return nil end
	-- 1. static positional ID (wins even over the name)
	local zone, boss = StaticByID(encounterID)
	if zone then return zone, boss, "static", false end

	local hasName = type(encounterName) == "string" and encounterName ~= ""
	-- 2. static name, whatever the ID (order inside the encrypted ranges does not matter)
	if hasName then
		zone, boss = StaticByName(encounterName)
		if zone then return zone, boss, "name", false end
	end

	local nid = tonumber(encounterID)
	-- 3. static range: zone from the range, boss = live name; registered so it shows in the menus
	zone = RangeZone(nid)
	if zone then
		if not hasName or not core.DB then return nil end
		core.DB.CustomEncounters = core.DB.CustomEncounters or {}
		local bosses = core.DB.CustomEncounters[zone] or {}
		core.DB.CustomEncounters[zone] = bosses
		local isNew = bosses[nid] ~= encounterName
		if isNew then bosses[nid] = encounterName end
		return zone, encounterName, "range", isNew
	end

	-- 4. stored custom ID (future Forever phases already discovered)
	zone, boss = CustomByID(nid)
	if zone then return zone, boss, "custom", false end

	-- 5. new discovery (unchanged from AD-11.3)
	if not hasName or not nid or not core.DB then return nil end
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

-- AD-18.3: Boss Killed menu selection. Static row: (raidKey, index). Discovered row: (encounterID, zone).
-- A bare ID (legacy callers, tests) falls back to ResolveEncounter. Returns zone, boss, source, or nil.
function CommDKP:ResolveMenuBoss(a1, a2)
	if type(a1) == "string" and type(a2) == "number" then
		local list, zi = core.BossList[a1], core.RaidZoneIndex[a1]
		if list and zi and type(list[a2]) == "string" then return core.ZoneList[zi], list[a2], "static" end
		return nil
	end
	local ce = core.DB and core.DB.CustomEncounters
	if type(a2) == "string" and type(ce) == "table" and type(ce[a2]) == "table" and type(ce[a2][a1]) == "string" then
		return a2, ce[a2][a1], "custom"
	end
	return CommDKP:ResolveEncounter(a1)
end

-- AD-18.4: default boss context = first boss of the first menu raid (enUS "The Barrow Deeps" / "Deepscar Matriarch").
-- Never nil: "" when the catalog is missing, so string concatenation at award time cannot error.
function CommDKP:GetDefaultBossContext()
	local key = core.RaidMenuOrder and core.RaidMenuOrder[1]
	local zi = key and core.RaidZoneIndex and core.RaidZoneIndex[key]
	local list = key and core.BossList and core.BossList[key]
	return (zi and core.ZoneList and core.ZoneList[zi]) or "", (list and list[1]) or ""
end

-- AD-18.4: a stored zone is valid when it is a current static zone or a discovered (CustomEncounters) zone.
function CommDKP:IsKnownBossZone(zone, customEncounters)
	if type(zone) ~= "string" or zone == "" then return false end
	for _, z in ipairs(core.ZoneList or {}) do if z == zone then return true end end
	return type(customEncounters) == "table" and type(customEncounters[zone]) == "table"
end

-- AD-18.4 (BR-11.2.3): idempotent repair of a stale/retired saved zone. Touches ONLY CurrentRaidZone/LastKilledBoss.
-- Returns true when it changed something.
function CommDKP:RepairBossContext(bossargs, customEncounters)
	if type(bossargs) ~= "table" or CommDKP:IsKnownBossZone(bossargs.CurrentRaidZone, customEncounters) then return false end
	bossargs.CurrentRaidZone, bossargs.LastKilledBoss = CommDKP:GetDefaultBossContext()
	return true
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
-- AD-17.2 (CDKP-010): the one read of the hovered item. TooltipUtil first, tooltip.GetItem second.
-- nil (never an error) for a hidden/absent tooltip, a missing API, an empty tooltip or a secret link.
-- Self-contained (no file-local upvalues): the headless tests extract it verbatim.
-------------------------------------
function CommDKP:GetHoveredItemLink(tooltip)
	tooltip = tooltip or _G.GameTooltip
	if type(tooltip) ~= "table" or type(tooltip.IsShown) ~= "function" then return nil end
	local okShown, shown = pcall(tooltip.IsShown, tooltip)
	if not okShown or not shown then return nil end
	local isSecret = _G.issecretvalue
	local function usable(ok, link)
		if not ok or link == nil then return nil end
		if isSecret and isSecret(link) then return nil end
		if type(link) ~= "string" or link == "" then return nil end
		return link
	end
	local TU, link = _G.TooltipUtil, nil
	if type(TU) == "table" and type(TU.GetDisplayedItem) == "function" then
		local ok, _, l = pcall(TU.GetDisplayedItem, tooltip)
		link = usable(ok, l)
	end
	if not link and type(tooltip.GetItem) == "function" then
		local ok, _, l = pcall(tooltip.GetItem, tooltip)
		link = usable(ok, l)
	end
	return link
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
