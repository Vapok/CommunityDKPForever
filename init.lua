local addonName, core = ...;
local _G = _G;
local CommDKP = core.CommDKP;
local L = core.L;
local waitTable = {};
local waitFrame = nil;
local lockouts = CreateFrame("Frame", "LockoutsFrame");
local eventDelay = {};

-- CDKP-003 (Decision 3): the combat log is unavailable on the 12.x engine, so the "last 15
-- NPCs killed in raid" list is fed from BOSS_KILL / ENCOUNTER_END and LOOT_OPENED instead.
local function IsSecret(v)
	return issecretvalue ~= nil and v ~= nil and issecretvalue(v) and true or false
end

local function RecordKilledNPC(name)
	if IsSecret(name) or type(name) ~= "string" or name == "" then return end
	local list = core.DB and core.DB.bossargs and core.DB.bossargs.LastKilledNPC
	if not list or CommDKP:Table_Search(list, name) then return end	-- only adds it if it doesn't already exist in the table
	table.insert(list, 1, name)
	for i = #list, 16, -1 do  		-- trims the tail end of the stack to 15 entries
		table.remove(list, i)
	end
end

-- Chat events whose text/sender may arrive as Secret Values during restricted encounter contexts.
local SECRET_CHAT_EVENTS = { CHAT_MSG_WHISPER = true, CHAT_MSG_RAID = true, CHAT_MSG_RAID_LEADER = true, CHAT_MSG_GUILD = true }
local lastSecretNotice = 0

--------------------------------------
-- Slash Command
--------------------------------------
CommDKP.Commands = {
  ["config"] = function()
    if core.Initialized then
      local pass, err = pcall(CommDKP.Toggle)
      if not pass then
        CommDKP:Print(err)
        core.CommDKPUI:SetShown(false)
        StaticPopupDialogs["SUGGEST_RELOAD"] = {
          text = "|CFFFF0000"..L["WARNING"].."|r: "..L["MUSTRELOADUI"],
          button1 = L["YES"],
          button2 = L["NO"],
          OnAccept = function()
            ReloadUI();
          end,
          timeout = 0,
          whileDead = true,
          hideOnEscape = true,
          preferredIndex = 3,
        }
        StaticPopup_Show ("SUGGEST_RELOAD")
      end
    else
      CommDKP:Print("CommunityDKP has not completed initialization.")
    end
  end,
  ["reset"] = CommDKP.ResetPosition,
  ["bid"] = function(...)
    if core.Initialized then
      local item = strjoin(" ", ...)
      CommDKP:CheckOfficer()
      CommDKP:StatusVerify_Update()

      -- AD-12.4: officers get the Bidding window only; raiders get their Submit Bid window.
      if core.IsOfficer then
        if item == "" then                       -- `... == nil` tested only the first vararg; test the joined string
          if core.BidAuctioneer then CommDKP:ToggleBidWindow() else CommDKP:BidInterface_Toggle() end
        else
          local itemName, itemLink, itemIcon = CommDKP:ParseItemLink(item)
          if not itemLink then CommDKP:Print(L["AWARDWARNING"]) return end
          CommDKP:Print("Opening Bid Window for: " .. itemLink)
          CommDKP:ToggleBidWindow(itemLink, itemIcon, itemName)
        end
      else
        CommDKP:BidInterface_Toggle()           -- raiders: open their Submit Bid window
      end
    else
      CommDKP:Print("CommunityDKP has not completed initialization.")
    end 
  end,
  ["repairtables"] = function(...)       -- test new features
    local cmd = ...
    if core.IsOfficer then
      if cmd == "true" then
        CommDKP:RepairTables(cmd)
      else
        CommDKP:RepairTables()
      end
    end
  end,
  ["award"] = function (name, ...)
    if core.IsOfficer and core.Initialized then
      CommDKP:StatusVerify_Update()
      
      if not name or not strfind(name, ":::::") then
        CommDKP:Print(L["AWARDWARNING"])
        return
	  end
      local item = strjoin(" ", ...)
      if not item then return end
      item = name.." "..item;
	  -- AD-12.3: cold-cache safe; MinBids is keyed by the STRING item ID.
	  local itemName, itemLink, _, _, itemKey = CommDKP:ParseItemLink(item)
	  if not itemKey then CommDKP:Print(L["AWARDWARNING"]) return end
	  local cost = 0;

	  local search = CommDKP:GetTable(CommDKP_MinBids, true)[itemKey];

	  if not search then
		cost = CommDKP:GetMinBid(item)
	  else
		cost = search.minbid;
	  end

	  CommDKP:AwardConfirm(nil, cost, core.DB.bossargs.LastKilledBoss, core.DB.bossargs.CurrentRaidZone, item)
    else
      CommDKP:Print(L["NOPERMISSION"])
    end
  end,
  ["lockouts"] = function()
    lockouts:RegisterEvent("UPDATE_INSTANCE_INFO");
    lockouts:SetScript("OnEvent", CommDKP_OnEvent);
    RequestRaidInfo()
  end,
  ["timer"] = function(time, ...)
    if time == nil then
      CommDKP:BroadcastTimer(1, "...")
    else
      local title = strjoin(" ", ...)
      CommDKP:BroadcastTimer(tonumber(time), title)
    end
  end,
  ["export"] = function(time, ...)
    CommDKP:ToggleExportWindow()
  end,
  ["modes"] = function()
    if core.Initialized then
      CommDKP:CheckOfficer()
      if core.IsOfficer then
        CommDKP:ToggleDKPModesWindow()
      else
        CommDKP:Print(L["NOPERMISSION"])
      end
    else
      CommDKP:Print("CommunityDKP has not completed initialization.")
    end
  end,
  -- CDKP-006 (AD-6.4): open the Options -> AddOns launcher; `config` keeps opening the main window.
  ["settings"] = function()
    if InCombatLockdown() then CommDKP:Print(L["SETTINGSCOMBAT"]) return end   -- the Settings panel can't open in combat
    if core.SettingsCategoryID and Settings and Settings.OpenToCategory then
      Settings.OpenToCategory(core.SettingsCategoryID)
    else
      CommDKP:OpenOptionsTab()   -- fallback: main window on the Options tab
    end
  end,
  -- CDKP-005 (AD-6.3 step 6): Gate 2 review aid, persisted per guild. Not listed in /dkp help.
  ["palette"] = function(name)
    local chosen = CommDKP:SetPalette(name)
    if chosen then
      CommDKP:Print(string.format(L["PALETTESET"], chosen))
    else
      CommDKP:Print(L["PALETTEUSAGE"])
    end
  end,
  -- CDKP-006 F6-a (AD-7): Guild-Leader-only in-game diagnostic. Not listed in /dkp help.
  ["test"] = function()
    CommDKP:RunSelfTest()
  end,
  ["help"] = function()
    CommDKP:Print(" ");
    CommDKP:Print(L["SLASHCOMMANDLIST"]..":")
    CommDKP:Print("|cff00cc66/dkp|r - "..L["DKPLAUNCH"]);
    CommDKP:Print("|cff00cc66/dkp ?|r - "..L["HELPINFO"]);
    CommDKP:Print("|cff00cc66/dkp settings|r - "..L["SETTINGSHELP"]);
    CommDKP:Print("|cff00cc66/dkp reset|r - "..L["DKPRESETPOS"]);
    CommDKP:Print("|cff00cc66/dkp lockouts|r - "..L["DKPLOCKOUT"]);
    CommDKP:Print("|cff00cc66/dkp timer|r - "..L["CREATERAIDTIMER"]);
    CommDKP:Print("|cff00cc66/dkp bid|r - "..L["OPENBIDWINDOWHELP"]);
    CommDKP:Print("|cff00cc66/dkp bid [itemlink]|r - "..L["OPENAUCWINHELP"]);
    CommDKP:Print("|cff00cc66/dkp award [item link]|r - "..L["DKPAWARDHELP"]);
    CommDKP:Print("|cff00cc66/dkp modes|r - "..L["DKPMODESHELP"]);
    CommDKP:Print("|cff00cc66/dkp export|r - "..L["DKPEXPORTHELP"]);
    CommDKP:Print(" ");
    CommDKP:Print(L["WHISPERCMDSHELP"]);
    CommDKP:Print("|cff00cc66!bid (or !bid <"..L["VALUE"]..">)|r - "..L["BIDHELP"]);
    CommDKP:Print("|cff00cc66!dkp (or !dkp <"..L["PLAYERNAME"]..">)|r - "..L["DKPCMDHELP"]);
  end,
};

local function HandleSlashCommands(str)
  if (#str == 0) then
    CommDKP.Commands.config();
    return;
  end  
  
  local args = {};
  for _, arg in ipairs({ string.split(' ', str) }) do
    if (#arg > 0) then
      table.insert(args, arg);
    end
  end
  
  local path = CommDKP.Commands;
  
  for id, arg in ipairs(args) do
    if (#arg > 0) then
      arg = arg:lower();      
      if (path[arg]) then
        if (type(path[arg]) == "function") then
          path[arg](select(id + 1, unpack(args))); 
          return;          
        elseif (type(path[arg]) == "table") then        
          path = path[arg];
        end
      else
        CommDKP.Commands.help();
        return;
      end
    end
  end
end

ChatFrame_AddMessageEventFilter("CHAT_MSG_WHISPER_INFORM", function(self, event, msg, ...)      -- suppresses outgoing whisper responses to limit spam
	
	if core.DB == nil then
		return false;
	end

	if core.DB.defaults.SuppressTells then
		if core.BidInProgress then
			if strfind(msg, L["YOURBIDOF"]) == 1 then
			  return true
			elseif strfind(msg, L["BIDDENIEDFILTER"]) == 1 then
			  return true
			elseif strfind(msg, L["BIDACCEPTEDFILTER"]) == 1 then
			  return true;
			elseif strfind(msg, L["NOTSUBMITTEDBID"]) == 1 then
			  return true;
			elseif strfind(msg, L["ONLYONEROLLWARN"]) == 1 then
			  return true;
			elseif strfind(msg, L["ROLLNOTACCEPTED"]) == 1 then
			  return true;
			elseif strfind(msg, L["YOURBID"].." "..L["MANUALLYDENIED"]) == 1 then
			  return true;
			elseif strfind(msg, L["CANTCANCELROLL"]) == 1 then
			  return true;
			end
		end
	  
		if strfind(msg, "CommunityDKP: ") == 1 then
			return true
		elseif strfind(msg, L["DKPAVAILABLE"]) ~= nil and strfind(msg, '%[') ~= nil and strfind(msg, '%]') ~= nil then
			return true
		elseif strfind(msg, L["NOBIDINPROGRESS"]) == 1 then
			return true
		elseif strfind(msg, L["BIDCANCELLED"]) == 1 then
			return true
		end
	end
end)

ChatFrame_AddMessageEventFilter("CHAT_MSG_WHISPER", function(self, event, msg, ...)      -- suppresses incoming whisper responses to limit spam

	if core.DB == nil then
		return false;
	end

	if core.DB.defaults.SuppressTells then
		if core.BidInProgress then
			if strfind(msg, "!bid") == 1 then
			  return true
			end
		end

		if strfind(msg, "!dkp") == 1 then
			return true
		end
	end
end)


function CommDKP_wait(delay, func, ...)
	if(type(delay)~="number" or type(func)~="function") then
		return false;
	end
	if(waitFrame == nil) then
		waitFrame = CreateFrame("Frame","WaitFrame", UIParent);
		waitFrame:SetScript("onUpdate",function (self,elapse)
		local count = #waitTable;
		local i = 1;
		while(i<=count) do
			local waitRecord = tremove(waitTable,i);
			local d = tremove(waitRecord,1);
			local f = tremove(waitRecord,1);
			local p = tremove(waitRecord,1);
			if(d>elapse) then
			tinsert(waitTable,i,{d-elapse,f,p});
			i = i + 1;
			else
			count = count - 1;
			f(unpack(p));
			end
		end
		end);
  end
  tinsert(waitTable,{delay,func,{...}});
  return true;
end

local function DoInit(event, arg1)
	-- AD-9.4: runs before anything (MonolithMigration, OnInitialize:803) can create an empty real bucket.
	CommDKP:RepairIdentityBuckets()
	if CommDKP:MonolithMigration() then
		return -- Legacy MonolithDKP addon detected: don't initialise any further!
	end
	CommDKP:OnInitialize(event, arg1);
end

-- AD-9.3: wait (1 s ticks, max 30) until realm, faction and guild are known before binding core.DB.
local function DoInitWhenReady(event, arg1, tries)
	if CommDKP:IsIdentityReady() or tries >= 30 then
		if tries >= 30 then CommDKP:PrintAlways("CommunityDKP Forever: guild info not ready after 30s; continuing.") end
		return DoInit(event, arg1)
	end
	if IsInGuild() and C_GuildInfo and C_GuildInfo.GuildRoster then C_GuildInfo.GuildRoster() end
	C_Timer.After(1, function() DoInitWhenReady(event, arg1, tries + 1) end)
end

local function DoGuildUpdate()
	if IsInGuild() and not core.InitStart then
		C_GuildInfo.GuildRoster()
		core.InitStart = true

		-- Prints info after all addons have loaded. Circumvents addons that load saved chat messages pushing info out of view.
		C_Timer.After(3, function ()
			CommDKP:CheckOfficer()
			CommDKP:SortLootTable()
			CommDKP:SortDKPHistoryTable()
			CommDKP:Print(L["VERSION"].." "..core.MonVersion..", "..L["CREATEDMAINTAIN"].." Vapok (WoW: Forever Edition)");
			CommDKP:Print(L["LOADED"].." "..#CommDKP:GetTable(CommDKP_DKPTable, true).." "..L["PLAYERRECORDS"]..", "..#CommDKP:GetTable(CommDKP_Loot, true).." "..L["LOOTHISTRECORDS"].." "..#CommDKP:GetTable(CommDKP_DKPHistory, true).." "..L["DKPHISTRECORDS"]..".");
			CommDKP:Print(L["USE"].." /dkp ? "..L["SUBMITBUGS"].." @ https://github.com/Vapok/CommunityDKPForever/issues");
			CommDKP.Sync:SendData("CommDKPBuild", tostring(core.BuildNumber)) -- broadcasts build number to guild to check if a newer version is available
			CommDKP:SendTalentsAndRole()

			-- send seed for every team in guild
			-- this basically sends index of latest entry in loot and DKP tables to everyone online in guild,
			-- if they have this entry it does nothing since they are up to date, if they dont it changes seed in those tables to the index being sent
			CommDKP:SendSeedData();
		end)
	end
end

function CommDKP:SendSeedData()

	local latestIndexForTeam = {}
	local _teams = CommDKP:GetGuildTeamList();
	local _numberOfTeams = CommDKP:tablelength(_teams);

	for i=1, _numberOfTeams do

		latestIndexForTeam[tostring(_teams[i][1])] = {}

		if 	#CommDKP:GetTable(CommDKP_DKPHistory, true, tostring(_teams[i][1])) > 0 and strfind(CommDKP:GetTable(CommDKP_DKPHistory, true, tostring(_teams[i][1]))[1].index, "-") then
			local off1,date1 = strsplit("-", CommDKP:GetTable(CommDKP_DKPHistory, true, tostring(_teams[i][1]))[1].index)
			if CommDKP:ValidateSender(off1) then
				latestIndexForTeam[tostring(_teams[i][1])]["DKPHistory"] = CommDKP:GetTable(CommDKP_DKPHistory, true, tostring(_teams[i][1]))[1].index
			else
				latestIndexForTeam[tostring(_teams[i][1])]["DKPHistory"] = "start"
			end
		else
			latestIndexForTeam[tostring(_teams[i][1])]["DKPHistory"] = "start"
		end
		
		if #CommDKP:GetTable(CommDKP_Loot, true, tostring(_teams[i][1])) > 0 and strfind(CommDKP:GetTable(CommDKP_Loot, true, tostring(_teams[i][1]))[1].index, "-") then
			local off2,date2 = strsplit("-", CommDKP:GetTable(CommDKP_Loot, true, tostring(_teams[i][1]))[1].index)
			if CommDKP:ValidateSender(off2) then
				latestIndexForTeam[tostring(_teams[i][1])]["Loot"] = CommDKP:GetTable(CommDKP_Loot, true, tostring(_teams[i][1]))[1].index
			else
				latestIndexForTeam[tostring(_teams[i][1])]["Loot"] = "start"
			end
		else
			latestIndexForTeam[tostring(_teams[i][1])]["Loot"] = "start"
		end
	end

	--[[ 
		latestIndexForTeam = {
			["0"] = {
				["Loot"] = "name-date",
				["DKPHistory"] = "name-date"
			},
			["1"] = {
				["Loot"] = "start",
				["DKPHistory"] = "start"
			}
		}
	--]]

	CommDKP.Sync:SendData("CommDKPSeed", latestIndexForTeam) -- requests role and spec data and sends current seeds (index of newest DKP and Loot entries)

end

function CommDKP_OnEvent(self, event, arg1, ...)

	if self:IsForbidden() then return; end;

	if event == "ADDON_LOADED" then
		if (arg1 ~= addonName) then return end
		core.IsOfficer = nil
		core.Initialized = false
		C_Timer.After(2, function() DoInitWhenReady(event, arg1, 0) end);  -- AD-9.3
		---DoInit(event,arg1);
		self:UnregisterEvent("ADDON_LOADED")
		return;
	end

	-- If core.DB is nil, that means that the addon hasn't fully initialized.. so let's wait 1 second and try again.
	if core.DB == nil then
		if eventDelay[event] == nil then
			eventDelay[event] = 1;
		else
			eventDelay[event] = eventDelay[event] + 2;
		end
		C_Timer.After(eventDelay[event], function () CommDKP_OnEvent(self, event, arg1); end);
		return;
	end

	if eventDelay[event] ~= nil then
		eventDelay[event] = nil;
	end

	-- unregister unneccessary events
	if event == "CHAT_MSG_WHISPER" and not core.DB.modes.channels.whisper then
		self:UnregisterEvent("CHAT_MSG_WHISPER")
		return
	end
	if (event == "CHAT_MSG_RAID" or event == "CHAT_MSG_RAID_LEADER") and not core.DB.modes.channels.raid then
		self:UnregisterEvent("CHAT_MSG_RAID")
		self:UnregisterEvent("CHAT_MSG_RAID_LEADER")
		return
	end
	if event == "CHAT_MSG_GUILD" and not core.DB.modes.channels.guild and not core.DB.modes.StandbyOptIn then
		self:UnregisterEvent("CHAT_MSG_GUILD")
		return
	end

	-- CDKP-003 (AC-3): chat text/sender can be Secret Values in restricted contexts; any string op
	-- (strlower/strfind) on them errors. Refuse before parsing and tell the officer running an auction.
	if SECRET_CHAT_EVENTS[event] then
		local sender = ...
		if IsSecret(arg1) or IsSecret(sender) then
			if core.BidInProgress and core.IsOfficer and (GetTime() - lastSecretNotice) > 10 then
				lastSecretNotice = GetTime()
				CommDKP:Print(L["BIDDINGLOCKED"])
			end
			return
		end
	end

	if event == "BOSS_KILL" then
		if IsSecret(arg1) or IsSecret((...)) then return end	-- AD-11.5: never index/store/print Secret Values
		if IsInRaid() then
			RecordKilledNPC((...))				-- AC-1: LastKilledNPC holds the boss name
		end
		CommDKP:CheckOfficer()
		if core.IsOfficer and IsInRaid() then
			local boss_name = ...;
			-- AD-11.5: static IDs, known world bosses by name, and discovered Forever encounters
			local zone, bossName, source, isNew = CommDKP:ResolveOrRegisterEncounter(arg1, boss_name)
			if zone then
				if isNew then
					CommDKP:Print("Discovered new WoW Forever raid encounter: "..zone.." - "..bossName.." (ID: "..tostring(arg1)..")")
				end
				CommDKP:ApplyBossContext(zone, bossName)		-- works with or without ConfigTab2

				if core.DB.modes.StandbyOptIn and core.RaidInProgress then
					CommDKP_Standby_Announce(boss_name)
				end

				if core.DB.modes.AutoAward and core.RaidInProgress then
					if not core.DB.modes.StandbyOptIn and core.DB.DKPBonus.IncStandby then
						CommDKP:AutoAward(3, core.DB.DKPBonus.BossKillBonus, core.DB.bossargs.CurrentRaidZone..": "..core.DB.bossargs.LastKilledBoss)
					else
						CommDKP:AutoAward(1, core.DB.DKPBonus.BossKillBonus, core.DB.bossargs.CurrentRaidZone..": "..core.DB.bossargs.LastKilledBoss)
					end
				end
			else
				CommDKP:Print("Event ID: "..tostring(arg1).." - > "..tostring(boss_name).." Killed. Please report this Event ID at https://github.com/Vapok/CommunityDKPForever/issues to update raid event handlers.")
			end
		elseif IsInRaid() then
			core.DB.bossargs.LastKilledBoss = ...;
		end
	elseif event == "ENCOUNTER_START" then
		core.InEncounter = true
		if core.DB.defaults.AutoLog and IsInRaid() then
			if not LoggingCombat() then
				LoggingCombat(1)
				CommDKP:Print(L["NOWLOGGINGCOMBAT"])
			end
		end
	elseif event == "ENCOUNTER_END" then
		-- args: encounterID, encounterName, difficultyID, groupSize, success
		core.InEncounter = false
		local _, encounterName, _, _, success = arg1, ...
		if success == 1 and IsInRaid() then
			RecordKilledNPC(encounterName)
		end
	elseif event == "PLAYER_ENTERING_WORLD" or event == "ZONE_CHANGED_NEW_AREA" then   		-- logs 15 recent zones entered while in a raid party
		-- A zone change can skip ENCOUNTER_END (disconnect, release); resync the encounter flag.
		core.InEncounter = (type(IsEncounterInProgress) == "function" and IsEncounterInProgress()) and true or false
		if IsInRaid() and core.Initialized then					-- only processes combat log events if in raid
			CommDKP:CheckOfficer()
			if core.IsOfficer then
				if not CommDKP:Table_Search(core.DB.bossargs.RecentZones, GetRealZoneText()) then 	-- only adds it if it doesn't already exist in the table
					if #core.DB.bossargs.RecentZones > 14 then
						for i=15, #core.DB.bossargs.RecentZones do  		-- trims the tail end of the stack
							table.remove(core.DB.bossargs.RecentZones, i)
						end
					end
					table.insert(core.DB.bossargs.RecentZones, 1, GetRealZoneText())
				end
			end
			local zoneText = GetRealZoneText()
			if core.DB.defaults.AutoLog and (CommDKP:Table_Search(core.ZoneList, zoneText)
					or (type(core.DB.CustomEncounters) == "table" and core.DB.CustomEncounters[zoneText] ~= nil)) then	-- AD-11.5: discovered Forever raids too
				if not LoggingCombat() then
					LoggingCombat(1)
					CommDKP:Print(L["NOWLOGGINGCOMBAT"])
				end
			end
		end
		if core.Initialized then
			CommDKP:SendTalentsAndRole()
		end
	elseif event == "CHAT_MSG_WHISPER" then
		CommDKP:CheckOfficer()
		if core.IsOfficer then

			arg1 = strlower(arg1)
			if (core.BidInProgress or string.find(arg1, "!dkp") == 1 or string.find(arg1, "！dkp") == 1) then
				CommDKP_CHAT_MSG_WHISPER(arg1, ...)
			elseif string.find(arg1, "!standby") == 1 and core.StandbyActive then
				CommDKP_Standby_Handler(arg1, ...)
			end
		end
	elseif event == "GUILD_ROSTER_UPDATE" then

		if not core.InitStart then
			DoGuildUpdate();
		end

		if IsInGuild() and core.InitStart then
			self:UnregisterEvent("GUILD_ROSTER_UPDATE")
		end
	elseif event == "CHAT_MSG_RAID" or event == "CHAT_MSG_RAID_LEADER" then
		CommDKP:CheckOfficer()
		arg1 = strlower(arg1)
		if (core.BidInProgress or string.find(arg1, "!dkp") == 1 or string.find(arg1, "!standby") == 1 or string.find(arg1, "！dkp") == 1) and core.IsOfficer == true then
			CommDKP_CHAT_MSG_WHISPER(arg1, ...)
		end
	elseif event == "UPDATE_INSTANCE_INFO" then
		local num = GetNumSavedInstances()
		local raidString, reset, newreset, days, hours, mins, maxPlayers, numEncounter, curLength;

		if not core.DB.Lockouts then core.DB.Lockouts = {Three = 0, Five = 1570032000, Seven = 1569945600} end

		for i=1, num do 		-- corrects reset timestamp for any raids where an active lockout exists
			_,_,reset,_,_,_,_,_,maxPlayers,_,numEncounter = GetSavedInstanceInfo(i)
			newreset = time() + reset + 2 	-- returned time is 2 seconds off

			if maxPlayers == 40 and numEncounter > 1 then
				curLength = "Seven"
			elseif maxPlayers == 40 and numEncounter == 1 then
				curLength = "Five"
			elseif maxPlayers == 20 then
				curLength = "Three"
			end

			if core.DB.Lockouts[curLength] < newreset then
				core.DB.Lockouts[curLength] = newreset
			end
		end

		-- Updates lockout timer if no lockouts were found to do so.
		while core.DB.Lockouts.Three < time() do core.DB.Lockouts.Three = core.DB.Lockouts.Three + 259200 end
		while core.DB.Lockouts.Five < time() do core.DB.Lockouts.Five = core.DB.Lockouts.Five + 432000 end
		while core.DB.Lockouts.Seven < time() do core.DB.Lockouts.Seven = core.DB.Lockouts.Seven + 604800 end

		for k,v in pairs(core.DB.Lockouts) do
			reset = v - time();
			days = math.floor(reset / 86400)
			hours = math.floor(math.floor(reset % 86400) / 3600)
			mins = math.ceil((reset % 3600) / 60)
			
			if days > 1 then days = " "..days.." "..L["DAYS"] elseif days == 0 then days = "" else days = " "..days.." "..L["DAY"] end
			if hours > 1 then hours = " "..hours.." "..L["HOURS"] elseif hours == 0 then hours = "" else hours = " "..hours.." "..L["HOUR"].."." end
			if mins > 1 then mins = " "..mins.." "..L["MINUTES"].."." elseif mins == 0 then mins = "" else mins = " "..mins.." "..L["MINUTE"].."." end

			if k == "Three" then raidString = "ZG, AQ20"
			elseif k == "Five" then raidString = "Onyxia"
			elseif k == "Seven" then raidString = "MC, BWL, AQ40"
			end

			if k ~= "Three" then 	-- remove when three day raid lockouts are added
				CommDKP:Print(raidString.." "..L["RESETSIN"]..days..hours..mins.." ("..date("%A @ %H:%M:%S%p", v)..")")
			end
		end

		self:UnregisterEvent("UPDATE_INSTANCE_INFO");
	elseif event == "CHAT_MSG_GUILD" then
		CommDKP:CheckOfficer()
		if core.IsOfficer then
			arg1 = strlower(arg1)
			if (core.BidInProgress or string.find(arg1, "!dkp") == 1 or string.find(arg1, "！dkp") == 1) and core.DB.modes.channels.guild then
				CommDKP_CHAT_MSG_WHISPER(arg1, ...)
			elseif string.find(arg1, "!standby") == 1 and core.StandbyActive then
				CommDKP_Standby_Handler(arg1, ...)
			end
		end
	--elseif event == "CHAT_MSG_SYSTEM" then
		--MonoDKP_CHAT_MSG_SYSTEM(arg1)
	elseif event == "GROUP_ROSTER_UPDATE" then 			--updates raid listing if window is open
		if CommDKP.UIConfig and core.CommDKPUI:IsShown() then
			if core.CurSubView == "raid" then
				CommDKP:ViewLimited(true)
			elseif core.CurSubView == "raid and standby" then
				CommDKP:ViewLimited(true, true)
			end
		end
	elseif event == "LOOT_OPENED" then
		CommDKP:CheckOfficer();
		if core.IsOfficer then
			local lootTable = {}
			local lootList = {};

			if IsInRaid() then
				for i=1, GetNumLootItems() do
					local link = LootSlotHasItem(i) and GetLootSlotLink(i)
					if link then
						-- CDKP-004: quality comes from the loot slot itself; GetItemInfo returns nil for
						-- uncached items, which made the old `quality >= 4` comparison error.
						local quality = select(5, GetLootSlotInfo(i))
						if quality and quality >= 4 then
							table.insert(lootTable, link)
						end
					end
				end
				local name
				if not UnitIsFriend("player", "target") and UnitIsDead("target") then
					local targetName = UnitName("target")  -- sets bidding window name to current target
					if targetName and not IsSecret(targetName) then
						name = targetName
						RecordKilledNPC(targetName)		-- Decision 3: LOOT_OPENED target capture
					end
				end
				if not name then
					name = core.LastKilledBoss  -- no usable target (chest, or name is a Secret Value): keep last killed boss
				end
				lootTable.boss=name
				CommDKP.Sync:SendData("CommDKPBossLoot", lootTable)

				for i=1, #lootTable do
					local item = Item:CreateFromItemLink(lootTable[i]);
					item:ContinueOnItemLoad(function()
						local icon = item:GetItemIcon()
						table.insert(lootList, {icon=icon, link=item:GetItemLink()})
					end);
				end

				CommDKP:LootTable_Set(lootList)
			end
		end
	elseif core.DB.defaults.AutoAwardLoot and event == "TRADE_SHOW" then
		local traderName = UnitName("npc")
		if traderName == nil or core.DB.pendingLoot == nil or core.DB.pendingLoot[traderName] == nil then
			return
		end
		core.DB.pendingTradePlayer = traderName
		core.DB.pendingTrade = {}
		local pendingLoot = core.DB.pendingLoot[traderName]

		for i, lootLink in pairs(pendingLoot) do
			local awarded = false
			for containerSlot = 0, NUM_BAG_FRAMES do
				for bagSlot = 1, C_Container.GetContainerNumSlots(containerSlot) do
					local containerLink = C_Container.GetContainerItemLink(containerSlot, bagSlot)

					if not awarded and containerLink ~= nil and containerLink == lootLink then
						ClearCursor()
						C_Container.PickupContainerItem(containerSlot, bagSlot)
						local tradeSlot = TradeFrame_GetAvailableSlot()
						if tradeSlot ~= nil and tradeSlot <= 6 then
							ClickTradeButton(tradeSlot)
							pendingLoot[i] = nil
							tinsert(core.DB.pendingTrade, lootLink)
							awarded = true
						end
					end
				end
			end
		end
	elseif core.DB.defaults.AutoAwardLoot and event == "TRADE_ACCEPT_UPDATE" then
		local arg2 = ...
		local traderName = UnitName("npc")
		if traderName == nil or core.DB.pendingLoot == nil or core.DB.pendingLoot[traderName] == nil then
			return
		end
		if arg1 ~= nil and arg1 == 1 then
			local pendingLoot = core.DB.pendingLoot[traderName]
			if core.DB.pendingTrade == nil then
				core.DB.pendingTrade = {}
			end
			for tradeSlot = 1, 6 do
				local tradeLink = GetTradePlayerItemLink(tradeSlot)
				for i, lootLink in pairs(pendingLoot) do
					if tradeLink ~= nil and tradeLink == lootLink then
						tinsert(core.DB.pendingTrade, tradeLink)
					end
				end
			end
		end
	elseif core.DB.defaults.AutoAwardLoot and event == "TRADE_CLOSED" then
		local traderName = UnitName("npc")
		if traderName == nil or core.DB.pendingTrade == nil or core.DB.pendingLoot == nil or core.DB.pendingLoot[traderName] == nil then
			return
		end
		local pendingLoot = core.DB.pendingLoot[traderName]
		for _, tradeLink in pairs(core.DB.pendingTrade) do
			for i, lootLink in pairs(pendingLoot) do
				if tradeLink == lootLink then
					pendingLoot[i] = nil
				end
			end
		end
		if #pendingLoot <= 0 then
			core.DB.pendingLoot[traderName] = nil
		end
		core.DB.pendingTrade = {}
		core.DB.pendingTradePlayer = nil
	end
end

function CommDKP:OnInitialize(event, name)		-- This is the FIRST function to run on load triggered registered events at bottom of file
	if (name ~= addonName) then return end

	-- allows using left and right buttons to move through chat 'edit' box
	--[[for i = 1, NUM_CHAT_WINDOWS do
		_G["ChatFrame"..i.."EditBox"]:SetAltArrowKeyMode(false);
	end--]]
	
	----------------------------------
	-- Register Slash Commands
	----------------------------------
	SLASH_CommunityDKP1 = "/dkp";
	SLASH_CommunityDKP2 = "/CommDKP";
	SlashCmdList.CommunityDKP = HandleSlashCommands;

	--[[SLASH_RELOADUI1 = "/rl"; -- new slash command for reloading UI 				-- for debugging
	SlashCmdList.RELOADUI = ReloadUI;--]]

	if(event == "ADDON_LOADED") then
		local ACTION_BAR_FRAMES = { "MultiBarLeft", "MultiBarRight", "MultiBarBottomLeft", "MultiBarBottomRight", "MainMenuBar" }
		C_Timer.After(5, function ()
			-- CDKP-006 F6-b (AD-8.4): one UI error must not stop the addon from starting or leave a half-built window on screen.
			local ok, err = xpcall(function()
				core.CommDKPUI = CommDKP.UIConfig or CommDKP:CreateMenu();		-- creates main menu after 5 seconds (trying to initialize after raid frames are loaded)
			end, function(e) geterrorhandler()(e); return e end)			-- still reaches BugSack / the error frame
			if not ok then
				core.InitError = tostring(err)
				if CommDKP.UIConfig then
					if CommDKP.UIConfig.TabMenu then CommDKP.UIConfig.TabMenu:Hide() end
					CommDKP.UIConfig:Hide()										-- no orphaned black box on screen
				end
				CommDKP:PrintAlways("UI failed to build (Guild Leader: type /dkp test). " .. core.InitError)
			end
			core.KeyEventUI = CreateFrame("Frame","KeyEventFrame", UIParent);
			
			-- on every key down ? really?	
			core.KeyEventUI:SetScript("OnKeyDown", function(self, key)
				if core.Initialized and core.IsOfficer then
					-- AD-8.4: Mainline renamed/rebuilt several action-bar frames; a nil global must not throw here.
					for _, n in ipairs(ACTION_BAR_FRAMES) do
						local f = _G[n]
						if f and MouseIsOver(f) then return end
					end
						-- TODO: Make this a configurable keybind.
					if GameTooltip:GetItem() then
						local item, link = GameTooltip:GetItem();

						if (key == "LALT" or key == "LSHIFT") and IsShiftKeyDown() and IsAltKeyDown() then
							
							local itemName, itemLink, itemIcon = CommDKP:ParseItemLink(link)	-- AD-12.3
							if itemLink then CommDKP:ToggleBidWindow(itemLink, itemIcon, itemName) end
						end

						if (key == "LCTRL" or key == "LSHIFT") and IsShiftKeyDown() and IsControlKeyDown() then
							-- TODO: Automate the Price a Bit More
							CommDKP:AwardConfirm(nil, 0, core.DB.bossargs.LastKilledBoss, core.DB.bossargs.CurrentRaidZone, link);
						end


					end
				end
			end);

			core.KeyEventUI:SetPropagateKeyboardInput(true);
		end)
		------------------------------------------------
		-- Verify DB Schemas
		------------------------------------------------\
		if not CommDKP:VerifyDBSchema(CommDKP_DB) then CommDKP_DB = CommDKP:UpgradeDBSchema(CommDKP_DB, CommDKP_DB, false, "CommDKP_DB") end;
		
		-- Verify that the DB table has been initialized.
		CommDKP:SetTable(CommDKP_DB, false, CommDKP:InitializeCommDKPDB(CommDKP:GetTable(CommDKP_DB)))
		core.DB = CommDKP:GetTable(CommDKP_DB); --Player specific DB

		-- CDKP-005 (AD-6.3): saved palette choice (/dkp palette). Applied before any frame is built
		-- (the main menu is created 5s later). Optional field; absent = core.DefaultPaletteName.
		if not CommDKP:SetPalette(core.DB.defaults.Palette or core.DefaultPaletteName) then
			CommDKP:SetPalette(core.DefaultPaletteName)
		end

		
		if not CommDKP:VerifyDBSchema(CommDKP_DKPTable) then CommDKP_DKPTable = CommDKP:UpgradeDBSchema(CommDKP_DKPTable, CommDKP_DKPTable, true, "CommDKP_DKPTable") end;
		if not CommDKP:VerifyDBSchema(CommDKP_Loot) then CommDKP_Loot = CommDKP:UpgradeDBSchema(CommDKP_Loot, CommDKP_Loot, true, "CommDKP_Loot") end;
		if not CommDKP:VerifyDBSchema(CommDKP_DKPHistory) then CommDKP_DKPHistory = CommDKP:UpgradeDBSchema(CommDKP_DKPHistory, CommDKP_DKPHistory, true, "CommDKP_DKPHistory") end;
		if not CommDKP:VerifyDBSchema(CommDKP_MinBids) then CommDKP_MinBids = CommDKP:UpgradeDBSchema(CommDKP_MinBids, CommDKP_MinBids, true, "CommDKP_MinBids") end;
		if not CommDKP:VerifyDBSchema(CommDKP_MaxBids) then CommDKP_MaxBids = CommDKP:UpgradeDBSchema(CommDKP_MaxBids, CommDKP_MaxBids, true, "CommDKP_MaxBids") end;
		if not CommDKP:VerifyDBSchema(CommDKP_Whitelist) then CommDKP_Whitelist = CommDKP:UpgradeDBSchema(CommDKP_Whitelist, CommDKP_Whitelist, false, "CommDKP_Whitelist") end;
		if not CommDKP:VerifyDBSchema(CommDKP_Standby) then CommDKP_Standby = CommDKP:UpgradeDBSchema(CommDKP_Standby, CommDKP_Standby, true, "CommDKP_Standby") end;
		if not CommDKP:VerifyDBSchema(CommDKP_Archive) then CommDKP_Archive = CommDKP:UpgradeDBSchema(CommDKP_Archive, CommDKP_Archive, true, "CommDKP_Archive") end;
		if not CommDKP:VerifyDBSchema(CommDKP_Profiles) then CommDKP_Profiles = CommDKP:UpgradeDBSchema(CommDKP_Profiles, CommDKP_Profiles, true, "CommDKP_Profiles") end;


		------------------------------------
	    --	Import SavedVariables
	    ------------------------------------
		core.WorkingTable 		= CommDKP:GetTable(CommDKP_DKPTable, true); -- imports full DKP table to WorkingTable for list manipulation
		core.PriceTable			= CommDKP:FormatPriceTable();

		for i=1, #core.WorkingTable do
			local CurPlayer = core.WorkingTable[i].player;
			local search = CommDKP:Table_Search(CommDKP:GetTable(CommDKP_DKPTable, true), CurPlayer);

			if search then
				--Set Version Info on Legacy Record First
				local profile = CommDKP:GetTable(CommDKP_Profiles, true)[CurPlayer] or CommDKP:GetDefaultEntity();
				core.WorkingTable[i].version = profile.version;
			end
		end


		if not CommDKP:GetTable(CommDKP_DKPHistory, true).seed then CommDKP:GetTable(CommDKP_DKPHistory, true).seed = 0 end
		if not CommDKP:GetTable(CommDKP_Loot, true).seed then CommDKP:GetTable(CommDKP_Loot, true).seed = 0 end
		if CommDKP:GetTable(CommDKP_DKPTable, true).seed then CommDKP:GetTable(CommDKP_DKPTable, true).seed = nil end


		core.CurrentRaidZone	= core.DB.bossargs.CurrentRaidZone;	-- stores raid zone as a redundency
		core.LastKilledBoss 	= core.DB.bossargs.LastKilledBoss;	-- stores last boss killed as a redundency
		core.LastKilledNPC		= core.DB.bossargs.LastKilledNPC 		-- Stores last 30 mobs killed in raid.
		core.RecentZones		= core.DB.bossargs.RecentZones 		-- Stores last 30 zones entered within a raid party.

		table.sort(core.WorkingTable, function(a, b)
			return a["player"] < b["player"]
		end)
		
		table.sort(core.PriceTable, function(a, b)
			if a["item"] ~= nil and b["item"] == nil then
				return true;
			elseif a["item"] == nil and b["item"] ~= nil then
				return false;
			elseif a["item"] == nil and b["item"] == nil then
				return false;
			end

			return a["item"] < b["item"]
		end)
		CommDKP:StartBidTimer("seconds", nil)						-- initiates timer frame for use

		if CommDKP.BidTimer then CommDKP.BidTimer:SetScript("OnUpdate", nil) end

		if #CommDKP:GetTable(CommDKP_Loot, true) > core.DB.defaults.HistoryLimit then
			CommDKP:PurgeLootHistory()									-- purges Loot History entries that exceed the "HistoryLimit" option variable (oldest entries) and populates CommDKP_Archive with deleted values
		end
		if #CommDKP:GetTable(CommDKP_DKPHistory, true) > core.DB.defaults.DKPHistoryLimit then
			CommDKP:PurgeDKPHistory()									-- purges DKP History entries that exceed the "DKPHistoryLimit" option variable (oldest entries) and populates CommDKP_Archive with deleted values
		end
		core.DB.pendingLoot = {}
	end
end

function CommDKP:GetTable(dbTable, hasTeams, teamIndex)
	hasTeams = hasTeams or false;
	local _teamIndex;

	if IsInGuild() then
		local realmName = CommDKP:GetRealmName();
		local guildName = CommDKP:GetGuildName();

		dbTable = CommDKP:InitializeGuild(dbTable,realmName,guildName);

		if hasTeams then

			if teamIndex == nil then
				_teamIndex =  core.DB.defaults.CurrentTeam;
			else
				_teamIndex = teamIndex
			end

			if not dbTable[realmName][guildName][_teamIndex] then
				dbTable[realmName][guildName][_teamIndex] = {}
			end

			return dbTable[realmName][guildName][_teamIndex];
		else
			return dbTable[realmName][guildName];
		end
	else
		return dbTable[core.defaultTable];
	end
end

function CommDKP:SetTable(dbTable, hasTeams, value, teamIndex)
	hasTeams = hasTeams or false;
	local _teamIndex;

	if IsInGuild() then
		local realmName = CommDKP:GetRealmName();
		local guildName = CommDKP:GetGuildName();

		dbTable = CommDKP:InitializeGuild(dbTable,realmName,guildName);

		if hasTeams then
			if teamIndex == nil then
				_teamIndex =  core.DB.defaults.CurrentTeam;
			else
				_teamIndex = teamIndex
			end

			dbTable[realmName][guildName][_teamIndex] = value;
		else
			dbTable[realmName][guildName] = value;
		end
	else
		dbTable[core.defaultTable] = value;
	end
end

function CommDKP:VerifyDBSchema(dbTable)
	local verified = false;
	--Check to see if the schema node exists. If not, this is 2.1.2 database.
	local retOK, hasInfo = pcall(CommDKP_tableHasKey,dbTable,"dbinfo");

	if (not retOK) or (retOK and not hasInfo) then
		verified = false;
	elseif dbTable.dbinfo.build == core.BuildNumber then
		verified = true;
	end

	return verified;
end

function CommDKP:UpgradeDBSchema(newDbTable, oldDbTable, hasTeams, tableName)
	-- Initialize the Database for a Pre-2.2 Database
	local retOK, hasInfo = pcall(CommDKP_tableHasKey,oldDbTable,"dbinfo");
	if (not retOK) or (retOK and not hasInfo) then
		newDbTable = CommDKP:InitPlayerTable(oldDbTable, hasTeams, tableName)
	end

	-- Verify that build and priorbuild elements exist.
	if  newDbTable.dbinfo.build == nil then
		newDbTable.dbinfo.build = 0;
	end

	if  newDbTable.dbinfo.priorbuild == nil then
		newDbTable.dbinfo.priorbuild = 0;
	end
	
	--Set Prior Build
	newDbTable.dbinfo.priorbuild = newDbTable.dbinfo.build;

	-- Build 20205 (2.2.5) Changes
	if newDbTable.dbinfo.build < 20205 and newDbTable.dbinfo.priorbuild ~= core.BuildNumber then
		if newDbTable.dbinfo.name == "CommDKP_DB" then

			local defaultTable = {}
			defaultTable = CommDKP:InitializeCommDKPDB(CommDKP:GetTable(defaultTable))
			if not defaultTable.defaults.CurrentTeam then defaultTable.defaults.CurrentTeam = "0" end;
			if not defaultTable.teams then defaultTable.teams = {} end;
			newDbTable[core.defaultTable] = defaultTable;
		end
	end

	if newDbTable.dbinfo.build < 30200 and newDbTable.dbinfo.priorbuild ~= core.BuildNumber and newDbTable.dbinfo.priorbuild ~= 0 then
		if newDbTable.dbinfo.name == "CommDKP_MinBids" then
			newDbTable = CommDKP:RefactorMinBidItemTable(newDbTable);
		end
	end

	if newDbTable.dbinfo.build < 30202 and newDbTable.dbinfo.priorbuild ~= core.BuildNumber and newDbTable.dbinfo.priorbuild ~= 0 then
		if newDbTable.dbinfo.name == "CommDKP_MinBids" then
			newDbTable = CommDKP:VerifyMinBidItemTable(newDbTable);
		end
	end

	-- Set Current Build Number
	newDbTable.dbinfo.build = core.BuildNumber;
	return newDbTable;
end

function CommDKP_tableHasKey(table,key)
	return table[key] ~= nil;
end

function CommDKP:InitializeCommDKPDB(dbTable)
	if dbTable == nil then
		dbTable = {}
	end
	
	if not dbTable.DKPBonus or not dbTable.DKPBonus.OnTimeBonus then
		dbTable.DKPBonus = {
			OnTimeBonus = 15, BossKillBonus = 5, CompletionBonus = 10, NewBossKillBonus = 10, UnexcusedAbsence = -25, BidTimer = 30, DecayPercentage = 20, GiveRaidStart = false, IncStandby = false,
		}
	end

	if not dbTable.defaults or not dbTable.defaults.HistoryLimit then
		dbTable.defaults = {
			HistoryLimit = 2500, DKPHistoryLimit = 2500, BidTimerSize = 1.0, CommDKPScaleSize = 1.0, SuppressNotifications = false, TooltipHistoryCount = 15, SuppressTells = true,
		}
	end
	if not dbTable.defaults.ChatFrames then 
		dbTable.defaults.ChatFrames = {}
		for i = 1, NUM_CHAT_WINDOWS do
			local name = GetChatWindowInfo(i)

			if name ~= "" then
				dbTable.defaults.ChatFrames[name] = true
			end
		end
	end
	if not dbTable.raiders then dbTable.raiders = {} end
	if not dbTable.MinBidBySlot or not dbTable.MinBidBySlot.Head then
		dbTable.MinBidBySlot = {
			Head = 70, Neck = 70, Shoulders = 70, Cloak = 70, Chest = 70, Bracers = 70, Hands = 70, Belt = 70, Legs = 70, Boots = 70, Ring = 70, Trinket = 70, OneHanded = 70, TwoHanded = 70, OffHand = 70, Range = 70, Other = 70,
		}
	end
	if not dbTable.MaxBidBySlot or not dbTable.MaxBidBySlot.Head then
		dbTable.MaxBidBySlot = {
			Head = 0, Neck = 0, Shoulders = 0, Cloak = 0, Chest = 0, Bracers = 0, Hands = 0, Belt = 0, Legs = 0, Boots = 0, Ring = 0, Trinket = 0, OneHanded = 0, TwoHanded = 0, OffHand = 0, Range = 0, Other = 0,
		}
	end
	if not dbTable.bossargs then dbTable.bossargs = { CurrentRaidZone = "Molten Core", LastKilledBoss = "Lucifron" } end
	if not dbTable.modes or not dbTable.modes.mode then dbTable.modes = { mode = "Minimum Bid Values", SubZeroBidding = false, rounding = 0, AddToNegative = false, increment = 60, ZeroSumBidType = "Static", AllowNegativeBidders = false } end;
	if not dbTable.modes.ZeroSumBank then dbTable.modes.ZeroSumBank = { balance = 0 } end
	if not dbTable.modes.channels then dbTable.modes.channels = { raid = true, whisper = true, guild = true } end
	if not dbTable.modes.costvalue then dbTable.modes.costvalue = "Integer" end
	if not dbTable.modes.rolls or not dbTable.modes.rolls.min then dbTable.modes.rolls = { min = 1, max = 100, UsePerc = false, AddToMax = 0 } end
	if not dbTable.bossargs.LastKilledNPC then dbTable.bossargs.LastKilledNPC = {} end
	if not dbTable.bossargs.RecentZones then dbTable.bossargs.RecentZones = {} end
	if type(dbTable.CustomEncounters) ~= "table" then dbTable.CustomEncounters = {} end	-- AD-11.2: [zoneName][encounterID] = bossName
	-- AD-12.2: one-time (idempotent) prune of discovered IDs that are now in the static catalog
	for zone, bosses in pairs(dbTable.CustomEncounters) do
		if type(bosses) == "table" then
			for id in pairs(bosses) do
				if CommDKP:Table_Search(core.EncounterList, id) then bosses[id] = nil end	-- now in the static catalog
			end
			if not next(bosses) then dbTable.CustomEncounters[zone] = nil end
		end
	end
	if not dbTable.defaults.HideChangeLogs then dbTable.defaults.HideChangeLogs = 0 end
	if not dbTable.modes.AntiSnipe then dbTable.modes.AntiSnipe = 0 end
	if not dbTable.defaults.CurrentGuild then dbTable.defaults.CurrentGuild = {} end
	if not dbTable.defaults.CurrentTeam then dbTable.defaults.CurrentTeam = "0" end;
	if not dbTable.teams then dbTable.teams = {} end;
	if not dbTable.modes.AnnounceRaidWarning then dbTable.modes.AnnounceRaidWarning = false end;
	if dbTable.defaults.CustomMaxBid == nil then dbTable.defaults.CustomMaxBid = true end;
	if dbTable.defaults.CustomMinBid == nil then dbTable.defaults.CustomMinBid = true end;

	-- 3.1.3 Version Change - Removing installed Variables
	if dbTable.defaults.installed210 then
		dbTable.defaults.installed210 = nil;
	end

	if dbTable.defaults.installed then
		dbTable.defaults.installed = nil;
	end

	if IsInGuild() then
		if not dbTable.teams["0"] then 
			dbTable.teams["0"] = {name=CommDKP:GetGuildName()}
			dbTable.defaults.CurrentTeam = "0";
		end;
		-- AD-9.4: heal a team saved as "No Guild" before guild info had loaded.
		if dbTable.teams["0"] and dbTable.teams["0"].name == L["NOGUILD"] then local g = GetGuildInfo("player"); if g then dbTable.teams["0"].name = g end end
	end

	return dbTable;
end

function CommDKP:InitPlayerTable(globalTable, hasTeams, tableName)
	local playerTable = {};
	playerTable = CommDKP:InitDbSchema(playerTable, tableName);
	if IsInGuild() then

		local realmName = CommDKP:GetRealmName();
		local guildName = CommDKP:GetGuildName();
		

		playerTable = CommDKP:InitializeGuild(playerTable,realmName,guildName);

		if  not globalTable then
			globalTable = {};
		end

		if hasTeams then
			playerTable[realmName][guildName]["0"] = CopyTable(globalTable);
		else
			playerTable[realmName][guildName] = CopyTable(globalTable);
		end
	end
	-- Init Default Table
	playerTable[core.defaultTable] = {};
	return playerTable;
end

function CommDKP:InitializeGuild(dataTable, realmName, guildName)
	local retOK1, hasInfo1 = pcall(CommDKP_tableHasKey,dataTable,realmName);
	
	if (not retOK1) or (retOK1 and not hasInfo1) then
		dataTable[realmName] = {}
	end
	
	if guildName ~= nil then
		local retOK2, hasInfo2 = pcall(CommDKP_tableHasKey,dataTable[realmName],guildName);
		
		if (not retOK2) or (retOK2 and not hasInfo2) then
			dataTable[realmName][guildName] = {}
		end
	end
	
 	return dataTable
end

function CommDKP:InitDbSchema(dbTable, tableName)
	dbTable["dbinfo"] = {};
	dbTable.dbinfo["build"] = 0;
	dbTable.dbinfo["name"] = tableName;
	dbTable.dbinfo["priorbuild"] = 0;
	dbTable.dbinfo["needsUpgrade"] = false;
	return dbTable;
end

----------------------------------
-- Monolith Migration
----------------------------------

function CommDKP:MonolithMigration()
	local _, _, _, _, reason = C_AddOns.GetAddOnInfo("MonolithDKP")
	if reason == "MISSING" or reason == "DISABLED" then
		return false -- MonolithDKP is missing or globally disabled
	end
	
	local loaded, finished = C_AddOns.IsAddOnLoaded("MonolithDKP")
	if not loaded then
		return false -- MonolithDKP is disabled for the current character
	end

	if not finished then
		CommDKP:Print("MonolithDKP has not finished loading - please report to Discord!")
		return false -- Should not happen?! Maybe race condition ...
	end

	-- MonolithDKP is up & running - CommunityDKP will not initialise
	CommDKP:Print("Legacy MonolithDKP addon detected - please disable it to continue with CommunityDKP!")
	local activeCommunity = self:MonolithMigrationDbEntries("CommDKP") -- check if CommunityDKP already has table entries
	local activeCommunitySchema = CommDKP_DB ~= nil and CommDKP:GetTable(CommDKP_DB, false)["teams"] ~= nil -- check if CommunityDKP finished schema migration
	local activeMonolith21x = self:MonolithMigrationLegacySeed() > 0 -- check if there are usable MonolithDKP 2.1.x tables available
	local activeMonolith22x = self:MonolithMigrationDbBuild() > 0 and self:MonolithMigrationDbEntries("MonDKP") -- same for MonolithDKP 2.2.x

	-- check if we should offer migration
	if not activeCommunity and (activeMonolith21x or activeMonolith21x) then
		-- CommunityDKP is fresh and there are MonolithDKP 2.1.x or 2.2.x tables available
		self:MonolithMigrationLegacyDetected(function() self:MonolithMigrationProcess(false) end)
	elseif activeCommunity and activeCommunitySchema and activeMonolith21x and IsInGuild() and CommDKP:ValidateSender(CommDKP:GetPlayerName()) then
		-- CommunityDKP already has data we can import MonolithDKP 2.1.x data as a new team
		self:MonolithMigrationAsNewTeam(function() self:MonolithMigrationProcess(true) end)
	else
 		-- CommunityDKP already has table entries and there is no legacy data to add as an additional team
		self:MonolithMigrationGenericPopup(L["MIGRATIONUNAVAILABLE"])
	end

	return true -- don't initialise CommunityDKP
end

function CommDKP:MonolithMigrationProcess(asNewTeam)
	asNewTeam = asNewTeam or false;

 	-- add a new team?
	local teamIndex
	if asNewTeam then
		teamIndex = CommDKP:AddNewTeamToGuild()
	end

 	-- deep copy so we don't modify the source data
	local copyTableRecursive
	copyTableRecursive = function(obj)
		if type(obj) ~= "table" then return obj end
		local res = {}
		for k, v in pairs(obj) do res[copyTableRecursive(k)] = copyTableRecursive(v) end
		return res
	end

 	-- rename MonDKPScaleSize property to CommDKPScaleSize for each guild / team
	local migrateDefaultsRecursive
	migrateDefaultsRecursive = function(table)
		for k, v in pairs(table) do
			if k == "defaults" then
				if v.MonDKPScaleSize ~= nil then
					v.CommDKPScaleSize = v.MonDKPScaleSize
					v.MonDKPScaleSize = nil
				end
			elseif type(v) == "table" then
				migrateDefaultsRecursive(v)
			end
		end
	end

	-- copy everything from legacy addon
	if asNewTeam then
	 -- local tempDB = copyTableRecursive(MonDKP_DB)
	 -- migrateDefaultsRecursive(tempDB)
	 -- CommDKP:SetTable(CommDKP_DB,         true, tempDB,            teamIndex)

	 -- CommDKP:GetTable(CommDKP_DKPTable,   false)[teamIndex] = MonDKP_DKPTable
		CommDKP:SetTable(CommDKP_DKPTable,   true, MonDKP_DKPTable,   teamIndex)
		CommDKP:SetTable(CommDKP_Loot,       true, MonDKP_Loot,       teamIndex)
		CommDKP:SetTable(CommDKP_DKPHistory, true, MonDKP_DKPHistory, teamIndex)
		CommDKP:SetTable(CommDKP_MinBids,    true, MonDKP_MinBids,    teamIndex)
		CommDKP:SetTable(CommDKP_MaxBids,    true, MonDKP_MaxBids,    teamIndex)
		CommDKP:SetTable(CommDKP_Whitelist,  true, MonDKP_Whitelist,  teamIndex)
		CommDKP:SetTable(CommDKP_Standby,    true, MonDKP_Standby,    teamIndex)
		CommDKP:SetTable(CommDKP_Archive,    true, MonDKP_Archive,    teamIndex)
	else
		local tempDB = copyTableRecursive(MonDKP_DB)
		migrateDefaultsRecursive(tempDB)
		CommDKP_DB         = tempDB

		CommDKP_DKPTable   = MonDKP_DKPTable
		CommDKP_Loot       = MonDKP_Loot
		CommDKP_DKPHistory = MonDKP_DKPHistory
		CommDKP_MinBids    = MonDKP_MinBids
		CommDKP_MaxBids    = MonDKP_MaxBids
		CommDKP_Whitelist  = MonDKP_Whitelist
		CommDKP_Standby    = MonDKP_Standby
		CommDKP_Archive    = MonDKP_Archive
	end

	-- show completion popup
	self:MonolithMigrationGenericPopup(L["MIGRATIONCOMPLETED"])
end

function CommDKP:MonolithMigrationLegacyDetected(migration)
	StaticPopupDialogs["MONOLITH_MIGRATION_DETECTED"] = {
		text = L["MIGRATIONDETECTED"],
		button1 = L["YES"],
		button2 = L["NO"],
		OnAccept = function() self:MonolithMigrationConfirmationPopup(migration) end,
		OnCancel = function() self:MonolithMigrationCancelationPopup() end,
		timeout = 0,
		whileDead = true,
		hideOnEscape = true,
		preferredIndex = 3,
	}
	StaticPopup_Show("MONOLITH_MIGRATION_DETECTED")
end

function CommDKP:MonolithMigrationAsNewTeam(migration)
	StaticPopupDialogs["MONOLITH_MIGRATION_TEAM"] = {
		text = L["MIGRATIONTEAM"],
		button1 = L["YES"],
		button2 = L["NO"],
		OnAccept = migration,
		OnCancel = function() self:MonolithMigrationCancelationPopup() end,
		timeout = 0,
		whileDead = true,
		hideOnEscape = true,
		preferredIndex = 3,
	}
	StaticPopup_Show("MONOLITH_MIGRATION_TEAM")
end

function CommDKP:MonolithMigrationConfirmationPopup(migration)
	StaticPopupDialogs["MONOLITH_MIGRATION_CONFIRMATION"] = {
		text = "|CFFFF0000"..L["WARNING"].."|r: "..L["MIGRATIONCONFIRM"],
		button1 = L["YES"],
		button2 = L["NO"],
		OnAccept = migration,
		OnCancel = function() self:MonolithMigrationCancelationPopup() end,
		timeout = 0,
		whileDead = true,
		hideOnEscape = true,
		preferredIndex = 3,
	}
	StaticPopup_Show("MONOLITH_MIGRATION_CONFIRMATION")
end

function CommDKP:MonolithMigrationCancelationPopup()
	StaticPopupDialogs["MONOLITH_MIGRATION_CANCELED"] = {
		text = L["MIGRATIONCANCELED"],
		button1 = L["OK"],
		timeout = 0,
		whileDead = true,
		hideOnEscape = true,
		preferredIndex = 3,
	}
	StaticPopup_Show("MONOLITH_MIGRATION_CANCELED")
end

function CommDKP:MonolithMigrationGenericPopup(text)
	StaticPopupDialogs["MONOLITH_MIGRATION_GENERIC"] = {
		text = text,
		button1 = L["OK"],
		timeout = 0,
		whileDead = true,
		hideOnEscape = true,
		preferredIndex = 3,
	}
	StaticPopup_Show("MONOLITH_MIGRATION_GENERIC")
end

function CommDKP:MonolithMigrationLegacySeed()
	-- returns the latest seed timestamp (version 2.1.x) or 0 if it won't find anything
	local lootSeed = 0
	local historySeed = 0

	if MonDKP_Loot ~= nil and #MonDKP_Loot > 0 and MonDKP_Loot[1].index ~= nil and strfind(MonDKP_Loot[1].index, "-") ~= nil then
		lootSeed = tonumber(strsub(MonDKP_Loot[1].index, strfind(MonDKP_Loot[1].index, "-") + 1))
	end
	if MonDKP_DKPHistory ~= nil and #MonDKP_DKPHistory > 0 and MonDKP_DKPHistory[1].index ~= nil and strfind(MonDKP_DKPHistory[1].index, "-") ~= nil then
		historySeed = tonumber(strsub(MonDKP_DKPHistory[1].index, strfind(MonDKP_DKPHistory[1].index, "-") + 1))
	end

	return math.max(lootSeed or 0, historySeed or 0)
end

function CommDKP:MonolithMigrationDbBuild()
	-- returns the db build version (version 2.2.x) or 0 if it won't find anything
	local build = 0

	if MonDKP_DB ~= nil and MonDKP_DB.dbinfo ~= nil and MonDKP_DB.dbinfo.build ~= nil then
		build = tonumber(MonDKP_DB.dbinfo.build)
	end

	return build or 0
end

function CommDKP:MonolithMigrationDbEntries(prefix)
	-- returns true if there are already CommunityDKP entries
	local findEntryRecursive
	findEntryRecursive = function(table, entry)
		if table == nil then
			return false
		end

		for k, v in pairs(table) do
			if k == entry then
				return true -- entry found - ABORT!
			elseif type(v) == "table" and findEntryRecursive(v, entry) then
				return true -- entry in child table found - ABORT!
			end
		end

		return false
	end

	if prefix ~= nil and prefix == "MonDKP" then
		return findEntryRecursive(MonDKP_DKPHistory, "players")
			or findEntryRecursive(MonDKP_DKPTable, "player")
			or findEntryRecursive(MonDKP_Loot, "player")
	else
		return findEntryRecursive(CommDKP_DKPHistory, "players")
			or findEntryRecursive(CommDKP_DKPTable, "player")
			or findEntryRecursive(CommDKP_Loot, "player")
	end
end

----------------------------------
-- Register Events and Initiallize AddOn
----------------------------------

local events = CreateFrame("Frame", "EventsFrame");
events:RegisterEvent("ADDON_LOADED");
events:RegisterEvent("GROUP_ROSTER_UPDATE");
events:RegisterEvent("ENCOUNTER_START");      -- sets core.InEncounter (CDKP-003)
events:RegisterEvent("ENCOUNTER_END");        -- clears core.InEncounter, records killed boss (CDKP-003)
events:RegisterEvent("LOOT_OPENED")
events:RegisterEvent("CHAT_MSG_RAID")
events:RegisterEvent("CHAT_MSG_RAID_LEADER")
events:RegisterEvent("CHAT_MSG_WHISPER");
events:RegisterEvent("CHAT_MSG_GUILD")
events:RegisterEvent("GUILD_ROSTER_UPDATE")
events:RegisterEvent("PLAYER_ENTERING_WORLD")
events:RegisterEvent("ZONE_CHANGED_NEW_AREA")
events:RegisterEvent("BOSS_KILL")
events:RegisterEvent("TRADE_SHOW")
events:RegisterEvent("TRADE_ACCEPT_UPDATE")
events:RegisterEvent("TRADE_CLOSED")
events:SetScript("OnEvent", CommDKP_OnEvent); -- calls the above CommDKP_OnEvent function to determine what to do with the event
