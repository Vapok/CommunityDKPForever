local _, core = ...;
local _G = _G;
local CommDKP = core.CommDKP;
local L = core.L;

local bytesSent = 0
local bytesTotal = 0
local LibAceSerializer = LibStub:GetLibrary("AceSerializer-3.0")
local LibDeflate = LibStub:GetLibrary("LibDeflate")
local LibDD = LibStub:GetLibrary("LibUIDropDownMenu-4.0");

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
			table.insert(CommDKP:GetTable(CommDKP_DKPTable, true, _teamIndex), { player=player, lifetime_spent=spent, lifetime_gained=gained, class=class, dkp=dkp, rank=10, spec=L["NOSPECREPORTED"], role=L["NOROLEDETECTED"], rankName="None", previous_dkp=0, })

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
					tinsert(CommDKP:GetTable(CommDKP_DKPTable, true, _teamIndex), { player=player, class=tempClass, dkp=dkp, previous_dkp=0, lifetime_gained=gained, lifetime_spent=spent, rank=10, rankName="None", spec=L["NOSPECREPORTED"], role=L["NOROLEDETECTED"], })
					CommDKP:FilterDKPTable(core.currentSort, "reset")
					CommDKP:ClassGraph_Update()
					created = true
					break
				end
			end
		end
	end

	if not created then
		tinsert(CommDKP:GetTable(CommDKP_DKPTable, true, _teamIndex), { player=player, class=class, dkp=dkp, previous_dkp=0, lifetime_gained=gained, lifetime_spent=spent, rank=10, rankName="None", spec=L["NOSPECREPORTED"], role=L["NOROLEDETECTED"], })
	end

	return created
end

local function CommDKP_BroadcastFull_Status_Create()
	-- UX §10.6.2: native template toast, pinned at FULLSCREEN_DIALOG (not a floater, no Esc binding).
	local f = CommDKP:CreateForeverWindow("CommDKP_FullBroadcastStatus", 300, 100,
		L["BCASTINGTABLES"], { floater = false, escape = false })
	f:SetPoint("TOP", UIParent, "TOP", 0, -10);
	f:SetFrameStrata("FULLSCREEN_DIALOG")    -- pinned; never cycled by FocusWindow
	f.bcastHeader = f.TitleLabel             -- SetText(L["BCASTINGTABLES"]) now writes the title

	f.status = CreateFrame("StatusBar", nil, f, "BackdropTemplate")
	f.status:SetSize(200, 15)
	CommDKP:ApplyBackdrop(f.status, "StatusBg", "StatusBg")
	f.status:SetStatusBarTexture([[Interface\TargetingFrame\UI-TargetingFrame-BarFill]])
	f.status:SetPoint("CENTER", f, "CENTER", 0, -6)

	f.status.percentage = f:CreateFontString(nil, "OVERLAY")
	f.status.percentage:SetFontObject("CommDKPLargeCenter");
	f.status.percentage:SetPoint("TOP", f.status, "BOTTOM", 0, -9);
	f.status.percentage:SetScale(0.6)

	f.status.border = CreateFrame("Frame", nil, f.status, "BackdropTemplate");
	f.status.border:SetPoint("CENTER", f.status, "CENTER");
	f.status.border:SetFrameLevel(f.status:GetFrameLevel() + 1)   -- inherits the toast's strata (§10.6.2)
	f.status.border:SetSize(200, 18);
	CommDKP:ApplyBackdrop(f.status.border, "BorderOnly", "Clear", "WindowBorder")
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

	LibDD:UIDropDownMenu_Initialize(core.Broadcast.player, function(self, level, menuList)
		
		local filterName = LibDD:UIDropDownMenu_CreateInfo()
		local FLAT_MAX = 25		-- AD-12.6: flat list for small rosters

		if #PlayerList <= FLAT_MAX then
			if (level or 1) == 1 then
				filterName.func = self.SetValue
				for i = 1, #PlayerList do
					local name = PlayerList[i].player
					local colored = "|c"..CommDKP:GetCColors(PlayerList[i].class).hex..name.."|r"
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
			filterName.func = self.SetValue

			for i=1, numSubs do
				local min, max = (i*20)-19, i*20;
				if max > #PlayerList then max = #PlayerList end
				local inRange = false
				for j = min, max do
					if PlayerList[j].player == player then inRange = true; break end
				end
				filterName.text, filterName.checked, filterName.menuList, filterName.hasArrow = strsub(PlayerList[min].player, 1, 1).."-"..strsub(PlayerList[max].player, 1, 1), inRange, i, true
				LibDD:UIDropDownMenu_AddButton(filterName)
			end
			
		else
			filterName.func = self.SetValue
			for i=ranges[menuList], ranges[menuList]+19 do
				if PlayerList[i] then
					local c = CommDKP:GetCColors(PlayerList[i].class)

					filterName.text, filterName.arg1, filterName.arg2, filterName.checked, filterName.isNotRadio = "|c"..c.hex..PlayerList[i].player.."|r", PlayerList[i].player, "|c"..c.hex..PlayerList[i].player.."|r", PlayerList[i].player == player, true
					LibDD:UIDropDownMenu_AddButton(filterName, level)
				end
			end
		end
	end)
	LibDD:UIDropDownMenu_SetText(core.Broadcast.player, "")

	function core.Broadcast.player:SetValue(newValue, arg2) 	---- PLAYER dropdown function
		if player ~= newValue then player = newValue end
		LibDD:UIDropDownMenu_SetText(core.Broadcast.player, arg2)
		LibDD:CloseDropDownMenus()
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
	-- UX §10.6.1: native template window (modal floater, returns focus to UIConfig on hide).
	local f = CommDKP:CreateForeverWindow("CommDKP_FullBroadcastWindow", 340, 270,
		"CommunityDKP Forever \226\128\148 " .. L["BROADCASTTABLES"])
	f:SetPoint("TOP", UIParent, "TOP", 0, -200);
	f.bcastHeader = f.TitleLabel

	f.tocontainer = CommDKP:CreateContainer(f, "CommDKP_Broadcast_tocontainer", "Broadcast to:")
    f.tocontainer:SetPoint("TOP", f, "TOP", 0, -48)
    f.tocontainer:SetSize(250, 64)

		-- to player
		f.playerHeader = f:CreateFontString(nil, "OVERLAY")
		f.playerHeader:SetFontObject("CommDKPLargeLeft");
		f.playerHeader:SetScale(0.6)
		f.playerHeader:SetPoint("TOPLEFT", f.tocontainer, "TOPLEFT", 40, -25);
		f.playerHeader:SetText(L["PLAYER"])

		f.playerCheckbox = CreateFrame("CheckButton", nil, f, "UICheckButtonTemplate");
		f.playerCheckbox:SetPoint("RIGHT", f.playerHeader, "LEFT", 0, 0)
		f.playerCheckbox:SetChecked(false)
		f.playerCheckbox:SetScale(0.6)
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

		f.player = LibDD:Create_UIDropDownMenu("CommDKPBroadcastPlayerDropDown", f);
		f.player:SetPoint("TOPRIGHT", f.tocontainer, "TOPRIGHT", 5, -7)
		LibDD:UIDropDownMenu_SetWidth(f.player, 150)
		LibDD:UIDropDownMenu_JustifyText(f.player, "LEFT")
		f.player:Hide()

		-- to guild
		f.guildHeader = f:CreateFontString(nil, "OVERLAY")
		f.guildHeader:SetFontObject("CommDKPLargeLeft");
		f.guildHeader:SetScale(0.6)
		f.guildHeader:SetPoint("TOPLEFT", f.playerHeader, "BOTTOMLEFT", 0, -15);
		f.guildHeader:SetText(L["GUILD"])

		f.guildCheckbox = CreateFrame("CheckButton", nil, f, "UICheckButtonTemplate");
		f.guildCheckbox:SetPoint("RIGHT", f.guildHeader, "LEFT", 0, 0)
		f.guildCheckbox:SetChecked(false)
		f.guildCheckbox:SetScale(0.6)
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

	f.datacontainer = CommDKP:CreateContainer(f, "CommDKP_Broadcast_tocontainer", "Data:")
    f.datacontainer:SetPoint("TOPLEFT", f.tocontainer, "BOTTOMLEFT", 0, -18)
    f.datacontainer:SetSize(250, 64)

    	f.mergeHeader = f:CreateFontString(nil, "OVERLAY")
		f.mergeHeader:SetFontObject("CommDKPLargeLeft");
		f.mergeHeader:SetScale(0.6)
		f.mergeHeader:SetPoint("TOPLEFT", f.datacontainer, "TOPLEFT", 40, -25);
		f.mergeHeader:SetText(L["MERGE2WEEKS"])

		f.mergeCheckbox = CreateFrame("CheckButton", nil, f, "UICheckButtonTemplate");
		f.mergeCheckbox:SetPoint("RIGHT", f.mergeHeader, "LEFT", 0, 0)
		f.mergeCheckbox:SetChecked(false)
		f.mergeCheckbox:SetScale(0.6)
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

		f.fullHeader = f:CreateFontString(nil, "OVERLAY")
		f.fullHeader:SetFontObject("CommDKPLargeLeft");
		f.fullHeader:SetScale(0.6)
		f.fullHeader:SetPoint("TOPLEFT", f.mergeHeader, "BOTTOMLEFT", 0, -15);
		f.fullHeader:SetText(L["FULLBROADCAST"])

		f.fullCheckbox = CreateFrame("CheckButton", nil, f, "UICheckButtonTemplate");
		f.fullCheckbox:SetPoint("RIGHT", f.fullHeader, "LEFT", 0, 0)
		f.fullCheckbox:SetChecked(false)
		f.fullCheckbox:SetScale(0.6)
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

	f.confirmButton = CommDKP:CreateButton("BOTTOMLEFT", f, "BOTTOMLEFT", 20, 14, L["BROADCAST"]);
	f.cancelButton = CommDKP:CreateButton("BOTTOMRIGHT", f, "BOTTOMRIGHT", -20, 14, L["CANCEL"]);

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
