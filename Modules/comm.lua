--[[
  Usage so far:  CommDKP.Sync:SendData(prefix, core.WorkingTable)  --sends table through comm channel for updates
--]]  

local _, core = ...;
local _G = _G;
local CommDKP = core.CommDKP;
local L = core.L;

CommDKP.Sync = LibStub("AceAddon-3.0"):NewAddon("CommDKP", "AceComm-3.0")

local LibAceSerializer = LibStub:GetLibrary("AceSerializer-3.0")
local LibDeflate = LibStub:GetLibrary("LibDeflate")

-- AD-10.5: true if a history entry with this index is among the most recent `depth` (default 100) entries.
-- History tables are newest-first, so this catches self-echoes and duplicate deliveries cheaply.
local function AlreadyHaveIndex(tbl, index, depth)
  if index == nil or type(tbl) ~= "table" then return false end
  for i = 1, math.min(#tbl, depth or 100) do
    if tbl[i] and tbl[i].index == index then return true end
  end
  return false
end
CommDKP.AlreadyHaveIndex = AlreadyHaveIndex  -- exposed for headless tests

function CommDKP:ValidateSender(sender)                -- returns true if "sender" has permission to write officer notes. false if not or not found.
  sender = CommDKP:ResolveRosterName(sender)           -- AD-10.3: legacy bare first names ("Bank") -> "Bank Robbers"
  local rankIndex = CommDKP:GetGuildRankIndex(sender);

  if rankIndex == 1 then             -- automatically gives permissions above all settings if player is guild leader
    return true;
  end
  if #CommDKP:GetTable(CommDKP_Whitelist) > 0 then                  -- if a whitelist exists, checks that rather than officer note permissions
    for i=1, #CommDKP:GetTable(CommDKP_Whitelist) do
      if CommDKP:SamePlayer(CommDKP:GetTable(CommDKP_Whitelist)[i], sender) then
        return true;
      end
    end
    return false;
  else
    if rankIndex then
      local ok, flags = pcall(function() return C_GuildInfo and C_GuildInfo.GuildControlGetRankFlags and C_GuildInfo.GuildControlGetRankFlags(rankIndex) end)
      if ok and type(flags) == "table" and flags[12] ~= nil then
        return flags[12] and true or false
      end
      return false                     -- AD-34.4 (G-26.5): unresolvable rank flags fail closed (BR-26.3)
    else
      return false;
    end
  end
end

-------------------------------------------------
-- Register Broadcast Prefixs
-------------------------------------------------

function CommDKP.Sync:OnEnable()
  CommDKP.Sync:RegisterComm("CommDKPDelUsers", CommDKP.Sync:OnCommReceived())      -- Broadcasts deleted users (archived users not on the DKP table)
  CommDKP.Sync:RegisterComm("CommDKPAddUsers", CommDKP.Sync:OnCommReceived())   -- Broadcasts newly added users (or recovers)
  CommDKP.Sync:RegisterComm("CommDKPMerge", CommDKP.Sync:OnCommReceived())      -- Broadcasts 2 weeks of data from officers (for merging)
  -- Normal broadcast Prefixs
  CommDKP.Sync:RegisterComm("CommDKPDecay", CommDKP.Sync:OnCommReceived())        -- Broadcasts a weekly decay adjustment
  CommDKP.Sync:RegisterComm("CommDKPBCastMsg", CommDKP.Sync:OnCommReceived())      -- broadcasts a message that is printed as is
  CommDKP.Sync:RegisterComm("CommDKPCommand", CommDKP.Sync:OnCommReceived())      -- broadcasts a command (ex. timers, bid timers, stop all timers etc.)
  CommDKP.Sync:RegisterComm("CommDKPLootDist", CommDKP.Sync:OnCommReceived())      -- broadcasts individual loot award to loot table
  CommDKP.Sync:RegisterComm("CommDKPDelLoot", CommDKP.Sync:OnCommReceived())      -- broadcasts deleted loot award entries
  CommDKP.Sync:RegisterComm("CommDKPDelSync", CommDKP.Sync:OnCommReceived())      -- broadcasts deleated DKP history entries
  CommDKP.Sync:RegisterComm("CommDKPDKPDist", CommDKP.Sync:OnCommReceived())      -- broadcasts individual DKP award to DKP history table
  CommDKP.Sync:RegisterComm("CommDKPMinBid", CommDKP.Sync:OnCommReceived())      -- broadcasts minimum dkp values (set in Options tab or custom values in bid window)
  CommDKP.Sync:RegisterComm("CommDKPMaxBid", CommDKP.Sync:OnCommReceived())      -- broadcasts maximum dkp values (set in Options tab or custom values in bid window)
  CommDKP.Sync:RegisterComm("CDKPWhitelist", CommDKP.Sync:OnCommReceived())      -- broadcasts whitelist
  CommDKP.Sync:RegisterComm("CommDKPDKPModes", CommDKP.Sync:OnCommReceived())      -- broadcasts DKP Mode settings
  CommDKP.Sync:RegisterComm("CommDKPStand", CommDKP.Sync:OnCommReceived())        -- broadcasts standby list
  CommDKP.Sync:RegisterComm("CommDKPRaidTime", CommDKP.Sync:OnCommReceived())      -- broadcasts Raid Timer Commands
  CommDKP.Sync:RegisterComm("CommDKPZSumBank", CommDKP.Sync:OnCommReceived())    -- broadcasts ZeroSum Bank
  CommDKP.Sync:RegisterComm("CommDKPQuery", CommDKP.Sync:OnCommReceived())        -- Querys guild for spec/role data
  CommDKP.Sync:RegisterComm("CommDKPSeed", CommDKP.Sync:OnCommReceived())
  CommDKP.Sync:RegisterComm("CommDKPBuild", CommDKP.Sync:OnCommReceived())        -- broadcasts Addon build number to inform others an update is available.
  CommDKP.Sync:RegisterComm("CommDKPTalents", CommDKP.Sync:OnCommReceived())      -- broadcasts current spec
  CommDKP.Sync:RegisterComm("CommDKPRoles", CommDKP.Sync:OnCommReceived())        -- broadcasts current role info
  CommDKP.Sync:RegisterComm("CommDKPBossLoot", CommDKP.Sync:OnCommReceived())      -- broadcast current loot table
  CommDKP.Sync:RegisterComm("CommDKPBidShare", CommDKP.Sync:OnCommReceived())      -- broadcast accepted bids
  CommDKP.Sync:RegisterComm("CommDKPBidder", CommDKP.Sync:OnCommReceived())      -- Submit bids
  CommDKP.Sync:RegisterComm("CommDKPAllTabs", CommDKP.Sync:OnCommReceived())      -- Full table broadcast
  CommDKP.Sync:RegisterComm("CommDKPSetPrice", CommDKP.Sync:OnCommReceived())      -- Set Single Item Price
  CommDKP.Sync:RegisterComm("CommDKPCurTeam", CommDKP.Sync:OnCommReceived())      -- Sets Current Raid Team
  CommDKP.Sync:RegisterComm("CommDKPTeams", CommDKP.Sync:OnCommReceived())
  CommDKP.Sync:RegisterComm("CommDKPPreBroad", CommDKP.Sync:OnCommReceived()) -- send info that full broadcast is starting
  --CommDKP.Sync:RegisterComm("CommDKPEditLoot", CommDKP.Sync:OnCommReceived())    -- not in use
  --CommDKP.Sync:RegisterComm("CommDKPDataSync", CommDKP.Sync:OnCommReceived())    -- not in use
  --CommDKP.Sync:RegisterComm("CommDKPDKPLogSync", CommDKP.Sync:OnCommReceived())  -- not in use
  --CommDKP.Sync:RegisterComm("CommDKPLogSync", CommDKP.Sync:OnCommReceived())    -- not in use
  CommDKP.Sync:RegisterComm("CDKProfileSend", CommDKP.Sync:OnCommReceived()) -- Broadcast Player Profile for Update or Create
end

function GetNameFromLink(link)
  if link == nil then
    return "Item Name Not Found - Bad Link";
  end

  local _, _, Color, Ltype, itemID, Enchant, Gem1, Gem2, Gem3, Gem4, Suffix, Unique, LinkLvl, Name = string.find(link,"|?c?f?f?(%x*)|?H?([^:]*):?(%d+):?(%d*):?(%d*):?(%d*):?(%d*):?(%d*):?(%-?%d*):?(%-?%d*):?(%d*):?(%d*):?(%-?%d*)|?h?%[?([^%[%]]*)%]?|?h?|?r?");
  return Name;
end

-- main functions that receives all communication via appropriate channels
function CommDKP.Sync:OnCommReceived(prefix, message, distribution, sender)

  local isMetaPrefix = (prefix == "CDKProfileSend" or prefix == "CommDKPTalents" or prefix == "CommDKPRoles")
  if (isMetaPrefix and not core.DB) or (not isMetaPrefix and (not core.Initialized or core.IsOfficer == nil)) then
    -- AD-30.1.7 (BR-22.1): G1 drop is visible in the session-only comm trace. Meta prefixes only require core.DB.
    if core.CommTrace and (isMetaPrefix or prefix == "CommDKPSeed") then
      CommDKP:CommTrace("RECV %s from=%s DROPPED (initialized=%s officer=%s)", tostring(prefix), tostring(sender), tostring(core.Initialized), tostring(core.IsOfficer))
    end
    return; 
  end

  if prefix then
    if CommDKP:IsSelf(sender) then core.LastSelfEchoSender = sender end  -- AD-10.9: /dkp test telemetry
    local decoded = LibDeflate:DecodeForWoWAddonChannel(message);
    local decompressed = decoded and LibDeflate:DecompressDeflate(decoded) or nil;
    if decompressed == nil then
      local pDecoded = LibDeflate:DecodeForPrint(message)
      if pDecoded then decompressed = LibDeflate:DecompressDeflate(pDecoded) end
    end
    if decompressed == nil then
      local cDecoded = LibDeflate:DecodeForWoWChatChannel(message)
      if cDecoded then decompressed = LibDeflate:DecompressDeflate(cDecoded) end
    end

    
    if decompressed == nil then  -- this checks if message was previously encoded and compressed
      -- < 3.2.4-r61 CommDKPBuild msg handler
      if prefix == "CommDKPBuild" and not CommDKP:IsSelf(sender) then
        local LastVerCheck = time() - core.LastVerCheck;

        if LastVerCheck > 900 then             -- limits the Out of Date message from firing more than every 15 minutes 
          if tonumber(message) > core.BuildNumber then
            core.LastVerCheck = time();
            CommDKP:Print(L["OUTOFDATEANNOUNCE"])
          end
        end

        if tonumber(message) < core.BuildNumber then   -- returns build number if receiving party has a newer version
          CommDKP.Sync:SendData("CommDKPBuild", tostring(core.BuildNumber))
        end
        return;
      elseif prefix == "CommDKPBuild" and CommDKP:IsSelf(sender) then
        return;
      else
        CommDKP:Print("Unknown comm Received with prefix "..prefix.." from "..sender);
      end      
      return;
    end

    -- decompresed is not null meaning data is coming from 2.3.0 or CommunityDKP
    local success, _objReceived = LibAceSerializer:Deserialize(decompressed);   -- AD-15.5(b)
    
    --[[ 
      _objReceived = {
        Teams = {},
        CurrentTeam = "0",
        Data = string | {} | nil
      }
    --]]

    if success then
      if prefix == "CommDKPQuery" then
        ------------------------------
        -- This has been deprecated --
        ------------------------------
        return;
      elseif prefix == "CommDKPSeed" then
        CommDKP:SeedReceived(_objReceived, sender);
        return;
      elseif prefix == "CommDKPBidder" then
        CommDKP:BidderReceived(_objReceived, sender, distribution);
        return;
      elseif prefix == "CDKProfileSend" then
        CommDKP:ProfileReceived(_objReceived, sender, distribution);   -- AD-30.1.7
        return;
      elseif prefix == "CommDKPTalents" then
        CommDKP:TalentsReceived(_objReceived, sender, distribution);   -- AD-30.1.7
        return;
      elseif prefix == "CommDKPRoles" then
        CommDKP:RolesReceived(_objReceived, sender, distribution);   -- AD-30.1.7
        return;
      elseif prefix == "CommDKPBuild" then
        CommDKP:BuildReceived(_objReceived, sender);
        return;
      end

      -- AD-36.5.2 (BR-28.13, CM-08): the team list and the current team are officer data (G4): validated, non-self only.
      if prefix == "CommDKPTeams" or prefix == "CommDKPCurTeam" then
        if not CommDKP:IsSelf(sender) and CommDKP:ValidateSender(sender) then
          if prefix == "CommDKPTeams" then CommDKP:TeamsReceived(_objReceived, sender) else CommDKP:CurTeamReceived(_objReceived, sender) end
        elseif core.CommTrace then
          CommDKP:CommTrace("RECV %s from=%s DROPPED (G4: not a validated officer, or self)", tostring(prefix), tostring(sender))
        end
        return
      end

      ---
      -- OFFICER LEVEL DATA
      ---
      if CommDKP:ValidateSender(sender) then    -- validates sender as an officer. fail-safe to prevent addon alterations to manipulate DKP table

        if (prefix == "CommDKPBCastMsg") and not CommDKP:IsSelf(sender) then
          CommDKP:Print(_objReceived.Data);
          return;
        elseif prefix == "CommDKPPreBroad" then
          CommDKP:PreBroadReceived(_objReceived, sender);
          return;
        elseif prefix == "CommDKPCommand" then
          CommDKP:CommandReceived(_objReceived, sender);
          return;
        elseif prefix == "CommDKPRaidTime" then
          CommDKP:RaidTimeReceived(_objReceived, sender);
          return;
        end

        if not CommDKP:IsSelf(sender) then
          if prefix == "CommDKPAllTabs" then   -- receives full table broadcast
            CommDKP:AllTabsReceived(_objReceived, sender);
            return;
          elseif prefix == "CommDKPMerge" then
            CommDKP:MergeReceived(_objReceived, distribution, sender);
            return;
          elseif prefix == "CommDKPLootDist" then
            CommDKP:LootDistReceived(_objReceived);
            return;
          elseif prefix == "CommDKPDKPDist" then
            CommDKP:DKPDistReceived(_objReceived);
            return;
          elseif prefix == "CommDKPDecay" then
            CommDKP:DKPDecayReceived(_objReceived);
            return;
          elseif prefix == "CommDKPAddUsers" then
            CommDKP:AddUsersReceived(_objReceived, sender);
            return;
          elseif prefix == "CommDKPDelUsers" then
            CommDKP:DelUsersReceived(_objReceived, sender);
            return;
          elseif prefix == "CommDKPDelLoot" then
            CommDKP:DelLootReceived(_objReceived);
            return;
          elseif prefix == "CommDKPDelSync" then
            CommDKP:DelSyncReceived(_objReceived);
            return;
          elseif prefix == "CommDKPMinBid" then
            CommDKP:MinBidReceived(_objReceived);
            return;
          elseif prefix == "CommDKPMaxBid" then
            CommDKP:MaxbidReceived(_objReceived);
            return;
          elseif prefix == "CDKPWhitelist" then 
            CommDKP:WhiteListReceived(_objReceived);
            return;
          elseif prefix == "CommDKPStand" then
            CommDKP:StandByReceived(_objReceived);
            return;
          elseif prefix == "CommDKPSetPrice" then
            CommDKP:SetPriceReceived(_objReceived);
            return;
          elseif prefix == "CommDKPZSumBank" then
            CommDKP:ZSumBankReceived(_objReceived);
            return;
          elseif prefix == "CommDKPDKPModes" then
            CommDKP:DKPModesReceived(_objReceived);
            return;
          elseif prefix == "CommDKPBidShare" then
            CommDKP:BidShareReceived(_objReceived);
            return;
          elseif prefix == "CommDKPBossLoot" then
            CommDKP:BossLootReceived(_objReceived);
          end 
        end
      end
    else -- success == false
      CommDKP:Print("OnCommReceived ERROR: "..prefix)  -- error reporting if string doesn't get deserialized correctly
    end
  end
end

-- AD-6.1: xpcall handler for SendData's dispatch. Appends the stack at the point of failure, so the
-- rethrown error still points at the *Send function that failed, not at SendData's rethrow line.
local function WithStack(e)
  return (debugstack and (tostring(e) .. "\n" .. debugstack(2))) or e
end

function CommDKP.Sync:SendData(prefix, data, target, targetTeam, prio)

  -- 2.3.0 object being sent with almost everything?
  -- the idea is to envelope the old message into another object and then decode it on receiving end
  -- that way we won't have to do too much diging in the old code
  -- expect to send everything through SendData
  -- the only edge case is CommDKPBuild which for now stays the same as it was in 2.1.2

  targetTeam = targetTeam or CommDKP:GetCurrentTeamIndex();

  local _objToSend = {
    Teams = CommDKP:GetTable(CommDKP_DB, false)["teams"],
    CurrentTeam = CommDKP:GetCurrentTeamIndex(),
    TargetTeam = targetTeam,
    Data = nil,
    Prefix = prefix
  };

  -- everything else but CommDKPBuild is getting compressed
  _objToSend.Data = data; -- if we send table everytime we have to serialize / deserialize anyway
  
  local _compressedObj = CommDKP.Sync:SerializeTableToString(_objToSend);

  if _compressedObj == nil then
    CommDKP:Print("prefix"..prefix.." ");
    CommDKP:Print("Compressing is fucked mate");
  end

  if data == nil or data == "" then data = " " end -- just in case, to prevent disconnects due to empty/nil string AddonMessages

  --AceComm Communication doesn't work if the prefix is longer than 15.  And if sucks if you try.
  if #prefix > 15 then
    CommDKP:Print("CommunityDKP Error: Prefix ["..prefix.."] is longer than 15. Please shorten.");
    return;
  end

  -- AD-14.2: we are the auctioneer; process our own bid locally, no network round trip.
  -- Runs before Dispatch so it works solo, in a party, in a raid, and guildless.
  if prefix == "CommDKPBidder" and core.BidInProgress and core.IsOfficer then
    CommDKP:BidderLocal(data)
    return;
  end

  -- at this point object is ready to be sent

  -- CDKP-003 F3-a (AD-5.1 change B): CommGate collapses deferred snapshots per team, but it only sees
  -- serialized text, so stamp the team key for the duration of this synchronous dispatch.
  -- Cleared on every exit (early returns inside Dispatch, and errors via pcall + rethrow).
  local function Dispatch()
  -- AD-26.5.2 (BR-18.7): own spec / role / version reach the guild, or the group when guildless. Solo + guildless: silent.
  if prefix == "CommDKPTalents" or prefix == "CommDKPRoles" or prefix == "CDKProfileSend" then
    local ch = IsInGuild() and "GUILD" or CommDKP:GetGroupCommChannel(false)
    if not ch then
      CommDKP:RecordMetaSend(prefix, "none", "NoChannel")                        -- AD-30.1.7: was a silent return
      return
    end
    -- AD-30.1.4 (BR-22.2): per-message context as the AceComm callback (final result, GUILD -> group fallback)
    local ctx = { prefix = prefix, channel = ch, text = _compressedObj, fallback = false }
    local cb = function(c, sent, total, didSend, result) CommDKP:OnMetaSendResult(c, sent, total, didSend, result) end
    if prefix == "CommDKPTalents" then CommDKP:TalentsSend(prefix, _compressedObj, ch, cb, ctx)
    elseif prefix == "CommDKPRoles" then CommDKP:RolesSend(prefix, _compressedObj, ch, cb, ctx)
    else CommDKP:ProfileSend(prefix, _compressedObj, ch, cb, ctx) end
    return
  end
  if IsInGuild() then
    if prefix == "CommDKPQuery" then
      CommDKP:QuerySend(prefix, _compressedObj, "GUILD");
      return;
    elseif prefix == "CommDKPBidder" then -- bid submissions. AD-14.1: group-relative
      CommDKP:BidderSend(prefix, _compressedObj, "RAID");
      return;
    elseif prefix == "CommDKPBuild" then
      CommDKP:BuildSend(prefix, _compressedObj, "GUILD");
      return;
    elseif prefix == "CommDKPSeed" then
      local seedCtx = { prefix = "CommDKPSeed", channel = "GUILD", fallback = true }
      CommDKP.Sync:SendCommMessage(prefix, _compressedObj, "GUILD", nil, "NORMAL",
        function(c, sent, total, didSend, result) CommDKP:OnMetaSendResult(c, sent, total, didSend, result) end, seedCtx)
      return;
    end

    if core.IsOfficer then
      if prefix == "CommDKPCommand" then
        CommDKP:CommandSend(prefix, _compressedObj, "RAID");
        return;
      end
  
      if prefix == "CommDKPRaidTime" then
        CommDKP:RaidTimeSend(prefix, _compressedObj, "RAID");
        return;
      end
  
      if prefix == "CommDKPBCastMsg" then

        if target == nil then
          CommDKP:CastMsgSend(prefix, _compressedObj, target, nil, prio);
        else
          CommDKP:CastMsgSend(prefix, _compressedObj, "WHISPER", target, prio);
        end;
      
        return;
      end  
  
      if prefix == "CommDKPZSumBank" then
        CommDKP:ZSumBankSend(prefix, _compressedObj, "RAID");
        return;
      end  
  
      if prefix == "CommDKPBossLoot" then
        CommDKP:BossLootSend(prefix, _compressedObj, "RAID");
        return;
      end  
  
      if prefix == "CommDKPBidShare" then
        CommDKP:BidShareSend(prefix, _compressedObj, "RAID");
        return;
      end  
  
      if prefix == "CommDKPPreBroad" then
        CommDKP:PreBroadSend(prefix, _compressedObj, target);
        return;
      end
  
      if prefix == "CommDKPAllTabs" then
        CommDKP:AllTabsSend(prefix, _compressedObj, target);
        return;
      end
  
      if prefix == "CommDKPMerge" then
        CommDKP:MergeSend(prefix, _compressedObj, target);
        return;
      end
      
      -- what is being sent here?
      if target then
        CommDKP.Sync:SendCommMessage(prefix, CommDKP.Sync:ToPrintSafePacket(_compressedObj), "WHISPER", target)   -- AD-36.6.3 (BR-28.20)
      else
        CommDKP.Sync:SendCommMessage(prefix, _compressedObj, "GUILD")
      end
    end

  end
  end -- Dispatch

  -- Save/restore (not just clear): AllTabsSend/MergeSend call SendData("CommDKPPreBroad") *inside* this
  -- dispatch, and the outer AllTabs/Merge send that follows must keep its own stamp.
  local prevTeamKey = CommDKP.Sync._gateTeamKey
  CommDKP.Sync._gateTeamKey = tostring(_objToSend.CurrentTeam) .. ":" .. tostring(targetTeam)
  local ok, err = xpcall(Dispatch, WithStack)   -- AD-6.1: keep the failing *Send frame in the error report
  CommDKP.Sync._gateTeamKey = prevTeamKey
  if not ok then error(err, 0) end             -- rethrow: legacy SendData let errors stop the caller
end


-- AD-34.2 (G-26.2, B6b): print-safe (6-bit) form of ONE addon-channel packet. Pure; no shared state.
-- Non-string input (headless sandboxes pass tables) or any decode failure returns the packet unchanged.
function CommDKP.Sync:ToPrintSafePacket(packet)
  if type(packet) ~= "string" then return packet end
  local raw = LibDeflate:DecodeForWoWAddonChannel(packet)
  if type(raw) ~= "string" then return packet end
  return LibDeflate:EncodeForPrint(raw) or packet
end

function CommDKP.Sync:SerializeTableToString(data)

  local serialized = nil;
  local packet = nil;

  if data then
    serialized = LibAceSerializer:Serialize(data); -- serializes tables to a string
  end
  
  local compressed = LibDeflate:CompressDeflate(serialized, {level = 9})
    if compressed then
      packet = LibDeflate:EncodeForWoWAddonChannel(compressed)
    end
  return packet;
end


function CommDKP.Sync:DeserializeStringToTable(_string)

  if not _string == nil then

    local decoded = LibDeflate:DecompressDeflate(LibDeflate:DecodeForWoWAddonChannel(_string))
    local success, _obj  = LibAceSerializer:Deserialize(decoded);

    CommDKP:Print("success: "..success)  -- error reporting if string doesn't get deserialized correctly
    if not success then
      CommDKP:Print("_string: ".._string)  -- error reporting if string doesn't get deserialized correctly
      CommDKP:Print("decoded: "..decoded)  -- error reporting if string doesn't get deserialized correctly
    end

    return success, _obj;
  end

end


----------
-- FULL BROADCAST HANDLERS
----------

function CommDKP:AllTabsSend(prefix, commObject, channel)
  local _channel = channel or "GUILD";
  local _prefix = prefix or "CommDKPAllTabs";

  if channel then -- check if we are targeting specific player
    print("[CommunityDKP] COMMS: You started Full Broadcast for team "..CommDKP:GetTeamName(CommDKP:GetCurrentTeamIndex()).." to player "..channel);
    local wPacket = CommDKP.Sync:ToPrintSafePacket(commObject)   -- AD-34.2 (G-26.2)
    CommDKP.Sync:SendCommMessage(prefix, wPacket, "WHISPER", channel, "NORMAL", CommDKP_BroadcastFull_Callback, channel);
  else
    CommDKP.Sync:SendData("CommDKPPreBroad", prefix, nil);
    CommDKP.Sync:SendCommMessage(prefix, commObject, _channel, nil, "NORMAL", CommDKP_BroadcastFull_Callback, _channel);
  end
end


function CommDKP:AllTabsReceived(commObject, sender)   -- AD-15.5(a)
  --[[ 
      commObject = {
        Teams = {},
        CurrentTeam = "0",
        Data = {
          DKPTable = {},
          DKP = {}, 
          Loot = {}, 
          Archive = {}, 
          MinBids = {},
          Teams= {} 
        }
      }
    --]]

  -- AD-30.1.3(b): what this broadcast says about MY row, captured before anything is sorted or overwritten.
  if not CommDKP:IsSelf(sender) then core.LastOfficerSender = sender end
  local selfState = CommDKP:IncomingSelfMetaState(commObject.Data and commObject.Data.DKPTable)
  core.LastBroadcastSelfMeta = { state = selfState, kind = "full", from = CommDKP:NormalizeName(sender), t = GetTime() }
  if type(commObject.Data) == "table" and type(commObject.Data.DKPTable) == "table" then
    local curRows = CommDKP:GetTable(CommDKP_DKPTable, true, commObject.CurrentTeam)
    local curProfs = CommDKP:GetTable(CommDKP_Profiles, true, commObject.CurrentTeam)
    local harvested = false
    for i = 1, #commObject.Data.DKPTable do
      local src = commObject.Data.DKPTable[i]
      if type(src) == "table" and type(src.player) == "string" and src.player ~= "" and not CommDKP:IsSelf(src.player) then
        CommDKP:CachePlayerMeta(src.player, { spec = src.spec, roleData = not CommDKP:IsPlaceholderMeta("role", src.role) and src.spec or nil, version = src.version, class = src.class }, true)   -- AD-34.6: relayed = fill-only
        local hit = CommDKP:Table_Search(curRows, src.player, "player")
        if hit then
          local row = curRows[hit[1][1]]
          if CommDKP:IsPlaceholderMeta("spec", row.spec) and not CommDKP:IsPlaceholderMeta("spec", src.spec) then row.spec = src.spec; harvested = true end
          if CommDKP:IsPlaceholderMeta("role", row.role) and not CommDKP:IsPlaceholderMeta("role", src.role) then row.role = src.role; harvested = true end
          if CommDKP:IsPlaceholderMeta("version", row.version) and not CommDKP:IsPlaceholderMeta("version", src.version) then row.version = src.version; harvested = true end
          if type(curProfs[src.player]) ~= "table" then curProfs[src.player] = CommDKP:GetDefaultEntity() end
          curProfs[src.player].player = src.player
          curProfs[src.player].spec = row.spec
          curProfs[src.player].role = row.role
          curProfs[src.player].version = row.version
        end
      end
    end
    if harvested then CommDKP:FilterDKPTable(core.currentSort, "reset") end
  end

  table.sort(commObject.Data.Loot, function(a, b)
    return a["date"] > b["date"]
  end)

  table.sort(commObject.Data.DKP, function(a, b)
    return a["date"] > b["date"]
  end)

  if commObject.Data.MinBids ~= nil then
    table.sort(commObject.Data.MinBids, function(a, b)
      --Ensure that if there is a data issue, we detect and move on during syncs.
      local aItem = a["item"] or GetNameFromLink(a["link"]);
      local bItem = b["item"] or GetNameFromLink(b["link"]);

      return aItem < bItem
    end)
  end

  -- AD-36.2.3 (BR-28.5, CM-11): an EMPTY incoming DKP / Loot array is "not newer" (it has no [1]); only non-empty ones
  -- are compared. The local "both non-empty" requirement is unchanged.
  local inDKP, inLoot = commObject.Data.DKP, commObject.Data.Loot
  local myDKP = CommDKP:GetTable(CommDKP_DKPHistory, true, commObject.CurrentTeam)
  local myLoot = CommDKP:GetTable(CommDKP_Loot, true, commObject.CurrentTeam)
  if (#myDKP > 0 and #myLoot > 0) and (
      (#inDKP > 0 and inDKP[1].date < myDKP[1].date) or
      (#inLoot > 0 and inLoot[1].date < myLoot[1].date)
    ) then

    local entry1 = (#inLoot > 0) and ("Loot: "..inLoot[1].loot.." |cff616ccf"..L["WONBY"].." "..inLoot[1].player.." ("..date("%b %d @ %H:%M:%S", inLoot[1].date)..") by "..(CommDKP:StripRealm(inLoot[1].index) or "?").."|r") or ""  -- AD-9.6
    local entry2 = (#inDKP > 0) and ("DKP: |cff616ccf"..inDKP[1].reason.." ("..date("%b %d @ %H:%M:%S", inDKP[1].date)..") - "..(CommDKP:StripRealm(inDKP[1].index) or "?").."|r") or ""

    StaticPopupDialogs["FULL_TABS_ALERT"] = {
      text = "|CFFFF0000"..L["WARNING"].."|r: "..string.format(L["NEWERTABS1"], CommDKP:NormalizeName(sender) or "?").."\n\n"..entry1.."\n\n"..entry2.."\n\n"..L["NEWERTABS2"],
      button1 = L["YES"],
      button2 = L["NO"],
      OnAccept = function()
        local follow = tostring(commObject.CurrentTeam) == tostring(CommDKP:GetCurrentTeamIndex())               -- AD-36.5.5 (a)
          or #CommDKP:GetTable(CommDKP_DKPTable, true, CommDKP:GetCurrentTeamIndex()) == 0                          -- (b), before replacement
        local metaIndex = CommDKP:BuildKnownMetaIndex()   -- AD-26.4.3: pre-overwrite snapshot
        if type(commObject.Data.DKPTable) == "table" then
          for i = 1, #commObject.Data.DKPTable do
            local r = commObject.Data.DKPTable[i]
            if type(r) == "table" and type(r.player) == "string" and not CommDKP:IsSelf(r.player) then
              CommDKP:CachePlayerMeta(r.player, { spec = r.spec, roleData = not CommDKP:IsPlaceholderMeta("role", r.role) and r.spec or nil, version = r.version, class = r.class }, true)   -- AD-34.6: relayed = fill-only
            end
          end
        end
        CommDKP:SetTable(CommDKP_DKPTable, true, commObject.Data.DKPTable, commObject.CurrentTeam);
        CommDKP:RestoreKnownPlayerMeta(commObject.CurrentTeam, metaIndex)
        for i = 1, #commObject.Data.DKPTable do
          local r = commObject.Data.DKPTable[i]
          if type(r) == "table" and type(r.player) == "string" and r.player ~= "" then
            CommDKP:GetTable(CommDKP_Profiles, true, commObject.CurrentTeam)[r.player] = r
          end
        end
        CommDKP:SetTable(CommDKP_DKPHistory, true, commObject.Data.DKP, commObject.CurrentTeam);
        CommDKP:SetTable(CommDKP_Loot, true, commObject.Data.Loot, commObject.CurrentTeam);
        CommDKP:GetTable(CommDKP_DKPHistory, true, commObject.CurrentTeam).seed = 0   -- AD-36.3.2 (BR-28.9b): same as the no-popup branch;
        CommDKP:GetTable(CommDKP_Loot, true, commObject.CurrentTeam).seed = 0         -- also drops an older client's serialized .seed
        CommDKP:SetTable(CommDKP_Archive, true, commObject.Data.Archive, commObject.CurrentTeam);

        local minBidTable = CommDKP:FormatPriceTable(commObject.Data.MinBids, true);
        local newMinBidTable = {}
        for i=1, #minBidTable do
          local id = minBidTable[i].itemID;
          if id == nil and minBidTable[i].link ~= nil then
            id = minBidTable[i].link:match("|Hitem:(%d+):")
          end
          if id ~= nil then
            newMinBidTable[id] = minBidTable[i];
          end
        end

        CommDKP:SetTable(CommDKP_MinBids, true, newMinBidTable, commObject.CurrentTeam);
        core.DB["teams"] = commObject.Teams;

        if follow then CommDKP:SetCurrentTeam(commObject.CurrentTeam) end   -- AD-36.5.5 (BR-28.16): team-scoped
        
        CommDKP:FilterDKPTable(core.currentSort, "reset")
        CommDKP:StatusVerify_Update()
      end,
      timeout = 0,
      whileDead = true,
      hideOnEscape = true,
      preferredIndex = 3,
    }
    StaticPopup_Show ("FULL_TABS_ALERT")
  else
    local follow = tostring(commObject.CurrentTeam) == tostring(CommDKP:GetCurrentTeamIndex())               -- AD-36.5.5 (a)
      or #CommDKP:GetTable(CommDKP_DKPTable, true, CommDKP:GetCurrentTeamIndex()) == 0                          -- (b), before replacement
    local metaIndex = CommDKP:BuildKnownMetaIndex()   -- AD-26.4.3: pre-overwrite snapshot
    if type(commObject.Data.DKPTable) == "table" then
      for i = 1, #commObject.Data.DKPTable do
        local r = commObject.Data.DKPTable[i]
        if type(r) == "table" and type(r.player) == "string" and not CommDKP:IsSelf(r.player) then
          CommDKP:CachePlayerMeta(r.player, { spec = r.spec, roleData = not CommDKP:IsPlaceholderMeta("role", r.role) and r.spec or nil, version = r.version, class = r.class }, true)   -- AD-34.6: relayed = fill-only
        end
      end
    end
    CommDKP:SetTable(CommDKP_DKPTable, true, commObject.Data.DKPTable, commObject.CurrentTeam);
    CommDKP:RestoreKnownPlayerMeta(commObject.CurrentTeam, metaIndex)
    for i = 1, #commObject.Data.DKPTable do
      local r = commObject.Data.DKPTable[i]
      if type(r) == "table" and type(r.player) == "string" and r.player ~= "" then
        CommDKP:GetTable(CommDKP_Profiles, true, commObject.CurrentTeam)[r.player] = r
      end
    end
    CommDKP:SetTable(CommDKP_DKPHistory, true, commObject.Data.DKP, commObject.CurrentTeam);
    CommDKP:SetTable(CommDKP_Loot, true, commObject.Data.Loot, commObject.CurrentTeam);
    -- reset seeds since this is a fullbroadcast (AD-36.5.5: moved up, matching AD-36.3.2, so seed is 0 before any StatusVerify_Update)
    CommDKP:GetTable(CommDKP_DKPHistory, true, commObject.CurrentTeam).seed = 0 
    CommDKP:GetTable(CommDKP_Loot, true, commObject.CurrentTeam).seed = 0
    CommDKP:SetTable(CommDKP_Archive, true, commObject.Data.Archive, commObject.CurrentTeam);

    local minBidTable = CommDKP:FormatPriceTable(commObject.Data.MinBids, true);
    local newMinBidTable = {}
    for i=1, #minBidTable do
      local id = minBidTable[i].itemID;
      if id == nil and minBidTable[i].link ~= nil then
        id = minBidTable[i].link:match("|Hitem:(%d+):")
      end
      if id ~= nil then
        newMinBidTable[id] = minBidTable[i];
      end
    end

    CommDKP:SetTable(CommDKP_MinBids, true, newMinBidTable, commObject.CurrentTeam);

    core.DB["teams"] = commObject.Teams;
    if follow then CommDKP:SetCurrentTeam(commObject.CurrentTeam) end   -- AD-36.5.5 (BR-28.16): team-scoped
    CommDKP:FilterDKPTable(core.currentSort, "reset");
    CommDKP:StatusVerify_Update();
  end
  
  print("[CommunityDKP] COMMS: Full broadcast receive finished for team "..CommDKP:GetTeamName(commObject.CurrentTeam));
  -- AD-30.1.3(b) (F-7): outside the popup branch, so it also runs when the user declines.
  CommDKP:QueueTalentSend("broadcast")
  CommDKP:CommTrace("RECV CommDKPAllTabs from=%s: officer copy of my meta=%s -> re-send queued", tostring(sender), selfState)
end


----------
-- 2-WEEK MERGE HANDLERS
----------

function CommDKP:MergeSend(prefix, commObject, channel)
  local _channel = channel or "GUILD";
  local _prefix = prefix or "CommDKPMerge";

  if channel then -- check if we are targeting specific player
    print("[CommunityDKP] COMMS: You started 2-week broadcast for team "..CommDKP:GetTeamName(CommDKP:GetCurrentTeamIndex()).." to player "..channel);
    local wPacket = CommDKP.Sync:ToPrintSafePacket(commObject)   -- AD-34.2 (G-26.2)
    CommDKP.Sync:SendCommMessage(prefix, wPacket, "WHISPER", channel, "NORMAL", CommDKP_BroadcastFull_Callback, channel);
  else
    CommDKP.Sync:SendData("CommDKPPreBroad", prefix, nil);
    CommDKP.Sync:SendCommMessage(prefix, commObject, _channel, nil, "NORMAL", CommDKP_BroadcastFull_Callback, _channel);
  end
end


function CommDKP:MergeReceived(commObject, channel, who)
  if type(who) == "string" and who ~= "" and not CommDKP:IsSelf(who) then
    core.LastOfficerSender = who
  end
  -- AD-30.1.3(c): what this merge says about MY row (no sender is passed to this handler).
  local selfState = CommDKP:IncomingSelfMetaState(commObject.Data and commObject.Data.Profiles)
  core.LastBroadcastSelfMeta = { state = selfState, kind = "merge", from = nil, t = GetTime() }
  for i=1, #commObject.Data.DKP do
    local search = CommDKP:Table_Search(CommDKP:GetTable(CommDKP_DKPHistory, true, commObject.CurrentTeam), commObject.Data.DKP[i].index, "index")

    if not search and ((CommDKP:GetTable(CommDKP_Archive, true, commObject.CurrentTeam).DKPMeta and CommDKP:GetTable(CommDKP_Archive, true, commObject.CurrentTeam).DKPMeta < commObject.Data.DKP[i].date) or (not CommDKP:GetTable(CommDKP_Archive, true, commObject.CurrentTeam).DKPMeta)) then   -- prevents adding entry if this entry has already been archived
      local players = {strsplit(",", strsub(commObject.Data.DKP[i].players, 1, -2))}
      local dkp

      if strfind(commObject.Data.DKP[i].dkp, "%-%d*%.?%d+%%") then
        dkp = {strsplit(",", commObject.Data.DKP[i].dkp)}
      end

      if commObject.Data.DKP[i].deletes then      -- adds deletedby field to entry if the received table is a delete entry
        local search_del = CommDKP:Table_Search(CommDKP:GetTable(CommDKP_DKPHistory, true, commObject.CurrentTeam), commObject.Data.DKP[i].deletes, "index")

        if search_del then
          CommDKP:GetTable(CommDKP_DKPHistory, true, commObject.CurrentTeam)[search_del[1][1]].deletedby = commObject.Data.DKP[i].index
        end
      end
      
      if not commObject.Data.DKP[i].deletedby then
        local search_del = CommDKP:Table_Search(CommDKP:GetTable(CommDKP_DKPHistory, true, commObject.CurrentTeam), commObject.Data.DKP[i].index, "deletes")

        if search_del then
          commObject.Data.DKP[i].deletedby = CommDKP:GetTable(CommDKP_DKPHistory, true, commObject.CurrentTeam)[search_del[1][1]].index
        end
      end

      table.insert(CommDKP:GetTable(CommDKP_DKPHistory, true, commObject.CurrentTeam), commObject.Data.DKP[i])

      for j=1, #players do
        if players[j] then
          local findEntry = CommDKP:Table_Search(CommDKP:GetTable(CommDKP_DKPTable, true, commObject.CurrentTeam), players[j], "player")

          if strfind(commObject.Data.DKP[i].dkp, "%-%d*%.?%d+%%") then     -- handles decay entries
            if findEntry then
              CommDKP:GetTable(CommDKP_DKPTable, true, commObject.CurrentTeam)[findEntry[1][1]].dkp = CommDKP:GetTable(CommDKP_DKPTable, true, commObject.CurrentTeam)[findEntry[1][1]].dkp + tonumber(dkp[j])
            else
              if not CommDKP:GetTable(CommDKP_Archive, true, commObject.CurrentTeam)[players[j]] or (CommDKP:GetTable(CommDKP_Archive, true, commObject.CurrentTeam)[players[j]] and CommDKP:GetTable(CommDKP_Archive, true, commObject.CurrentTeam)[players[j]].deleted ~= true) then
                CommDKP_Profile_Create(players[j], tonumber(dkp[j]), nil, nil, commObject.CurrentTeam)
              end
            end
          else
            if findEntry then
              CommDKP:GetTable(CommDKP_DKPTable, true, commObject.CurrentTeam)[findEntry[1][1]].dkp = CommDKP:GetTable(CommDKP_DKPTable, true, commObject.CurrentTeam)[findEntry[1][1]].dkp + tonumber(commObject.Data.DKP[i].dkp)
              if (tonumber(commObject.Data.DKP[i].dkp) > 0 and not commObject.Data.DKP[i].deletes) or (tonumber(commObject.Data.DKP[i].dkp) < 0 and commObject.Data.DKP[i].deletes) then -- adjust lifetime if it's a DKP gain or deleting a DKP gain 
                CommDKP:GetTable(CommDKP_DKPTable, true, commObject.CurrentTeam)[findEntry[1][1]].lifetime_gained = CommDKP:GetTable(CommDKP_DKPTable, true, commObject.CurrentTeam)[findEntry[1][1]].lifetime_gained + commObject.Data.DKP[i].dkp   -- NOT if it's a DKP penalty or deleteing a DKP penalty
              end
            else
              if not CommDKP:GetTable(CommDKP_Archive, true, commObject.CurrentTeam)[players[j]] or (CommDKP:GetTable(CommDKP_Archive, true, commObject.CurrentTeam)[players[j]] and CommDKP:GetTable(CommDKP_Archive, true, commObject.CurrentTeam)[players[j]].deleted ~= true) then
                local class

                if (tonumber(commObject.Data.DKP[i].dkp) > 0 and not commObject.Data.DKP[i].deletes) or (tonumber(commObject.Data.DKP[i].dkp) < 0 and commObject.Data.DKP[i].deletes) then
                  CommDKP_Profile_Create(players[j], tonumber(commObject.Data.DKP[i].dkp), tonumber(commObject.Data.DKP[i].dkp), nil, commObject.CurrentTeam)
                else
                  CommDKP_Profile_Create(players[j], tonumber(commObject.Data.DKP[i].dkp), nil, nil, commObject.CurrentTeam)
                end
              end
            end
          end
        end
      end
    end
  end

  if CommDKP.ConfigTab6 and CommDKP.ConfigTab6.history and CommDKP.ConfigTab6:IsShown() then
    CommDKP:DKPHistory_Update(true)
  end

  for i=1, #commObject.Data.Loot do
    local search = CommDKP:Table_Search(CommDKP:GetTable(CommDKP_Loot, true, commObject.CurrentTeam), commObject.Data.Loot[i].index, "index")

    if not search and ((CommDKP:GetTable(CommDKP_Archive, true, commObject.CurrentTeam).LootMeta and CommDKP:GetTable(CommDKP_Archive, true, commObject.CurrentTeam).LootMeta < commObject.Data.Loot[i].date) or (not CommDKP:GetTable(CommDKP_Archive, true, commObject.CurrentTeam).LootMeta)) then -- prevents adding entry if this entry has already been archived
      if commObject.Data.Loot[i].deletes then
        local search_del = CommDKP:Table_Search(CommDKP:GetTable(CommDKP_Loot, true, commObject.CurrentTeam), commObject.Data.Loot[i].deletes, "index")

        if search_del and not CommDKP:GetTable(CommDKP_Loot, true, commObject.CurrentTeam)[search_del[1][1]].deletedby then
          CommDKP:GetTable(CommDKP_Loot, true, commObject.CurrentTeam)[search_del[1][1]].deletedby = commObject.Data.Loot[i].index
        end
      end

      if not commObject.Data.Loot[i].deletedby then
        local search_del = CommDKP:Table_Search(CommDKP:GetTable(CommDKP_Loot, true, commObject.CurrentTeam), commObject.Data.Loot[i].index, "deletes")

        if search_del then
          commObject.Data.Loot[i].deletedby = CommDKP:GetTable(CommDKP_Loot, true, commObject.CurrentTeam)[search_del[1][1]].index
        end
      end

      table.insert(CommDKP:GetTable(CommDKP_Loot, true, commObject.CurrentTeam), commObject.Data.Loot[i])

      local findEntry = CommDKP:Table_Search(CommDKP:GetTable(CommDKP_DKPTable, true, commObject.CurrentTeam), commObject.Data.Loot[i].player, "player")

      if findEntry then
        CommDKP:GetTable(CommDKP_DKPTable, true, commObject.CurrentTeam)[findEntry[1][1]].dkp = CommDKP:GetTable(CommDKP_DKPTable, true, commObject.CurrentTeam)[findEntry[1][1]].dkp + commObject.Data.Loot[i].cost
        CommDKP:GetTable(CommDKP_DKPTable, true, commObject.CurrentTeam)[findEntry[1][1]].lifetime_spent = CommDKP:GetTable(CommDKP_DKPTable, true, commObject.CurrentTeam)[findEntry[1][1]].lifetime_spent + commObject.Data.Loot[i].cost
      else
        if not CommDKP:GetTable(CommDKP_Archive, true, commObject.CurrentTeam)[commObject.Data.Loot[i].player] or (CommDKP:GetTable(CommDKP_Archive, true, commObject.CurrentTeam)[commObject.Data.Loot[i].player] and CommDKP:GetTable(CommDKP_Archive, true, commObject.CurrentTeam)[commObject.Data.Loot[i].player].deleted ~= true) then
          CommDKP_Profile_Create(commObject.Data.Loot[i].player, commObject.Data.Loot[i].cost, 0, commObject.Data.Loot[i].cost, commObject.CurrentTeam)
        end
      end
    end
  end

  local metaIndex = CommDKP:BuildKnownMetaIndex()   -- AD-26.4.3: snapshot before rows are created
  for i=1, #commObject.Data.Profiles do

    local search = CommDKP:Table_Search(CommDKP:GetTable(CommDKP_DKPTable, true, commObject.CurrentTeam), commObject.Data.Profiles[i].player, "player")

    if search then
      if CommDKP:GetTable(CommDKP_DKPTable, true, commObject.CurrentTeam)[search[1][1]].class == "NONE" then
        CommDKP:GetTable(CommDKP_DKPTable, true, commObject.CurrentTeam)[search[1][1]].class = commObject.Data.Profiles[i].class
      end
      local row, src = CommDKP:GetTable(CommDKP_DKPTable, true, commObject.CurrentTeam)[search[1][1]], commObject.Data.Profiles[i]
      if not CommDKP:IsSelf(row.player) then                                   -- AD-30.1.3(c): placeholder-only fill
        if CommDKP:IsPlaceholderMeta("spec", row.spec) and not CommDKP:IsPlaceholderMeta("spec", src.spec) then row.spec = src.spec end
        if CommDKP:IsPlaceholderMeta("role", row.role) and not CommDKP:IsPlaceholderMeta("role", src.role) then row.role = src.role end
        if CommDKP:IsPlaceholderMeta("version", row.version) and not CommDKP:IsPlaceholderMeta("version", src.version) then row.version = src.version end
        CommDKP:CachePlayerMeta(row.player, { spec = row.spec, roleData = not CommDKP:IsPlaceholderMeta("role", row.role) and row.spec or nil, version = row.version, class = row.class }, true)   -- AD-34.6: relayed = fill-only
        local profs = CommDKP:GetTable(CommDKP_Profiles, true, commObject.CurrentTeam)
        if type(profs[row.player]) ~= "table" then profs[row.player] = CommDKP:GetDefaultEntity() end
        profs[row.player].player = row.player
        profs[row.player].spec = row.spec
        profs[row.player].role = row.role
        profs[row.player].version = row.version
      end
    else
      local p = commObject.Data.Profiles[i]
      if type(p) == "table" and type(p.player) == "string" and not CommDKP:IsSelf(p.player) then
        CommDKP:CachePlayerMeta(p.player, { spec = p.spec, roleData = not CommDKP:IsPlaceholderMeta("role", p.role) and p.spec or nil, version = p.version, class = p.class }, true)   -- AD-34.6: relayed = fill-only
      end
      CommDKP:HydratePlayerRow(p, metaIndex)   -- AD-26.4.3
      tinsert(CommDKP:GetTable(CommDKP_DKPTable, true, commObject.CurrentTeam), p)
      if type(p) == "table" and type(p.player) == "string" and p.player ~= "" then
        CommDKP:GetTable(CommDKP_Profiles, true, commObject.CurrentTeam)[p.player] = p
      end
    end
  end

  -- AD-36.2.4 (BR-28.6, CM-12): newest first for the MERGED team, UI open or not, current team or not. table.sort only
  -- touches the array part, so .seed survives. nil / non-numeric dates sort last; ties keep any order (G-28.6).
  local function newestFirst(a, b) return (tonumber(a and a.date) or -1) > (tonumber(b and b.date) or -1) end
  table.sort(CommDKP:GetTable(CommDKP_DKPHistory, true, commObject.CurrentTeam), newestFirst)
  table.sort(CommDKP:GetTable(CommDKP_Loot, true, commObject.CurrentTeam), newestFirst)
  -- AD-36.3.3 (BR-28.10, CM-04): an ORPHANED seed is cleared after a merge (G4 already validated the sender; guild or
  -- WHISPER). Orphaned = non-zero AND still not found AND (malformed per R-SEED, OR not newer than the newest entry this
  -- sender merged for that table). A seed newer than everything merged is kept (another officer may own it).
  for _, pair in ipairs({ { CommDKP_DKPHistory, commObject.Data.DKP }, { CommDKP_Loot, commObject.Data.Loot } }) do
    local tbl = CommDKP:GetTable(pair[1], true, commObject.CurrentTeam)
    local seed = tbl.seed
    if seed ~= nil and seed ~= 0 and not (type(seed) == "string" and CommDKP:Table_Search(tbl, seed, "index")) then
      local seedDate
      if type(seed) == "string" then local _, d = strsplit("-", seed); seedDate = tonumber(d) end   -- R-SEED (D-36.4)
      local newest
      for i = 1, #pair[2] do
        local d = type(pair[2][i]) == "table" and tonumber(pair[2][i].date) or nil
        if d and (not newest or d > newest) then newest = d end
      end
      if seedDate == nil or (newest ~= nil and seedDate <= newest) then tbl.seed = 0 end   -- G-28.5: no payload date -> (i) only
    end
  end
  CommDKP:LootHistory_Reset()
  CommDKP:LootHistory_Update(L["NOFILTER"])
  CommDKP:FilterDKPTable(core.currentSort, "reset")
  CommDKP:StatusVerify_Update()
  CommDKP:QueueTalentSend("broadcast")   -- AD-26.4.3 / AD-26.5.1 (b)
  CommDKP:CommTrace("RECV CommDKPMerge from=?: officer copy of my meta=%s -> re-send queued", selfState)   -- AD-30.1.3(c)
  return
end


----------
-- CommDKPQuery message HANDLERS
----------

function CommDKP:QuerySend(prefix, commObject, channel)
  local _channel = channel or "GUILD";
  local _prefix = prefix or "CommDKPQuery";
  CommDKP.Sync:SendCommMessage(_prefix, commObject, _channel);
end

----------
-- CommDKPBuild message HANDLERS
----------

function CommDKP:BuildSend(prefix, commObject, channel)
  local _channel = channel or "GUILD";
  local _prefix = prefix or "CommDKPQuery";
  CommDKP.Sync:SendCommMessage(_prefix, commObject, _channel);
  return;
end

function CommDKP:BuildReceived(commObject, sender)
  if not CommDKP:IsSelf(sender) then
    local remoteBuild = tonumber(commObject and commObject.Data); if not remoteBuild then return end   -- AD-15.5(c)
    local LastVerCheck = time() - core.LastVerCheck;

        if LastVerCheck > 900 then             -- limits the Out of Date message from firing more than every 15 minutes
          if remoteBuild > core.BuildNumber then
            core.LastVerCheck = time();
            CommDKP:Print(L["OUTOFDATEANNOUNCE"])
          end
        end

        if remoteBuild < core.BuildNumber then   -- returns build number if receiving party has a newer version
          CommDKP.Sync:SendData("CommDKPBuild", tostring(core.BuildNumber))
        end
        return;
  end
end

----------
-- CommDKPTalents message HANDLERS
----------

function CommDKP:TalentsSend(prefix, commObject, channel, cb, cbArg)   -- AD-30.1.4: optional AceComm callback
  local _channel = channel or "GUILD";
  local _prefix = prefix or "CommDKPTalents";
  CommDKP.Sync:SendCommMessage(_prefix, commObject, _channel, nil, "NORMAL", cb, cbArg);
end


function CommDKP:TalentsReceived(commObject, sender, distribution)   -- AD-26.4.1 + AD-30.1.7
  if type(commObject) ~= "table" then return end
  local name = CommDKP:ResolveSenderName(sender)                       -- AD-26.2.7 (F4); superset of AD-15.2
  local _, n = CommDKP:ApplyReportedPlayerMeta(name, { spec = commObject.Data }, commObject.Teams)
  CommDKP:RecordMetaRecv("CommDKPTalents", sender, name, n, distribution)
end

----------
-- CommDKPRoles message HANDLERS
----------

function CommDKP:RolesSend(prefix, commObject, channel, cb, cbArg)   -- AD-30.1.4: optional AceComm callback
  local _channel = channel or "GUILD";
  local _prefix = prefix or "CommDKPRoles";
  CommDKP.Sync:SendCommMessage(_prefix, commObject, _channel, nil, "NORMAL", cb, cbArg);
end

-- AD-19.2 (012g): ONE class + spec -> role rule (BR-12.14.4). Used by RolesReceived and SendTalentsAndRole.
function CommDKP:ResolveRoleForClassAndSpec(classToken, specText)
  local data = type(specText) == "string" and specText or ""
  if classToken == "WARRIOR" then
    local _, _, c = strsplit("/", data)
    local legacyC = tonumber(c) and tonumber(strsub(c, 1, -2))      -- legacy expression, now nil-safe (R7)
    local tally3 = tonumber(strmatch(data, "/(%d+)%)%s*$") or "")   -- "(t1/t2/t3)" third tally (R7, PM-12.10)
    if strfind(data, "Protection") or (legacyC and legacyC > 15) or (tally3 and tally3 > 15) then return L["TANK"] end
    return L["MELEEDPS"]
  elseif classToken == "PALADIN" then
    if strfind(data, "Protection") then return L["TANK"] elseif strfind(data, "Holy") then return L["HEALER"] end
    return L["MELEEDPS"]
  elseif classToken == "HUNTER" then return L["RANGEDPS"]
  elseif classToken == "ROGUE" then return L["MELEEDPS"]
  elseif classToken == "PRIEST" then return strfind(data, "Shadow") and L["CASTERDPS"] or L["HEALER"]
  elseif classToken == "SHAMAN" then
    if strfind(data, "Restoration") then return L["HEALER"] elseif strfind(data, "Elemental") then return L["CASTERDPS"] end
    return L["MELEEDPS"]
  elseif classToken == "MAGE" or classToken == "WARLOCK" then return L["CASTERDPS"]
  elseif classToken == "DRUID" then
    if strfind(data, "Feral") then return L["TANK"] elseif strfind(data, "Balance") then return L["CASTERDPS"] end
    return L["HEALER"]
  end
  return L["NOROLEDETECTED"]
end

function CommDKP:RolesReceived(commObject, sender, distribution)   -- AD-26.4.1 + AD-30.1.7
  if type(commObject) ~= "table" then return end
  local name = CommDKP:ResolveSenderName(sender)
  local _, n = CommDKP:ApplyReportedPlayerMeta(name, { roleData = commObject.Data }, commObject.Teams)
  CommDKP:RecordMetaRecv("CommDKPRoles", sender, name, n, distribution)
end

----------
-- CDKProfileSend message HANDLERS
----------

function CommDKP:ProfileSend(prefix, commObject, channel, cb, cbArg)   -- AD-30.1.4: optional AceComm callback
  local _channel = channel or "GUILD";
  local _prefix = prefix or "CDKProfileSend";
  CommDKP.Sync:SendCommMessage(_prefix, commObject, _channel, nil, "NORMAL", cb, cbArg);
end


function CommDKP:ProfileReceived(commObject, sender, distribution)   -- AD-26.4.1 + AD-30.1.7
  local profile = type(commObject) == "table" and commObject.Data
  if type(profile) ~= "table" then return end
  local name = CommDKP:ResolveSenderName(sender, profile.player)       -- learns the alias (F4); anti-spoof
  if not name or name == "" then
    CommDKP:RecordMetaRecv("CDKProfileSend", sender, nil, 0, distribution)
    return
  end
  local _, n = CommDKP:ApplyReportedPlayerMeta(name, { version = profile.version, class = profile.class }, commObject.Teams)
  CommDKP:RecordMetaRecv("CDKProfileSend", sender, name, n, distribution)
end

function CommDKP:OnMetaSendResult(ctx, sent, total, didSend, result)   -- AD-30.1.4 (BR-22.2, F-1)
  xpcall(function()
    if type(ctx) ~= "table" or ctx.done then return end
    if didSend == false then                                            -- final non-success (CTL already retried throttle/lockdown)
      ctx.done = true
      local name = CommDKP:SendResultName(result)
      CommDKP:RecordMetaSend(ctx.prefix, ctx.channel, name)
      if ctx.channel == "GUILD" and not ctx.fallback then
        local gch = CommDKP:GetGroupCommChannel(false)
        if gch then
          local c2 = { prefix = ctx.prefix, channel = gch, text = ctx.text, fallback = true }
          CommDKP.Sync:SendCommMessage(ctx.prefix, ctx.text, gch, nil, "NORMAL",
            function(c, s, t, d, r) CommDKP:OnMetaSendResult(c, s, t, d, r) end, c2)
        elseif type(core.LastOfficerSender) == "string" and core.LastOfficerSender ~= "" and not CommDKP:IsSelf(core.LastOfficerSender) then
          local wText = CommDKP.Sync:ToPrintSafePacket(ctx.text)   -- AD-34.2 (G-26.2)
          local c2 = { prefix = ctx.prefix, channel = "WHISPER", target = core.LastOfficerSender, text = wText, fallback = true }
          CommDKP.Sync:SendCommMessage(ctx.prefix, wText, "WHISPER", core.LastOfficerSender, "NORMAL",
            function(c, s, t, d, r) CommDKP:OnMetaSendResult(c, s, t, d, r) end, c2)
        end
        if not core.MetaGuildWarned then
          core.MetaGuildWarned = true
          CommDKP:PrintAlways(string.format(L["METAGUILDWARN"], name))
        end
      end
      return
    end
    if didSend == nil and (total or 0) == 0 then                        -- CommGate collapsed it (DropDeferred: cbArg, 0, 0)
      ctx.done = true
      CommDKP:RecordMetaSend(ctx.prefix, ctx.channel, "Superseded")
      return
    end
    if type(sent) == "number" and type(total) == "number" and sent >= total then   -- last chunk
      ctx.done = true
      CommDKP:RecordMetaSend(ctx.prefix, ctx.channel, didSend == true and CommDKP:SendResultName(result) or "Unknown")
    end
  end, geterrorhandler)
end

----------
-- CommDKPBidder message HANDLERS
----------

-- AD-14.1: the addon channel that actually reaches the current group.
-- guildFallback: true -> fall back to "GUILD" when solo; false/nil -> return nil (don't send).
function CommDKP:GetGroupCommChannel(guildFallback)
  if IsInRaid() then return "RAID" end
  if IsInGroup() then return "PARTY" end
  if guildFallback and IsInGuild() then return "GUILD" end
  return nil
end

-- Resolves a caller-supplied channel: nil/"RAID" are group-relative, anything else is honored verbatim.
local function ResolveGroupChannel(channel, guildFallback)
  if channel == nil or channel == "RAID" then return CommDKP:GetGroupCommChannel(guildFallback) end
  return channel
end

local function GuildChannelOpen()
  return (core.DB and core.DB.modes and core.DB.modes.channels and core.DB.modes.channels.guild) and true or false
end

function CommDKP:BidderSend(prefix, commObject, channel)
  local _channel = ResolveGroupChannel(channel, true);
  if not _channel then return end
  local _prefix = prefix or "CommDKPBidder";
  CommDKP.Sync:SendCommMessage(_prefix, commObject, _channel);
end


-- AD-14.2: single bid-processing path for both network and local loopback.
local function ProcessBidderData(data, sender)
  if not (core.BidInProgress and core.IsOfficer) then return end
  if data == nil or data == "pass" then return end  -- TODO: surface passes to the auctioneer at some point.
  CommDKP_CHAT_MSG_WHISPER(data, sender);
end

function CommDKP:BidderReceived(commObject, sender, distribution)
  if CommDKP:IsSelf(sender) then return end        -- our own echo; already handled by loopback
  if not (core.BidInProgress and core.IsOfficer) then return end
  sender = CommDKP:ResolveRosterName(sender) or CommDKP:NormalizeName(sender) or sender   -- AD-15.2 rule
  -- AD-15.1: RAID/PARTY delivery is server-restricted to group members; only GUILD/WHISPER needs a roster check.
  local groupDist = distribution == "RAID" or distribution == "PARTY" or distribution == "INSTANCE_CHAT"
  if not groupDist and not GuildChannelOpen() and (IsInRaid() or IsInGroup()) then
    if not CommDKP:IsPlayerInGroup(sender) then return end
  end
  ProcessBidderData(commObject and commObject.Data, sender)
end

function CommDKP:BidderLocal(data)                    -- AD-14.2
  ProcessBidderData(data, CommDKP:GetPlayerName())  -- no raw unit-name fallback (NAME-002)
end

----------
-- CommDKPCommand message HANDLERS
----------

function CommDKP:CommandSend(prefix, commObject, channel)
  local _channel = ResolveGroupChannel(channel, GuildChannelOpen());  -- AD-14.1
  if not _channel then return end
  local _prefix = prefix or "CommDKPCommand";
  CommDKP.Sync:SendCommMessage(_prefix, commObject, _channel);
end


function CommDKP:CommandReceived(commObject, sender)
  local command, arg1, arg2, arg3, arg4 = strsplit("#", commObject.Data);
  if not CommDKP:IsSelf(sender) then
    if command == "StartTimer" then
      CommDKP:StartTimer(arg1, arg2)
    elseif command == "StartBidTimer" then
      CommDKP:StartBidTimer(arg1, arg2, arg3)
      core.BiddingInProgress = true;
      if strfind(arg1, "{") then
        CommDKP:Print("Bid timer extended by "..tonumber(strsub(arg1, strfind(arg1, "{")+1)).." seconds.")
      end
    elseif command == "StopBidTimer" then
      if CommDKP.BidTimer then
        CommDKP.BidTimer:SetScript("OnUpdate", nil)
        CommDKP.BidTimer:Hide()
        core.BiddingInProgress = false;
      end
      if core.BidInterface and #core.BidInterface.LootTableButtons > 0 then
        for i=1, #core.BidInterface.LootTableButtons do
          CommDKP:HideButtonGlow(core.BidInterface.LootTableButtons[i])
        end
      end
      C_Timer.After(2, function()
        if core.BidInterface and core.BidInterface:IsShown() and not core.BiddingInProgress then
          core.BidInterface:Hide()
        end
      end)
    elseif command == "BidInfo" then
      if not core.BidInterface then
        core.BidInterface = core.BidInterface or CommDKP:BidInterface_Create()  -- initiates bid window if it hasn't been created
      end
      if core.DB.defaults.AutoOpenBid and not core.BidInterface:IsShown() then  -- toggles bid window if option is set to
        CommDKP:BidInterface_Toggle()
      end

      CommDKP:CurrItem_Set(arg1, arg2, arg3, arg4)  -- populates bid window
    end
  end
end


----------
-- CommDKPRaidTime message HANDLERS
----------

function CommDKP:RaidTimeSend(prefix, commObject, channel)
  local _channel = ResolveGroupChannel(channel, false);  -- AD-14.1
  if not _channel then return end
  local _prefix = prefix or "CommDKPRaidTime";
  CommDKP.Sync:SendCommMessage(_prefix, commObject, _channel);
end


function CommDKP:RaidTimeReceived(commObject, sender)
  if CommDKP:IsSelf(sender) or type(commObject) ~= "table" or type(commObject.Data) ~= "string" then return end
  local command, args = strsplit(",", commObject.Data);
  local isSync = type(command) == "string" and strfind(command, "sync", 1) ~= nil
  -- AD-36.5.4 (BR-28.15): "start" (also resume) always moves the receiver to the raid's team, officers and raiders alike
  -- (ruling 1); "sync" only when it differs (ruling 2 / CM-22: no per-minute redraw or meta burst); nothing else switches.
  local function follow(always)
    if always or tostring(commObject.CurrentTeam) ~= tostring(CommDKP:GetCurrentTeamIndex()) then
      CommDKP:SetCurrentTeam(commObject.CurrentTeam)
    end
  end

  if core.IsOfficer and CommDKP.ConfigTab2 then
    if command == "start" then
      follow(true)
      local arg1, arg2, arg3, arg4, arg5, arg6 = strsplit(" ", args, 6)

      if arg1 == "true" then arg1 = true else arg1 = false end
      if arg4 == "true" then arg4 = true else arg4 = false end
      if arg5 == "true" then arg5 = true else arg5 = false end
      if arg6 == "true" then arg6 = true else arg6 = false end

      if arg2 ~= nil then
        CommDKP.ConfigTab2.RaidTimerContainer.interval:SetNumber(tonumber(arg2));
        core.DB.modes.increment = tonumber(arg2);
      end
      if arg3 ~= nil then
        CommDKP.ConfigTab2.RaidTimerContainer.bonusvalue:SetNumber(tonumber(arg3));
        core.DB.DKPBonus.IntervalBonus = tonumber(arg3);
      end
      if arg4 ~= nil then
        CommDKP.ConfigTab2.RaidTimerContainer.StartBonus:SetChecked(arg4);
        core.DB.DKPBonus.GiveRaidStart = arg4;
      end
      if arg5 ~= nil then
        CommDKP.ConfigTab2.RaidTimerContainer.EndRaidBonus:SetChecked(arg5);
        core.DB.DKPBonus.GiveRaidEnd = arg5;
      end
      if arg6 ~= nil then
        CommDKP.ConfigTab2.RaidTimerContainer.StandbyInclude:SetChecked(arg6);
        core.DB.DKPBonus.IncStandby = arg6;
      end

      CommDKP:StartRaidTimer(arg1)
    elseif command == "stop" then
      CommDKP:StopRaidTimer()
    elseif isSync then
      local _, syncTimer, syncSecondCount, syncMinuteCount, syncAward = strsplit(" ", command, 5)
      CommDKP:StartRaidTimer(nil, syncTimer, syncSecondCount, syncMinuteCount, syncAward)
      follow(false)
      core.RaidInProgress = true
    end
  elseif command == "start" then
    follow(true)
  elseif isSync then
    follow(false)
  end
end

----------
-- CommDKPBCastMsg message HANDLERS
----------

function CommDKP:CastMsgSend(prefix, commObject, channel, player, prio)
  local _prefix = prefix or "CommDKPBCastMsg";
  local _prio = prio or "NORMAL";

  if player == nil then
    local _channel = ResolveGroupChannel(channel, true);  -- AD-36.6.2 (BR-28.19, CM-19): RAID / PARTY when grouped, else GUILD
    if not _channel then return end
    CommDKP.Sync:SendCommMessage(_prefix, commObject, _channel, nil, _prio, nil, nil);
  else
    -- AD-36.6.3 (BR-28.20, CM-20): WHISPER is print-safe (AD-34.2)
    CommDKP.Sync:SendCommMessage(_prefix, CommDKP.Sync:ToPrintSafePacket(commObject), "WHISPER", player, _prio, nil, nil);
  end;
end


----------
-- CommDKPZSumBank message HANDLERS
----------

function CommDKP:ZSumBankSend(prefix, commObject, channel)
  local _channel = ResolveGroupChannel(channel, false);  -- AD-14.1
  if not _channel then return end
  local _prefix = prefix or "CommDKPZSumBank";
  CommDKP.Sync:SendCommMessage(_prefix, commObject, _channel);
end


function CommDKP:ZSumBankReceived(commObject)
  if core.IsOfficer then
    core.DB.modes.ZeroSumBank = commObject.Data;
    if core.ZeroSumBank then
      if commObject.Data.balance == 0 then
        core.ZeroSumBank.LootFrame.LootList:SetText("")
      end
      CommDKP:ZeroSumBank_Update()
    end
  end
end

----------
-- CommDKPBossLoot message HANDLERS
----------

function CommDKP:BossLootSend(prefix, commObject, channel)
  local _channel = ResolveGroupChannel(channel, false);  -- AD-14.1
  if not _channel then return end
  local _prefix = prefix or "CommDKPBossLoot";
  CommDKP.Sync:SendCommMessage(_prefix, commObject, _channel);
end


function CommDKP:BossLootReceived(commObject)

  local lootList = {};
  core.DB.bossargs.LastKilledBoss = commObject.Data.boss;

  for i=1, #commObject.Data do
    local item = Item:CreateFromItemLink(commObject.Data[i]);
    item:ContinueOnItemLoad(function()
      local icon = item:GetItemIcon()
      table.insert(lootList, {icon=icon, link=item:GetItemLink()})
    end);
  end
  CommDKP:LootTable_Set(lootList)
end

----------
-- CommDKPBidShare message HANDLERS
----------

function CommDKP:BidShareSend(prefix, commObject, channel)
  local _channel = ResolveGroupChannel(channel, GuildChannelOpen());  -- AD-14.1
  if not _channel then return end
  local _prefix = prefix or "CommDKPBidShare";
  CommDKP.Sync:SendCommMessage(_prefix, commObject, _channel);
end

function CommDKP:BidShareReceived(commObject)
  if core.BidInterface then
    CommDKP:Bids_Set(commObject.Data)
  end
  return
end

----------
-- CommDKPPreBroad message HANDLERS
----------

function CommDKP:PreBroadSend(prefix, commObject, channel)
  local _channel = channel or "GUILD";
  local _prefix = prefix or "CommDKPPreBroad";
  CommDKP.Sync:SendCommMessage(_prefix, commObject, _channel);
end


function CommDKP:PreBroadReceived(commObject, sender)

  if CommDKP:IsSelf(sender) then   -- AD-36.6.1 (BR-28.18, CM-18)
    if commObject.Data == "CommDKPAllTabs" then
      print("[CommunityDKP] COMMS: You started Full Broadcast for team "..CommDKP:GetTeamName(commObject.CurrentTeam));
    elseif commObject.Data == "CommDKPMerge" then
      print("[CommunityDKP] COMMS: You started 2-week broadcast for team "..CommDKP:GetTeamName(commObject.CurrentTeam));
    end
  else
    if commObject.Data == "CommDKPAllTabs" then
      print("[CommunityDKP] COMMS: Full broadcast started by "..sender.." for team "..CommDKP:GetTeamName(commObject.CurrentTeam));
    elseif commObject.Data == "CommDKPMerge" then
      print("[CommunityDKP] COMMS: 2-week merge broadcast started by "..sender.." for team "..CommDKP:GetTeamName(commObject.CurrentTeam));
    end
  end
end

----------
-- CommDKPLootDist message HANDLERS
----------

function CommDKP:LootDistReceived(commObject)
  if AlreadyHaveIndex(CommDKP:GetTable(CommDKP_Loot, true, commObject.CurrentTeam), commObject.Data.index) then return end  -- AD-10.5

  local search = CommDKP:Table_Search(CommDKP:GetTable(CommDKP_DKPTable, true, commObject.CurrentTeam), commObject.Data.player, "player")
  if search then
    local DKPTable = CommDKP:GetTable(CommDKP_DKPTable, true, commObject.CurrentTeam)[search[1][1]]
    DKPTable.dkp = DKPTable.dkp + commObject.Data.cost
    DKPTable.lifetime_spent = DKPTable.lifetime_spent + commObject.Data.cost
  else
    if not CommDKP:GetTable(CommDKP_Archive, true, commObject.CurrentTeam)[commObject.Data.player] or 
    (
      CommDKP:GetTable(CommDKP_Archive, true, commObject.CurrentTeam)[commObject.Data.player] and 
      CommDKP:GetTable(CommDKP_Archive, true, commObject.CurrentTeam)[commObject.Data.player].deleted ~= true
    ) then
      CommDKP_Profile_Create(commObject.Data.player, commObject.Data.cost, 0, commObject.Data.cost, commObject.CurrentTeam);
    end
  end
  tinsert(CommDKP:GetTable(CommDKP_Loot, true, commObject.CurrentTeam), 1, commObject.Data)

  CommDKP:LootHistory_Reset()
  CommDKP:LootHistory_Update(L["NOFILTER"])
  CommDKP:FilterDKPTable(core.currentSort, "reset")
  if CommDKP.StatusVerify_Update and CommDKP.DKPTable and CommDKP.DKPTable.SeedVerify then CommDKP:StatusVerify_Update() end   -- AD-36.2.1 (BR-28.4, CM-06)
end


----------
-- CommDKPDKPDist message HANDLERS
----------

function CommDKP:DKPDistReceived(commObject)
  if AlreadyHaveIndex(CommDKP:GetTable(CommDKP_DKPHistory, true, commObject.CurrentTeam), commObject.Data.index) then return end  -- AD-10.5

  local players = {strsplit(",", strsub(commObject.Data.players, 1, -2))}
  local dkp = commObject.Data.dkp

  tinsert(CommDKP:GetTable(CommDKP_DKPHistory, true, commObject.CurrentTeam), 1, commObject.Data)

  for i=1, #players do
    local search = CommDKP:Table_Search(CommDKP:GetTable(CommDKP_DKPTable, true, commObject.CurrentTeam), players[i], "player")

    if search then
      CommDKP:GetTable(CommDKP_DKPTable, true, commObject.CurrentTeam)[search[1][1]].dkp = CommDKP:GetTable(CommDKP_DKPTable, true, commObject.CurrentTeam)[search[1][1]].dkp + tonumber(dkp)
      if tonumber(dkp) > 0 then
        CommDKP:GetTable(CommDKP_DKPTable, true, commObject.CurrentTeam)[search[1][1]].lifetime_gained = CommDKP:GetTable(CommDKP_DKPTable, true, commObject.CurrentTeam)[search[1][1]].lifetime_gained + tonumber(dkp)
      end
    else
      if not CommDKP:GetTable(CommDKP_Archive, true, commObject.CurrentTeam)[players[i]] or
       (
         CommDKP:GetTable(CommDKP_Archive, true, commObject.CurrentTeam)[players[i]] and 
         CommDKP:GetTable(CommDKP_Archive, true, commObject.CurrentTeam)[players[i]].deleted ~= true
      ) then
        CommDKP_Profile_Create(players[i], tonumber(dkp), tonumber(dkp), nil, commObject.CurrentTeam);  -- creates temp profile for data and requests additional data from online officers (hidden until data received)
      end
    end
  end

  if CommDKP.ConfigTab6 and CommDKP.ConfigTab6.history and CommDKP.ConfigTab6:IsShown() then
    CommDKP:DKPHistory_Update(true)
  end
  CommDKP:FilterDKPTable(core.currentSort, "reset")
  if CommDKP.StatusVerify_Update and CommDKP.DKPTable and CommDKP.DKPTable.SeedVerify then CommDKP:StatusVerify_Update() end   -- AD-36.2.1 (BR-28.4, CM-06)
end

----------
-- CommDKPDecay message HANDLERS
----------

function CommDKP:DKPDecayReceived(commObject)
  if AlreadyHaveIndex(CommDKP:GetTable(CommDKP_DKPHistory, true, commObject.CurrentTeam), commObject.Data.index) then return end  -- AD-10.5

  local players = {strsplit(",", strsub(commObject.Data.players, 1, -2))}
  local dkp = {strsplit(",", commObject.Data.dkp)}

  tinsert(CommDKP:GetTable(CommDKP_DKPHistory, true, commObject.CurrentTeam), 1, commObject.Data)
  
  for i=1, #players do
    local search = CommDKP:Table_Search(CommDKP:GetTable(CommDKP_DKPTable, true, commObject.CurrentTeam), players[i], "player")

    if search then
      CommDKP:GetTable(CommDKP_DKPTable, true, commObject.CurrentTeam)[search[1][1]].dkp = CommDKP:GetTable(CommDKP_DKPTable, true, commObject.CurrentTeam)[search[1][1]].dkp + tonumber(dkp[i])
    else
      if not CommDKP:GetTable(CommDKP_Archive, true, commObject.CurrentTeam)[players[i]] or (CommDKP:GetTable(CommDKP_Archive, true, commObject.CurrentTeam)[players[i]] and CommDKP:GetTable(CommDKP_Archive, true, commObject.CurrentTeam)[players[i]].deleted ~= true) then
        CommDKP_Profile_Create(players[i], tonumber(dkp[i]), nil, nil, commObject.CurrentTeam);  -- creates temp profile for data and requests additional data from online officers (hidden until data received)
      end
    end
  end

  if CommDKP.ConfigTab6 and CommDKP.ConfigTab6.history and CommDKP.ConfigTab6:IsShown() then
    CommDKP:DKPHistory_Update(true)
  end
  CommDKP:FilterDKPTable(core.currentSort, "reset")
  if CommDKP.StatusVerify_Update and CommDKP.DKPTable and CommDKP.DKPTable.SeedVerify then CommDKP:StatusVerify_Update() end   -- AD-36.2.1 (BR-28.4, CM-06)
end

----------
-- CommDKPAddUsers message HANDLERS
----------

function CommDKP:AddUsersReceived(commObject, sender)  -- AD-10.2: sender was an unset global
  if not CommDKP:IsSelf(sender) then
    core.LastOfficerSender = sender
    CommDKP:AddEntitiesToDKPTable(commObject.Data, commObject.TargetTeam);
  end
  return;
end

----------
-- CommDKPDelUsers message HANDLERS
----------

function CommDKP:DelUsersReceived(commObject, sender)  -- AD-10.2: sender was an unset global
  local numPlayers = 0
  local removedUsers = ""

  if not CommDKP:IsSelf(sender) then
    for i=1, #commObject.Data do
      local search = CommDKP:Table_Search(CommDKP:GetTable(CommDKP_DKPTable, true, commObject.CurrentTeam), commObject.Data[i].player, "player")

      if search and commObject.Data[i].deleted and commObject.Data[i].deleted ~= "Recovered" then
        if commObject.Data[i].edited == nil then
          commObject.Data[i].edited = time();
        end

        if (CommDKP:GetTable(CommDKP_Archive, true, commObject.CurrentTeam)[commObject.Data[i].player] and commObject.Data[i].deleted) or (CommDKP:GetTable(CommDKP_Archive, true, commObject.CurrentTeam)[commObject.Data[i].player] and CommDKP:GetTable(CommDKP_Archive, true, commObject.CurrentTeam)[commObject.Data[i].player].edited < commObject.Data[i].edited) or (not CommDKP:GetTable(CommDKP_Archive, true, commObject.CurrentTeam)[commObject.Data[i].player]) then
          --delete user, archive data
          local src = commObject.Data[i]
          local myRow = CommDKP:GetTable(CommDKP_DKPTable, true, commObject.CurrentTeam)[search[1][1]]   -- before tremove
          -- AD-36.8.2 (BR-28.23, CM-15): sender's pre-removal values; older sender -> my own row; else 0.
          local function val(k) return tonumber(src[k]) or tonumber(myRow and myRow[k]) or 0 end
          local arch = CommDKP:GetTable(CommDKP_Archive, true, commObject.CurrentTeam)
          if not arch[src.player] then    -- creates/adds to archive entry for user
            arch[src.player] = { dkp=val("dkp"), lifetime_spent=val("lifetime_spent"), lifetime_gained=val("lifetime_gained"), deleted=src.deleted, edited=src.edited }
          else
            arch[src.player].deleted = src.deleted
            arch[src.player].edited = src.edited
            arch[src.player].dkp, arch[src.player].lifetime_spent, arch[src.player].lifetime_gained = val("dkp"), val("lifetime_spent"), val("lifetime_gained")
          end
          
          c = CommDKP:GetCColors(CommDKP:GetTable(CommDKP_DKPTable, true, commObject.CurrentTeam)[search[1][1]].class)
          if i==1 then
            removedUsers = "|c"..c.hex..CommDKP:GetTable(CommDKP_DKPTable, true, commObject.CurrentTeam)[search[1][1]].player.."|r"
          else
            removedUsers = removedUsers..", |c"..c.hex..CommDKP:GetTable(CommDKP_DKPTable, true, commObject.CurrentTeam)[search[1][1]].player.."|r"
          end
          numPlayers = numPlayers + 1

          tremove(CommDKP:GetTable(CommDKP_DKPTable, true, commObject.CurrentTeam), search[1][1])
          CommDKP:GetTable(CommDKP_Profiles, true, commObject.CurrentTeam)[commObject.Data[i].player] = nil;

          local search2 = CommDKP:Table_Search(CommDKP:GetTable(CommDKP_Standby, true, commObject.CurrentTeam), commObject.Data[i].player, "player");

          if search2 then
            table.remove(CommDKP:GetTable(CommDKP_Standby,true, commObject.CurrentTeam), search2[1][1])
          end
        end
      elseif not search and commObject.Data[i].deleted == "Recovered" then
        if CommDKP:GetTable(CommDKP_Archive, true, commObject.CurrentTeam)[commObject.Data[i].player] and (CommDKP:GetTable(CommDKP_Archive, true, commObject.CurrentTeam)[commObject.Data[i].player].edited == nil or CommDKP:GetTable(CommDKP_Archive, true, commObject.CurrentTeam)[commObject.Data[i].player].edited < commObject.Data[i].edited) then
          CommDKP_Profile_Create(commObject.Data[i].player, nil, nil, nil, commObject.CurrentTeam);  -- User was recovered, create/request profile as needed
          CommDKP:GetTable(CommDKP_Archive, true, commObject.CurrentTeam)[commObject.Data[i].player].deleted = "Recovered"
          CommDKP:GetTable(CommDKP_Archive, true, commObject.CurrentTeam)[commObject.Data[i].player].edited = commObject.Data[i].edited
        end
      end
    end
    if numPlayers > 0 then
      CommDKP:FilterDKPTable(core.currentSort, "reset")
      CommDKP:Print("["..CommDKP:GetTeamName(commObject.CurrentTeam).."] ".."Removed "..numPlayers.." player(s): "..removedUsers)
    end
  end
  return
end

----------
-- CommDKPDelLoot message HANDLERS
----------

function CommDKP:DelLootReceived(commObject)
  if AlreadyHaveIndex(CommDKP:GetTable(CommDKP_Loot, true, commObject.CurrentTeam), commObject.Data.index) then return end  -- AD-36.2.2 (BR-28.7, CM-16)
  local search = CommDKP:Table_Search(CommDKP:GetTable(CommDKP_Loot, true, commObject.CurrentTeam), commObject.Data.deletes, "index")

  if search then
    CommDKP:GetTable(CommDKP_Loot, true, commObject.CurrentTeam)[search[1][1]].deletedby = commObject.Data.index
  end

  local search_player = CommDKP:Table_Search(CommDKP:GetTable(CommDKP_DKPTable, true, commObject.CurrentTeam), commObject.Data.player, "player")

  if search_player then
    CommDKP:GetTable(CommDKP_DKPTable, true, commObject.CurrentTeam)[search_player[1][1]].dkp = CommDKP:GetTable(CommDKP_DKPTable, true, commObject.CurrentTeam)[search_player[1][1]].dkp + commObject.Data.cost                  -- refund previous looter
    CommDKP:GetTable(CommDKP_DKPTable, true, commObject.CurrentTeam)[search_player[1][1]].lifetime_spent = CommDKP:GetTable(CommDKP_DKPTable, true, commObject.CurrentTeam)[search_player[1][1]].lifetime_spent + commObject.Data.cost       -- remove from lifetime_spent
  else
    if not CommDKP:GetTable(CommDKP_Archive, true, commObject.CurrentTeam)[commObject.Data.player] or (CommDKP:GetTable(CommDKP_Archive, true, commObject.CurrentTeam)[commObject.Data.player] and CommDKP:GetTable(CommDKP_Archive, true, commObject.CurrentTeam)[commObject.Data.player].deleted ~= true) then
      CommDKP_Profile_Create(commObject.Data.player, commObject.Data.cost, 0, commObject.Data.cost, commObject.CurrentTeam);  -- creates temp profile for data and requests additional data from online officers (hidden until data received)
    end
  end

  table.insert(CommDKP:GetTable(CommDKP_Loot, true, commObject.CurrentTeam), 1, commObject.Data)
  CommDKP:SortLootTable()
  CommDKP:LootHistory_Reset()
  CommDKP:LootHistory_Update(L["NOFILTER"]);
  CommDKP:FilterDKPTable(core.currentSort, "reset")
  if CommDKP.StatusVerify_Update and CommDKP.DKPTable and CommDKP.DKPTable.SeedVerify then CommDKP:StatusVerify_Update() end   -- AD-36.2.1 (BR-28.4, CM-06)
end

----------
-- CommDKPDelSync message HANDLERS
----------

function CommDKP:DelSyncReceived(commObject)
  if AlreadyHaveIndex(CommDKP:GetTable(CommDKP_DKPHistory, true, commObject.CurrentTeam), commObject.Data.index) then return end  -- AD-36.2.2 (BR-28.7, CM-16)
  local search = CommDKP:Table_Search(CommDKP:GetTable(CommDKP_DKPHistory, true, commObject.CurrentTeam), commObject.Data.deletes, "index")
  local players = {strsplit(",", strsub(commObject.Data.players, 1, -2))}   -- cuts off last "," from string to avoid creating an empty value
  local dkp, mod;

  if strfind(commObject.Data.dkp, "%-%d*%.?%d+%%") then     -- determines if it's a mass decay
    dkp = {strsplit(",", commObject.Data.dkp)}
    mod = "perc";
  else
    dkp = commObject.Data.dkp
    mod = "whole"
  end

  for i=1, #players do
    if mod == "perc" then
      local search2 = CommDKP:Table_Search(CommDKP:GetTable(CommDKP_DKPTable, true, commObject.CurrentTeam), players[i], "player")

      if search2 then
        CommDKP:GetTable(CommDKP_DKPTable, true, commObject.CurrentTeam)[search2[1][1]].dkp = CommDKP:GetTable(CommDKP_DKPTable, true, commObject.CurrentTeam)[search2[1][1]].dkp + tonumber(dkp[i])
      else
        if not CommDKP:GetTable(CommDKP_Archive, true, commObject.CurrentTeam)[players[i]] or (CommDKP:GetTable(CommDKP_Archive, true, commObject.CurrentTeam)[players[i]] and CommDKP:GetTable(CommDKP_Archive, true, commObject.CurrentTeam)[players[i]].deleted ~= true) then
          CommDKP_Profile_Create(players[i], tonumber(dkp[i]), nil, nil, commObject.CurrentTeam);  -- creates temp profile for data and requests additional data from online officers (hidden until data received)
        end
      end
    else
      local search2 = CommDKP:Table_Search(CommDKP:GetTable(CommDKP_DKPTable, true, commObject.CurrentTeam), players[i], "player")

      if search2 then
        CommDKP:GetTable(CommDKP_DKPTable, true, commObject.CurrentTeam)[search2[1][1]].dkp =CommDKP:GetTable(CommDKP_DKPTable, true, commObject.CurrentTeam)[search2[1][1]].dkp + tonumber(dkp)

        if tonumber(dkp) < 0 then
          CommDKP:GetTable(CommDKP_DKPTable, true, commObject.CurrentTeam)[search2[1][1]].lifetime_gained = CommDKP:GetTable(CommDKP_DKPTable, true, commObject.CurrentTeam)[search2[1][1]].lifetime_gained + tonumber(dkp)
        end
      else
        if not CommDKP:GetTable(CommDKP_Archive, true, commObject.CurrentTeam)[players[i]] or (CommDKP:GetTable(CommDKP_Archive, true, commObject.CurrentTeam)[players[i]] and CommDKP:GetTable(CommDKP_Archive, true, commObject.CurrentTeam)[players[i]].deleted ~= true) then
          local gained;
          if tonumber(dkp) < 0 then gained = tonumber(dkp) else gained = 0 end

          CommDKP_Profile_Create(players[i], tonumber(dkp), gained, nil, commObject.CurrentTeam);  -- creates temp profile for data and requests additional data from online officers (hidden until data received)
        end
      end
    end
  end

  if search then
    CommDKP:GetTable(CommDKP_DKPHistory, true, commObject.CurrentTeam)[search[1][1]].deletedby = commObject.Data.index;    -- adds deletedby field if the entry exists
  end

  table.insert(CommDKP:GetTable(CommDKP_DKPHistory, true, commObject.CurrentTeam), 1, commObject.Data)

  if CommDKP.ConfigTab6 and CommDKP.ConfigTab6.history then
    CommDKP:DKPHistory_Update(true)
  end
  CommDKP:FilterDKPTable(core.currentSort, "reset")   -- AD-36.2.5 (BR-28.8, CM-26)
  if CommDKP.StatusVerify_Update and CommDKP.DKPTable and CommDKP.DKPTable.SeedVerify then CommDKP:StatusVerify_Update() end   -- AD-36.2.1 (BR-28.4, CM-06)
end

----------
-- CommDKPMinBid message HANDLERS
----------

function CommDKP:MinBidReceived(commObject)
  if core.IsOfficer then
    local data = type(commObject) == "table" and commObject.Data or nil
    if type(data) ~= "table" then return end
    core.DB.MinBidBySlot = data[1]
    -- AD-36.1.2 (BR-28.2, CM-02): pairs() over each team's items, so the string-keyed map (current senders) and a legacy
    -- numeric array both apply. Stored under the STRING itemID key (AD-12.3). Malformed entries are skipped.
    if type(data[2]) == "table" then
      for _, bidInfo in ipairs(data[2]) do
        local bidTeam = type(bidInfo) == "table" and bidInfo[1] or nil
        local bidItems = type(bidInfo) == "table" and bidInfo[2] or nil
        if (type(bidTeam) == "string" or type(bidTeam) == "number") and type(bidItems) == "table" then
          local dest = CommDKP:GetTable(CommDKP_MinBids, true, tostring(bidTeam))
          for k, v in pairs(bidItems) do
            local id = type(v) == "table" and (v.itemID or (type(k) == "string" and k or nil)) or nil   -- D-36.5
            if id ~= nil then
              id = tostring(id)
              local row = dest[id]
              if type(row) == "table" then
                row.minbid = v.minbid
                if v.link ~= nil then row.link = v.link end
                if v.icon ~= nil then row.icon = v.icon end
              else
                dest[id] = v
              end
            end
          end
        end
      end
    end
    if CommDKP.RefreshOptionsUI then CommDKP:RefreshOptionsUI() end
  end
end

----------
-- CommDKPMaxBid message HANDLERS
----------

function CommDKP:MaxbidReceived(commObject)
  if core.IsOfficer then
    local data = type(commObject) == "table" and commObject.Data or nil
    if type(data) ~= "table" then return end
    core.DB.MaxBidBySlot = data[1];                                   -- AD-36.1.2: the global leak is gone
    if type(data[2]) == "table" then
      for _, bidInfo in ipairs(data[2]) do
        local bidTeam = type(bidInfo) == "table" and bidInfo[1] or nil
        local bidItems = type(bidInfo) == "table" and bidInfo[2] or nil
        if (type(bidTeam) == "string" or type(bidTeam) == "number") and type(bidItems) == "table" then
          local dest = CommDKP:GetTable(CommDKP_MaxBids, true, tostring(bidTeam))
          for _, v in pairs(bidItems) do                                -- array upsert by item (C-28.7)
            if type(v) == "table" and v.item ~= nil then
              local search = CommDKP:Table_Search(dest, v.item)
              if search then dest[search[1][1]].maxbid = v.maxbid else table.insert(dest, v) end
            end
          end
        end
      end
    end
    if CommDKP.RefreshOptionsUI then CommDKP:RefreshOptionsUI() end
  end
end

----------
-- CDKPWhitelist message HANDLERS
----------

function CommDKP:WhiteListReceived(commObject)
  if not CommDKP:IsPlayerGuildLeader() then -- only applies if not GM (AD-9.2.7: roster-independent)
    CommDKP:SetTable(CommDKP_Whitelist, false, commObject.Data, commObject.CurrentTeam);
  end
end

----------
-- CommDKPStand message HANDLERS
----------

function CommDKP:StandByReceived(commObject)
  CommDKP:SetTable(CommDKP_Standby, true, commObject.Data, commObject.CurrentTeam); -- issues/153
  CommDKP:FilterDKPTable(core.currentSort, "reset")   -- AD-36.7 (BR-28.21a): no-op without the main window
end

----------
-- CommDKPSetPrice message HANDLERS
----------

function CommDKP:SetPriceReceived(commObject)
  -- AD-13.4: read the parameter, not the leaked global _objReceived; cold-cache safe item key.
  local _objSetPrice = commObject and commObject.Data
  if not _objSetPrice or not _objSetPrice.link then return end
  local _, _, _, _, itemID = CommDKP:ParseItemLink(_objSetPrice.link)
  itemID = itemID or (_objSetPrice.itemID and tostring(_objSetPrice.itemID))
  if not itemID then return end

  CommDKP:GetTable(CommDKP_MinBids, true, commObject.CurrentTeam)[itemID] = _objSetPrice;

  CommDKP:RefreshPriceTable();	-- AD-25 (S6)

end

----------
-- CommDKPDKPModes message HANDLERS
----------

function CommDKP:DKPModesReceived(commObject)
  if (core.DB.modes.mode ~= commObject.Data[1].mode) or (core.DB.modes.MaxBehavior ~= commObject.Data[1].MaxBehavior) then
    CommDKP:Print(L["RECOMMENDRELOAD"])
  end
  core.DB.modes = commObject.Data[1]
  core.DB.DKPBonus = commObject.Data[2]
  core.DB.raiders = commObject.Data[3]
  if CommDKP.RefreshOptionsUI then CommDKP:RefreshOptionsUI() end
  if CommDKP.RefreshModesWindow then                                   -- AD-35.6 (BR-27.7)
    local okM, errM = pcall(CommDKP.RefreshModesWindow, CommDKP)
    if not okM then geterrorhandler()(errM) end                        -- a UI error never undoes the applied payload
  end
end

----------
-- CommDKPSeed message HANDLERS
----------

----------
-- AD-35.3 (CDKP-027) officer seed reply
----------
local OFFICER_SEED_COOLDOWN = 15            -- BR-27.3: <= 1 officer seed reply per 15 s
local OFFICER_SEED_JITTER_MIN, OFFICER_SEED_JITTER_MAX = 1, 4   -- G-27.2: spread N officers; lets one cover the rest
local OFFICER_SEED_SIG_TTL = 600            -- G-27.1: one answer per (sender, state) per 10 min

-- G-27.6 / AD-35 D-1, D-2: the SAME per-table rule as SendSeedData (init.lua:373-393): the row at [1] if its index is
-- "<officer>-<ts>" and that officer validates, else "start". Deletion rows are NOT skipped. H137a diffs this against
-- the real SendSeedData; change both or neither. Returns index, row (row = nil for "start").
function CommDKP:GetNewestSeedIndex(tbl)
  local top = type(tbl) == "table" and tbl[1] or nil
  if type(top) ~= "table" or type(top.index) ~= "string" or not strfind(top.index, "-") then return "start", nil end
  local off = strsplit("-", top.index)
  local okV, valid = pcall(CommDKP.ValidateSender, CommDKP, off)
  if okV and valid then return top.index, top end
  return "start", nil
end

-- BR-27.2(3): sorted "team|prop|theirs|mine" keys for which the sender is PROVABLY behind. Pure read, no writes.
-- Behind = sender reported "start" while I have a valid newest, OR sender's index is a known row of mine that is
-- strictly older (numeric .date) than my newest. Unknown index (sender ahead / diverged) = not behind (G-27.1).
-- Teams come from my own team list (as SendSeedData), so a sender cannot make me create team buckets.
function CommDKP:GetSeedBehindKeys(data)
  local out = {}
  if type(data) ~= "table" then return out end
  for _, t in ipairs(CommDKP:GetGuildTeamList()) do
    local team = tostring(t[1])
    local v = data[team]
    if type(v) == "table" then
      for _, prop in ipairs({ "DKPHistory", "Loot" }) do
        local theirs = v[prop]
        if type(theirs) == "string" then
          local tbl = CommDKP:GetTable(prop == "Loot" and CommDKP_Loot or CommDKP_DKPHistory, true, team)
          local mine, myRow = CommDKP:GetNewestSeedIndex(tbl)
          if mine ~= "start" and theirs ~= mine then
            local behind = (theirs == "start")
            if not behind then
              for i = 2, #tbl do
                local row = tbl[i]
                if type(row) == "table" and row.index == theirs then
                  behind = type(row.date) == "number" and type(myRow.date) == "number" and myRow.date > row.date
                  break
                end
              end
            end
            if behind then out[#out + 1] = team .. "|" .. prop .. "|" .. theirs .. "|" .. mine end
          end
        end
      end
    end
  end
  table.sort(out)
  return out
end

-- BR-27.3 / G-27.2: decides and schedules; returns true if a reply is (now or already) scheduled. State lives in
-- core.OfficerSeedReply (session only, never SavedVariables).
function CommDKP:QueueOfficerSeedReply(data, who)
  if core.IsOfficer ~= true then return false end
  local now = (type(GetTime) == "function" and GetTime()) or 0
  core.OfficerSeedReply = core.OfficerSeedReply or { gen = 0, bySender = {} }
  local st = core.OfficerSeedReply

  -- G-27.2 coverage: while a reply is pending, ANY non-self seed that already carries my newest index for every pending
  -- team/table reached the whole guild, so my pending reply is redundant (checked before this seed's own verdict).
  if st.pending and st.pendingKeys and type(data) == "table" then
    local all = true
    for pk, mine in pairs(st.pendingKeys) do
      local team, prop = strsplit("|", pk)
      local v = data[team]
      if not (type(v) == "table" and v[prop] == mine) then all = false; break end
    end
    if all then st.coveredAt = now end
  end

  for k, e in pairs(st.bySender) do if now - e.at >= OFFICER_SEED_SIG_TTL then st.bySender[k] = nil end end
  local keys = CommDKP:GetSeedBehindKeys(data)
  if #keys == 0 then return false end
  local key = (type(who) == "string" and who ~= "") and who or "?"
  local sig = table.concat(keys, ";")
  if st.bySender[key] and st.bySender[key].sig == sig then return false end   -- G-27.1: this exact state already answered
  st.bySender[key] = { sig = sig, at = now }
  st.pendingKeys = st.pendingKeys or {}
  for _, k in ipairs(keys) do
    local team, prop, _, mine = strsplit("|", k)
    st.pendingKeys[team .. "|" .. prop] = mine
  end
  if st.pending then return true end                                           -- coalesced: one reply covers all

  local wait = 0
  if st.lastReplyAt and now - st.lastReplyAt < OFFICER_SEED_COOLDOWN then
    wait = st.lastReplyAt + OFFICER_SEED_COOLDOWN - now                         -- D-4: deferred, not dropped
  end
  local delay = wait + OFFICER_SEED_JITTER_MIN + math.random() * (OFFICER_SEED_JITTER_MAX - OFFICER_SEED_JITTER_MIN)
  st.gen = st.gen + 1
  local gen = st.gen
  st.pending, st.coveredAt = true, nil
  C_Timer.After(delay, function()
    if gen ~= st.gen then return end
    st.pending = false
    local covered = st.coveredAt ~= nil
    st.pendingKeys, st.coveredAt = nil, nil
    st.lastReplyAt = (type(GetTime) == "function" and GetTime()) or 0
    if covered then CommDKP:CommTrace("OFFSEED reply suppressed (covered by another seed)"); return end
    if core.IsOfficer ~= true or not IsInGuild() then return end
    local ok, err = pcall(CommDKP.SendSeedData, CommDKP)
    if not ok then geterrorhandler()(err); return end
    CommDKP:CommTrace("OFFSEED reply sent (%d key(s))", #keys)
  end)
  CommDKP:CommTrace("OFFSEED reply scheduled for %s in %.1fs", key, delay)
  return true
end

function CommDKP:SeedReceived(commObject, sender)

  --[[ 
      Data = {
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

  if CommDKP:IsSelf(sender) then
    CommDKP:CommTrace("RECV CommDKPSeed from=%s (self echo) reply=none", tostring(sender))
    return
  end
  local who = CommDKP:ResolveSenderName(sender)
  local queued = CommDKP:QueueTalentSend("seed", nil, who)    -- AD-30.1.2 FIRST: nothing below can suppress the reply
  CommDKP:CommTrace("RECV CommDKPSeed from=%s -> %s reply=%s", tostring(sender), tostring(who), queued and "scheduled" or "cooldown")
  -- AD-34.1 (G-26.1): every member seeds now (BR-26.4); only a validated officer may become the WHISPER fallback target.
  local okV, isOfficer = pcall(CommDKP.ValidateSender, CommDKP, sender)
  if okV and isOfficer == true then core.LastOfficerSender = sender end
  if type(commObject) ~= "table" or type(commObject.Data) ~= "table" then return end
  local ok, err = pcall(function()   -- AD-30.1.2: a seed-loop error is reported but never suppresses the reply
    local changed = false
    for tableIndex,v in pairs(commObject.Data) do
      if(type(v) == "table") then
        for property,value in pairs(v) do
          if value ~= "start" then

            local off1,date1 = strsplit("-", value);

            if CommDKP:ValidateSender(off1) then
              if property == "Loot" then

                local searchLoot = CommDKP:Table_Search(CommDKP:GetTable(CommDKP_Loot, true, tostring(tableIndex)), value, "index")

                if not searchLoot then
                  local t = CommDKP:GetTable(CommDKP_Loot, true, tostring(tableIndex))
                  if t.seed ~= value then t.seed = value; changed = true end          -- AD-35.2 (BR-27.1)
                end

              elseif property == "DKPHistory" then
                local searchDKPHistory = CommDKP:Table_Search(CommDKP:GetTable(CommDKP_DKPHistory, true, tostring(tableIndex)), value, "index")
                
                if not searchDKPHistory then
                  local t = CommDKP:GetTable(CommDKP_DKPHistory, true, tostring(tableIndex))
                  if t.seed ~= value then t.seed = value; changed = true end          -- AD-35.2 (BR-27.1)
                end
              end
            end
          end
        end
      end
    end
    -- AD-35.2 (BR-27.1): one pip refresh after the loop, only when a .seed really changed. Guarded for sandboxes and
    -- for seeds that arrive before CreateMenu (+5 s) has built the pip; StatusVerify_Update keeps its own hidden-window
    -- early return (G-27.7), so core.OOD is then computed when the window opens.
    if changed and CommDKP.StatusVerify_Update and CommDKP.DKPTable and CommDKP.DKPTable.SeedVerify then
      CommDKP:StatusVerify_Update()
    end
  end)
  if not ok then geterrorhandler()(err) end
  -- AD-35.3 (BR-27.2): an online officer answers a provably-stale seed with its own seed. Fail-closed: any error means
  -- "no reply" and is only traced (never raised), so sandboxes without guild APIs (H128/H132) see no change.
  if core.IsOfficer == true and CommDKP.QueueOfficerSeedReply then
    local okR, res = pcall(CommDKP.QueueOfficerSeedReply, CommDKP, commObject.Data, who)
    if not okR then CommDKP:CommTrace("OFFSEED reply skipped from=%s (error: %s)", tostring(who), tostring(res)) end
  end
end

----------
-- CommDKPTeams message HANDLERS
----------

function CommDKP:TeamsReceived(commObject, sender)
  CommDKP:GetTable(CommDKP_DB, false)["teams"] = commObject.Teams
  -- AD-36.5.3 (BR-28.14, CM-10): show a renamed team at once; never switches team. Skipped (no error) without the main
  -- window or when the new list lacks my current index (GetCurrentTeamName would index nil).
  local ui, teams = CommDKP.UIConfig, commObject.Teams
  if ui and ui.TeamViewChangerDropDown and CommDKP.DD and type(teams) == "table"
    and type(teams[CommDKP:GetCurrentTeamIndex()]) == "table" then
    CommDKP.DD:UIDropDownMenu_SetText(ui.TeamViewChangerDropDown, CommDKP:GetCurrentTeamName())
  end
end

----------
-- CommDKPCurTeam message HANDLERS
----------

function CommDKP:CurTeamReceived(commObject, sender)
  CommDKP:SetCurrentTeam(commObject.CurrentTeam) -- this also refreshes all the tables/views/graphs
end

----------
-- TODO message HANDLERS
----------