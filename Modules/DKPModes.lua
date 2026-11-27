local _, core = ...;
local _G = _G;
local CommDKP = core.CommDKP;
local L = core.L;
local W = CommDKP.Widgets

function CommDKP:ToggleDKPModesWindow()
	if core.IsOfficer == true then
		if not core.ModesWindow then
			core.ModesWindow =  CommDKP:DKPModesFrame_Create();

			-- Populate Tabs
			CommDKP:DKPModes_Main()
			CommDKP:DKPModes_Misc()
		end
	 	core.ModesWindow:SetShown(not core.ModesWindow:IsShown())
		if core.ModesWindow:IsShown() then CommDKP:FocusWindow(core.ModesWindow) end   -- UX §9.1.4: floater strata
		if core.BiddingWindow then core.BiddingWindow:SetFrameLevel(6) end
		if CommDKP.UIConfig then CommDKP.UIConfig:SetFrameLevel(2) end
	else
		CommDKP:Print(L["NOPERMISSION"])
	end
end

-- UX §11.3.3: shows pane i and checks only its tab. Clicking the active tab is a no-op (single pane, no collapse).
function CommDKP:DKPModes_SelectTab(i)
	local f = core.ModesWindow or _G["CommDKP_DKPModesFrame"]
	if not f or not f.Tabs then return end
	if f.selectedTab == i and f.Tabs[i].content:IsShown() then return end
	CommDKP:ShowTabPane(f, i)
	if f.HeaderText and f.Tabs[i].cdkpTitle then f.HeaderText:SetText(f.Tabs[i].cdkpTitle) end   -- §12.2.2 page header
end

-- AD-35.6 (BR-27.7): re-reads core.DB into an ALREADY BUILT DKP Modes window, shown or hidden (a hidden window is not
-- rebuilt on open, and its Roll boxes are written back to core.DB by OnHide/Broadcast). Never creates it (AC-27.12);
-- never changes the selected tab.
function CommDKP:RefreshModesWindow()
	local f = core.ModesWindow
	if not f then return false end
	if f.DKPModesMain and f.DKPModesMain.RefreshFromDB then f.DKPModesMain.RefreshFromDB() end
	if f.DKPModesMisc and f.DKPModesMisc.RefreshFromDB then f.DKPModesMisc.RefreshFromDB() end
	return true
end

function CommDKP:DKPModesFrame_Create()

	local f;

	-- UX §12.4.4 / AD-16.4: "window" chrome (PortraitFrameTemplate, NoPortrait NineSlice, no Inset well) on the
	-- shared chrome path, plaque fallback. Interior: page header + scroll region on f.Content (BR-9.4.4); Q9 short title.
	f = CommDKP.Widgets.CreateChromeFrame("CommDKP_DKPModesFrame", UIParent, "window", L["DKPMODES"], { titleInset = 16 })
	CommDKP.Widgets.LayoutContent(f)            -- f.Content (= f.ContentInset)

	local ActiveMode = core.DB.modes.mode;
	local ActiveCostType = core.DB.modes.costvalue;

	if not core.IsOfficer then
		CommDKP:Print(L["NOPERMISSION"])
		return
	end

	f:SetClampedToScreen(true)
	f:SetClampRectInsets(0, 42, 0, 0)           -- UX §11.3.3: side-tab column on the right; no bottom tabs any more
	f:SetPoint("TOPLEFT", UIParent, "TOPLEFT", 300, -120);
	f:SetSize(490, 636);
	f:SetToplevel(true)
	f:SetFrameStrata("MEDIUM")                  -- real strata is assigned by CommDKP:FocusWindow (§9.1.4)
	f:SetMovable(true);
	f:EnableMouse(true);
	f:RegisterForDrag("LeftButton");
	f:SetScript("OnDragStart", function(self) CommDKP:FocusWindow(self); self:StartMoving() end);
	f:SetScript("OnDragStop", f.StopMovingOrSizing);
	f:SetScript("OnMouseDown", function(self)
		CommDKP:FocusWindow(self)
		if core.BiddingWindow then core.BiddingWindow:SetFrameLevel(6) end
		if CommDKP.UIConfig then CommDKP.UIConfig:SetFrameLevel(2) end
	end)
	tinsert(UISpecialFrames, f:GetName()); -- Sets frame to close on "Escape" (registered once)

	-- §12.4.4 pane area (466 wide): a template-free scroll region from below the 34 px page header to 34 px above the
	-- content bottom (the BroadcastSettings footer). Its 6 px rail sits in the pane's right lane (x 460..466).
	local inset = f.Content
	f.ScrollFrame = W.CreateScrollRegion(inset, { step = 40 })
	f.ScrollFrame:SetPoint("TOPLEFT",     inset, "TOPLEFT",     0, -42);
	f.ScrollFrame:SetPoint("BOTTOMRIGHT", inset, "BOTTOMRIGHT", 0, 34);
	f.ScrollFrame.ScrollBar:ClearAllPoints()
	f.ScrollFrame.ScrollBar:SetPoint("TOPRIGHT", f.ScrollFrame, "TOPRIGHT", 0, 0)
	f.ScrollFrame.ScrollBar:SetPoint("BOTTOMRIGHT", f.ScrollFrame, "BOTTOMRIGHT", 0, 0)
	f.ScrollFrame.ScrollBar:SetFrameLevel(f.ScrollFrame:GetFrameLevel() + 20)   -- above the cards in the pane

	-- §12.2.2 page header (34 px): the active pane title (Modes / Options). f.HeaderText is the alias DKPModes_SelectTab writes.
	f.Header = W.CreatePageHeader(inset, "Modes")
	f.Header:SetPoint("TOPLEFT", inset, "TOPLEFT", 0, 0)
	f.Header:SetPoint("TOPRIGHT", inset, "TOPRIGHT", 0, 0)
	f.Header:SetHeight(W.PAGE_HDR + 6)
	f.HeaderText = f.Header.Title

	-- UX §11.3.3: 2 right-edge icon side-tabs (supersede the §9 bottom tabs). No collapse toggle here.
	f.sideTabIcons = {
		{ "Interface\\Icons\\INV_Misc_Coin_02" },                                       -- Modes
		{ "Interface\\Icons\\INV_Gizmo_02", "Interface\\Icons\\Trade_Engineering" },  -- Options
	}
	f.onSideTabClick = function(i) CommDKP:DKPModes_SelectTab(i) end
	f.DKPModesMain, f.DKPModesMisc = CommDKP:SetTabs(f, 2, 466, 533, "Modes", L["OPTIONS"]);
	f:HookScript("OnShow", function() CommDKP:DKPModes_SelectTab(1) end)   -- Modes selected on every open
	f:Hide()

	f:SetScript("OnHide", function()
		core.DB.modes.rolls.min = f.DKPModesMain.RollContainer.rollMin:GetNumber()
		core.DB.modes.rolls.max = f.DKPModesMain.RollContainer.rollMax:GetNumber()
		core.DB.modes.rolls.AddToMax = f.DKPModesMain.RollContainer.AddMax:GetNumber()

		if (core.DB.modes.rolls.min > core.DB.modes.rolls.max and core.DB.modes.rolls.max ~= 0 and core.DB.modes.rolls.UserPerc == false) or (core.DB.modes.rolls.UsePerc and (core.DB.modes.rolls.min < 0 or core.DB.modes.rolls.max > 100 or core.DB.modes.rolls.min > core.DB.modes.rolls.max)) then
			StaticPopupDialogs["NOTIFY_ROLLS"] = {
				text = "|CFFFF0000"..L["WARNING"].."|r: "..L["INVALIDROLLPARAM"],
				button1 = L["OK"],
				timeout = 0,
				whileDead = true,
				hideOnEscape = true,
				preferredIndex = 3,
			}
			-- UX §10.1.3: drop all floaters to MEDIUM and hold focus so the DIALOG-strata popup renders in front;
			-- the f:Show() below only records the focus request, which is restored when the popup hides.
			CommDKP:ShowPopupOverFloaters("NOTIFY_ROLLS", f)
			f:Show()
			return;
		end
	end)
	CommDKP:RegisterFloater(f)   -- UX §10.1.3: after SetScript("OnHide"/"OnMouseDown") so the registry hooks survive
	return f;
end
