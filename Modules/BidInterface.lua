local _, core = ...;
local _G = _G;
local CommDKP = core.CommDKP;
local L = core.L;
local W = CommDKP.Widgets

local lootTable = {};

  --[[["132744"] = "|cffa335ee|Hitem:12895::::::::60:::::|h[Breastplate of the Chromatic Flight]|h|r",
  ["132585"] = "|cffa335ee|Hitem:16862::::::::60:::::|h[Sabatons of Might]|h|r",
  ["133066"] = "|cffff8000|Hitem:17182::::::::60:::::|h[Sulfuras, Hand of Ragnaros]|h|r",
  ["133173"] = "|cffa335ee|Hitem:16963::::::::60:::::|h[Helm of Wrath]|h|r",
  ["135065"] = "|cffa335ee|Hitem:16961::::::::60:::::|h[Pauldrons of Wrath]|h|r",--]]

local width, height, numrows = 352, 18, 9   -- §12.4.2 Bids card: 9 x 18 px faux rows + the 20 px column strip
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

-- UX §12.4.2: one height helper. Full 556 in every mode (the Max Bid line lives in the Your Bid summary row, so no
-- per-mode delta); collapsed (no Bids card) 328. Replaces 556/528 and 283/255; layout constants only.
local function BIDINT_HEIGHT(collapsed)
  if collapsed then return 328 end
  return 556
end

local Bids_Submitted = {};
local CurrItemForBid, CurrItemIcon;

-- Broadcast should set LootTable_Set when loot is opened. Starting an auction will update through CurrItem_Set
-- When bid received it will be broadcasted and handled with Bids_Set(). If bid broadcasting is off, window will be reduced in size and scrollframe removed.

function CommDKP:LootTable_Set(lootList)
  lootTable = lootList
end

-- CDKP-003 (AD-1/BR-6): bid submit/cancel/pass are refused, never deferred, during lockdown.
-- Returns true when the action must be refused.
local function BiddingLocked()
  if CommDKP:IsMessagingRestricted() then
    CommDKP:Print(L["BIDDINGLOCKED"])
    return true
  end
  return false
end

-- AD-13.5: single send path shared by BidInterface_Create and CurrItem_Set.
local function CancelBid_OnClick()
  if core.BidInterface and core.BidInterface.Bid then core.BidInterface.Bid:ClearFocus() end
  if BiddingLocked() then return end
  CommDKP.Sync:SendData("CommDKPBidder", "!bid cancel")
end

local function SortBidTable()
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

local function RollMinMax_Get()
  local search = CommDKP:Table_Search(CommDKP:GetTable(CommDKP_DKPTable, true), CommDKP:GetPlayerName())
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

  return minRoll, maxRoll;
end

local function UpdateBidderWindow()
	local i = 1;
	local mode = core.DB.modes.mode;
	local _, link, icon = CommDKP:ParseItemLink(CurrItemForBid)   -- AD-13.4: cold-cache safe
	icon = icon or tonumber(CurrItemIcon)

	if not core.BidInterface then
		core.BidInterface = core.BidInterface or CommDKP:BidInterface_Create()
	end

	for j=2, 10 do
		core.BidInterface.LootTableIcons[j]:Hide()
		core.BidInterface.LootTableButtons[j]:Hide();
	end
	core.BidInterface.lootContainer:SetSize(28, 28)

	for k,v in pairs(lootTable) do
		core.BidInterface.LootTableIcons[i]:SetTexture(tonumber(v.icon))
		core.BidInterface.LootTableIcons[i]:Show()
		core.BidInterface.LootTableButtons[i]:Show();
		core.BidInterface.LootTableButtons[i]:SetScript("OnEnter", function(self)
			GameTooltip:SetOwner(self:GetParent(), "ANCHOR_BOTTOMRIGHT", 0, 500);
			GameTooltip:SetHyperlink(v.link)
		end)
		core.BidInterface.LootTableButtons[i]:SetScript("OnLeave", function(self)
			GameTooltip:Hide();
		end)
		if tonumber(v.icon) == tonumber(icon) and v.link == link then
			CommDKP:ShowButtonGlow(core.BidInterface.LootTableButtons[i])
		else
			CommDKP:HideButtonGlow(core.BidInterface.LootTableButtons[i])
		end
		i = i+1
	end

	if i==1 then
		core.BidInterface.lootContainer:SetSize(28, 28)
	else
		i = i-1
		core.BidInterface.lootContainer:SetSize(34*i - 6, 28)   -- §12.4.2: 28 px icons, 6 px apart
	end

	if mode == "Minimum Bid Values" or (mode == "Zero Sum" and core.DB.modes.ZeroSumBidType == "Minimum Bid") then
		core.BidInterface.MinBidHeader:SetText(L["MINIMUMBID"]..":")
		core.BidInterface.SubmitBid:SetText(L["SUBMITBID"])
		core.BidInterface.Bid:Show();
		core.BidInterface.CancelBid:Show();
		core.BidInterface.Pass:Show();
	elseif mode == "Roll Based Bidding" then
		core.BidInterface.MinBidHeader:SetText(L["ITEMCOST"]..":")
		core.BidInterface.SubmitBid:SetText(L["ROLL"])
		core.BidInterface.Bid:Hide();
		core.BidInterface.CancelBid:Hide();
		core.BidInterface.Pass:Hide();
	else
		core.BidInterface.MinBidHeader:SetText(L["ITEMCOST"]..":")
		core.BidInterface.SubmitBid:SetText(L["SUBMITBID"])
		core.BidInterface.Bid:Hide();
		core.BidInterface.CancelBid:Show();
		core.BidInterface.Pass:Show();
	end


	core.BidInterface.item:SetText(CurrItemForBid)
	core.BidInterface.itemIcon:SetTexture(icon)              -- §12.4.2 row 2 item icon (display only)
	core.BidInterface.Boss:SetText(core.DB.bossargs.LastKilledBoss)
end

function CommDKP_BidInterface_Update()
  local numOptions = #Bids_Submitted;
  local index, row
    local offset = FauxScrollFrame_GetOffset(core.BidInterface.bidTable) or 0
    local rank;
    local showRows = #Bids_Submitted

    if #Bids_Submitted > numrows then
      showRows = numrows
    end

  if not core.BidInterface.bidTable:IsShown() then return end

    SortBidTable()
    local muted = MutedHex() -- AD-22.8.3: read once per refresh (BR-084.3)
    for i=1, numrows do
      row = core.BidInterface.bidTable.Rows[i]
      row:Hide()
    end    
  if Bids_Submitted[1] and Bids_Submitted[1].bid and core.BidInterface.bidTable:IsShown() and
    (core.BidInterface.Bid:GetNumber() == nil or tonumber(core.BidInterface.Bid:GetNumber()) == nil or Bids_Submitted[1].bid > tonumber(core.BidInterface.Bid:GetNumber())) then
    core.BidInterface.Bid:SetNumber(Bids_Submitted[1].bid)
  end
    for i=1, showRows do
        row = core.BidInterface.bidTable.Rows[i]
        index = offset + i
        local entry = Bids_Submitted[index]    -- AD-13.3: always index by scrolled position
        if entry then
            local dkpTable = CommDKP:GetTable(CommDKP_DKPTable, true)
            local dkp_total = CommDKP:Table_Search(dkpTable, entry.player)
            if not dkp_total and CommDKP_Profile_Create(entry.player) then
              dkp_total = CommDKP:Table_Search(dkpTable, entry.player)
            end
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
            row.Strings[1].rowCounter:SetText(index)
            row.Strings[1]:SetText(entry.player.." "..muted.."("..rank..")|r")
            row.Strings[1]:SetTextColor(c.r, c.g, c.b, 1)
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
    FauxScrollFrame_Update(core.BidInterface.bidTable, numOptions, numrows, height, nil, nil, nil, nil, nil, nil, true) -- alwaysShowScrollBar= true to stop frame from hiding
end

function CommDKP:BidInterface_Toggle()
  core.BidInterface = core.BidInterface or CommDKP:BidInterface_Create()
  local f = core.BidInterface;
  local mode = core.DB.modes.mode;

  if core.DB.bidintpos then
    core.BidInterface:ClearAllPoints()
    local a = core.DB.bidintpos
    core.BidInterface:SetPoint(a.point, a.relativeTo, a.relativePoint, a.x, a.y)
  end

  if core.BidInterface:IsShown() then core.BidInterface:Hide(); end
  if CommDKP.BidTimer.OpenBid and CommDKP.BidTimer.OpenBid:IsShown() then CommDKP.BidTimer.OpenBid:Hide() end
  if core.DB.modes.BroadcastBids and not (core.BiddingWindow and core.BiddingWindow:IsShown()) then
    core.BidInterface:SetHeight(BIDINT_HEIGHT(false));
    core.BidInterface.bidTable:Show();
    for k, v in pairs(f.headerButtons) do
      v:SetHighlightTexture("Interface\\BUTTONS\\BlueGrad64_faded.blp");
      if k == "player" then
        if mode == "Minimum Bid Values" or mode == "Roll Based Bidding" or (mode == "Zero Sum" and core.DB.modes.ZeroSumBidType == "Minimum Bid") then
          v:SetSize((width/2)-1, height)
          v:Show()
        elseif mode == "Static Item Values" or mode == "Roll Based Bidding" or (mode == "Zero Sum" and core.DB.modes.ZeroSumBidType == "Static") then
          v:SetSize((width*0.75)-1, height)
          v:Show()
        end
      else
        if mode == "Minimum Bid Values" or mode == "Roll Based Bidding" or (mode == "Zero Sum" and core.DB.modes.ZeroSumBidType == "Minimum Bid") then
          v:SetSize((width/4)-1, height)
          v:Show();
        elseif mode == "Static Item Values" or mode == "Roll Based Bidding" or (mode == "Zero Sum" and core.DB.modes.ZeroSumBidType == "Static") then
          if k == "bid" then
            v:Hide()
          else
            v:SetSize((width/4)-1, height)
            v:Show();
          end
        end
      end
    end

    if mode == "Minimum Bid Values" or (mode == "Zero Sum" and core.DB.modes.ZeroSumBidType == "Minimum Bid") then
      f.headerButtons.bid.t:SetText(L["BID"]);
      f.headerButtons.bid.t:Show();
    elseif mode == "Static Item Values" or (mode == "Zero Sum" and core.DB.modes.ZeroSumBidType == "Static") then
      f.headerButtons.bid.t:Hide(); 
    elseif mode == "Roll Based Bidding" then
      f.headerButtons.bid.t:SetText(L["PLAYERROLL"])
      f.headerButtons.bid.t:Show()
    end

    if mode == "Minimum Bid Values" or (mode == "Zero Sum" and core.DB.modes.ZeroSumBidType == "Minimum Bid") then
      f.headerButtons.dkp.t:SetText(L["TOTALDKP"]);
      f.headerButtons.dkp.t:Show();
    elseif mode == "Static Item Values" or (mode == "Zero Sum" and core.DB.modes.ZeroSumBidType == "Static") then
      f.headerButtons.dkp.t:SetText(L["DKP"]);
      f.headerButtons.dkp.t:Show()
    elseif mode == "Roll Based Bidding" then
      f.headerButtons.dkp.t:SetText(L["EXPECTEDROLL"])
      f.headerButtons.dkp.t:Show();
    end
  end

  if core.DB.modes.BroadcastBids then
    local pass, err = pcall(CommDKP_BidInterface_Update)

    if not pass then
      print(err)
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
      CommDKP:ShowPopupOverFloaters("SUGGEST_RELOAD", core.BidInterface)
    end
  end

  if not core.DB.modes.BroadcastBids or (core.BiddingWindow and core.BiddingWindow:IsShown()) then
    core.BidInterface:SetHeight(BIDINT_HEIGHT(true));
    core.BidInterface.bidTable:Hide();
  else
    core.BidInterface:SetHeight(BIDINT_HEIGHT(false));
    core.BidInterface.bidTable:Show();
  end  

  core.BidInterface:SetShown(true)
end

local function BidWindowCreateRow(parent, id) -- Create 3 buttons for each row in the list

  local f;

  f = CreateFrame("Button", "$parentLine"..id, parent)

  f.Strings = {}
  f:SetSize(width, height)
  W.StyleRow(f, id)                    -- §12.2.10 stripe + hover (replaces ListBox-Highlight / talent-blue-glow)
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

    return f
end

-- populate bid window
function CommDKP:CurrItem_Set(item, value, icon, value2)
  CurrItemForBid = item;
  CurrItemIcon = icon;

  

  ----------------------------------------------------------------------
  -- Check if item is in the item list
  -- If not then we have out of kill bid
  -- Overwrite the list to contain only the item
  -- Thank you to lantisnt of EssentialDKP for the assist on this.
  -- https://github.com/lantisnt/EssentialDKP/pull/26/files#diff-c2e2b9359e4bbfc335111a2a4472c9c6

  -- AD-13.4: cold-cache safe; ParseItemLink already returns the raw hyperlink when the cache is cold.
  local _, tmpLink, tmpIcon = CommDKP:ParseItemLink(item)
  tmpIcon = tmpIcon or tonumber(icon)
  local currItemInLoot = false

  if tmpLink == nil then
    -- CDKP-004 (BR-2): uncached item; re-run once the client has loaded it.
    if type(item) == "string" and item:find("|Hitem:") then
      local itemObj = Item:CreateFromItemLink(item)
      if not itemObj:IsItemEmpty() then
        itemObj:ContinueOnItemLoad(function () CommDKP:CurrItem_Set(item, value, icon, value2); end)
        return;
      end
    end
    C_Timer.After(0.5, function () CommDKP:CurrItem_Set(item, value, icon, value2); end);  -- not a link (legacy path): poll as before
    return;
  end

  for _,_i in pairs(lootTable) do
    if _i.link == tmpLink then currItemInLoot = true end
  end

  if not currItemInLoot then
    CommDKP:LootTable_Set({{icon=tmpIcon, link=tmpLink}})
  end
  ----------------------------------------------------------------------
  
  UpdateBidderWindow()

  if not strfind(value, "%%") and not strfind(value, "DKP") then
    core.BidInterface.MinBid:SetText(value.." DKP");
  else
    core.BidInterface.MinBid:SetText(value);
  end
  
  if core.BidInterface.MaxBid then
    if not strfind(value2, "%%") and not strfind(value2, "DKP") then
      if value2 == "MAX" then
        local dkpValue = 0;

        local search = CommDKP:Table_Search(CommDKP:GetTable(CommDKP_DKPTable, true), CommDKP:GetPlayerName(), "player")
        if search then
          dkpValue = CommDKP:GetTable(CommDKP_DKPTable, true)[search[1][1]].dkp;
        end
        core.BidInterface.MaxBid:SetText(dkpValue.." DKP");
      else
        core.BidInterface.MaxBid:SetText(value2.." DKP");
      end
    else
      core.BidInterface.MaxBid:SetText(value2);
    end
  end
  
  if core.BidInterface.Bid:IsShown() then
    core.BidInterface.Bid:SetNumber(value);
  end

  if core.DB.modes.mode ~= "Roll Based Bidding" then
    core.BidInterface.SubmitBid:SetScript("OnClick", function()
      if BiddingLocked() then return end
      local message;

      if core.BidInterface.Bid:IsShown() then
        message = "!bid "..CommDKP_round(core.BidInterface.Bid:GetNumber(), core.DB.modes.rounding)
      else
        message = "!bid";
      end
      CommDKP.Sync:SendData("CommDKPBidder", tostring(message))
      core.BidInterface.Bid:ClearFocus();
    end)

    core.BidInterface.CancelBid:SetScript("OnClick", CancelBid_OnClick)
  elseif core.DB.modes.mode == "Roll Based Bidding" then
    core.BidInterface.SubmitBid:SetScript("OnClick", function()
      local min, max = RollMinMax_Get()

      RandomRoll(min, max);
    end)
  end

  if not core.DB.modes.BroadcastBids or core.BidInProgress then
    core.BidInterface:SetHeight(BIDINT_HEIGHT(true));
    core.BidInterface.bidTable:Hide();
  else
    core.BidInterface:SetHeight(BIDINT_HEIGHT(false));
    core.BidInterface.bidTable:Show();
  end
end

function CommDKP:Bids_Set(entry)
  Bids_Submitted = entry;
  
  local pass, err = pcall(CommDKP_BidInterface_Update)

  if not pass then
    print(err)
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
    CommDKP:ShowPopupOverFloaters("SUGGEST_RELOAD", core.BidInterface)
  end
end

function CommDKP:BidInterface_Create()
  -- UX §12.4.2 / AD-16.4: "window" chrome (400 x 556 / collapsed 328, floater group "bidding"). Current Item card +
  -- Your Bid card + Bids card (only while bid broadcasting is on, as today), all anchored to f.Content (BR-9.4.4).
  local f, content = CommDKP:CreateForeverWindow("CommDKP_BidderWindow", 400, BIDINT_HEIGHT(false),
        L["SUBMITBID"], { group = "bidding" })   -- AD-13.5; Q9 short title
  local mode = core.DB.modes.mode;
  f:SetPoint("TOPLEFT", UIParent, "TOPLEFT", 700, -200);
  f:SetScript("OnDragStop", function()
    f:StopMovingOrSizing();
    local point, relativeTo, relativePoint, xOff, yOff = f:GetPoint(1)
    if not core.DB.bidintpos then
      core.DB.bidintpos = {}
    end
    core.DB.bidintpos.point = point;
    core.DB.bidintpos.relativeTo = relativeTo;
    core.DB.bidintpos.relativePoint = relativePoint;
    core.DB.bidintpos.x = xOff;
    core.DB.bidintpos.y = yOff;
  end);
  -- HookScript (not SetScript): SetScript would wipe the floater registry hooks (§10.1.3).
  f:HookScript("OnMouseDown", function(self)
    self:SetFrameLevel(10)
    if core.ModesWindow then core.ModesWindow:SetFrameLevel(6) end
    if CommDKP.UIConfig then CommDKP.UIConfig:SetFrameLevel(2) end
  end)

  f.CurrentItemCard = W.CreateCard(content, L["CARDCURRENTITEM"], 376, 122)
  f.CurrentItemCard:SetPoint("TOPLEFT", content, "TOPLEFT", 0, 0)
  f.YourBidCard = W.CreateCard(content, L["CARDYOURBID"], 376, 124)
  f.YourBidCard:SetPoint("TOPLEFT", f.CurrentItemCard, "BOTTOMLEFT", 0, -8)
  local cur, yb = f.CurrentItemCard.Body, f.YourBidCard.Body

  f.LootTableIcons = {}
  f.LootTableButtons = {}

  -- UX §10.3: parented to f (was UIParent, which leaked a stray frame outliving f's hide/scale). It is only the
  -- centering anchor of row 1; the icons themselves draw on the card body.
  f.lootContainer = CreateFrame("Frame", "CommDKP_LootContainer", f, "BackdropTemplate");

  f.lootContainer:SetPoint("TOP", cur, "TOP", 0, -6);
  f.lootContainer:SetSize(28, 28)

  -- Row 1: boss loot icons at 28 x 28, 6 px apart (clicks/tooltips unchanged)
  for i=1, 10 do
    f.LootTableIcons[i] = cur:CreateTexture(nil, "OVERLAY", nil);
    f.LootTableIcons[i]:SetColorTexture(0, 0, 0, 1)
    f.LootTableIcons[i]:SetSize(28, 28);
    f.LootTableIcons[i]:Hide();
    f.LootTableButtons[i] = CreateFrame("Button", "CommDKPBidderLootTableButton", cur)
    f.LootTableButtons[i]:SetPoint("TOPLEFT", f.LootTableIcons[i], "TOPLEFT", 0, 0);
    f.LootTableButtons[i]:SetSize(28, 28);
    f.LootTableButtons[i]:Hide()

    if i==1 then
      f.LootTableIcons[i]:SetPoint("LEFT", f.lootContainer, "LEFT", 0, 0);
    else
      f.LootTableIcons[i]:SetPoint("LEFT", f.LootTableIcons[i-1], "RIGHT", 6, 0);
    end
  end

  -- 1 px rule between the loot row and the current item
  f.itemRule = cur:CreateTexture(nil, "BORDER")
  f.itemRule:SetPoint("TOPLEFT", cur, "TOPLEFT", W.PAD, -40)
  f.itemRule:SetPoint("TOPRIGHT", cur, "TOPRIGHT", -W.PAD, -40)
  f.itemRule:SetHeight(1)
  f.itemRule:SetColorTexture(unpack((core.Palette or core.Palettes.Forever).rule))

  -- Row 2: item icon 36 (trimQuiet ring) + the link in quality color, normal case (GameFontNormalLarge) + boss caption
  f.itemIcon = cur:CreateTexture(nil, "ARTWORK", nil);
  f.itemIcon:SetPoint("TOPLEFT", cur, "TOPLEFT", W.PAD, -48);
  f.itemIcon:SetSize(36, 36);
  f.itemIconFrame = CreateFrame("Frame", nil, cur)
  f.itemIconFrame:SetAllPoints(f.itemIcon)
  f.itemIconFrame.Edges = CommDKP:CreatePixelBorder(f.itemIconFrame, (core.Palette or core.Palettes.Forever).trimQuiet)

  f.item = W.CreateText(cur, "title", nil, "LEFT")
  f.item:SetPoint("TOPLEFT", f.itemIcon, "TOPRIGHT", 8, -2);
  f.item:SetPoint("RIGHT", cur, "RIGHT", -W.PAD, 0);
  if f.item.SetWordWrap then f.item:SetWordWrap(false) end

  f.Boss = W.CreateText(cur, "caption", nil, "LEFT", "textMuted")
  f.Boss:SetPoint("TOPLEFT", f.item, "BOTTOMLEFT", 0, -4)

  -- Your Bid card, summary row: Minimum Bid (or Item Cost) + Maximum Bid at x 180 (min-bid modes only, as today)
  f.MinBidHeader = W.CreateText(yb, "label", L["MINIMUMBID"]..":", "LEFT")
  f.MinBidHeader:SetPoint("LEFT", yb, "TOPLEFT", W.PAD, -14);

  f.MinBid = W.CreateText(yb, "body", nil, "LEFT")
  f.MinBid:SetPoint("LEFT", f.MinBidHeader, "RIGHT", 6, 0);

  if mode == "Minimum Bid Values" or (mode == "Zero Sum" and core.DB.modes.ZeroSumBidType == "Minimum Bid") then
    f.MaxBidHeader = W.CreateText(yb, "label", L["MAXIMUMBID"]..":", "LEFT")
    f.MaxBidHeader:SetPoint("LEFT", yb, "TOPLEFT", 180, -14);

    f.MaxBid = W.CreateText(yb, "body", nil, "LEFT")
    f.MaxBid:SetPoint("LEFT", f.MaxBidHeader, "RIGHT", 6, 0);
  end

  -- Action row 1: Bid label + the always-boxed Bid input (76, right-aligned) + +1 / +5 / HALF / MAX (52 each, 6 gap)
  f.BidHeader = W.CreateText(yb, "label", L["BID"], "LEFT")
  f.BidHeader:SetPoint("LEFT", yb, "TOPLEFT", W.PAD, -45);

  f.Bid = CreateFrame("EditBox", nil, yb, "BackdropTemplate")
  f.Bid:SetPoint("TOPLEFT", yb, "TOPLEFT", 40, -34)
  f.Bid:SetAutoFocus(false)
  f.Bid:SetMultiLine(false)
  f.Bid:SetSize(76, W.H)
  f.Bid:SetMaxLetters(8)
  f.Bid:SetScript("OnEscapePressed", function(self)    -- clears focus on esc
    self:ClearFocus()
  end)
  W.StyleEditBox(f.Bid, { numeric = true })

  -- The step buttons stay children of f.Bid (they hide with it in Roll / Static modes, as today).
  f.BidPlusOne = CreateFrame("Button", nil, f.Bid, "CommunityDKPButtonTemplate")
  f.BidPlusOne:SetPoint("LEFT", f.Bid, "RIGHT", 8, 0);
  f.BidPlusOne:SetSize(52, W.H)
  f.BidPlusOne:SetText("+1");
  W.StyleButton(f.BidPlusOne)
  f.BidPlusOne:SetScript("OnClick", function()
    f.Bid:SetNumber(f.Bid:GetNumber() + 1);
  end)

  f.BidPlusFive = CreateFrame("Button", nil, f.Bid, "CommunityDKPButtonTemplate")
  f.BidPlusFive:SetPoint("LEFT", f.BidPlusOne, "RIGHT", 6, 0);
  f.BidPlusFive:SetSize(52, W.H)
  f.BidPlusFive:SetText("+5");
  W.StyleButton(f.BidPlusFive)
  f.BidPlusFive:SetScript("OnClick", function()
    f.Bid:SetNumber(f.Bid:GetNumber() + 5);
  end)

  f.BidMax = CreateFrame("Button", nil, f.BidPlusFive, "CommunityDKPButtonTemplate")
  f.BidMax:SetPoint("LEFT", f.BidPlusFive, "RIGHT", 64, 0);
  f.BidMax:SetSize(52, W.H)
  f.BidMax:SetText("MAX");
  W.StyleButton(f.BidMax)
  f.BidMax:SetScript("OnClick", function()
    local behavior = core.DB.modes.MaxBehavior
    local itemValue = 0
    if mode == "Minimum Bid Values" or (mode == "Zero Sum" and core.DB.modes.ZeroSumBidType == "Minimum Bid") then
      local value, text = strsplit(" ", f.MaxBid:GetText())
      itemValue = tonumber(value)
    else
      behavior = "Max DKP"
    end

    local dkp = 0
    local search = CommDKP:Table_Search(CommDKP:GetTable(CommDKP_DKPTable, true), CommDKP:GetPlayerName(), "player")
    if search then
      dkp = CommDKP:GetTable(CommDKP_DKPTable, true)[search[1][1]].dkp;
    end

    if behavior == "Max DKP" or itemValue == 0  then
      f.Bid:SetNumber(dkp);
    elseif behavior == "Max Item Value" then
      f.Bid:SetNumber(itemValue);
    elseif behavior == "Min(Max DKP, Max Item Value)" then
      if dkp < itemValue then
        f.Bid:SetNumber(dkp)
      else
        f.Bid:SetNumber(itemValue);
      end
    else
      f.Bid:SetNumber(dkp);
    end
  end)

  f.BidHalf = CreateFrame("Button", nil, f.BidPlusOne, "CommunityDKPButtonTemplate")
  f.BidHalf:SetPoint("LEFT", f.BidPlusFive, "RIGHT", 6, 0);
  f.BidHalf:SetSize(52, W.H)
  f.BidHalf:SetText("HALF");
  W.StyleButton(f.BidHalf)
  f.BidHalf:SetScript("OnClick", function()
    local behavior = core.DB.modes.MaxBehavior
    local itemValue = 0
    if mode == "Minimum Bid Values" or (mode == "Zero Sum" and core.DB.modes.ZeroSumBidType == "Minimum Bid") then
      local value, text = strsplit(" ", f.MaxBid:GetText())
      itemValue = tonumber(value)
    else
      behavior = "Max DKP"
    end

    local dkp = 0
    local search = CommDKP:Table_Search(CommDKP:GetTable(CommDKP_DKPTable, true), CommDKP:GetPlayerName(), "player")
    if search then
      dkp = CommDKP:GetTable(CommDKP_DKPTable, true)[search[1][1]].dkp;
    end

    if behavior == "Max DKP" or itemValue == 0  then
      f.Bid:SetNumber(dkp/2);
    elseif behavior == "Max Item Value" then
      f.Bid:SetNumber(itemValue/2);
    elseif behavior == "Min(Max DKP, Max Item Value)" then
      if dkp < itemValue then
        f.Bid:SetNumber(dkp/2)
      else
        f.Bid:SetNumber(itemValue/2);
      end
    else
      f.Bid:SetNumber(dkp/2)
    end
  end)

  -- Action row 2: Submit (primary) · Cancel · Pass, three equal widths on one baseline and style (AC-9.9)
    f.SubmitBid = CreateFrame("Button", nil, yb, "CommunityDKPButtonTemplate")
  f.SubmitBid:SetPoint("TOPLEFT", yb, "TOPLEFT", W.PAD, -64);
  f.SubmitBid:SetSize(110, W.H)
  f.SubmitBid:SetText(L["SUBMITBID"]);
  W.StyleButton(f.SubmitBid, "primary")

  f.CancelBid = CreateFrame("Button", nil, yb, "CommunityDKPButtonTemplate")
  f.CancelBid:SetPoint("LEFT", f.SubmitBid, "RIGHT", 6, 0);
  f.CancelBid:SetSize(110, W.H)
  f.CancelBid:SetText(L["CANCELBID"]);
  W.StyleButton(f.CancelBid)
  f.CancelBid:SetScript("OnClick", CancelBid_OnClick)   -- AD-13.5

  f.Pass = CreateFrame("Button", nil, yb, "CommunityDKPButtonTemplate")
  f.Pass:SetPoint("LEFT", f.CancelBid, "RIGHT", 6, 0);
  f.Pass:SetSize(110, W.H)
  f.Pass:SetText(L["PASS"]);
  W.StyleButton(f.Pass)
  f.Pass:SetScript("OnClick", function()
    if BiddingLocked() then return end
    f.Bid:ClearFocus();
    CommDKP.Sync:SendData("CommDKPBidder", "pass")
    core.BidInterface:Hide()
  end)

  if core.DB.defaults.AutoOpenBid == nil then
    core.DB.defaults.AutoOpenBid = true
  end

  -- Footer: Auto Open Bid Window at BOTTOMLEFT of the content area
  f.AutoOpenCheckbox = W.CreateCheckbox(content, nil, L["AUTOOPEN"]);
  f.AutoOpenCheckbox:SetChecked(core.DB.defaults.AutoOpenBid)
  f.AutoOpenCheckbox:SetPoint("BOTTOMLEFT", content, "BOTTOMLEFT", 0, 2)
  f.AutoOpenCheckbox:SetScript("OnClick", function(self)
    core.DB.defaults.AutoOpenBid = self:GetChecked()
  end)
  f.AutoOpenCheckbox:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_LEFT");
    GameTooltip:SetText(L["AUTOOPEN"], 0.25, 0.75, 0.90, 1, true);
    GameTooltip:AddLine(L["AUTOOPENTTDESC"], 1.0, 1.0, 1.0, true);
    GameTooltip:Show();
  end)
  f.AutoOpenCheckbox:SetScript("OnLeave", function(self)
    GameTooltip:Hide()
  end)


  --------------------------------------------------
  -- Bids card (y 262, to -44 from the frame bottom): column strip + faux rows + thin rail
  --------------------------------------------------
  f.BidsCard = W.CreateCard(content, L["BIDS"], 376, 220)
  f.BidsCard:SetPoint("TOPLEFT", f.YourBidCard, "BOTTOMLEFT", 0, -8)
  local bc = f.BidsCard.Body

  f.bidTable = CreateFrame("ScrollFrame", "CommDKP_BiderWindowTable", bc, "FauxScrollFrameTemplate")
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
    FauxScrollFrame_OnVerticalScroll(self, offset, height, CommDKP_BidInterface_Update)
  end)

  -- The Bids card follows the table's visibility (bid broadcasting on/off, BidInProgress), which the logic drives
  -- through bidTable:Show/Hide/SetShown; bidTable:IsShown() keeps its own meaning.
  local function SyncBidsCard() f.BidsCard:SetShown(f.bidTable:IsShown()) end
  hooksecurefunc(f.bidTable, "Show", SyncBidsCard)
  hooksecurefunc(f.bidTable, "Hide", SyncBidsCard)
  hooksecurefunc(f.bidTable, "SetShown", SyncBidsCard)

  ---------------------------------------
  -- Header Buttons
  ---------------------------------------
  f.headerButtons = {}
  mode = core.DB.modes.mode;

  f.BidTable_Headers = W.CreateColumnStrip(bc, 20, "CommDKPBidderTableHeaders")
  f.BidTable_Headers:SetPoint("TOPLEFT", bc, "TOPLEFT", 0, 0)
  f.BidTable_Headers:SetPoint("TOPRIGHT", bc, "TOPRIGHT", 0, 0)
  f.bidTable:SetPoint("TOPLEFT", bc, "TOPLEFT", 4, -22)
  f.BidTable_Headers:Show()
  W.AttachFauxRail(f.bidTable, bc)

  f.headerButtons.player = CreateFrame("Button", "$ParentButtonPlayer", f.BidTable_Headers)
  f.headerButtons.bid = CreateFrame("Button", "$ParentButtonBid", f.BidTable_Headers)
  f.headerButtons.dkp = CreateFrame("Button", "$ParentSuttonDkp", f.BidTable_Headers)

  f.headerButtons.player:SetPoint("LEFT", f.BidTable_Headers, "LEFT", 4, 0)
  f.headerButtons.bid:SetPoint("LEFT", f.headerButtons.player, "RIGHT", 0, 0)
  f.headerButtons.dkp:SetPoint("LEFT", f.headerButtons.bid, "RIGHT", 0, 0)

  f.headerButtons.player.t = W.CreateText(f.headerButtons.player, "label", L["PLAYER"], "LEFT")
  f.headerButtons.player.t:SetPoint("LEFT", f.headerButtons.player, "LEFT", 20, 0);

  f.headerButtons.bid.t = W.CreateText(f.headerButtons.bid, "label", nil, "CENTER")
  f.headerButtons.bid.t:SetPoint("CENTER", f.headerButtons.bid, "CENTER", 0, 0);

  f.headerButtons.dkp.t = W.CreateText(f.headerButtons.dkp, "label", nil, "CENTER")
  f.headerButtons.dkp.t:SetPoint("CENTER", f.headerButtons.dkp, "CENTER", 0, 0);

  if not core.DB.modes.BroadcastBids then
    f.bidTable:Hide();
    f:SetHeight(BIDINT_HEIGHT(true));
  end;     --hides table if broadcasting is set to false.
  SyncBidsCard()

  f:Hide();

  f:HookScript("OnHide", function ()   -- HookScript: keeps the floater registry hooks (§10.1.3)
    if core.BiddingInProgress then
      CommDKP:Print(L["CLOSEDBIDINPROGRESS"])
    end
    if CommDKP.BidTimer:IsShown() then
      CommDKP.BidTimer.OpenBid:Show()
    end
  end)

  return f;
end
