local _, core = ...;
local _G = _G;
local CommDKP = core.CommDKP;
local L = core.L;

local LibDD = LibStub:GetLibrary("LibUIDropDownMenu-4.0");
local DD = CommDKP.DD                     -- AD-16.3: selector protocol (GuildRankDropDown, TeamListDropDown)
local W = CommDKP.Widgets
local MANAGE_COL = 165                    -- UX §12.3.4: three equal 165 px button columns, 8 px gutter

local function Remove_Entries()
	CommDKP:StatusVerify_Update()
	local numPlayers = 0;
	local removedUsers, c;
	local deleted = {};

	for i=1, #core.SelectedData do
		local search = CommDKP:Table_Search(CommDKP:GetTable(CommDKP_DKPTable, true), core.SelectedData[i]["player"]);
		local flag = false -- flag = only create archive entry if they appear anywhere in the history. If there's no history, there's no reason anyone would have it.
		local curTime = time()

		if search then
			local path = CommDKP:GetTable(CommDKP_DKPTable, true)[search[1][1]]

			for i=1, #CommDKP:GetTable(CommDKP_DKPHistory, true) do
				if strfind(CommDKP:GetTable(CommDKP_DKPHistory, true)[i].players, ","..path.player..",") or strfind(CommDKP:GetTable(CommDKP_DKPHistory, true)[i].players, path.player..",") == 1 then
					flag = true
				end
			end

			for i=1, #CommDKP:GetTable(CommDKP_Loot, true) do
				if CommDKP:GetTable(CommDKP_Loot, true)[i].player == path.player then
					flag = true
				end
			end
			
			if flag then 		-- above 2 loops flags character if they have any loot/dkp history. Only inserts to archive and broadcasts if found. Other players will not have the entry if no history exists
				if not CommDKP:GetTable(CommDKP_Archive, true)[core.SelectedData[i].player] then
					CommDKP:GetTable(CommDKP_Archive, true)[core.SelectedData[i].player] = { deleted=true, edited=curTime }
				end
				CommDKP:GetTable(CommDKP_Archive, true)[core.SelectedData[i].player].dkp = path.dkp
				CommDKP:GetTable(CommDKP_Archive, true)[core.SelectedData[i].player].lifetime_spent = path.lifetime_spent
				CommDKP:GetTable(CommDKP_Archive, true)[core.SelectedData[i].player].lifetime_gained = path.lifetime_gained
				CommDKP:GetTable(CommDKP_Archive, true)[core.SelectedData[i].player].deleted = true
				CommDKP:GetTable(CommDKP_Archive, true)[core.SelectedData[i].player].edited = curTime
			end

			c = CommDKP:GetCColors(core.SelectedData[i]["class"])
			if i==1 then
				removedUsers = "|c"..c.hex..core.SelectedData[i]["player"].."|r"
			else
				removedUsers = removedUsers..", |c"..c.hex..core.SelectedData[i]["player"].."|r"
			end
			numPlayers = numPlayers + 1

			tremove(CommDKP:GetTable(CommDKP_DKPTable, true), search[1][1])
			tinsert(deleted, { player=path.player, deleted=true, dkp=path.dkp, lifetime_gained=path.lifetime_gained, lifetime_spent=path.lifetime_spent, edited=curTime })   -- AD-36.8.2 (BR-28.23)
			CommDKP:GetTable(CommDKP_Profiles, true)[path.player] = nil;

			local search2 = CommDKP:Table_Search(CommDKP:GetTable(CommDKP_Standby, true), core.SelectedData[i].player, "player");

			if search2 then
				table.remove(CommDKP:GetTable(CommDKP_Standby, true), search2[1][1])
			end
		end
	end
	table.wipe(core.SelectedData)
	CommDKPSelectionCount_Update()
	CommDKP:FilterDKPTable(core.currentSort, "reset")
	CommDKP:Print("["..CommDKP:GetTeamName(CommDKP:GetCurrentTeamIndex()).."] ".."Removed "..numPlayers.." player(s): "..removedUsers)
	CommDKP:ClassGraph_Update()

	if #deleted >0 then
		CommDKP.Sync:SendData("CommDKPDelUsers", deleted)
	end
end

local function AddRaidToDKPTable()
	local GroupType = "none";

	if IsInRaid() then
		GroupType = "raid"
	elseif IsInGroup() then
		GroupType = "party"
	end

	if GroupType ~= "none" then
		local tempName,tempClass;
		local addedUsers, c
		local numPlayers = 0;
		local guildSize = GetNumGuildMembers();
		local name, rank, rankIndex;
		local InGuild = false; -- Only adds player to list if the player is found in the guild roster.
		local GroupSize;
		local FlagRecovery = false
		local curTime = time()
		local entities = {}

		if GroupType == "raid" then
			GroupSize = 40
		elseif GroupType == "party" then
			GroupSize = 5
		end

		local metaIndex = CommDKP:BuildKnownMetaIndex()			-- AD-26.4.2 P2: one snapshot for the whole batch
		local addedSelf = false

		for i=1, GroupSize do
			InGuild, rank, rankIndex = false, nil, nil			-- RC-11: no rank/guild state leaks from the previous member
			tempName,_,_,_,_,tempClass = GetRaidRosterInfo(i)
			tempName = tempName and CommDKP:NormalizeName(tempName)
			for j=1, guildSize do
				name, rank, rankIndex = GetGuildRosterInfo(j)
				name = CommDKP:StripRealm(name)						-- AD-9.5.3: realm suffix optional; nil entries skipped
				if name and CommDKP:SamePlayer(name, tempName) then
					InGuild = true;
					break;  -- keep this member's rank/rankIndex
				end
			end
			if tempName then
				local profile = CommDKP:GetDefaultEntity();
				if not CommDKP:Table_Search(CommDKP:GetTable(CommDKP_DKPTable, true), tempName) then
					if InGuild then
						profile.player=tempName;
						profile.class=tempClass;
						profile.rank = rankIndex;
						profile.rankName = rank;
					else
						profile.player=tempName;
						profile.class=tempClass;
					end
					CommDKP:HydratePlayerRow(profile, metaIndex)		-- AD-26.4.2 P2: before any insert
					if CommDKP:IsSelf(tempName) then addedSelf = true end
					tinsert(CommDKP:GetTable(CommDKP_DKPTable, true), profile);
					tinsert(entities, profile);
					CommDKP:GetTable(CommDKP_Profiles, true)[tempName] = profile;	-- RC-11: keyed by the raider, not the last guild row
					numPlayers = numPlayers + 1;
					c = CommDKP:GetCColors(tempClass)
					if addedUsers == nil then
						addedUsers = "|c"..c.hex..tempName.."|r"; 
					else
						addedUsers = addedUsers..", |c"..c.hex..tempName.."|r"
					end
					if CommDKP:GetTable(CommDKP_Archive, true)[tempName] and CommDKP:GetTable(CommDKP_Archive, true)[tempName].deleted then
						profile.dkp = CommDKP:GetTable(CommDKP_Archive, true)[tempName].dkp
						profile.lifetime_gained = CommDKP:GetTable(CommDKP_Archive, true)[tempName].lifetime_gained
						profile.lifetime_spent = CommDKP:GetTable(CommDKP_Archive, true)[tempName].lifetime_spent
						CommDKP:GetTable(CommDKP_Archive, true)[tempName].deleted = "Recovered"
						CommDKP:GetTable(CommDKP_Archive, true)[tempName].edited = curTime
						FlagRecovery = true
					end
				end
			end
		end
		if addedUsers then
			CommDKP:Print("["..CommDKP:GetTeamName(CommDKP:GetCurrentTeamIndex()).."] "..L["ADDED"].." "..numPlayers.." "..L["PLAYERS"]..": "..addedUsers)
		end
		if core.ClassGraph then
			CommDKP:ClassGraph_Update()
		else
			CommDKP:ClassGraph()
		end
		if FlagRecovery then 
			CommDKP:Print(L["YOUHAVERECOVERED"])
		end
		CommDKP:FilterDKPTable(core.currentSort, "reset")
		if numPlayers > 0 then
			CommDKP.Sync:SendData("CommDKPAddUsers", CopyTable(entities))
			if IsInGuild() and CommDKP.SendSeedData then CommDKP:SendSeedData() end
		end
		if addedSelf then CommDKP:QueueTalentSend("added") end
	else
		CommDKP:Print(L["NOPARTYORRAID"])
	end
end

local function AddGuildToDKPTable(rank, level)
	local guildSize = GetNumGuildMembers();
	local class, addedUsers, c, name, rankName, rankIndex, charLevel;
	local numPlayers = 0;
	local FlagRecovery = false
	local curTime = time()
	local entities = {}
	local metaIndex = CommDKP:BuildKnownMetaIndex()			-- AD-26.4.2 P1
	local addedSelf = false

	for i=1, guildSize do
		name,rankName,rankIndex,charLevel,_,_,_,_,_,_,class = GetGuildRosterInfo(i)
		name = CommDKP:StripRealm(name)			-- AD-9.5.4: realm suffix optional; nil while the roster refreshes
		if name then
		local search = CommDKP:Table_Search(CommDKP:GetTable(CommDKP_DKPTable, true), name)

		if not search and (level == nil or (charLevel or 0) >= level) and (rank == nil or rankIndex == rank) then
			local profile = CommDKP:GetDefaultEntity();

			profile.player=name;
			profile.class=class;
			profile.rank = rankIndex;
			profile.rankName = rankName;  -- AD-9.1 R7: the rank string, not the numeric filter
			CommDKP:HydratePlayerRow(profile, metaIndex)		-- AD-26.4.2 P1 (F7): before any insert
			if CommDKP:IsSelf(name) then addedSelf = true end

			tinsert(CommDKP:GetTable(CommDKP_DKPTable, true), profile);
			tinsert(entities, profile);
			CommDKP:GetTable(CommDKP_Profiles, true)[name] = profile;

			numPlayers = numPlayers + 1;
			c = CommDKP:GetCColors(class)
			if addedUsers == nil then
				addedUsers = "|c"..c.hex..name.."|r"; 
			else
				addedUsers = addedUsers..", |c"..c.hex..name.."|r"
			end
			if CommDKP:GetTable(CommDKP_Archive, true)[name] and CommDKP:GetTable(CommDKP_Archive, true)[name].deleted then
				profile.dkp = CommDKP:GetTable(CommDKP_Archive, true)[name].dkp
				profile.lifetime_gained = CommDKP:GetTable(CommDKP_Archive, true)[name].lifetime_gained
				profile.lifetime_spent = CommDKP:GetTable(CommDKP_Archive, true)[name].lifetime_spent
				CommDKP:GetTable(CommDKP_Archive, true)[name].deleted = "Recovered"
				CommDKP:GetTable(CommDKP_Archive, true)[name].edited = curTime
				FlagRecovery = true
			end
		end
		end -- if name
	end
	CommDKP:FilterDKPTable(core.currentSort, "reset")
	if addedUsers then
		CommDKP:Print("["..CommDKP:GetTeamName(CommDKP:GetCurrentTeamIndex()).."] "..L["ADDED"].." "..numPlayers.." "..L["PLAYERS"]..": "..addedUsers)
	end
	if FlagRecovery then 
		CommDKP:Print(L["YOUHAVERECOVERED"])
	end
	if core.ClassGraph then
		CommDKP:ClassGraph_Update()
	else
		CommDKP:ClassGraph()
	end
	if numPlayers > 0 then
		CommDKP.Sync:SendData("CommDKPAddUsers", CopyTable(entities))
	end
	if addedSelf then CommDKP:QueueTalentSend("added") end
end

local function AddTargetToDKPTable()
	local name = CommDKP:GetUnitFullName("target");  -- AD-10: Forever "First Last"
	if not name then return end
	local _,class = UnitClass("target");
	local c;
	local curTime = time()
	local entities = {}

	local search = CommDKP:Table_Search(CommDKP:GetTable(CommDKP_DKPTable, true), name)
	local profile = CommDKP:GetDefaultEntity();
	
	profile.player=name;
	profile.class=class;

	if not search then
		CommDKP:HydratePlayerRow(profile)					-- AD-26.4.2 P3: before the insert
		tinsert(CommDKP:GetTable(CommDKP_DKPTable, true), profile);
		tinsert(entities, profile);
		CommDKP:GetTable(CommDKP_Profiles, true)[name] = profile;

		CommDKP:FilterDKPTable(core.currentSort, "reset")
		c = CommDKP:GetCColors(class)
		CommDKP:Print("["..CommDKP:GetTeamName(CommDKP:GetCurrentTeamIndex()).."] "..L["ADDED"].." |c"..c.hex..name.."|r")

		if addedUsers == nil then
			addedUsers = "|c"..c.hex..name.."|r"; 
		else
			addedUsers = addedUsers..", |c"..c.hex..name.."|r"
		end


		if core.ClassGraph then
			CommDKP:ClassGraph_Update()
		else
			CommDKP:ClassGraph()
		end
		if CommDKP:GetTable(CommDKP_Archive, true)[name] and CommDKP:GetTable(CommDKP_Archive, true)[name].deleted then
			profile.dkp = CommDKP:GetTable(CommDKP_Archive, true)[name].dkp
			profile.lifetime_gained = CommDKP:GetTable(CommDKP_Archive, true)[name].lifetime_gained
			profile.lifetime_spent = CommDKP:GetTable(CommDKP_Archive, true)[name].lifetime_spent
			CommDKP:GetTable(CommDKP_Archive, true)[name].deleted = "Recovered"
			CommDKP:GetTable(CommDKP_Archive, true)[name].edited = curTime
			CommDKP:Print(L["YOUHAVERECOVERED"])
		end
		CommDKP.Sync:SendData("CommDKPAddUsers", CopyTable(entities))
		if IsInGuild() and CommDKP.SendSeedData then CommDKP:SendSeedData() end
		if CommDKP:IsSelf(name) then CommDKP:QueueTalentSend("added") end
	end
end

function CommDKP:CopyProfileToTeam(row, team)
	local entities = {};
	local copy = {};
	if #core.SelectedData > 1 then
		--Multiple Selections
		copy = CopyTable(core.SelectedData)
	else
		--Only Profile Selected
		tinsert(copy,core.WorkingTable[row])
	end

	for i=1, #copy do
		local profile = copy[i];
		local name = profile.player;

		local search = CommDKP:Table_Search(CommDKP:GetTable(CommDKP_DKPTable, true, team), name);

		if not search then
			profile.norecover = true;
			tinsert(entities, profile);
		end
	end

	if #entities > 0 then
		CommDKP:AddEntitiesToDKPTable(CopyTable(entities), team);
		CommDKP.Sync:SendData("CommDKPAddUsers", CopyTable(entities), nil, team);
	end
end

function CommDKP:AddEntitiesToDKPTable(entities, team)
	team = team or CommDKP:GetCurrentTeamIndex();
	local addedUsers;
	local numPlayers = 0;
	local curTime = time()
	local metaIndex = CommDKP:BuildKnownMetaIndex()			-- AD-26.4.2 P4
	local addedSelf = false

	for i=1, #entities do
		if type(entities[i]) == "table" then
			CommDKP:CachePlayerMeta(entities[i].player, {
				spec = entities[i].spec,
				roleData = not CommDKP:IsPlaceholderMeta("role", entities[i].role) and entities[i].spec or nil,
				version = entities[i].version,
				class = entities[i].class,
			}, true)		-- AD-34.6 (F-34.2): officer-relayed meta is fill-only
		end
		CommDKP:HydratePlayerRow(entities[i], metaIndex)		-- AD-26.4.2 P4 (F6): first statement, before Profiles/insert
		local name = entities[i].player;
		if CommDKP:IsSelf(name) then addedSelf = true end
		local class = entities[i].class;
		local profile = entities[i];
		local c;
	
		local search = CommDKP:Table_Search(CommDKP:GetTable(CommDKP_DKPTable, true, team), name)
	
		CommDKP:GetTable(CommDKP_Profiles, true, team)[name] = profile;

		if search then
			local row = CommDKP:GetTable(CommDKP_DKPTable, true, team)[search[1][1]]
			if type(row) == "table" and not CommDKP:IsSelf(name) then
				if CommDKP:IsPlaceholderMeta("spec", row.spec) and not CommDKP:IsPlaceholderMeta("spec", profile.spec) then row.spec = profile.spec end
				if CommDKP:IsPlaceholderMeta("role", row.role) and not CommDKP:IsPlaceholderMeta("role", profile.role) then row.role = profile.role end
				if CommDKP:IsPlaceholderMeta("version", row.version) and not CommDKP:IsPlaceholderMeta("version", profile.version) then row.version = profile.version end
				CommDKP:QueueRosterRedraw()
			end
		else
	
			numPlayers = numPlayers + 1;
			c = CommDKP:GetCColors(class)
			if addedUsers == nil then
				addedUsers = "|c"..c.hex..name.."|r"; 
			else
				addedUsers = addedUsers..", |c"..c.hex..name.."|r"
			end
			if profile.norecover then
				profile.norecover = nil;
			else
				if CommDKP:GetTable(CommDKP_Archive, true, team)[name] and CommDKP:GetTable(CommDKP_Archive, true, team)[name].deleted then
					profile.dkp = CommDKP:GetTable(CommDKP_Archive, true, team)[name].dkp
					profile.lifetime_gained = CommDKP:GetTable(CommDKP_Archive, true, team)[name].lifetime_gained
					profile.lifetime_spent = CommDKP:GetTable(CommDKP_Archive, true, team)[name].lifetime_spent
					CommDKP:GetTable(CommDKP_Archive, true, team)[name].deleted = "Recovered"
					CommDKP:GetTable(CommDKP_Archive, true, team)[name].edited = curTime
					FlagRecovery = true
				end
			end
			tinsert(CommDKP:GetTable(CommDKP_DKPTable, true, team), CopyTable(profile));
		end
	end
	if addedSelf then CommDKP:QueueTalentSend("added") end		-- AD-26.4.2 P4: BR-18.4(a)

	if numPlayers > 0  then
		CommDKP:FilterDKPTable(core.currentSort, "reset")
		if addedUsers then
			CommDKP:Print("["..CommDKP:GetTeamName(team).."] "..L["ADDED"].." "..numPlayers.." "..L["PLAYERS"]..": "..addedUsers)
		end
		if FlagRecovery then 
			CommDKP:Print(L["YOUHAVERECOVERED"])
		end
		if core.ClassGraph then
			CommDKP:ClassGraph_Update()
		else
			CommDKP:ClassGraph()
		end
	end
end


function CommDKP:GetGuildRankList()
	local numRanks = GuildControlGetNumRanks()
	local tempTable = {}
	for i=1, numRanks do
		table.insert(tempTable, {index = i-1, name = GuildControlGetRankName(i)})
		tempTable[GuildControlGetRankName(i)] = i-1
	end
	
	return tempTable;
end

-------
-- TEAM FUNCTIONS
-------

function CommDKP:ChangeTeamName(index, _name) 
	CommDKP:GetTable(CommDKP_DB, false)["teams"][tostring(index)].name = _name;
	CommDKP.Sync:SendData("CommDKPTeams", {Teams =  CommDKP:GetTable(CommDKP_DB, false)["teams"]} , nil)
end

function CommDKP:AddNewTeamToGuild() 
	local _index = 0
	local _tmp = CommDKP:GetTable(CommDKP_DB, false)["teams"]
	local realmName = CommDKP:GetRealmName();
	local guildName = CommDKP:GetGuildName();

	-- get the index of last team from CommDKP_DB
	for k,v in pairs(_tmp) do
		if(type(v) == "table") then
			_index = _index + 1
		end
	end

	-- add new team definition to CommDKP_DB with generic GuildName-index
	CommDKP:GetTable(CommDKP_DB, false)["teams"][tostring(_index)] = { ["name"] = guildName.."-"..tostring(_index)}

	------
	-- add new team with new "index" to all "team" tables in saved variables
	-- CommDKP_Loot, CommDKP_DKPTable, CommDKP_DKPHistory, CommDKP_MinBids, CommDKP_MaxBids, CommDKP_Standby, CommDKP_Archive
	------
		CommDKP:GetTable(CommDKP_Loot, false)[tostring(_index)] = {}
		CommDKP:GetTable(CommDKP_DKPTable, false)[tostring(_index)] = {}
		CommDKP:GetTable(CommDKP_DKPHistory, false)[tostring(_index)] = {}
		CommDKP:GetTable(CommDKP_MinBids, false)[tostring(_index)] = {}
		CommDKP:GetTable(CommDKP_MaxBids, false)[tostring(_index)] = {}
		CommDKP:GetTable(CommDKP_Standby, false)[tostring(_index)] = {}
		CommDKP:GetTable(CommDKP_Archive, false)[tostring(_index)] = {}

		CommDKP.Sync:SendData("CommDKPTeams", {Teams =  CommDKP:GetTable(CommDKP_DB, false)["teams"]} , nil)

	return tostring(_index)
end

-------
-- TEAM FUNCTIONS END
-------

function CommDKP:reset_prev_dkp(player)
	if player then
		local search = CommDKP:Table_Search(CommDKP:GetTable(CommDKP_DKPTable, true), player, "player")

		if search then
			CommDKP:GetTable(CommDKP_DKPTable, true)[search[1][1]].previous_dkp = CommDKP:GetTable(CommDKP_DKPTable, true)[search[1][1]].dkp
		end
	else
		for i=1, #CommDKP:GetTable(CommDKP_DKPTable, true) do
			CommDKP:GetTable(CommDKP_DKPTable, true)[i].previous_dkp = CommDKP:GetTable(CommDKP_DKPTable, true)[i].dkp
		end
	end
end

local function UpdateWhitelist()
	if #core.SelectedData > 0 then
		table.wipe(CommDKP:GetTable(CommDKP_Whitelist))
		for i=1, #core.SelectedData do
			local validate = CommDKP:ValidateSender(core.SelectedData[i].player)

			if not validate then
				StaticPopupDialogs["VALIDATE_OFFICER"] = {
					text = core.SelectedData[i].player.." "..L["NOTANOFFICER"],
					button1 = "Ok",
					timeout = 0,
					whileDead = true,
					hideOnEscape = true,
					preferredIndex = 3,
				}
				StaticPopup_Show ("VALIDATE_OFFICER")
				return;
			end
		end
		for i=1, #core.SelectedData do
			table.insert(CommDKP:GetTable(CommDKP_Whitelist), core.SelectedData[i].player)
		end

		local pname = CommDKP:GetPlayerName();
		local verifyLeadAdded = false
		for _, wlName in ipairs(CommDKP:GetTable(CommDKP_Whitelist)) do   -- AD-10.4.3: SamePlayer, not ==
			if CommDKP:SamePlayer(wlName, pname) then verifyLeadAdded = true; break end
		end

		if not verifyLeadAdded and pname then
			table.insert(CommDKP:GetTable(CommDKP_Whitelist), pname)		-- verifies leader is included in white list. Adds if they aren't
		end
	else
		table.wipe(CommDKP:GetTable(CommDKP_Whitelist))
	end
	CommDKP.Sync:SendData("CDKPWhitelist", CommDKP:GetTable(CommDKP_Whitelist))
	CommDKP:Print(L["WHITELISTBROADCASTED"])
end

local function ViewWhitelist()
	if #CommDKP:GetTable(CommDKP_Whitelist) > 0 then
		core.SelectedData = {}
		for i=1, #CommDKP:GetTable(CommDKP_Whitelist) do
			local search = CommDKP:Table_Search(CommDKP:GetTable(CommDKP_DKPTable, true), CommDKP:GetTable(CommDKP_Whitelist)[i])

			if search then
				table.insert(core.SelectedData, CommDKP:GetTable(CommDKP_DKPTable, true)[search[1][1]])
			end
		end
		CommDKP:FilterDKPTable(core.currentSort, "reset")
	end
end


---------------------------------------
-- Manage DKP TAB.Create()
---------------------------------------
-- AD-9.5.2: Guild Leader-only controls. Uses IsPlayerGuildLeader() (roster-independent), so it is
-- correct even while the guild roster is still empty; also refreshes the team header guild name.
local leaderHookInstalled = false
local function ApplyLeaderVisibility()
	local tab = CommDKP.ConfigTab3
	if not tab or not tab.WhitelistContainer then return end
	local controls = { tab.WhitelistContainer, tab.TeamHeader, tab.TeamListDropDown, tab.TeamNameInput, tab.TeamRename, tab.TeamAdd }
	local isLeader = CommDKP:IsPlayerGuildLeader()
	if tab.TeamHeader then
		tab.TeamHeader:SetText(L["TEAMMANAGEMENTHEADER"].." of "..CommDKP:GetGuildName())
	end
	for _, ctl in ipairs(controls) do
		if ctl then
			if isLeader then ctl:Show() else ctl:Hide() end
		end
	end
	if tab.LayoutWhitelistCard then tab.LayoutWhitelistCard() end   -- AD-21.3.1
end

function CommDKP:ManageEntries()

	local CheckLeader = CommDKP:IsPlayerGuildLeader()  -- AD-9.5.1 (click handlers re-check at click time)
	-- add raid to dkp table if they don't exist

	----------------------------------
	-- Header text above the buttons
	----------------------------------
		-- UX §12.3.4: the old AddEntriesHeader text is now the card title. Three 165 px button columns, 8 px gutter.
		local addCard = W.CreateCard(CommDKP.ConfigTab3, L["ADDREMDKPTABLEENTRIES"], 548, 131)
		addCard:SetPoint("TOPLEFT", CommDKP.ConfigTab3, "TOPLEFT", 0, 0)
		CommDKP.ConfigTab3.AddEntriesCard = addCard
		CommDKP.ConfigTab3.AddEntriesHeader = addCard.Header.Title
		local aBody = addCard.Body
		local function Slot(btn, col, row, tone)          -- col 1..3, row 1..3 inside the Add/Remove card body
			btn:SetParent(aBody)
			btn:SetSize(MANAGE_COL, W.H)
			btn:ClearAllPoints()
			btn:SetPoint("TOPLEFT", aBody, "TOPLEFT", W.PAD + (col - 1) * (MANAGE_COL + W.GUT), -10 - (row - 1) * 30)
			W.StyleButton(btn, tone)
		end

	----------------------------------
	-- add raid members button
	----------------------------------
		CommDKP.ConfigTab3.add_raid_to_table = self:CreateButton("TOPLEFT", CommDKP.ConfigTab3, "TOPLEFT", 30, -90, L["ADDRAIDMEMBERS"]);
		Slot(CommDKP.ConfigTab3.add_raid_to_table, 1, 1)

		-- tooltip for add raid members button
		CommDKP.ConfigTab3.add_raid_to_table:SetScript("OnEnter", 
			function(self)
				GameTooltip:SetOwner(self, "ANCHOR_RIGHT");
				GameTooltip:SetText(L["ADDRAIDMEMBERS"], 0.25, 0.75, 0.90, 1, true);
				GameTooltip:AddLine(L["ADDRAIDMEMBERSTTDESC"], 1.0, 1.0, 1.0, true);
				GameTooltip:Show();
			end
		)
		CommDKP.ConfigTab3.add_raid_to_table:SetScript("OnLeave", 
			function(self)
				GameTooltip:Hide()
			end
		)

		-- confirmation dialog to remove user(s)
		CommDKP.ConfigTab3.add_raid_to_table:SetScript("OnClick", 
			function ()
				local selected = L["ADDRAIDMEMBERSCONFIRM"];

				StaticPopupDialogs["ADD_RAID_ENTRIES"] = {
				text = selected,
				button1 = L["YES"],
				button2 = L["NO"],
				OnAccept = function()
					AddRaidToDKPTable()
				end,
				timeout = 0,
				whileDead = true,
				hideOnEscape = true,
				preferredIndex = 3,
				}
				StaticPopup_Show ("ADD_RAID_ENTRIES")
			end
		);


	
	----------------------------------
	-- remove selected entries button
	----------------------------------
		CommDKP.ConfigTab3.remove_entries = self:CreateButton("TOPLEFT", CommDKP.ConfigTab3, "TOPLEFT", 170, -60, L["REMOVEENTRIES"]);
		Slot(CommDKP.ConfigTab3.remove_entries, 3, 1, "caution")
		CommDKP.ConfigTab3.remove_entries:SetScript("OnEnter", 
			function(self)
				GameTooltip:SetOwner(self, "ANCHOR_RIGHT");
				GameTooltip:SetText(L["REMOVESELECTEDENTRIES"], 0.25, 0.75, 0.90, 1, true);
				GameTooltip:AddLine(L["REMSELENTRIESTTDESC"], 1.0, 1.0, 1.0, true);
				GameTooltip:AddLine(L["REMSELENTRIESTTWARN"], 1.0, 0, 0, true);
				GameTooltip:Show();
			end
		)
		CommDKP.ConfigTab3.remove_entries:SetScript("OnLeave", 
			function(self)
				GameTooltip:Hide()
			end
		)
		-- confirmation dialog to remove user(s)
		CommDKP.ConfigTab3.remove_entries:SetScript("OnClick", 
			function ()	
				if #core.SelectedData > 0 then
					local selected = L["CONFIRMREMOVESELECT"]..": \n\n";

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
					selected = selected.."?"

					StaticPopupDialogs["REMOVE_ENTRIES"] = {
					text = selected,
					button1 = L["YES"],
					button2 = L["NO"],
					OnAccept = function()
						Remove_Entries()
					end,
					timeout = 0,
					whileDead = true,
					hideOnEscape = true,
					preferredIndex = 3,
					}
					StaticPopup_Show ("REMOVE_ENTRIES")
				else
					CommDKP:Print(L["NOENTRIESSELECTED"])
				end
			end
		);
	----------------------------------
	-- Reset previous DKP button -- number showing how much a player has gained or lost since last clear
	----------------------------------
		CommDKP.ConfigTab3.reset_previous_dkp = self:CreateButton("TOPLEFT", CommDKP.ConfigTab3, "TOPLEFT", 310, -60, L["RESETPREVIOUS"]);
		Slot(CommDKP.ConfigTab3.reset_previous_dkp, 3, 2, "caution")
		CommDKP.ConfigTab3.reset_previous_dkp:SetScript("OnEnter",
			function(self)
				GameTooltip:SetOwner(self, "ANCHOR_RIGHT");
				GameTooltip:SetText(L["RESETPREVDKP"], 0.25, 0.75, 0.90, 1, true);
				GameTooltip:AddLine(L["RESETPREVDKPTTDESC"], 1.0, 1.0, 1.0, true);
				GameTooltip:AddLine(L["RESETPREVDKPTTWARN"], 1.0, 0, 0, true);
				GameTooltip:Show();
			end
		)
		CommDKP.ConfigTab3.reset_previous_dkp:SetScript("OnLeave", 
			function(self)
				GameTooltip:Hide()
			end
		)
		-- confirmation dialog to remove user(s)
		CommDKP.ConfigTab3.reset_previous_dkp:SetScript("OnClick",
			function ()	
				StaticPopupDialogs["RESET_PREVIOUS_DKP"] = {
					text = L["RESETPREVCONFIRM"],
					button1 = L["YES"],
					button2 = L["NO"],
					OnAccept = function()
						CommDKP:reset_prev_dkp()
					end,
					timeout = 0,
					whileDead = true,
					hideOnEscape = true,
					preferredIndex = 3,
				}
				StaticPopup_Show ("RESET_PREVIOUS_DKP")
			end
		);

	local curIndex;
	local curRank;

	----------------------------------
	-- rank select dropDownMenu
	----------------------------------
		CommDKP.ConfigTab3.GuildRankDropDown = DD:Create_UIDropDownMenu("CommDKPConfigReasonDropDown", aBody);
		CommDKP.ConfigTab3.GuildRankDropDown:SetPoint("TOPLEFT", aBody, "TOPLEFT", W.PAD, -40)
		CommDKP.ConfigTab3.GuildRankDropDown:SetScript("OnEnter", 
			function(self)
				GameTooltip:SetOwner(self, "ANCHOR_RIGHT");
				GameTooltip:SetText(L["RANKLIST"], 0.25, 0.75, 0.90, 1, true);
				GameTooltip:AddLine(L["RANKLISTTTDESC"], 1.0, 1.0, 1.0, true);
				GameTooltip:Show();
			end
		)
		CommDKP.ConfigTab3.GuildRankDropDown:SetScript("OnLeave",
			function(self)
				GameTooltip:Hide()
			end
		)
		DD:UIDropDownMenu_SetWidth(CommDKP.ConfigTab3.GuildRankDropDown, MANAGE_COL)
		DD:UIDropDownMenu_SetText(CommDKP.ConfigTab3.GuildRankDropDown, "Select Rank")

		-- Create and bind the initialization function to the dropdown menu
			DD:UIDropDownMenu_Initialize(CommDKP.ConfigTab3.GuildRankDropDown, 
			function(self, level, menuList)
				
				local rank = DD:UIDropDownMenu_CreateInfo()
					rank.func = self.SetValue

					local rankList = CommDKP:GetGuildRankList()

					for i=1, #rankList do
						rank.text, rank.arg1, rank.arg2, rank.checked, rank.isNotRadio = rankList[i].name, rankList[i].name, rankList[i].index, rankList[i].name == curRank, true
						DD:UIDropDownMenu_AddButton(rank)
					end
			end
		)

		-- Dropdown Menu Function
		function CommDKP.ConfigTab3.GuildRankDropDown:SetValue(arg1, arg2)
			if curRank ~= arg1 then
				curRank = arg1
				curIndex = arg2
				DD:UIDropDownMenu_SetText(CommDKP.ConfigTab3.GuildRankDropDown, arg1)
			else
				curRank = nil
				curIndex = nil
				DD:UIDropDownMenu_SetText(CommDKP.ConfigTab3.GuildRankDropDown, L["SELECTRANK"])
			end

			LibDD:CloseDropDownMenus()
		end

	----------------------------------
	-- Add Guild to DKP Table Button
	----------------------------------
		CommDKP.ConfigTab3.AddGuildToDKP = self:CreateButton("TOPLEFT", CommDKP.ConfigTab3, "TOPLEFT", 0, 0, L["ADDGUILDMEMBERS"]);
		Slot(CommDKP.ConfigTab3.AddGuildToDKP, 2, 2)
		CommDKP.ConfigTab3.AddGuildToDKP:SetScript("OnEnter", 
			function(self)
				GameTooltip:SetOwner(self, "ANCHOR_RIGHT");
				GameTooltip:SetText(L["ADDGUILDDKPTABLE"], 0.25, 0.75, 0.90, 1, true);
				GameTooltip:AddLine(L["ADDGUILDDKPTABLETT"], 1.0, 1.0, 1.0, true);
				GameTooltip:Show();
			end
		)
		CommDKP.ConfigTab3.AddGuildToDKP:SetScript("OnLeave", 
			function(self)
				GameTooltip:Hide()
			end
		)
		-- confirmation dialog to add user(s)
		CommDKP.ConfigTab3.AddGuildToDKP:SetScript("OnClick",
			function ()	
				if curIndex ~= nil then
					StaticPopupDialogs["ADD_GUILD_MEMBERS"] = {
						text = L["ADDGUILDCONFIRM"].." \""..curRank.."\"?",
						button1 = L["YES"],
						button2 = L["NO"],
						OnAccept = function()
							AddGuildToDKPTable(curIndex)
						end,
						timeout = 0,
						whileDead = true,
						hideOnEscape = true,
						preferredIndex = 3,
					}
					StaticPopup_Show ("ADD_GUILD_MEMBERS")
				else
					StaticPopupDialogs["ADD_GUILD_MEMBERS"] = {
						text = L["NORANKSELECTED"],
						button1 = L["OK"],
						timeout = 0,
						whileDead = true,
						hideOnEscape = true,
						preferredIndex = 3,
					}
					StaticPopup_Show ("ADD_GUILD_MEMBERS")
				end
			end
		);

	----------------------------------
	-- Add target to DKP list button
	----------------------------------	
		CommDKP.ConfigTab3.AddTargetToDKP = self:CreateButton("TOPLEFT", CommDKP.ConfigTab3, "TOPLEFT", 0, 0, L["ADDTARGET"]);
		Slot(CommDKP.ConfigTab3.AddTargetToDKP, 2, 1)
		CommDKP.ConfigTab3.AddTargetToDKP:SetScript("OnEnter", 
			function(self)
				GameTooltip:SetOwner(self, "ANCHOR_RIGHT");
				GameTooltip:SetText(L["ADDTARGETTODKPTABLE"], 0.25, 0.75, 0.90, 1, true);
				GameTooltip:AddLine(L["ADDTARGETTTDESC"], 1.0, 1.0, 1.0, true);
				GameTooltip:Show();
			end
		)
		CommDKP.ConfigTab3.AddTargetToDKP:SetScript("OnLeave",
			function(self)
				GameTooltip:Hide()
			end
		)
		CommDKP.ConfigTab3.AddTargetToDKP:SetScript("OnClick", 
			function ()	-- confirmation dialog to add user(s)
				if UnitIsPlayer("target") == true then
					StaticPopupDialogs["ADD_TARGET_DKP"] = {
						text = L["CONFIRMADDTARGET"].." "..(CommDKP:GetUnitFullName("target") or "").." "..L["TODKPLIST"],
						button1 = L["YES"],
						button2 = L["NO"],
						OnAccept = function()
							AddTargetToDKPTable()
						end,
						timeout = 0,
						whileDead = true,
						hideOnEscape = true,
						preferredIndex = 3,
					}
					StaticPopup_Show ("ADD_TARGET_DKP")
				else
					StaticPopupDialogs["ADD_TARGET_DKP"] = {
						text = L["NOPLAYERTARGETED"],
						button1 = L["OK"],
						timeout = 0,
						whileDead = true,
						hideOnEscape = true,
						preferredIndex = 3,
					}
					StaticPopup_Show ("ADD_TARGET_DKP")
				end
			end
		);

	----------------------------------
	-- Purge DKP list button
	----------------------------------
		CommDKP.ConfigTab3.CleanList = self:CreateButton("TOPLEFT", CommDKP.ConfigTab3, "TOPLEFT", 0, 0, L["PURGELIST"]);
		Slot(CommDKP.ConfigTab3.CleanList, 3, 3, "caution")
		CommDKP.ConfigTab3.CleanList:SetScript("OnEnter", 
			function(self)
				GameTooltip:SetOwner(self, "ANCHOR_RIGHT");
				GameTooltip:SetText(L["PURGELIST"], 0.25, 0.75, 0.90, 1, true);
				GameTooltip:AddLine(L["PURGELISTTTDESC"], 1.0, 1.0, 1.0, true);
				GameTooltip:Show();
			end
		)
		CommDKP.ConfigTab3.CleanList:SetScript("OnLeave", 
			function(self)
				GameTooltip:Hide()
			end
		)
		CommDKP.ConfigTab3.CleanList:SetScript("OnClick", 
			function()
				StaticPopupDialogs["PURGE_CONFIRM"] = {
					text = L["PURGECONFIRM"],
					button1 = L["YES"],
					button2 = L["NO"],
					OnAccept = function()
						local purgeString, c, name;
						local count = 0;
						local i = 1;

						while i <= #CommDKP:GetTable(CommDKP_DKPTable, true) do
							local search = CommDKP:TableStrFind(CommDKP:GetTable(CommDKP_DKPHistory, true), CommDKP:GetTable(CommDKP_DKPTable, true)[i].player, "players")

							if CommDKP:GetTable(CommDKP_DKPTable, true)[i].dkp == 0 and not search then
								c = CommDKP:GetCColors(CommDKP:GetTable(CommDKP_DKPTable, true)[i].class)
								name = CommDKP:GetTable(CommDKP_DKPTable, true)[i].player;

								if purgeString == nil then
									purgeString = "|c"..c.hex..name.."|r"; 
								else
									purgeString = purgeString..", |c"..c.hex..name.."|r"
								end

								count = count + 1;
								table.remove(CommDKP:GetTable(CommDKP_DKPTable, true), i)
							else
								i=i+1;
							end
						end
						if count > 0 then
							CommDKP:Print(L["PURGELIST"].." ("..count.."):")
							CommDKP:Print(purgeString)
							CommDKP:FilterDKPTable(core.currentSort, "reset")
						end
					end,
					timeout = 0,
					whileDead = true,
					hideOnEscape = true,
					preferredIndex = 3,
				}
				StaticPopup_Show ("PURGE_CONFIRM")
			end
		)

	----------------------------------
	-- White list container
	----------------------------------

		-- UX §12.3.4: WhitelistContainer IS the card (key kept; leader-only Show/Hide unchanged). Title = first line of
		-- WHITELISTHEADER (color code stripped), "(Leader Only) (Alpha)" is the header note, the rest a caption
		-- (full caption; card fits it (AD-21.3.1)).
		local wlFull = L["WHITELISTHEADER"]
		local wlFirst, wlRest = wlFull:match("^(.-)\n\n(.*)$")
		wlFirst, wlRest = wlFirst or wlFull, wlRest or ""
		local wlTitle, wlNote = wlFirst:match("^(.-)%s*|[cC]%x%x%x%x%x%x%x%x(.-)|r")
		wlTitle, wlNote = wlTitle or wlFirst, wlNote or ""
		CommDKP.ConfigTab3.WhitelistContainer = W.CreateCard(CommDKP.ConfigTab3, wlTitle, 548, 140, { note = wlNote });
		CommDKP.ConfigTab3.WhitelistContainer:SetPoint("TOPLEFT", CommDKP.ConfigTab3, "TOPLEFT", 0, -139)
		local wBody = CommDKP.ConfigTab3.WhitelistContainer.Body

		-- Whitelist Header (the paragraph caption)
		CommDKP.ConfigTab3.WhitelistContainer.WhitelistHeader = W.CreateCaption(wBody, wlRest, 4)
		CommDKP.ConfigTab3.WhitelistContainer.WhitelistHeader:SetPoint("TOPLEFT", wBody, "TOPLEFT", W.PAD, -8);
		CommDKP.ConfigTab3.WhitelistContainer.WhitelistHeader:SetWidth(548 - 6 - 2 * W.PAD)
		CommDKP.ConfigTab3.WhitelistContainer:EnableMouse(true)
		CommDKP.ConfigTab3.WhitelistContainer:SetScript("OnEnter", function(self)
			GameTooltip:SetOwner(self, "ANCHOR_RIGHT");
			GameTooltip:SetText(wlTitle, 1, 0.82, 0, 1, true);
			GameTooltip:AddLine(wlRest, 1.0, 1.0, 1.0, true);
			GameTooltip:Show();
		end)
		CommDKP.ConfigTab3.WhitelistContainer:SetScript("OnLeave", function() GameTooltip:Hide() end)
		local function WLSlot(btn, col)
			btn:SetParent(wBody)
			btn:SetSize(MANAGE_COL, W.H)
			btn:ClearAllPoints()
			btn:SetPoint("BOTTOMLEFT", wBody, "BOTTOMLEFT", W.PAD + (col - 1) * (MANAGE_COL + W.GUT), 10)
			W.StyleButton(btn)
		end

		-- Whitelist button
		CommDKP.ConfigTab3.WhitelistContainer.AddWhitelistButton = self:CreateButton("BOTTOMLEFT", CommDKP.ConfigTab3.WhitelistContainer, "BOTTOMLEFT", 15, 15, L["SETWHITELIST"]);
		WLSlot(CommDKP.ConfigTab3.WhitelistContainer.AddWhitelistButton, 1)
		CommDKP.ConfigTab3.WhitelistContainer.AddWhitelistButton:SetScript("OnEnter", 
			function(self)
				GameTooltip:SetOwner(self, "ANCHOR_RIGHT");
				GameTooltip:SetText(L["SETWHITELIST"], 0.25, 0.75, 0.90, 1, true);
				GameTooltip:AddLine(L["SETWHITELISTTTDESC1"], 1.0, 1.0, 1.0, true);
				GameTooltip:AddLine(L["SETWHITELISTTTDESC2"], 0.2, 1.0, 0.2, true);
				GameTooltip:AddLine(L["SETWHITELISTTTWARN"], 1.0, 0, 0, true);
				GameTooltip:Show();
			end
		)
		CommDKP.ConfigTab3.WhitelistContainer.AddWhitelistButton:SetScript("OnLeave", 
			function(self)
				GameTooltip:Hide()
			end
		)
		-- confirmation dialog to add user(s)
		CommDKP.ConfigTab3.WhitelistContainer.AddWhitelistButton:SetScript("OnClick", 
			function ()	
				if #core.SelectedData > 0 then
					StaticPopupDialogs["ADD_GUILD_MEMBERS"] = {
						text = L["CONFIRMWHITELIST"],
						button1 = L["YES"],
						button2 = L["NO"],
						OnAccept = function()
							UpdateWhitelist()
						end,
						timeout = 0,
						whileDead = true,
						hideOnEscape = true,
						preferredIndex = 3,
					}
					StaticPopup_Show ("ADD_GUILD_MEMBERS")
				else
					StaticPopupDialogs["ADD_GUILD_MEMBERS"] = {
						text = L["CONFIRMWHITELISTCLEAR"],
						button1 = L["YES"],
						button2 = L["NO"],
						OnAccept = function()
							UpdateWhitelist()
						end,
						timeout = 0,
						whileDead = true,
						hideOnEscape = true,
						preferredIndex = 3,
					}
					StaticPopup_Show ("ADD_GUILD_MEMBERS")
				end
			end
		);

			----------------------------------
			-- View Whitelist Button
			----------------------------------
		
				CommDKP.ConfigTab3.WhitelistContainer.ViewWhitelistButton = self:CreateButton("BOTTOMLEFT", CommDKP.ConfigTab3.WhitelistContainer, "BOTTOMLEFT", 15, 15, L["VIEWWHITELISTBTN"]);
				WLSlot(CommDKP.ConfigTab3.WhitelistContainer.ViewWhitelistButton, 2)
				CommDKP.ConfigTab3.WhitelistContainer.ViewWhitelistButton:SetScript("OnEnter",
					function(self)
						GameTooltip:SetOwner(self, "ANCHOR_RIGHT");
						GameTooltip:SetText(L["VIEWWHITELISTBTN"], 0.25, 0.75, 0.90, 1, true);
						GameTooltip:AddLine(L["VIEWWHITELISTTTDESC"], 1.0, 1.0, 1.0, true);
						GameTooltip:Show();
					end
				)
				CommDKP.ConfigTab3.WhitelistContainer.ViewWhitelistButton:SetScript("OnLeave", 
					function(self)
						GameTooltip:Hide()
					end
				)
				CommDKP.ConfigTab3.WhitelistContainer.ViewWhitelistButton:SetScript("OnClick", 
					function ()	-- confirmation dialog to add user(s)
						if #CommDKP:GetTable(CommDKP_Whitelist) > 0 then
							ViewWhitelist()
						else
							StaticPopupDialogs["ADD_GUILD_MEMBERS"] = {
								text = L["WHITELISTEMPTY"],
								button1 = L["OK"],
								timeout = 0,
								whileDead = true,
								hideOnEscape = true,
								preferredIndex = 3
							}
							StaticPopup_Show ("ADD_GUILD_MEMBERS")
						end
					end
				);

			----------------------------------
			-- Broadcast Whitelist Button
			----------------------------------
		
				CommDKP.ConfigTab3.WhitelistContainer.SendWhitelistButton = self:CreateButton("BOTTOMLEFT", CommDKP.ConfigTab3.WhitelistContainer, "BOTTOMLEFT", 15, 15, L["SENDWHITELIST"]);
				WLSlot(CommDKP.ConfigTab3.WhitelistContainer.SendWhitelistButton, 3)
				CommDKP.ConfigTab3.WhitelistContainer.SendWhitelistButton:SetScript("OnEnter", 
					function(self)
						GameTooltip:SetOwner(self, "ANCHOR_RIGHT");
						GameTooltip:SetText(L["SENDWHITELIST"], 0.25, 0.75, 0.90, 1, true);
						GameTooltip:AddLine(L["SENDWHITELISTTTDESC"], 1.0, 1.0, 1.0, true);
						GameTooltip:AddLine(L["SENDWHITELISTTTWARN"], 1.0, 0, 0, true);
						GameTooltip:Show();
					end
				)
				CommDKP.ConfigTab3.WhitelistContainer.SendWhitelistButton:SetScript("OnLeave",
					function(self)
						GameTooltip:Hide()
					end
				)
				-- confirmation dialog to add user(s)
				CommDKP.ConfigTab3.WhitelistContainer.SendWhitelistButton:SetScript("OnClick",
					function ()	
						CommDKP.Sync:SendData("CDKPWhitelist", CommDKP:GetTable(CommDKP_Whitelist))
						CommDKP:Print(L["WHITELISTBROADCASTED"])
					end
				);

		

	----------------------------------
	-- Guild team management section
	----------------------------------

	local selectedTeam;
	local selectedTeamIndex;

		----------------------------------
		-- Teams Header
		----------------------------------
		-- UX §12.3.4: Teams card. TeamHeader now points at the card (the leader-only Show/Hide covers the whole card);
		-- its SetText writes the header note, so ApplyLeaderVisibility's TEAMMANAGEMENTHEADER text renders as today.
		CommDKP.ConfigTab3.TeamHeader = W.CreateCard(CommDKP.ConfigTab3, L["TEAMS"], 548, 195)
		CommDKP.ConfigTab3.TeamHeader:SetPoint("TOPLEFT", CommDKP.ConfigTab3, "TOPLEFT", 0, -287);
		function CommDKP.ConfigTab3.TeamHeader:SetText(s) self:SetNote(s) end
		CommDKP.ConfigTab3.TeamHeader:SetText(L["TEAMMANAGEMENTHEADER"].." of "..CommDKP:GetGuildName().."");
		local tBody = CommDKP.ConfigTab3.TeamHeader.Body
		CommDKP.ConfigTab3.TeamHeader.TeamLabel = W.CreateText(tBody, "label", L["TEAM"], "LEFT")
		CommDKP.ConfigTab3.TeamHeader.TeamLabel:SetPoint("TOPLEFT", tBody, "TOPLEFT", W.PAD, -10)
		CommDKP.ConfigTab3.TeamHeader.NameLabel = W.CreateText(tBody, "label", L["TEAMNAMEINPUTTOOLTIP"], "LEFT")
		CommDKP.ConfigTab3.TeamHeader.NameLabel:SetPoint("TOPLEFT", tBody, "TOPLEFT", W.PAD + 200 + W.GUT, -10)

		----------------------------------
		-- Drop down with lists of teams 
		----------------------------------
			CommDKP.ConfigTab3.TeamListDropDown = DD:Create_UIDropDownMenu("CommDKPConfigReasonDropDown", tBody);
			CommDKP.ConfigTab3.TeamListDropDown:SetPoint("TOPLEFT", tBody, "TOPLEFT", W.PAD, -26)
			-- tooltip on mouseOver
			CommDKP.ConfigTab3.TeamListDropDown:SetScript("OnEnter", 
				function(self) 
					GameTooltip:SetOwner(self, "ANCHOR_RIGHT");
					GameTooltip:SetText(L["TEAMLIST"], 0.25, 0.75, 0.90, 1, true);
					GameTooltip:AddLine(L["TEAMLISTDESC"], 1.0, 1.0, 1.0, true);
					GameTooltip:Show();
				end
			)
			CommDKP.ConfigTab3.TeamListDropDown:SetScript("OnLeave",
				function(self)
					GameTooltip:Hide()
				end
			)
			DD:UIDropDownMenu_SetWidth(CommDKP.ConfigTab3.TeamListDropDown, 200)
			DD:UIDropDownMenu_SetText(CommDKP.ConfigTab3.TeamListDropDown, L["TEAMSELECT"])

			-- Create and bind the initialization function to the dropdown menu
				DD:UIDropDownMenu_Initialize(CommDKP.ConfigTab3.TeamListDropDown, 
				function(self, level, menuList)
					
					local dropDownMenuItem = DD:UIDropDownMenu_CreateInfo()
					dropDownMenuItem.func = self.SetValue

					teamList = CommDKP:GetGuildTeamList()

					for i=1, #teamList do
						dropDownMenuItem.text = teamList[i][2]
						dropDownMenuItem.arg1 = teamList[i][2]
						dropDownMenuItem.arg2 = teamList[i][1]
						dropDownMenuItem.checked = teamList[i][1] == selectedTeamIndex
						dropDownMenuItem.isNotRadio = true
						DD:UIDropDownMenu_AddButton(dropDownMenuItem)
					end
				end
			)

			-- Dropdown Menu on SetValue()
			function CommDKP.ConfigTab3.TeamListDropDown:SetValue(arg1, arg2)
				if selectedTeamIndex ~= arg2 then
					selectedTeam = arg1
					selectedTeamIndex = arg2
					DD:UIDropDownMenu_SetText(CommDKP.ConfigTab3.TeamListDropDown, arg1)
					CommDKP.ConfigTab3.TeamNameInput:SetText(arg1)
				else
					selectedTeam = nil
					selectedTeamIndex = nil
					CommDKP.ConfigTab3.TeamNameInput:SetText("")
					DD:UIDropDownMenu_SetText(CommDKP.ConfigTab3.TeamListDropDown, L["TEAMSELECT"])
				end

				LibDD:CloseDropDownMenus()
			end

		----------------------------------
		-- Team name input box
		----------------------------------
			CommDKP.ConfigTab3.TeamNameInput = CreateFrame("EditBox", nil, tBody)

			CommDKP.ConfigTab3.TeamNameInput:SetAutoFocus(false)
			CommDKP.ConfigTab3.TeamNameInput:SetMultiLine(false)
			CommDKP.ConfigTab3.TeamNameInput:SetSize(180, W.H)
			CommDKP.ConfigTab3.TeamNameInput:SetPoint("TOPLEFT", tBody, "TOPLEFT", W.PAD + 200 + W.GUT, -26)
			CommDKP.ConfigTab3.TeamNameInput.tooltipText = L["TEAMNAMEINPUTTOOLTIP"]
			CommDKP.ConfigTab3.TeamNameInput.tooltipDescription = L["TEAMNAMEINPUTTOOLTIPDESC"]
			CommDKP.ConfigTab3.TeamNameInput:SetScript("OnEscapePressed", 
				function(self)    -- clears focus on esc
					self:HighlightText(0,0)
					self:ClearFocus()
				end
			)
			CommDKP.ConfigTab3.TeamNameInput:SetScript("OnEnterPressed", 
				function(self)
					self:HighlightText(0,0)
					if (selectedTeamIndex == nil ) then
						StaticPopupDialogs["RENAME_TEAM"] = {
							text = L["NOTEAMCHOSEN"],
							button1 = L["OK"],
							timeout = 0,
							whileDead = true,
							hideOnEscape = true,
							preferredIndex = 3
						}
						StaticPopup_Show ("RENAME_TEAM")
					else
						CommDKP:ChangeTeamName(selectedTeamIndex, self:GetText())
						-- if we are performing name change on currently selected team, change main team view dropdown Text
						if tonumber(CommDKP:GetCurrentTeamIndex()) == selectedTeamIndex then
							DD:UIDropDownMenu_SetText(CommDKP.UIConfig.TeamViewChangerDropDown, self:SetText(""))
						end
						DD:UIDropDownMenu_SetText(CommDKP.ConfigTab3.TeamListDropDown, L["TEAMSELECT"])
						selectedTeam = nil
						selectedTeamIndex = nil
						LibDD:CloseDropDownMenus()
						self:ClearFocus()
						self:SetText("")
					end
				end
			)
			CommDKP.ConfigTab3.TeamNameInput:SetScript("OnEnter", 
				function(self)
					if (self.tooltipText) then
						GameTooltip:SetOwner(self, "ANCHOR_RIGHT");
						GameTooltip:SetText(self.tooltipText, 0.25, 0.75, 0.90, 1, true);
					end
					if (self.tooltipDescription) then
						GameTooltip:AddLine(self.tooltipDescription, 1.0, 1.0, 1.0, true);
						GameTooltip:Show();
					end
					if (self.tooltipWarning) then
						GameTooltip:AddLine(self.tooltipWarning, 1.0, 0, 0, true);
						GameTooltip:Show();
					end
				end
			)
			CommDKP.ConfigTab3.TeamNameInput:SetScript("OnLeave",
				function(self)
					GameTooltip:Hide()
				end
			)
			W.StyleEditBox(CommDKP.ConfigTab3.TeamNameInput, { align = "LEFT" })   -- after its own SetScripts: kit hooks chain on

			

		----------------------------------
		-- Rename selected team button
		----------------------------------	
			CommDKP.ConfigTab3.TeamRename = self:CreateButton("TOPLEFT", CommDKP.ConfigTab3, "TOPLEFT", 0, 0, L["TEAMRENAME"]);
			CommDKP.ConfigTab3.TeamRename:SetParent(tBody)
			CommDKP.ConfigTab3.TeamRename:SetSize(126, W.H);
			CommDKP.ConfigTab3.TeamRename:ClearAllPoints()
			CommDKP.ConfigTab3.TeamRename:SetPoint("LEFT", CommDKP.ConfigTab3.TeamNameInput, "RIGHT", W.GUT, 0)
			W.StyleButton(CommDKP.ConfigTab3.TeamRename)
			CommDKP.ConfigTab3.TeamRename:SetScript("OnEnter", 
				function(self)
					GameTooltip:SetOwner(self, "ANCHOR_RIGHT");
					GameTooltip:SetText(L["TEAMRENAMESELECTED"], 0.25, 0.75, 0.90, 1, true);
					GameTooltip:AddLine(L["TEAMRENAMESELECTEDESC"], 1.0, 1.0, 1.0, true);
					GameTooltip:Show();
				end
			)
			CommDKP.ConfigTab3.TeamRename:SetScript("OnLeave",
				function(self)
					GameTooltip:Hide()
				end
			)
			-- rename team function
			CommDKP.ConfigTab3.TeamRename:SetScript("OnClick", 
				function ()	
					if selectedTeamIndex == nil then
						StaticPopupDialogs["RENAME_TEAM"] = {
							text = L["NOTEAMCHOSEN"],
							button1 = L["OK"],
							timeout = 0,
							whileDead = true,
							hideOnEscape = true,
							preferredIndex = 3
						}
						StaticPopup_Show ("RENAME_TEAM")
					else
						if CommDKP:IsPlayerGuildLeader() then
							CommDKP:ChangeTeamName(selectedTeamIndex, CommDKP.ConfigTab3.TeamNameInput:GetText())
							-- if we are performing name change on currently selected team, change main team view dropdown Text
							if tonumber(CommDKP:GetCurrentTeamIndex()) == selectedTeamIndex then
								DD:UIDropDownMenu_SetText(CommDKP.UIConfig.TeamViewChangerDropDown, CommDKP.ConfigTab3.TeamNameInput:GetText())
							end
							CommDKP.ConfigTab3.TeamNameInput:SetText("")
							DD:UIDropDownMenu_SetText(CommDKP.ConfigTab3.TeamListDropDown, L["TEAMSELECT"])
							selectedTeam = nil
							selectedTeamIndex = nil
							LibDD:CloseDropDownMenus()
						else
							StaticPopupDialogs["NOT_GUILD_MASTER"] = {
								text = L["NOTGUILDMASTER"],
								button1 = L["OK"],
								timeout = 0,
								whileDead = true,
								hideOnEscape = true,
								preferredIndex = 3
							}
							StaticPopup_Show ("NOT_GUILD_MASTER")	
						end
					end
				end
			);

		----------------------------------
		-- Add new team button
		----------------------------------	
		CommDKP.ConfigTab3.TeamAdd = self:CreateButton("TOPLEFT", CommDKP.ConfigTab3, "TOPLEFT", 0, 0, L["TEAMADD"]);
		CommDKP.ConfigTab3.TeamAdd:SetParent(CommDKP.ConfigTab3.TeamHeader.Body)
		CommDKP.ConfigTab3.TeamAdd:SetSize(MANAGE_COL, W.H);
		CommDKP.ConfigTab3.TeamAdd:ClearAllPoints()
		CommDKP.ConfigTab3.TeamAdd:SetPoint("TOPLEFT", CommDKP.ConfigTab3.TeamHeader.Body, "TOPLEFT", W.PAD, -62)
		W.StyleButton(CommDKP.ConfigTab3.TeamAdd)
		CommDKP.ConfigTab3.TeamAdd:SetScript("OnEnter", 
			function(self)
				GameTooltip:SetOwner(self, "ANCHOR_RIGHT");
				GameTooltip:SetText(L["TEAMADD"], 0.25, 0.75, 0.90, 1, true);
				GameTooltip:AddLine(L["TEAMADDDESC"], 1.0, 1.0, 1.0, true);
				GameTooltip:Show();
			end
		)
		CommDKP.ConfigTab3.TeamAdd:SetScript("OnLeave",
			function(self)
				GameTooltip:Hide()
			end
		)
		-- rename team function
		CommDKP.ConfigTab3.TeamAdd:SetScript("OnClick", 
			function ()	
				if CommDKP:IsPlayerGuildLeader() then
					StaticPopupDialogs["ADD_TEAM"] = {
						text = L["TEAMADDDIALOG"],
						button1 = L["YES"],
						button2 = L["NO"],
						OnAccept = function()
							CommDKP:AddNewTeamToGuild()
							CommDKP.ConfigTab3.TeamNameInput:SetText("")
							DD:UIDropDownMenu_SetText(CommDKP.ConfigTab3.TeamListDropDown, L["TEAMSELECT"])
							LibDD:CloseDropDownMenus()
						end,
						timeout = 0,
						whileDead = true,
						hideOnEscape = true,
						preferredIndex = 3
					}
					StaticPopup_Show ("ADD_TEAM")	
				else
					StaticPopupDialogs["NOT_GUILD_MASTER"] = {
						text = L["NOTGUILDMASTER"],
						button1 = L["OK"],
						timeout = 0,
						whileDead = true,
						hideOnEscape = true,
						preferredIndex = 3
					}
					StaticPopup_Show ("NOT_GUILD_MASTER")	
				end			
			end
		);

	-- AD-21.3.1 (BR-14.2.1): the Whitelist card follows its caption; the Teams card and the pane move with it.
	local WL_MIN_H, WL_CHROME_H, WL_TOP_Y, TEAMS_H, MANAGE_PANE_H = 140, 76, 139, 195, 482
	local function LayoutWhitelistCard()
		local tab = CommDKP.ConfigTab3
		local wl = tab and tab.WhitelistContainer
		if not wl then return end
		local d = wl.WhitelistHeader
		local hc = d and d.GetStringHeight and d:GetStringHeight() or 0
		if not hc or hc < 1 then hc = 96 end                     -- fonts not laid out yet: assume 8 caption lines
		local wlH = math.max(WL_MIN_H, math.ceil(hc) + WL_CHROME_H)
		wl:SetHeight(wlH)
		tab.TeamHeader:ClearAllPoints()
		tab.TeamHeader:SetPoint("TOPLEFT", tab, "TOPLEFT", 0, -(WL_TOP_Y + wlH + W.GUT))
		local h = MANAGE_PANE_H
		if wl:IsShown() then h = math.max(MANAGE_PANE_H, WL_TOP_Y + wlH + W.GUT + TEAMS_H) end   -- leader-only cards
		tab:SetHeight(h)
	end
	CommDKP.ConfigTab3.LayoutWhitelistCard = LayoutWhitelistCard

	-- only show whitelist and/or team management if player is a guild master
	ApplyLeaderVisibility()
	if not leaderHookInstalled then
		leaderHookInstalled = true
		CommDKP.ConfigTab3:HookScript("OnShow", ApplyLeaderVisibility)  -- AD-9.5.2: re-check when Tab 3 opens
	end
end
