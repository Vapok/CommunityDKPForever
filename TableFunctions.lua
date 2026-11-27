local _, core = ...;
local _G = _G;
local CommDKP = core.CommDKP;
local L = core.L;
local LibDD = LibStub:GetLibrary("LibUIDropDownMenu-4.0");   -- the roster right-click menuFrame stays on LibDD (Q4)
local W = CommDKP.Widgets

local SelectedRow = 0;        -- sets the row that is being clicked

-- UX §12.2.10: stripe / hover come from W.StyleRow; selection is W.SetRowSelected (bg3 fill + 1 px trim edge).
-- The row keeps a transparent normal texture because DKPTable_Update still raises its alpha for the player's own
-- row (GetNormalTexture():SetAlpha(0.8)); that faint bronze "self" band is unchanged.
local ROW_FILL = "Interface\\Buttons\\WHITE8X8"
local function PaintRow(row, selected)
	local P = core.Palette or core.Palettes.Forever
	row:SetNormalTexture(ROW_FILL)
	local t = row:GetNormalTexture()
	t:SetVertexColor(P.line[1], P.line[2], P.line[3])
	t:SetAlpha(0)
	W.SetRowSelected(row, selected)
end
local menuFrame = LibDD:Create_UIDropDownMenu("CommDKPDKPTableMenuFrame", UIParent)
CommDKP.Widgets.RegisterContextMenu(menuFrame)   -- CDKP-019 (AD-27.2.3)
local ConvToRaidEvent = CreateFrame("Frame", "CommDKPConvToRaidEventsFrame");
local InvCount;
local LastSelection = 0;

function CommDKPSelectionCount_Update()
	if #core.SelectedData == 0 then
		CommDKP.DKPTable.counter.s:SetText("");    -- updates "Entries Shown" at bottom of DKPTable
	else
		if #core.SelectedData == 1 then
			CommDKP.DKPTable.counter.s:SetText("("..#core.SelectedData.." "..L["ENTRYSELECTED"]..")");
		else
			CommDKP.DKPTable.counter.s:SetText("("..#core.SelectedData.." "..L["ENTRIESSELECTED"]..")");
		end
	end
end

local function CountDown(time)
	if time then CooldownTimer = time end
	if CooldownTimer > 0 then
		C_Timer.After(1, function()
			CooldownTimer = CooldownTimer - 1
			CountDown()
		end)
	end
end

local function DKPTable_OnClick(self)   
	local offset = FauxScrollFrame_GetOffset(CommDKP.DKPTable) or 0
	local index, TempSearch;
	SelectedRow = self.index

	if L_UIDROPDOWNMENU_OPEN_MENU then
		LibDD:ToggleDropDownMenu(nil, nil, menuFrame)
	end
	
	if IsShiftKeyDown() then
		if LastSelection < SelectedRow then
			for i=LastSelection+1, SelectedRow do
				TempSearch = CommDKP:Table_Search(core.SelectedData, core.WorkingTable[i].player);
				
				if not TempSearch then
					tinsert(core.SelectedData, core.WorkingTable[i])
				end
			end
		else
			for i=SelectedRow, LastSelection-1 do
				TempSearch = CommDKP:Table_Search(core.SelectedData, core.WorkingTable[i].player);
				
				if not TempSearch then
					tinsert(core.SelectedData, core.WorkingTable[i])
				end
			end
		end

		if CommDKP.ConfigTab2.selectAll:GetChecked() then
			CommDKP.ConfigTab2.selectAll:SetChecked(false)
		end
	elseif IsControlKeyDown() then
		LastSelection = SelectedRow;
		TempSearch = CommDKP:Table_Search(core.SelectedData, core.WorkingTable[SelectedRow].player);
		if TempSearch == false then
			tinsert(core.SelectedData, core.WorkingTable[SelectedRow]);
			PlaySound(808)
		else
			tremove(core.SelectedData, TempSearch[1][1])
			PlaySound(868)
		end
	else
		LastSelection = SelectedRow;
		for i=1, core.TableNumRows do
			TempSearch = CommDKP:Table_Search(core.SelectedData, core.WorkingTable[SelectedRow].player);
			if CommDKP.ConfigTab2.selectAll:GetChecked() then
				CommDKP.ConfigTab2.selectAll:SetChecked(false)
			end
			if (TempSearch == false) then
				tinsert(core.SelectedData, core.WorkingTable[SelectedRow]);
				PlaySound(808)
			else
				core.SelectedData = {}
			end
		end
	end

	CommDKP:DKPTable_Update()
	CommDKPSelectionCount_Update()
end

local function Invite_OnEvent(self, event, arg1, ...)
	if event == "CHAT_MSG_SYSTEM" then
		if strfind(arg1, " joins the party.") then
			ConvertToRaid()
			ConvToRaidEvent:UnregisterEvent("CHAT_MSG_SYSTEM")
			for i=InvCount+1, #core.SelectedData do
				InviteUnit(core.SelectedData[i].player)
			end
		end
	end
end

-- AD-24.2 (CDKP-017, BR-17.1): the ONE Roster / officer-Bidding "Recent History" tooltip. On normal data it is call-for-call
-- the former file-local DisplayUserHistory (BR-17.3); the AD-24 guards only change cases that used to throw (BR-17.4/17.6).
function CommDKP:ShowPlayerHistoryTooltip(owner, player)
	if not owner or type(player) ~= "string" or player == "" then return end          -- AD-24 G1 (BR-17.6)
	if issecretvalue and issecretvalue(player) then return end                         -- AD-24 G1 (BR-17.8)

	local PlayerTable = {}
	local c, PlayerSearch, PlayerSearch2, LifetimeSearch, RowCount, curDate;
	local maxCount = (core.DB and core.DB.defaults and tonumber(core.DB.defaults.TooltipHistoryCount)) or 15  -- AD-24 G2
	if maxCount < 1 then maxCount = 15 end                                             -- AD-24 G2
	local lookUpLimit = maxCount;                                                      -- AD-24 G2

	PlayerSearch = CommDKP:TableStrFind(CommDKP:GetTable(CommDKP_DKPHistory, true), player, "players", lookUpLimit)
	PlayerSearch2 = CommDKP:Table_Search(CommDKP:GetTable(CommDKP_Loot, true), player, "player", lookUpLimit)
	LifetimeSearch = CommDKP:Table_Search(CommDKP:GetTable(CommDKP_DKPTable, true), player, "player", lookUpLimit)

	-- AD-24 G3 (BR-17.4, T4): no profile -> grey header (same 0.67 grey as the Bidding row; hex is required by the |c below)
	local dkpTable = CommDKP:GetTable(CommDKP_DKPTable, true)
	local profileEntry = (LifetimeSearch and LifetimeSearch[1] and LifetimeSearch[1][1]) and dkpTable[LifetimeSearch[1][1]] or nil
	local GREY = { r = 0.67, g = 0.67, b = 0.67, hex = "ffababab" }
	if profileEntry and profileEntry.class then
		c = CommDKP:GetCColors(profileEntry.class) or GREY
	else
		c = GREY
	end

	GameTooltip:SetOwner(owner, "ANCHOR_RIGHT", 0, 0);
	GameTooltip:SetText(L["RECENTHISTORYFOR"].." |c"..c.hex..player.."|r\n", 0.25, 0.75, 0.90, 1, true);

	if PlayerSearch then
		for i=1, #PlayerSearch do
			if not CommDKP:GetTable(CommDKP_DKPHistory, true)[PlayerSearch[i][1]].deletes and not CommDKP:GetTable(CommDKP_DKPHistory, true)[PlayerSearch[i][1]].deletedby and not CommDKP:GetTable(CommDKP_DKPHistory, true)[PlayerSearch[i][1]].hidden then
				tinsert(
					PlayerTable, {
						reason = CommDKP:GetTable(CommDKP_DKPHistory, true)[PlayerSearch[i][1]].reason, 
						date = CommDKP:GetTable(CommDKP_DKPHistory, true)[PlayerSearch[i][1]].date, 
						dkp = CommDKP:GetTable(CommDKP_DKPHistory, true)[PlayerSearch[i][1]].dkp, 
						players = CommDKP:GetTable(CommDKP_DKPHistory, true)[PlayerSearch[i][1]].players
					}
				)
			end
		end
	end

	if PlayerSearch2 then
		for i=1, #PlayerSearch2 do
			if not CommDKP:GetTable(CommDKP_Loot, true)[PlayerSearch2[i][1]].deletes and not CommDKP:GetTable(CommDKP_Loot, true)[PlayerSearch2[i][1]].deletedby and not CommDKP:GetTable(CommDKP_Loot, true)[PlayerSearch2[i][1]].hidden then
				tinsert(PlayerTable, {
					loot = CommDKP:GetTable(CommDKP_Loot, true)[PlayerSearch2[i][1]].loot, 
					date = CommDKP:GetTable(CommDKP_Loot, true)[PlayerSearch2[i][1]].date, 
					zone = CommDKP:GetTable(CommDKP_Loot, true)[PlayerSearch2[i][1]].zone, 
					boss = CommDKP:GetTable(CommDKP_Loot, true)[PlayerSearch2[i][1]].boss, 
					cost = CommDKP:GetTable(CommDKP_Loot, true)[PlayerSearch2[i][1]].cost
				})
			end
		end
	end

	table.sort(PlayerTable, function(a, b)
		return a["date"] > b["date"]
	end)

	if #PlayerTable > 0 then
		if #PlayerTable > maxCount then                                                  -- AD-24 G2
			RowCount = maxCount                                                            -- AD-24 G2
		else
			RowCount = #PlayerTable;
		end

		for i=1, RowCount do
			if date("%m/%d/%y", PlayerTable[i].date) ~= curDate then
				curDate = date("%m/%d/%y", PlayerTable[i].date)
				GameTooltip:AddLine(date("%m/%d/%y", PlayerTable[i].date), 1.0, 1.0, 1.0, true);
			end
			if PlayerTable[i].dkp then
				if strfind(PlayerTable[i].dkp, "%%") then
					local decay = {strsplit(",", PlayerTable[i].dkp)}
					-- get substring till player name and split to get correct player index for decay list
					local playerIndex = {strsplit(",", string.sub(PlayerTable[i].players, 1, (strfind(PlayerTable[i].players, player..","))))};
					GameTooltip:AddDoubleLine("  "..PlayerTable[i].reason, "|cffff0000"..decay[#playerIndex].." DKP|r", 1.0, 0, 0);
				elseif tonumber(PlayerTable[i].dkp) < 0 then
					GameTooltip:AddDoubleLine("  "..PlayerTable[i].reason, "|cffff0000"..CommDKP_round(PlayerTable[i].dkp, core.DB.modes.rounding).." DKP|r", 1.0, 0, 0);
				else
					GameTooltip:AddDoubleLine("  "..PlayerTable[i].reason, "|cff00ff00"..CommDKP_round(PlayerTable[i].dkp, core.DB.modes.rounding).." DKP|r", 0, 1.0, 0);
				end
			elseif PlayerTable[i].cost then
				GameTooltip:AddDoubleLine("  "..(PlayerTable[i].zone or "")..": |cffff0000"..(PlayerTable[i].boss or "").."|r", PlayerTable[i].loot.." |cffff0000("..PlayerTable[i].cost.." DKP)|r", 1.0, 1.0, 1.0);  -- AD-24 G5
			end
		end
		if profileEntry then                                                             -- AD-24 G4 (BR-17.4)
			GameTooltip:AddDoubleLine(" ", " ", 1.0, 1.0, 1.0);
			GameTooltip:AddLine("  |cff00ff00"..L["LIFETIMEEARNED"]..": "..CommDKP_round(profileEntry.lifetime_gained, core.DB.modes.rounding).."|r", 1.0, 1.0, 1.0, true);
			GameTooltip:AddLine("  |cffff0000"..L["LIFETIMESPENT"]..": "..CommDKP_round(profileEntry.lifetime_spent, core.DB.modes.rounding).."|r", 1.0, 1.0, 1.0, true);
		end
	else
		GameTooltip:AddLine("No DKP Entries", 1.0, 1.0, 1.0, true);
	end

	GameTooltip:Show();
end

local function EditStandbyList(row, arg1)
	if arg1 ~= "clear" then
		if #core.SelectedData > 1 then
			local copy = CopyTable(core.SelectedData)

			for i=1, #copy do
				local search = CommDKP:Table_Search(CommDKP:GetTable(CommDKP_Standby, true), copy[i].player)

				if arg1 == "add" then
					if not search then
						table.insert(CommDKP:GetTable(CommDKP_Standby, true), copy[i])
					end
				elseif arg1 == "remove" then          
					if search then
						table.remove(CommDKP:GetTable(CommDKP_Standby, true), search[1][1])
						core.SelectedData = {}
						if core.CurView == "limited" then
							table.remove(core.WorkingTable, search[1][1])
						end
					end
				end
			end
		else
			if arg1 == "add" then
				table.insert(CommDKP:GetTable(CommDKP_Standby, true), core.WorkingTable[row])
			elseif arg1 == "remove" then
				local search = CommDKP:Table_Search(CommDKP:GetTable(CommDKP_Standby, true), core.WorkingTable[row].player)

				if search then
					table.remove(CommDKP:GetTable(CommDKP_Standby, true), search[1][1])
					core.SelectedData = {}
					if core.CurView == "limited" then
						table.remove(core.WorkingTable, search[1][1])
					end
				end
			end
		end
		CommDKP.Sync:SendData("CommDKPStand", CommDKP:GetTable(CommDKP_Standby, true))
		CommDKP:DKPTable_Update()
	else
		table.wipe(CommDKP:GetTable(CommDKP_Standby, true))
		core.WorkingTable = {}
		CommDKP:DKPTable_Update()
		CommDKP.Sync:SendData("CommDKPStand", CommDKP:GetTable(CommDKP_Standby, true))
	end
	if #core.WorkingTable == 0 then
		core.WorkingTable = CopyTable(CommDKP:GetTable(CommDKP_DKPTable, true));
		core.CurView = "all"
		CommDKP:FilterDKPTable(core.currentSort, "reset")
	end
end

function CommDKP:ViewLimited(raid, standby, raiders)
	if #CommDKP:GetTable(CommDKP_Standby, true) == 0 and standby and not raid and not raiders then
		CommDKP:Print(L["NOPLAYERINSTANDBY"])
		core.CurView = "all"
		core.CurSubView = "all"
	elseif raid or standby or raiders then
		local tempTable = {}
		local GroupType = "none"
		
		if (not IsInGroup() and not IsInRaid()) and raid then
			CommDKP:Print(L["NOPARTYORRAID"])
			core.WorkingTable = CopyTable(CommDKP:GetTable(CommDKP_DKPTable, true))
			core.CurView = "all"
			core.CurSubView = "all"
			for i=1, 10 do
				CommDKP.ConfigTab1.checkBtn[i]:SetChecked(true)
			end
			CommDKP:FilterDKPTable(core.currentSort, "reset");
			return;
		end

		if raid then
			local inGroup = CommDKP:GetGroupRosterNames()		-- AD-15.3(c): one roster build; raid and 5-man party (incl. self)
			for k,v in pairs(CommDKP:GetTable(CommDKP_DKPTable, true)) do
				if type(v) == "table" and v.player and inGroup[CommDKP:NormalizeName(v.player) or ""] then
					tinsert(tempTable, v)
				end
			end
		end

		if standby then
			for i=1, #CommDKP:GetTable(CommDKP_Standby, true) do
				local search = CommDKP:Table_Search(CommDKP:GetTable(CommDKP_DKPTable, true), CommDKP:GetTable(CommDKP_Standby, true)[i].player)
				local search2 = CommDKP:Table_Search(tempTable, CommDKP:GetTable(CommDKP_Standby, true)[i].player)
				
				if search and not search2 then
					table.insert(tempTable, CommDKP:GetTable(CommDKP_DKPTable, true)[search[1][1]])
				end
			end
		end

		if raiders then
			local guildSize = GetNumGuildMembers();
			local name, rankIndex;

			local nameIndices = {}
			for i, entry in pairs(CommDKP:GetTable(CommDKP_DKPTable, true)) do
				nameIndices[entry.player] = i
			end
			local rankList = CommDKP:GetGuildRankList()
			local raiderRanks = {}
			for i, rank in ipairs(core.DB.raiders) do
				raiderRanks[rank] = true
			end
			
			for i=1, guildSize do
				name,_,rankIndex = GetGuildRosterInfo(i)
				name = CommDKP:StripRealm(name)      -- AD-9.6: realm suffix optional; nil entries skipped
				local search = name and nameIndices[name]

				if search then
					if raiderRanks[rankList[rankIndex+1].name] then
						table.insert(tempTable, CommDKP:GetTable(CommDKP_DKPTable, true)[search])
					end
				end
			end
			if #tempTable == 0 then
				CommDKP:Print(L["NOCORERAIDTEAM"])
				return;
			end
		end

		core.SelectedData = {}
		LastSelection = 0
		CommDKPSelectionCount_Update()
		core.WorkingTable = CopyTable(tempTable)
		table.wipe(tempTable)

		core.CurView = "limited"
		CommDKP:DKPTable_Update()
	elseif core.CurView == "limited" then
		core.WorkingTable = CopyTable(CommDKP:GetTable(CommDKP_DKPTable, true))
		core.CurView = "all"
		core.CurSubView = "all"
		for i=1, 10 do
			CommDKP.ConfigTab1.checkBtn[i]:SetChecked(true)
		end
		CommDKPFilterChecks(CommDKP.ConfigTab1.checkBtn[1])
	end
end

local function RightClickMenu(self)
	local menu;
	local disabled;

	if #CommDKP:GetTable(CommDKP_Standby, true) < 1 then disabled = true else disabled = false end

	--Build Team Table for Manage Tables
	local manageTeamTables = {}
	local teams = CommDKP:GetTable(CommDKP_DB, false)["teams"]
	local teamMenuText = "";

	for teamIndex,team in pairs(teams) do
		local teamDisabled = false;

		local nameIndices = {}
		for i, entry in pairs(CommDKP:GetTable(CommDKP_DKPTable, true, teamIndex)) do
			nameIndices[entry.player] = i
		end

		if teamIndex == CommDKP:GetCurrentTeamIndex() then
			teamDisabled = true;
		end

		if #core.SelectedData < 2 then
			teamMenuText = string.format("Copy %s to %s",core.WorkingTable[self.index].player,team.name);
			if nameIndices[core.WorkingTable[self.index].player] then
				teamDisabled = true;
			end
		else
			teamMenuText = string.format("Copy %s to %s","Selected Players",team.name);
		end
	
		local teamMenu = { text = teamMenuText, notCheckable = true, disabled = teamDisabled, func = function()
			CommDKP:CopyProfileToTeam(self.index, teamIndex)
			LibDD:ToggleDropDownMenu(nil, nil, menuFrame)
		end }
		tinsert(manageTeamTables, teamMenu);
	end
	
	-- Build Full Menu
	menu = {
		{ text = L["MULTIPLESELECT"], isTitle = true, notCheckable = true}, --1
		{ text = L["INVITESELECTED"], notCheckable = true, func = function()
			InvCount = 4 - GetNumSubgroupMembers()
			
			for i=1, InvCount do
				InviteUnit(core.SelectedData[i].player)
			end
			if #core.SelectedData >= 5 then
				ConvToRaidEvent:RegisterEvent("CHAT_MSG_SYSTEM")
				ConvToRaidEvent:SetScript("OnEvent", Invite_OnEvent);
			end
		end }, --2
		{ text = L["SELECTALL"], notCheckable = true, func = function()
			core.SelectedData = CopyTable(core.WorkingTable);
			CommDKPSelectionCount_Update()
			CommDKP:DKPTable_Update()
		end }, --3
		{ text = " ", notCheckable = true, disabled = true}, --4
		{ text = L["VIEWS"], isTitle = true, notCheckable = true}, --5
		{ text = L["TABLEVIEWS"], notCheckable = true, hasArrow = true,
				menuList = { 
					{ text = L["VIEWRAID"], notCheckable = true, keepShownOnClick = false; func = function()
						CommDKP:ViewLimited(true)
						core.CurSubView = "raid"
						CommDKP.ConfigTab1.checkBtn[11]:SetChecked(true);
						CommDKP.ConfigTab1.checkBtn[13]:SetChecked(false);   -- AD-28.2.3 (D-28.3, BR-20.2)
						LibDD:ToggleDropDownMenu(nil, nil, menuFrame)
					end },
					{ text = L["VIEWSTANDBY"], notCheckable = true, func = function()
						CommDKP:ViewLimited(false, true)
						core.CurSubView = "standby"
						LibDD:ToggleDropDownMenu(nil, nil, menuFrame)
					end },
					{ text = L["VIEWRAIDSTANDBY"], notCheckable = true, func = function()
						CommDKP:ViewLimited(true, true)
						core.CurSubView = "raid and standby"
						LibDD:ToggleDropDownMenu(nil, nil, menuFrame)
					end },
					{ text = L["VIEWCORERAID"], notCheckable = true, func = function()
						CommDKP:ViewLimited(false, false, true)
						CommDKP:SortDKPTable(core.currentSort, "reset")
						core.CurSubView = "core"
						LibDD:ToggleDropDownMenu(nil, nil, menuFrame)
					end },
					{ text = L["VIEWALL"], notCheckable = true, func = function()
						CommDKP.ConfigTab1.checkBtn[11]:SetChecked(false);
						CommDKP.ConfigTab1.checkBtn[12]:SetChecked(false);
						CommDKP.ConfigTab1.checkBtn[13]:SetChecked(false);
						CommDKP:ViewLimited()
						LibDD:ToggleDropDownMenu(nil, nil, menuFrame, nil, nil, nil, nil, nil)
					end },
			}
		}, --6
		{ text = L["CLASSFILTER"], notCheckable = true, hasArrow = true,
				menuList = {}
		}, --7
		{ text = " ", notCheckable = true, disabled = true}, --8
		{ text = L["MANAGELISTS"], isTitle = true, notCheckable = true}, --9
		{ text = L["MANAGESTANDBY"], notCheckable = true, hasArrow = true,
				menuList = {
					{ text = L["ADDTOSTANDBY"], notCheckable = true, func = function()
						EditStandbyList(self.index, "add")
						LibDD:ToggleDropDownMenu(nil, nil, menuFrame)
					end },
					{ text = L["REMOVEFROMSTANDBY"], notCheckable = true, func = function()
						EditStandbyList(self.index, "remove")
						LibDD:ToggleDropDownMenu(nil, nil, menuFrame)
					end },
					{ text = L["CLEARSTANDBY"], notCheckable = true, disabled = disabled, func = function()
						EditStandbyList(self.index, "clear")
						LibDD:ToggleDropDownMenu(nil, nil, menuFrame)
					end },
				}
		}, --10
		{ text = L["MANAGECORELIST"], notCheckable = true, hasArrow = true,
				menuList = {}
		}, --11
		{ text = " ", notCheckable = true, disabled = true}, --8
		{ text = "Manage Tables", isTitle = true, notCheckable = true}, --9
		{ text = "Copy Profile", notCheckable = true, hasArrow = true,
				menuList = manageTeamTables
		},
		{ text = L["RESETPREVIOUS"], notCheckable = true, func = function()
			for i=1, #core.SelectedData do
				CommDKP:reset_prev_dkp(core.SelectedData[i].player)
			end
			CommDKP:FilterDKPTable(core.currentSort, "reset")
		end 
		}, --13
		{ text = L["VALIDATETABLES"], notCheckable = true, disabled = not core.IsOfficer, func = function()
			StaticPopupDialogs["VALIDATE_WARN"] = {
				text = "|CFFFF0000"..L["WARNING"].."|r: "..L["VALIDATEWARN"],
				button1 = L["YES"],
				button2 = L["NO"],
				OnAccept = function()
					CommDKP:ValidateLootTable()
				end,
				timeout = 0,
				whileDead = true,
				hideOnEscape = true,
				preferredIndex = 3,
			}
			StaticPopup_Show ("VALIDATE_WARN")
		end 
		}, --14
	}

	if #core.SelectedData < 2 then
		menu[1].text = core.WorkingTable[self.index].player;
		menu[2] = { text = L["INVITE"].." "..core.WorkingTable[self.index].player.." "..L["TORAID"], notCheckable = true, func = function()
			InviteUnit(core.WorkingTable[self.index].player)
		end }

		local StandbySearch = CommDKP:Table_Search(CommDKP:GetTable(CommDKP_Standby, true), core.WorkingTable[self.index].player)
		
		if StandbySearch then
			menu[10].menuList = {
				{ text = L["REMOVE"].." "..core.WorkingTable[self.index].player.." "..L["FROMSTANDBYLIST"], notCheckable = true, func = function()
					EditStandbyList(self.index, "remove")
					LibDD:ToggleDropDownMenu(nil, nil, menuFrame)
				end },
				{ text = L["CLEARSTANDBY"], notCheckable = true, disabled = disabled, func = function()
					EditStandbyList(self.index, "clear")
					LibDD:ToggleDropDownMenu(nil, nil, menuFrame)
				end },
			}
		else
			menu[10].menuList = {
				{ text = L["ADD"].." "..core.WorkingTable[self.index].player.." "..L["TOSTANDBYLIST"], notCheckable = true, func = function()
					EditStandbyList(self.index, "add")
					LibDD:ToggleDropDownMenu(nil, nil, menuFrame)
				end },
				{ text = L["CLEARSTANDBY"], notCheckable = true, disabled = disabled, func = function()
					EditStandbyList(self.index, "clear")
					LibDD:ToggleDropDownMenu(nil, nil, menuFrame)
				end },
			}
		end
	end

	for i=1, #core.classes do       -- create Filter selections in context menu
		menu[7].menuList[i] = { text = API_CLASSES[core.classes[i]], isNotRadio = true, keepShownOnClick = true, checked = CommDKP.ConfigTab1.checkBtn[i]:GetChecked(), func = function()
			CommDKP.ConfigTab1.checkBtn[i]:SetChecked(not CommDKP.ConfigTab1.checkBtn[i]:GetChecked())
			CommDKPFilterChecks(CommDKP.ConfigTab1.checkBtn[10])
			for j=1, #core.classes+1 do
				menu[7].menuList[j].checked = CommDKP.ConfigTab1.checkBtn[j]:GetChecked()
			end
		end }
	end

	menu[7].menuList[#core.classes+1] = { text = L["ALLCLASSES"], isNotRadio = true, keepShownOnClick = false, notCheckable = true, func = function()
		CommDKP.ConfigTab1.checkBtn[10]:SetChecked(true)
		
		for i=1, #core.classes do
			CommDKP.ConfigTab1.checkBtn[i]:SetChecked(true)
			menu[7].menuList[i].checked = true
		end

		CommDKPFilterChecks(CommDKP.ConfigTab1.checkBtn[10])
		if L_UIDROPDOWNMENU_OPEN_MENU then
			LibDD:ToggleDropDownMenu(nil, nil, menuFrame)
		end
	end }

	menu[7].menuList[#core.classes+2] = { text = L["ONLYPARTYRAID"], isNotRadio = true, keepShownOnClick = false, disabled = not (IsInRaid() or IsInGroup()), checked = CommDKP.ConfigTab1.checkBtn[11]:GetChecked(), func = function()
		CommDKP.ConfigTab1.checkBtn[11]:SetChecked(not CommDKP.ConfigTab1.checkBtn[11]:GetChecked())
		CommDKP.ConfigTab1.checkBtn[13]:SetChecked(false)
		menu[7].menuList[#core.classes+4].checked = false

		CommDKPFilterChecks(CommDKP.ConfigTab1.checkBtn[11])
		if L_UIDROPDOWNMENU_OPEN_MENU then
			LibDD:ToggleDropDownMenu(nil, nil, menuFrame)
		end
	end }

	menu[7].menuList[#core.classes+3] = { text = L["ONLINE"], isNotRadio = true, keepShownOnClick = true, checked = CommDKP.ConfigTab1.checkBtn[12]:GetChecked(), func = function()
		CommDKP.ConfigTab1.checkBtn[12]:SetChecked(not CommDKP.ConfigTab1.checkBtn[12]:GetChecked())
		core.CurView = "limited"

		CommDKPFilterChecks(CommDKP.ConfigTab1.checkBtn[12])
	end }

	menu[7].menuList[#core.classes+4] = { text = L["NOTINRAIDFILTER"], isNotRadio = true, keepShownOnClick = false, disabled = not (IsInRaid() or IsInGroup()), checked = CommDKP.ConfigTab1.checkBtn[13]:GetChecked(), func = function()
		CommDKP.ConfigTab1.checkBtn[13]:SetChecked(not CommDKP.ConfigTab1.checkBtn[13]:GetChecked())
		CommDKP.ConfigTab1.checkBtn[11]:SetChecked(false)
		menu[7].menuList[#core.classes+2].checked = false

		CommDKPFilterChecks(CommDKP.ConfigTab1.checkBtn[13])
		if L_UIDROPDOWNMENU_OPEN_MENU then
			LibDD:ToggleDropDownMenu(nil, nil, menuFrame)
		end
	end }

	if #CommDKP:GetTable(CommDKP_Standby, true) == 0 then
		menu[6].menuList[2] = { text = L["VIEWSTANDBY"], notCheckable = true, disabled = true, }
		menu[6].menuList[3] = { text = L["VIEWRAIDSTANDBY"], notCheckable = true, disabled = true}
	end

	if not IsInGroup() and not IsInRaid() then
		menu[6].menuList[1] = { text = L["VIEWRAID"], notCheckable = true, disabled = true }
		menu[6].menuList[3] = { text = L["VIEWRAIDSTANDBY"], notCheckable = true, disabled = true}
	end

	local rankList = CommDKP:GetGuildRankList()
	for i=1, #rankList do
		local checked;

		if CommDKP:Table_Search(core.DB.raiders, rankList[i].name) then
			checked = true;
		else
			checked = false;
		end

		menu[11].menuList[i] = { text = rankList[i].name, isNotRadio = true, keepShownOnClick = true, checked = checked, func = function()
			if menu[11].menuList[i].checked then
				menu[11].menuList[i].checked = false;

				local rank_search = CommDKP:Table_Search(core.DB.raiders, rankList[i].name)

				if rank_search then
					table.remove(core.DB.raiders, rank_search[1])
				end
			else
				menu[11].menuList[i].checked = true;
				table.insert(core.DB.raiders, rankList[i].name)
			end
		end }
	end

	menu[11].menuList[#menu[11].menuList + 1] = { text = " ", notCheckable = true, disabled = true }

	menu[11].menuList[#menu[11].menuList + 1] = { text = L["CLOSE"], notCheckable = true, func = function()
		LibDD:ToggleDropDownMenu(nil, nil, menuFrame)
	end }


	local guildSize = GetNumGuildMembers();
	local name, rankIndex;
	local tempTable = {}
	local nameIndices = {}
	for i, entry in pairs(CommDKP:GetTable(CommDKP_DKPTable, true)) do
		nameIndices[entry.player] = i
	end

	for i=1, guildSize do
		name,_,rankIndex = GetGuildRosterInfo(i)
		name = CommDKP:StripRealm(name)      -- AD-9.6: realm suffix optional; nil entries skipped
		local search = name and nameIndices[name]

		if search then
			local rankList = CommDKP:GetGuildRankList()

			local match_rank = CommDKP:Table_Search(core.DB.raiders, rankList[rankIndex+1].name)

			if match_rank then
				table.insert(tempTable, CommDKP:GetTable(CommDKP_DKPTable, true)[search])
			end
		end
	end
	if #tempTable == 0 then
		menu[6].menuList[4].disabled = true;
	else
		menu[6].menuList[4].disabled = false;
	end
	table.wipe(tempTable);

	if core.IsOfficer == false then
		for i=8, #menu do
			menu[i].disabled = true
		end

		--table.remove(menu[6].menuList, 4)
	end

	LibDD:EasyMenu(menu, menuFrame, "cursor", 0 , 0, "MENU", 1);
end

local function CreateRow(parent, id) -- Create 3 buttons for each row in the list
		local f = CreateFrame("Button", "$parentLine"..id, parent)
		f.DKPInfo = {}
		f:SetSize(core.TableWidth, core.TableRowHeight)
		W.StyleRow(f, id)                 -- §12.2.10 stripe (odd rows) + bg3 hover; replaces the old highlight texture
		PaintRow(f, false)
		f:SetScript("OnClick", DKPTable_OnClick)
		for i=1, 3 do
			f.DKPInfo[i] = W.CreateText(f, "body", nil, "LEFT");      -- §12.2.10 cells: GameFontHighlight (class / DKP colors unchanged, Q8)
			if (i==1) then
				f.DKPInfo[i].rowCounter = W.CreateText(f, "caption", nil, "LEFT", "textMuted");
				f.DKPInfo[i].rowCounter:SetPoint("LEFT", f, "LEFT", 3, 0);
			end
			if (i==3) then
				f.DKPInfo[i].adjusted = W.CreateText(f, "caption", nil, "LEFT", "textMuted");
				f.DKPInfo[i].adjusted:SetPoint("LEFT", f.DKPInfo[3], "RIGHT", 3, 0);

				if core.DB.modes.mode == "Roll Based Bidding" then
					f.DKPInfo[i].rollrange = W.CreateText(f, "caption", nil, "CENTER", "textMuted");
					f.DKPInfo[i].rollrange:SetPoint("CENTER", 115, 0);
				end

				f.DKPInfo[i].adjustedArrow = f:CreateTexture(nil, "OVERLAY", nil, -8);
				f.DKPInfo[i].adjustedArrow:SetPoint("RIGHT", f, "RIGHT", -10, 0);
				f.DKPInfo[i].adjustedArrow:SetColorTexture(0, 0, 0, 0.5)
				f.DKPInfo[i].adjustedArrow:SetSize(8, 12);
			end
		end
		f.DKPInfo[1]:SetPoint("LEFT", 30, 0)
		f.DKPInfo[2]:SetPoint("CENTER")
		f.DKPInfo[3]:SetPoint("RIGHT", -80, 0)


		f:SetScript("OnMouseDown", function(self, button)
			if button == "RightButton" then
				RightClickMenu(self)
			end
		end)

		return f
end

function CommDKP:DKPTable_Update()
	if not CommDKP.UIConfig:IsShown() then     -- does not update list if DKP window is closed. Gets done when /dkp is used anyway.
		return;
	end

	if core.RepairWorking then
		print("[CommunityDKP] DKP Table Repair Started");
		for i=1, #CommDKP:GetTable(CommDKP_DKPTable, true) do
			local record = CommDKP:GetTable(CommDKP_DKPTable, true)[i];
			local bad = false;
			if record["dkp"] == nil then bad = true	end
			if record["previous_dkp"] == nil then bad = true end
			if record["lifetime_spent"] == nil then bad = true end
			if record["lifetime_gained"] == nil then bad = true end
			if bad then
				print("Removing DKP Table Record "..tostring(i));
				tremove(CommDKP:GetTable(CommDKP_DKPTable, true), i)
				tremove(core.WorkingTable, i)
			end
		end
		print("[CommunityDKP] DKP Table Repair Complete");
		core.RepairWorking = false;
	end

	if core.CurView == "limited" then  -- recreates WorkingTable if in limited view (view raid, core raiders etc)
		local tempTable = {}

		for i=1, #core.WorkingTable do
			local search = CommDKP:Table_Search(CommDKP:GetTable(CommDKP_DKPTable, true), core.WorkingTable[i].player)

			if search then
				
				table.insert(tempTable, CommDKP:GetTable(CommDKP_DKPTable, true)[search[1][1]])
			end
		end
		core.WorkingTable = CopyTable(tempTable)
		table.wipe(tempTable)
	end

	local numOptions = #core.WorkingTable
	local index, row, c
	local offset = FauxScrollFrame_GetOffset(CommDKP.DKPTable) or 0
	local rank, rankIndex;

	for i=1, core.TableNumRows do     -- hide all rows before displaying them 1 by 1 as they show values
		row = CommDKP.DKPTable.Rows[i];
		row:Hide();
	end
	--[[for i=1, #CommDKP:GetTable(CommDKP_DKPTable, true) do
		if CommDKP:GetTable(CommDKP_DKPTable, true)[i].dkp < 0 then CommDKP:GetTable(CommDKP_DKPTable, true)[i].dkp = 0 end  -- cleans negative numbers from SavedVariables
	end--]]
	for i=1, core.TableNumRows do     -- show rows if they have values
		row = CommDKP.DKPTable.Rows[i]
		index = offset + i
		if core.WorkingTable[index] then
			--if (tonumber(core.WorkingTable[index].dkp) < 0) then core.WorkingTable[index].dkp = 0 end           -- shows 0 if negative DKP

			c = CommDKP:GetCColors(core.WorkingTable[index].class);
			row:Show()
			row.index = index
			local CurPlayer = core.WorkingTable[index].player;

			if core.CenterSort == "rank" then
				local SetRank = CommDKP:Table_Search(CommDKP:GetTable(CommDKP_DKPTable, true), core.WorkingTable[index].player, "player")
				rank, rankIndex = CommDKP:GetGuildRank(core.WorkingTable[index].player)
				CommDKP:GetTable(CommDKP_DKPTable, true)[SetRank[1][1]].rank = rankIndex or 20;
				CommDKP:GetTable(CommDKP_DKPTable, true)[SetRank[1][1]].rankName = rank or "None";
			end
			row.DKPInfo[1]:SetText(core.WorkingTable[index].player)
			row.DKPInfo[1].rowCounter:SetText(index)
			row.DKPInfo[1]:SetTextColor(c.r, c.g, c.b, 1)
			
			if core.CenterSort == "class" then
				row.DKPInfo[2]:SetText(API_CLASSES[core.WorkingTable[index].class])
			elseif core.CenterSort == "rank" then
				row.DKPInfo[2]:SetText(rank)
			elseif core.CenterSort == "spec" then
				if core.WorkingTable[index].spec then
					row.DKPInfo[2]:SetText(core.WorkingTable[index].spec)
				else
					row.DKPInfo[2]:SetText(L["NOSPECREPORTED"])
					local SetSpec = CommDKP:Table_Search(CommDKP:GetTable(CommDKP_DKPTable, true), core.WorkingTable[index].player, "player")		-- writes "No Spec Reported" to players profile if spec field doesn't exist
					CommDKP:GetTable(CommDKP_DKPTable, true)[SetSpec[1][1]].spec = L["NOSPECREPORTED"]
				end
			elseif core.CenterSort == "role" then
				if core.WorkingTable[index].role then
					row.DKPInfo[2]:SetText(core.WorkingTable[index].role)
				else
					row.DKPInfo[2]:SetText(L["NOROLEDETECTED"])
					local SetRole = CommDKP:Table_Search(CommDKP:GetTable(CommDKP_DKPTable, true), core.WorkingTable[index].player, "player")		-- writes "No Role Detected" to players profile if role field doesn't exist
					CommDKP:GetTable(CommDKP_DKPTable, true)[SetRole[1][1]].role = L["NOROLEDETECTED"]
				end
			elseif core.CenterSort == "version" then
				row.DKPInfo[2]:SetText(core.WorkingTable[index].version or "Unknown");	-- AD-26.4.5: display only, no write-back
			end
			
			row.DKPInfo[3]:SetText(CommDKP_round(core.WorkingTable[index].dkp, core.DB.modes.rounding))
			local CheckAdjusted = core.WorkingTable[index].dkp - core.WorkingTable[index].previous_dkp;
			if(CheckAdjusted > 0) then 
				CheckAdjusted = strjoin("", "+", CheckAdjusted) 
				row.DKPInfo[3].adjustedArrow:SetTexture("Interface\\AddOns\\CommunityDKPForever\\Media\\Textures\\green-up-arrow.png");
			elseif (CheckAdjusted < 0) then
				row.DKPInfo[3].adjustedArrow:SetTexture("Interface\\AddOns\\CommunityDKPForever\\Media\\Textures\\red-down-arrow.png");
			else
				row.DKPInfo[3].adjustedArrow:SetTexture(nil);
			end        
			row.DKPInfo[3].adjusted:SetText("("..CommDKP_round(CheckAdjusted, core.DB.modes.rounding)..")");

			if core.DB.modes.mode == "Roll Based Bidding" then
				local minimum;
				local maximum;

				if core.DB.modes.rolls.UsePerc then
					if core.DB.modes.rolls.min == 0 or core.DB.modes.rolls.min == 1 then
							minimum = 1;
					else
						minimum = core.WorkingTable[index].dkp * (core.DB.modes.rolls.min / 100);
					end
					maximum = core.WorkingTable[index].dkp * (core.DB.modes.rolls.max / 100) + core.DB.modes.rolls.AddToMax;
				elseif not core.DB.modes.rolls.UsePerc then
					minimum = core.DB.modes.rolls.min;

					if core.DB.modes.rolls.max == 0 then
						maximum = core.WorkingTable[index].dkp + core.DB.modes.rolls.AddToMax;
					else
						maximum = core.DB.modes.rolls.max + core.DB.modes.rolls.AddToMax;
					end
				end
				if maximum < 1 then maximum = 1 end
				if minimum < 1 then minimum = 1 end        

				if minimum > maximum then
					row.DKPInfo[3].rollrange:SetText("(0-0)")
				else
					row.DKPInfo[3].rollrange:SetText("("..math.floor(minimum).."-"..math.floor(maximum)..")")
				end
			elseif row.DKPInfo[3].rollrange then
				row.DKPInfo[3].rollrange:SetText("")
			end

			local a = CommDKP:Table_Search(core.SelectedData, core.WorkingTable[index].player);  -- searches selectedData for the player name indexed.
			if not a then
				PaintRow(CommDKP.DKPTable.Rows[i], false)
			else
				PaintRow(CommDKP.DKPTable.Rows[i], true)
			end
			if CommDKP:IsSelf(core.WorkingTable[index].player) then
				row.DKPInfo[2]:SetText("|cff00ff00"..row.DKPInfo[2]:GetText().."|r")
				row.DKPInfo[3]:SetText("|cff00ff00"..CommDKP_round(core.WorkingTable[index].dkp, core.DB.modes.rounding).."|r")
				CommDKP.DKPTable.Rows[i]:GetNormalTexture():SetAlpha(0.8)
			end
			CommDKP.DKPTable.Rows[i]:SetScript("OnEnter", function(self)
				CommDKP:ShowPlayerHistoryTooltip(self, CurPlayer)       -- AD-24.2.5 (BR-17.1): shared helper
			end)
			CommDKP.DKPTable.Rows[i]:SetScript("OnLeave", function()
				GameTooltip:Hide()
			end)
		else
			row:Hide()
		end
	end

	if #core.WorkingTable == 0 then  		-- Displays "No Entries Returned" if the result of filter combinations yields an empty table
		--CommDKP_RestoreFilterOptions()
		CommDKP.DKPTable.Rows[1].DKPInfo[1].rowCounter:SetText("")
		CommDKP.DKPTable.Rows[1].DKPInfo[1]:SetText("")
		CommDKP.DKPTable.Rows[1].DKPInfo[2]:SetText("|cffff6060"..L["NOENTRIESRETURNED"].."|r")
		CommDKP.DKPTable.Rows[1].DKPInfo[3]:SetText("")
		CommDKP.DKPTable.Rows[1].DKPInfo[3].adjusted:SetText("")
		CommDKP.DKPTable.Rows[1].DKPInfo[3].adjustedArrow:SetTexture(nil)
		if CommDKP.DKPTable.Rows[1].DKPInfo[3].rollrange then CommDKP.DKPTable.Rows[1].DKPInfo[3].rollrange:SetText("") end
		CommDKP.DKPTable.Rows[1]:SetScript("OnEnter", nil)
		CommDKP.DKPTable.Rows[1]:SetScript("OnMouseDown", function()
			CommDKP_RestoreFilterOptions() 		-- restores filter selections to default on click.
		end)
		CommDKP.DKPTable.Rows[1]:SetScript("OnClick", function()
			CommDKP_RestoreFilterOptions() 		-- restores filter selections to default on click.
		end)
		CommDKP.DKPTable.Rows[1]:Show()
	else
		CommDKP.DKPTable.Rows[1]:SetScript("OnMouseDown", function(self, button)
			if button == "RightButton" then
				RightClickMenu(self)
			end
		end)
		CommDKP.DKPTable.Rows[1]:SetScript("OnClick", DKPTable_OnClick)
	end

	CommDKP.DKPTable.counter.t:SetText(#core.WorkingTable.." "..L["ENTRIESSHOWN"]);    -- updates "Entries Shown" at bottom of DKPTable

	FauxScrollFrame_Update(CommDKP.DKPTable, numOptions, core.TableNumRows, core.TableRowHeight, nil, nil, nil, nil, nil, nil, true) -- alwaysShowScrollBar= true to stop frame from hiding
end

function CommDKP:DKPTable_Create()
	-- UX §12.3.1: the table lives in the Roster Card body, under the 24 px column strip. 23 rows x 18 = 414 (+3)
	-- between the strip and the 34 px footer (B12: only core.TableNumRows sets the count). The card provides the frame.
	local rosterCard = CommDKP.UIConfig.RosterCard
	local host = (rosterCard and rosterCard.Body) or CommDKP.UIConfig
	CommDKP.DKPTable = CreateFrame("ScrollFrame", "CommDKPDisplayScrollFrame", host, "FauxScrollFrameTemplate, BackdropTemplate")
	CommDKP.DKPTable:SetSize(core.TableWidth, core.TableRowHeight*core.TableNumRows+3)
	CommDKP.DKPTable:SetPoint("TOPLEFT", host, "TOPLEFT", 0, -24)

	
	CommDKP.DKPTable:SetClipsChildren(false);

	CommDKP.DKPTable.ScrollBar = FauxScrollFrame_GetChildFrames(CommDKP.DKPTable)
	CommDKP.DKPTable.Rows = {}
	for i=1, core.TableNumRows do
		CommDKP.DKPTable.Rows[i] = CreateRow(CommDKP.DKPTable, i)
		if i==1 then
			CommDKP.DKPTable.Rows[i]:SetPoint("TOPLEFT", CommDKP.DKPTable, "TOPLEFT", 0, -2)
		else  
			CommDKP.DKPTable.Rows[i]:SetPoint("TOPLEFT", CommDKP.DKPTable.Rows[i-1], "BOTTOMLEFT")
		end
	end
	CommDKP.DKPTable:SetScript("OnVerticalScroll", function(self, offset)
		FauxScrollFrame_OnVerticalScroll(self, offset, core.TableRowHeight, CommDKP.DKPTable_Update)
	end)
	W.AttachFauxRail(CommDKP.DKPTable, host)          -- §12.2.8: 6 px rail at the table's right, inside the card

	-- §12.2.11 sync pip: SeedVerify (16 x 16, same OnEnter/OnLeave/OnMouseDown) on the Roster Card footer, LEFT (10, 0).
	local footer = (rosterCard and rosterCard.Footer) or CommDKP.DKPTable
	CommDKP.DKPTable.SeedVerify = CreateFrame("Frame", nil, footer);
	if rosterCard then
		CommDKP.DKPTable.SeedVerify:SetPoint("LEFT", footer, "LEFT", 10, 0);
	else
		CommDKP.DKPTable.SeedVerify:SetPoint("TOPLEFT", CommDKP.DKPTable, "BOTTOMLEFT", 0, -15);
	end
	CommDKP.DKPTable.SeedVerify:SetSize(16, 16);
	CommDKP.DKPTable.SeedVerify:SetScript("OnLeave", function(self)
		GameTooltip:Hide()
	end)
	CommDKP.DKPTable.SeedVerify:SetScript("OnMouseDown", function()  -- broadcast button
		if core.IsOfficer then	
			CommDKP:SendSeedData();
			CommDKP_BroadcastFull_Init() 	-- launches Broadcast UI
		end
	end)

	CommDKP.DKPTable.SeedVerifyIcon = CommDKP.DKPTable.SeedVerify:CreateTexture(nil, "ARTWORK", nil)   -- seed verify (footer left) pip fill
	W.StyleStatusPip(CommDKP.DKPTable.SeedVerify, CommDKP.DKPTable.SeedVerifyIcon)
	W.SetPipState(CommDKP.DKPTable.SeedVerifyIcon, true)   -- same initial state as the old out-of-date texture
end
