local _, core = ...;
local _G = _G;
local CommDKP = core.CommDKP;
local L = core.L;
local W = CommDKP.Widgets

local function ZeroSumDistribution()
	if IsInRaid() and core.IsOfficer then
		local curTime = time();
		local distribution, balance;
		local reason = core.DB.bossargs.CurrentRaidZone..": "..core.DB.bossargs.LastKilledBoss
		local players = "";
		local VerifyTable = {};
		local curOfficer = CommDKP:GetPlayerName()
		if not curOfficer then return end  -- AD-10.4

		if core.DB.modes.ZeroSumStandby then
			for i=1, #CommDKP:GetTable(CommDKP_Standby, true) do
				tinsert(VerifyTable, CommDKP:GetTable(CommDKP_Standby, true)[i].player)
			end
		end		

		for i=1, 40 do
			local tempName, _rank, _subgroup, _level, _class, _fileName, zone, online = GetRaidRosterInfo(i)
			local search = CommDKP:Table_Search(VerifyTable, tempName)
			local search2 = CommDKP:Table_Search(CommDKP:GetTable(CommDKP_DKPTable, true), tempName)
			local OnlineOnly = core.DB.modes.OnlineOnly
			local limitToZone = core.DB.modes.SameZoneOnly
			local isSameZone = zone == GetRealZoneText()

			if not search and search2 and (not OnlineOnly or online) and (not limitToZone or isSameZone) then
				tinsert(VerifyTable, tempName)
			end
		end

		balance = tonumber(core.ZeroSumBank.Balance:GetText())
		distribution = CommDKP_round(balance / #VerifyTable, core.DB.modes.rounding) + core.DB.modes.Inflation

		for i=1, #VerifyTable do
			local name = VerifyTable[i]
			local search = CommDKP:Table_Search(CommDKP:GetTable(CommDKP_DKPTable, true), name)

			if search then
				CommDKP:GetTable(CommDKP_DKPTable, true)[search[1][1]].dkp = CommDKP:GetTable(CommDKP_DKPTable, true)[search[1][1]].dkp + distribution
				if tonumber(distribution) and tonumber(distribution) > 0 then   -- AD-36.8.1 (BR-28.22, CM-14): DKPDistReceived's rule
					local row = CommDKP:GetTable(CommDKP_DKPTable, true)[search[1][1]]
					row.lifetime_gained = (tonumber(row.lifetime_gained) or 0) + distribution
				end
				players = players..name..","
			end
		end
		
		local newIndex = curOfficer.."-"..curTime
		tinsert(CommDKP:GetTable(CommDKP_DKPHistory, true), 1, {players=players, dkp=distribution, reason=reason, date=curTime, index=newIndex})
		if CommDKP.ConfigTab6.history then
			CommDKP:DKPHistory_Update(true)
		end

		CommDKP.Sync:SendData("CommDKPDKPDist", CommDKP:GetTable(CommDKP_DKPHistory, true)[1])
		CommDKP.Sync:SendData("CommDKPBCastMsg", L["RAIDDKPADJUSTBY"].." "..distribution.." "..L["AMONG"].." "..#VerifyTable.." "..L["PLAYERSFORREASON"]..": "..reason)
		CommDKP:Print("Raid DKP Adjusted by "..distribution.." "..L["AMONG"].." "..#VerifyTable.." "..L["PLAYERSFORREASON"]..": "..reason)
		
		table.wipe(VerifyTable)
		table.wipe(core.DB.modes.ZeroSumBank)
		core.DB.modes.ZeroSumBank.balance = 0
		core.ZeroSumBank.LootFrame.LootList:SetText("")
		CommDKP:DKPTable_Update()
		CommDKP.Sync:SendData("CommDKPZSumBank", core.DB.modes.ZeroSumBank)
		CommDKP:ZeroSumBank_Update()
		core.ZeroSumBank:Hide();
	else
		CommDKP:Print(L["NOTINRAIDPARTY"])
	end
end

function CommDKP:ZeroSumBank_Update()
	core.ZeroSumBank.Boss:SetText(core.DB.bossargs.LastKilledBoss.." in "..core.DB.bossargs.CurrentRaidZone)
	core.ZeroSumBank.Balance:SetText(core.DB.modes.ZeroSumBank.balance)

	for i=1, #core.DB.modes.ZeroSumBank do
 		if i==1 then
 			core.ZeroSumBank.LootFrame.LootList:SetText(core.DB.modes.ZeroSumBank[i].loot.." "..L["FOR"].." "..core.DB.modes.ZeroSumBank[i].cost.." "..L["DKP"].."\n")
 		else
 			core.ZeroSumBank.LootFrame.LootList:SetText(core.ZeroSumBank.LootFrame.LootList:GetText()..core.DB.modes.ZeroSumBank[i].loot.." "..L["FOR"].." "..core.DB.modes.ZeroSumBank[i].cost.." "..L["DKP"].."\n")
 		end
 	end

	-- UX §12.4.5: recompute on every update so the frame also shrinks after Distribute clears the list.
	-- Loot Banked card = header 22 + body pads 22 + list; window = title 30 + Balance card 122 + gap 8 + card + edge 12.
	local lf = core.ZeroSumBank.LootFrame
	lf:SetHeight(math.max(188, lf.LootList:GetStringHeight() + W.CARD_HDR + 22))
	core.ZeroSumBank:SetHeight(30 + 130 + lf:GetHeight() + 12)   -- -> 360 at rest
end

function CommDKP:ZeroSumBank_Create()

	local f;

	-- UX §12.4.5 / AD-16.4: "window" chrome (335 x 360, floater group "bidding"); Esc-to-close and screen clamping.
	-- Balance card + Loot Banked card, anchored to f.Content (BR-9.4.4).
	local content
	f, content = CommDKP:CreateForeverWindow("CommDKP_DKPZeroSumBankFrame", 335, 360, L["ZEROSUMBANK"], { group = "bidding" })

	if not core.DB.modes.ZeroSumBank then core.DB.modes.ZeroSumBank = 0 end

	f:SetPoint("TOP", UIParent, "TOP", 400, -50);               -- fallback only; docked on show (ToggleBidWindow)
	f:SetScript("OnDragStop", function(self) self:StopMovingOrSizing(); self.userMoved = true end)
	f.BankHeader = f.TitleLabel                                 -- alias; in-body header retired

	f.BalanceCard = W.CreateCard(content, L["BALANCE"], 311, 122)
	f.BalanceCard:SetPoint("TOPLEFT", content, "TOPLEFT", 0, 0)
	f.BalanceCard:SetPoint("TOPRIGHT", content, "TOPRIGHT", 0, 0)
	local b = f.BalanceCard.Body

	f.Boss = W.CreateText(b, "body", nil, "LEFT")
	f.Boss:SetPoint("TOPLEFT", b, "TOPLEFT", 64, -10);
	f.Boss:SetPoint("RIGHT", b, "RIGHT", -W.PAD, 0);
	if f.Boss.SetWordWrap then f.Boss:SetWordWrap(false) end

	f.Boss.Header = W.CreateText(b, "label", L["BOSS"], "LEFT")
	f.Boss.Header:SetPoint("TOPLEFT", b, "TOPLEFT", W.PAD, -11);

	f.Balance = CreateFrame("EditBox", nil, b, "BackdropTemplate")

	f.Balance:SetPoint("TOPLEFT", b, "TOPLEFT", 64, -32)
    f.Balance:SetAutoFocus(false)
    f.Balance:SetMultiLine(false)
    f.Balance:SetSize(80, W.H)
    f.Balance:SetMaxLetters(10)
    f.Balance:SetScript("OnEscapePressed", function(self)    -- clears focus on esc
      self:ClearFocus()
    end)
    f.Balance:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_RIGHT");
		GameTooltip:SetText(L["ZEROSUMBALANCE"], 0.25, 0.75, 0.90, 1, true);
		GameTooltip:AddLine(L["ZEROSUMBALANCETTDESC"], 1.0, 1.0, 1.0, true);
		GameTooltip:Show();
	end)
	f.Balance:SetScript("OnLeave", function(self)
		GameTooltip:Hide()
	end)
	W.StyleEditBox(f.Balance, { numeric = true })

	f.Balance.Header = W.CreateText(b, "label", L["BALANCE"], "LEFT")
	f.Balance.Header:SetPoint("LEFT", b, "TOPLEFT", W.PAD, -43);

	f.Distribute = CreateFrame("Button", "CommDKPBiddingDistributeButton", b, "CommunityDKPButtonTemplate")
	f.Distribute:SetPoint("TOPLEFT", b, "TOPLEFT", W.PAD, -64);
	f.Distribute:SetPoint("TOPRIGHT", b, "TOPRIGHT", -W.PAD, -64);
	f.Distribute:SetHeight(W.H);
	f.Distribute:SetText(L["DISTRIBUTEDKP"]);
	W.StyleButton(f.Distribute, "primary")
	f.Distribute:SetScript("OnClick", function (self)
		if core.DB.modes.ZeroSumBank.balance > 0 or tonumber(f.Balance:GetText()) > 0 then
			StaticPopupDialogs["CONFIRM_ADJUST1"] = {
				text = L["DISTRIBUTEALLDKPCONF"],
				button1 = L["YES"],
				button2 = L["NO"],
				OnAccept = function()
					ZeroSumDistribution()
				end,
				timeout = 0,
				whileDead = true,
				hideOnEscape = true,
				preferredIndex = 3,
			}
			CommDKP:ShowPopupOverFloaters("CONFIRM_ADJUST1", core.ZeroSumBank)
		else
			CommDKP:Print(L["NOPOINTSTODISTRIBUTE"])
		end
	end)
	f.Distribute:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_RIGHT");
		GameTooltip:SetText(L["DISTRIBUTEDKP"], 0.25, 0.75, 0.90, 1, true);
		GameTooltip:AddLine(L["DISTRUBUTEBANKED"], 1.0, 1.0, 1.0, true);
		GameTooltip:Show();
	end)
	f.Distribute:SetScript("OnLeave", function(self)
		GameTooltip:Hide()
	end)

	-- Include Standby Checkbox
	f.IncludeStandby = W.CreateCheckbox(b, nil, L["INCLUDESTANDBY"]);
	f.IncludeStandby:SetChecked(core.DB.modes.ZeroSumStandby)
	f.IncludeStandby:SetPoint("LEFT", f.Balance, "RIGHT", 12, 0);
	f.IncludeStandby:SetScript("OnClick", function(self)
		core.DB.modes.ZeroSumStandby = self:GetChecked();
		PlaySound(808)
	end)
	f.IncludeStandby:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_RIGHT");
		GameTooltip:SetText(L["INCLUDESTANDBYLIST"], 0.25, 0.75, 0.90, 1, true);
		GameTooltip:AddLine(L["INCSTANDBYLISTTTDESC"], 1.0, 1.0, 1.0, true);
		GameTooltip:AddLine(L["INCSTANDBYLISTTTWARN"], 1.0, 0, 0, true);
		GameTooltip:Show();
	end)
	f.IncludeStandby:SetScript("OnLeave", function(self)
		GameTooltip:Hide()
	end)

	-- Loot Banked card (keeps the LootFrame key and its global name; L["LOOTBANKED"] moves to the card title).
	-- Two-point width anchor; ZeroSumBank_Update sets the height.
	f.LootFrame = W.CreateCard(content, L["LOOTBANKED"], 311, 188, { name = "CommDKPZeroSumBankLootListContainer" })
	f.LootFrame:SetPoint("TOPLEFT", content, "TOPLEFT", 0, -130)
	f.LootFrame:SetPoint("TOPRIGHT", content, "TOPRIGHT", 0, -130)

	f.LootFrame.LootList = W.CreateText(f.LootFrame.Body, "body", "", "LEFT")
	f.LootFrame.LootList:SetPoint("TOPLEFT", f.LootFrame.Body, "TOPLEFT", W.PAD, -8);
	f.LootFrame.LootList:SetPoint("RIGHT", f.LootFrame.Body, "RIGHT", -W.PAD, 0);
	f.LootFrame.LootList:SetText("")

	return f
end
