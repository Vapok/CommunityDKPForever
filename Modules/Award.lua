local _, core = ...;
local _G = _G;
local CommDKP = core.CommDKP;
local L = core.L;

local LibDD = LibStub:GetLibrary("LibUIDropDownMenu-4.0");

local function SetItemPrice(cost, loot)
	-- AD-12.3: cold-cache safe; MinBids is keyed by the STRING item ID (itemKey).
	local itemName, itemLink, itemIcon, _, itemID = CommDKP:ParseItemLink(loot)
	if not itemID then return end
	local cost = cost;

	local search = CommDKP:GetTable(CommDKP_MinBids, true)[itemID];
	local newItem = {item=itemName, minbid=cost, link=itemLink, icon=itemIcon, disenchants=0, lastbid=cost, itemID = itemID}

	if not search then
		CommDKP:GetTable(CommDKP_MinBids, true)[itemID] = newItem;
	elseif search then
		CommDKP:GetTable(CommDKP_MinBids, true)[itemID].minbid = CommDKP_round(cost, core.DB.modes.rounding);
		CommDKP:GetTable(CommDKP_MinBids, true)[itemID].lastbid = CommDKP_round(cost, core.DB.modes.rounding);
		CommDKP:GetTable(CommDKP_MinBids, true)[itemID].link = itemLink;
		CommDKP:GetTable(CommDKP_MinBids, true)[itemID].icon = itemIcon;
		CommDKP:GetTable(CommDKP_MinBids, true)[itemID].item = itemName;
		CommDKP:GetTable(CommDKP_MinBids, true)[itemID].itemID = itemID;
		if cost == 0 then
			CommDKP:GetTable(CommDKP_MinBids, true)[itemID].disenchants = 0;
		end
		newItem = CommDKP:GetTable(CommDKP_MinBids, true)[itemID];
	end
	core.PriceTable = CommDKP:FormatPriceTable();
	CommDKP:PriceTable_Update(0);
	CommDKP.Sync:SendData("CommDKPSetPrice", newItem);

end

local function AwardItem(player, cost, boss, zone, loot, reassign)
	local cost = cost;
	local winner = player;
	local curTime = time();
	local curZone = zone;
	local curBoss = boss;
	local loot = loot;
	local BidsEntry = {};
	local mode = core.DB.modes.mode;
	local curOfficer = CommDKP:GetPlayerName()
	if not curOfficer then return end  -- AD-10.4
	local bids;
	local search_reassign;
	local itemName, itemLink, itemIcon = CommDKP:ParseItemLink(loot)	-- AD-12.3

	CommDKP:StatusVerify_Update()
	if core.IsOfficer then
		if core.DB.modes.costvalue == "Percent" then
			local search = CommDKP:Table_Search(CommDKP:GetTable(CommDKP_DKPTable, true), winner);

			if core.DB.modes.mode == "Roll Based Bidding" then
				if search then
					cost = CommDKP:GetTable(CommDKP_DKPTable, true)[search[1][1]].dkp * (cost / 100)
					cost = CommDKP_round(cost, core.DB.modes.rounding);
				else
					print(L["ERROR"])
				end
			else
				cost = CommDKP:GetTable(CommDKP_DKPTable, true)[search[1][1]].dkp * (cost / 100)
				cost = CommDKP_round(cost, core.DB.modes.rounding);
			end
		else
			cost = CommDKP_round(cost, core.DB.modes.rounding)
		end

		if cost > 0 then
			cost = cost * -1
		end

		if reassign then
			search_reassign = CommDKP:Table_Search(CommDKP:GetTable(CommDKP_Loot, true), reassign, "index")

			if search_reassign then
				local deleted = CopyTable(CommDKP:GetTable(CommDKP_Loot, true)[search_reassign[1][1]])
				local reimburse = CommDKP:Table_Search(CommDKP:GetTable(CommDKP_DKPTable, true), deleted.player, "player")
				local newIndex = curOfficer.."-"..curTime-2
				deleted.cost = deleted.cost * -1
				deleted.deletes = reassign
				deleted.index = newIndex
				deleted.date = curTime-2
				if deleted.bids then
					bids = CopyTable(deleted.bids);
					deleted.bids = nil;
				end
				CommDKP:GetTable(CommDKP_Loot, true)[search_reassign[1][1]].deletedby = newIndex
				CommDKP:GetTable(CommDKP_DKPTable, true)[reimburse[1][1]].dkp = CommDKP:GetTable(CommDKP_DKPTable, true)[reimburse[1][1]].dkp + deleted.cost
				CommDKP:GetTable(CommDKP_DKPTable, true)[reimburse[1][1]].lifetime_spent = CommDKP:GetTable(CommDKP_DKPTable, true)[reimburse[1][1]].lifetime_spent + deleted.cost
				table.insert(CommDKP:GetTable(CommDKP_Loot, true), 1, deleted)
				CommDKP.Sync:SendData("CommDKPDelLoot", CommDKP:GetTable(CommDKP_Loot, true)[1])
			end
		end

		if core.DB.modes.StoreBids and not reassign then
			local Bids_Submitted = CommDKP:BidsSubmitted_Get();
			local newIndex = curOfficer.."-"..curTime

			for i=1, #Bids_Submitted do
				if Bids_Submitted[i].bid then
					BidsEntry[Bids_Submitted[i].player] = Bids_Submitted[i].bid;
				elseif Bids_Submitted[i].dkp then
					BidsEntry[Bids_Submitted[i].player] = Bids_Submitted[i].dkp;
				elseif Bids_Submitted[i].roll then
					BidsEntry[Bids_Submitted[i].player] = Bids_Submitted[i].roll..Bids_Submitted[i].range;
				end
			end
			if Bids_Submitted[1] then
				if Bids_Submitted[1].bid then
					tinsert(CommDKP:GetTable(CommDKP_Loot, true), 1, {player=winner, loot=loot, zone=curZone, date=curTime, boss=curBoss, cost=cost, index=newIndex, bids={ }})
					for k,v in pairs(BidsEntry) do
						table.insert(CommDKP:GetTable(CommDKP_Loot, true)[1].bids, {bidder=k, bid=v});
					end
				elseif Bids_Submitted[1].dkp then
					tinsert(CommDKP:GetTable(CommDKP_Loot, true), 1, {player=winner, loot=loot, zone=curZone, date=curTime, boss=curBoss, cost=cost, index=newIndex, dkp={ }})
					for k,v in pairs(BidsEntry) do
						table.insert(CommDKP:GetTable(CommDKP_Loot, true)[1].dkp, {bidder=k, dkp=v});
					end
				elseif Bids_Submitted[1].roll then
					tinsert(CommDKP:GetTable(CommDKP_Loot, true), 1, {player=winner, loot=loot, zone=curZone, date=curTime, boss=curBoss, cost=cost, index=newIndex, rolls={ }})
					for k,v in pairs(BidsEntry) do
						table.insert(CommDKP:GetTable(CommDKP_Loot, true)[1].rolls, {bidder=k, roll=v});
					end
				end
			else
				tinsert(CommDKP:GetTable(CommDKP_Loot, true), 1, {player=winner, loot=loot, zone=curZone, date=curTime, boss=curBoss, cost=cost, index=newIndex})
			end
		else
			local newIndex = curOfficer.."-"..curTime
			tinsert(CommDKP:GetTable(CommDKP_Loot, true), 1, {player=winner, loot=loot, zone=curZone, date=curTime, boss=curBoss, cost=cost, index=newIndex})
			if reassign then
				local search = CommDKP:Table_Search(CommDKP:GetTable(CommDKP_Loot, true), reassign, "index")

				if search and CommDKP:GetTable(CommDKP_Loot, true)[search[1][1]].player ~= winner then
					CommDKP:GetTable(CommDKP_Loot, true)[1].reassigned = true
				end
			end 
			if type(bids) == "table" then
				CommDKP:GetTable(CommDKP_Loot, true)[1].bids = bids
			end
		end
		CommDKP:BidsSubmitted_Clear()
		CommDKP.Sync:SendData("CommDKPLootDist", CommDKP:GetTable(CommDKP_Loot, true)[1])
		CommDKP:DKPTable_Set(winner, "dkp", CommDKP_round(cost, core.DB.modes.rounding), true)
		CommDKP:LootHistory_Reset();
		CommDKP:LootHistory_Update(L["NOFILTER"])

		if core.BiddingWindow and core.BiddingWindow:IsShown() then  -- runs below if award is through bidding window (update minbids and zerosum bank)
			CommDKP:ResetBidToggle()	-- CDKP-006 (AD-5.3): resets Bidding.lua's own toggle; never rebinds OnClick

			core.BidInProgress = false;
			CommDKP:BroadcastStopBidTimer()
			
			local _, _, _, _, itemID = CommDKP:ParseItemLink(loot)	-- AD-13.4: string itemKey, cold-cache safe
		
			local search = CommDKP:GetTable(CommDKP_MinBids, true)[itemID]
			local minBidAmount = CommDKP_round(CommDKP:GetMinBid(loot), core.DB.modes.rounding);
			local lastBidAmount = CommDKP_round(core.BiddingWindow.cost:GetNumber(), core.DB.modes.rounding);

			if mode == "Static Item Values" or mode == "Roll Based Bidding" or (mode == "Zero Sum" and core.DB.modes.ZeroSumBidType == "Static") then
				if core.BiddingWindow.CustomMinBid:GetChecked() == false then
					minBidAmount = CommDKP_round(minBidAmount, core.DB.modes.rounding);
				else
					if core.BiddingWindow.cost:GetNumber() ~= tonumber(minBidAmount) then
						minBidAmount = CommDKP_round(core.BiddingWindow.cost:GetNumber(), core.DB.modes.rounding);
					end
				end
			else
				if core.BiddingWindow.CustomMinBid:GetChecked() == true then
					minBidAmount = CommDKP_round(core.BiddingWindow.minBid:GetNumber(), core.DB.modes.rounding);
				end
			end

			--set table here
			local minBidEntry = {item=itemName, minbid=minBidAmount, link=itemLink, icon=itemIcon, lastbid=lastBidAmount, itemID=itemID};

			if not search then
				--not found
				CommDKP:GetTable(CommDKP_MinBids, true)[itemID] = minBidEntry;
				if mode == "Static Item Values" or mode == "Roll Based Bidding" or (mode == "Zero Sum" and core.DB.modes.ZeroSumBidType == "Static") then
					core.BiddingWindow.CustomMinBid:SetShown(true);
					core.BiddingWindow.CustomMinBid:SetChecked(core.DB.defaults.CustomMinBid);
				end
				CommDKP.Sync:SendData("CommDKPSetPrice", minBidEntry);
			else
				--found
				if CommDKP:GetTable(CommDKP_MinBids, true)[itemID].minbid ~= minBidAmount then
					if mode == "Static Item Values" or mode == "Roll Based Bidding" or (mode == "Zero Sum" and core.DB.modes.ZeroSumBidType == "Static") then
						core.BiddingWindow.CustomMinBid:SetShown(true);
						core.BiddingWindow.CustomMinBid:SetChecked(core.DB.defaults.CustomMinBid);
					end
				end

				CommDKP:GetTable(CommDKP_MinBids, true)[itemID].minbid = minBidEntry.minbid;
				CommDKP:GetTable(CommDKP_MinBids, true)[itemID].lastbid = minBidEntry.lastbid;
				CommDKP:GetTable(CommDKP_MinBids, true)[itemID].link = minBidEntry.link;
				CommDKP:GetTable(CommDKP_MinBids, true)[itemID].icon = minBidEntry.icon;
				CommDKP:GetTable(CommDKP_MinBids, true)[itemID].item = minBidEntry.item;
				CommDKP:GetTable(CommDKP_MinBids, true)[itemID].itemID = minBidEntry.itemID;

				CommDKP.Sync:SendData("CommDKPSetPrice", CommDKP:GetTable(CommDKP_MinBids, true)[itemID]);
			end
			
			core.PriceTable = CommDKP:FormatPriceTable();
			CommDKP:PriceTable_Update(0);

			if mode == "Zero Sum" and not reassign then
				core.DB.modes.ZeroSumBank.balance = core.DB.modes.ZeroSumBank.balance + -tonumber(cost)
				table.insert(core.DB.modes.ZeroSumBank, { loot = loot, cost = -tonumber(cost) })
				CommDKP:ZeroSumBank_Update()
				CommDKP.Sync:SendData("CommDKPZSumBank", core.DB.modes.ZeroSumBank)
			end
			core.BiddingWindow:Hide()
			CommDKP:ClearBidWindow()
		end

		-- moved this outside of above if to always display even if manual award
		CommDKP:SendChat(L["CONGRATS"].." "..winner.." "..L["ON"].." "..loot.." @ "..-cost.." "..L["DKP"], "RAID_WARNING")
		if core.DB.modes.AnnounceAward then
			CommDKP:SendChat(L["CONGRATS"].." "..winner.." "..L["ON"].." "..loot.." @ "..-cost.." "..L["DKP"], "GUILD")
		end

		if core.DB.defaults.AutoAwardLoot then
			local numLootItems = GetNumLootItems()
			if numLootItems > 0 then
				local lootIndex = nil
				for i = 1, numLootItems do
					local lootLink = GetLootSlotLink(i)
					if lootIndex == nil and lootLink ~= nil and lootLink == loot then
						lootIndex = i
					end
				end

				local candidateIndex = nil
				local maxGroupMembers = MAX_RAID_MEMBERS
				if not IsInRaid() then maxGroupMembers = MAX_PARTY_MEMBERS end
				for i = 1, maxGroupMembers do
					local candidate = GetMasterLootCandidate(lootIndex, i)
					if candidateIndex == nil and candidate ~= nil and candidate == winner then
						candidateIndex = i
					end
				end

				if lootIndex ~= nil and candidateIndex ~= nil then
					GiveMasterLoot(lootIndex, candidateIndex)
				end
			else
				if core.DB.pendingLoot == nil then
					core.DB.pendingLoot = {}
				end
				if core.DB.pendingLoot[winner] == nil then
					core.DB.pendingLoot[winner] = {}
				end
				tinsert(core.DB.pendingLoot[winner], loot)
				InitiateTrade(winner)
			end
		end

	end
end

local function AwardConfirm_Create()

	local f;

	-- UX §10.4: native template window (modal floater, returns focus on hide); now movable, clamped, Esc = Cancel.
	f = CommDKP:CreateForeverWindow("CommDKP_AwardWindowConfirm", 400, 270,
		"CommunityDKP Forever \226\128\148 " .. L["CONFAWARD"])
	f:SetPoint("TOP", UIParent, "TOP", 0, -200);
	f.confirmHeader = f.TitleLabel          -- alias: the in-body header is retired; any :SetText() still works
	if f.CloseButton then f.CloseButton:HookScript("OnClick", function() PlaySound(851) end) end   -- same sound as noButton

	----------------------------------
	-- Team row
	----------------------------------

		f.teamHeader = f:CreateFontString(nil, "OVERLAY")
		f.teamHeader:SetFontObject("CommDKPLargeRight");
		f.teamHeader:SetScale(0.7)
		f.teamHeader:SetPoint("TOPLEFT", f, "TOPLEFT", 120, -60);
		f.teamHeader:SetText(L["TEAM"]..":")

		f.team = LibDD:Create_UIDropDownMenu("CommDKPAwardConfirmTeamDropDown", f);
		f.team:SetPoint("LEFT", f.teamHeader, "RIGHT", -15, 0)
		LibDD:UIDropDownMenu_SetWidth(f.team, 150)
		LibDD:UIDropDownMenu_JustifyText(f.team, "LEFT")

	----------------------------------
	-- Player row
	----------------------------------	

		f.playerHeader = f:CreateFontString(nil, "OVERLAY")
		f.playerHeader:SetFontObject("CommDKPLargeRight");
		f.playerHeader:SetScale(0.7)
		f.playerHeader:SetPoint("TOPRIGHT", f.teamHeader, "BOTTOMRIGHT", 0, -10);
		f.playerHeader:SetText(L["PLAYER"]..":")

		f.player = LibDD:Create_UIDropDownMenu("CommDKPAwardConfirmPlayerDropDown", f);
		f.player:SetPoint("LEFT", f.playerHeader, "RIGHT", -15, 0)
		LibDD:UIDropDownMenu_SetWidth(f.player, 150)
		LibDD:UIDropDownMenu_JustifyText(f.player, "LEFT")

	----------------------------------
	-- Item row
	----------------------------------	

		f.lootHeader = f:CreateFontString(nil, "OVERLAY")
		f.lootHeader:SetFontObject("CommDKPLargeRight");
		f.lootHeader:SetScale(0.7)
		f.lootHeader:SetPoint("TOPRIGHT", f.playerHeader, "BOTTOMRIGHT", 0, -10);
		f.lootHeader:SetText(L["ITEM"]..":")

		f.lootIcon = f:CreateTexture(nil, "OVERLAY", nil);
		f.lootIcon:SetPoint("LEFT", f.lootHeader, "RIGHT", 5, 0);
		f.lootIcon:SetColorTexture(0, 0, 0, 1)
		f.lootIcon:SetSize(20, 20);

		f.loot = f:CreateFontString(nil, "OVERLAY")
		f.loot:SetFontObject("CommDKPNormalLeft");
		f.loot:SetPoint("LEFT", f.lootIcon, "RIGHT", 5, 1);
		f.loot:SetSize(200, 28);

	----------------------------------
	-- Cost row
	----------------------------------

		f.costHeader = f:CreateFontString(nil, "OVERLAY")
		f.costHeader:SetFontObject("CommDKPLargeRight");
		f.costHeader:SetScale(0.7)
		f.costHeader:SetPoint("TOPRIGHT", f.lootHeader, "BOTTOMRIGHT", 0, -10);
		f.costHeader:SetText(L["ITEMCOST"]..":")

		f.cost = CreateFrame("EditBox", nil, f, "BackdropTemplate")
		
		f.cost:SetAutoFocus(false)
		f.cost:SetMultiLine(false)
		f.cost:SetPoint("LEFT", f.costHeader, "RIGHT", 5, 0)
		f.cost:SetSize(50, 22)
		CommDKP:ApplyBackdrop(f.cost, "SolidEdge", "InputBg", "InputBorderAccent")
		f.cost:SetMaxLetters(10)
		f.cost:SetTextColor(1, 1, 1, 1)
		f.cost:SetFontObject("CommDKPSmallRight")
		f.cost:SetTextInsets(10,10,0,0)
		f.cost:SetScript("OnEscapePressed", function(self)    -- clears focus on esc
			self:ClearFocus()
		end)
		f.cost:SetScript("OnTabPressed", function(self)    -- clears focus on tab
			self:ClearFocus()
		end)
		f.cost:SetScript("OnEnterPressed", function(self)    -- clears focus on enter
			self:ClearFocus()
		end)

		f.costFooter = f:CreateFontString(nil, "OVERLAY")
		f.costFooter:SetFontObject("CommDKPNormalLeft");
		f.costFooter:SetPoint("LEFT", f.cost, "RIGHT", 5, 0);
		f.costFooter:SetSize(200, 28);

	----------------------------------
	-- Boss row
	----------------------------------

		f.bossHeader = f:CreateFontString(nil, "OVERLAY")
		f.bossHeader:SetFontObject("CommDKPLargeRight");
		f.bossHeader:SetScale(0.7)
		f.bossHeader:SetPoint("TOPRIGHT", f.costHeader, "BOTTOMRIGHT", 0, -10);
		f.bossHeader:SetText(L["BOSS"]..":")

		f.bossDropDown = LibDD:Create_UIDropDownMenu("CommDKPAwardConfirmBossDropDown", f);
		f.bossDropDown:SetPoint("LEFT", f.bossHeader, "RIGHT", -15, -2)
		LibDD:UIDropDownMenu_SetWidth(f.bossDropDown, 150)
		LibDD:UIDropDownMenu_JustifyText(f.bossDropDown, "LEFT")

	----------------------------------
	-- Zone row
	----------------------------------

		f.zoneHeader = f:CreateFontString(nil, "OVERLAY")
		f.zoneHeader:SetFontObject("CommDKPLargeRight");
		f.zoneHeader:SetScale(0.7)
		f.zoneHeader:SetPoint("TOPRIGHT", f.bossHeader, "BOTTOMRIGHT", 0, -10);
		f.zoneHeader:SetText(L["ZONE"]..":")

		f.zoneDropDown = LibDD:Create_UIDropDownMenu("CommDKPAwardConfirmZoneDropDown", f);
		f.zoneDropDown:SetPoint("LEFT", f.zoneHeader, "RIGHT", -15, -2)
		LibDD:UIDropDownMenu_SetWidth(f.zoneDropDown, 150)
		LibDD:UIDropDownMenu_JustifyText(f.zoneDropDown, "LEFT")

	----------------------------------
	-- Buttons
	----------------------------------

		f.yesButton = CommDKP:CreateButton("BOTTOMLEFT", f, "BOTTOMLEFT", 20, 15, L["CONFIRM"]);
		f.setPriceButton = CommDKP:CreateButton("BOTTOMLEFT", f, "BOTTOMLEFT", 150, 15, "Set Price");
		f.setPriceButton:SetShown(false);
		f.noButton = CommDKP:CreateButton("BOTTOMRIGHT", f, "BOTTOMRIGHT", -20, 15, L["CANCEL"]);

	return f;
end


-- this also populates all the drop downs
function CommDKP:AwardConfirm(player, cost, boss, zone, loot, reassign)
	local _, itemLink, itemIcon = CommDKP:ParseItemLink(loot)	-- AD-12.3
	local curBoss, curZone, player, cost = boss, zone, player, cost
	local class, search;
	local PlayerList = {};
	local mode = core.DB.modes.mode;
	
	
	if player then
		search = CommDKP:Table_Search(CommDKP:GetTable(CommDKP_DKPTable, true), player)
		class = CommDKP:GetCColors(CommDKP:GetTable(CommDKP_DKPTable, true)[search[1][1]].class)
	end

	for i=1, #CommDKP:GetTable(CommDKP_DKPTable, true) do
		table.insert(PlayerList, CommDKP:GetTable(CommDKP_DKPTable, true)[i].player)
	end
	table.sort(PlayerList, function(a, b)
		return a < b
	end)

	PlaySound(850)
	core.AwardConfirm = core.AwardConfirm or AwardConfirm_Create()
	core.AwardConfirm:SetShown(true)	-- AD-11.6 ruling 3: a second click re-fills the dropdowns and keeps the window open

	if mode == "Static Item Values" or mode == "Roll Based Bidding" or (mode == "Zero Sum" and core.DB.modes.ZeroSumBidType == "Static") then
		core.AwardConfirm.setPriceButton:SetShown(true);
	end

	--core.AwardConfirm.player:SetText("|c"..class.hex..player.."|r")
	core.AwardConfirm.lootIcon:SetTexture(itemIcon)
	core.AwardConfirm.loot:SetText(loot)
	core.AwardConfirm.cost:SetNumber(cost)
	core.AwardConfirm.cost:SetScript("OnKeyUp", function(self)
		cost = self:GetNumber();
	end)
	core.AwardConfirm.costFooter:SetText("DKP")
	--core.AwardConfirm.boss:SetText(boss.." in "..zone)

	-----
	-- team drop down initialization
	-----

	core.AwardConfirm.team:SetScript("OnEnter", 
		function(self) 
			GameTooltip:SetOwner(self, "ANCHOR_RIGHT");
			GameTooltip:SetText(L["TEAMCURRENTLIST"], 0.25, 0.75, 0.90, 1, true);
			GameTooltip:AddLine(L["WARNING"], 1.0, 0, 0, true);
			GameTooltip:AddLine(L["TEAMCURRENTLISTDESC3"], 1.0, 1.0, 1.0, true);
			GameTooltip:Show();
		end
	)
	core.AwardConfirm.team:SetScript("OnLeave",
		function(self)
			GameTooltip:Hide()
		end
	)

	-- Create and bind the initialization function to the dropdown menu
		LibDD:UIDropDownMenu_Initialize(core.AwardConfirm.team, 
			function(self, level, menuList)
				
				local dropDownMenuItem = LibDD:UIDropDownMenu_CreateInfo()
				dropDownMenuItem.func = self.SetValue
				dropDownMenuItem.fontObject = "CommDKPSmallCenter"
			
				teamList = CommDKP:GetGuildTeamList()

				for i=1, #teamList do
					dropDownMenuItem.disabled = true
					dropDownMenuItem.text = teamList[i][2]
					dropDownMenuItem.arg1 = teamList[i][2] -- name
					dropDownMenuItem.arg2 = teamList[i][1] -- index
					dropDownMenuItem.checked = teamList[i][1] == tonumber(CommDKP:GetCurrentTeamIndex())
					dropDownMenuItem.isNotRadio = true
					LibDD:UIDropDownMenu_AddButton(dropDownMenuItem)
				end
			end
		)
		-- Show which team is currently the current one
		LibDD:UIDropDownMenu_SetText(core.AwardConfirm.team, CommDKP:GetCurrentTeamName())
	
	if player then
		LibDD:UIDropDownMenu_SetText(core.AwardConfirm.player, "|c"..class.hex..player.."|r")
	else
		LibDD:UIDropDownMenu_SetText(core.AwardConfirm.player, "")
	end

	-- AD-12.6: flat list for small rosters, range submenus (with a correct checkmark) above FLAT_MAX.
	local FLAT_MAX = 25
	local function PlayerColorHex(name)
		local classSearch = CommDKP:Table_Search(CommDKP:GetTable(CommDKP_DKPTable, true), name)
		if classSearch then
			return CommDKP:GetCColors(CommDKP:GetTable(CommDKP_DKPTable, true)[classSearch[1][1]].class).hex
		end
		return "ff444444"
	end

	LibDD:UIDropDownMenu_Initialize(core.AwardConfirm.player, function(self, level, menuList)
		local filterName = LibDD:UIDropDownMenu_CreateInfo()
		filterName.func = self.SetValue

		if #PlayerList <= FLAT_MAX then
			if (level or 1) == 1 then
				for i = 1, #PlayerList do
					local name = PlayerList[i]
					local colored = "|c"..PlayerColorHex(name)..name.."|r"
					filterName.text, filterName.arg1, filterName.arg2, filterName.checked, filterName.isNotRadio = colored, name, colored, name == player, true
					LibDD:UIDropDownMenu_AddButton(filterName)
				end
			end
			return
		end

		local ranges = {1}
		while ranges[#ranges] < #PlayerList do
			table.insert(ranges, ranges[#ranges]+20)
		end

		if (level or 1) == 1 then
			local numSubs = ceil(#PlayerList/20)
			for i=1, numSubs do
				local min, max = (i*20)-19, i*20
				if max > #PlayerList then max = #PlayerList end
				local inRange = false
				for j = min, max do
					if PlayerList[j] == player then inRange = true; break end
				end
				filterName.text, filterName.checked, filterName.menuList, filterName.hasArrow = strsub(PlayerList[min], 1, 1).."-"..strsub(PlayerList[max], 1, 1), inRange, i, true
				LibDD:UIDropDownMenu_AddButton(filterName)
			end
		else
			for i=ranges[menuList], ranges[menuList]+19 do
				if PlayerList[i] then
					local colored = "|c"..PlayerColorHex(PlayerList[i])..PlayerList[i].."|r"
					filterName.text, filterName.arg1, filterName.arg2, filterName.checked, filterName.isNotRadio = colored, PlayerList[i], colored, PlayerList[i] == player, true
					LibDD:UIDropDownMenu_AddButton(filterName, level)
				end
			end
		end
	end)

	-- AD-12.5: ZONE and BOSS dropdowns driven by the static catalog + discovered encounters.
	local function SetBossText()  LibDD:UIDropDownMenu_SetText(core.AwardConfirm.bossDropDown, curBoss or "") end
	local function SetZoneText()  LibDD:UIDropDownMenu_SetText(core.AwardConfirm.zoneDropDown, curZone or "") end
	SetBossText(); SetZoneText()

	-- BOSS: level 1 = bosses of curZone, then recent kills, then an "All Raids" section whose zones open level 2.
	LibDD:UIDropDownMenu_Initialize(core.AwardConfirm.bossDropDown, function(self, level, menuList)
		local info = LibDD:UIDropDownMenu_CreateInfo()
		info.func, info.isNotRadio = self.SetValue, true
		if (level or 1) == 1 then
			local names, seen = CommDKP:GetZoneBossNames(curZone)
			-- An ad-hoc/custom curBoss not in this zone's catalog stays visible (and checked) at the top.
			if curBoss and curBoss ~= "" and not seen[curBoss] then
				seen[curBoss] = true
				info.text, info.arg1, info.arg2, info.checked = curBoss, curBoss, nil, true
				LibDD:UIDropDownMenu_AddButton(info)
			end
			for _, n in ipairs(names) do
				info.text, info.arg1, info.arg2, info.checked = n, n, nil, n == curBoss
				LibDD:UIDropDownMenu_AddButton(info)
			end
			-- "Recent Kills" comes ONLY from actual recorded kills (BOSS_KILL / ENCOUNTER_END success).
			-- core.LastKilledBoss is NOT used: it defaults to "Lucifron" and tracks Adjust-tab selections.
			local recent = {}
			for _, n in ipairs(core.LastKilledNPC or {}) do
				if type(n) == "string" and n ~= "" and not seen[n] then recent[#recent + 1] = n; seen[n] = true end
			end
			if #recent > 0 then
				local t = LibDD:UIDropDownMenu_CreateInfo()
				t.text, t.isTitle, t.notCheckable = L["RECENTKILLS"] or "Recent Kills", true, true
				LibDD:UIDropDownMenu_AddButton(t)
				for _, n in ipairs(recent) do
					info.text, info.arg1, info.arg2, info.checked = n, n, nil, n == curBoss
					LibDD:UIDropDownMenu_AddButton(info)
				end
			end
			local t = LibDD:UIDropDownMenu_CreateInfo()
			t.text, t.isTitle, t.notCheckable = L["ALLRAIDS"] or "All Raids", true, true
			LibDD:UIDropDownMenu_AddButton(t)
			for _, z in ipairs(CommDKP:GetAwardZoneNames()) do
				local sub = LibDD:UIDropDownMenu_CreateInfo()    -- fresh table: no func, so a click on the zone row only opens it
				sub.text, sub.hasArrow, sub.menuList, sub.notCheckable = z, true, z, true
				LibDD:UIDropDownMenu_AddButton(sub)
			end
		else
			for _, n in ipairs(CommDKP:GetZoneBossNames(menuList)) do      -- menuList is the zone name
				info.text, info.arg1, info.arg2, info.checked = n, n, menuList, (n == curBoss and menuList == curZone)
				LibDD:UIDropDownMenu_AddButton(info, level)
			end
		end
	end)

	-- ZONE: flat list of every zone.
	LibDD:UIDropDownMenu_Initialize(core.AwardConfirm.zoneDropDown, function(self, level, menuList)
		local info = LibDD:UIDropDownMenu_CreateInfo()
		info.func, info.isNotRadio = self.SetValue, true
		local extra = { curZone, core.CurrentRaidZone }
		for _, z in pairs(core.RecentZones or {}) do extra[#extra + 1] = z end
		for _, z in ipairs(CommDKP:GetAwardZoneNames(extra)) do
			info.text, info.arg1, info.checked = z, z, z == curZone
			LibDD:UIDropDownMenu_AddButton(info)
		end
	end)

	function core.AwardConfirm.player:SetValue(newValue, arg2) 	---- PLAYER dropdown function
		if player ~= newValue then player = newValue end
		LibDD:UIDropDownMenu_SetText(core.AwardConfirm.player, arg2)
		LibDD:CloseDropDownMenus()
	end

	-- arg2 = zone when the boss was picked from an "All Raids" submenu; otherwise the zone is unchanged.
	-- AD-11.4: SetValue must not use self (buttons call it with the button as self).
	function core.AwardConfirm.bossDropDown:SetValue(newValue, zone)
		curBoss = newValue
		if zone and zone ~= curZone then curZone = zone; SetZoneText() end
		SetBossText(); LibDD:CloseDropDownMenus()
	end

	function core.AwardConfirm.zoneDropDown:SetValue(newValue)
		curZone = newValue
		local names, seen = CommDKP:GetZoneBossNames(newValue)
		if #names > 0 and not (curBoss and seen[curBoss]) then curBoss = names[1]; SetBossText() end
		SetZoneText(); LibDD:CloseDropDownMenus()
	end

	core.AwardConfirm.yesButton:SetScript("OnClick", function()         -- Run when "Yes" is clicked
		if not player then
			StaticPopupDialogs["AWARD_VALIDATE"] = {
				text = L["PLAYERVALIDATE"],
				button1 = L["OK"],
				timeout = 0,
				whileDead = true,
				hideOnEscape = true,
				preferredIndex = 3,
			}
			CommDKP:ShowPopupOverFloaters("AWARD_VALIDATE", core.AwardConfirm)
		else
			if reassign then
				AwardItem(player, cost, curBoss, curZone, loot, reassign)
			else
				AwardItem(player, cost, curBoss, curZone, loot)
			end
			core.AwardConfirm:SetShown(false)
		end

		PlaySound(851)
	end)
	core.AwardConfirm.noButton:SetScript("OnClick", function()          -- Run when "No" is clicked
		PlaySound(851)
		core.AwardConfirm:SetShown(false)
	end)
	core.AwardConfirm.setPriceButton:SetScript("OnClick", function()          -- Run when "Set Price" is clicked
		SetItemPrice(cost, loot)
		PlaySound(851)
		core.AwardConfirm:SetShown(false)
	end)
end
