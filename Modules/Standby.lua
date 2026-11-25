local _, core = ...;
local _G = _G;
local CommDKP = core.CommDKP;
local L = core.L;

local function CMD_Handler(...)
	local _, cmd = string.split(" ", ..., 2)

	if tonumber(cmd) then
		cmd = tonumber(cmd) -- converts it to a number if it's a valid numeric string
	end

	return cmd;
end

function CommDKP_Standby_Announce(bossName)
	core.StandbyActive = true; -- activates opt in
	table.wipe(CommDKP:GetTable(CommDKP_Standby, true));
	if CommDKP:CheckRaidLeader() then
		CommDKP:SendChat(bossName..L["STANDBYOPTINBEGIN"], "GUILD") -- only raid leader announces
	end
	C_Timer.After(120, function ()
		core.StandbyActive = false;  -- deactivates opt in
		if CommDKP:CheckRaidLeader() then
			CommDKP:SendChat(L["STANDBYOPTINEND"]..bossName, "GUILD") -- only raid leader announces
			if core.DB.DKPBonus.AutoIncStandby then
				CommDKP:AutoAward(2, core.DB.DKPBonus.BossKillBonus, core.DB.bossargs.CurrentRaidZone..": "..core.DB.bossargs.LastKilledBoss)
			end
		end
	end)
end

-- AD-15.4(a): registered once at file scope (was re-registered on every handler call).
ChatFrame_AddMessageEventFilter("CHAT_MSG_WHISPER_INFORM", function(self, event, msg, ...)		-- suppresses outgoing whisper responses to limit spam
	if issecretvalue and issecretvalue(msg) then return false end
	if core.StandbyActive and core.DB and core.DB.defaults.SuppressTells then
		if type(msg) == "string" and strfind(msg, "CommunityDKP: ", 1, true) then
			return true
		end
	end
end)

function CommDKP_Standby_Handler(text, ...)
	local name = ...;
	if issecretvalue and (issecretvalue(text) or (name ~= nil and issecretvalue(name))) then return end  -- AD-15.4
	if type(text) ~= "string" then return end
	local cmd;
	local response = L["ERRORPROCESSING"];

	name = CommDKP:ResolveRosterName(name) or CommDKP:NormalizeName(name) or name	-- AD-15.4 / AD-9.6

	if string.find(text, "!standby") == 1 and core.IsOfficer then
		cmd = tostring(CMD_Handler(text))

		if cmd and strtrim(cmd) ~= "nil" and strtrim(cmd) ~= "" then
			-- if it's !standby *name*
			cmd = strtrim(cmd)											-- keep the inner First/Last space
			cmd = CommDKP:ResolveRosterName(cmd) or cmd
			local search = CommDKP:Table_Search(CommDKP:GetTable(CommDKP_DKPTable, true), cmd, "player")
			local verify = CommDKP:Table_Search(CommDKP:GetTable(CommDKP_Standby, true), cmd, "player")
			if search then cmd = CommDKP:GetTable(CommDKP_DKPTable, true)[search[1][1]].player end  -- canonical casing in the reply

			if search and not verify then
				table.insert(CommDKP:GetTable(CommDKP_Standby, true), CommDKP:GetTable(CommDKP_DKPTable, true)[search[1][1]])
				response = "CommunityDKP: "..cmd.." "..L["STANDBYWHISPERRESP1"]
			elseif search and verify then
				response = "CommunityDKP: "..cmd.." "..L["STANDBYWHISPERRESP2"]
			else
				response = "CommunityDKP: "..cmd.." "..L["STANDBYWHISPERRESP3"];
			end
		else
			-- if it's just !standby
			local search = CommDKP:Table_Search(CommDKP:GetTable(CommDKP_DKPTable, true), name, "player")
			local verify = CommDKP:Table_Search(CommDKP:GetTable(CommDKP_Standby, true), name, "player")

			if search and not verify then
				table.insert(CommDKP:GetTable(CommDKP_Standby, true), CommDKP:GetTable(CommDKP_DKPTable, true)[search[1][1]])
				response = "CommunityDKP: "..L["STANDBYWHISPERRESP4"]
			elseif search and verify then
				response = "CommunityDKP: "..L["STANDBYWHISPERRESP5"]
			else
				response = "CommunityDKP: "..L["STANDBYWHISPERRESP6"];
			end
		end
		if CommDKP:CheckRaidLeader() then 						 -- only raid leader responds to add.
			CommDKP:SendChat(response, "WHISPER", nil, name)
		end
	end
end
