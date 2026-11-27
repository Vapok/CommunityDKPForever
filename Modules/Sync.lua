local _, core = ...;
local _G = _G;
local CommDKP = core.CommDKP;
local L = core.L;

local bytesSent = 0
local bytesTotal = 0
local LibAceSerializer = LibStub:GetLibrary("AceSerializer-3.0")
local LibDeflate = LibStub:GetLibrary("LibDeflate")
local DD = CommDKP.DD                     -- AD-16.3: selector protocol (CommDKPBroadcastPlayerDropDown)
local W = CommDKP.Widgets

function CommDKP_Profile_Create(player, dkp, gained, spent, teamIndex)
	local _teamIndex = teamIndex or core.DB.defaults.CurrentTeam;
	local tempName, tempClass
	local guildSize = GetNumGuildMembers();
	local class = "NONE"
	local dkp = dkp or 0
	local gained = gained or 0
	local spent = spent or 0
	local created = false
	player = CommDKP:NormalizeName(player) or player		-- AD-15.2(c): every inserted row stores the canonical name

	for i=1, (guildSize or 0) do
		tempName,_,_,_,_,_,_,_,_,_,tempClass = GetGuildRosterInfo(i)
		tempName = CommDKP:StripRealm(tempName)			-- AD-9.6: realm suffix optional; nil entries skipped
		if tempName and CommDKP:SamePlayer(tempName, player) then
			class = tempClass
			local row = { player=player, lifetime_spent=spent, lifetime_gained=gained, class=class, dkp=dkp, rank=10, spec=L["NOSPECREPORTED"], role=L["NOROLEDETECTED"], rankName="None", previous_dkp=0, version="Unknown", }
			CommDKP:HydratePlayerRow(row)					-- AD-26.4.2 P5: heal from known meta (BR-18.3)
			table.insert(CommDKP:GetTable(CommDKP_DKPTable, true, _teamIndex), row)

			CommDKP:FilterDKPTable(core.currentSort, "reset")
			CommDKP:ClassGraph_Update()
			created = true
			break
		end
	end

	if not created and (IsInRaid() or IsInGroup()) then 	-- if player not found in guild, checks raid/party
		-- AD-15.2(c): raid via GetRaidRosterInfo; party via party1..N (First+Last rule), names realm-stripped.
		local inRaid = IsInRaid()
		local count = inRaid and (GetNumGroupMembers() or 0) or (GetNumSubgroupMembers() or 0)

		for i=1, count do
			if inRaid then
				tempName,_,_,_,_,tempClass = GetRaidRosterInfo(i)
			else
				tempName = CommDKP:GetUnitFullName("party"..i)
				tempClass = tempName and select(2, UnitClass("party"..i)) or nil
			end
			tempName = CommDKP:StripRealm(tempName)
			if tempName and CommDKP:SamePlayer(tempName, player) then
				if not CommDKP:Table_Search(CommDKP:GetTable(CommDKP_DKPTable, true, _teamIndex), player, "player") then
					local row = { player=player, class=tempClass, dkp=dkp, previous_dkp=0, lifetime_gained=gained, lifetime_spent=spent, rank=10, rankName="None", spec=L["NOSPECREPORTED"], role=L["NOROLEDETECTED"], version="Unknown", }
					CommDKP:HydratePlayerRow(row)			-- AD-26.4.2 P5
					tinsert(CommDKP:GetTable(CommDKP_DKPTable, true, _teamIndex), row)
					CommDKP:FilterDKPTable(core.currentSort, "reset")
					CommDKP:ClassGraph_Update()
					created = true
					break
				end
			end
		end
	end

	if not created then
		local row = { player=player, class=class, dkp=dkp, previous_dkp=0, lifetime_gained=gained, lifetime_spent=spent, rank=10, rankName="None", spec=L["NOSPECREPORTED"], role=L["NOROLEDETECTED"], version="Unknown", }
		CommDKP:HydratePlayerRow(row)						-- AD-26.4.2 P5
		tinsert(CommDKP:GetTable(CommDKP_DKPTable, true, _teamIndex), row)
	end

	return created
end

local function CommDKP_BroadcastFull_Status_Create()
	-- UX §12.4.9 / AD-16.4: "plaque" toast (300 x 92), no close button, pinned at FULLSCREEN_DIALOG (not a floater,
	-- no Esc binding). Interior anchors to f.Content only (BR-9.4.4 style flip).
	local f, content = CommDKP:CreateForeverWindow("CommDKP_FullBroadcastStatus", 300, 92,
		L["BCASTINGTABLES"], { style = "plaque", floater = false, escape = false, noClose = true })
	f:SetPoint("TOP", UIParent, "TOP", 0, -10);
	f:SetFrameStrata("FULLSCREEN_DIALOG")    -- pinned; never cycled by FocusWindow
	f.bcastHeader = f.TitleLabel             -- §12.4.9: the duplicate body header is removed; SetText writes the title

	-- §12.2.12 progress bar (18 px, full width) with the percentage inside it. f.status / f.status.percentage keep
	-- their keys (SetMinMaxValues / SetStatusBarColor / OnUpdate / SetValue / percentage:SetText are unchanged).
	f.status = W.CreateProgressBar(content, 284, 18)
	f.status.Holder:SetPoint("TOPLEFT", content, "TOPLEFT", 0, -20)
	f.status.Holder:SetPoint("TOPRIGHT", content, "TOPRIGHT", 0, -20)
	f.status.percentage = f.status.Text
	return f
end

local function CommDKP_BroadcastFull_Status()
	core.BroadcastProgress = core.BroadcastProgress or CommDKP_BroadcastFull_Status_Create()
	core.BroadcastProgress:SetShown(not core.BroadcastProgress:IsShown())

	core.BroadcastProgress.status:Show()
	core.BroadcastProgress.bcastHeader:SetText(L["BCASTINGTABLES"])

	core.BroadcastProgress.status:SetMinMaxValues(0, 100)
	core.BroadcastProgress.status:SetStatusBarColor(0, 0.3, 1)
	core.BroadcastProgress.status:SetScript("OnUpdate", function(self)
		local val

		if bytesSent < bytesTotal then
			val = (bytesSent / bytesTotal) * 100
		else
			val = 100
		end

		self:SetValue(val)
		core.BroadcastProgress.status.percentage:SetText(CommDKP_round(val, 0).."%")

		if bytesSent == bytesTotal then
			self:SetValue(100)
			self:SetScript("OnUpdate", nil)
			C_Timer.After(2, function()
				core.BroadcastProgress:Hide()
			end)
		end
	end)
end

function CommDKP_BroadcastFull_Init()
	local PlayerList = {}
	local player

	C_GuildInfo.GuildRoster()  -- requests new guild roster data for dropdown
	for j=1, GetNumGuildMembers() do
		tempName,_,_,_,_,_,_,_,online,_,class = GetGuildRosterInfo(j)
		tempName = CommDKP:StripRealm(tempName)  -- AD-9.6: realm suffix optional; nil entries skipped
		if tempName and online and not CommDKP:IsSelf(tempName) then
			table.insert(PlayerList, { player=tempName, class=class })
		end
	end

	table.sort(PlayerList, function(a, b)
		return a["player"] < b["player"]
	end)

	core.Broadcast = core.Broadcast or CommDKP_BroadcastFull_Create()
	core.Broadcast:SetShown(not core.Broadcast:IsShown())

	DD:UIDropDownMenu_Initialize(core.Broadcast.player, function(self, level, menuList)
		
		local filterName = DD:UIDropDownMenu_CreateInfo()
		local FLAT_MAX = 25		-- AD-12.6: flat list for small rosters

		if #PlayerList <= FLAT_MAX then
			if (level or 1) == 1 then
				filterName.func = self.SetValue
				for i = 1, #PlayerList do
					local name = PlayerList[i].player
					local colored = "|c"..CommDKP:GetCColors(PlayerList[i].class).hex..name.."|r"
					filterName.text, filterName.arg1, filterName.arg2, filterName.checked, filterName.isNotRadio = colored, name, colored, name == player, true
					DD:UIDropDownMenu_AddButton(filterName)
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
			filterName.func = self.SetValue

			for i=1, numSubs do
				local min, max = (i*20)-19, i*20;
				if max > #PlayerList then max = #PlayerList end
				local inRange = false
				for j = min, max do
					if PlayerList[j].player == player then inRange = true; break end
				end
				filterName.text, filterName.checked, filterName.menuList, filterName.hasArrow = strsub(PlayerList[min].player, 1, 1).."-"..strsub(PlayerList[max].player, 1, 1), inRange, i, true
				DD:UIDropDownMenu_AddButton(filterName)
			end
			
		else
			filterName.func = self.SetValue
			for i=ranges[menuList], ranges[menuList]+19 do
				if PlayerList[i] then
					local c = CommDKP:GetCColors(PlayerList[i].class)

					filterName.text, filterName.arg1, filterName.arg2, filterName.checked, filterName.isNotRadio = "|c"..c.hex..PlayerList[i].player.."|r", PlayerList[i].player, "|c"..c.hex..PlayerList[i].player.."|r", PlayerList[i].player == player, true
					DD:UIDropDownMenu_AddButton(filterName, level)
				end
			end
		end
	end)
	DD:UIDropDownMenu_SetText(core.Broadcast.player, "")

	function core.Broadcast.player:SetValue(newValue, arg2) 	---- PLAYER dropdown function
		if player ~= newValue then player = newValue end
		DD:UIDropDownMenu_SetText(core.Broadcast.player, arg2)
		DD:CloseDropDownMenus()
	end

	core.Broadcast.confirmButton:SetScript("OnClick", function()
		local tempTable
		local teams = CommDKP:GetTable(CommDKP_DB, false)["teams"];

		if core.Broadcast.mergeCheckbox:GetChecked() == false and core.Broadcast.fullCheckbox:GetChecked() == false then
			CommDKP:Print(L["BROADCASTWHICHDATA"])
			return
		end
		if core.Broadcast.playerCheckbox:GetChecked() == true and player == nil then
			CommDKP:Print(L["PLAYERVALIDATE"])
			return
		end
		if core.Broadcast.fullCheckbox:GetChecked() == true then
			tempTable = { 
				DKPTable = CommDKP:GetTable(CommDKP_DKPTable, true),
				DKP=CommDKP:GetTable(CommDKP_DKPHistory, true), 
				Loot=CommDKP:GetTable(CommDKP_Loot, true), 
				Archive=CommDKP:GetTable(CommDKP_Archive, true), 
				MinBids=CommDKP:FormatPriceTable(), 
				Teams=teams
			}
			-- AD-36.3.1 (BR-28.9a, CM-04): the payload carries array copies WITHOUT the non-array .seed key. Rows are shared
			-- (SendData serializes synchronously); the live tables keep their .seed until the existing post-send zeroing.
			-- Kept outside the literal above (H109 evaluates that literal on its own).
			for _, k in ipairs({ "DKP", "Loot" }) do
				local src, copy = tempTable[k], {}
				for i = 1, #src do copy[i] = src[i] end
				tempTable[k] = copy
			end
		elseif core.Broadcast.mergeCheckbox:GetChecked() == true then
			tempTable = CommDKP_MergeTable_Create()
		end
		if core.Broadcast.playerCheckbox:GetChecked() == true and player ~= nil then
			if core.Broadcast.mergeCheckbox:GetChecked() == true then
			 	CommDKP.Sync:SendData("CommDKPMerge", tempTable, player)
			 	CommDKP_SyncDeleted()
				core.Broadcast:Hide()
				CommDKP_BroadcastFull_Status()
			elseif core.Broadcast.fullCheckbox:GetChecked() == true then
				StaticPopupDialogs["FULL_TABS_ALERT"] = {
					text = "|CFFFF0000"..L["WARNING"].."|r: "..L["OVERWRITETABLES"],
					button1 = L["YES"],
					button2 = L["NO"],
					OnAccept = function()
						CommDKP.Sync:SendData("CommDKPAllTabs", tempTable, player)
						core.Broadcast:Hide()
						CommDKP:GetTable(CommDKP_DKPHistory, true).seed = 0
						CommDKP:GetTable(CommDKP_Loot, true).seed = 0
						CommDKP_BroadcastFull_Status()
					end,
					timeout = 0,
					whileDead = true,
					hideOnEscape = true,
					preferredIndex = 3,
				}
				CommDKP:ShowPopupOverFloaters("FULL_TABS_ALERT", core.Broadcast)
			end
		elseif core.Broadcast.guildCheckbox:GetChecked() == true then
			if core.Broadcast.mergeCheckbox:GetChecked() == true then
				CommDKP.Sync:SendData("CommDKPMerge", tempTable)
				CommDKP_SyncDeleted()
				if IsInGuild() and CommDKP.SendSeedData then CommDKP:SendSeedData() end
				core.Broadcast:Hide()
				CommDKP_BroadcastFull_Status()
			elseif core.Broadcast.fullCheckbox:GetChecked() == true then
				StaticPopupDialogs["FULL_TABS_ALERT"] = {
					text = "|CFFFF0000"..L["WARNING"].."|r: "..L["OVERWRITETABLES"],
					button1 = L["YES"],
					button2 = L["NO"],
					OnAccept = function()
						CommDKP.Sync:SendData("CommDKPAllTabs", tempTable)
						if IsInGuild() and CommDKP.SendSeedData then CommDKP:SendSeedData() end
						core.Broadcast:Hide()
						CommDKP:GetTable(CommDKP_DKPHistory, true).seed = 0
						CommDKP:GetTable(CommDKP_Loot, true).seed = 0
						CommDKP_BroadcastFull_Status()
					end,
					timeout = 0,
					whileDead = true,
					hideOnEscape = true,
					preferredIndex = 3,
				}
				CommDKP:ShowPopupOverFloaters("FULL_TABS_ALERT", core.Broadcast)
			end
		end
	end)
	core.Broadcast.cancelButton:SetScript("OnClick", function()
		core.Broadcast:Hide()
	end)
end

function CommDKP_BroadcastFull_Callback(arg1, arg2, arg3)
	bytesSent = arg2
	bytesTotal = arg3

	if arg2 == arg3 then
		bytesSent = 0
		bytesTotal = 0
	end
end

function CommDKP_BroadcastFull_Create()
	-- UX §12.4.6 / AD-16.4: "window" chrome (340 x 270, modal floater, returns focus to UIConfig on hide).
	-- One "Send To" card + the action row; every interior control anchors to f.Content (BR-9.4.4).
	local f, content = CommDKP:CreateForeverWindow("CommDKP_FullBroadcastWindow", 340, 270, L["BROADCASTTABLES"])
	f:SetPoint("TOP", UIParent, "TOP", 0, -200);
	f.bcastHeader = f.TitleLabel

	local card = W.CreateCard(content, L["CARDSENDTO"], 316, 152)
	card:SetPoint("TOPLEFT", content, "TOPLEFT", 0, 0)
	f.tocontainer, f.datacontainer = card, card     -- legacy container keys (both groups now live in the one card)
	local b = card.Body

		-- to player: the four CommDKPLargeLeft headers become the checkboxes' own labels (same strings, §12.4.6)
		f.playerCheckbox = W.CreateCheckbox(b, nil, L["PLAYER"])
		f.playerCheckbox:SetPoint("TOPLEFT", b, "TOPLEFT", W.PAD, -13)
		f.playerCheckbox:SetChecked(false)
		f.playerHeader = f.playerCheckbox.text
		f.playerCheckbox:SetScript("OnClick", function(self)
			if self:GetChecked() == true then
				f.player:Show()
				f.guildCheckbox:SetChecked(false)
			else
				f.player:Hide()
			end
		end)
		f.playerCheckbox:SetScript("OnEnter", function(self)
			GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
			GameTooltip:SetText(L["PLAYER"], 0.25, 0.75, 0.90, 1, true)
			GameTooltip:AddLine(L["TOPLAYERTTDESC"], 1.0, 1.0, 1.0, true);
			GameTooltip:Show()
		end)
		f.playerCheckbox:SetScript("OnLeave", function()
			GameTooltip:Hide()
		end)

		f.player = DD:Create_UIDropDownMenu("CommDKPBroadcastPlayerDropDown", b);
		f.player:SetPoint("TOPLEFT", b, "TOPLEFT", 120, -10)
		DD:UIDropDownMenu_SetWidth(f.player, 178)
		DD:UIDropDownMenu_JustifyText(f.player, "LEFT")
		f.player:Hide()

		-- to guild
		f.guildCheckbox = W.CreateCheckbox(b, nil, L["GUILD"])
		f.guildCheckbox:SetPoint("TOPLEFT", b, "TOPLEFT", W.PAD, -41)
		f.guildCheckbox:SetChecked(false)
		f.guildHeader = f.guildCheckbox.text
		f.guildCheckbox:SetScript("OnClick", function(self)
			if self:GetChecked() == true then
				f.playerCheckbox:SetChecked(false)
				f.player:Hide()
			end
		end)
		f.guildCheckbox:SetScript("OnEnter", function(self)
			GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
			GameTooltip:SetText(L["GUILD"], 0.25, 0.75, 0.90, 1, true)
			GameTooltip:AddLine(L["TOGUILDTTDESC"], 1.0, 1.0, 1.0, true);
			GameTooltip:Show()
		end)
		f.guildCheckbox:SetScript("OnLeave", function()
			GameTooltip:Hide()
		end)

		-- 1 px rule between the recipient and the data choices
		f.sendRule = b:CreateTexture(nil, "BORDER")
		f.sendRule:SetPoint("TOPLEFT", b, "TOPLEFT", W.PAD, -66)
		f.sendRule:SetPoint("TOPRIGHT", b, "TOPRIGHT", -W.PAD, -66)
		f.sendRule:SetHeight(1)
		f.sendRule:SetColorTexture(unpack((core.Palette or core.Palettes.Forever).rule))

		f.mergeCheckbox = W.CreateCheckbox(b, nil, L["MERGE2WEEKS"])
		f.mergeCheckbox:SetPoint("TOPLEFT", b, "TOPLEFT", W.PAD, -77)
		f.mergeCheckbox:SetChecked(false)
		f.mergeHeader = f.mergeCheckbox.text
		f.mergeCheckbox:SetScript("OnClick", function(self)
			if self:GetChecked() == true then
				f.fullCheckbox:SetChecked(false)
			end
		end)
		f.mergeCheckbox:SetScript("OnEnter", function(self)
			GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
			GameTooltip:SetText(L["MERGE2WEEKS"], 0.25, 0.75, 0.90, 1, true)
			GameTooltip:AddLine(L["MERGE2WEEKSTTDESC"], 1.0, 1.0, 1.0, true);
			GameTooltip:AddLine(L["MERGE2WEEKSTTWARN"], 1.0, 0, 0, true);
			GameTooltip:Show()
		end)
		f.mergeCheckbox:SetScript("OnLeave", function()
			GameTooltip:Hide()
		end)

		f.fullCheckbox = W.CreateCheckbox(b, nil, L["FULLBROADCAST"])
		f.fullCheckbox:SetPoint("TOPLEFT", b, "TOPLEFT", W.PAD, -101)
		f.fullCheckbox:SetChecked(false)
		f.fullHeader = f.fullCheckbox.text
		f.fullCheckbox:SetScript("OnClick", function(self)
			if self:GetChecked() == true then
				f.mergeCheckbox:SetChecked(false)
			end
		end)
		f.fullCheckbox:SetScript("OnEnter", function(self)
			GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
			GameTooltip:SetText(L["FULLBROADCAST"], 0.25, 0.75, 0.90, 1, true)
			GameTooltip:AddLine(L["FULLBROADCASTTTDESC"], 1.0, 1.0, 1.0, true);
			GameTooltip:AddLine(L["FULLBROADCASTTTWARN"], 1.0, 0, 0, true);
			GameTooltip:Show()
		end)
		f.fullCheckbox:SetScript("OnLeave", function()
			GameTooltip:Hide()
		end)

	-- Action row: Broadcast (primary, 120) left, Cancel (120) right.
	f.confirmButton = CommDKP:CreateButton("BOTTOMLEFT", content, "BOTTOMLEFT", 0, 0, L["BROADCAST"]);
	f.confirmButton:SetSize(120, W.H)
	W.StyleButton(f.confirmButton, "primary")
	f.cancelButton = CommDKP:CreateButton("BOTTOMRIGHT", content, "BOTTOMRIGHT", 0, 0, L["CANCEL"]);
	f.cancelButton:SetSize(120, W.H)

	return f
end

function CommDKP_SyncDeleted()
	local deleted = {}
	for k,v in pairs(CommDKP:GetTable(CommDKP_Archive, true)) do
		if type(CommDKP:GetTable(CommDKP_Archive, true)[k]) == "table" then
			if CommDKP:GetTable(CommDKP_Archive, true)[k].deleted then
				table.insert(deleted, { player=k, deleted=v.deleted, edited=v.edited })
			end
		end

	end

	if #deleted > 0 then
		CommDKP.Sync:SendData("CommDKPDelUsers", deleted)
	end
end

function CommDKP_MergeTable_Create()
	local tempDKP = {}
	local tempLoot = {}
	local profiles = {}
	local teams = CommDKP:GetTable(CommDKP_DB, false)["teams"]

	for i=1, #CommDKP:GetTable(CommDKP_DKPHistory, true) do
		if CommDKP:GetTable(CommDKP_DKPHistory, true)[i].date > (time() - 1209600) then
			table.insert(tempDKP, CommDKP:GetTable(CommDKP_DKPHistory, true)[i])
		else
			break
		end
	end

	for i=1, #CommDKP:GetTable(CommDKP_Loot, true) do
		if CommDKP:GetTable(CommDKP_Loot, true)[i].date > (time() - 1209600) then
			table.insert(tempLoot, CommDKP:GetTable(CommDKP_Loot, true)[i])
		else
			break
		end
	end

	for i=1, #CommDKP:GetTable(CommDKP_DKPTable, true) do
		table.insert(profiles, CommDKP:GetTable(CommDKP_DKPTable, true)[i])
	end

	local tempTable = { DKP=tempDKP, Loot=tempLoot, Profiles=profiles, Teams=teams }
	return tempTable
end
