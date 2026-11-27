local _, core = ...;
local _G = _G;
local CommDKP = core.CommDKP;
local L = core.L;

--
--  When clicking a box off, unchecks "All" as well and flags checkAll to false
--
local checkAll = true;                    -- changes to false when less than all of the boxes are checked
local curReason;                          -- stores user input in dropdown
local W = CommDKP.Widgets                 -- CDKP-009 kit (Modules/UI/Widgets.lua, loaded after Core.lua)

function CommDKPFilterChecks(self)         -- sets/unsets check boxes in conjunction with "All" button, then runs CommDKP:FilterDKPTable() above
	local verifyCheck = true; -- switches to false if the below loop finds anything unchecked
	if (self:GetChecked() == false and not CommDKP.ConfigTab1.checkBtn[11]) then
		core.CurView = "limited"
		core.CurSubView = "raid"
		CommDKP.ConfigTab1.checkBtn[9]:SetChecked(false);
		checkAll = false;
		verifyCheck = false
	end
	for i=1, 8 do             -- checks all boxes to see if all are checked, if so, checks "All" as well
		if CommDKP.ConfigTab1.checkBtn[i]:GetChecked() == false then
			verifyCheck = false;
		end
	end
	if (verifyCheck == true) then
		CommDKP.ConfigTab1.checkBtn[10]:SetChecked(true);
	else
		CommDKP.ConfigTab1.checkBtn[10]:SetChecked(false);
	end
	for k,v in pairs(core.classes) do
		if (CommDKP.ConfigTab1.checkBtn[k]:GetChecked() == true) then
			core.classFiltered[v] = true;
		else
			core.classFiltered[v] = false;
		end
	end
	PlaySound(808)
	CommDKP:FilterDKPTable(core.currentSort, "reset");
end

-- AD-28.2.1 (CDKP-020, BR-20.1/20.2): "In Party/Raid" (11) and "Not In Raid" (13) are an exclusive pair;
-- "Online" (12) is independent and keeps CommDKPFilterChecks as its OnClick. The click has already toggled `btn`.
function CommDKP:GroupFilterOnClick(btn)
	local id = btn:GetID()
	local partner = (id == 11 and 13) or (id == 13 and 11) or nil
	if partner and CommDKP.ConfigTab1.checkBtn[partner] then
		CommDKP.ConfigTab1.checkBtn[partner]:SetChecked(false)
	end
	CommDKPFilterChecks(btn)                       -- plays 808 once and re-filters (unchanged)
end

---------------------------------------
-- UX §11.1.4 / §11.3.3: right-edge icon side-tabs (supersede the §9 bottom tabs and the legacy XML tab
-- template). CommDKP:SetTabs keeps its signature and return values, so both callers
-- (ConfigMenuTabs: 7 panes, DKPModesFrame_Create: 2 panes) and every _G[frameName.."Tab"..i] lookup still work.
-- Optional fields on `frame` (set by the caller before SetTabs):
--   frame.sideTabHost   frame whose right edge carries the tabs (default: frame itself)
--   frame.sideTabIcons  { [i] = { iconPath, fallbackPath, ... } }
--   frame.onSideTabClick function(i) called on click (default: CommDKP:ShowTabPane(frame, i)); return false = no-op
--   host.sideTabOrder   (AD-31) optional { idx, ... } rail order read by StackSideTabs from the HOST (sideTabHost) so every
--                       re-stack (SetTabs, UpdateGuildUIState) keeps it; absent = index order (DKP Modes)
---------------------------------------
local SIDE_TAB_TOP = -42                 -- first tab 18 px below the 24 px title bar

-- §11.1.4 icon table for the main window (index = ConfigTab1..7, NOT rail position; rail order: MAIN_SIDE_TAB_ORDER).
-- Titles come from the SetTabs varargs.
local SIDE_TAB_ICONS = {
	{ "Interface\\Icons\\INV_Misc_Spyglass_03", "Interface\\Icons\\Ability_Spy" },                -- 1 Filters
	{ 4624666, "Interface\\AddOns\\CommunityDKPForever\\Media\\Textures\\cdkp-tab-adjust-dkp", "Interface\\Icons\\Spell_ChargePositive" },   -- 2 Adjust DKP (CDKP-024: FileDataID 4624666 + addon TGA + stock fallback)
	{ 134149, "Interface\\AddOns\\CommunityDKPForever\\Media\\Textures\\cdkp-tab-manage-roster", "Interface\\Icons\\INV_Misc_Note_01" },     -- 3 Manage DKP Roster (CDKP-024: FileDataID 134149 + addon TGA + stock fallback)
	{ "Interface\\Icons\\INV_Gizmo_02", "Interface\\Icons\\Trade_Engineering" },                   -- 4 Options
	{ "Interface\\Icons\\INV_Misc_Bag_10", "Interface\\Icons\\INV_Box_02" },                       -- 5 Loot History
	{ "Interface\\Icons\\INV_Misc_Book_09", "Interface\\Icons\\INV_Scroll_03" },                   -- 6 DKP History
	{ "Interface\\Icons\\INV_Misc_Coin_01", "Interface\\Icons\\INV_Misc_Coin_03" },                -- 7 Pricing (CDKP-023: + fallback)
}
CommDKP.SideTabIcons = SIDE_TAB_ICONS

-- AD-31 (CDKP-023): main-window rail order, top to bottom, as ConfigTab indexes:
-- Filters, Manage DKP Roster (3), Adjust DKP (2), Options, Loot History, DKP History, Pricing.
local MAIN_SIDE_TAB_ORDER = { 1, 3, 2, 4, 5, 6, 7 }
CommDKP.MainSideTabOrder = MAIN_SIDE_TAB_ORDER   -- read-only; exported for H133

-- Pane switch shared by both tab hosts: shows pane `id` in frame.ScrollFrame, hides the previous one,
-- toggles the scroll bar, refreshes the history panes, and checks only tab `id`.
function CommDKP:ShowTabPane(frame, id)
	local tab = frame.Tabs and frame.Tabs[id]
	if not tab then return end
	frame.selectedTab = id                                 -- same field the Blizzard helpers used
	for i, t in ipairs(frame.Tabs) do t:cdkpSetSelected(i == id) end

	local sf = frame.ScrollFrame
	if sf.UpdateRail then
		-- §12.2.8: the kit rail shows itself only while the pane overflows (refreshed after the child swap below).
	elseif sf.ScrollBar then
		if id > 4 and id ~= 7 then
			sf.ScrollBar:Show()
		elseif id == 4 and core.IsOfficer == true then
			sf.ScrollBar:Show()
		else
			sf.ScrollBar:Hide()
		end
	end

	if frame.numTabs == 7 then                             -- history panes only exist in the main window
		if id == 5 then
			CommDKP:LootHistory_Update(L["NOFILTER"]);
		elseif id == 6 then
			CommDKP:DKPHistory_Update(true)
		elseif id == 7 then
			CommDKP:RefreshPriceTable() -- AD-25.2.8: Pricing always reflects MinBids on show (keeps offset)
		end
	end

	local scrollChild = sf:GetScrollChild();
	if scrollChild and scrollChild ~= tab.content then
		scrollChild:Hide();
	end
	sf:SetScrollChild(tab.content);
	tab.content:Show();
	sf:SetVerticalScroll(0)
	if sf.UpdateRail then sf:UpdateRail() end
end

function CommDKP:SetTabs(frame, numTabs, width, height, ...)
	frame.numTabs = numTabs;

	local contents, tabs = {}, {};
	local frameName = frame:GetName();
	local host = frame.sideTabHost or frame
	local icons = frame.sideTabIcons or SIDE_TAB_ICONS

	for i = 1, numTabs do
		local title = select(i, ...)
		local tab = CommDKP:CreateSideTab(host, frameName, i, icons[i], title, function()
			-- AD-19.2 (012d) (c) / BR-12.4: the sound plays only when the click changes something
			-- (an onSideTabClick returning false is a silent no-op).
			if frame.onSideTabClick then
				if frame.onSideTabClick(i) ~= false then PlaySound(808) end
			else
				PlaySound(808); CommDKP:ShowTabPane(frame, i)
			end
		end)
		_G[frameName.."Tab"..i] = tab                       -- legacy global name (Toggle, SettingsPanel, tests)

		tab.content = CreateFrame("Frame", nil, frame.ScrollFrame);
		tab.content:SetSize(width, height);
		tab.content:Hide();

		tabs[i] = tab
		table.insert(contents, tab.content);
	end
	frame.Tabs = tabs
	host.SideTabs = tabs
	CommDKP:StackSideTabs(host, tabs, SIDE_TAB_TOP)

	CommDKP:ShowTabPane(frame, 1);

	return unpack(contents);
end

---------------------------------------
-- §12.3.6 history panes (Loot History / DKP History): a compact Filter card holding the filter selector (placed by
-- LootHistory.lua / DKPHistory.lua on tab.FilterCard.Body) and the right-aligned `inst` caption, plus a Log card
-- whose body is a scroll region. Entries are parented to tab.LogContent (= the region's scroll child).
---------------------------------------
function CommDKP:CreateHistoryCards(tab, logTitle)
	tab.FilterCard = W.CreateCard(tab, L["CARDFILTER"], 534, 71)   -- AD-19.2 (012d) (d) R5: cards end at x 534
	tab.FilterCard:SetPoint("TOPLEFT", tab, "TOPLEFT", 0, 0)
	tab.inst = W.CreateText(tab.FilterCard.Body, "caption", nil, "RIGHT", "textMuted")
	tab.inst:SetPoint("RIGHT", tab.FilterCard.Body, "RIGHT", -W.PAD, 0)
	tab.inst:SetWidth(300)

	tab.LogCard = W.CreateCard(tab, logTitle, 534, 403)
	tab.LogCard:SetPoint("TOPLEFT", tab, "TOPLEFT", 0, -79)
	tab.LogScroll = W.CreateScrollRegion(tab.LogCard.Body, { step = 40 })
	tab.LogScroll:SetPoint("TOPLEFT", tab.LogCard.Body, "TOPLEFT", 8, -6)
	tab.LogScroll:SetPoint("BOTTOMRIGHT", tab.LogCard.Body, "BOTTOMRIGHT", -16, 6)
	tab.LogContent = tab.LogScroll.ScrollChild
	tab.LogContent:SetSize(516, 1)
	return tab.FilterCard, tab.LogCard
end

-- Grows the Log scroll content to cover `last` (the bottom-most entry or the Load More button), then refreshes the rail.
function CommDKP:FitHistoryLog(tab, last)
	if not (tab and tab.LogContent) then return end
	if last then W.FitScrollChild(tab.LogContent, last, 12) else tab.LogContent:SetHeight(1) end
	if tab.LogScroll.UpdateRail then tab.LogScroll:UpdateRail() end
end

---------------------------------------
-- Populate Tabs
---------------------------------------
function CommDKP:ConfigMenuTabs()
	---------------------------------------
	-- TabMenu
	---------------------------------------

	-- UX §12.1.2: right workspace, 548 x 524 at (544, -52). No fill and no border: it only holds the page header
	-- and the pane. The 14 px seam x 530..544 between the Roster Card and the workspace stays bare (BR-9.1.4).
	local menu = CreateFrame("Frame", "CommDKPCommDKP.ConfigTabMenu", CommDKP.UIConfig);
	CommDKP.UIConfig.TabMenu = menu
	menu:SetPoint("TOPLEFT", CommDKP.UIConfig, "TOPLEFT", 544, -52);
	menu:SetSize(548, 524);

	-- §12.2.2 page header (548 x 34): active tab title + the « Collapse pill in its right slot (UX §13.4.3).
	-- TabMenu.HeaderText stays the alias SelectSideTab writes (AD-16.2 (c)).
	menu.Header = W.CreatePageHeader(menu, L["FILTERS"])
	menu.Header:SetPoint("TOPLEFT", menu, "TOPLEFT", 0, 0)
	menu.Header:SetPoint("TOPRIGHT", menu, "TOPRIGHT", 0, 0)
	menu.Header:SetHeight(W.PAGE_HDR + 6)
	menu.HeaderText = menu.Header.Title
	-- AD-19.2 (012d) (d) / BR-12.5: single-border pill (double chevron + "Collapse"), 24 tall in the 28 px band.
	menu.CollapseBtn = W.CreatePillButton(menu.Header.Band, COLLAPSE or "Collapse", "left", function()
		PlaySound(808)
		CommDKP:SetWorkspaceShown(false)
	end)
	menu.CollapseBtn:SetPoint("RIGHT", menu.Header.Band, "RIGHT", -4, 0)
	menu.CollapseBtn:HookScript("OnEnter", function(self)
		if not GameTooltip then return end
		GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
		GameTooltip:SetText(COLLAPSE or "Collapse", 1, 0.82, 0)
		GameTooltip:AddLine(L["COLLAPSEDESC"] or "Hide the workspace (click any side-tab to reopen)", 1, 1, 1, true)
		GameTooltip:Show()
	end)
	menu.CollapseBtn:HookScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
	menu.Header.CollapseBtn = menu.CollapseBtn

	-- §12.1.2 / §12.2.8: the pane is a template-free scroll region (548 x 482 at TabMenu (0, -42)); its 6 px rail
	-- sits inside the pane's right lane (x 538..544), never on the seam. menu.ScrollFrame / .ScrollBar keep their keys.
	menu.ScrollFrame = W.CreateScrollRegion(menu, { step = 40 })
	menu.ScrollFrame:SetPoint("TOPLEFT", menu, "TOPLEFT", 0, -42);
	menu.ScrollFrame:SetPoint("BOTTOMRIGHT", menu, "BOTTOMRIGHT", 0, 0);
	menu.ScrollBar = menu.ScrollFrame.ScrollBar
	menu.ScrollBar:ClearAllPoints()
	menu.ScrollBar:SetPoint("TOPRIGHT", menu.ScrollFrame, "TOPRIGHT", -4, 0)
	menu.ScrollBar:SetPoint("BOTTOMRIGHT", menu.ScrollFrame, "BOTTOMRIGHT", -4, 0)
	menu.ScrollBar:SetFrameLevel(menu.ScrollFrame:GetFrameLevel() + 20)   -- above the cards in the pane

	-- UX §11.1.4: the 7 side-tabs hang off UIConfig's right edge (always visible, also when collapsed).
	menu.sideTabHost = CommDKP.UIConfig
	menu.sideTabIcons = SIDE_TAB_ICONS
	CommDKP.UIConfig.sideTabOrder = MAIN_SIDE_TAB_ORDER                      -- AD-31: rail order (host-level; UpdateGuildUIState re-uses it)
	menu.onSideTabClick = function(i) return CommDKP:SelectSideTab(i) end   -- false = active-tab no-op (BR-12.4)

	-- §12.3: every pane is 548 x 482 of scroll-region content (cards are pane-relative; Options grows its own height).
	CommDKP.ConfigTab1, CommDKP.ConfigTab2, CommDKP.ConfigTab3, CommDKP.ConfigTab4, CommDKP.ConfigTab5, CommDKP.ConfigTab6, CommDKP.ConfigTab7 = CommDKP:SetTabs(menu, 7, 548, 482, L["FILTERS"], L["ADJUSTDKP"], L["MANAGEDKPROSTER"], L["OPTIONS"], L["LOOTHISTORY"], L["DKPHISTORY"], L["PRICETAB"]);
	CommDKP.UIConfig.activeTab = 1
	menu.HeaderText:SetText(L["FILTERS"])

	---------------------------------------
	-- MENU TAB 1: Filters (§12.3.2). The page header is the only title (Q7): no in-pane large heading.
	---------------------------------------
	local filterCard = W.CreateCard(CommDKP.ConfigTab1, L["CARDCLASSFILTERS"], 548, 186)
	filterCard:SetPoint("TOPLEFT", CommDKP.ConfigTab1, "TOPLEFT", 0, 0)
	CommDKP.ConfigTab1.FilterCard = filterCard
	local fBody = filterCard.Body

	local checkBtn = {}
	CommDKP.ConfigTab1.checkBtn = checkBtn;

	-- Create CheckBoxes (B6: template-free kit CheckButtons; same table slots, IDs and OnClick handlers)
	for i=1, 11 do
		CommDKP.ConfigTab1.checkBtn[i] = W.CreateCheckbox(fBody, nil, "");
		if i <= 10 then CommDKP.ConfigTab1.checkBtn[i]:SetChecked(true) else CommDKP.ConfigTab1.checkBtn[i]:SetChecked(false) end;
		CommDKP.ConfigTab1.checkBtn[i]:SetID(i)
		if i <= 9 then
			CommDKP.ConfigTab1.checkBtn[i].text:SetText(API_CLASSES[core.classes[i]]);
		end
		if i==10 then
			CommDKP.ConfigTab1.checkBtn[i]:SetScript("OnClick",
				function()
					for j=1, 10 do
						if (checkAll) then
							CommDKP.ConfigTab1.checkBtn[j]:SetChecked(false)
						else
							CommDKP.ConfigTab1.checkBtn[j]:SetChecked(true)
						end
					end
					checkAll = not checkAll;
					CommDKPFilterChecks(CommDKP.ConfigTab1.checkBtn[9]);
				end)

			for k,v in pairs(core.classes) do               -- sets core.classFiltered table with all values
				if (CommDKP.ConfigTab1.checkBtn[k]:GetChecked() == true) then
					core.classFiltered[v] = true;
				else
					core.classFiltered[v] = false;
				end
			end
		elseif i==11 then
			CommDKP.ConfigTab1.checkBtn[i]:SetScript("OnClick", function(self) CommDKP:GroupFilterOnClick(self) end)   -- AD-28.2.1
		else
			CommDKP.ConfigTab1.checkBtn[i]:SetScript("OnClick", CommDKPFilterChecks)
		end
	end

	-- §12.3.2 layout: All Classes (row 1) · checkBtn[1..9] in a 3 x 3 grid (col 174, row 24, core.classes order)
	-- · 1 px rule · In Party/Raid, Online, Not In Raid on one row.
	local COL, ROW, X0 = 174, 24, W.PAD
	CommDKP.ConfigTab1.checkBtn[10]:SetPoint("TOPLEFT", fBody, "TOPLEFT", X0, -10);
	CommDKP.ConfigTab1.checkBtn[10].text:SetText(L["ALLCLASSES"]);
	for i=1, 9 do
		CommDKP.ConfigTab1.checkBtn[i]:SetPoint("TOPLEFT", fBody, "TOPLEFT", X0 + ((i-1) % 3) * COL, -34 - math.floor((i-1) / 3) * ROW);
	end
	filterCard.Rule = fBody:CreateTexture(nil, "BORDER")
	filterCard.Rule:SetColorTexture(unpack(core.Palettes.Forever.rule))
	filterCard.Rule:SetHeight(1)
	filterCard.Rule:SetPoint("TOPLEFT", fBody, "TOPLEFT", X0, -112)
	filterCard.Rule:SetPoint("TOPRIGHT", fBody, "TOPRIGHT", -X0, -112)
	CommDKP.ConfigTab1.checkBtn[11]:SetPoint("TOPLEFT", fBody, "TOPLEFT", X0, -124);
	CommDKP.ConfigTab1.checkBtn[11].text:SetText(L["INPARTYRAID"]);         -- executed in filterDKPTable (CommunityDKP.lua)

	CommDKP.ConfigTab1.checkBtn[12] = W.CreateCheckbox(fBody, nil, L["ONLINE"]);
	CommDKP.ConfigTab1.checkBtn[12]:SetID(12)
	CommDKP.ConfigTab1.checkBtn[12]:SetScript("OnClick", CommDKPFilterChecks)
	CommDKP.ConfigTab1.checkBtn[12]:SetPoint("TOPLEFT", fBody, "TOPLEFT", X0 + COL, -124);

	CommDKP.ConfigTab1.checkBtn[13] = W.CreateCheckbox(fBody, nil, L["NOTINRAIDFILTER"]);
	CommDKP.ConfigTab1.checkBtn[13]:SetID(13)
	CommDKP.ConfigTab1.checkBtn[13]:SetScript("OnClick", function(self) CommDKP:GroupFilterOnClick(self) end)   -- AD-28.2.1 (RC-1)
	CommDKP.ConfigTab1.checkBtn[13]:SetPoint("TOPLEFT", fBody, "TOPLEFT", X0 + 2 * COL, -124);

	-- §12.3.2 Class Distribution card: the class graph is built on its body (ClassGraph.lua reads GraphCard).
	CommDKP.ConfigTab1.GraphCard = W.CreateCard(CommDKP.ConfigTab1, L["CARDCLASSGRAPH"], 548, 288)
	CommDKP.ConfigTab1.GraphCard:SetPoint("TOPLEFT", CommDKP.ConfigTab1, "TOPLEFT", 0, -194)

	core.ClassGraph = CommDKP:ClassGraph()  -- draws class graph on tab1

	---------------------------------------
	-- Adjust DKP TAB
	---------------------------------------
	CommDKP:AdjustDKPTab_Create()

	---------------------------------------
	-- Price  TAB
	---------------------------------------
	CommDKP:PriceTab_Create()

	---------------------------------------
	-- Manage DKP TAB (§12.3.4: no in-pane heading; the 3 cards are built by ManageEntries)
	---------------------------------------
	CommDKP:ManageEntries()

	---------------------------------------
	-- Loot History TAB (§12.3.6): Filter card (0,0) 548 x 71 + Loot Log card (0,-79) 548 x 403 with a scroll region.
	---------------------------------------
	CommDKP:CreateHistoryCards(CommDKP.ConfigTab5, L["CARDLOOTLOG"])
	CommDKP.ConfigTab5.inst:SetText(L["LOOTHISTINST1"]);
	-- Populate Loot History (LootHistory.lua). Entries live on the Loot Log scroll content (LogContent).
	local looter = {}
	CommDKP.ConfigTab5.looter = looter
	local lootFrame = {}
	CommDKP.ConfigTab5.lootFrame = lootFrame
	for i=1, #CommDKP:GetTable(CommDKP_Loot, true) do
		CommDKP.ConfigTab5.lootFrame[i] = CreateFrame("Frame", "CommDKPLootHistoryFrame"..i, CommDKP.ConfigTab5.LogContent);
	end
	if #CommDKP:GetTable(CommDKP_Loot, true) > 0 then
		CommDKP:LootHistory_Update(L["NOFILTER"])
		CommDKP:CreateSortBox();
	end
	---------------------------------------
	-- DKP History Tab (§12.3.6): Filter card + DKP Log card.
	---------------------------------------
	CommDKP:CreateHistoryCards(CommDKP.ConfigTab6, L["CARDDKPLOG"])
	if #CommDKP:GetTable(CommDKP_DKPHistory, true) > 0 then
		CommDKP:DKPHistory_Update()
	end
	CommDKP:DKPHistoryFilterBox_Create()
end
