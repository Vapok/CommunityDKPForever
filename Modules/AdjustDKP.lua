local _, core = ...;
local _G = _G;
local CommDKP = core.CommDKP;
local L = core.L;

local curReason;
local LibDD = LibStub:GetLibrary("LibUIDropDownMenu-4.0");
local DD = CommDKP.DD                     -- AD-16.3: selector protocol (reasonDropDown, BossKilledDropdown)
local W = CommDKP.Widgets

function CommDKP:AdjustDKP(value)
	local adjustReason = curReason;
	local curTime = time()
	local c;
	local curOfficer = CommDKP:GetPlayerName()
	if not curOfficer then return end  -- AD-10.4: identity not loaded yet
	value = CommDKP_round(value, core.DB.modes.rounding);

	if not IsInRaid() then
		c = CommDKP:GetCColors();
	end

	if (curReason == L["OTHER"]) then adjustReason = L["OTHER"].." - "..CommDKP.ConfigTab2.otherReason:GetText(); end
	if curReason == L["BOSSKILLBONUS"] then adjustReason = core.CurrentRaidZone..": "..core.LastKilledBoss; end
	if curReason == L["NEWBOSSKILLBONUS"] then adjustReason = core.CurrentRaidZone..": "..core.LastKilledBoss.." ("..L["FIRSTKILL"]..")" end
	if (#core.SelectedData > 0 and adjustReason and adjustReason ~= L["OTHER"].." - "..L["ENTEROTHERREASONHERE"]) then
		if core.IsOfficer then
			local tempString = "";       -- stores list of changes
			local dkpHistoryString = ""   -- stores list for CommDKP:GetTable(CommDKP_DKPHistory, true)
			for i=1, #core.SelectedData do
				local current;
				local search = CommDKP:Table_Search(CommDKP:GetTable(CommDKP_DKPTable, true), core.SelectedData[i]["player"])
				if search then
					if not IsInRaid() then
						if i < #core.SelectedData then
							tempString = tempString.."|c"..c[core.SelectedData[i]["class"]].hex..core.SelectedData[i]["player"].."|r, ";
						else
							tempString = tempString.."|c"..c[core.SelectedData[i]["class"]].hex..core.SelectedData[i]["player"].."|r";
						end
					end
					dkpHistoryString = dkpHistoryString..core.SelectedData[i]["player"]..","
					current = CommDKP:GetTable(CommDKP_DKPTable, true)[search[1][1]].dkp
					CommDKP:GetTable(CommDKP_DKPTable, true)[search[1][1]].dkp = CommDKP_round(tonumber(current + value), core.DB.modes.rounding)
					if value > 0 then
						CommDKP:GetTable(CommDKP_DKPTable, true)[search[1][1]]["lifetime_gained"] = CommDKP_round(tonumber(CommDKP:GetTable(CommDKP_DKPTable, true)[search[1][1]]["lifetime_gained"] + value), core.DB.modes.rounding)
					end
				end
			end
			local newIndex = curOfficer.."-"..curTime
			tinsert(CommDKP:GetTable(CommDKP_DKPHistory, true), 1, {players=dkpHistoryString, dkp=value, reason=adjustReason, date=curTime, index=newIndex})
			CommDKP.Sync:SendData("CommDKPDKPDist", CommDKP:GetTable(CommDKP_DKPHistory, true)[1])

			if CommDKP.ConfigTab6.history and CommDKP.ConfigTab6:IsShown() then
				CommDKP:DKPHistory_Update(true)
			end
			CommDKP:DKPTable_Update()
			if IsInRaid() then
				CommDKP.Sync:SendData("CommDKPBCastMsg", L["RAIDDKPADJUSTBY"].." "..value.." "..L["FORREASON"]..": "..adjustReason)
			else
				CommDKP.Sync:SendData("CommDKPBCastMsg", L["DKPADJUSTBY"].." "..value.." "..L["FORPLAYERS"]..": ")
				CommDKP.Sync:SendData("CommDKPBCastMsg", tempString)
				CommDKP.Sync:SendData("CommDKPBCastMsg", L["REASON"]..": "..adjustReason)
			end
		end
	else
		local validation;
		if (#core.SelectedData == 0 and not adjustReason) then
			validation = L["PLAYERREASONVALIDATE"]
		elseif #core.SelectedData == 0 then
			validation = L["PLAYERVALIDATE"]
		elseif not adjustReason or CommDKP.ConfigTab2.otherReason:GetText() == "" or CommDKP.ConfigTab2.otherReason:GetText() == L["ENTEROTHERREASONHERE"] then
			validation = L["OTHERREASONVALIDATE"]
		end

		StaticPopupDialogs["VALIDATION_PROMPT"] = {
			text = validation,
			button1 = L["OK"],
			timeout = 5,
			whileDead = true,
			hideOnEscape = true,
			preferredIndex = 3,
		}
		StaticPopup_Show ("VALIDATION_PROMPT")
	end
end

local function DecayDKP(amount, deductionType, GetSelections)
	local playerString = "";
	local dkpString = "";
	local curTime = time()
	local curOfficer = CommDKP:GetPlayerName()
	if not curOfficer then return end  -- AD-10.4: identity not loaded yet

	for key, value in ipairs(CommDKP:GetTable(CommDKP_DKPTable, true)) do
		local dkp = tonumber(value["dkp"])
		local player = value["player"]
		local amount = amount;
		amount = tonumber(amount) / 100		-- converts percentage to a decimal
		if amount < 0 then
			amount = amount * -1			-- flips value to positive if officer accidently used negative number in editbox
		end
		local deducted;

		if (GetSelections and CommDKP:Table_Search(core.SelectedData, player)) or GetSelections == false then
			if dkp > 0 then
				if deductionType == "percent" then
					deducted = dkp * amount
					dkp = dkp - deducted
					value["dkp"] = CommDKP_round(tonumber(dkp), core.DB.modes.rounding);
					dkpString = dkpString.."-"..CommDKP_round(deducted, core.DB.modes.rounding)..",";
					playerString = playerString..player..",";
				elseif deductionType == "points" then
					-- do stuff for flat point deductions
				end
			elseif dkp < 0 and CommDKP.ConfigTab2.AddNegative:GetChecked() then
				if deductionType == "percent" then
					deducted = dkp * amount
					dkp = (deducted - dkp) * -1
					value["dkp"] = CommDKP_round(tonumber(dkp), core.DB.modes.rounding)
					dkpString = dkpString..CommDKP_round(-deducted, core.DB.modes.rounding)..",";
					playerString = playerString..player..",";
				elseif deductionType == "points" then
					-- do stuff for flat point deductions
				end	
			end
		end
	end
	dkpString = dkpString.."-"..amount.."%";

	if tonumber(amount) < 0 then amount = amount * -1 end		-- flips value to positive if officer accidently used a negative number

	local newIndex = curOfficer.."-"..curTime
	tinsert(CommDKP:GetTable(CommDKP_DKPHistory, true), 1, {players=playerString, dkp=dkpString, reason=L["WEEKLYDECAY"], date=curTime, index=newIndex})
	CommDKP.Sync:SendData("CommDKPDecay", CommDKP:GetTable(CommDKP_DKPHistory, true)[1])
	if CommDKP.ConfigTab6.history then
		CommDKP:DKPHistory_Update(true)
	end
	CommDKP:DKPTable_Update()
end

local function RaidTimerPopout_Create()
	if not CommDKP.RaidTimerPopout then

		-- UX §12.4.10 / AD-16.4: "plaque" HUD readout (190 x 74; floater, no Esc, no [X]). Created hidden.
		-- The [«] dock-back icon button sits in the close slot; no SetScale hack (size comes from the font object).
		local f, content = CommDKP:CreateForeverWindow("CommDKP_RaidTimerPopout", 190, 74, L["RAIDTIMER"],
			{ style = "plaque", escape = false, noClose = true })
		CommDKP.RaidTimerPopout = f
		f:SetPoint("RIGHT", UIParent, "RIGHT", -300, 100)
		-- OnHide covers every close path (the [«] dock-back, the "<" toggle, any future hide); ">" twice is idempotent.
		f:HookScript("OnHide", function()
			CommDKP.ConfigTab2.RaidTimerContainer.PopOut:SetText(">")
		end)

		f.PopIn = W.CreateIconButton(f, "Interface\\Buttons\\UI-SpellbookIcon-PrevPage-Up", L["POPOUTTIMER"], function()
			PlaySound(808)
			f:Hide()
		end)
		f.PopIn:SetSize(18, 18)
		f.PopIn:SetPoint("TOPRIGHT", f, "TOPRIGHT", -4, -4)

		-- Raid Timer Output: Readout style (green from the logic's color codes), left
		f.Output = W.CreateText(content, "readout", "|cff00ff0000:00:00|r", "LEFT")
		f.Output:SetPoint("BOTTOMLEFT", content, "BOTTOMLEFT", 4, 2)

		-- "Bonus" caption over the bonus value, right. Display-only mirror of the Raid Timer card's Bonus readout,
		-- refreshed twice a second while the popout is visible (RaidTimer.lua stays untouched; no hooks).
		f.BonusHeader = W.CreateText(content, "caption", L["BONUS"], "RIGHT", "textMuted")
		f.BonusHeader:SetPoint("TOPRIGHT", content, "TOPRIGHT", -4, -2)
		f.Bonus = W.CreateText(content, "readout", nil, "RIGHT")
		f.Bonus:SetPoint("BOTTOMRIGHT", content, "BOTTOMRIGHT", -4, 2)
		local elapsedSinceSync = 1
		f:HookScript("OnUpdate", function(_, elapsed)
			elapsedSinceSync = elapsedSinceSync + (elapsed or 0)
			if elapsedSinceSync < 0.5 then return end
			elapsedSinceSync = 0
			local src = CommDKP.ConfigTab2.RaidTimerContainer and CommDKP.ConfigTab2.RaidTimerContainer.Bonus
			if src then f.Bonus:SetText(W.SafeText(src:GetText())) end
		end)
	else
		CommDKP.RaidTimerPopout:Show()
	end
end

function CommDKP:AdjustDKPTab_Create()
	-- UX §12.3.3: Manual Adjustment (0,0) 270 x 306 · Weekly DKP Decay (0,314) 270 x 168 · Raid Timer (278,0) 256 x 482 (AD-19.2 012c).
	-- No in-pane heading (Q7): the page header is the only title.
	local INNER = 270 - 6 - 2 * W.PAD        -- usable body width of a 270 px card (240)
	local manualCard = W.CreateCard(CommDKP.ConfigTab2, L["CARDMANUALADJ"], 270, 306)
	manualCard:SetPoint("TOPLEFT", CommDKP.ConfigTab2, "TOPLEFT", 0, 0)
	CommDKP.ConfigTab2.ManualCard = manualCard
	local mBody = manualCard.Body
	local decayCard = W.CreateCard(CommDKP.ConfigTab2, L["WEEKLYDKPDECAY"], 270, 168)
	decayCard:SetPoint("TOPLEFT", CommDKP.ConfigTab2, "TOPLEFT", 0, -314)
	CommDKP.ConfigTab2.DecayCard = decayCard
	local dBody = decayCard.Body

	-- AD-20.3.2 (CDKP-013b, BR-13.3.3): the help caption is the card's intro; every control below is anchored to its bottom.
	CommDKP.ConfigTab2.description = W.CreateCaption(mBody, L["ADJUSTDESC"], 4)   -- §12.2.12 help caption (3rd arg ignored, BR-12.3.1)
	CommDKP.ConfigTab2.description:SetWidth(INNER)                                 -- width before measuring (LayoutManualCard)
	CommDKP.ConfigTab2.description:SetPoint("TOPLEFT", mBody, "TOPLEFT", W.PAD, -10);
	manualCard:EnableMouse(true)
	manualCard:SetScript("OnEnter", function(self)              -- full-text tooltip
		GameTooltip:SetOwner(self, "ANCHOR_RIGHT");
		GameTooltip:SetText(L["CARDMANUALADJ"], 1, 0.82, 0, 1, true);
		GameTooltip:AddLine(L["ADJUSTDESC"], 1.0, 1.0, 1.0, true);
		GameTooltip:Show();
	end)
	manualCard:SetScript("OnLeave", function() GameTooltip:Hide() end)

	-- Reason DROPDOWN box 
	-- Create the dropdown, and configure its appearance
	CommDKP.ConfigTab2.reasonDropDown = DD:Create_UIDropDownMenu("CommDKPConfigReasonDropDown", mBody);
	DD:UIDropDownMenu_SetWidth(CommDKP.ConfigTab2.reasonDropDown, INNER)
	DD:UIDropDownMenu_SetText(CommDKP.ConfigTab2.reasonDropDown, L["SELECTREASON"])

	-- Create and bind the initialization function to the dropdown menu
		DD:UIDropDownMenu_Initialize(CommDKP.ConfigTab2.reasonDropDown, function(self, level, menuList)
		
		local reason = DD:UIDropDownMenu_CreateInfo()
		reason.func = self.SetValue

		reason.text, reason.arg1, reason.checked, reason.isNotRadio = L["ONTIMEBONUS"], L["ONTIMEBONUS"], L["ONTIMEBONUS"] == curReason, true
		DD:UIDropDownMenu_AddButton(reason)
		reason.text, reason.arg1, reason.checked, reason.isNotRadio = L["BOSSKILLBONUS"], L["BOSSKILLBONUS"], L["BOSSKILLBONUS"] == curReason, true
		DD:UIDropDownMenu_AddButton(reason)
		reason.text, reason.arg1, reason.checked, reason.isNotRadio = L["RAIDCOMPLETIONBONUS"], L["RAIDCOMPLETIONBONUS"], L["RAIDCOMPLETIONBONUS"] == curReason, true
		DD:UIDropDownMenu_AddButton(reason)
		reason.text, reason.arg1, reason.checked, reason.isNotRadio = L["NEWBOSSKILLBONUS"], L["NEWBOSSKILLBONUS"], L["NEWBOSSKILLBONUS"] == curReason, true
		DD:UIDropDownMenu_AddButton(reason)
		reason.text, reason.arg1, reason.checked, reason.isNotRadio = L["CORRECTINGERROR"], L["CORRECTINGERROR"], L["CORRECTINGERROR"] == curReason, true
		DD:UIDropDownMenu_AddButton(reason)
		reason.text, reason.arg1, reason.checked, reason.isNotRadio = L["DKPADJUST"], L["DKPADJUST"], L["DKPADJUST"] == curReason, true
		DD:UIDropDownMenu_AddButton(reason)
		reason.text, reason.arg1, reason.checked, reason.isNotRadio = L["UNEXCUSEDABSENCE"], L["UNEXCUSEDABSENCE"], L["UNEXCUSEDABSENCE"] == curReason, true
		DD:UIDropDownMenu_AddButton(reason)
		reason.text, reason.arg1, reason.checked, reason.isNotRadio = L["OTHER"], L["OTHER"], L["OTHER"] == curReason, true
		DD:UIDropDownMenu_AddButton(reason)
	end)

	-- Dropdown Menu Function
	function CommDKP.ConfigTab2.reasonDropDown:SetValue(newValue)
		if curReason ~= newValue then curReason = newValue else curReason = nil end

		DD:UIDropDownMenu_SetText(CommDKP.ConfigTab2.reasonDropDown, curReason)

		if (curReason == L["ONTIMEBONUS"]) then CommDKP.ConfigTab2.addDKP:SetNumber(core.DB.DKPBonus.OnTimeBonus); CommDKP.ConfigTab2.BossKilledDropdown:Hide()
		elseif (curReason == L["BOSSKILLBONUS"]) then
			CommDKP.ConfigTab2.addDKP:SetNumber(core.DB.DKPBonus.BossKillBonus);
			CommDKP.ConfigTab2.BossKilledDropdown:Show()
			DD:UIDropDownMenu_SetText(CommDKP.ConfigTab2.BossKilledDropdown, core.CurrentRaidZone..": "..core.LastKilledBoss)
		elseif (curReason == L["RAIDCOMPLETIONBONUS"]) then CommDKP.ConfigTab2.addDKP:SetNumber(core.DB.DKPBonus.CompletionBonus); CommDKP.ConfigTab2.BossKilledDropdown:Hide()
		elseif (curReason == L["NEWBOSSKILLBONUS"]) then
			CommDKP.ConfigTab2.addDKP:SetNumber(core.DB.DKPBonus.NewBossKillBonus);
			CommDKP.ConfigTab2.BossKilledDropdown:Show()
			DD:UIDropDownMenu_SetText(CommDKP.ConfigTab2.BossKilledDropdown, core.CurrentRaidZone..": "..core.LastKilledBoss)
		elseif (curReason == L["UNEXCUSEDABSENCE"]) then CommDKP.ConfigTab2.addDKP:SetNumber(core.DB.DKPBonus.UnexcusedAbsence); CommDKP.ConfigTab2.BossKilledDropdown:Hide()
		else CommDKP.ConfigTab2.addDKP:SetText(""); CommDKP.ConfigTab2.BossKilledDropdown:Hide() end

		if (curReason == L["OTHER"]) then
			CommDKP.ConfigTab2.otherReason:Show();
			CommDKP.ConfigTab2.BossKilledDropdown:Hide()
		else
			CommDKP.ConfigTab2.otherReason:Hide();
		end

		LibDD:CloseDropDownMenus()
	end

	CommDKP.ConfigTab2.reasonDropDown:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_RIGHT");
		GameTooltip:SetText(L["REASON"], 0.25, 0.75, 0.90, 1, true);
		GameTooltip:AddLine(L["REASONTTDESC"], 1.0, 1.0, 1.0, true);
		GameTooltip:AddLine(L["REASONTTWARN"], 1.0, 0, 0, true);
		GameTooltip:Show();
	end)
	CommDKP.ConfigTab2.reasonDropDown:SetScript("OnLeave", function(self)
		GameTooltip:Hide()
	end)

	CommDKP.ConfigTab2.reasonHeader = W.CreateText(mBody, "label", L["REASONFORADJUSTMENT"], "LEFT")
	CommDKP.ConfigTab2.reasonHeader:SetPoint("TOPLEFT", CommDKP.ConfigTab2.description, "BOTTOMLEFT", 0, -10);   -- AD-20.3.2
	local reasonHeader = CommDKP.ConfigTab2.reasonHeader     -- anchor of the control group (intra-group offsets unchanged)
	CommDKP.ConfigTab2.reasonDropDown:SetPoint("TOPLEFT", reasonHeader, "TOPLEFT", 0, -16)

	-- Other Reason Editbox. Hidden unless "Other" is selected in dropdown

	-- AD-16 B5: the hint is a placeholder (never written into the box), so GetText() is "" until the officer types.
	CommDKP.ConfigTab2.otherReason = CreateFrame("EditBox", nil, mBody)

	CommDKP.ConfigTab2.otherReason:SetPoint("TOPLEFT", reasonHeader, "TOPLEFT", 0, -44)     -- conditional slot (shared with BossKilledDropdown)
	CommDKP.ConfigTab2.otherReason:SetAutoFocus(false)
	CommDKP.ConfigTab2.otherReason:SetMultiLine(false)
	CommDKP.ConfigTab2.otherReason:SetSize(INNER, W.H)
	CommDKP.ConfigTab2.otherReason:SetMaxLetters(50)
	CommDKP.ConfigTab2.otherReason:SetScript("OnEscapePressed", function(self)    -- clears text and focus on esc
		self:ClearFocus()
	end)
	W.StyleEditBox(CommDKP.ConfigTab2.otherReason, { placeholder = L["ENTEROTHERREASONHERE"], align = "LEFT" })
	CommDKP.ConfigTab2.otherReason:Hide();

	-- Boss Killed Dropdown - Hidden unless "Boss Kill Bonus" or "New Boss Kill Bonus" is selected
	-- Killing a boss on the list will auto select that boss
	CommDKP.ConfigTab2.BossKilledDropdown = DD:Create_UIDropDownMenu("CommDKPBossKilledDropdown", mBody);
	CommDKP.ConfigTab2.BossKilledDropdown:SetPoint("TOPLEFT", reasonHeader, "TOPLEFT", 0, -44)
	CommDKP.ConfigTab2.BossKilledDropdown:Hide()
	DD:UIDropDownMenu_SetWidth(CommDKP.ConfigTab2.BossKilledDropdown, INNER)
	DD:UIDropDownMenu_SetText(CommDKP.ConfigTab2.BossKilledDropdown, L["SELECTBOSS"])

	DD:UIDropDownMenu_Initialize(CommDKP.ConfigTab2.BossKilledDropdown, function(self, level, menuList)
		
		local boss = DD:UIDropDownMenu_CreateInfo()

		if (level or 1) == 1 then
			-- AD-11.4: static raid zones (TBC removed), then discovered Forever raids
			for _, key in ipairs(core.RaidMenuOrder) do
				local zone = core.ZoneList[core.RaidZoneIndex[key]]
				boss.text, boss.checked, boss.menuList, boss.hasArrow = zone, core.CurrentRaidZone == zone, key, true
				DD:UIDropDownMenu_AddButton(boss)
			end
			local custom = CommDKP:GetCustomEncounterZones()
			if #custom > 0 then
				local title = DD:UIDropDownMenu_CreateInfo()		-- separate table: isTitle must not leak into `boss`
				title.text, title.isTitle, title.notCheckable = L["DISCOVEREDRAIDS"] or "Discovered Raids", true, true
				DD:UIDropDownMenu_AddButton(title)
				for _, zone in ipairs(custom) do
					boss.text, boss.checked, boss.menuList, boss.hasArrow = zone, core.CurrentRaidZone == zone, "CUSTOM:"..zone, true
					DD:UIDropDownMenu_AddButton(boss)
				end
			end
		else
			boss.func = self.SetValue
			local zone, seen = nil, {}
			if menuList:sub(1, 7) == "CUSTOM:" then
				zone = menuList:sub(8)
			else
				zone = core.ZoneList[core.RaidZoneIndex[menuList]]
				for i = 1, #core.BossList[menuList] do
					local name = core.BossList[menuList][i]
					seen[name] = true
					boss.text, boss.arg1, boss.arg2, boss.checked = name, menuList, i, name == core.LastKilledBoss   -- AD-18.3: (key, index)
					DD:UIDropDownMenu_AddButton(boss, level)
				end
			end
			for _, e in ipairs(CommDKP:GetCustomBosses(zone, seen)) do	-- discovered bosses (merged into the static zones too)
				boss.text, boss.arg1, boss.arg2, boss.checked = e.name, e.id, zone, (e.name == core.LastKilledBoss and core.CurrentRaidZone == zone)
				DD:UIDropDownMenu_AddButton(boss, level)
			end
		end
	end)

	-- Called through boss.func with the menu button as `self`, so it must not use `self`.
	-- AD-18.3: (raidKey, index) for static rows, (encounterID, zone) for discovered rows; a bare ID still works.
	function CommDKP.ConfigTab2.BossKilledDropdown:SetValue(newValue, arg2)
		local zone, bossName = CommDKP:ResolveMenuBoss(newValue, arg2)
		if not zone then return end
		CommDKP:ApplyBossContext(zone, bossName)					-- calls RefreshBossContext below
	end

	function CommDKP.ConfigTab2.BossKilledDropdown:RefreshBossContext()
		if curReason ~= L["BOSSKILLBONUS"] and curReason ~= L["NEWBOSSKILLBONUS"] then
			CommDKP.ConfigTab2.reasonDropDown:SetValue(L["BOSSKILLBONUS"])
		end
		DD:UIDropDownMenu_SetText(self, core.CurrentRaidZone..": "..core.LastKilledBoss)
		LibDD:CloseDropDownMenus()
	end

	-- Add DKP Edit Box

	CommDKP.ConfigTab2.addDKP = CreateFrame("EditBox", nil, mBody)

	CommDKP.ConfigTab2.addDKP:SetPoint("TOPLEFT", reasonHeader, "TOPLEFT", 0, -92)
	CommDKP.ConfigTab2.addDKP:SetAutoFocus(false)
	CommDKP.ConfigTab2.addDKP:SetMultiLine(false)
	CommDKP.ConfigTab2.addDKP:SetSize(90, W.H)
	CommDKP.ConfigTab2.addDKP:SetMaxLetters(10)
	CommDKP.ConfigTab2.addDKP:SetScript("OnEscapePressed", function(self)    -- clears text and focus on esc
		self:SetText("")
		self:ClearFocus()
	end)
	CommDKP.ConfigTab2.addDKP:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_RIGHT");
		GameTooltip:SetText(L["POINTS"], 0.25, 0.75, 0.90, 1, true);
		GameTooltip:AddLine(L["POINTSTTDESC"], 1.0, 1.0, 1.0, true);
		GameTooltip:AddLine(L["POINTSTTWARN"], 1.0, 0, 0, true);
		GameTooltip:Show();
	end)
	CommDKP.ConfigTab2.addDKP:SetScript("OnLeave", function(self)
		GameTooltip:Hide()
	end)
	W.StyleEditBox(CommDKP.ConfigTab2.addDKP, { numeric = true })   -- B11: right-aligned only; -50 still allowed

	CommDKP.ConfigTab2.pointsHeader = W.CreateText(mBody, "label", L["POINTS"], "LEFT")
	CommDKP.ConfigTab2.pointsHeader:SetPoint("TOPLEFT", reasonHeader, "TOPLEFT", 0, -78);

	-- Raid Only Checkbox
	CommDKP.ConfigTab2.RaidOnlyCheck = W.CreateCheckbox(mBody, nil, "Show Raid Only");
	CommDKP.ConfigTab2.RaidOnlyCheck:SetChecked(false)
	CommDKP.ConfigTab2.RaidOnlyCheck:SetPoint("TOPLEFT", reasonHeader, "TOPLEFT", 0, -130);   -- hidden (AD-20.3.2)
	CommDKP.ConfigTab2.RaidOnlyCheck:Hide()
	

	-- Select All Checkbox
	CommDKP.ConfigTab2.selectAll = W.CreateCheckbox(mBody, nil, L["SELECTALLVISIBLE"]);
	CommDKP.ConfigTab2.selectAll:SetChecked(false)
	CommDKP.ConfigTab2.selectAll:SetPoint("TOPLEFT", reasonHeader, "TOPLEFT", 0, -154);   -- hidden (AD-20.3.2)
	CommDKP.ConfigTab2.selectAll:Hide();
	

		-- Adjust DKP Button
	CommDKP.ConfigTab2.adjustButton = self:CreateButton("BOTTOMRIGHT", mBody, "BOTTOMRIGHT", -W.PAD, W.PAD, L["ADJUSTDKP"]);
	CommDKP.ConfigTab2.adjustButton:SetSize(110, W.H)
	W.StyleButton(CommDKP.ConfigTab2.adjustButton, "primary")
	CommDKP.ConfigTab2.adjustButton:SetScript("OnClick", function()
		if #core.SelectedData > 0 and curReason and CommDKP.ConfigTab2.otherReason:GetText() then
			local selected = L["AREYOUSURE"].." "..CommDKP_round(CommDKP.ConfigTab2.addDKP:GetNumber(), core.DB.modes.rounding).." "..L["DKPTOFOLLOWING"]..": \n\n";

			for i=1, #core.SelectedData do
				local classSearch = CommDKP:Table_Search(CommDKP:GetTable(CommDKP_DKPTable, true), core.SelectedData[i].player)

				if classSearch then
					c = CommDKP:GetCColors(CommDKP:GetTable(CommDKP_DKPTable, true)[classSearch[1][1]].class)
				else
					c = { hex="ffffffff" }
				end
				if i == 1 then
					selected = selected.."|c"..c.hex..core.SelectedData[i].player.."|r"
				else
					selected = selected..", |c"..c.hex..core.SelectedData[i].player.."|r"
				end
			end
			StaticPopupDialogs["ADJUST_DKP"] = {
				text = selected,
				button1 = L["YES"],
				button2 = L["NO"],
				OnAccept = function()
					CommDKP:AdjustDKP(CommDKP.ConfigTab2.addDKP:GetNumber())
				end,
				timeout = 0,
				whileDead = true,
				hideOnEscape = true,
				preferredIndex = 3,
			}
			StaticPopup_Show ("ADJUST_DKP")
		else
			CommDKP:AdjustDKP(CommDKP.ConfigTab2.addDKP:GetNumber());
		end
	end)
	CommDKP.ConfigTab2.adjustButton:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_RIGHT");
		GameTooltip:SetText(L["ADJUSTDKP"], 0.25, 0.75, 0.90, 1, true);
		GameTooltip:AddLine(L["ADJUSTDKPTTDESC"], 1.0, 1.0, 1.0, true);
		GameTooltip:AddLine(L["ADJUSTDKPTTWARN"], 1.0, 0, 0, true);
		GameTooltip:Show();
	end)
	CommDKP.ConfigTab2.adjustButton:SetScript("OnLeave", function(self)
		GameTooltip:Hide()
	end)

	-- weekly decay Editbox

	CommDKP.ConfigTab2.decayDKP = CreateFrame("EditBox", nil, dBody)

	CommDKP.ConfigTab2.decayDKP:SetPoint("TOPLEFT", dBody, "TOPLEFT", W.PAD, -24)
	CommDKP.ConfigTab2.decayDKP:SetAutoFocus(false)
	CommDKP.ConfigTab2.decayDKP:SetMultiLine(false)
	CommDKP.ConfigTab2.decayDKP:SetSize(60, W.H)
	CommDKP.ConfigTab2.decayDKP:SetMaxLetters(4)
	CommDKP.ConfigTab2.decayDKP:SetNumber(tonumber(core.DB.DKPBonus.DecayPercentage))
	CommDKP.ConfigTab2.decayDKP:SetScript("OnEscapePressed", function(self)    -- clears focus on esc
		self:ClearFocus()
	end)

	CommDKP.ConfigTab2.decayDKP:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_RIGHT");
		GameTooltip:SetText(L["WEEKLYDKPDECAY"], 0.25, 0.75, 0.90, 1, true);
		GameTooltip:AddLine(L["WEEKLYDECAYTTDESC"], 1.0, 1.0, 1.0, true);
		GameTooltip:AddLine(L["WEEKLYDECAYTTWARN"], 1.0, 0, 0, true);
		GameTooltip:Show();
	end)
	CommDKP.ConfigTab2.decayDKP:SetScript("OnLeave", function(self)
		GameTooltip:Hide()
	end)
	W.StyleEditBox(CommDKP.ConfigTab2.decayDKP, { numeric = true })

	CommDKP.ConfigTab2.decayDKPHeader = W.CreateText(dBody, "label", L["WEEKLYDKPDECAY"], "LEFT")
	CommDKP.ConfigTab2.decayDKPHeader:SetPoint("TOPLEFT", dBody, "TOPLEFT", W.PAD, -8);

	CommDKP.ConfigTab2.decayDKPFooter = W.CreateText(dBody, "body", "%", "LEFT", "textMuted")
	CommDKP.ConfigTab2.decayDKPFooter:SetPoint("LEFT", CommDKP.ConfigTab2.decayDKP, "RIGHT", 4, 0);

	-- selected players only checkbox
	CommDKP.ConfigTab2.SelectedOnlyCheck = W.CreateCheckbox(dBody, nil, L["SELPLAYERSONLY"]);
	CommDKP.ConfigTab2.SelectedOnlyCheck:SetChecked(false)
	CommDKP.ConfigTab2.SelectedOnlyCheck:SetPoint("TOPLEFT", dBody, "TOPLEFT", W.PAD, -58);
	CommDKP.ConfigTab2.SelectedOnlyCheck:SetScript("OnClick", function(self)
		PlaySound(808)
	end)
	CommDKP.ConfigTab2.SelectedOnlyCheck:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_RIGHT");
		GameTooltip:SetText(L["SELPLAYERSONLY"], 0.25, 0.75, 0.90, 1, true);
		GameTooltip:AddLine(L["SELPLAYERSTTDESC"], 1.0, 1.0, 1.0, true);
		GameTooltip:AddLine(L["SELPLAYERSTTWARN"], 1.0, 0, 0, true);
		GameTooltip:Show();
	end)
	CommDKP.ConfigTab2.SelectedOnlyCheck:SetScript("OnLeave", function(self)
		GameTooltip:Hide()
	end)

	-- add to negative dkp checkbox
	CommDKP.ConfigTab2.AddNegative = W.CreateCheckbox(dBody, nil, L["ADDNEGVALUES"]);
	CommDKP.ConfigTab2.AddNegative:SetChecked(core.DB.modes.AddToNegative)
	CommDKP.ConfigTab2.AddNegative:SetPoint("TOPLEFT", dBody, "TOPLEFT", W.PAD, -82);
	CommDKP.ConfigTab2.AddNegative:SetScript("OnClick", function(self)
		core.DB.modes.AddToNegative = self:GetChecked();
		PlaySound(808)
	end)
	CommDKP.ConfigTab2.AddNegative:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_RIGHT");
		GameTooltip:SetText(L["ADDNEGVALUES"], 0.25, 0.75, 0.90, 1, true);
		GameTooltip:AddLine(L["ADDNEGTTDESC"], 1.0, 1.0, 1.0, true);
		GameTooltip:AddLine(L["ADDNEGTTWARN"], 1.0, 0, 0, true);
		GameTooltip:Show();
	end)
	CommDKP.ConfigTab2.AddNegative:SetScript("OnLeave", function(self)
		GameTooltip:Hide()
	end)

	CommDKP.ConfigTab2.decayButton = self:CreateButton("BOTTOMRIGHT", dBody, "BOTTOMRIGHT", -W.PAD, W.PAD, L["APPLYDECAY"]);
	CommDKP.ConfigTab2.decayButton:SetSize(110, W.H)
	W.StyleButton(CommDKP.ConfigTab2.decayButton, "primary")
	CommDKP.ConfigTab2.decayButton:SetScript("OnClick", function()
		local SelectedToggle;
		local selected;

		if CommDKP.ConfigTab2.SelectedOnlyCheck:GetChecked() then SelectedToggle = "|cffff0000"..L["SELECTED"].."|r" else SelectedToggle = "|cffff0000"..L["ALL"].."|r" end
		selected = L["CONFIRMDECAY"].." "..SelectedToggle.." "..L["DKPENTRIESBY"].." "..CommDKP.ConfigTab2.decayDKP:GetNumber().."%%";

			StaticPopupDialogs["ADJUST_DKP"] = {
				text = selected,
				button1 = L["YES"],
				button2 = L["NO"],
				OnAccept = function()
					DecayDKP(CommDKP.ConfigTab2.decayDKP:GetNumber(), "percent", CommDKP.ConfigTab2.SelectedOnlyCheck:GetChecked())
				end,
				timeout = 0,
				whileDead = true,
				hideOnEscape = true,
				preferredIndex = 3,
			}
			StaticPopup_Show ("ADJUST_DKP")
	end)
	CommDKP.ConfigTab2.decayButton:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_RIGHT");
		GameTooltip:SetText(L["WEEKLYDKPDECAY"], 0.25, 0.75, 0.90, 1, true);
		GameTooltip:AddLine(L["APPDECAYTTDESC"], 1.0, 1.0, 1.0, true);
		GameTooltip:AddLine(L["APPDECAYTTWARN"], 1.0, 0, 0, true);
		GameTooltip:Show();
	end)
	CommDKP.ConfigTab2.decayButton:SetScript("OnLeave", function(self)
		GameTooltip:Hide()
	end)

	-- Raid Timer Container

	-- AD-19.2 (012c) (g) / UX §13.7 (b): 256 wide at (278, 0) -> right edge 534, 4 px clear of the pane rail lane.
	local RT_W = 256
	local RT_INNER = RT_W - 6 - 2 * W.PAD     -- usable body width of the Raid Timer card (226)
	CommDKP.ConfigTab2.RaidTimerContainer = W.CreateCard(CommDKP.ConfigTab2, L["RAIDTIMER"], RT_W, 482);
	CommDKP.ConfigTab2.RaidTimerContainer:SetPoint("TOPLEFT", CommDKP.ConfigTab2, "TOPLEFT", 278, 0)
	local rBody = CommDKP.ConfigTab2.RaidTimerContainer.Body
	local HALF = math.floor((RT_INNER - 6) / 2)  -- two side-by-side controls (110)
		-- Pop out button: a 20 x 20 [>] / [<] icon button in the card header's right slot (its ">"/"<" text is logic state)
		CommDKP.ConfigTab2.RaidTimerContainer.PopOut = W.CreateButton(CommDKP.ConfigTab2.RaidTimerContainer, ">", nil, { width = 20 })
		CommDKP.ConfigTab2.RaidTimerContainer.PopOut:SetSize(20, 20)
		CommDKP.ConfigTab2.RaidTimerContainer:AddHeaderButton(CommDKP.ConfigTab2.RaidTimerContainer.PopOut)
		CommDKP.ConfigTab2.RaidTimerContainer.PopOut:ClearAllPoints()
		CommDKP.ConfigTab2.RaidTimerContainer.PopOut:SetPoint("RIGHT", CommDKP.ConfigTab2.RaidTimerContainer.Header.Actions, "RIGHT", -2, 0)
		CommDKP.ConfigTab2.RaidTimerContainer.PopOut:SetText(">")
		CommDKP.ConfigTab2.RaidTimerContainer.PopOut:SetScript("OnEnter", function(self)
			GameTooltip:SetOwner(self, "ANCHOR_RIGHT");
			GameTooltip:SetText(L["POPOUTTIMER"], 0.25, 0.75, 0.90, 1, true);
			GameTooltip:AddLine(L["POPOUTTIMERDESC"], 1.0, 1.0, 1.0, true);
			GameTooltip:Show();
		end)
		CommDKP.ConfigTab2.RaidTimerContainer.PopOut:SetScript("OnLeave", function(self)
			GameTooltip:Hide();
		end)
		CommDKP.ConfigTab2.RaidTimerContainer.PopOut:SetScript("OnClick", function(self)
			if self:GetText() == ">" then
				self:SetText("<");
				RaidTimerPopout_Create()
			else
				self:SetText(">");
			CommDKP.RaidTimerPopout:Hide();
			end
		end)
		W.StyleButton(CommDKP.ConfigTab2.RaidTimerContainer.PopOut)

		-- Raid Timer Header
	    -- (the old "RAID TIMER" large text is now the card title; .Header is the card's header band)
	    -- Readout well (bg0 + 1 px line): Time Elapsed on the left, Bonus Awarded on the right.
	    CommDKP.ConfigTab2.RaidTimerContainer.Readout = CreateFrame("Frame", nil, rBody)
	    CommDKP.ConfigTab2.RaidTimerContainer.Readout:SetPoint("TOPLEFT", rBody, "TOPLEFT", W.PAD, -10)
	    CommDKP.ConfigTab2.RaidTimerContainer.Readout:SetSize(RT_INNER, 58)
	    CommDKP.ConfigTab2.RaidTimerContainer.Readout.Fill = CommDKP.ConfigTab2.RaidTimerContainer.Readout:CreateTexture(nil, "BACKGROUND")
	    CommDKP.ConfigTab2.RaidTimerContainer.Readout.Fill:SetAllPoints()
	    CommDKP.ConfigTab2.RaidTimerContainer.Readout.Fill:SetColorTexture(unpack((core.Palette or core.Palettes.Forever).bg0))
	    CommDKP.ConfigTab2.RaidTimerContainer.Readout.Edges = CommDKP:CreatePixelBorder(CommDKP.ConfigTab2.RaidTimerContainer.Readout, (core.Palette or core.Palettes.Forever).line)
	    local well = CommDKP.ConfigTab2.RaidTimerContainer.Readout

	    -- Raid Timer Output Header
	    CommDKP.ConfigTab2.RaidTimerContainer.OutputHeader = W.CreateText(well, "label", L["TIMEELAPSED"], "LEFT")
	    CommDKP.ConfigTab2.RaidTimerContainer.OutputHeader:SetPoint("TOPLEFT", well, "TOPLEFT", 8, -7);   -- §12.3.3: now shown

	    -- Raid Timer Output
	    CommDKP.ConfigTab2.RaidTimerContainer.Output = W.CreateText(well, "readout", "|cff00ff0000:00:00|r", "LEFT")   -- AD-19 R1: green idle clock (popout parity)
	    CommDKP.ConfigTab2.RaidTimerContainer.Output:SetPoint("BOTTOMLEFT", well, "BOTTOMLEFT", 8, 7);

	    -- Bonus Awarded Header
	    CommDKP.ConfigTab2.RaidTimerContainer.BonusHeader = W.CreateText(well, "label", L["BONUSAWARDED"], "RIGHT")
	    CommDKP.ConfigTab2.RaidTimerContainer.BonusHeader:SetPoint("TOPRIGHT", well, "TOPRIGHT", -8, -7);   -- §12.3.3: now shown

	    -- Bonus Awarded Output
	    CommDKP.ConfigTab2.RaidTimerContainer.Bonus = W.CreateText(well, "readout", "|cff00ff000|r", "RIGHT")   -- AD-19 R1: green idle bonus
	    CommDKP.ConfigTab2.RaidTimerContainer.Bonus:SetPoint("BOTTOMRIGHT", well, "BOTTOMRIGHT", -8, 7);

	    -- Start Raid Timer Button
	    CommDKP.ConfigTab2.RaidTimerContainer.StartTimer = self:CreateButton("TOPLEFT", rBody, "TOPLEFT", W.PAD, -214, L["INITRAID"]);
		CommDKP.ConfigTab2.RaidTimerContainer.StartTimer:SetSize(HALF, W.H)
		W.StyleButton(CommDKP.ConfigTab2.RaidTimerContainer.StartTimer, "primary")
		CommDKP.ConfigTab2.RaidTimerContainer.StartTimer:SetScript("OnClick", function(self)
			if not IsInRaid() then
				StaticPopupDialogs["NO_RAID_TIMER"] = {
					text = L["NOTINRAID"],
					button1 = L["OK"],
					timeout = 0,
					whileDead = true,
					hideOnEscape = true,
					preferredIndex = 3,
				}
				StaticPopup_Show ("NO_RAID_TIMER")
				return;
			end
			if not core.RaidInProgress then				
				if core.DB.DKPBonus.GiveRaidStart and self:GetText() ~= L["CONTINUERAID"] then
					StaticPopupDialogs["START_RAID_BONUS"] = {
						text = L["RAIDTIMERBONUSCONFIRM"],
						button1 = L["YES"],
						button2 = L["NO"],
						OnAccept = function()						
							local setInterval = CommDKP.ConfigTab2.RaidTimerContainer.interval:GetNumber();
							local setBonus = CommDKP.ConfigTab2.RaidTimerContainer.bonusvalue:GetNumber();
							local setOnTime = tostring(CommDKP.ConfigTab2.RaidTimerContainer.StartBonus:GetChecked());
							local setGiveEnd = tostring(CommDKP.ConfigTab2.RaidTimerContainer.EndRaidBonus:GetChecked());
							local setStandby = tostring(CommDKP.ConfigTab2.RaidTimerContainer.StandbyInclude:GetChecked());
							CommDKP.Sync:SendData("CommDKPRaidTime", "start,false "..setInterval.. " "..setBonus.." "..setOnTime.." "..setGiveEnd.." "..setStandby)
							if CommDKP.ConfigTab2.RaidTimerContainer.StartTimer:GetText() == L["CONTINUERAID"] then
								CommDKP.Sync:SendData("CommDKPBCastMsg", L["RAIDRESUME"])
							else
								CommDKP.Sync:SendData("CommDKPBCastMsg", L["RAIDSTART"])
								CommDKP.ConfigTab2.RaidTimerContainer.Output:SetText("|cff00ff0000:00:00|r")   -- AD-19.2 (g): well-formed fresh-start seed
							end
							CommDKP:StartRaidTimer(false)
						end,
						timeout = 0,
						whileDead = true,
						hideOnEscape = true,
						preferredIndex = 3,
					}
					StaticPopup_Show ("START_RAID_BONUS")
				else
					local setInterval = CommDKP.ConfigTab2.RaidTimerContainer.interval:GetNumber();
					local setBonus = CommDKP.ConfigTab2.RaidTimerContainer.bonusvalue:GetNumber();
					local setOnTime = tostring(CommDKP.ConfigTab2.RaidTimerContainer.StartBonus:GetChecked());
					local setGiveEnd = tostring(CommDKP.ConfigTab2.RaidTimerContainer.EndRaidBonus:GetChecked());
					local setStandby = tostring(CommDKP.ConfigTab2.RaidTimerContainer.StandbyInclude:GetChecked());
					CommDKP.Sync:SendData("CommDKPRaidTime", "start,false "..setInterval.. " "..setBonus.." "..setOnTime.." "..setGiveEnd.." "..setStandby)
					if CommDKP.ConfigTab2.RaidTimerContainer.StartTimer:GetText() == L["CONTINUERAID"] then
						CommDKP.Sync:SendData("CommDKPBCastMsg", L["RAIDRESUME"])
					else
						CommDKP.Sync:SendData("CommDKPBCastMsg", L["RAIDSTART"])
						CommDKP.ConfigTab2.RaidTimerContainer.Output:SetText("|cff00ff0000:00:00|r")   -- AD-19.2 (g): well-formed fresh-start seed
					end
					CommDKP:StartRaidTimer(false)
				end
			else
				StaticPopupDialogs["END_RAID"] = {
					text = L["ENDCURRAIDCONFIRM"],
					button1 = L["YES"],
					button2 = L["NO"],
					OnAccept = function()
						CommDKP.Sync:SendData("CommDKPBCastMsg", L["RAIDTIMERCONCLUDE"].." "..CommDKP.ConfigTab2.RaidTimerContainer.Output:GetText().."!")
						CommDKP.Sync:SendData("CommDKPRaidTime", "stop")
						CommDKP:StopRaidTimer()
					end,
					timeout = 0,
					whileDead = true,
					hideOnEscape = true,
					preferredIndex = 3,
				}
				StaticPopup_Show ("END_RAID")
			end
		end)
		CommDKP.ConfigTab2.RaidTimerContainer.StartTimer:SetScript("OnEnter", function(self)
			GameTooltip:SetOwner(self, "ANCHOR_RIGHT");
			GameTooltip:SetText(L["INITRAID"], 0.25, 0.75, 0.90, 1, true);
			GameTooltip:AddLine(L["INITRAIDTTDESC"], 1.0, 1.0, 1.0, true);
			GameTooltip:AddLine(L["INITRAIDTTWARN"], 1.0, 0, 0, true);
			GameTooltip:Show();
		end)
		CommDKP.ConfigTab2.RaidTimerContainer.StartTimer:SetScript("OnLeave", function(self)
			GameTooltip:Hide()
		end)

		-- Pause Raid Timer Button
	    CommDKP.ConfigTab2.RaidTimerContainer.PauseTimer = self:CreateButton("TOPLEFT", rBody, "TOPLEFT", W.PAD + HALF + 6, -214, L["PAUSERAID"]);
		CommDKP.ConfigTab2.RaidTimerContainer.PauseTimer:SetSize(HALF, W.H)
		CommDKP.ConfigTab2.RaidTimerContainer.PauseTimer:Hide();
		CommDKP.ConfigTab2.RaidTimerContainer.PauseTimer:SetScript("OnClick", function(self)
			if core.RaidInProgress then
				local setInterval = CommDKP.ConfigTab2.RaidTimerContainer.interval:GetNumber();
				local setBonus = CommDKP.ConfigTab2.RaidTimerContainer.bonusvalue:GetNumber();
				local setOnTime = tostring(CommDKP.ConfigTab2.RaidTimerContainer.StartBonus:GetChecked());
				local setGiveEnd = tostring(CommDKP.ConfigTab2.RaidTimerContainer.EndRaidBonus:GetChecked());
				local setStandby = tostring(CommDKP.ConfigTab2.RaidTimerContainer.StandbyInclude:GetChecked());

				CommDKP.Sync:SendData("CommDKPRaidTime", "start,true "..setInterval.. " "..setBonus.." "..setOnTime.." "..setGiveEnd.." "..setStandby)
				CommDKP.Sync:SendData("CommDKPBCastMsg", L["RAIDPAUSE"].." "..CommDKP.ConfigTab2.RaidTimerContainer.Output:GetText().."!")
				CommDKP:StartRaidTimer(true)
			end
		end)
		CommDKP.ConfigTab2.RaidTimerContainer.PauseTimer:SetScript("OnEnter", function(self)
			GameTooltip:SetOwner(self, "ANCHOR_RIGHT");
			GameTooltip:SetText(L["PAUSERAID"], 0.25, 0.75, 0.90, 1, true);
			GameTooltip:AddLine(L["PAUSERAIDTTDESC"], 1.0, 1.0, 1.0, true);
			GameTooltip:AddLine(L["PAUSERAIDTTWARN"], 1.0, 0, 0, true);
			GameTooltip:Show();
		end)
		CommDKP.ConfigTab2.RaidTimerContainer.PauseTimer:SetScript("OnLeave", function(self)
			GameTooltip:Hide()
		end)

		-- Award Interval Editbox
		if not core.DB.modes.increment then core.DB.modes.increment = 60 end

		CommDKP.ConfigTab2.RaidTimerContainer.interval = CreateFrame("EditBox", nil, rBody)

		CommDKP.ConfigTab2.RaidTimerContainer.interval:SetPoint("TOPLEFT", rBody, "TOPLEFT", W.PAD, -96)
		CommDKP.ConfigTab2.RaidTimerContainer.interval:SetAutoFocus(false)
		CommDKP.ConfigTab2.RaidTimerContainer.interval:SetMultiLine(false)
		CommDKP.ConfigTab2.RaidTimerContainer.interval:SetSize(HALF, W.H)
		CommDKP.ConfigTab2.RaidTimerContainer.interval:SetMaxLetters(5)
		CommDKP.ConfigTab2.RaidTimerContainer.interval:SetNumber(tonumber(core.DB.modes.increment))
		CommDKP.ConfigTab2.RaidTimerContainer.interval:SetScript("OnTextChanged", function(self)    -- clears focus on esc
			if tonumber(self:GetNumber()) then
				core.DB.modes.increment = self:GetNumber();
			else
				StaticPopupDialogs["ALERT_NUMBER"] = {
					text = L["INCREMENTINVALIDWARN"],
					button1 = L["OK"],
					timeout = 0,
					whileDead = true,
					hideOnEscape = true,
					preferredIndex = 3,
				}
				StaticPopup_Show ("ALERT_NUMBER")
			end
		end)
		CommDKP.ConfigTab2.RaidTimerContainer.interval:SetScript("OnEscapePressed", function(self)    -- clears focus on esc
			self:HighlightText(0,0)
			self:ClearFocus()
		end)
		CommDKP.ConfigTab2.RaidTimerContainer.interval:SetScript("OnEnterPressed", function(self)    -- clears focus on esc
			self:HighlightText(0,0)
			self:ClearFocus()
		end)
		CommDKP.ConfigTab2.RaidTimerContainer.interval:SetScript("OnTabPressed", function(self)    -- clears focus on esc
			self:HighlightText(0,0)
			CommDKP.ConfigTab2.RaidTimerContainer.bonusvalue:SetFocus()
			CommDKP.ConfigTab2.RaidTimerContainer.bonusvalue:HighlightText()
		end)

		CommDKP.ConfigTab2.RaidTimerContainer.interval:SetScript("OnEnter", function(self)
			GameTooltip:SetOwner(self, "ANCHOR_RIGHT");
			GameTooltip:SetText(L["AWARDINTERVAL"], 0.25, 0.75, 0.90, 1, true);
			GameTooltip:AddLine(L["AWARDINTERVALTTDESC"], 1.0, 1.0, 1.0, true);
			GameTooltip:AddLine(L["AWARDINTERVALTTWARN"], 1.0, 0, 0, true);
			GameTooltip:Show();
		end)
		CommDKP.ConfigTab2.RaidTimerContainer.interval:SetScript("OnLeave", function(self)
			GameTooltip:Hide()
		end)
		W.StyleEditBox(CommDKP.ConfigTab2.RaidTimerContainer.interval, { numeric = true })

		CommDKP.ConfigTab2.RaidTimerContainer.intervalHeader = W.CreateText(rBody, "label", L["INTERVAL"], "LEFT")
	    CommDKP.ConfigTab2.RaidTimerContainer.intervalHeader:SetPoint("BOTTOMLEFT", CommDKP.ConfigTab2.RaidTimerContainer.interval, "TOPLEFT", 0, 4);

	    -- Award Value Editbox
	    if not core.DB.DKPBonus.IntervalBonus then core.DB.DKPBonus.IntervalBonus = 15 end

		CommDKP.ConfigTab2.RaidTimerContainer.bonusvalue = CreateFrame("EditBox", nil, rBody)

		CommDKP.ConfigTab2.RaidTimerContainer.bonusvalue:SetPoint("LEFT", CommDKP.ConfigTab2.RaidTimerContainer.interval, "RIGHT", 6, 0)
		CommDKP.ConfigTab2.RaidTimerContainer.bonusvalue:SetAutoFocus(false)
		CommDKP.ConfigTab2.RaidTimerContainer.bonusvalue:SetMultiLine(false)
		CommDKP.ConfigTab2.RaidTimerContainer.bonusvalue:SetSize(HALF, W.H)
		CommDKP.ConfigTab2.RaidTimerContainer.bonusvalue:SetMaxLetters(5)
		CommDKP.ConfigTab2.RaidTimerContainer.bonusvalue:SetNumber(tonumber(core.DB.DKPBonus.IntervalBonus))
		CommDKP.ConfigTab2.RaidTimerContainer.bonusvalue:SetScript("OnTextChanged", function(self)    -- clears focus on esc
			if tonumber(self:GetNumber()) then
				core.DB.DKPBonus.IntervalBonus = self:GetNumber();
			else
				StaticPopupDialogs["ALERT_NUMBER"] = {
					text = L["INCREMENTINVALIDWARN"],
					button1 = L["OK"],
					timeout = 0,
					whileDead = true,
					hideOnEscape = true,
					preferredIndex = 3,
				}
				StaticPopup_Show ("ALERT_NUMBER")
			end
		end)
		CommDKP.ConfigTab2.RaidTimerContainer.bonusvalue:SetScript("OnEscapePressed", function(self)    -- clears focus on esc
			self:HighlightText(0,0)
			self:ClearFocus()
		end)
		CommDKP.ConfigTab2.RaidTimerContainer.bonusvalue:SetScript("OnEnterPressed", function(self)    -- clears focus on esc
			self:HighlightText(0,0)
			self:ClearFocus()
		end)
		CommDKP.ConfigTab2.RaidTimerContainer.bonusvalue:SetScript("OnTabPressed", function(self)    -- clears focus on esc
			self:HighlightText(0,0)
			CommDKP.ConfigTab2.RaidTimerContainer.interval:SetFocus()
			CommDKP.ConfigTab2.RaidTimerContainer.interval:HighlightText()
		end)

		CommDKP.ConfigTab2.RaidTimerContainer.bonusvalue:SetScript("OnEnter", function(self)
			GameTooltip:SetOwner(self, "ANCHOR_RIGHT");
			GameTooltip:SetText(L["AWARDBONUS"], 0.25, 0.75, 0.90, 1, true);
			GameTooltip:AddLine(L["AWARDBONUSTTDESC"], 1.0, 1.0, 1.0, true);
			GameTooltip:Show();
		end)
		CommDKP.ConfigTab2.RaidTimerContainer.bonusvalue:SetScript("OnLeave", function(self)
			GameTooltip:Hide()
		end)
		W.StyleEditBox(CommDKP.ConfigTab2.RaidTimerContainer.bonusvalue, { numeric = true })

		CommDKP.ConfigTab2.RaidTimerContainer.bonusvalueHeader = W.CreateText(rBody, "label", L["BONUS"], "LEFT")
	    CommDKP.ConfigTab2.RaidTimerContainer.bonusvalueHeader:SetPoint("BOTTOMLEFT", CommDKP.ConfigTab2.RaidTimerContainer.bonusvalue, "TOPLEFT", 0, 4);
    	
    	-- Give On Time Bonus Checkbox
		CommDKP.ConfigTab2.RaidTimerContainer.StartBonus = W.CreateCheckbox(rBody, nil, L["GIVEONTIMEBONUS"]);
		CommDKP.ConfigTab2.RaidTimerContainer.StartBonus:SetChecked(core.DB.DKPBonus.GiveRaidStart)
		CommDKP.ConfigTab2.RaidTimerContainer.StartBonus:SetPoint("TOPLEFT", rBody, "TOPLEFT", W.PAD, -130);

		CommDKP.ConfigTab2.RaidTimerContainer.StartBonus:SetScript("OnClick", function(self)
			if self:GetChecked() then
				core.DB.DKPBonus.GiveRaidStart = true;
				PlaySound(808)
			else
				core.DB.DKPBonus.GiveRaidStart = false;
			end
		end)
		CommDKP.ConfigTab2.RaidTimerContainer.StartBonus:SetScript("OnEnter", function(self)
			GameTooltip:SetOwner(self, "ANCHOR_RIGHT");
			GameTooltip:SetText(L["GIVEONTIMEBONUS"], 0.25, 0.75, 0.90, 1, true);
			GameTooltip:AddLine(L["GIVEONTIMETTDESC"], 1.0, 1.0, 1.0, true);
			GameTooltip:Show();
		end)
		CommDKP.ConfigTab2.RaidTimerContainer.StartBonus:SetScript("OnLeave", function(self)
			GameTooltip:Hide()
		end)

		-- Give Raid End Bonus Checkbox
		CommDKP.ConfigTab2.RaidTimerContainer.EndRaidBonus = W.CreateCheckbox(rBody, nil, L["GIVEENDBONUS"]);
		CommDKP.ConfigTab2.RaidTimerContainer.EndRaidBonus:SetChecked(core.DB.DKPBonus.GiveRaidEnd)
		CommDKP.ConfigTab2.RaidTimerContainer.EndRaidBonus:SetPoint("TOPLEFT", rBody, "TOPLEFT", W.PAD, -154);

		CommDKP.ConfigTab2.RaidTimerContainer.EndRaidBonus:SetScript("OnClick", function(self)
			if self:GetChecked() then
				core.DB.DKPBonus.GiveRaidEnd = true;
				PlaySound(808)
			else
				core.DB.DKPBonus.GiveRaidEnd = false;
			end
		end)
		CommDKP.ConfigTab2.RaidTimerContainer.EndRaidBonus:SetScript("OnEnter", function(self)
			GameTooltip:SetOwner(self, "ANCHOR_RIGHT");
			GameTooltip:SetText(L["GIVEENDBONUS"], 0.25, 0.75, 0.90, 1, true);
			GameTooltip:AddLine(L["GIVEENDBONUSTTDESC"], 1.0, 1.0, 1.0, true);
			GameTooltip:Show();
		end)
		CommDKP.ConfigTab2.RaidTimerContainer.EndRaidBonus:SetScript("OnLeave", function(self)
			GameTooltip:Hide()
		end)

		-- Include Standby Checkbox
		CommDKP.ConfigTab2.RaidTimerContainer.StandbyInclude = W.CreateCheckbox(rBody, nil, L["INCLUDESTANDBY"]);
		CommDKP.ConfigTab2.RaidTimerContainer.StandbyInclude:SetChecked(core.DB.DKPBonus.IncStandby)
		CommDKP.ConfigTab2.RaidTimerContainer.StandbyInclude:SetPoint("TOPLEFT", rBody, "TOPLEFT", W.PAD, -178);

		CommDKP.ConfigTab2.RaidTimerContainer.StandbyInclude:SetScript("OnClick", function(self)
			if self:GetChecked() then
				core.DB.DKPBonus.IncStandby = true;
				PlaySound(808)
			else
				core.DB.DKPBonus.IncStandby = false;
			end
		end)
		CommDKP.ConfigTab2.RaidTimerContainer.StandbyInclude:SetScript("OnEnter", function(self)
			GameTooltip:SetOwner(self, "ANCHOR_RIGHT");
			GameTooltip:SetText(L["INCLUDESTANDBY"], 0.25, 0.75, 0.90, 1, true);
			GameTooltip:AddLine(L["INCLUDESTANDBYTTDESC"], 1.0, 1.0, 1.0, true);
			GameTooltip:AddLine(L["INCLUDESTANDBYTTWARN"], 1.0, 0, 0, true);
			GameTooltip:Show();
		end)
		CommDKP.ConfigTab2.RaidTimerContainer.StandbyInclude:SetScript("OnLeave", function(self)
			GameTooltip:Hide()
		end)

		-- §12.2.12 warning note (replaces the red paragraph; full TIMERWARNING text, locale string untouched)
		CommDKP.ConfigTab2.RaidTimerContainer.TimerWarning = W.CreateWarnNote(rBody, L["TIMERWARNING"])
	    CommDKP.ConfigTab2.RaidTimerContainer.TimerWarning:SetPoint("BOTTOMLEFT", rBody, "BOTTOMLEFT", W.PAD, W.PAD);
	    CommDKP.ConfigTab2.RaidTimerContainer.TimerWarning:SetPoint("BOTTOMRIGHT", rBody, "BOTTOMRIGHT", -W.PAD, W.PAD);
	    CommDKP.ConfigTab2.RaidTimerContainer.TimerWarning:SetHeight(170)       -- refit once the text has a width (OnShow)
	    CommDKP.ConfigTab2.RaidTimerContainer:HookScript("OnShow", function(self) self.TimerWarning:Fit() end)
	    RaidTimerPopout_Create()

	-- AD-20.3.2 (BR-13.3.4/13.3.5): size the Manual Adjustment card from the caption's rendered height so the
	-- Points box always clears the Adjust DKP button by >= 8 px; a taller card pushes Weekly DKP Decay down.
	local MANUAL_MIN_H, DECAY_H, PANE_H = 306, 168, 482
	local function LayoutManualCard()
		local d = CommDKP.ConfigTab2.description
		local hc = d and d.GetStringHeight and d:GetStringHeight() or 0
		if not hc or hc < 1 then hc = 96 end                 -- fonts not laid out yet: assume 8 caption lines
		local cardH = math.max(MANUAL_MIN_H, math.ceil(hc) + 204)   -- 28 chrome + 10 + hc + 10 + 114 + 8 clearance + 34 button
		manualCard:SetHeight(cardH)
		decayCard:ClearAllPoints()
		decayCard:SetPoint("TOPLEFT", CommDKP.ConfigTab2, "TOPLEFT", 0, -(cardH + W.GUT))
		CommDKP.ConfigTab2:SetHeight(math.max(PANE_H, cardH + W.GUT + DECAY_H))
	end
	CommDKP.ConfigTab2.LayoutManualCard = LayoutManualCard
	LayoutManualCard()
	CommDKP.ConfigTab2:HookScript("OnShow", LayoutManualCard)
end
