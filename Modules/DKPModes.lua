local _, core = ...;
local _G = _G;
local CommDKP = core.CommDKP;
local L = core.L;

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

function CommDKP:DKPModesFrame_Create()

	local f;

	-- UX §9.1: native Blizzard window (NineSlice border, metallic title bar, CloseButton, InsetBg).
	-- No custom backdrop / close box / watermark: the template owns all chrome.
	f = CreateFrame("Frame", "CommDKP_DKPModesFrame", UIParent, "BasicFrameTemplateWithInset");

	local ActiveMode = core.DB.modes.mode;
	local ActiveCostType = core.DB.modes.costvalue;

	if not core.IsOfficer then
		CommDKP:Print(L["NOPERMISSION"])
		return
	end

	f:SetClampedToScreen(true)
	f:SetClampRectInsets(0, 0, 0, -22)          -- tabs hang 20 px below the frame + 2 px slack (§9.2.4)
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

	-- Title (same defensive accessor as the Change Log, §7.4)
	local titleText = f.TitleText or (f.TitleContainer and f.TitleContainer.TitleText)
	if not titleText then
		titleText = f:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
		titleText:SetPoint("CENTER", f.TitleBg or f, f.TitleBg and "CENTER" or "TOP", 0, f.TitleBg and 0 or -12)
	end
	titleText:SetText("CommunityDKP Forever \226\128\148 DKP Modes")   -- UTF-8 em dash; native gold title
	f.TitleLabel = titleText

	-- TabMenu ScrollFrame and ScrollBar (inside the template's InsetBg, §9.1.2)
	local inset = f.InsetBg or f.Inset or f
	local fallback = (inset == f)
	f.ScrollFrame = CreateFrame("ScrollFrame", nil, f);

	f.ScrollFrame:ClearAllPoints();
	f.ScrollFrame:SetPoint("TOPLEFT",     inset, "TOPLEFT",     fallback and 6  or 2, fallback and -28 or -4);
	f.ScrollFrame:SetPoint("BOTTOMRIGHT", inset, "BOTTOMRIGHT", fallback and -8 or -2, fallback and 8   or 4);
	f.ScrollFrame:SetClipsChildren(false);
	f.ScrollFrame:SetScript("OnMouseWheel", ScrollFrame_OnMouseWheel);

	f.ScrollFrame.ScrollBar = CreateFrame("Slider", nil, f.ScrollFrame, "UIPanelScrollBarTrimTemplate")
	f.ScrollFrame.ScrollBar:ClearAllPoints();
	f.ScrollFrame.ScrollBar:SetPoint("TOPLEFT", f.ScrollFrame, "TOPRIGHT", -20, -12);
	f.ScrollFrame.ScrollBar:SetPoint("BOTTOMRIGHT", f.ScrollFrame, "BOTTOMRIGHT", -2, 15);

	f.useRetailTabs = true   -- UX §9.1.3 / §9.2: only ModesWindow gets Accountant-Classic bottom tabs
	f.DKPModesMain, f.DKPModesMisc = CommDKP:SetTabs(f, 2, 475, 600, "Modes", "Misc");
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
