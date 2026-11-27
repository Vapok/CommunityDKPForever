local _, core = ...;
local _G = _G;
local CommDKP = core.CommDKP;
local CommDKPApi = core.CommDKPApi;
local L = core.L;
local W = CommDKP.Widgets
local LibDD = LibStub:GetLibrary("LibUIDropDownMenu-4.0");
local DD = CommDKP.DD                     -- AD-19.2 (012b): kit selector protocol for the Boss dropdown

local Bids_Submitted = {};
local upper = string.upper
local width, height, numrows = 352, 18, 13   -- §12.4.3 Bids card: 13 x 18 px rows (352 wide + the rail lane)
-- AD-22.8.3 (CDKP-015d, BR-084.3/084.4): Bids-table secondary text (rank, row number) = palette textMuted at
-- full alpha, read at call time so it follows core.Palette. File-local: no Widgets.lua / Core.lua change.
local MUTED_FALLBACK = { 0.725, 0.655, 0.537, 1 } -- #B9A789 = Core.lua TEXT_MUTED
local function MutedRGBA()
  local tm = (core.Palette and core.Palette.textMuted) or MUTED_FALLBACK
  return tm[1], tm[2], tm[3], 1 -- alpha forced to 1 (BR-084.4: never translucent)
end
local function ToByte(v)
  v = math.floor((tonumber(v) or 0) * 255 + 0.5)
  if v < 0 then return 0 elseif v > 255 then return 255 end
  return v
end
local function MutedHex() -- Forever/Legacy textMuted -> "|cffb9a789"
  local r, g, b = MutedRGBA()
  return string.format("|cff%02x%02x%02x", ToByte(r), ToByte(g), ToByte(b))
end
local CurrItemForBid;
local CurrItemIcon;
local SelectedBidder = {}
local CurZone;
local Timer = 0;
local timerToggle = 0;
local mode;
local events = CreateFrame("Frame", "BiddingEventsFrame");
local menuFrame = LibDD:Create_UIDropDownMenu("CommDKPBidWindowMenuFrame", UIParent)
CommDKP.Widgets.RegisterContextMenu(menuFrame) -- CDKP-019 (AD-27.2.3)
local hookedSlots = {}

function CommDKPApi:SetPriceListApi(api)
  if api.GetItemPrice ~= nil then
    CommDKPApi.pricelist = api
    return true
  end
  return false
end

local function UpdateBidWindow()
  core.BiddingWindow.item:SetText(CurrItemForBid)
  core.BiddingWindow.itemIcon:SetTexture(CurrItemIcon)
end

-- AD-19.2 (012b) / BR-12.10.2: open, new item and Clear Window all reset the Boss dropdown to the last kill.
-- Read-only: never writes bossargs / core.LastKilledBoss (PM-12.5). bossargs is the persisted source, core.* the fallback.
local function ResetBiddingBoss()
  local b = core.BiddingWindow and core.BiddingWindow.boss
  if not b then return end
  local args = core.DB and core.DB.bossargs or {}
  local boss = (args.LastKilledBoss and args.LastKilledBoss ~= "") and args.LastKilledBoss or core.LastKilledBoss
  local zone = (args.CurrentRaidZone and args.CurrentRaidZone ~= "") and args.CurrentRaidZone or core.CurrentRaidZone
  b.cdkpZone = zone or ""
  b:SetText(boss or "")
end

function CommDKP:BidsSubmitted_Get()
  return Bids_Submitted;
end

function CommDKP:BidsSubmitted_Clear()
  Bids_Submitted = {};
end

local function Roll_OnEvent(self, event, arg1, ...)
  if event == "CHAT_MSG_SYSTEM" and core.BidInProgress then
    -- CDKP-003: system text can be a Secret Value in restricted contexts; never pattern-match it.
    if issecretvalue and issecretvalue(arg1) then return end

    -- corrects roll pattern for german clients (local copy: never write to Blizzard's global string, it taints it)
    local rollResult = (GetLocale() == 'deDE') and "%s w\195\188rfelt. Ergebnis: %d (%d-%d)" or RANDOM_ROLL_RESULT
    local pattern = string.gsub(rollResult, "[%(%)-]", "%%%1")
    pattern = string.gsub(pattern, "%%s", "(.+)")
    pattern = string.gsub(pattern, "%%d", "%(%%d+%)")

    for name, roll, low, high in string.gmatch(arg1, pattern) do
      name = CommDKP:StripRealm(name) or name
      name = CommDKP:ResolveRosterName(name) or name   -- AD-13.3: "Bank" -> "Bank Robbers"
      local search = CommDKP:Table_Search(CommDKP:GetTable(CommDKP_DKPTable, true), name)
      local minRoll;
          local maxRoll;

          if core.DB.modes.rolls.UsePerc then
            if core.DB.modes.rolls.min == 0 or core.DB.modes.rolls.min == 1 then
              minRoll = 1;
            else
              minRoll = CommDKP:GetTable(CommDKP_DKPTable, true)[search[1][1]].dkp * (core.DB.modes.rolls.min / 100);
            end
            maxRoll = CommDKP:GetTable(CommDKP_DKPTable, true)[search[1][1]].dkp * (core.DB.modes.rolls.max / 100) + core.DB.modes.rolls.AddToMax;
          elseif not core.DB.modes.rolls.UsePerc then
            minRoll = core.DB.modes.rolls.min;

            if core.DB.modes.rolls.max == 0 then
              maxRoll = CommDKP:GetTable(CommDKP_DKPTable, true)[search[1][1]].dkp + core.DB.modes.rolls.AddToMax;
            else
              maxRoll = core.DB.modes.rolls.max + core.DB.modes.rolls.AddToMax;
            end
          end
          if tonumber(minRoll) < 1 then minRoll = 1 end
          if tonumber(maxRoll) < 1 then maxRoll = 1 end
          if tonumber(low) > tonumber(minRoll) or tonumber(high) > tonumber(maxRoll) then
            CommDKP:SendChat(L["ROLLDECLINED"].." "..math.floor(minRoll).."-"..math.floor(maxRoll)..".", "WHISPER", nil, name)
            return;
          end

          --math.floor(minRoll).."-"..math.floor(maxRoll)

      if search and mode == "Roll Based Bidding" and core.BiddingWindow.cost:GetNumber() > CommDKP:GetTable(CommDKP_DKPTable, true)[search[1][1]].dkp and not core.DB.modes.SubZeroBidding and core.DB.modes.costvalue ~= "Percent" then
            CommDKP:SendChat(L["ROLLNOTACCEPTED"].." "..CommDKP:GetTable(CommDKP_DKPTable, true)[search[1][1]].dkp.." "..L["DKP"]..".", "WHISPER", nil, name)

            return;
            end

      if not CommDKP:Table_Search(Bids_Submitted, name) and search then
        if core.DB.modes.AnnounceBid and ((Bids_Submitted[1] and Bids_Submitted[1].roll < roll) or not Bids_Submitted[1]) then
          local msgTarget = "RAID";
          if core.DB.modes.AnnounceRaidWarning then
            msgTarget = "RAID_WARNING";
          end

          if not core.DB.modes.AnnounceBidName then
            CommDKP:SendChat(L["NEWHIGHROLL"].." "..roll.." ("..low.."-"..high..")", msgTarget)
          else
            CommDKP:SendChat(L["NEWHIGHROLLER"].." "..name..": "..roll.." ("..low.."-"..high..")", msgTarget)
          end
        end
        table.insert(Bids_Submitted, {player=name, roll=roll, range=" ("..low.."-"..high..")"})
        if core.DB.modes.BroadcastBids then
          CommDKP.Sync:SendData("CommDKPBidShare", Bids_Submitted)
        end
      else
        if not search then
          CommDKP:SendChat(L["NAMENOTFOUND"], "WHISPER", nil, name)
        else
          CommDKP:SendChat(L["ONLYONEROLLWARN"], "WHISPER", nil, name)
        end
      end
      CommDKP:BidScrollFrame_Update()
    end
  end
end

local function BidCmd(...)
  local _, cmd = string.split(" ", ..., 2)

  if tonumber(cmd) then
    cmd = tonumber(cmd) -- converts it to a number if it's a valid numeric string
  elseif cmd then
    cmd = cmd:trim()
  end

  return cmd;
end

function CommDKP_CHAT_MSG_WHISPER(text, ...)
  local name = ...;
  -- CDKP-003 (AC-3): refuse Secret Value text/sender before any string operation.
  if issecretvalue and (issecretvalue(text) or (name ~= nil and issecretvalue(name))) then
    if core.IsOfficer then CommDKP:Print(L["BIDDINGLOCKED"]) end
    return
  end
  local cmd;
  local dkp;
  local seconds;
  local response = L["ERRORPROCESSING"];
  
  mode = core.DB.modes.mode;

  name = CommDKP:StripRealm(name) or name   -- AD-9.6: removes server name from name if exists
  name = CommDKP:ResolveRosterName(name) or name   -- AD-13.3: multi-word Forever names

  if string.find(text, "!bid") == 1 and core.IsOfficer == true then
    if core.BidInProgress then
      cmd = BidCmd(text)
      if (mode == "Static Item Values" and cmd ~= "cancel") or (mode == "Zero Sum" and cmd ~= "cancel" and core.DB.modes.ZeroSumBidType == "Static") then
        cmd = nil;
      end
      if cmd == "cancel" and core.DB.modes.mode ~= "Roll Based Bidding" then
        local flagCanceled = false
        for i=1, #Bids_Submitted do           -- !bid cancel will cancel their bid
          if Bids_Submitted[i] and CommDKP:SamePlayer(Bids_Submitted[i].player, name) then
            table.remove(Bids_Submitted, i)
            if core.DB.modes.BroadcastBids then
              CommDKP.Sync:SendData("CommDKPBidShare", Bids_Submitted)
            end
            CommDKP:BidScrollFrame_Update()
            response = L["BIDCANCELLED"]
            flagCanceled = true
            --CommDKP:SendChat(response, "WHISPER", nil, name)
            --return;
          end
        end
        if not flagCanceled then
          response = L["NOTSUBMITTEDBID"]
        end
      elseif cmd == "cancel" and core.DB.modes.mode == "Roll Based Bidding" then
        response = L["CANTCANCELROLL"]
      end
      dkp = tonumber(CommDKP:GetPlayerDKP(name))
      if not dkp then    -- exits function if player is not on the DKP list
        CommDKP:SendChat(L["INVALIDPLAYER"], "WHISPER", nil, name)
        return
      end

      if (tonumber(cmd) and (core.BiddingWindow.maxBid == nil or tonumber(cmd) <= core.BiddingWindow.maxBid:GetNumber() or core.BiddingWindow.maxBid:GetNumber() == 0)) or ((mode == "Static Item Values" or (mode == "Zero Sum" and core.DB.modes.ZeroSumBidType == "Static")) and not cmd) then
        if dkp then
          if (cmd and cmd <= dkp) or (core.DB.modes.SubZeroBidding == true and dkp >= 0) or (core.DB.modes.SubZeroBidding == true and core.DB.modes.AllowNegativeBidders == true) or (mode == "Static Item Values" and dkp > 0 and (dkp > core.BiddingWindow.cost:GetNumber() or core.DB.modes.SubZeroBidding == true or core.DB.modes.costvalue == "Percent")) or ((mode == "Zero Sum" and core.DB.modes.ZeroSumBidType == "Static") and not cmd) then
            if (cmd and core.BiddingWindow.minBid and tonumber(core.BiddingWindow.minBid:GetNumber()) <= cmd) or mode == "Static Item Values" or (mode == "Zero Sum" and core.DB.modes.ZeroSumBidType == "Static") or (mode == "Zero Sum" and core.DB.modes.ZeroSumBidType == "Minimum Bid" and cmd >= core.BiddingWindow.minBid:GetNumber()) then
              for i=1, #Bids_Submitted do           -- checks if a bid was submitted, removes last bid if it was
                if (not (mode == "Zero Sum" and core.DB.modes.ZeroSumBidType == "Static")) and Bids_Submitted[i] and CommDKP:SamePlayer(Bids_Submitted[i].player, name) and Bids_Submitted[i].bid < cmd then
                  table.remove(Bids_Submitted, i)
                elseif (not (mode == "Zero Sum" and core.DB.modes.ZeroSumBidType == "Static")) and Bids_Submitted[i] and CommDKP:SamePlayer(Bids_Submitted[i].player, name) and Bids_Submitted[i].bid >= cmd then
                  CommDKP:SendChat(L["BIDEQUALORLESS"], "WHISPER", nil, name)
                  return
                end
              end
              if mode == "Minimum Bid Values" or (mode == "Zero Sum" and core.DB.modes.ZeroSumBidType == "Minimum Bid") then
                if core.DB.modes.AnnounceBid and ((Bids_Submitted[1] and Bids_Submitted[1].bid < cmd) or not Bids_Submitted[1]) then
                  local msgTarget = "RAID";
                  if core.DB.modes.AnnounceRaidWarning then
                    msgTarget = "RAID_WARNING";
                  end

                  if not core.DB.modes.AnnounceBidName then
                    CommDKP:SendChat(L["NEWHIGHBID"].." "..cmd.." DKP", msgTarget)
                  else
                    CommDKP:SendChat(L["NEWHIGHBIDDER"].." "..name.." ("..cmd.." DKP)", msgTarget)
                  end
                end
                if core.DB.modes.DeclineLowerBids and Bids_Submitted[1] and cmd <= Bids_Submitted[1].bid then   -- declines bids lower than highest bid
                  response = "Bid Declined! Current highest bid is "..Bids_Submitted[1].bid;
                else
                  table.insert(Bids_Submitted, {player=name, bid=cmd})
                  response = L["YOURBIDOF"].." "..cmd.." "..L["DKPWASACCEPTED"].."."
                end
                if core.DB.modes.BroadcastBids then
                  CommDKP.Sync:SendData("CommDKPBidShare", Bids_Submitted)
                end
                if Timer ~= 0 and Timer > (core.BiddingWindow.bidTimer:GetText() - 10) and core.DB.modes.AntiSnipe > 0 then
                  seconds = core.BiddingWindow.bidTimer:GetText().."{"..core.DB.modes.AntiSnipe
                  if core.BiddingWindow.maxBid:GetNumber() ~= 0 then
                    CommDKP:BroadcastBidTimer(seconds, core.BiddingWindow.item:GetText().." Min Bid: "..core.BiddingWindow.minBid:GetText().." Max Bid: "..core.BiddingWindow.maxBid:GetText(), core.BiddingWindow.itemIcon:GetTexture());
                  else
                    CommDKP:BroadcastBidTimer(seconds, core.BiddingWindow.item:GetText().." Min Bid: "..core.BiddingWindow.minBid:GetText(), core.BiddingWindow.itemIcon:GetTexture());
                  end
                end
              elseif mode == "Static Item Values" or (mode == "Zero Sum" and core.DB.modes.ZeroSumBidType == "Static") then
                if core.DB.modes.AnnounceBid and ((Bids_Submitted[1] and Bids_Submitted[1].dkp < dkp) or not Bids_Submitted[1]) then
                  local msgTarget = "RAID";
                  if core.DB.modes.AnnounceRaidWarning then
                    msgTarget = "RAID_WARNING";
                  end

                  if not core.DB.modes.AnnounceBidName then
                    CommDKP:SendChat(L["NEWHIGHBID"].." "..dkp.." DKP", msgTarget)
                  else
                    CommDKP:SendChat(L["NEWHIGHBIDDER"].." "..name.." ("..dkp.." DKP)", msgTarget)
                  end
                end
                table.insert(Bids_Submitted, {player=name, dkp=dkp})
                if core.DB.modes.BroadcastBids then
                  CommDKP.Sync:SendData("CommDKPBidShare", Bids_Submitted)
                end
                response = L["BIDWASACCEPTED"]

                if Timer ~= 0 and Timer > (core.BiddingWindow.bidTimer:GetText() - 10) and core.DB.modes.AntiSnipe > 0 then
                  seconds = core.BiddingWindow.bidTimer:GetText().."{"..core.DB.modes.AntiSnipe
                  CommDKP:BroadcastBidTimer(seconds, core.BiddingWindow.item:GetText().." Extended", core.BiddingWindow.itemIcon:GetTexture());
                end
              end
              CommDKP:BidScrollFrame_Update()
            else
              response = L["BIDDENIEDMINBID"].." "..core.BiddingWindow.minBid:GetNumber().."!"
            end
          elseif core.DB.modes.SubZeroBidding == true and dkp < 0 then
            response = L["BIDDENIEDNEGATIVE"].." ("..dkp.." "..L["DKP"]..")."
          else
            response = L["BIDDENIEDONLYHAVE"].." "..dkp.." "..L["DKP"]
          end
        end
      elseif not cmd and (mode == "Minimum Bid Values" or (mode == "Zero Sum" and core.DB.modes.ZeroSumBidType == "Minimum Bid")) then
        response = L["BIDDENIEDNOVALUE"]
      elseif cmd ~= "cancel" and (tonumber(cmd) and tonumber(cmd) > core.BiddingWindow.maxBid:GetNumber()) then
        response = L["BIDDENIEDEXCEEDMAX"].." "..core.BiddingWindow.maxBid:GetNumber().." "..L["DKP"].."."
      else
        if cmd ~= "cancel" then
          response = L["BIDDENIEDINVALID"]
        end
      end
      CommDKP:SendChat(response, "WHISPER", nil, name)
    else
      CommDKP:SendChat(L["NOBIDINPROGRESS"], "WHISPER", nil, name)
    end
  elseif string.find(text, "!dkp") == 1 and core.IsOfficer == true then
    cmd = tostring(BidCmd(text))

    if cmd and cmd:gsub("%d+", "") == "" then
      return CommDKP_CHAT_MSG_WHISPER("!bid "..cmd, name)
    elseif cmd and strtrim(cmd) ~= "nil" and strtrim(cmd) ~= "" then    -- allows command if it has content
      cmd = strtrim(cmd)                                  -- AD-15.4(b): keep the inner First/Last space
      cmd = CommDKP:ResolveRosterName(cmd) or cmd
      CommDKP:WhisperAvailableDKP(name, cmd);
      return;
    else
      CommDKP:WhisperAvailableDKP(name);
      return;
    end

    CommDKP:SendChat(response, "WHISPER", nil, name)
  end


end

function CommDKP:WhisperAvailableDKP(name, cmd)
  local cmd = cmd or name;
  
  local teams = CommDKP:GetGuildTeamList(true);
  local response = "";
  local playerFound = false;
  local currentTeam = CommDKP:GetCurrentTeamIndex();

  for k, v in pairs(teams) do
    local teamIndex = tostring(v.index);
    local team = v
    local minimum;
    local maximum;
    local range = "";
    local perc = "";

    local search = CommDKP:Table_Search(CommDKP:GetTable(CommDKP_DKPTable, true, teamIndex), cmd, "player")

    if search and not playerFound then
      -- CommunityDKP: Kyliee
      local playerResponse = "CommunityDKP: "..CommDKP:GetTable(CommDKP_DKPTable, true, teamIndex)[search[1][1]].player;
      CommDKP:SendChat(playerResponse, "WHISPER", nil, name)
      playerFound = true;
    end

    if core.DB.modes.mode == "Roll Based Bidding" and search then
      if core.DB.modes.rolls.UsePerc then
        if core.DB.modes.rolls.min == 0 then
          minimum = 1;
        else
          minimum = CommDKP:GetTable(CommDKP_DKPTable, true, teamIndex)[search[1][1]].dkp * (core.DB.modes.rolls.min / 100);
        end
        perc = " ("..core.DB.modes.rolls.min.."% - "..core.DB.modes.rolls.max.."%)";
        maximum = CommDKP:GetTable(CommDKP_DKPTable, true, teamIndex)[search[1][1]].dkp * (core.DB.modes.rolls.max / 100) + core.DB.modes.rolls.AddToMax;
      elseif not core.DB.modes.rolls.UsePerc then
        minimum = core.DB.modes.rolls.min;

        if core.DB.modes.rolls.max == 0 then
          maximum = CommDKP:GetTable(CommDKP_DKPTable, true, teamIndex)[search[1][1]].dkp + core.DB.modes.rolls.AddToMax;
        else
          maximum = core.DB.modes.rolls.max + core.DB.modes.rolls.AddToMax;
        end
        if maximum < 0 then maximum = 0 end
        if minimum < 0 then minimum = 0 end
      end

      range = range.." "..L["USE"].." /random "..CommDKP_round(minimum, 0).."-"..CommDKP_round(maximum, 0).." "..L["TOBID"].." "..perc..".";
    end

    if search and playerFound then
      -- [Laughing Jester Tavern] 213 DKP Available
      -- [The Red Hand] 123 DKP Available
      response = "["..team.name.."] "..CommDKP:GetTable(CommDKP_DKPTable, true, teamIndex)[search[1][1]].dkp.." "..L["DKPAVAILABLE"];
      CommDKP:SendChat(response, "WHISPER", nil, name)
      if teamIndex == currentTeam then
        if name == cmd then
          CommDKP:SendChat(range, "WHISPER", nil, name)
        end
      end
    end
  end
  if not playerFound then
    response = "CommunityDKP: "..L["PLAYERNOTFOUND"]
    CommDKP:SendChat(response, "WHISPER", nil, name)
  end
  return;
end

function CommDKP:GetItemPrice(itemLink)
  if CommDKPApi.pricelist == nil then
    return nil
  end

  return CommDKPApi.pricelist:GetItemPrice(itemLink)
end

function CommDKP:GetItemLocBid(from, itemLink)
  local _,_,_,_,_,_,_,_,loc = C_Item.GetItemInfo(itemLink);

  if loc == "INVTYPE_HEAD" then
    return from.Head
  elseif loc == "INVTYPE_NECK" then
    return from.Neck
  elseif loc == "INVTYPE_SHOULDER" then
    return from.Shoulders
  elseif loc == "INVTYPE_CLOAK" then
    return from.Cloak
  elseif loc == "INVTYPE_CHEST" or loc == "INVTYPE_ROBE" then
    return from.Chest
  elseif loc == "INVTYPE_WRIST" then
    return from.Bracers
  elseif loc == "INVTYPE_HAND" then
    return from.Hands
  elseif loc == "INVTYPE_WAIST" then
    return from.Belt
  elseif loc == "INVTYPE_LEGS" then
    return from.Legs
  elseif loc == "INVTYPE_FEET" then
    return from.Boots
  elseif loc == "INVTYPE_FINGER" then
    return from.Ring
  elseif loc == "INVTYPE_TRINKET" then
    return from.Trinket
  elseif loc == "INVTYPE_WEAPON" or loc == "INVTYPE_WEAPONMAINHAND" or loc == "INVTYPE_WEAPONOFFHAND" then
    return from.OneHanded
  elseif loc == "INVTYPE_2HWEAPON" then
    return from.TwoHanded
  elseif loc == "INVTYPE_HOLDABLE" or loc == "INVTYPE_SHIELD" then
    return from.OffHand
  elseif loc == "INVTYPE_RANGED" or loc == "INVTYPE_THROWN" or loc == "INVTYPE_RANGEDRIGHT" or loc == "INVTYPE_RELIC" then
    return from.Range
  else
    return from.Other
  end
end

function CommDKP:GetMinBid(itemLink)
  local itemPrice = CommDKP:GetItemPrice(itemLink);
  if itemPrice then
    return itemPrice.minBid
  end

  return CommDKP:GetItemLocBid(core.DB.MinBidBySlot, itemLink)
end

function CommDKP:GetMaxBid(itemLink)
  local itemPrice = CommDKP:GetItemPrice(itemLink);
  if itemPrice then
    return itemPrice.maxBid
  end

  return CommDKP:GetItemLocBid(core.DB.MaxBidBySlot, itemLink)
end

function CommDKP:ToggleBidWindow(loot, lootIcon, itemName)
  local minBid, maxBid, itemID;

  mode = core.DB.modes.mode;

  if core.IsOfficer then
    
    if not core.BiddingWindow then
      core.BiddingWindow = CommDKP:CreateBidWindow();
      ResetBiddingBoss()                         -- AD-19.2 (012b): creation seeds the Boss dropdown (BR-12.10.2)
    end

    if core.DB.bidpos then
       core.BiddingWindow:ClearAllPoints()
      local a = core.DB.bidpos
      core.BiddingWindow:SetPoint(a.point, a.relativeTo, a.relativePoint, a.x, a.y)
    end

    core.BiddingWindow:SetShown(true)
    core.BiddingWindow:SetFrameLevel(10)

    if core.DB.modes.mode == "Zero Sum" then
      core.ZeroSumBank = core.ZeroSumBank or CommDKP:ZeroSumBank_Create()
      if not core.ZeroSumBank.userMoved then     -- UX §10.5: dock beside the Bidding window
        core.ZeroSumBank:ClearAllPoints()
        core.ZeroSumBank:SetPoint("TOPLEFT", core.BiddingWindow, "TOPRIGHT", 4, 0)
      end
      core.ZeroSumBank:SetShown(true)            -- OnShow -> group focus: Bidding + ZeroSum both FULLSCREEN

      CommDKP:ZeroSumBank_Update();
    end

    if core.ModesWindow then core.ModesWindow:SetFrameLevel(6) end
    if CommDKP.UIConfig then CommDKP.UIConfig:SetFrameLevel(2) end
    if CommDKP.FocusWindow then CommDKP:FocusWindow(core.BiddingWindow) end   -- UX §9.1.4: floaters -> MEDIUM

    if loot then
      local _, _, _, _, key = CommDKP:ParseItemLink(loot); itemID = key   -- AD-12.3: string MinBids key
       Bids_Submitted = {}
      if core.DB.modes.BroadcastBids then
        CommDKP.Sync:SendData("CommDKPBidShare", Bids_Submitted)
      end

      CurrItemForBid = loot;
      CurrItemIcon = lootIcon
      CurZone = GetRealZoneText()

      
      if mode == "Minimum Bid Values" or (mode == "Zero Sum" and core.DB.modes.ZeroSumBidType == "Minimum Bid") then
        
        -- Max bid values
        local search_max = CommDKP:Table_Search(CommDKP:GetTable(CommDKP_MaxBids, true), itemName)
        if search_max then
          maxBid = CommDKP:GetTable(CommDKP_MaxBids, true)[search_max[1][1]].maxbid
        else
          maxBid = CommDKP:GetMaxBid(CurrItemForBid)
        end
        
        -- search min bid value(item cost)
        local search_min = CommDKP:GetTable(CommDKP_MinBids, true)[itemID];
        if search_min then
          minBid = CommDKP:GetTable(CommDKP_MinBids, true)[itemID].minbid
        else
          minBid = CommDKP:GetMinBid(CurrItemForBid);
        end
      elseif mode == "Static Item Values" or mode == "Roll Based Bidding" or (mode == "Zero Sum" and core.DB.modes.ZeroSumBidType == "Static") then
        
        -- search min bid value(item cost)
        local search_min = CommDKP:GetTable(CommDKP_MinBids, true)[itemID];
        if search_min then
          minBid = CommDKP:GetTable(CommDKP_MinBids, true)[itemID].minbid
        else
          minBid = CommDKP:GetMinBid(CurrItemForBid);
        end
      else
        minBid = CommDKP:GetMinBid(CurrItemForBid);
        maxBid = CommDKP:GetMaxBid(CurrItemForBid);
      end
      
      if mode == "Minimum Bid Values" or (mode == "Zero Sum" and core.DB.modes.ZeroSumBidType == "Minimum Bid") then
        core.BiddingWindow.CustomMinBid:Show();
        core.BiddingWindow.CustomMinBid:SetChecked(core.DB.defaults.CustomMinBid)
        core.BiddingWindow.CustomMinBid:SetScript("OnClick", function(self)
          if self:GetChecked() == true then
            core.BiddingWindow.minBid:SetText(CommDKP_round(minBid, core.DB.modes.rounding))
          else
            core.BiddingWindow.minBid:SetText(CommDKP:GetMinBid(CurrItemForBid))
          end
          core.DB.defaults.CustomMinBid = self:GetChecked();
        end)

        core.BiddingWindow.CustomMaxBid:Show();
        core.BiddingWindow.CustomMaxBid:SetChecked(core.DB.defaults.CustomMaxBid)
        core.BiddingWindow.CustomMaxBid:SetScript("OnClick", function(self)
          if self:GetChecked() == true then
            core.BiddingWindow.maxBid:SetText(CommDKP_round(maxBid, core.DB.modes.rounding))
          else
            local behavior = core.DB.modes.MaxBehavior
            local dkpValue = 0;

            if behavior == "Max DKP" then
                dkpValue = "MAX";
            else
              dkpValue = CommDKP_round(CommDKP:GetMaxBid(CurrItemForBid), core.DB.modes.rounding);
            end
            core.BiddingWindow.maxBid:SetText(dkpValue);
          end
          core.DB.defaults.CustomMaxBid = self:GetChecked();
        end)
      elseif mode == "Static Item Values" or mode == "Roll Based Bidding" or (mode == "Zero Sum" and core.DB.modes.ZeroSumBidType == "Static") then
        core.BiddingWindow.CustomMinBid:Show();
        core.BiddingWindow.CustomMinBid:SetChecked(core.DB.defaults.CustomMinBid)
        core.BiddingWindow.CustomMinBid:SetScript("OnClick", function(self)
          if self:GetChecked() == true then
            core.BiddingWindow.cost:SetText(CommDKP_round(minBid, core.DB.modes.rounding))
          else
            core.BiddingWindow.cost:SetText(CommDKP:GetMinBid(CurrItemForBid))
          end
          core.DB.defaults.CustomMinBid = not core.DB.defaults.CustomMinBid;
        end)
      end

      if mode == "Minimum Bid Values" or (mode == "Zero Sum" and core.DB.modes.ZeroSumBidType == "Minimum Bid") then
        core.BiddingWindow.minBid:SetText(CommDKP_round(minBid, core.DB.modes.rounding))

        local behavior = core.DB.modes.MaxBehavior
        local dkpValue = 0;

        if not core.DB.defaults.CustomMaxBid then
          if behavior == "Max DKP" then
              dkpValue = "MAX";
          else
            dkpValue = CommDKP_round(maxBid, core.DB.modes.rounding);
          end
          core.BiddingWindow.maxBid:SetText(dkpValue);
        else
          core.BiddingWindow.maxBid:SetText(CommDKP_round(maxBid, core.DB.modes.rounding))
        end
      end

      core.BiddingWindow.cost:SetText(CommDKP_round(minBid, core.DB.modes.rounding))
      core.BiddingWindow.itemName:SetText(itemName)
      core.BiddingWindow.bidTimer:SetText(core.DB.DKPBonus.BidTimer)
      ResetBiddingBoss()
      UpdateBidWindow()
      core.BiddingWindow.ItemTooltipButton:SetSize(core.BiddingWindow.itemIcon:GetWidth() + core.BiddingWindow.item:GetStringWidth() + 10, core.BiddingWindow.item:GetHeight());
      core.BiddingWindow.ItemTooltipButton:SetScript("OnEnter", function(self)
        CommDKP:ShowButtonGlow(core.BiddingWindow.ItemIconButton)
        GameTooltip:SetOwner(self:GetParent(), "ANCHOR_BOTTOMRIGHT", 0, 500);
        GameTooltip:SetHyperlink(CurrItemForBid)
      end)
      core.BiddingWindow.ItemTooltipButton:SetScript("OnLeave", function(self)
        CommDKP:HideButtonGlow(core.BiddingWindow.ItemIconButton)
        GameTooltip:Hide()
      end)
    else
      UpdateBidWindow()
    end

    CommDKP:BidScrollFrame_Update()
  else
    CommDKP:Print(L["NOPERMISSION"])
  end
end

local function StartBidding()
  local perc;
  mode = core.DB.modes.mode;
  core.BidInProgress = true;

  if mode == "Minimum Bid Values" or (mode == "Zero Sum" and core.DB.modes.ZeroSumBidType == "Minimum Bid") then
    core.BiddingWindow.cost:SetNumber(CommDKP_round(core.BiddingWindow.minBid:GetNumber(), core.DB.modes.rounding))
    if core.BiddingWindow.maxBid:GetNumber() ~= 0 then
      CommDKP:BroadcastBidTimer(core.BiddingWindow.bidTimer:GetText(), core.BiddingWindow.item:GetText().." Min Bid: "..core.BiddingWindow.minBid:GetText().." Max Bid: "..core.BiddingWindow.maxBid:GetText(), CurrItemIcon)
    else
      CommDKP:BroadcastBidTimer(core.BiddingWindow.bidTimer:GetText(), core.BiddingWindow.item:GetText().." Min Bid: "..core.BiddingWindow.minBid:GetText(), CurrItemIcon)
    end
    CommDKP.Sync:SendData("CommDKPCommand", "BidInfo#"..core.BiddingWindow.item:GetText().."#"..core.BiddingWindow.minBid:GetText().."#"..CurrItemIcon.."#"..core.BiddingWindow.maxBid:GetText())
    
    CommDKP:CurrItem_Set(core.BiddingWindow.item:GetText(), core.BiddingWindow.minBid:GetText(), CurrItemIcon, core.BiddingWindow.maxBid:GetText())

    if core.DB.defaults.AutoOpenBid then  -- toggles bid window if option is set to
      CommDKP:BidInterface_Toggle()
    end
    local _, _, _, _, itemID = CommDKP:ParseItemLink(CurrItemForBid)   -- AD-13.4: string itemKey, cold-cache safe

    local search_min = CommDKP:GetTable(CommDKP_MinBids, true)[itemID];
    local val_min = CommDKP:GetMinBid(CurrItemForBid);
    local search_max = CommDKP:Table_Search(CommDKP:GetTable(CommDKP_MaxBids, true), core.BiddingWindow.itemName:GetText(), "item")
    local val_max = CommDKP:GetMaxBid(CurrItemForBid);

    -- Min
    if not search_min and core.BiddingWindow.minBid:GetNumber() ~= tonumber(val_min) then
      CommDKP:GetTable(CommDKP_MinBids, true)[itemID] = {item=core.BiddingWindow.itemName:GetText(), minbid=core.BiddingWindow.minBid:GetNumber(), link=CurrItemForBid};
      core.BiddingWindow.CustomMinBid:SetShown(true);
      core.BiddingWindow.CustomMinBid:SetChecked(core.DB.defaults.CustomMinBid);
    elseif search_min and core.BiddingWindow.minBid:GetNumber() ~= tonumber(val_min) and core.BiddingWindow.CustomMinBid:GetChecked() == true then
      if CommDKP:GetTable(CommDKP_MinBids, true)[itemID].minbid ~= core.BiddingWindow.minBid:GetNumber() then
        CommDKP:GetTable(CommDKP_MinBids, true)[itemID].minbid = core.BiddingWindow.minBid:GetNumber();
        core.BiddingWindow.CustomMinBid:SetShown(true);
        core.BiddingWindow.CustomMinBid:SetChecked(core.DB.defaults.CustomMinBid);
      end
    end

    if search_min and core.BiddingWindow.CustomMinBid:GetChecked() == false then
      CommDKP:GetTable(CommDKP_MinBids, true)[itemID] = {}
      core.BiddingWindow.CustomMinBid:SetShown(false);
    end

    -- Max
    if not search_max and core.BiddingWindow.maxBid:GetNumber() ~= tonumber(val_max) then
      tinsert(CommDKP:GetTable(CommDKP_MaxBids, true), {item=core.BiddingWindow.itemName:GetText(), maxbid=core.BiddingWindow.maxBid:GetNumber()})
      core.BiddingWindow.CustomMaxBid:SetShown(true);
      core.BiddingWindow.CustomMaxBid:SetChecked(core.DB.defaults.CustomMaxBid);
    elseif search_max and core.BiddingWindow.maxBid:GetNumber() ~= tonumber(val_max) and core.BiddingWindow.CustomMaxBid:GetChecked() == true then
      if CommDKP:GetTable(CommDKP_MaxBids, true)[search_max[1][1]].maxbid ~= core.BiddingWindow.maxBid:GetNumber() then
        CommDKP:GetTable(CommDKP_MaxBids, true)[search_max[1][1]].maxbid = core.BiddingWindow.maxBid:GetNumber();
        core.BiddingWindow.CustomMaxBid:SetShown(true);
        core.BiddingWindow.CustomMaxBid:SetChecked(core.DB.defaults.CustomMaxBid);
      end
    end

    if search_max and core.BiddingWindow.CustomMaxBid:GetChecked() == false then
      table.remove(CommDKP:GetTable(CommDKP_MaxBids, true), search_max[1][1])
      core.BiddingWindow.CustomMaxBid:SetShown(false);
    end
  else
    if core.DB.modes.costvalue == "Percent" then perc = "%" else perc = " DKP" end;
    CommDKP:BroadcastBidTimer(core.BiddingWindow.bidTimer:GetText(), core.BiddingWindow.item:GetText().." Cost: "..core.BiddingWindow.cost:GetNumber()..perc, CurrItemIcon)
    CommDKP.Sync:SendData("CommDKPCommand", "BidInfo#"..core.BiddingWindow.item:GetText().."#"..core.BiddingWindow.cost:GetText()..perc.."#"..CurrItemIcon.."#0")
    CommDKP:BidInterface_Toggle()
    
    CommDKP:CurrItem_Set(core.BiddingWindow.item:GetText(), core.BiddingWindow.cost:GetText()..perc, CurrItemIcon, 0)
  end

  if mode == "Roll Based Bidding" then
    events:RegisterEvent("CHAT_MSG_SYSTEM")
    events:SetScript("OnEvent", Roll_OnEvent);
  end

  if CurrItemForBid then
    local channels = {};
    local channelText = "";

    if core.DB.modes.channels.raid then table.insert(channels, "/raid") end
    if core.DB.modes.channels.guild then table.insert(channels, "/guild") end
    if core.DB.modes.channels.whisper then table.insert(channels, "/whisper") end

    for i=1, #channels do
      if #channels == 1 then
        channelText = channels[i]
      else
        if i == 1 then
          channelText = channels[i];
        elseif i == #channels then
          channelText = channelText.." "..L["OR"].." "..channels[i]
        else
          channelText = channelText..", "..channels[i]
        end
      end
    end

    if mode == "Minimum Bid Values" or (mode == "Zero Sum" and core.DB.modes.ZeroSumBidType == "Minimum Bid") then
      if core.BiddingWindow.maxBid:GetNumber() ~= 0 then
        CommDKP:SendChat(L["TAKINGBIDSON"].." "..core.BiddingWindow.item:GetText().." ("..core.BiddingWindow.minBid:GetText().." "..L["DKPMINBID"].." "..core.BiddingWindow.maxBid:GetText().." "..L["DKPMAXBID"]..")", "RAID_WARNING")
      else
        CommDKP:SendChat(L["TAKINGBIDSON"].." "..core.BiddingWindow.item:GetText().." ("..core.BiddingWindow.minBid:GetText().." "..L["DKPMINBID"]..")", "RAID_WARNING")
      end
      CommDKP:SendChat(L["TOBIDUSE"].." "..channelText.." "..L["TOSEND"].." !bid <"..L["VALUE"].."> (ex: !bid "..core.BiddingWindow.minBid:GetText().."). "..L["OR"].." !bid cancel "..L["TOWITHDRAWBID"], "RAID_WARNING")
    elseif mode == "Static Item Values" or (mode == "Zero Sum" and core.DB.modes.ZeroSumBidType == "Static") then
      CommDKP:SendChat(L["TAKINGBIDSON"].." "..core.BiddingWindow.item:GetText().." ("..core.BiddingWindow.cost:GetText()..perc..")", "RAID_WARNING")
      CommDKP:SendChat(L["TOBIDUSE"].." "..channelText.." "..L["TOSEND"].." !bid. "..L["OR"].." !bid cancel "..L["TOWITHDRAWBID"], "RAID_WARNING")
    elseif mode == "Roll Based Bidding" then
      CommDKP:SendChat(L["ROLLFOR"].." "..core.BiddingWindow.item:GetText().." ("..core.BiddingWindow.cost:GetText()..perc..")", "RAID_WARNING")
      CommDKP:SendChat(L["TOBIDROLLRANGE"].." "..channelText.." "..L["WITH"].." !dkp", "RAID_WARNING")
    end
  end
end

-- CDKP-006 (AD-5.3): lets Award.lua / LootPriceTab.lua reset the auction toggle after an award or
-- disenchant. Resets this file's local timerToggle (they used to write an unrelated global) and never
-- rebinds OnClick (their old closures called ToggleTimerBtn, which is nil outside this file).
function CommDKP:ResetBidToggle()
  timerToggle = 0
  local btn = _G["CommDKPBiddingStartBiddingButton"]
  if btn then btn:SetText(L["STARTBIDDING"]) end
end

local function ToggleTimerBtn(self)
  mode = core.DB.modes.mode;

  -- CDKP-003 (AD-1/BR-6): opening or closing an auction is refused, never deferred, during lockdown.
  if CommDKP:IsMessagingRestricted() then
    CommDKP:Print(L["BIDDINGLOCKED"])
    return false
  end

  if timerToggle == 0 then
    --if not IsInRaid() then CommDKP:Print("You are not in a raid.") return false end
    if (mode == "Minimum Bid Values" or (mode == "Zero Sum" and core.DB.modes.ZeroSumBidType == "Minimum Bid")) and (not core.BiddingWindow.item:GetText() or core.BiddingWindow.minBid:GetText() == "" or core.BiddingWindow.maxBid:GetText() == "") then CommDKP:Print(L["NOMINBIDORITEM"]) return false end
    if (mode == "Minimum Bid Values" or (mode == "Zero Sum" and core.DB.modes.ZeroSumBidType == "Minimum Bid")) and ((core.BiddingWindow.maxBid:GetNumber() ~= 0) and (core.BiddingWindow.minBid:GetNumber() > core.BiddingWindow.maxBid:GetNumber())) then CommDKP:Print(L["MAXGTMIN"]) return false end
    if (mode == "Static Item Values" or (mode == "Zero Sum" and core.DB.modes.ZeroSumBidType == "Static")) and (not core.BiddingWindow.item:GetText() or core.BiddingWindow.cost:GetText() == "") then CommDKP:Print(L["NOITEMORITEMCOST"]) return false end
    if mode == "Roll Based Bidding" and (not core.BiddingWindow.item:GetText() or core.BiddingWindow.cost:GetText() == "") then CommDKP:Print(L["NOITEMORITEMCOST"]) return false end

    timerToggle = 1;
    self:SetText(L["ENDBIDDING"])
    StartBidding()
    core.BidAuctioneer = true;
  else
    timerToggle = 0;
    core.BidInProgress = false;
    core.BidAuctioneer = false;
    self:SetText(L["STARTBIDDING"])
    CommDKP:SendChat(L["BIDDINGCLOSED"], "RAID_WARNING")
    events:UnregisterEvent("CHAT_MSG_SYSTEM")
    CommDKP:BroadcastStopBidTimer()
  end
end

function CommDKP:ClearBidWindow()
  CurrItemForBid = "";
  CurrItemIcon = "";
  Bids_Submitted = {}
  SelectedBidder = {}
  if core.DB.modes.BroadcastBids then
    CommDKP.Sync:SendData("CommDKPBidShare", Bids_Submitted)
  end
  core.BiddingWindow.cost:SetText("")
  core.BiddingWindow.CustomMinBid:Hide();

  core.BiddingWindow.ItemTooltipButton:SetSize(0,0)
  CommDKP:BidScrollFrame_Update()
  UpdateBidWindow()
  core.BidInProgress = false;
  ResetBiddingBoss()                           -- BR-12.10.2: Clear Window resets to the last-killed boss
  _G["CommDKPBiddingStartBiddingButton"]:SetText(L["STARTBIDDING"])
  _G["CommDKPBiddingStartBiddingButton"]:SetScript("OnClick", function (self)
    local pass, err = pcall(ToggleTimerBtn, self)

    if core.BiddingWindow.bidTimer then core.BiddingWindow.bidTimer:ClearFocus(); end
    if core.BiddingWindow.minBid then core.BiddingWindow.minBid:ClearFocus(); end

    if core.BiddingWindow.minBid then core.BiddingWindow.minBid:ClearFocus(); end
    core.BiddingWindow.bidTimer:ClearFocus()
    core.BiddingWindow.cost:ClearFocus()
    if not pass then
      core.BiddingWindow:SetShown(false)
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
      CommDKP:ShowPopupOverFloaters("SUGGEST_RELOAD", core.BiddingWindow)
    end
  end)
  timerToggle = 0;
  if mode == "Minimum Bid Values" or (mode == "Zero Sum" and core.DB.modes.ZeroSumBidType == "Minimum Bid") then
    core.BiddingWindow.minBid:SetText("")
    core.BiddingWindow.CustomMaxBid:Hide();
    core.BiddingWindow.maxBid:ClearFocus();
    core.BiddingWindow.maxBid:SetText("")
  end
  for i=1, numrows do
    W.SetRowSelected(core.BiddingWindow.bidTable.Rows[i], false)
  end
end

function CommDKP:BroadcastBidTimer(seconds, title, itemIcon)       -- broadcasts timer and starts it natively
  local title = title;
  CommDKP.Sync:SendData("CommDKPCommand", "StartBidTimer#"..seconds.."#"..title.."#"..itemIcon)
  CommDKP:StartBidTimer(seconds, title, itemIcon)

  if strfind(seconds, "{") then
    CommDKP:Print("Bid timer extended by "..tonumber(strsub(seconds, strfind(seconds, "{")+1)).." seconds.")
  end
end

function CommDKP:BroadcastStopBidTimer()
  CommDKP.BidTimer:SetScript("OnUpdate", nil)
  CommDKP.BidTimer:Hide()
  CommDKP.Sync:SendData("CommDKPCommand", "StopBidTimer")
end

function CommDKP:StartBidTimer(seconds, title, itemIcon)
  local duration, timer, timerText, modulo, timerMinute, expiring;
  local title = title;
  local alpha = 1;
  local messageSent = { false, false, false, false, false, false }
  local audioPlayed = false;
  local extend = false;

  if tonumber(seconds) then
    timer = 0
    duration = tonumber(seconds);
  else
    if seconds ~= "seconds" then
      timer = Timer - tonumber(strsub(seconds, strfind(seconds, "{")+1))
      duration = tonumber(strsub(seconds, 1, strfind(seconds, "{")-1))          --strsub("30{10", strfind("30{10", "{")+1)
      extend = true;
    end
  end
  
  CommDKP.BidTimer = CommDKP.BidTimer or CommDKP:CreateTimer();    -- recycles bid timer frame so multiple instances aren't created
  if not extend then CommDKP.BidTimer:SetShown(not CommDKP.BidTimer:IsShown()); end          -- shows if not shown
  if core.BidInterface and core.BidInterface:IsShown() == false then CommDKP.BidTimer.OpenBid:Show() end
  CommDKP.BidTimer:SetMinMaxValues(0, duration or 20)
  CommDKP.BidTimer.timerTitle:SetText(title)
  CommDKP.BidTimer.itemIcon:SetTexture(itemIcon)
    CommDKP.BidTimer:SetAlpha(1);
    CommDKP.BidTimer:SetScale(core.DB.defaults.BidTimerSize);
  CommDKP.BidTimer:SetScript("OnMouseDown", function(self, button)
      if button == "RightButton" then
        CommDKP.BidTimer:SetAlpha(0);
        CommDKP.BidTimer:SetScale(0.1);
      end
    end)
  if title ~= nil then
    PlaySound(8959);
  end

  if core.DB.timerpos then
    local a = core.DB["timerpos"]                    -- retrieves timer's saved position from SavedVariables
    CommDKP.BidTimer:SetPoint(a.point, a.relativeTo, a.relativePoint, a.x, a.y)
  else
    CommDKP.BidTimer:SetPoint("CENTER")                      -- sets to center if no position has been saved
  end

  CommDKP.BidTimer:SetScript("OnUpdate", function(self, elapsed)
    timer = timer + elapsed
    Timer = timer;       -- stores external copy of timer for extending
    timerText = CommDKP_round(duration - timer, 1)
    if tonumber(timerText) > 60 then
      timerMinute = math.floor(tonumber(timerText) / 60, 0);
      modulo = tonumber(timerText) % 60;
      if tonumber(modulo) < 10 then modulo = "0"..modulo end
      CommDKP.BidTimer.timertext:SetText(timerMinute..":"..modulo)
    else
      CommDKP.BidTimer.timertext:SetText(timerText)
    end
    if duration >= 120 then
      expiring = 30;
    else
      expiring = 10;
    end
    if tonumber(timerText) < expiring then
      CommDKP.BidTimer:SetStatusBarColor(0.8, 0.1, 0, alpha)
      if alpha > 0 then
        alpha = alpha - 0.005
      elseif alpha <= 0 then
        alpha = 1
      end
    else
      CommDKP.BidTimer:SetStatusBarColor(0, 0.8, 0)
    end

    if tonumber(timerText) == 10 and messageSent[1] == false then
      if audioPlayed == false then
            PlaySound(23639);
          end
      CommDKP:Print(L["TENSECONDSTOBID"])
      messageSent[1] = true;
    end
    if tonumber(timerText) == 5 and messageSent[2] == false then
      CommDKP:Print("5")
      messageSent[2] = true;
    end
    if tonumber(timerText) == 4 and messageSent[3] == false then
      CommDKP:Print("4")
      messageSent[3] = true;
    end
    if tonumber(timerText) == 3 and messageSent[4] == false then
      CommDKP:Print("3")
      messageSent[4] = true;
    end
    if tonumber(timerText) == 2 and messageSent[5] == false then
      CommDKP:Print("2")
      messageSent[5] = true;
    end
    if tonumber(timerText) == 1 and messageSent[6] == false then
      CommDKP:Print("1")
      messageSent[6] = true;
    end
    self:SetValue(timer)
    if timer >= duration then
      if CurrItemForBid and core.BidInProgress then
        CommDKP:SendChat(L["BIDDINGCLOSED"], "RAID_WARNING")
        events:UnregisterEvent("CHAT_MSG_SYSTEM")
      end
      core.BidInProgress = false;
      if _G["CommDKPBiddingStartBiddingButton"] then
        _G["CommDKPBiddingStartBiddingButton"]:SetText(L["STARTBIDDING"])
        _G["CommDKPBiddingStartBiddingButton"]:SetScript("OnClick", function (self)
          local pass, err = pcall(ToggleTimerBtn, self)

          if core.BiddingWindow.minBid then core.BiddingWindow.minBid:ClearFocus(); end
          core.BiddingWindow.bidTimer:ClearFocus()
          core.BiddingWindow.cost:ClearFocus()
          if not pass then
            core.BiddingWindow:SetShown(false)
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
            CommDKP:ShowPopupOverFloaters("SUGGEST_RELOAD", core.BiddingWindow)
          end
        end)
        timerToggle = 0;
      end
      core.BiddingInProgress = false;
      CommDKP.BidTimer:SetScript("OnUpdate", nil)
      CommDKP.BidTimer:Hide();
      if core.BidInterface and core.BidInterface.LootTableButtons and #core.BidInterface.LootTableButtons > 0 then   -- AD-13.1
        for i=1, #core.BidInterface.LootTableButtons do
          CommDKP:HideButtonGlow(core.BidInterface.LootTableButtons[i])
        end
      end
      C_Timer.After(2, function()
        if core.BidInterface and core.BidInterface:IsShown() then
          core.BidInterface:Hide()
        end
      end)
    end
  end)
end

function CommDKP:CreateTimer()

  local f;

  f = CreateFrame("StatusBar", nil, UIParent, "BackdropTemplate")
 
  f:SetSize(300, 25)
  f:SetFrameStrata("DIALOG")
  f:SetFrameLevel(18)

  CommDKP:ApplyBackdrop(f, "StatusBg", "StatusBg")
  f:SetStatusBarTexture([[Interface\TargetingFrame\UI-TargetingFrame-BarFill]])
  f:SetMovable(true);
  f:EnableMouse(true);
  f:SetScale(core.DB.defaults.BidTimerSize)
  f:RegisterForDrag("LeftButton");
  f:SetScript("OnDragStart", f.StartMoving);
  f:SetScript("OnDragStop", function()
    f:StopMovingOrSizing();
    local point, _, relativePoint ,xOff,yOff = f:GetPoint(1)
    if not core.DB.timerpos then
      core.DB.timerpos = {}
    end
    core.DB.timerpos["point"] = point;
    core.DB.timerpos["relativePoint"] = relativePoint;
    core.DB.timerpos["x"] = xOff;
    core.DB.timerpos["y"] = yOff;
  end);

  f.border = CreateFrame("Frame", nil, f, "BackdropTemplate");
  
  f.border:SetPoint("CENTER", f, "CENTER");
  f.border:SetFrameStrata("DIALOG")
  f.border:SetFrameLevel(19)
  f.border:SetSize(300, 25);
  CommDKP:ApplyBackdrop(f.border, "Plaque", "Clear", "trimQuiet")   -- AD-16.3 (e) R3: edge only, bar stays visible
  f.timerTitle = W.CreateText(f, "bodyOutline", nil, "LEFT")
  f.timerTitle:SetWidth(270)
  f.timerTitle:SetHeight(25)
  f.timerTitle:SetTextColor(1, 1, 1, 1);
  f.timerTitle:SetPoint("LEFT", f, "LEFT", 3, 0);
  f.timerTitle:SetText(nil);

  f.timertext = W.CreateText(f, "bodyOutline", nil, "RIGHT")
  f.timertext:SetTextColor(1, 1, 1, 1);
  f.timertext:SetPoint("RIGHT", f, "RIGHT", -5, 0);
  f.timertext:SetText(nil);

  f.itemIcon = f:CreateTexture(nil, "OVERLAY", nil);   -- Title Bar Texture
  f.itemIcon:SetPoint("RIGHT", f, "LEFT", 0, 0);
  f.itemIcon:SetColorTexture(0, 0, 0, 1)
  f.itemIcon:SetSize(25, 25);

  f.OpenBid = CreateFrame("Button", nil, f, "CommunityDKPButtonTemplate")
  f.OpenBid:SetPoint("RIGHT", f.itemIcon, "LEFT", -5, 0);
  f.OpenBid:SetSize(40,25)
  f.OpenBid:SetText(L["BID"]);
  W.StyleButton(f.OpenBid)                               -- AD-16.1 (a): kit button only, no re-layout
  f.OpenBid:SetScript("OnClick", function()
    f.OpenBid:Hide()
    CommDKP:BidInterface_Toggle()
  end)
  f.OpenBid:Show()

  return f;
end

local function BidRow_OnClick(self)
  -- AD-13.3: never split the row label on " " (multi-word Forever names such as "Bank Robbers").
  local player = self.player or (Bids_Submitted[self.index] and Bids_Submitted[self.index].player)
  if not player then return end
  if SelectedBidder.player == player then
    for i=1, numrows do
      W.SetRowSelected(core.BiddingWindow.bidTable.Rows[i], false)
    end
    SelectedBidder = {}
  else
    for i=1, numrows do
      W.SetRowSelected(core.BiddingWindow.bidTable.Rows[i], false)
    end
      W.SetRowSelected(self, true)

      if core.DB.modes.costvalue == "Percent" then
        SelectedBidder = {player=player, dkp=tonumber(self.Strings[3]:GetText())}
      else
        SelectedBidder = {player=player, bid=tonumber(self.Strings[2]:GetText())}
      end
    end
end

local function RightClickMenu(self)
  local menu;

  menu = {
    { text = L["REMOVEENTRY"], notCheckable = true, func = function()
      if Bids_Submitted[self.index].bid then
        CommDKP:SendChat(L["YOURBIDOF"].." "..Bids_Submitted[self.index].bid.." "..L["DKP"].." "..L["MANUALLYDENIED"], "WHISPER", nil, Bids_Submitted[self.index].player)
      else
        CommDKP:SendChat(L["YOURBID"].." "..L["MANUALLYDENIED"], "WHISPER", nil, Bids_Submitted[self.index].player)
      end
      table.remove(Bids_Submitted, self.index)
      if core.DB.modes.BroadcastBids then
        CommDKP.Sync:SendData("CommDKPBidShare", Bids_Submitted)
      end
      SelectedBidder = {}
      for i=1, #core.BiddingWindow.bidTable.Rows do
        W.SetRowSelected(core.BiddingWindow.bidTable.Rows[i], false)
      end
      CommDKP:BidScrollFrame_Update()
    end },
  }
  LibDD:EasyMenu(menu, menuFrame, "cursor", 0 , 0, "MENU", 1);
end

local function BidWindowCreateRow(parent, id) -- Create 3 buttons for each row in the list
    local f = CreateFrame("Button", "$parentLine"..id, parent)
    f.Strings = {}
    f:SetSize(width, height)
    W.StyleRow(f, id)                    -- §12.2.10 stripe + hover; selection via W.SetRowSelected
    f:SetScript("OnClick", BidRow_OnClick)
    for i=1, 3 do
        f.Strings[i] = W.CreateText(f, "body", nil, i == 1 and "LEFT" or "CENTER")
        f.Strings[i]:SetTextColor(1, 1, 1, 1);
    end
    f.Strings[1].rowCounter = W.CreateText(f, "caption", nil, "LEFT")
  f.Strings[1].rowCounter:SetTextColor(MutedRGBA()) -- AD-22.8.3 (BR-084.4): textMuted, alpha 1 (was white @ 0.3)
  f.Strings[1].rowCounter:SetPoint("LEFT", f, "LEFT", 3, -1);

    f.Strings[1]:SetWidth((width/2)-10)
    -- AD-22.8.2 (CDKP-015d, BR-084.1/084.2): the Player cell is one line and never wraps. With its fixed width the
    -- engine end-truncates with "...", so the rank (last in the string) is shortened and the name stays whole.
    if f.Strings[1].SetWordWrap then f.Strings[1]:SetWordWrap(false) end
    if f.Strings[1].SetNonSpaceWrap then f.Strings[1]:SetNonSpaceWrap(false) end
    if f.Strings[1].SetMaxLines then f.Strings[1]:SetMaxLines(1) end
    f.Strings[2]:SetWidth(width/4)
    f.Strings[3]:SetWidth(width/4)
    f.Strings[1]:SetPoint("LEFT", f, "LEFT", 20, 0)
    f.Strings[2]:SetPoint("LEFT", f.Strings[1], "RIGHT", -9, 0)
    f.Strings[3]:SetPoint("RIGHT", 0, 0)

    f:SetScript("OnMouseDown", function(self, button)
      if button == "RightButton" then
        RightClickMenu(self)
      end
    end)

    -- AD-24.3.1 (CDKP-017, BR-17.1/17.2): the shared Roster history tooltip. self.player is read at hover time (BR-17.5),
    -- never captured here. W.StyleRow's KeepHooks re-attaches the §12.2.10 hover fill after these SetScripts (F7).
    f:SetScript("OnEnter", function(self)
      if self.player and CommDKP.ShowPlayerHistoryTooltip then
        CommDKP:ShowPlayerHistoryTooltip(self, self.player)
      end
    end)
    f:SetScript("OnLeave", function(self)
      if GameTooltip:GetOwner() == self then GameTooltip:Hide() end   -- only if this row owns it (handoff, F11)
    end)

    return f
end

local function SortBidTable()             -- sorts the Loot History Table by date
  mode = core.DB.modes.mode;
  table.sort(Bids_Submitted, function(a, b)
      if mode == "Minimum Bid Values" or (mode == "Zero Sum" and core.DB.modes.ZeroSumBidType == "Minimum Bid") then
        return a["bid"] > b["bid"]
      elseif mode == "Static Item Values" or (mode == "Zero Sum" and core.DB.modes.ZeroSumBidType == "Static") then
        return a["dkp"] > b["dkp"]
      elseif mode == "Roll Based Bidding" then
        return a["roll"] > b["roll"]
      end
    end)
end

function CommDKP:BidScrollFrame_Update()
  local numOptions = #Bids_Submitted;
  local index, row
    local offset = FauxScrollFrame_GetOffset(core.BiddingWindow.bidTable) or 0
    local rank;
    local showRows = #Bids_Submitted

    if #Bids_Submitted > numrows then
      showRows = numrows
    end

    SortBidTable()
    local muted = MutedHex() -- AD-22.8.3: read once per refresh (BR-084.3)
    -- AD-24.3.3 (BR-17.5): remember which bidder row (if any) owns an open tooltip BEFORE the rows are hidden/repainted.
    local tipRow
    if GameTooltip:IsShown() then
      local tipOwner = GameTooltip:GetOwner()
      for i=1, numrows do
        if tipOwner and core.BiddingWindow.bidTable.Rows[i] == tipOwner then tipRow = tipOwner; break end
      end
    end
    for i=1, numrows do
      row = core.BiddingWindow.bidTable.Rows[i]
      row:Hide()
      row.player = nil                       -- AD-24.3.2: a hidden row never keeps a stale bidder
    end
    for i=1, showRows do
        row = core.BiddingWindow.bidTable.Rows[i]
        index = offset + i
        local entry = Bids_Submitted[index]    -- AD-13.3: always index by scrolled position
        if entry then
            local dkpTable = CommDKP:GetTable(CommDKP_DKPTable, true)
            local dkp_total = CommDKP:Table_Search(dkpTable, entry.player)
            local c
            if dkp_total then
              c = CommDKP:GetCColors(dkpTable[dkp_total[1][1]].class)
            else       -- unprofiled bidder: grey
              c = { r = 0.67, g = 0.67, b = 0.67 }
            end
            local playerDKP = dkp_total and dkpTable[dkp_total[1][1]].dkp or 0
            rank = CommDKP:GetGuildRank(entry.player) or ""
            row:Show()
            row.index = index
            row.player = entry.player
            row.Strings[1]:SetText(entry.player.." "..muted.."("..rank..")|r")
            row.Strings[1]:SetTextColor(c.r, c.g, c.b, 1)
            row.Strings[1].rowCounter:SetText(index)
            if mode == "Minimum Bid Values" or (mode == "Zero Sum" and core.DB.modes.ZeroSumBidType == "Minimum Bid") then
              row.Strings[2]:SetText(entry.bid)
              row.Strings[3]:SetText(CommDKP_round(playerDKP, core.DB.modes.rounding))
            elseif mode == "Roll Based Bidding" then
              local minRoll;
              local maxRoll;

              if core.DB.modes.rolls.UsePerc then
                if core.DB.modes.rolls.min == 0 or core.DB.modes.rolls.min == 1 then
                  minRoll = 1;
                else
                  minRoll = playerDKP * (core.DB.modes.rolls.min / 100);
                end
                maxRoll = playerDKP * (core.DB.modes.rolls.max / 100) + core.DB.modes.rolls.AddToMax;
              elseif not core.DB.modes.rolls.UsePerc then
                minRoll = core.DB.modes.rolls.min;

                if core.DB.modes.rolls.max == 0 then
                  maxRoll = playerDKP + core.DB.modes.rolls.AddToMax;
                else
                  maxRoll = core.DB.modes.rolls.max + core.DB.modes.rolls.AddToMax;
                end
              end
              if tonumber(minRoll) < 1 then minRoll = 1 end
              if tonumber(maxRoll) < 1 then maxRoll = 1 end

              row.Strings[2]:SetText(entry.roll..entry.range)
              row.Strings[3]:SetText(math.floor(minRoll).."-"..math.floor(maxRoll))
            elseif mode == "Static Item Values" or (mode == "Zero Sum" and core.DB.modes.ZeroSumBidType == "Static") then
              row.Strings[3]:SetText(CommDKP_round(entry.dkp, core.DB.modes.rounding))
            end
        else
            row:Hide()
        end
    end
    if tipRow then                                             -- AD-24.3.3
      if tipRow:IsShown() and tipRow.player then
        CommDKP:ShowPlayerHistoryTooltip(tipRow, tipRow.player) -- re-render for whoever is NOW on this row
      else
        GameTooltip:Hide()                                     -- row emptied (removed / cleared / list shrank)
      end
    end
    if mode == "Minimum Bid Values" or (mode == "Zero Sum" and core.DB.modes.ZeroSumBidType == "Minimum Bid") then
      if core.DB.modes.CostSelection == "First Bidder" and Bids_Submitted[1] then
        core.BiddingWindow.cost:SetText(Bids_Submitted[1].bid)
      elseif core.DB.modes.CostSelection == "Second Bidder" then
        if Bids_Submitted[2] then
          core.BiddingWindow.cost:SetText(Bids_Submitted[2].bid)
        elseif Bids_Submitted[1] then
          core.BiddingWindow.cost:SetText(Bids_Submitted[1].bid)
        end
      elseif core.DB.modes.CostSelection == "Second Bidder or Min" then
        if Bids_Submitted[2] then
          core.BiddingWindow.cost:SetText(Bids_Submitted[2].bid)
        else
          core.BiddingWindow.cost:SetText(core.BiddingWindow.minBid:GetText())
        end
      end
  end
    -- AD-14.2(c): BidShare skips self, so mirror our list into the auctioneer's own Submit Bid window.
    -- Shallow copy: Bids_Set stores the reference and BidInterface sorts it in place.
    if core.BidInterface and core.DB.modes.BroadcastBids then
      local copy = {}; for i = 1, #Bids_Submitted do copy[i] = Bids_Submitted[i] end
      CommDKP:Bids_Set(copy)
    end
    --FauxScrollFrame_Update(core.BiddingWindow.bidTable, numOptions, numrows, height, nil, nil, nil, nil, nil, nil, true) -- alwaysShowScrollBar= true to stop frame from hiding
end

function CommDKP:CreateBidWindow()

  local f, content;

  -- UX §12.4.3 / AD-16.4: "window" chrome (floater, group "bidding"). Item card + Auction card + Bids card (with the
  -- Award footer), all anchored to f.Content (BR-9.4.4). Q9 short title. Height 616 (not 524): the officer table has no
  -- scrolling, so all 13 bidder rows stay visible (AC-9.10: no functional regression).
  f, content = CommDKP:CreateForeverWindow("CommDKP_BiddingWindow", 400, 616,
        "Bidding", { group = "bidding" })   -- no locale key exists

  mode = core.DB.modes.mode;

  f:SetPoint("TOPLEFT", UIParent, "TOPLEFT", 300, -200);
  f:SetScript("OnDragStop", function()
    f:StopMovingOrSizing();
    local point, relativeTo, relativePoint ,xOff,yOff = f:GetPoint(1)
    if not core.DB.bidpos then
      core.DB.bidpos = {}
    end
    core.DB.bidpos.point = point;
    core.DB.bidpos.relativeTo = relativeTo;
    core.DB.bidpos.relativePoint = relativePoint;
    core.DB.bidpos.x = xOff;
    core.DB.bidpos.y = yOff;
  end);
  -- HookScript (not SetScript): SetScript would wipe the floater registry hooks (§10.1.3).
  f:HookScript("OnHide", function ()
    if core.BidInProgress then
      CommDKP:Print(L["CLOSEDBIDINPROGRESS"])
    end
  end)
  f:HookScript("OnMouseDown", function(self)
    self:SetFrameLevel(10)
    if core.ModesWindow then core.ModesWindow:SetFrameLevel(6) end
    if CommDKP.UIConfig then CommDKP.UIConfig:SetFrameLevel(2) end
  end)

  if core.IsOfficer then
    f.ItemCard = W.CreateCard(content, L["ITEM"], 376, 106)
    f.ItemCard:SetPoint("TOPLEFT", content, "TOPLEFT", 0, 0)
    f.AuctionCard = W.CreateCard(content, L["CARDAUCTION"], 376, 124)
    f.AuctionCard:SetPoint("TOPLEFT", f.ItemCard, "BOTTOMLEFT", 0, -8)
    f.BidsCard = W.CreateCard(content, L["BIDS"], 376, 328, { footer = 38 })
    f.BidsCard:SetPoint("TOPLEFT", f.AuctionCard, "BOTTOMLEFT", 0, -8)
    local ib, ab, bb, ft = f.ItemCard.Body, f.AuctionCard.Body, f.BidsCard.Body, f.BidsCard.Footer

    -- Item card, row 1: ItemIconButton 32 (trimQuiet ring) + the item link in quality color (GameFontNormalLarge)
    f.itemIcon = ib:CreateTexture(nil, "OVERLAY", nil);
    f.itemIcon:SetPoint("TOPLEFT", ib, "TOPLEFT", W.PAD, -8);
    f.itemIcon:SetColorTexture(0, 0, 0, 1)
    f.itemIcon:SetSize(32, 32);

    f.ItemIconButton = CreateFrame("Button", "CommDKPBiddingItemTooltipButtonButton", ib)
    f.ItemIconButton:SetPoint("TOPLEFT", f.itemIcon, "TOPLEFT", 0, 0);
    f.ItemIconButton:SetSize(32, 32);
    f.ItemIconButton.Edges = CommDKP:CreatePixelBorder(f.ItemIconButton, (core.Palette or core.Palettes.Forever).trimQuiet)

    f.item = W.CreateText(ib, "title", nil, "LEFT")
    f.item:SetPoint("LEFT", f.itemIcon, "RIGHT", 8, 0);
    f.item:SetSize(300, 28)
    if f.item.SetWordWrap then f.item:SetWordWrap(false) end

    f.ItemTooltipButton = CreateFrame("Button", "CommDKPBiddingItemTooltipButtonButton", ib)
    f.ItemTooltipButton:SetPoint("TOPLEFT", f.itemIcon, "TOPLEFT", 0, 0);

    f.itemName = W.CreateText(f, "body")       -- hidden itemName field

    -- Item card, row 2: Boss label + the Boss dropdown (shared Award Confirm menu, AD-19.2 012b), 200 wide
    f.bossHeader = W.CreateText(ib, "label", L["BOSS"], "LEFT")
    f.bossHeader:SetPoint("LEFT", ib, "TOPLEFT", W.PAD, -59);

    f.boss = DD:Create_UIDropDownMenu("CommDKPBiddingBossDropDown", ib)      -- kit Forever dropdown (has :SetText/:GetText)
    f.boss:SetPoint("TOPLEFT", ib, "TOPLEFT", 52, -48)                       -- same footprint as the EditBox (UX §13.6.2)
    DD:UIDropDownMenu_SetWidth(f.boss, 200)
    f.bossDropDown = f.boss                                                   -- UX §13.6.2 name alias
    do  -- AD-19 compat shim: plain SetText(v) keeps the checked mark in sync; the zone is left as is.
      local rawSetText = f.boss.SetText
      function f.boss:SetText(v) self.cdkpBoss = v or ""; return rawSetText(self, v or "") end
    end
    function f.boss.SetValue(_, newValue, zone)                               -- AD-11.4: never self
      f.boss.cdkpZone = zone or f.boss.cdkpZone
      f.boss:SetText(newValue); DD:CloseDropDownMenus()
    end
    DD:UIDropDownMenu_Initialize(f.boss, function(self, level, menuList)
      CommDKP:PopulateBossDropdown(self, level, menuList, f.boss.cdkpBoss, f.boss.cdkpZone)
    end)

    -- Auction card, row 1: Minimum Bid (60, right) + Custom · at x 180: Maximum Bid (60) + Custom (labels above)
    f.minBidHeader = W.CreateText(ab, "label", nil, "LEFT")
    f.minBidHeader:SetPoint("TOPLEFT", ab, "TOPLEFT", W.PAD, -6);

    if mode == "Minimum Bid Values" or (mode == "Zero Sum" and core.DB.modes.ZeroSumBidType == "Minimum Bid") then
      -- Min Bid
      f.minBidHeader:SetText(L["MINIMUMBID"])

      f.minBid = CreateFrame("EditBox", nil, ab, "BackdropTemplate")

      f.minBid:SetPoint("TOPLEFT", ab, "TOPLEFT", W.PAD, -20)
      f.minBid:SetAutoFocus(false)
      f.minBid:SetMultiLine(false)
      f.minBid:SetSize(60, W.H)
      f.minBid:SetMaxLetters(8)
      f.minBid.tooltipText = L["MINIMUMBID"];
      f.minBid.tooltipDescription = L["MINBIDTTDESC"]
      f.minBid.tooltipWarning = L["MINBIDTTWARN"]
      f.minBid:SetScript("OnEscapePressed", function(self)    -- clears focus on esc
        self:ClearFocus()
      end)
      f.minBid:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT");
        GameTooltip:SetText(L["MINIMUMBID"], 0.25, 0.75, 0.90, 1, true);
        GameTooltip:AddLine(L["MINBIDTTDESC"], 1.0, 1.0, 1.0, true);
        GameTooltip:AddLine(L["MINBIDTTWARN"], 1.0, 0, 0, true);
        GameTooltip:AddLine(L["MINBIDTTEXT"], 1.0, 0.5, 0, true);
        GameTooltip:Show();
      end)
      f.minBid:SetScript("OnLeave", function(self)
        GameTooltip:Hide()
      end)
      W.StyleEditBox(f.minBid, { numeric = true })
    end

    f.CustomMinBid = W.CreateCheckbox(ab, nil, L["CUSTOM"]);
    f.CustomMinBid:SetChecked(true)
    f.CustomMinBid:Hide();
    f.CustomMinBid:SetScript("OnEnter", function(self)
      GameTooltip:SetOwner(self, "ANCHOR_RIGHT");
      GameTooltip:SetText(L["CUSTOMMINBID"], 0.25, 0.75, 0.90, 1, true);
      GameTooltip:AddLine(L["CUSTOMMINBIDTTDESC"], 1.0, 1.0, 1.0, true);
      GameTooltip:AddLine(L["CUSTOMMINBIDTTWARN"], 1.0, 0, 0, true);
      GameTooltip:Show();
    end)
    f.CustomMinBid:SetScript("OnLeave", function(self)
      GameTooltip:Hide()
    end)

    -- Max Bid
    if mode == "Minimum Bid Values" or (mode == "Zero Sum" and core.DB.modes.ZeroSumBidType == "Minimum Bid") then
      f.maxBidHeader = W.CreateText(ab, "label", L["MAXIMUMBID"], "LEFT")
      f.maxBidHeader:SetPoint("TOPLEFT", ab, "TOPLEFT", 180, -6);

      f.maxBid = CreateFrame("EditBox", nil, ab, "BackdropTemplate")

      f.maxBid:SetPoint("TOPLEFT", ab, "TOPLEFT", 180, -20)
      f.maxBid:SetAutoFocus(false)
      f.maxBid:SetMultiLine(false)
      f.maxBid:SetSize(60, W.H)
      f.maxBid:SetMaxLetters(8)
      f.maxBid.tooltipText = L["MAXIMUMBID"];
      f.maxBid.tooltipDescription = L["MAXBIDTTDESC"]
      f.maxBid.tooltipWarning = L["MAXBIDTTWARN"]
      f.maxBid:SetScript("OnEscapePressed", function(self)    -- clears focus on esc
        self:ClearFocus()
      end)
      f.maxBid:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT");
        GameTooltip:SetText(L["MAXIMUMBID"], 0.25, 0.75, 0.90, 1, true);
        GameTooltip:AddLine(L["MAXBIDTTDESC"], 1.0, 1.0, 1.0, true);
        GameTooltip:AddLine(L["MAXBIDTTWARN"], 1.0, 0, 0, true);
        GameTooltip:AddLine(L["MAXBIDTTEXT"], 1.0, 0.5, 0, true);
        GameTooltip:Show();
      end)
      f.maxBid:SetScript("OnLeave", function(self)
        GameTooltip:Hide()
      end)
      W.StyleEditBox(f.maxBid, { numeric = true })

    f.CustomMaxBid = W.CreateCheckbox(ab, nil, L["CUSTOM"]);
    f.CustomMaxBid:SetChecked(core.DB.defaults.CustomMaxBid)
    f.CustomMaxBid:Hide();
    f.CustomMaxBid:SetScript("OnEnter", function(self)
      GameTooltip:SetOwner(self, "ANCHOR_RIGHT");
      GameTooltip:SetText(L["CUSTOMMAXBID"], 0.25, 0.75, 0.90, 1, true);
      GameTooltip:AddLine(L["CUSTOMMAXBIDTTDESC"], 1.0, 1.0, 1.0, true);
      GameTooltip:AddLine(L["CUSTOMMAXBIDTTWARN"], 1.0, 0, 0, true);
      GameTooltip:Show();
    end)
    f.CustomMaxBid:SetScript("OnLeave", function(self)
      GameTooltip:Hide()
    end)
  end
    -- Auction card, row 2: Bid Timer label + bidTimer (60) + "Seconds" caption · Start Bidding (primary) · Clear Window
    f.bidTimerHeader = W.CreateText(ab, "label", L["BIDTIMER"], "LEFT")
    f.bidTimerHeader:SetPoint("TOPLEFT", ab, "TOPLEFT", W.PAD, -52);

    f.bidTimer = CreateFrame("EditBox", nil, ab, "BackdropTemplate")

    f.bidTimer:SetPoint("TOPLEFT", ab, "TOPLEFT", W.PAD, -66)
      f.bidTimer:SetAutoFocus(false)
      f.bidTimer:SetMultiLine(false)
      f.bidTimer:SetSize(60, W.H)
      f.bidTimer:SetMaxLetters(4)
      f.bidTimer.tooltipText = L["BIDTIMER"];
      f.bidTimer.tooltipDescription = L["BIDTIMERTTDESC"]
      f.bidTimer.tooltipWarning = L["BIDTIMERTTWARN"]
      f.bidTimer:SetScript("OnEscapePressed", function(self)    -- clears focus on esc
        self:ClearFocus()
      end)
      f.bidTimer:SetScript("OnEscapePressed", function(self)    -- clears focus on esc
        self:ClearFocus()
      end)
      f.bidTimer:SetScript("OnEnter", function(self)
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
    end)
    f.bidTimer:SetScript("OnLeave", function(self)
      GameTooltip:Hide()
    end)
    W.StyleEditBox(f.bidTimer, { numeric = true })

    f.bidTimerFooter = W.CreateText(ab, "caption", L["SECONDS"], "LEFT", "textMuted")
    f.bidTimerFooter:SetPoint("LEFT", f.bidTimer, "RIGHT", 5, 0);

    -- B7: the global CommDKPBiddingStartBiddingButton stays the Start/End button; styled primary where it is created.
    f.StartBidding = CreateFrame("Button", "CommDKPBiddingStartBiddingButton", ab, "CommunityDKPButtonTemplate")
    f.StartBidding:SetPoint("TOPLEFT", ab, "TOPLEFT", 128, -66);
    f.StartBidding:SetSize(110, W.H);
    f.StartBidding:SetText(L["STARTBIDDING"]);
    W.StyleButton(f.StartBidding, "primary")
    f.StartBidding:SetScript("OnClick", function (self)
      local pass, err = pcall(ToggleTimerBtn, self)

      if f.minBid then f.minBid:ClearFocus(); end
      if f.maxBid then f.maxBid:ClearFocus(); end
      f.bidTimer:ClearFocus()
      f.cost:ClearFocus()
      if not pass then
        CommDKP:Print(err)
        core.BiddingWindow:SetShown(false)
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
        CommDKP:ShowPopupOverFloaters("SUGGEST_RELOAD", core.BiddingWindow)
      end
    end)
    f.StartBidding:SetScript("OnEnter", function(self)
      GameTooltip:SetOwner(self, "ANCHOR_RIGHT");
      GameTooltip:SetText(L["STARTBIDDING"], 0.25, 0.75, 0.90, 1, true);
      GameTooltip:AddLine(L["STARTBIDDINGTTDESC"], 1.0, 1.0, 1.0, true);
      GameTooltip:AddLine(L["STARTBIDDINGTTWARN"], 1.0, 0, 0, true);
      GameTooltip:Show();
    end)
    f.StartBidding:SetScript("OnLeave", function(self)
      GameTooltip:Hide()
    end)

    f.ClearBidWindow = CommDKP:CreateButton("LEFT", f.StartBidding, "RIGHT", 6, 0, L["CLEARBIDWINDOW"]);
    f.ClearBidWindow:SetSize(110, W.H)
    f.ClearBidWindow:SetScript("OnClick", CommDKP.ClearBidWindow)
    f.ClearBidWindow:SetScript("OnEnter", function(self)
      GameTooltip:SetOwner(self, "ANCHOR_RIGHT");
      GameTooltip:SetText(L["CLEARBIDWINDOW"], 0.25, 0.75, 0.90, 1, true);
      GameTooltip:AddLine(L["CLEARBIDWINDOWTTDESC"], 1.0, 1.0, 1.0, true);
      GameTooltip:Show();
    end)
    f.ClearBidWindow:SetScript("OnLeave", function(self)
      GameTooltip:Hide()
    end)


    --------------------------------------------------
    -- Bids card: column strip + the officer table (13 rows, kit rows/selection, region rail). The right-click bidder
    -- menu stays the stock LibDD CommDKPBidWindowMenuFrame (Q4).
    --------------------------------------------------
    f.bidTable = CreateFrame("ScrollFrame", "CommDKP_BidWindowTable", bb)

    f.bidTable:SetSize(width, height*numrows)
    f.bidTable.ScrollBar = FauxScrollFrame_GetChildFrames(f.bidTable)


      f.bidTable.Rows = {}
      for i=1, numrows do
          f.bidTable.Rows[i] = BidWindowCreateRow(f.bidTable, i)
          if i==1 then
            f.bidTable.Rows[i]:SetPoint("TOPLEFT", f.bidTable, "TOPLEFT", 0, 0)
          else
            f.bidTable.Rows[i]:SetPoint("TOPLEFT", f.bidTable.Rows[i-1], "BOTTOMLEFT")
          end
      end
      f.bidTable:SetScript("OnVerticalScroll", function(self, offset)
          FauxScrollFrame_OnVerticalScroll(self, offset, height, CommDKP.BidScrollFrame_Update)
      end)

    ---------------------------------------
    -- Header Buttons
    ---------------------------------------
    local headerButtons = {}
    mode = core.DB.modes.mode;

    f.BidTable_Headers = W.CreateColumnStrip(bb, 20, "CommDKPDKPTableHeaders")
    f.BidTable_Headers:SetPoint("TOPLEFT", bb, "TOPLEFT", 0, 0)
    f.BidTable_Headers:SetPoint("TOPRIGHT", bb, "TOPRIGHT", 0, 0)
    f.bidTable:SetPoint("TOPLEFT", bb, "TOPLEFT", 4, -22)
    f.BidTable_Headers:Show()
    W.AttachRegionRail(f.bidTable, bb)

    headerButtons.player = CreateFrame("Button", "$ParentButtonPlayer", f.BidTable_Headers)
    headerButtons.bid = CreateFrame("Button", "$ParentButtonBid", f.BidTable_Headers)
    headerButtons.dkp = CreateFrame("Button", "$ParentSuttonDkp", f.BidTable_Headers)

    headerButtons.player:SetPoint("LEFT", f.BidTable_Headers, "LEFT", 4, 0)
    headerButtons.bid:SetPoint("LEFT", headerButtons.player, "RIGHT", 0, 0)
    headerButtons.dkp:SetPoint("LEFT", headerButtons.bid, "RIGHT", 0, 0)

    for k, v in pairs(headerButtons) do
      v:SetHighlightTexture("Interface\\BUTTONS\\BlueGrad64_faded.blp");
      if k == "player" then
        if mode == "Minimum Bid Values" or mode == "Roll Based Bidding" or (mode == "Zero Sum" and core.DB.modes.ZeroSumBidType == "Minimum Bid") then
          v:SetSize((width/2)-1, height)
        elseif mode == "Static Item Values" or mode == "Roll Based Bidding" or (mode == "Zero Sum" and core.DB.modes.ZeroSumBidType == "Static") then
          v:SetSize((width*0.75)-1, height)
        end
      else
        if mode == "Minimum Bid Values" or mode == "Roll Based Bidding" or (mode == "Zero Sum" and core.DB.modes.ZeroSumBidType == "Minimum Bid") then
          v:SetSize((width/4)-1, height)
        elseif mode == "Static Item Values" or mode == "Roll Based Bidding" or (mode == "Zero Sum" and core.DB.modes.ZeroSumBidType == "Static") then
          if k == "bid" then
            v:Hide()
          else
            v:SetSize((width/4)-1, height)
          end
        end

      end
    end

    headerButtons.player.t = W.CreateText(headerButtons.player, "label", L["PLAYER"], "LEFT")
    headerButtons.player.t:SetPoint("LEFT", headerButtons.player, "LEFT", 20, 0);

    headerButtons.bid.t = W.CreateText(headerButtons.bid, "label", nil, "CENTER")
    headerButtons.bid.t:SetPoint("CENTER", headerButtons.bid, "CENTER", 0, 0);

    if mode == "Minimum Bid Values" or (mode == "Zero Sum" and core.DB.modes.ZeroSumBidType == "Minimum Bid") then
      headerButtons.bid.t:SetText(L["BID"]);
    elseif mode == "Static Item Values" or (mode == "Zero Sum" and core.DB.modes.ZeroSumBidType == "Static") then
      headerButtons.bid.t:Hide();
    elseif mode == "Roll Based Bidding" then
      headerButtons.bid.t:SetText(L["PLAYERROLL"])
    end

    headerButtons.dkp.t = W.CreateText(headerButtons.dkp, "label", nil, "CENTER")
    headerButtons.dkp.t:SetPoint("CENTER", headerButtons.dkp, "CENTER", 0, 0);

    if mode == "Minimum Bid Values" or (mode == "Zero Sum" and core.DB.modes.ZeroSumBidType == "Minimum Bid") then
      headerButtons.dkp.t:SetText(L["TOTALDKP"]);
    elseif mode == "Static Item Values" or (mode == "Zero Sum" and core.DB.modes.ZeroSumBidType == "Static") then
      headerButtons.dkp.t:SetText(L["DKP"]);
    elseif mode == "Roll Based Bidding" then
      headerButtons.dkp.t:SetText(L["EXPECTEDROLL"])
    end

      ------------------------------------
      --  AWARD ITEM (Bids card footer: 38 px bg2 band, 1 px line rule)
      ------------------------------------

      f.cost = CreateFrame("EditBox", nil, ft, "BackdropTemplate")

    f.cost:SetPoint("LEFT", ft, "LEFT", 66, 0)
      f.cost:SetAutoFocus(false)
      f.cost:SetMultiLine(false)
      f.cost:SetSize(60, W.H)
      f.cost:SetMaxLetters(8)
      f.cost:SetScript("OnEscapePressed", function(self)    -- clears focus on esc
        self:ClearFocus()
      end)
      f.cost:SetScript("OnEnter", function(self)
      GameTooltip:SetOwner(self, "ANCHOR_RIGHT");
      GameTooltip:SetText(L["ITEMCOST"], 0.25, 0.75, 0.90, 1, true);
      GameTooltip:AddLine(L["ITEMCOSTTTDESC"], 1.0, 1.0, 1.0, true);
      GameTooltip:Show();
    end)
    f.cost:SetScript("OnLeave", function(self)
      GameTooltip:Hide()
    end)
    W.StyleEditBox(f.cost, { numeric = true })

    f.costHeader = W.CreateText(ft, "label", L["ITEMCOST"], "LEFT")
    f.costHeader:SetPoint("LEFT", ft, "LEFT", W.PAD, 0);

    if core.DB.modes.costvalue == "Percent" then
      f.cost.perc = W.CreateText(f.cost, "caption", "%", "LEFT", "textMuted")
      f.cost.perc:SetPoint("LEFT", f.cost, "RIGHT", 3, 0);
    end

    if mode == "Minimum Bid Values" or (mode == "Zero Sum" and core.DB.modes.ZeroSumBidType == "Minimum Bid") then
      f.CustomMinBid:SetPoint("LEFT", f.minBid, "RIGHT", 10, 0);
      f.CustomMaxBid:SetPoint("LEFT", f.maxBid, "RIGHT", 10, 0);
    elseif mode == "Static Item Values" or mode == "Roll Based Bidding" or (mode == "Zero Sum" and core.DB.modes.ZeroSumBidType == "Static") then
      f.CustomMinBid:SetParent(ft)                        -- it sits next to the cost box in these modes (as today)
      f.CustomMinBid:SetPoint("LEFT", f.cost, "RIGHT", 10, 0);
    end

    f.ItemDE = CommDKP:CreateButton("RIGHT", ft, "RIGHT", -W.PAD, 0, "DE");
    f.ItemDE:SetSize(34, W.H)
    f.ItemDE:SetScript("OnClick", function ()
      CommDKP:ProcessDisenchant(CurrItemForBid)
    end);

    -- B7: f.StartBidding (the table field only) becomes the Award Item button; styled primary where it is created.
    f.StartBidding = CommDKP:CreateButton("RIGHT", f.ItemDE, "LEFT", -6, 0, L["AWARDITEM"]);
    f.StartBidding:SetSize(120, W.H)
    W.StyleButton(f.StartBidding, "primary")
    f.StartBidding:SetScript("OnClick", function ()  -- confirmation dialog to remove user(s)
      -- CDKP-003 (AD-1/BR-6): awarding is refused, never deferred, during lockdown.
      if CommDKP:IsMessagingRestricted() then
        CommDKP:Print(L["BIDDINGLOCKED"])
        return
      end
      if SelectedBidder["player"] then
        if strlen(strtrim(core.BiddingWindow.boss:GetText(), " ")) < 1 then       -- verifies there is a boss name
          StaticPopupDialogs["VALIDATE_BOSS"] = {
            text = L["INVALIDBOSSNAME"],
            button1 = L["OK"],
            timeout = 0,
            whileDead = true,
            hideOnEscape = true,
            preferredIndex = 3,
          }
          CommDKP:ShowPopupOverFloaters("VALIDATE_BOSS", core.BiddingWindow)
          return;
        end

        CommDKP:AwardConfirm(SelectedBidder["player"], tonumber(f.cost:GetText()), f.boss:GetText(), f.boss.cdkpZone or core.DB.bossargs.CurrentRaidZone, CurrItemForBid)   -- BR-12.10.3
      else
        local selected = L["PLAYERVALIDATE"];

        StaticPopupDialogs["CONFIRM_AWARD"] = {
          text = selected,
          button1 = L["OK"],
          timeout = 5,
          whileDead = true,
          hideOnEscape = true,
          preferredIndex = 3,
        }
        CommDKP:ShowPopupOverFloaters("CONFIRM_AWARD", core.BiddingWindow)
      end
    end);

    f:SetScript("OnMouseUp", function(self)    -- clears focus on esc
      local item,_,link = GetCursorInfo();

      if item == "item" then

        local itemName, _, itemIcon = CommDKP:ParseItemLink(link)   -- AD-13.4: cold-cache safe

        CurrItemForBid = link
        CurrItemIcon = itemIcon
        CommDKP:ToggleBidWindow(CurrItemForBid, CurrItemIcon, itemName)
        ClearCursor()
      end
      end)
  end

  return f;
end
