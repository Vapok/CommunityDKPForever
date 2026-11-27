local _, core = ...;
local _G = _G;
local CommDKP = core.CommDKP;
local L = core.L;

-- AD-9.7: Forever change log text (empty CHANGELOGn keys are skipped, no blank gaps). AD-33: the window title lives in CreateChangeLog.
function CommDKP:BuildChangeLogText()
	local parts = {}
	for i=1,10 do local s=L["CHANGELOG"..i]; if s and s~="" then parts[#parts+1]=s end end
	return table.concat(parts, "\n\n")
end

local OptionsLoaded = false;
local LibDD = LibStub:GetLibrary("LibUIDropDownMenu-4.0");
local DD = CommDKP.DD                     -- AD-16.3: roster selectors (SortButtons.class.t, TeamViewChangerDropDown)
local W = CommDKP.Widgets


function CommDKP_RestoreFilterOptions()  		-- restores default filter selections
	CommDKP.UIConfig.search:SetText("")              -- §12.3.1: the "Search" hint is a placeholder, never the value
	CommDKP.UIConfig.search:ClearFocus()
	core.WorkingTable = CopyTable(CommDKP:GetTable(CommDKP_DKPTable, true))
	core.CurView = "all"
	core.CurSubView = "all"
	for i=1, 10 do
		CommDKP.ConfigTab1.checkBtn[i]:SetChecked(true)
	end
	CommDKP.ConfigTab1.checkBtn[11]:SetChecked(false)
	CommDKP.ConfigTab1.checkBtn[12]:SetChecked(false)
	CommDKP.ConfigTab1.checkBtn[13]:SetChecked(false)
	CommDKPFilterChecks(CommDKP.ConfigTab1.checkBtn[1])
end

-- Focus z-order between UIConfig (DIALOG) and the Change Log window. Distinct strata, not frame levels:
-- The template window's CloseButton sits at a very high frame level, so within the same strata it
-- bleeds through UIConfig. A lower strata (MEDIUM) always renders below every child of a higher one.
-- UX §10.1.3 (supersedes §9.1.4): registry of template "floaters". One focused floater (or one focused
-- group) sits in FULLSCREEN, every other floater in MEDIUM.
-- FULLSCREEN (not FULLSCREEN_DIALOG): still above UIConfig (DIALOG), but BELOW dropdown
-- lists / Menu frames (FULLSCREEN_DIALOG), so dropdowns opened from a floater render on top of it.
local FOCUS_STRATA, BACK_STRATA = "FULLSCREEN", "MEDIUM"
local FLOATERS = {}                  -- [frame] = groupKey (string) or true
CommDKP.FocusedWindow = nil          -- last focus target (a floater, UIConfig, or nil)
local popupActive, popupReturn = false, nil

local function HookFloaterScript(f, event, fn)
	if f.HookScript then
		f:HookScript(event, fn)
	elseif f.SetScript then         -- headless mocks without HookScript
		local prev = f.GetScript and f:GetScript(event)
		f:SetScript(event, function(...)
			if prev then prev(...) end
			fn(...)
		end)
	end
end

function CommDKP:RegisterFloater(f, group)
	if not f or FLOATERS[f] then return end
	FLOATERS[f] = group or true
	if f.SetFrameStrata then f:SetFrameStrata(BACK_STRATA) end
	HookFloaterScript(f, "OnMouseDown", function(self) CommDKP:FocusWindow(self) end)
	HookFloaterScript(f, "OnShow", function(self)
		local prev = CommDKP.FocusedWindow
		self.cdkpReturnFocus = (prev ~= self) and prev or nil
		CommDKP:FocusWindow(self)
	end)
	HookFloaterScript(f, "OnHide", function(self)
		if CommDKP.FocusedWindow ~= self then return end
		local r = self.cdkpReturnFocus; self.cdkpReturnFocus = nil
		if r and r:IsShown() then CommDKP:FocusWindow(r) else CommDKP:FocusWindow(nil) end
	end)
end

function CommDKP:FocusWindow(target)             -- target: a floater, CommDKP.UIConfig, or nil
	if popupActive then                          -- a StaticPopup is up: remember the request, raise nothing
		if target ~= nil then popupReturn = target end
		return
	end
	CommDKP.FocusedWindow = target
	local group = target and FLOATERS[target]
	for f, g in pairs(FLOATERS) do
		local front = (target ~= nil) and (f == target or (type(group) == "string" and g == group))
		f:SetFrameStrata(front and FOCUS_STRATA or BACK_STRATA)
	end
	if group and target.Raise then target:Raise() end   -- clicked member on top within its group
end

-- StaticPopups live in DIALOG: a FULLSCREEN floater would cover them (the §9 NOTIFY_ROLLS trap, now general).
function CommDKP:ShowPopupOverFloaters(which, returnTo)
	local d = StaticPopupDialogs[which]
	popupReturn = returnTo or CommDKP.FocusedWindow
	CommDKP:FocusWindow(nil)                     -- everything -> MEDIUM, before the hold starts
	popupActive = true
	if d then
		local userOnHide = d.cdkpUserOnHide or d.OnHide
		d.cdkpUserOnHide = userOnHide
		d.OnHide = function(...)
			if userOnHide then userOnHide(...) end
			popupActive = false
			local r = popupReturn; popupReturn = nil
			if r and r:IsShown() then CommDKP:FocusWindow(r) end
		end
	end
	local shown = StaticPopup_Show(which)
	if not shown then                            -- popup suppressed: never wedge the hold
		popupActive = false
		local r = popupReturn; popupReturn = nil
		if r and r.IsShown and r:IsShown() then CommDKP:FocusWindow(r) end
	end
	return shown
end

function CommDKP:FocusChangeLog(focused)         -- unchanged API for existing call sites/tests
	if focused then return CommDKP:FocusWindow(CommDKP.ChangeLogDisplay) end
	if CommDKP.ChangeLogDisplay then CommDKP.ChangeLogDisplay:SetFrameStrata(BACK_STRATA) end
end

function CommDKP:Toggle()        -- toggles IsShown() state of CommDKP.UIConfig, the entire addon window
	core.CommDKPUI =  core.CommDKPUI or CommDKP:CreateMenu();
	core.CommDKPUI:SetShown(not core.CommDKPUI:IsShown())
	CommDKP.UIConfig:SetFrameLevel(10)
	if core.CommDKPUI:IsShown() then CommDKP:FocusWindow(CommDKP.UIConfig) end   -- UIConfig to the front; floaters -> MEDIUM
	CommDKP.UIConfig:SetClampedToScreen(true)
	if core.BiddingWindow then core.BiddingWindow:SetFrameLevel(6) end
	if core.ModesWindow then core.ModesWindow:SetFrameLevel(2) end

	CommDKP:UpdateGuildUIState()   -- AD-20.2.2 (CDKP-013a): resolve IsOfficer, tabs 2/3 shown iff officer, Roster notice
	if core.CommDKPUI:IsShown() then CommDKP:QueueTalentSend("toggle") end   -- AD-26.5.1 (d) / BR-18.4(d)

	if not OptionsLoaded then
		core.CommDKPOptions = core.CommDKPOptions or CommDKP:Options()
		OptionsLoaded = true;
	end

	if #CommDKP:GetTable(CommDKP_Whitelist) > 0 and core.IsOfficer then 				-- broadcasts whitelist any time the window is opened if one exists (help ensure everyone has the information even if they were offline when it was created)
		CommDKP.Sync:SendData("CDKPWhitelist", CommDKP:GetTable(CommDKP_Whitelist))   -- Only officers propagate the whitelist, and it is only accepted by players that are NOT the GM (prevents overwriting new Whitelist set by GM, if any.)
	end

	if core.CurSubView == "raid" then
		CommDKP:ViewLimited(true)
	elseif core.CurSubView == "standby" then
		CommDKP:ViewLimited(false, true)
	elseif core.CurSubView == "raid and standby" then
		CommDKP:ViewLimited(true, true)
	elseif core.CurSubView == "core" then
		CommDKP:ViewLimited(false, false, true)
	elseif core.CurSubView == "all" then
		CommDKP:ViewLimited()
	end

	core.CommDKPUI:SetScale(core.DB.defaults.CommDKPScaleSize)
	if CommDKP.ConfigTab6.history and CommDKP.ConfigTab6:IsShown() then
		CommDKP:DKPHistory_Update(true)
	elseif CommDKP.ConfigTab5 and CommDKP.ConfigTab5:IsShown() then
		CommDKP:LootHistory_Update(L["NOFILTER"]);
	end

	CommDKP:StatusVerify_Update()
	CommDKP:DKPTable_Update()
end

---------------------------------------
-- Sort Function
---------------------------------------
local SortButtons = {}

function CommDKP:FilterDKPTable(sort, reset)          -- filters core.WorkingTable based on classes in classFiltered table. core.currentSort should be used in most cases
	local parentTable;

	if not CommDKP.UIConfig then 
		return
	end

	if core.CurSubView ~= "all" then
		if core.CurSubView == "raid" then
			CommDKP:ViewLimited(true)
		elseif core.CurSubView == "standby" then
			CommDKP:ViewLimited(false, true)
		elseif core.CurSubView == "raid and standby" then
			CommDKP:ViewLimited(true, true)
		elseif core.CurSubView == "core" then
			CommDKP:ViewLimited(false, false, true)
		end
		parentTable = core.WorkingTable;
	else
		parentTable = CommDKP:GetTable(CommDKP_DKPTable, true);
	end

	core.WorkingTable = {}

	-- AD-28.2.2 (CDKP-020): group / online membership built ONCE per pass with the AD-15.1 helpers.
	-- [11] In Party/Raid and [13] Not In Raid are exclusive ([11] wins if both are ever set); [12] Online ANDs with either.
	local cb = CommDKP.ConfigTab1.checkBtn
	local wantGroup    = cb[11]:GetChecked() and true or false
	local wantNotGroup = (not wantGroup) and cb[13]:GetChecked() and true or false
	local wantOnline   = cb[12]:GetChecked() and true or false
	local isSecret     = _G.issecretvalue

	local groupSet                                   -- normalized name -> true (raid or 5-man party; self via IsSelf, F1)
	if wantGroup or wantNotGroup then
		groupSet = CommDKP:GetGroupRosterNames()
	end

	local onlineSet                                  -- normalized name -> true for online guild members (D-28.4)
	if wantOnline then
		onlineSet = {}
		for i = 1, (GetNumGuildMembers() or 0) do
			local gName, _, _, _, _, _, _, _, online = GetGuildRosterInfo(i)
			if gName and not (isSecret and isSecret(gName)) and not (isSecret and isSecret(online)) and online then
				local n = CommDKP:NormalizeName(gName)
				if n and n ~= "" then onlineSet[n] = true end
			end
		end
	end

	for k,v in ipairs(parentTable) do
		local searchFilter = true

		if CommDKP.UIConfig.search:GetText() ~= L["SEARCH"] and CommDKP.UIConfig.search:GetText() ~= "" then
			if not strfind(string.upper(v.player), string.upper(CommDKP.UIConfig.search:GetText())) and not strfind(string.upper(v.class), string.upper(CommDKP.UIConfig.search:GetText()))
			and not strfind(string.upper(v.role), string.upper(CommDKP.UIConfig.search:GetText())) and not strfind(string.upper(v.rankName), string.upper(CommDKP.UIConfig.search:GetText())) 
			and not strfind(string.upper(v.spec), string.upper(CommDKP.UIConfig.search:GetText())) then
				searchFilter = false;
			end
		end

		if core.classFiltered[v.class] == true and searchFilter == true then
			local n = CommDKP:NormalizeName(v.player) or ""
			local groupOK = true
			if groupSet then
				local inGroup = groupSet[n] == true or CommDKP:IsSelf(v.player)
				groupOK = (wantGroup and inGroup) or (wantNotGroup and not inGroup)
			end
			local onlineOK = (not wantOnline) or onlineSet[n] == true
			if groupOK and onlineOK then
				tinsert(core.WorkingTable, v)          -- exactly one insert per row (BR-20.4)
			end
		end
	end

	if #core.WorkingTable == 0 then  		-- removes all filter settings if the filter combination results in an empty table
		--CommDKP_RestoreFilterOptions()
		CommDKP.DKPTable.Rows[1].DKPInfo[1]:SetText("|cffff0000No Entries Returned.|r")
		CommDKP.DKPTable.Rows[1]:Show()
	end
	CommDKP:SortDKPTable(sort, reset);
end

function CommDKP:SortDKPTable(id, reset)        -- reorganizes core.WorkingTable based on id passed. Avail IDs are "class", "player" and "dkp"
	local button;                                 -- passing "reset" forces it to do initial sort (A to Z repeatedly instead of A to Z then Z to A toggled)

	if id == "class" or id == "rank" or id == "role" or id == "spec" or id == "version" then
		button = SortButtons.class
	elseif id == "spec" then                -- doesn't allow "spec" to be sorted.
		CommDKP:DKPTable_Update()
		return;
	else
		button = SortButtons[id]
	end

	if button == nil then
		return;
	end

	if reset and reset ~= "Clear" then                         -- reset is useful for check boxes when you don't want it repeatedly reversing the sort
		button.Ascend = button.Ascend
	else
		button.Ascend = not button.Ascend
	end
	for k, v in pairs(SortButtons) do
		if v ~= button then
			v.Ascend = nil
		end
	end
	table.sort(core.WorkingTable, function(a, b)
		-- Validate Data and Fix Discrepencies
		if a[button.Id] == nil then
			print("[CommunityDKP] Bad DKP Player Record Found: "..a.player)
			core.RepairWorking = true;
			return false;
		end
		if b[button.Id] == nil then
			print("[CommunityDKP] Bad DKP Player Record Found: "..b.player)
			core.RepairWorking = true;
			return false;
		end

		if button.Ascend then
			if id == "dkp" then
				return a[button.Id] > b[button.Id]
			elseif id == "class" or id == "rank" or id == "role" or id == "spec" or id == "version" then
				if a[button.Id] < b[button.Id] then
					return true
				elseif a[button.Id] > b[button.Id] then
					return false
				else
					return a.dkp > b.dkp
				end
			else
				return a[button.Id] < b[button.Id]
			end
		else
			if id == "dkp" then
				return a[button.Id] < b[button.Id]
			elseif id == "class" or id == "rank" or id == "role" or id == "spec" or id == "version" then
				if a[button.Id] > b[button.Id] then
					return true
				elseif a[button.Id] < b[button.Id] then
					return false
				else
					return a.dkp > b.dkp
				end
			else
				return a[button.Id] > b[button.Id]
			end
		end
	end)
	core.currentSort = id;
	CommDKP:DKPTable_Update()
end

---------------------------------------
-- UX §11.1.3: expand / collapse workspace model (core.ShowState == true -> expanded)
-- Widths keep the legacy 550 / 1106 geometry: the roster's FauxScrollFrame bar ends at x ~543 and the pane
-- scroll bar hangs ~22 px right of TabMenu (x 546 + 535), so the spec's 540 / 1080 would clip both bars.
---------------------------------------
local W_EXPANDED, W_COLLAPSED = 1106, 550
CommDKP.UIConfigWidths = { expanded = W_EXPANDED, collapsed = W_COLLAPSED }

local function PinTopLeft(f)
	local l, t = f:GetLeft(), f:GetTop()          -- frame-scale coords; SetPoint offsets are frame-scale too
	if not (l and t) then return end
	f:ClearAllPoints()
	f:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", l, t)
end

-- Every expand/collapse goes through here (side-tabs, the « Collapse pill, ResetPosition).
function CommDKP:SetWorkspaceShown(shown)
	local f = CommDKP.UIConfig
	if not f then return end
	PinTopLeft(f)                                 -- grow/shrink rightward: medallion and roster never jump
	core.ShowState = shown and true or false
	f:SetWidth(core.ShowState and W_EXPANDED or W_COLLAPSED)
	if f.TabMenu then f.TabMenu:SetShown(core.ShowState) end
	for i, tab in ipairs(f.SideTabs or {}) do tab:cdkpSetSelected(core.ShowState and i == f.activeTab) end
end

-- Pane switch only (no width change): ConfigMenuTabs' shared pane logic on the main TabMenu.
function CommDKP:ShowConfigPane(i)
	local f = CommDKP.UIConfig
	if f and f.TabMenu then CommDKP:ShowTabPane(f.TabMenu, i) end
end

-- AD-19.2 (012d) (c) / BR-12.4: a click on the already-active tab while expanded is a silent no-op (returns false so
-- SetTabs' click closure plays no sound). Collapsed + click expands on that tab. force = true is unchanged (OnShow,
-- Settings launcher). Collapsing is only done by the « Collapse pill.
function CommDKP:SelectSideTab(i, force)
	local f = CommDKP.UIConfig
	if not f then return false end
	if not force and core.ShowState and f.activeTab == i then return false end   -- BR-12.4.1: silent no-op
	f.activeTab = i
	CommDKP:ShowConfigPane(i)
	local tab = f.SideTabs and f.SideTabs[i]
	if f.TabMenu and f.TabMenu.HeaderText and tab then f.TabMenu.HeaderText:SetText(tab.cdkpTitle) end
	CommDKP:SetWorkspaceShown(true)
	return true
end

-- AD-20.2.2 (CDKP-013a): single owner of the guild-dependent main-window state. Non-protected frames only (combat-safe).
local NOTINGUILD_TEXT = "Not in a guild - guild DKP and officer features are disabled."
function CommDKP:UpdateGuildUIState(force)
	CommDKP:CheckOfficer(force)
	local inGuild, officer = IsInGuild() and true or false, core.IsOfficer == true
	core.LastInGuild = inGuild
	local f = CommDKP.UIConfig
	if not f or not f.SideTabs then return end             -- UI not built yet; CreateMenu calls us at the end
	-- 1) officer tabs: shown ONLY when resolved true (nil -> hidden; fixes the tri-state leak)
	local t2, t3 = _G["CommDKPCommDKP.ConfigTabMenuTab2"], _G["CommDKPCommDKP.ConfigTabMenuTab3"]
	if t2 then t2:SetShown(officer) end
	if t3 then t3:SetShown(officer) end
	CommDKP:StackSideTabs(f, f.SideTabs, -42)              -- UX §11.1.4: close/open the gap both ways
	-- 2) active tab became hidden -> Filters, without changing expanded/collapsed state
	if not officer and (f.activeTab == 2 or f.activeTab == 3) then
		local wasExpanded = core.ShowState
		CommDKP:SelectSideTab(1, true)
		if not wasExpanded then CommDKP:SetWorkspaceShown(false) end
	end
	-- 3) Roster header notice (BR-13.2.1-13.2.3); NOTINGUILDNOTICE, never NOTINGUILD (bucket sentinel, AD-20.1.3 #5)
	if f.RosterCard then
		local show = core.GuildStateReady and not inGuild
		f.RosterCard:SetNote(show and (L["NOTINGUILDNOTICE"] or NOTINGUILD_TEXT) or "")
		local note = f.RosterCard.Header and f.RosterCard.Header.Note
		local pal = core.Palette or (core.Palettes and core.Palettes.Forever) or {}
		local col = pal.warning or pal.textMuted
		if note and col then note:SetTextColor(unpack(col)) end
	end
	-- 4) PM-13.3: an open DKP Modes window (officer writes/broadcasts) closes on demotion / leaving the guild
	if not officer and core.ModesWindow and core.ModesWindow:IsShown() then core.ModesWindow:Hide() end
end

-- AD-20.2.4: trailing ~1 s debounce for guild events (same pattern as QueueTalentRefresh).
function CommDKP:QueueGuildStateRefresh()
	core.GuildRefreshGen = (core.GuildRefreshGen or 0) + 1
	local gen = core.GuildRefreshGen
	C_Timer.After(1, function()
		if gen ~= core.GuildRefreshGen then return end
		CommDKP:UpdateGuildUIState(true)
	end)
end

function CommDKP:CreateMenu()

	-- UX §12.1.1 / AD-16.4 (d): PortraitFrameTemplate + ButtonFrameTemplateNoPortrait NineSlice (gold), rock Bg,
	-- no Inset well; plaque fallback when the template probe fails. Same code path as every "window" popup.
	-- chromeOpts nil: the title stays in the template's TitleContainer, after the medallion.
	local f = CommDKP.Widgets.CreateChromeFrame("CommDKPConfig", UIParent, "window",
		"CommunityDKP Forever  |cffB9A789" .. tostring(core.SemVer) .. "|r")
	CommDKP.UIConfig = f
	f:SetSize(W_EXPANDED, 590);
	f:SetPoint("TOPLEFT", UIParent, "TOPLEFT", 200, -120);   -- ALWAYS a TOPLEFT anchor (§11.1.3)
	f:SetClampedToScreen(true)
	f:SetClampRectInsets(-13, 42, 16, -8)                     -- medallion overhang (L/T) + side-tab column (R)
	f:SetMovable(true);
	f:EnableMouse(true);
	f:RegisterForDrag("LeftButton");
	f:SetScript("OnDragStart", f.StartMoving);
	f:SetScript("OnDragStop", f.StopMovingOrSizing);
	CommDKP.UIConfig:SetFrameStrata("DIALOG")       -- unchanged (§10.1.3); outside the floater registry
	CommDKP.UIConfig:SetFrameLevel(10)
	CommDKP.UIConfig:SetScript("OnMouseDown", function(self)
		self:SetFrameLevel(10)
		CommDKP:FocusWindow(CommDKP.UIConfig)   -- both floaters drop to MEDIUM behind UIConfig (DIALOG)
		if core.ModesWindow then core.ModesWindow:SetFrameLevel(6) end
		if core.BiddingWindow then core.BiddingWindow:SetFrameLevel(2) end
	end)
	f.closeBtn = f.CloseButton                                -- legacy alias: every UIConfig.closeBtn reference keeps working
	tinsert(UISpecialFrames, f:GetName()); -- Sets frame to close on "Escape"

	-- UX §11.1.2 / AD-33.1: top-left corner medallion (decorative; clicks/drags fall through) + title clearance.
	-- Shared with the Change Log through W.AttachMedallion (BR-25.5).
	W.AttachMedallion(f, "CommDKPConfigMedallion")
	f.Version = f.TitleLabel                                -- legacy alias for UIConfig.Version

	-- AD-19.2 (012d) (f) / UX §13.4.4 / BR-12.7: borderless 16x16 Change Log glyph just left of [X].
	-- Toggles the on-demand Change Log; never writes HideChangeLogs.
	local clBtn = CreateFrame("Button", "CommDKPConfigChangeLogButton", f)
	clBtn:SetSize(16, 16)
	clBtn:SetHitRectInsets(-2, -2, -2, -2)
	if f.CloseButton then
		clBtn:SetPoint("RIGHT", f.CloseButton, "LEFT", -2, 0)
		clBtn:SetFrameLevel(f.CloseButton:GetFrameLevel())
	else
		clBtn:SetPoint("TOPRIGHT", f, "TOPRIGHT", -28, -4)
	end
	clBtn.Icon = clBtn:CreateTexture(nil, "ARTWORK")
	clBtn.Icon:SetAllPoints()
	clBtn.Icon:SetTexture(W.TEX.changelog)
	local function PalColor(role) return (core.Palette or core.Palettes.Forever)[role] or core.Palettes.Forever[role] end
	local function PaintCL(self, over)
		self.Icon:SetVertexColor(unpack(PalColor(over and "gold" or "textMuted")))
	end
	PaintCL(clBtn, false)
	clBtn:SetScript("OnEnter", function(self)
		PaintCL(self, true)
		if not GameTooltip then return end
		GameTooltip:SetOwner(self, "ANCHOR_BOTTOMLEFT")
		GameTooltip:SetText(L["CHANGELOGBTN"] or "Change Log", 1, 0.82, 0)
		GameTooltip:AddLine(tostring(core.SemVer), unpack(PalColor("textMuted")))
		GameTooltip:Show()
	end)
	clBtn:SetScript("OnLeave", function(self)
		PaintCL(self, false)
		if GameTooltip then GameTooltip:Hide() end
	end)
	clBtn:SetScript("OnMouseDown", function(self) self.Icon:ClearAllPoints(); self.Icon:SetPoint("TOPLEFT", 1, -1); self.Icon:SetPoint("BOTTOMRIGHT", 1, -1) end)
	clBtn:SetScript("OnMouseUp", function(self) self.Icon:ClearAllPoints(); self.Icon:SetAllPoints() end)
	clBtn:SetScript("OnClick", function() CommDKP:ToggleChangeLog() end)
	f.ChangeLogBtn = clBtn
	---------------------------------------
	-- Create and Populate Tab Menu and DKP Table
	---------------------------------------
	CommDKP.TabMenu = CommDKP:ConfigMenuTabs();        -- Create and populate Config Menu Tabs
	-- UX §12.3.1 Roster Card (516 x 524 at (14, -52)): 28 px "DKP Roster" page header, 24 px column strip,
	-- 23 rows + rail, 34 px footer (pip · search · count · team selector). DKPTable_Create builds into its body.
	CommDKP.UIConfig.RosterCard = W.CreateCard(CommDKP.UIConfig, L["CARDROSTER"], 516, 524, { page = true, footer = 34 })
	CommDKP.UIConfig.RosterCard:SetPoint("TOPLEFT", CommDKP.UIConfig, "TOPLEFT", 14, -52)
	local rosterBody, rosterFooter = CommDKP.UIConfig.RosterCard.Body, CommDKP.UIConfig.RosterCard.Footer
	CommDKP:DKPTable_Create();                        -- Create DKPTable and populate rows
	---------------------------------------
	-- DKP Table Header and Sort Buttons
	---------------------------------------

	-- §12.2.10 column strip (24 px, global name kept so the "$parent..." sort-button names still resolve).
	CommDKP.DKPTable_Headers = W.CreateColumnStrip(rosterBody, 24, "CommDKPDKPTableHeaders")
	CommDKP.DKPTable_Headers:SetPoint("TOPLEFT", rosterBody, "TOPLEFT", 0, 0)
	CommDKP.DKPTable_Headers:SetPoint("TOPRIGHT", rosterBody, "TOPRIGHT", 0, 0)
	CommDKP.DKPTable_Headers:Show()
	---------------------------------------
	-- Sort Buttons
	--------------------------------------- 

	SortButtons.player = CreateFrame("Button", "$ParentSortButtonPlayer", CommDKP.DKPTable_Headers, "BackdropTemplate")
	SortButtons.class = CreateFrame("Button", "$ParentSortButtonClass", CommDKP.DKPTable_Headers, "BackdropTemplate")
	SortButtons.dkp = CreateFrame("Button", "$ParentSortButtonDkp", CommDKP.DKPTable_Headers, "BackdropTemplate")
	
	SortButtons.class:SetPoint("CENTER", CommDKP.DKPTable_Headers, "LEFT", core.TableWidth / 2, 0)   -- centered on the 500 px table
	SortButtons.player:SetPoint("RIGHT", SortButtons.class, "LEFT")
	SortButtons.dkp:SetPoint("LEFT", SortButtons.class, "RIGHT")
	 
	for k, v in pairs(SortButtons) do
		v.Id = k
		v:SetSize((core.TableWidth/3)-1, core.TableRowHeight)
		if v.Id == "class" then
			v:SetScript("OnClick", function(self) CommDKP:SortDKPTable(core.CenterSort, "Clear") end)
		else
			v:SetScript("OnClick", function(self) CommDKP:SortDKPTable(self.Id, "Clear") end)
		end
	end
	SortButtons.player:SetSize((core.TableWidth*0.4)-1, core.TableRowHeight)
	SortButtons.class:SetSize((core.TableWidth*0.2)-1, core.TableRowHeight)
	SortButtons.dkp:SetSize((core.TableWidth*0.4)-1, core.TableRowHeight)

	SortButtons.player.t = W.CreateText(SortButtons.player, "label", L["PLAYER"], "CENTER")   -- §12.2.10 gold column label
	SortButtons.player.t:SetPoint("CENTER", SortButtons.player, "CENTER", 0, 0);

	-- center column dropdown (class, rank, spec etc..)
	-- §12.3.1: the one 18 px flat selector (92 wide) so it fits the 24 px strip with 3 px clearance (AC-9.4).
	SortButtons.class.t = DD:Create_UIDropDownMenu("CommDKPSortColDropdown", SortButtons.class)
	SortButtons.class.t:SetPoint("CENTER", SortButtons.class, "CENTER", 0, 0)
	SortButtons.class.t:SetHeight(18)
	DD:UIDropDownMenu_JustifyText(SortButtons.class.t, "CENTER")
	DD:UIDropDownMenu_SetWidth(SortButtons.class.t, 92)
	DD:UIDropDownMenu_SetText(SortButtons.class.t, L["CLASS"])
	DD:UIDropDownMenu_Initialize(SortButtons.class.t, function(self, level, menuList)

	local reason = DD:UIDropDownMenu_CreateInfo()
		reason.func = self.SetValue
		reason.text, reason.arg1, reason.arg2, reason.checked, reason.isNotRadio = L["CLASS"], "class", L["CLASS"], "class" == core.CenterSort, true
		DD:UIDropDownMenu_AddButton(reason)
		reason.text, reason.arg1, reason.arg2, reason.checked, reason.isNotRadio = L["SPEC"], "spec", L["SPEC"], "spec" == core.CenterSort, true
		DD:UIDropDownMenu_AddButton(reason)
		reason.text, reason.arg1, reason.arg2, reason.checked, reason.isNotRadio = L["RANK"], "rank", L["RANK"], "rank" == core.CenterSort, true
		DD:UIDropDownMenu_AddButton(reason)
		reason.text, reason.arg1, reason.arg2, reason.checked, reason.isNotRadio = L["ROLE"], "role", L["ROLE"], "role" == core.CenterSort, true
		DD:UIDropDownMenu_AddButton(reason)
		reason.text, reason.arg1, reason.arg2, reason.checked, reason.isNotRadio = L["VERSION"], "version", L["VERSION"], "version" == core.CenterSort, true
		DD:UIDropDownMenu_AddButton(reason)
	end)
	-- Dropdown Menu Function
	function SortButtons.class.t:SetValue(newValue, arg2)
		core.CenterSort = newValue
		SortButtons.class.Id = newValue;
		DD:UIDropDownMenu_SetText(SortButtons.class.t, arg2)
		CommDKP:SortDKPTable(newValue, "reset")
		core.currentSort = newValue;
		LibDD:CloseDropDownMenus()
	end
	SortButtons.dkp.t = W.CreateText(SortButtons.dkp, "label", nil, "CENTER")
	if core.DB.modes.mode == "Roll Based Bidding" then
		SortButtons.dkp.t:SetPoint("RIGHT", SortButtons.dkp, "RIGHT", -50, 0);
		SortButtons.dkp.t:SetText(L["TOTALDKP"]);

		SortButtons.dkp.roll = W.CreateText(SortButtons.dkp, "label", nil, "LEFT");
		SortButtons.dkp.roll:SetPoint("LEFT", SortButtons.dkp, "LEFT", 20, -1);
		SortButtons.dkp.roll:SetText(L["ROLLRANGE"])
	else
		SortButtons.dkp.t:SetPoint("CENTER", SortButtons.dkp, "CENTER", 0, 0);
		SortButtons.dkp.t:SetText(L["TOTALDKP"]);
	end
	----- Counter below DKP Table
	-- AD-19.2 (012d) (a) / UX §13.2: every footer element sits on the footer's vertical midline (y = 0).
	-- Slots: pip x 10 · search x 34-170 · counter centred at x 240 (174-306) · "Team:" label · dropdown x 350-500.
	local counter = CreateFrame("Frame", "CommDKPDisplayFrameCounter", rosterFooter)
	CommDKP.DKPTable.counter = counter
	counter:SetPoint("CENTER", rosterFooter, "LEFT", 240, 0)
	counter:SetSize(132, 30)

	counter.t = W.CreateText(counter, "caption", nil, "CENTER", "textMuted")
	counter.s = W.CreateText(counter, "caption", nil, "CENTER", "textMuted")
	for _, fs in ipairs({ counter.t, counter.s }) do
		if fs.SetWordWrap then fs:SetWordWrap(false) end
		if fs.SetJustifyH then fs:SetJustifyH("CENTER") end
	end
	-- counter.t / counter.s are written by TableFunctions.lua; the relayout follows every counter.s:SetText.
	-- s empty: t alone on the midline. s set: t above / s below, the 2-line block centred on the midline.
	local function RelayoutCounter()
		local s = counter.s:GetText()
		counter.t:ClearAllPoints(); counter.s:ClearAllPoints()
		if s == nil or s == "" then
			counter.t:SetPoint("CENTER", counter, "CENTER", 0, 0)
			counter.s:SetPoint("TOP", counter, "CENTER", 0, -1)
		else
			counter.t:SetPoint("BOTTOM", counter, "CENTER", 0, 1)
			counter.s:SetPoint("TOP", counter, "CENTER", 0, -1)
		end
	end
	counter.Relayout = RelayoutCounter
	RelayoutCounter()
	hooksecurefunc(counter.s, "SetText", RelayoutCounter)
	------------------------------
	-- Search Box
	------------------------------

	-- UX §13.2 footer: 136 x 22 at x 34. "Search" is a placeholder (it replaces the old hint-in-the-value text and its
	-- focus swap); FilterDKPTable's `~= L["SEARCH"] and ~= ""` check is unchanged and still correct.
	CommDKP.UIConfig.search = CreateFrame("EditBox", nil, rosterFooter)

	CommDKP.UIConfig.search:SetPoint("LEFT", rosterFooter, "LEFT", 34, 0)
	CommDKP.UIConfig.search:SetAutoFocus(false)
	CommDKP.UIConfig.search:SetMultiLine(false)
	CommDKP.UIConfig.search:SetSize(136, W.H)
	CommDKP.UIConfig.search:SetMaxLetters(50)
	CommDKP.UIConfig.search:SetScript("OnKeyUp", function(self)    -- clears text and focus on esc
		if (CommDKP.UIConfig.search:GetText():match("[%^%$%(%)%%%.%[%]%*%+%-%?]")) then
			CommDKP.UIConfig.search:SetText(string.gsub(CommDKP.UIConfig.search:GetText(), "[%^%$%(%)%%%.%[%]%*%+%-%?]", ""))
			--CommDKP.UIConfig.search:SetText(strsub(CommDKP.UIConfig.search:GetText(), 1, -2))
		else
			CommDKP:FilterDKPTable(core.currentSort, "reset")
		end
	end)
	CommDKP.UIConfig.search:SetScript("OnEscapePressed", function(self)    -- clears text and focus on esc
		self:SetText("")
		self:ClearFocus()
		CommDKP:FilterDKPTable(core.currentSort, "reset")
	end)
	CommDKP.UIConfig.search:SetScript("OnEnterPressed", function(self)    -- clears text and focus on enter
		self:ClearFocus()
	end)
	CommDKP.UIConfig.search:SetScript("OnTabPressed", function(self)    -- clears text and focus on tab
		self:ClearFocus()
	end)
	CommDKP.UIConfig.search:SetScript("OnEditFocusGained", function(self)
		self:HighlightText();
	end)
	CommDKP.UIConfig.search:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_RIGHT");
		GameTooltip:SetText(L["SEARCH"], 0.25, 0.75, 0.90, 1, true);
		GameTooltip:AddLine(L["SEARCHDESC"], 1.0, 1.0, 1.0, true);
		GameTooltip:Show();
	end)
	CommDKP.UIConfig.search:SetScript("OnLeave", function(self)
		GameTooltip:Hide();
	end)
	W.StyleEditBox(CommDKP.UIConfig.search, { placeholder = strtrim(L["SEARCH"]), align = "LEFT" })   -- after its SetScripts

	------------------------------
	-- Team view changer Drop Down
	------------------------------

		CommDKP.UIConfig.TeamViewChangerDropDown = DD:Create_UIDropDownMenu("CommDKPConfigReasonDropDown", rosterFooter);
		CommDKP.UIConfig.TeamViewChangerDropDown:SetPoint("RIGHT", rosterFooter, "RIGHT", -10, 0)   -- UX §13.2: pip-to-edge 10 = dropdown-to-edge 10
		-- tooltip on mouseOver
		CommDKP.UIConfig.TeamViewChangerDropDown:SetScript("OnEnter", 
			function(self) 
				GameTooltip:SetOwner(self, "ANCHOR_RIGHT");
				GameTooltip:SetText(L["TEAMCURRENTLIST"], 0.25, 0.75, 0.90, 1, true);
				GameTooltip:AddLine(L["TEAMCURRENTLISTDESC"], 1.0, 1.0, 1.0, true);
				GameTooltip:AddLine(L["WARNING"], 1.0, 0, 0, true);
				GameTooltip:AddLine(L["TEAMCURRENTLISTDESC2"], 1.0, 1.0, 1.0, true);
				GameTooltip:Show();
			end
		)
		CommDKP.UIConfig.TeamViewChangerDropDown:SetScript("OnLeave",
			function(self)
				GameTooltip:Hide()
			end
		)
		DD:UIDropDownMenu_SetWidth(CommDKP.UIConfig.TeamViewChangerDropDown, 150)
		DD:UIDropDownMenu_SetText(CommDKP.UIConfig.TeamViewChangerDropDown, CommDKP:GetCurrentTeamName())

		-- Create and bind the initialization function to the dropdown menu
		DD:UIDropDownMenu_Initialize(CommDKP.UIConfig.TeamViewChangerDropDown, 
			function(self, level, menuList)
				
				local dropDownMenuItem = DD:UIDropDownMenu_CreateInfo()
				dropDownMenuItem.func = self.SetValue

			
				teamList = CommDKP:GetGuildTeamList()

				for i=1, #teamList do
					dropDownMenuItem.text = teamList[i][2]
					dropDownMenuItem.arg1 = teamList[i][2] -- name
					dropDownMenuItem.arg2 = teamList[i][1] -- index
					dropDownMenuItem.checked = teamList[i][1] == tonumber(CommDKP:GetCurrentTeamIndex())
					dropDownMenuItem.isNotRadio = true
					DD:UIDropDownMenu_AddButton(dropDownMenuItem)
				end
			end
		)

		-- Dropdown Menu on SetValue()
		function CommDKP.UIConfig.TeamViewChangerDropDown:SetValue(arg1, arg2)

			if tonumber(CommDKP:GetCurrentTeamIndex()) ~= arg2 then
				if core.RaidInProgress == false and core.RaidInPause == false then
					CommDKP:SetCurrentTeam(arg2)
					CommDKP:SortDKPTable(core.currentSort, "reset")
					DD:UIDropDownMenu_SetText(CommDKP.UIConfig.TeamViewChangerDropDown, arg1)
				else
					StaticPopupDialogs["RAID_IN_PROGRESS"] = {
						text = L["TEAMCHANGERAIDINPROGRESS"],
						button1 = L["OK"],
						timeout = 0,
						whileDead = true,
						hideOnEscape = true,
						preferredIndex = 3,
					}
					StaticPopup_Show ("RAID_IN_PROGRESS")
				end
			else
				LibDD:CloseDropDownMenus()
			end
		end

		CommDKP.UIConfig.TeamViewChangerLabel = W.CreateText(rosterFooter, "caption", L["TEAMCURRENTLISTLABEL"] or "Team:", "RIGHT", "textMuted")   -- UX §13.2 / Q3
		CommDKP.UIConfig.TeamViewChangerLabel:SetPoint("RIGHT", CommDKP.UIConfig.TeamViewChangerDropDown, "LEFT", -6, 0);

	---------------------------------------
	-- UX §11.1.3: /dkp always opens expanded on Tab 1 (Filters)
	---------------------------------------
	f:HookScript("OnShow", function() CommDKP:SelectSideTab(1, true) end)
	---------------------------------------
	-- CHANGE LOG WINDOW
	---------------------------------------
	if core.DB.defaults.HideChangeLogs < core.BuildNumber then CommDKP:CreateChangeLog() end
	CommDKP.UIConfig:Hide(); -- hide menu after creation until called.
	CommDKP:FilterDKPTable(core.currentSort)   -- initial sort and populates data values in DKPTable.Rows{} CommDKP:FilterDKPTable() -> CommDKP:SortDKPTable() -> CommDKP:DKPTable_Update()
	CommDKP:UpdateGuildUIState()               -- AD-20.2.2: RosterCard + side-tabs exist now
	core.Initialized = true
	return CommDKP.UIConfig;
end

---------------------------------------
-- AD-19.2 (012d) (f) / BR-12.7: Change Log window, built on demand (login path when HideChangeLogs < BuildNumber,
-- or the header-rail button). Idempotent; builds shown and focused.
---------------------------------------
function CommDKP:CreateChangeLog()
	if CommDKP.ChangeLogDisplay then return CommDKP.ChangeLogDisplay end
	-- UX §12.4.1 / AD-16.4: "window" chrome (PortraitFrameTemplate, NoPortrait NineSlice, no Inset well), plaque
	-- fallback. Built on the shared chrome path (not the factory: it is created shown and keeps its own focus scripts).
	-- PM-025.1 / AD-33: narrow Q9 exception for this window only. The Change Log opens unprompted at login, so its title
	-- names the addon (main-window header style: gold name, muted parchment window name). The version stays in the body
	-- heading. chromeOpts nil (no titleInset): the template TitleContainer starts after the medallion, as on the main window.
	-- Auto-height logic is unchanged (220..560).
	local CL_FRAME_WIDTH, CL_TEXT_WIDTH, CL_MIN_HEIGHT, CL_MAX_HEIGHT = 600, 540, 220, 560
	local f = CommDKP.Widgets.CreateChromeFrame("CommDKP_ChangeLogDisplay", UIParent, "window",
		"CommunityDKP Forever  |cffB9A789" .. (L["CHANGELOGBTN"] or "Change Log") .. "|r")
	W.AttachMedallion(f, "CommDKP_ChangeLogMedallion")   -- BR-25.2 / BR-25.4: same helper as CommDKPConfigMedallion
	CommDKP.Widgets.LayoutContent(f)   -- f.Content (= f.ContentInset)
	CommDKP.ChangeLogDisplay = f

	f:SetPoint("TOP", UIParent, "TOP", 0, -200);
	f:SetSize(CL_FRAME_WIDTH, CL_MIN_HEIGHT);
	CommDKP:FocusChangeLog(true)   -- FULLSCREEN: pops up in front of UIConfig (DIALOG) and DKP Modes; see FocusWindow
	f:SetToplevel(true)
	f:SetClampedToScreen(true)
	f:SetClampRectInsets(-13, 0, 16, 0)   -- AD-33 / BR-25.6: medallion overhang (L/T), same as UIConfig's L/T insets
	f:SetMovable(true);
	f:EnableMouse(true);
	f:RegisterForDrag("LeftButton");
	f:SetScript("OnMouseDown", function() CommDKP:FocusChangeLog(true) end)
	f:SetScript("OnDragStart", function(self) CommDKP:FocusChangeLog(true); self:StartMoving() end);
	f:SetScript("OnDragStop", f.StopMovingOrSizing);
	CommDKP:RegisterFloater(f)      -- UX §10.1.3: after the SetScripts above so the registry hooks survive
	CommDKP:FocusChangeLog(true)    -- created shown (no OnShow): start focused in FULLSCREEN
	tinsert(UISpecialFrames, "CommDKP_ChangeLogDisplay")   -- Esc closes it

	local inset = f.Content

	-- ForeverGold page heading: gold GameFontNormalLarge, centered at the top of the content area.
	f.VerNumber = W.CreateText(inset, "title", "Version " .. tostring(core.SemVer), "CENTER", "gold")
	f.VerNumber:SetPoint("TOP", inset, "TOP", 0, -4)

	-- What's New card (y 30, fills to -46 from the frame bottom) holding a scroll region (thin rail on overflow).
	f.WhatsNew = W.CreateCard(inset, L["CARDWHATSNEW"])
	f.WhatsNew:SetPoint("TOPLEFT", inset, "TOPLEFT", 0, -30)
	f.WhatsNew:SetPoint("BOTTOMRIGHT", inset, "BOTTOMRIGHT", 0, 34)
	f.WhatsNewScroll = W.CreateScrollRegion(f.WhatsNew.Body, { step = 40 })
	f.WhatsNewScroll:SetPoint("TOPLEFT", f.WhatsNew.Body, "TOPLEFT", 8, -6)
	f.WhatsNewScroll:SetPoint("BOTTOMRIGHT", f.WhatsNew.Body, "BOTTOMRIGHT", -16, 6)
	local child = f.WhatsNewScroll.ScrollChild
	child:SetSize(CL_TEXT_WIDTH, 1)

	local y = -4
	local hasNotes = L["BESTPRACTICES"] ~= nil and L["BESTPRACTICES"] ~= ""
	if hasNotes then
		f.Notes = W.CreateCaption(child, L["BESTPRACTICES"], 6)
		f.Notes:SetWidth(CL_TEXT_WIDTH)
		f.Notes:SetPoint("TOPLEFT", child, "TOPLEFT", 0, y)
		y = y - f.Notes:GetStringHeight() - 10
	end

	-- CHANGELOG2..8 as bullets: gold dot + GameFontHighlight text, 14 px hanging indent, leading "- " stripped,
	-- empty keys skipped (AD-9.7). CHANGELOG1 is carried by the title + version heading (§12.4.1).
	f.Bullets = {}
	for i = 2, 8 do
		local s = L["CHANGELOG" .. i]
		if s and s ~= "" then
			s = s:gsub("^%-%s*", "")
			local dot = W.CreateText(child, "body", "\226\128\162", "LEFT", "gold")
			dot:SetPoint("TOPLEFT", child, "TOPLEFT", 0, y)
			local line = W.CreateText(child, "body", s, "LEFT")
			line:SetWidth(CL_TEXT_WIDTH - 14)
			if line.SetWordWrap then line:SetWordWrap(true) end
			if line.SetSpacing then line:SetSpacing(3) end
			line:SetPoint("TOPLEFT", child, "TOPLEFT", 14, y)
			f.Bullets[#f.Bullets + 1] = line
			y = y - line:GetStringHeight() - 6
		end
	end

	-- 1 px rule, then CHANGELOG9 / CHANGELOG10 as muted captions.
	f.ChangeLogRule = child:CreateTexture(nil, "BORDER")
	f.ChangeLogRule:SetPoint("TOPLEFT", child, "TOPLEFT", 0, y - 4)
	f.ChangeLogRule:SetSize(CL_TEXT_WIDTH, 1)
	f.ChangeLogRule:SetColorTexture(unpack((core.Palette or core.Palettes.Forever).rule))
	y = y - 12
	for i = 9, 10 do
		local s = L["CHANGELOG" .. i]
		if s and s ~= "" then
			local cap = W.CreateCaption(child, s, 2)
			cap:SetWidth(CL_TEXT_WIDTH)
			cap:SetPoint("TOPLEFT", child, "TOPLEFT", 0, y)
			y = y - cap:GetStringHeight() - 4
		end
	end
	local body = -y + 4
	child:SetHeight(body)

	f.DontShowCheck = W.CreateCheckbox(f, nil, L["DONTSHOW"]);
	f.DontShowCheck:SetChecked((tonumber(core.DB.defaults.HideChangeLogs) or 0) >= core.BuildNumber)   -- AD-19.2 (012d) (f): saved truth
	f.DontShowCheck:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 14, 10);
	f.DontShowCheck:SetScript("OnClick", function(self)
		if self:GetChecked() then
			core.DB.defaults.HideChangeLogs = core.BuildNumber
		else
			core.DB.defaults.HideChangeLogs = 0
		end
	end)

	local h = 30 + 30 + W.CARD_HDR + 6 + 12 + body + 46   -- title bar, version heading, card header, pads, body, footer
	f:SetSize(CL_FRAME_WIDTH, math.max(CL_MIN_HEIGHT, math.min(h, CL_MAX_HEIGHT)));  -- resize container
	f.WhatsNewScroll:UpdateRail()
	return f
end

function CommDKP:ToggleChangeLog()          -- AD-19: never writes HideChangeLogs (BR-12.7.3)
	local cl = CommDKP.ChangeLogDisplay
	if not cl then CommDKP:CreateChangeLog(); return end
	if cl:IsShown() then cl:Hide() else cl:Show(); CommDKP:FocusChangeLog(true) end
end
