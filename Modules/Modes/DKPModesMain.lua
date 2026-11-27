local _, core = ...;
local _G = _G;
local CommDKP = core.CommDKP;
local L = core.L;

local DD = CommDKP.DD                     -- AD-16.3: selector protocol (the 8 DKP Modes selectors)
local W = CommDKP.Widgets

-- UX §12.4.4 Modes pane: 4 cards, 456 wide (the pane's right 10 px lane holds the rail), two field columns of 205
-- with a 16 px gutter; labels sit above their field. A hidden field leaves its grid cell empty (no reflow).
local CARD_W, COL1, COL2, FIELD_W = 456, 12, 233, 205

function CommDKP:DKPModes_Main()
  local f = core.ModesWindow;

  f.DKPModesMain.ModeCard = W.CreateCard(f.DKPModesMain, L["CARDMODE"], CARD_W, 130)
  f.DKPModesMain.ModeCard:SetPoint("TOPLEFT", f.DKPModesMain, "TOPLEFT", 0, 0)
  f.DKPModesMain.CostCard = W.CreateCard(f.DKPModesMain, L["CARDCOSTRULES"], CARD_W, 131)
  f.DKPModesMain.CostCard:SetPoint("TOPLEFT", f.DKPModesMain.ModeCard, "BOTTOMLEFT", 0, -8)
  f.DKPModesMain.BidCard = W.CreateCard(f.DKPModesMain, L["CARDBIDRULES"], CARD_W, 161)
  f.DKPModesMain.BidCard:SetPoint("TOPLEFT", f.DKPModesMain.CostCard, "BOTTOMLEFT", 0, -8)
  local modeBody, costBody, bidBody = f.DKPModesMain.ModeCard.Body, f.DKPModesMain.CostCard.Body, f.DKPModesMain.BidCard.Body

  -- §12.4.4: the legacy large heading duplicated the dropdown's text and is removed. The FontString stays (hidden)
  -- because ModesDropDown:SetValue still writes it.
  f.DKPModesMain.ModeDescriptionHeader = W.CreateText(modeBody, "heading", nil, "LEFT")
  f.DKPModesMain.ModeDescriptionHeader:Hide()

  f.DKPModesMain.ModeDescription = W.CreateCaption(modeBody, nil, 4)
  f.DKPModesMain.ModeDescription:SetPoint("TOPLEFT", modeBody, "TOPLEFT", COL1, -52);
  f.DKPModesMain.ModeDescription:SetWidth(CARD_W - 6 - 2 * W.PAD);

  local MinBidDescription = L["MINBIDDESCRIPTION"]
  local StaticDescription = L["STATICDESCRIPTION"]
  local RollDescription = L["ROLLDESCRIPTION"]
  local ZeroSumDescription = L["ZEROSUMDESCRIPTION"];

  if core.DB.modes.mode == "Minimum Bid Values" then
    f.DKPModesMain.ModeDescriptionHeader:SetText(L["MINBIDVALUESHEAD"])
    f.DKPModesMain.ModeDescription:SetText(MinBidDescription)
  elseif core.DB.modes.mode == "Static Item Values" then
    f.DKPModesMain.ModeDescriptionHeader:SetText(L["STATICITEMVALUESHEAD"])
    f.DKPModesMain.ModeDescription:SetText(StaticDescription)
  elseif core.DB.modes.mode == "Roll Based Bidding" then
    f.DKPModesMain.ModeDescriptionHeader:SetText(L["ROLLBIDDINGHEAD"])
    f.DKPModesMain.ModeDescription:SetText(RollDescription)
  elseif core.DB.modes.mode == "Zero Sum" then
    f.DKPModesMain.ModeDescriptionHeader:SetText(L["ZEROSUMHEAD"])
    f.DKPModesMain.ModeDescription:SetText(ZeroSumDescription)
  end

  -- Mode DROPDOWN box 
  local CurMode = core.DB.modes.mode;
  local LocalMode;

  if CurMode == "Minimum Bid Values" then
    LocalMode = L["MINBIDVALUESHEAD"];
  elseif CurMode == "Static Item Values" then
    LocalMode = L["STATICITEMVALUESHEAD"]
  elseif CurMode == "Roll Based Bidding" then
    LocalMode = L["ROLLBIDDINGHEAD"]
  elseif CurMode == "Zero Sum" then
    LocalMode = L["ZEROSUMHEAD"]
  end


  f.DKPModesMain.ModesDropDown = DD:Create_UIDropDownMenu("CommDKPModeSelectDropDown", modeBody);

  -- Create and bind the initialization function to the dropdown menu
    DD:UIDropDownMenu_Initialize(f.DKPModesMain.ModesDropDown, function(self, level, menuList)
    
  local DKPMode = DD:UIDropDownMenu_CreateInfo()
    DKPMode.func = self.SetValue
    DKPMode.text, DKPMode.arg1, DKPMode.checked, DKPMode.isNotRadio = L["MINBIDVALUESHEAD"], "Minimum Bid Values", "Minimum Bid Values" == CurMode, false
    DD:UIDropDownMenu_AddButton(DKPMode)
    DKPMode.text, DKPMode.arg1, DKPMode.checked, DKPMode.isNotRadio = L["STATICITEMVALUESHEAD"], "Static Item Values", "Static Item Values" == CurMode, false
    DD:UIDropDownMenu_AddButton(DKPMode)
    DKPMode.text, DKPMode.arg1, DKPMode.checked, DKPMode.isNotRadio = L["ROLLBIDDINGHEAD"], "Roll Based Bidding", "Roll Based Bidding" == CurMode, false
    DD:UIDropDownMenu_AddButton(DKPMode)
    DKPMode.text, DKPMode.arg1, DKPMode.checked, DKPMode.isNotRadio = L["ZEROSUMHEAD"], "Zero Sum", "Zero Sum" == CurMode, false
    DD:UIDropDownMenu_AddButton(DKPMode)
  end)

  f.DKPModesMain.ModesDropDown:SetPoint("TOPLEFT", modeBody, "TOPLEFT", COL1, -22)
  DD:UIDropDownMenu_SetWidth(f.DKPModesMain.ModesDropDown, 220)
  DD:UIDropDownMenu_SetText(f.DKPModesMain.ModesDropDown, LocalMode)

  -- Dropdown Menu Function
  function f.DKPModesMain.ModesDropDown:SetValue(newValue)
    if curMode ~= newValue then CurMode = newValue end

    f.DKPModesMain.ModeDescriptionHeader:SetText(newValue)
    
    if newValue == "Minimum Bid Values" then
      core.DB.modes.mode = "Minimum Bid Values";
      f.DKPModesMain.ModeDescription:SetText(MinBidDescription)
      f.DKPModesMain.ItemCostDropDown:Hide();
      f.DKPModesMain.ItemCostHeader:Hide();
      f.DKPModesMain.MaxBidBehaviorDropDown:Show();
      f.DKPModesMain.MaxBidBehaviorHeader:Show();
      core.DB.modes.costvalue = "Integer";
      DD:UIDropDownMenu_SetText(f.DKPModesMain.ItemCostDropDown, "Integer")
      f.DKPModesMain.SubZeroBidding:Show();
      f.DKPModesMain.SubZeroBidding:SetChecked(core.DB.modes.SubZeroBidding)
      if core.DB.modes.SubZeroBidding == true then
        f.DKPModesMain.AllowNegativeBidders:Show()
        f.DKPModesMain.AllowNegativeBidders:SetChecked(core.DB.modes.AllowNegativeBidders)
      end
      f.DKPModesMain.RollContainer:Hide();
      f.DKPModesMain.ZeroSumType:Hide();
      f.DKPModesMain.ZeroSumTypeHeader:Hide();
      f.DKPModesMain.CostSelection:Show();
      f.DKPModesMain.CostSelectionHeader:Show();
      f.DKPModesMain.Inflation:Hide()
        f.DKPModesMain.Inflation.Header:Hide()
    elseif newValue == "Static Item Values" then
      core.DB.modes.mode = "Static Item Values"
      f.DKPModesMain.ModeDescription:SetText(StaticDescription)
      f.DKPModesMain.ItemCostHeader:Show();
      f.DKPModesMain.ItemCostDropDown:Show();
      f.DKPModesMain.MaxBidBehaviorDropDown:Hide();
      f.DKPModesMain.MaxBidBehaviorHeader:Hide();
      core.DB.modes.MaxBehavior = "Max DKP";
      DD:UIDropDownMenu_SetText(f.DKPModesMain.MaxBidBehaviorDropDown, "Max DKP")
      f.DKPModesMain.RollContainer:Hide()
      f.DKPModesMain.ZeroSumType:Hide()
      f.DKPModesMain.ZeroSumTypeHeader:Hide();
      f.DKPModesMain.CostSelection:Hide();
      f.DKPModesMain.CostSelectionHeader:Hide();
      f.DKPModesMain.Inflation:Hide()
      f.DKPModesMain.Inflation.Header:Hide()

      if core.DB.modes.costvalue == "Integer" then
        f.DKPModesMain.SubZeroBidding:Show()
        f.DKPModesMain.SubZeroBidding:SetChecked(core.DB.modes.SubZeroBidding)
        if core.DB.modes.SubZeroBidding == true then
          f.DKPModesMain.AllowNegativeBidders:Show()
          f.DKPModesMain.AllowNegativeBidders:SetChecked(core.DB.modes.AllowNegativeBidders)
        end
        DD:UIDropDownMenu_SetText(f.DKPModesMain.ItemCostDropDown, L["INTEGER"])
      else
        f.DKPModesMain.SubZeroBidding:Hide()
        f.DKPModesMain.AllowNegativeBidders:Hide()
        DD:UIDropDownMenu_SetText(f.DKPModesMain.ItemCostDropDown, L["PERCENT"])
      end
    elseif newValue == "Roll Based Bidding" then
      core.DB.modes.mode = "Roll Based Bidding"
      f.DKPModesMain.ItemCostHeader:Show();
      f.DKPModesMain.ItemCostDropDown:Show();
      f.DKPModesMain.MaxBidBehaviorDropDown:Hide();
      f.DKPModesMain.MaxBidBehaviorHeader:Hide();
      core.DB.modes.MaxBehavior = "Max DKP";
      DD:UIDropDownMenu_SetText(f.DKPModesMain.MaxBidBehaviorDropDown, "Max DKP")
      f.DKPModesMain.ModeDescription:SetText(RollDescription)
      f.DKPModesMain.RollContainer:Show()
      f.DKPModesMain.ZeroSumType:Hide()
      f.DKPModesMain.ZeroSumTypeHeader:Hide();
      f.DKPModesMain.CostSelection:Hide()
      f.DKPModesMain.CostSelectionHeader:Hide()
      f.DKPModesMain.Inflation:Hide()
        f.DKPModesMain.Inflation.Header:Hide()

      if core.DB.modes.costvalue == "Integer" then
        f.DKPModesMain.SubZeroBidding:Show()
        f.DKPModesMain.SubZeroBidding:SetChecked(core.DB.modes.SubZeroBidding)
        if core.DB.modes.SubZeroBidding == true then
          f.DKPModesMain.AllowNegativeBidders:Show()
          f.DKPModesMain.AllowNegativeBidders:SetChecked(core.DB.modes.AllowNegativeBidders)
        end
        DD:UIDropDownMenu_SetText(f.DKPModesMain.ItemCostDropDown, "Integer")
      end
    elseif newValue == "Zero Sum" then
      core.DB.modes.mode = "Zero Sum"
      core.DB.modes.costvalue = "Integer"
      f.DKPModesMain.ModeDescription:SetText(ZeroSumDescription)
      f.DKPModesMain.SubZeroBidding:Hide()
      f.DKPModesMain.AllowNegativeBidders:Hide()
      f.DKPModesMain.RollContainer:Hide()
      f.DKPModesMain.ItemCostHeader:Hide();
      DD:UIDropDownMenu_SetText(f.DKPModesMain.ItemCostDropDown, "Integer")
      f.DKPModesMain.ItemCostDropDown:Hide();
      f.DKPModesMain.ZeroSumType:Show()
      f.DKPModesMain.ZeroSumTypeHeader:Show();
      core.DB.modes.SubZeroBidding = true
      f.DKPModesMain.Inflation:Show()
        f.DKPModesMain.Inflation.Header:Show()

      if core.DB.modes.ZeroSumBidType == "Static" then
        f.DKPModesMain.MaxBidBehaviorDropDown:Hide();
        f.DKPModesMain.MaxBidBehaviorHeader:Hide();
        core.DB.modes.MaxBehavior = "Max DKP";
        DD:UIDropDownMenu_SetText(f.DKPModesMain.MaxBidBehaviorDropDown, "Max DKP")
        f.DKPModesMain.CostSelection:Hide()
        f.DKPModesMain.CostSelectionHeader:Hide()
      else
        f.DKPModesMain.MaxBidBehaviorDropDown:Show();
        f.DKPModesMain.MaxBidBehaviorHeader:Show();
        f.DKPModesMain.CostSelection:Show()
        f.DKPModesMain.CostSelectionHeader:Show()
        f.DKPModesMain.SubZeroBidding:Show()
        f.DKPModesMain.AllowNegativeBidders:Show()
      end
    end
    if f.DKPModesMain.LayoutModesMain then f.DKPModesMain.LayoutModesMain() end   -- AD-21.2 (BR-14.1.3)

    if CurMode == "Minimum Bid Values" then
      LocalMode = L["MINBIDVALUESHEAD"];
    elseif CurMode == "Static Item Values" then
      LocalMode = L["STATICITEMVALUESHEAD"]
    elseif CurMode == "Roll Based Bidding" then
      LocalMode = L["ROLLBIDDINGHEAD"]
    elseif CurMode == "Zero Sum" then
      LocalMode = L["ZEROSUMHEAD"]
    end

    DD:UIDropDownMenu_SetText(f.DKPModesMain.ModesDropDown, LocalMode)
    DD:CloseDropDownMenus()
  end

  f.DKPModesMain.ModesDropDown:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT");
    GameTooltip:SetText(L["DKPMODES"], 0.25, 0.75, 0.90, 1, true);
    GameTooltip:AddLine(L["DKPMODESTTDESC"], 1.0, 1.0, 1.0, true);
    GameTooltip:Show();
  end)
  f.DKPModesMain.ModesDropDown:SetScript("OnLeave", function(self)
    GameTooltip:Hide()
  end)

  f.DKPModesMain.ModeHeader = W.CreateText(modeBody, "label", L["DKPMODES"], "LEFT")
  f.DKPModesMain.ModeHeader:SetPoint("BOTTOMLEFT", f.DKPModesMain.ModesDropDown, "TOPLEFT", 0, 3);

  -- Rounding DROPDOWN box 
  f.DKPModesMain.RoundDropDown = DD:Create_UIDropDownMenu("CommDKPModeSelectDropDown", costBody);

  -- Create and bind the initialization function to the dropdown menu
    DD:UIDropDownMenu_Initialize(f.DKPModesMain.RoundDropDown, function(self, level, menuList)
    
  local places = DD:UIDropDownMenu_CreateInfo()
    places.func = self.SetValue
    places.text, places.arg1, places.checked, places.isNotRadio = 0, 0, 0 == core.DB.modes.rounding, false
    DD:UIDropDownMenu_AddButton(places)
    places.text, places.arg1, places.checked, places.isNotRadio = 1, 1, 1 == core.DB.modes.rounding, false
    DD:UIDropDownMenu_AddButton(places)
    places.text, places.arg1, places.checked, places.isNotRadio = 2, 2, 2 == core.DB.modes.rounding, false
    DD:UIDropDownMenu_AddButton(places)
    places.text, places.arg1, places.checked, places.isNotRadio = 3, 3, 3 == core.DB.modes.rounding, false
    DD:UIDropDownMenu_AddButton(places)
    places.text, places.arg1, places.checked, places.isNotRadio = 4, 4, 4 == core.DB.modes.rounding, false
    DD:UIDropDownMenu_AddButton(places)
  end)

  f.DKPModesMain.RoundDropDown:SetPoint("TOPLEFT", costBody, "TOPLEFT", COL1, -70)
  DD:UIDropDownMenu_SetWidth(f.DKPModesMain.RoundDropDown, FIELD_W)
  DD:UIDropDownMenu_SetText(f.DKPModesMain.RoundDropDown, core.DB.modes.rounding)

  -- Dropdown Menu Function
  function f.DKPModesMain.RoundDropDown:SetValue(newValue)
    core.DB.modes.rounding = newValue;
    DD:UIDropDownMenu_SetText(f.DKPModesMain.RoundDropDown, newValue)
    DD:CloseDropDownMenus()
  end

  f.DKPModesMain.RoundDropDown:SetScript("OnLeave", function(self)
    GameTooltip:Hide()
  end)
  f.DKPModesMain.RoundDropDown:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT");
    GameTooltip:SetText(L["DKPROUNDING"], 0.25, 0.75, 0.90, 1, true);
    GameTooltip:AddLine(L["DKPROUNDINGTTDESC"], 1.0, 1.0, 1.0, true);
    GameTooltip:Show();
  end)
    f.DKPModesMain.RoundDropDown:SetScript("OnLeave", function(self)
      GameTooltip:Hide()
    end)

  f.DKPModesMain.RoundHeader = W.CreateText(costBody, "label", L["DKPROUNDING"], "LEFT")
  f.DKPModesMain.RoundHeader:SetPoint("BOTTOMLEFT", f.DKPModesMain.RoundDropDown, "TOPLEFT", 0, 3);

  -- MAX Bid button behavior
  f.DKPModesMain.MaxBidBehaviorDropDown = DD:Create_UIDropDownMenu("CommDKPModeSelectDropDown", bidBody);

  -- Create and bind the initialization function to the dropdown menu
    DD:UIDropDownMenu_Initialize(f.DKPModesMain.MaxBidBehaviorDropDown, function(self, level, menuList)
    
  local MaxBehavior = DD:UIDropDownMenu_CreateInfo()
    MaxBehavior.func = self.SetValue
    MaxBehavior.text, MaxBehavior.arg1, MaxBehavior.checked, MaxBehavior.isNotRadio = L["MAXBIDBEHAVIORMAXDKP"], "Max DKP", "Max DKP" == core.DB.modes.MaxBehavior, false
    DD:UIDropDownMenu_AddButton(MaxBehavior)
    MaxBehavior.text, MaxBehavior.arg1, MaxBehavior.checked, MaxBehavior.isNotRadio = L["MAXBIDBEHAVIORMAXITEMVALUE"], "Max Item Value", "Max Item Value" == core.DB.modes.MaxBehavior, false
    DD:UIDropDownMenu_AddButton(MaxBehavior)
    MaxBehavior.text, MaxBehavior.arg1, MaxBehavior.checked, MaxBehavior.isNotRadio = L["MAXBIDBEHAVIORMIN"], "Min(Max DKP, Max Item Value)", "Min(Max DKP, Max Item Value)" == core.DB.modes.MaxBehavior, false
    DD:UIDropDownMenu_AddButton(MaxBehavior)
  end)

  f.DKPModesMain.MaxBidBehaviorDropDown:SetPoint("TOPLEFT", bidBody, "TOPLEFT", COL1, -22)
  -- AD-32.2.2 (CDKP-024, BR-24.3a): "Min(Max DKP, Max Item Value)" needs ~182 px of label; widen into the COL1 gutter
  -- up to W.GUT (8 px) before COL2: 233 - 12 - 8 = 213 -> 188 px of label. Header anchors to TOPLEFT (unchanged).
  DD:UIDropDownMenu_SetWidth(f.DKPModesMain.MaxBidBehaviorDropDown, COL2 - COL1 - W.GUT)
  DD:UIDropDownMenu_SetText(f.DKPModesMain.MaxBidBehaviorDropDown, core.DB.modes.MaxBehavior)

  -- Dropdown Menu Function
  function f.DKPModesMain.MaxBidBehaviorDropDown:SetValue(newValue)
    core.DB.modes.MaxBehavior = newValue;
    if newValue == "Max DKP" then
      DD:UIDropDownMenu_SetText(f.DKPModesMain.MaxBidBehaviorDropDown, L["MAXBIDBEHAVIORMAXDKP"])
    elseif newValue == "Max Item Value" then
      DD:UIDropDownMenu_SetText(f.DKPModesMain.MaxBidBehaviorDropDown, L["MAXBIDBEHAVIORMAXITEMVALUE"])
    else
      DD:UIDropDownMenu_SetText(f.DKPModesMain.MaxBidBehaviorDropDown, L["MAXBIDBEHAVIORMIN"])
    end
    DD:CloseDropDownMenus()
  end

  f.DKPModesMain.MaxBidBehaviorDropDown:SetScript("OnLeave", function(self)
    GameTooltip:Hide()
  end)

  f.DKPModesMain.MaxBidBehaviorDropDown:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT");
    GameTooltip:SetText(L["MAXBIDBEHAVIOR"], 0.25, 0.75, 0.90, 1, true);
    GameTooltip:AddLine(L["MAXBIDBEHAVIORTTDESC"], 1.0, 1.0, 1.0, true);
    GameTooltip:Show();
  end)
    f.DKPModesMain.MaxBidBehaviorDropDown:SetScript("OnLeave", function(self)
      GameTooltip:Hide()
    end)
  
  f.DKPModesMain.MaxBidBehaviorHeader = W.CreateText(bidBody, "label", L["MAXBIDBEHAVIOR"], "LEFT")
  f.DKPModesMain.MaxBidBehaviorHeader:SetPoint("BOTTOMLEFT", f.DKPModesMain.MaxBidBehaviorDropDown, "TOPLEFT", 0, 3);

  -- AntiSnipe Option

    f.DKPModesMain.AntiSnipe = CreateFrame("EditBox", nil, bidBody, "BackdropTemplate")
  
    f.DKPModesMain.AntiSnipe:SetAutoFocus(false)
    f.DKPModesMain.AntiSnipe:SetMultiLine(false)
    f.DKPModesMain.AntiSnipe:SetPoint("TOPLEFT", bidBody, "TOPLEFT", COL2, -70)
    f.DKPModesMain.AntiSnipe:SetSize(70, W.H)
    f.DKPModesMain.AntiSnipe:SetMaxLetters(8)
f.DKPModesMain.AntiSnipe:SetText(core.DB.modes.AntiSnipe)
    f.DKPModesMain.AntiSnipe:SetScript("OnEscapePressed", function(self)    -- clears focus on esc
      core.DB.modes.AntiSnipe = f.DKPModesMain.AntiSnipe:GetNumber()
      self:ClearFocus()
    end)
    f.DKPModesMain.AntiSnipe:SetScript("OnTabPressed", function(self)    -- clears focus on esc
      core.DB.modes.AntiSnipe = f.DKPModesMain.AntiSnipe:GetNumber()
      self:ClearFocus()
    end)
    f.DKPModesMain.AntiSnipe:SetScript("OnEnterPressed", function(self)    -- clears focus on esc
      core.DB.modes.AntiSnipe = f.DKPModesMain.AntiSnipe:GetNumber()
      self:ClearFocus()
    end)
    f.DKPModesMain.AntiSnipe:SetScript("OnKeyUp", function(self)    -- clears focus on esc
      if f.DKPModesMain.AntiSnipe:GetText():match("%a+") then
        f.DKPModesMain.AntiSnipe:SetNumber(f.DKPModesMain.AntiSnipe:GetNumber() or 0)
        if f.DKPModesMain.AntiSnipe:GetText() == "0" then
          f.DKPModesMain.AntiSnipe:HighlightText()
        end
      else
        core.DB.modes.AntiSnipe = f.DKPModesMain.AntiSnipe:GetNumber()
      end
    end)
    f.DKPModesMain.AntiSnipe:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT");
    GameTooltip:SetText(L["ANTISNIPE"], 0.25, 0.75, 0.90, 1, true);
    GameTooltip:AddLine(L["ANTISNIPETTDESC"], 1.0, 1.0, 1.0, true);
    GameTooltip:AddLine(L["ANTISNIPETTWARN"], 1.0, 0, 0, true);
    GameTooltip:Show();
  end)
    f.DKPModesMain.AntiSnipe:SetScript("OnLeave", function(self)
      GameTooltip:Hide()
    end)
    W.StyleEditBox(f.DKPModesMain.AntiSnipe, { numeric = true })

    f.DKPModesMain.AntiSnipe.Header = W.CreateText(f.DKPModesMain.AntiSnipe, "label", L["ANTISNIPE"], "LEFT")
    f.DKPModesMain.AntiSnipe.Header:SetPoint("BOTTOMLEFT", f.DKPModesMain.AntiSnipe, "TOPLEFT", 0, 3);

  -- Channels DROPDOWN box 
  f.DKPModesMain.ChannelsDropDown = DD:Create_UIDropDownMenu("CommDKPModeSelectDropDown", bidBody);

  -- Create and bind the initialization function to the dropdown menu
    DD:UIDropDownMenu_Initialize(f.DKPModesMain.ChannelsDropDown, function(self, level, menuList)
    
  local OpenChannel = DD:UIDropDownMenu_CreateInfo()
    OpenChannel.func = self.SetValue
    OpenChannel.keepShownOnClick = true;
    OpenChannel.isNotRadio = true;
    OpenChannel.text, OpenChannel.arg1, OpenChannel.checked = L["WHISPER"], "Whisper", true == core.DB.modes.channels.whisper
    DD:UIDropDownMenu_AddButton(OpenChannel)
    OpenChannel.text, OpenChannel.arg1, OpenChannel.checked = L["RAID"], "Raid", true == core.DB.modes.channels.raid
    DD:UIDropDownMenu_AddButton(OpenChannel)
    OpenChannel.text, OpenChannel.arg1, OpenChannel.checked = L["GUILD"], "Guild", true == core.DB.modes.channels.guild
    DD:UIDropDownMenu_AddButton(OpenChannel)
  end)

  f.DKPModesMain.ChannelsDropDown:SetPoint("TOPLEFT", bidBody, "TOPLEFT", COL1, -70)
  DD:UIDropDownMenu_SetWidth(f.DKPModesMain.ChannelsDropDown, FIELD_W)
  DD:UIDropDownMenu_SetText(f.DKPModesMain.ChannelsDropDown, L["OPENCHANNELS"])

  -- Dropdown Menu Function
  function f.DKPModesMain.ChannelsDropDown:SetValue(arg1)
    if arg1 == "Whisper" then
      core.DB.modes.channels.whisper = not core.DB.modes.channels.whisper
    elseif arg1 == "Raid" then
      core.DB.modes.channels.raid = not core.DB.modes.channels.raid
    elseif arg1 == "Guild" then
      core.DB.modes.channels.guild = not core.DB.modes.channels.guild
    end

    DD:UIDropDownMenu_SetText(f.DKPModesMain.ChannelsDropDown, "Open Channels")
    DD:CloseDropDownMenus()
  end

  f.DKPModesMain.ChannelsDropDown:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT");
    GameTooltip:SetText(L["COMMANDCHANNELS"], 0.25, 0.75, 0.90, 1, true);
    GameTooltip:AddLine(L["COMMANDCHANNELSTTDESC"], 1.0, 1.0, 1.0, true);
    GameTooltip:Show();
  end)
  f.DKPModesMain.ChannelsDropDown:SetScript("OnLeave", function(self)
    GameTooltip:Hide()
  end)

  f.DKPModesMain.ChannelsHeader = W.CreateText(bidBody, "label", L["COMMANDCHANNELS"], "LEFT")
  f.DKPModesMain.ChannelsHeader:SetPoint("BOTTOMLEFT", f.DKPModesMain.ChannelsDropDown, "TOPLEFT", 0, 3);

  -- Cost Auto Update Value DROPDOWN box 
  if not core.DB.modes.CostSelection then core.DB.modes.CostSelection = "Second Bidder" end
  f.DKPModesMain.CostSelection = DD:Create_UIDropDownMenu("CommDKPModeSelectDropDown", costBody);
  f.DKPModesMain.CostSelection:SetPoint("TOPLEFT", costBody, "TOPLEFT", COL2, -22)

  local LocalCostSel;

  if core.DB.modes.CostSelection == "First Bidder" then
    LocalCostSel = L["FIRSTBIDDER"]
  elseif core.DB.modes.CostSelection == "Second Bidder" then
    LocalCostSel = L["SECONDBIDDER"]
  elseif core.DB.modes.CostSelection == "Second Bidder or Min" then
    LocalCostSel = L["SECONDBIDDERORMIN"]
  end

  -- Create and bind the initialization function to the dropdown menu
    DD:UIDropDownMenu_Initialize(f.DKPModesMain.CostSelection, function(self, level, menuList)
    
  local CostSelect = DD:UIDropDownMenu_CreateInfo()
    CostSelect.func = self.SetValue
    CostSelect.text, CostSelect.arg1, CostSelect.checked, CostSelect.isNotRadio = L["FIRSTBIDDER"], "First Bidder", "First Bidder" == core.DB.modes.CostSelection, false
    DD:UIDropDownMenu_AddButton(CostSelect)
    CostSelect.text, CostSelect.arg1, CostSelect.checked, CostSelect.isNotRadio = L["SECONDBIDDER"], "Second Bidder", "Second Bidder" == core.DB.modes.CostSelection, false
    DD:UIDropDownMenu_AddButton(CostSelect)
    CostSelect.text, CostSelect.arg1, CostSelect.checked, CostSelect.isNotRadio = L["SECONDBIDDERORMIN"], "Second Bidder or Min", "Second Bidder or Min" == core.DB.modes.CostSelection, false
    DD:UIDropDownMenu_AddButton(CostSelect)
  end)
  
  

  DD:UIDropDownMenu_SetWidth(f.DKPModesMain.CostSelection, FIELD_W)
  DD:UIDropDownMenu_SetText(f.DKPModesMain.CostSelection, LocalCostSel)

  -- Dropdown Menu Function
  function f.DKPModesMain.CostSelection:SetValue(arg1)
    core.DB.modes.CostSelection = arg1

    if arg1 == "First Bidder" then
      LocalCostSel = L["FIRSTBIDDER"]
    elseif arg1 == "Second Bidder" then
      LocalCostSel = L["SECONDBIDDER"]
    else
      LocalCostSel = L["SECONDBIDDERORMIN"]
    end

    DD:UIDropDownMenu_SetText(f.DKPModesMain.CostSelection, LocalCostSel)
    DD:CloseDropDownMenus()
  end

  f.DKPModesMain.CostSelection:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT");
    GameTooltip:SetText(L["COSTAUTOUPDATE"], 0.25, 0.75, 0.90, 1, true);
    GameTooltip:AddLine(L["COSTAUTOUPDATETTDESC"], 1.0, 1.0, 1.0, true);
    GameTooltip:Show();
  end)
  f.DKPModesMain.CostSelection:SetScript("OnLeave", function(self)
    GameTooltip:Hide()
  end)

  f.DKPModesMain.CostSelectionHeader = W.CreateText(costBody, "label", L["COSTAUTOUPDATEVALUE"], "LEFT")
  f.DKPModesMain.CostSelectionHeader:SetPoint("BOTTOMLEFT", f.DKPModesMain.CostSelection, "TOPLEFT", 0, 3);

  if not (core.DB.modes.mode == "Minimum Bid Values" or (core.DB.modes.mode == "Zero Sum" and core.DB.modes.ZeroSumBidType == "Minimum Bid")) then
    f.DKPModesMain.CostSelection:Hide()
    f.DKPModesMain.CostSelectionHeader:Hide();
  end

  -- Artificial Inflation Editbox
  if not core.DB.modes.Inflation then core.DB.modes.Inflation = 0 end

    f.DKPModesMain.Inflation = CreateFrame("EditBox", nil, costBody, "BackdropTemplate")
  
    f.DKPModesMain.Inflation:SetAutoFocus(false)
    f.DKPModesMain.Inflation:SetMultiLine(false)
    f.DKPModesMain.Inflation:SetPoint("TOPLEFT", costBody, "TOPLEFT", COL2, -70)
    f.DKPModesMain.Inflation:SetSize(70, W.H)
    f.DKPModesMain.Inflation:SetMaxLetters(8)
f.DKPModesMain.Inflation:SetText(core.DB.modes.Inflation)
    f.DKPModesMain.Inflation:Hide();
    f.DKPModesMain.Inflation:SetScript("OnEscapePressed", function(self)    -- clears focus on esc
      core.DB.modes.Inflation = f.DKPModesMain.Inflation:GetNumber()
      self:ClearFocus()
    end)
    f.DKPModesMain.Inflation:SetScript("OnTabPressed", function(self)    -- clears focus on esc
      core.DB.modes.Inflation = f.DKPModesMain.Inflation:GetNumber()
      self:ClearFocus()
    end)
    f.DKPModesMain.Inflation:SetScript("OnEnterPressed", function(self)    -- clears focus on esc
      core.DB.modes.Inflation = f.DKPModesMain.Inflation:GetNumber()
      self:ClearFocus()
    end)
    f.DKPModesMain.Inflation:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT");
    GameTooltip:SetText(L["ARTIFICIALINFLATION"], 0.25, 0.75, 0.90, 1, true);
    GameTooltip:AddLine(L["ARTINFLATTTDESC"], 1.0, 1.0, 1.0, true);
    GameTooltip:Show();
  end)
    f.DKPModesMain.Inflation:SetScript("OnLeave", function(self)
      GameTooltip:Hide()
    end)
    W.StyleEditBox(f.DKPModesMain.Inflation, { numeric = true })

    -- Inflation Header
    f.DKPModesMain.Inflation.Header = W.CreateText(f.DKPModesMain.Inflation, "label", L["INFLATION"], "LEFT")
    f.DKPModesMain.Inflation.Header:SetPoint("BOTTOMLEFT", f.DKPModesMain.Inflation, "TOPLEFT", 0, 3);

    if core.DB.modes.mode == "Zero Sum" then
      f.DKPModesMain.Inflation:Show()
      f.DKPModesMain.Inflation.Header:Show()
    end

    -- ZeroSum Type DROPDOWN box 
  f.DKPModesMain.ZeroSumType = DD:Create_UIDropDownMenu("CommDKPModeSelectDropDown", bidBody);
  -- Create and bind the initialization function to the dropdown menu
    DD:UIDropDownMenu_Initialize(f.DKPModesMain.ZeroSumType, function(self, level, menuList)
    
  local BidType = DD:UIDropDownMenu_CreateInfo()
    BidType.func = self.SetValue
    BidType.text, BidType.arg1, BidType.checked, BidType.isNotRadio = L["STATIC"], "Static", "Static" == core.DB.modes.ZeroSumBidType, false
    DD:UIDropDownMenu_AddButton(BidType)
    BidType.text, BidType.arg1, BidType.checked, BidType.isNotRadio = L["MINIMUMBID"], "Minimum Bid", "Minimum Bid" == core.DB.modes.ZeroSumBidType, false
    DD:UIDropDownMenu_AddButton(BidType)
  end)

  f.DKPModesMain.ZeroSumType:SetPoint("TOPLEFT", bidBody, "TOPLEFT", COL2, -22)
  DD:UIDropDownMenu_SetWidth(f.DKPModesMain.ZeroSumType, FIELD_W)
  DD:UIDropDownMenu_SetText(f.DKPModesMain.ZeroSumType, core.DB.modes.ZeroSumBidType)

  -- Dropdown Menu Function
  function f.DKPModesMain.ZeroSumType:SetValue(newValue)
    core.DB.modes.ZeroSumBidType = newValue;
    if newValue == "Static" then
      f.DKPModesMain.CostSelection:Hide();
      f.DKPModesMain.CostSelectionHeader:Hide();
      newValue = L["STATIC"]
      f.DKPModesMain.SubZeroBidding:Hide()
      f.DKPModesMain.AllowNegativeBidders:Hide()
      f.DKPModesMain.MaxBidBehaviorDropDown:Hide();
      f.DKPModesMain.MaxBidBehaviorHeader:Hide();
      core.DB.modes.MaxBehavior = "Max DKP";
    else
      f.DKPModesMain.CostSelection:Show();
      f.DKPModesMain.CostSelectionHeader:Show();
      newValue = L["MINIMUMBID"]
      f.DKPModesMain.SubZeroBidding:Show()
      f.DKPModesMain.AllowNegativeBidders:Show()
      f.DKPModesMain.MaxBidBehaviorDropDown:Show();
      f.DKPModesMain.MaxBidBehaviorHeader:Show();
    end

    DD:UIDropDownMenu_SetText(f.DKPModesMain.ZeroSumType, newValue)
    DD:CloseDropDownMenus()
  end

  f.DKPModesMain.ZeroSumType:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT");
    GameTooltip:SetText(L["ZEROSUMITEMCOST"], 0.25, 0.75, 0.90, 1, true);
    GameTooltip:AddLine(L["ZEROSUMITEMCOSTTTDESC"], 1.0, 1.0, 1.0, true);
    GameTooltip:Show();
  end)
  f.DKPModesMain.ZeroSumType:SetScript("OnLeave", function(self)
    GameTooltip:Hide()
  end)

  f.DKPModesMain.ZeroSumTypeHeader = W.CreateText(bidBody, "label", L["BIDMETHOD"], "LEFT")
  f.DKPModesMain.ZeroSumTypeHeader:SetPoint("BOTTOMLEFT", f.DKPModesMain.ZeroSumType, "TOPLEFT", 0, 3);

  if core.DB.modes.mode ~= "Zero Sum" then
    f.DKPModesMain.ZeroSumType:Hide()
    f.DKPModesMain.ZeroSumTypeHeader:Hide();
  end

  -- Item Cost Value DROPDOWN box 
  f.DKPModesMain.ItemCostDropDown = DD:Create_UIDropDownMenu("CommDKPModeSelectDropDown", costBody);
  -- Create and bind the initialization function to the dropdown menu
    DD:UIDropDownMenu_Initialize(f.DKPModesMain.ItemCostDropDown, 
    function(self, level, menuList)
      
      local CostValue = DD:UIDropDownMenu_CreateInfo()
      CostValue.func = self.SetValue
      CostValue.text, CostValue.arg1, CostValue.checked, CostValue.isNotRadio = L["INTEGER"], "Integer", "Integer" == core.DB.modes.costvalue, false
      DD:UIDropDownMenu_AddButton(CostValue)
      CostValue.text, CostValue.arg1, CostValue.checked, CostValue.isNotRadio = L["PERCENT"], "Percent", "Percent" == core.DB.modes.costvalue, false
      DD:UIDropDownMenu_AddButton(CostValue)
    end)
  
  f.DKPModesMain.ItemCostDropDown:SetPoint("TOPLEFT", costBody, "TOPLEFT", COL1, -22)
  DD:UIDropDownMenu_SetWidth(f.DKPModesMain.ItemCostDropDown, FIELD_W)
  DD:UIDropDownMenu_SetText(f.DKPModesMain.ItemCostDropDown, L[string.upper(core.DB.modes.costvalue)])

  -- Dropdown Menu Function
  function f.DKPModesMain.ItemCostDropDown:SetValue(arg1)
    if arg1 == "Integer" then
      core.DB.modes.costvalue = "Integer"
      f.DKPModesMain.SubZeroBidding:Show()
      f.DKPModesMain.SubZeroBidding:SetChecked(core.DB.modes.SubZeroBidding)
      if core.DB.modes.SubZeroBidding == true then
        f.DKPModesMain.AllowNegativeBidders:Show()
        f.DKPModesMain.AllowNegativeBidders:SetChecked(core.DB.modes.AllowNegativeBidders)
      end
      DD:UIDropDownMenu_SetText(f.DKPModesMain.ItemCostDropDown, L["INTEGER"])
    elseif arg1 == "Percent" then
      core.DB.modes.costvalue = "Percent"
      f.DKPModesMain.SubZeroBidding:Hide()
      f.DKPModesMain.AllowNegativeBidders:Hide()
      core.DB.modes.SubZeroBidding = false;
      f.DKPModesMain.SubZeroBidding:SetChecked(false)
      DD:UIDropDownMenu_SetText(f.DKPModesMain.ItemCostDropDown, L["PERCENT"])
    end

    
    DD:CloseDropDownMenus()
  end

  f.DKPModesMain.ItemCostDropDown:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT");
    GameTooltip:SetText(L["ITEMCOSTTYPES"], 0.25, 0.75, 0.90, 1, true);
    GameTooltip:AddLine(L["ITEMCOSTTYPESTTDESC"], 1.0, 1.0, 1.0, true);
    GameTooltip:Show();
  end)
  f.DKPModesMain.ItemCostDropDown:SetScript("OnLeave", function(self)
    GameTooltip:Hide()
  end)

  f.DKPModesMain.ItemCostHeader = W.CreateText(costBody, "label", L["ITEMCOSTTYPES"], "LEFT")
  f.DKPModesMain.ItemCostHeader:SetPoint("BOTTOMLEFT", f.DKPModesMain.ItemCostDropDown, "TOPLEFT", 0, 3);

  if core.DB.modes.mode == "Minimum Bid Values" then
    f.DKPModesMain.ItemCostDropDown:Hide();
    f.DKPModesMain.ItemCostHeader:Hide();
    core.DB.modes.costvalue = "Integer";
    f.DKPModesMain.MaxBidBehaviorDropDown:Show();
    f.DKPModesMain.MaxBidBehaviorHeader:Show();
  elseif core.DB.modes.mode == "Roll Based Bidding" then
    f.DKPModesMain.MaxBidBehaviorDropDown:Hide();
    f.DKPModesMain.MaxBidBehaviorHeader:Hide();
    core.DB.modes.MaxBehavior = "Max DKP";
  elseif core.DB.modes.mode == "Static Item Values" then
    f.DKPModesMain.MaxBidBehaviorDropDown:Hide();
    f.DKPModesMain.MaxBidBehaviorHeader:Hide();
    core.DB.modes.MaxBehavior = "Max DKP";
  elseif core.DB.modes.mode == "Zero Sum" then
    f.DKPModesMain.ItemCostDropDown:Hide();
    f.DKPModesMain.ItemCostHeader:Hide();
    core.DB.modes.costvalue = "Integer";
    if core.DB.modes.ZeroSumBidType == "Static" then
      f.DKPModesMain.MaxBidBehaviorDropDown:Hide();
      f.DKPModesMain.MaxBidBehaviorHeader:Hide();
      core.DB.modes.MaxBehavior = "Max DKP";      
    else
      f.DKPModesMain.MaxBidBehaviorDropDown:Show();
      f.DKPModesMain.MaxBidBehaviorHeader:Show();    
    end
  end

  -- Sub Zero Bidding Checkbox
  f.DKPModesMain.SubZeroBidding = W.CreateCheckbox(bidBody, nil, L["SUBZEROBIDDING"]);
  f.DKPModesMain.SubZeroBidding:SetChecked(core.DB.modes.SubZeroBidding)
  f.DKPModesMain.SubZeroBidding:SetPoint("TOPLEFT", bidBody, "TOPLEFT", COL1, -106);
  f.DKPModesMain.SubZeroBidding:SetScript("OnClick", function(self)
    if self:GetChecked() == true then
      core.DB.modes.SubZeroBidding = true;
      CommDKP:Print("Sub Zero Bidding |cff00ff00"..L["ENABLED"].."|r")
      f.DKPModesMain.AllowNegativeBidders:Show()
      f.DKPModesMain.AllowNegativeBidders:SetChecked(core.DB.modes.AllowNegativeBidders)
    else
      core.DB.modes.SubZeroBidding = false;
      CommDKP:Print("Sub Zero Bidding |cffff0000"..L["DISABLED"].."|r")
      core.DB.modes.AllowNegativeBidders = false
      f.DKPModesMain.AllowNegativeBidders:Hide()
    end
    PlaySound(808);
  end)
  f.DKPModesMain.SubZeroBidding:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT");
    GameTooltip:SetText(L["SUBZEROBIDDING"], 0.25, 0.75, 0.90, 1, true);
    GameTooltip:AddLine(L["SUBZEROBIDDINGTTDESC"], 1.0, 1.0, 1.0, true);
    GameTooltip:Show();
  end)
  f.DKPModesMain.SubZeroBidding:SetScript("OnLeave", function(self)
    GameTooltip:Hide()
  end)
  if core.DB.modes.costvalue == "Percent" or (core.DB.modes.mode == "Zero Sum" and core.DB.modes.ZeroSumBidType == "Static") then
    f.DKPModesMain.SubZeroBidding:Hide()
  end
  
  -- Allow Bids below zero Checkbox
  f.DKPModesMain.AllowNegativeBidders = W.CreateCheckbox(bidBody, nil, L["ALLOWNEGATIVEBIDDERS"]);
  f.DKPModesMain.AllowNegativeBidders:SetChecked(core.DB.modes.AllowNegativeBidders)
  f.DKPModesMain.AllowNegativeBidders:SetPoint("TOPLEFT", bidBody, "TOPLEFT", COL2, -106);
  f.DKPModesMain.AllowNegativeBidders:SetScript("OnClick", function(self)
    if self:GetChecked() == true then
      core.DB.modes.AllowNegativeBidders = true;
      CommDKP:Print("Allow Negative Bidders |cff00ff00"..L["ENABLED"].."|r")
    else
      core.DB.modes.AllowNegativeBidders = false;
      CommDKP:Print("Allow Negative Bidders |cffff0000"..L["DISABLED"].."|r")
    end
    PlaySound(808);
  end)
  f.DKPModesMain.AllowNegativeBidders:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT");
    GameTooltip:SetText(L["ALLOWNEGATIVEBIDDERS"], 0.25, 0.75, 0.90, 1, true);
    GameTooltip:AddLine(L["ALLOWNEGATIVEBIDTTDESC"], 1.0, 1.0, 1.0, true);
    GameTooltip:Show();
  end)
  f.DKPModesMain.AllowNegativeBidders:SetScript("OnLeave", function(self)
    GameTooltip:Hide()
  end)
  if (core.DB.modes.costvalue == "Percent" or (core.DB.modes.mode == "Zero Sum" and core.DB.modes.ZeroSumBidType == "Static")) or core.DB.modes.SubZeroBidding == false then
    f.DKPModesMain.AllowNegativeBidders:Hide()
  end


  ---
  -- Roll Container
  ---

    f.DKPModesMain.RollContainer = W.CreateCard(f.DKPModesMain, L["ROLLSETTINGS"], CARD_W, 115);
    f.DKPModesMain.RollContainer:SetPoint("TOPLEFT", f.DKPModesMain.BidCard, "BOTTOMLEFT", 0, -8)
    local rollBody = f.DKPModesMain.RollContainer.Body
    f.DKPModesMain.RollContainer:Hide();
    if core.DB.modes.mode == "Roll Based Bidding" then
      f.DKPModesMain.RollContainer:Show()
    end

    ---
    -- Roll Container Header
    ---
      -- (the legacy large L["ROLLSETTINGS"] heading is now the card title; .Header is the card's header band)

    ---
    -- Roll bidding mode dropdown
    ---

      if core.DB.modes.RollMode == nil then
        core.DB.modes.RollMode = "Default"
      end

      f.DKPModesMain.RollContainer.RollBiddingModeDropdown = DD:Create_UIDropDownMenu("CommDKPModeSelectDropDown", rollBody);

      DD:UIDropDownMenu_Initialize(
        f.DKPModesMain.RollContainer.RollBiddingModeDropdown,
          function(self, level, menuList)
            
            local _rollMode = DD:UIDropDownMenu_CreateInfo()
            _rollMode.func = self.SetValue
            _rollMode.text = "Default"
            _rollMode.arg1 = "Default"
            _rollMode.checked = ("Default" == core.DB.modes.RollMode)
            _rollMode.isNotRadio = false
            DD:UIDropDownMenu_AddButton(_rollMode)
            _rollMode.text = "Ni Karma"
            _rollMode.arg1 = "Ni Karma"
            _rollMode.checked = ("Ni Karma" == core.DB.modes.RollMode)
            _rollMode.isNotRadio = false
            DD:UIDropDownMenu_AddButton(_rollMode)
          end
      )
    
      f.DKPModesMain.RollContainer.RollBiddingModeDropdown:SetPoint("TOPLEFT", rollBody, "TOPLEFT", COL1, -22)
      DD:UIDropDownMenu_SetWidth(f.DKPModesMain.RollContainer.RollBiddingModeDropdown, FIELD_W)
      DD:UIDropDownMenu_SetText(f.DKPModesMain.RollContainer.RollBiddingModeDropdown, core.DB.modes.RollMode)

      -- Dropdown Menu Function
      function f.DKPModesMain.RollContainer.RollBiddingModeDropdown:SetValue(arg1)
        if arg1 == "Default" then
          core.DB.modes.RollMode = "Default"
          f.DKPModesMain.RollContainer.UsePerc:Show()
          f.DKPModesMain.RollContainer.UsePerc.text:Show()
          f.DKPModesMain.RollContainer.AddMax:Show()
          f.DKPModesMain.RollContainer.AddMax.Header:Show()
          f.DKPModesMain.RollContainer.maxKarma:Hide()
          f.DKPModesMain.RollContainer.maxKarma.Header:Hide()
        elseif arg1 == "Ni Karma" then
          core.DB.modes.RollMode = "Ni Karma"
          f.DKPModesMain.RollContainer.UsePerc:Hide()
          f.DKPModesMain.RollContainer.UsePerc.text:Hide()
          f.DKPModesMain.RollContainer.AddMax:Hide()
          f.DKPModesMain.RollContainer.AddMax.Header:Hide()
          f.DKPModesMain.RollContainer.maxKarma:Show()
          f.DKPModesMain.RollContainer.maxKarma.Header:Show()
        end
        DD:UIDropDownMenu_SetText(f.DKPModesMain.RollContainer.RollBiddingModeDropdown, core.DB.modes.RollMode);
        DD:CloseDropDownMenus()
      end

      f.DKPModesMain.RollContainer.RollBiddingModeDropdown:SetScript(
        "OnEnter", 
          function(self)
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT");
            GameTooltip:SetText(L["ITEMCOSTTYPES"], 0.25, 0.75, 0.90, 1, true);
            GameTooltip:AddLine(L["ITEMCOSTTYPESTTDESC"], 1.0, 1.0, 1.0, true);
            GameTooltip:Show();
          end
        )
      f.DKPModesMain.RollContainer.RollBiddingModeDropdown:SetScript(
        "OnLeave",
          function(self)
            GameTooltip:Hide()
          end)

    ---
    -- Roll settings sub mode header
    ---

      f.DKPModesMain.RollContainer.SubModeHeader = W.CreateText(rollBody, "label", "Roll sub mode", "LEFT")
      f.DKPModesMain.RollContainer.SubModeHeader:SetPoint("BOTTOMLEFT", f.DKPModesMain.RollContainer.RollBiddingModeDropdown, "TOPLEFT", 0, 3);

    ---
    -- Default roll sub section
    ---    

    ---
    -- Min Roll Editbox
    ---
      f.DKPModesMain.RollContainer.rollMin = CreateFrame("EditBox", nil, rollBody, "BackdropTemplate")

      
      f.DKPModesMain.RollContainer.rollMin:SetAutoFocus(false)
      f.DKPModesMain.RollContainer.rollMin:SetMultiLine(false)
      f.DKPModesMain.RollContainer.rollMin:SetPoint("TOPLEFT", rollBody, "TOPLEFT", COL2, -22)
      f.DKPModesMain.RollContainer.rollMin:SetSize(60, W.H)
      f.DKPModesMain.RollContainer.rollMin:SetMaxLetters(6)
f.DKPModesMain.RollContainer.rollMin:SetText(core.DB.modes.rolls.min)
      f.DKPModesMain.RollContainer.rollMin:SetScript(
        "OnEscapePressed", 
          function(self)    -- clears focus on esc
            core.DB.modes.rolls.min = f.DKPModesMain.RollContainer.rollMin:GetNumber()
            core.DB.modes.rolls.max = f.DKPModesMain.RollContainer.rollMax:GetNumber()  
            core.DB.modes.rolls.AddToMax = f.DKPModesMain.RollContainer.AddMax:GetNumber()
            self:ClearFocus()
          end
        )
      f.DKPModesMain.RollContainer.rollMin:SetScript(
        "OnTabPressed", 
          function(self)    -- clears focus on esc
            core.DB.modes.rolls.min = f.DKPModesMain.RollContainer.rollMin:GetNumber()
            core.DB.modes.rolls.max = f.DKPModesMain.RollContainer.rollMax:GetNumber()  
            core.DB.modes.rolls.AddToMax = f.DKPModesMain.RollContainer.AddMax:GetNumber()
            f.DKPModesMain.RollContainer.rollMax:SetFocus()
          end
        )
      f.DKPModesMain.RollContainer.rollMin:SetScript(
        "OnEnterPressed", 
          function(self)    -- clears focus on esc
            core.DB.modes.rolls.min = f.DKPModesMain.RollContainer.rollMin:GetNumber()
            core.DB.modes.rolls.max = f.DKPModesMain.RollContainer.rollMax:GetNumber()  
            core.DB.modes.rolls.AddToMax = f.DKPModesMain.RollContainer.AddMax:GetNumber()  
            self:ClearFocus()
          end
        )
      f.DKPModesMain.RollContainer.rollMin:SetScript(
        "OnEnter", 
          function(self)
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT");
            GameTooltip:SetText(L["MINIMUMROLL"], 0.25, 0.75, 0.90, 1, true);
            GameTooltip:AddLine(L["MINIMUMROLLTTDESC"], 1.0, 1.0, 1.0, true);
            GameTooltip:Show();
          end
        )
      f.DKPModesMain.RollContainer.rollMin:SetScript(
        "OnLeave",
          function(self)
            GameTooltip:Hide()
          end
        )
      W.StyleEditBox(f.DKPModesMain.RollContainer.rollMin, { numeric = true })

    ---
    -- Min Roll Header
    ---
      f.DKPModesMain.RollContainer.rollMin.Header = W.CreateText(f.DKPModesMain.RollContainer.rollMin, "label", L["MIN"], "LEFT")
      f.DKPModesMain.RollContainer.rollMin.Header:SetPoint("BOTTOMLEFT", f.DKPModesMain.RollContainer.rollMin, "TOPLEFT", 0, 3);

        -- Dash Between Rolls (§12.4.4: a textMuted en dash)
        f.DKPModesMain.RollContainer.dash = W.CreateText(rollBody, "body", "\226\128\147", "CENTER", "textMuted")
        f.DKPModesMain.RollContainer.dash:SetPoint("LEFT", f.DKPModesMain.RollContainer.rollMin, "RIGHT", 18, 0);

        -- Max Roll Editbox
      f.DKPModesMain.RollContainer.rollMax = CreateFrame("EditBox", nil, rollBody, "BackdropTemplate")
        f.DKPModesMain.RollContainer.rollMax:SetAutoFocus(false)
        f.DKPModesMain.RollContainer.rollMax:SetMultiLine(false)
        f.DKPModesMain.RollContainer.rollMax:SetPoint("LEFT", f.DKPModesMain.RollContainer.rollMin, "RIGHT", 40, 0)
        f.DKPModesMain.RollContainer.rollMax:SetSize(60, W.H)
        f.DKPModesMain.RollContainer.rollMax:SetMaxLetters(6)
f.DKPModesMain.RollContainer.rollMax:SetText(core.DB.modes.rolls.max)
        f.DKPModesMain.RollContainer.rollMax:SetScript("OnEscapePressed", function(self)    -- clears focus on esc
          core.DB.modes.rolls.min = f.DKPModesMain.RollContainer.rollMin:GetNumber()
        core.DB.modes.rolls.max = f.DKPModesMain.RollContainer.rollMax:GetNumber()  
        core.DB.modes.rolls.AddToMax = f.DKPModesMain.RollContainer.AddMax:GetNumber()  
          self:ClearFocus()
        end)
        f.DKPModesMain.RollContainer.rollMax:SetScript("OnTabPressed", function(self)    -- clears focus on esc
            core.DB.modes.rolls.min = f.DKPModesMain.RollContainer.rollMin:GetNumber()
        core.DB.modes.rolls.max = f.DKPModesMain.RollContainer.rollMax:GetNumber()  
        core.DB.modes.rolls.AddToMax = f.DKPModesMain.RollContainer.AddMax:GetNumber()  
          f.DKPModesMain.RollContainer.AddMax:SetFocus()
        end)
        f.DKPModesMain.RollContainer.rollMax:SetScript("OnEnterPressed", function(self)    -- clears focus on esc
          core.DB.modes.rolls.min = f.DKPModesMain.RollContainer.rollMin:GetNumber()
        core.DB.modes.rolls.max = f.DKPModesMain.RollContainer.rollMax:GetNumber()  
        core.DB.modes.rolls.AddToMax = f.DKPModesMain.RollContainer.AddMax:GetNumber()  
          self:ClearFocus()
        end)
        f.DKPModesMain.RollContainer.rollMax:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT");
        GameTooltip:SetText(L["MAXIMUMROLL"], 0.25, 0.75, 0.90, 1, true);
        GameTooltip:AddLine(L["MAXIMUMROLLTTDESC"], 1.0, 1.0, 1.0, true);
        GameTooltip:AddLine(L["MAXIMUMROLLTTWARN"], 1.0, 0, 0, true);
        GameTooltip:Show();
      end)
        f.DKPModesMain.RollContainer.rollMax:SetScript("OnLeave", function(self)
          GameTooltip:Hide()
        end)
        W.StyleEditBox(f.DKPModesMain.RollContainer.rollMax, { numeric = true })

        -- Max Roll Header
        f.DKPModesMain.RollContainer.rollMax.Header = W.CreateText(f.DKPModesMain.RollContainer.rollMax, "label", L["MAX"], "LEFT")
        f.DKPModesMain.RollContainer.rollMax.Header:SetPoint("BOTTOMLEFT", f.DKPModesMain.RollContainer.rollMax, "TOPLEFT", 0, 3);

        f.DKPModesMain.RollContainer.rollMin.perc = W.CreateText(f.DKPModesMain.RollContainer.rollMin, "caption", "%", "LEFT", "textMuted")
        f.DKPModesMain.RollContainer.rollMin.perc:SetPoint("LEFT", f.DKPModesMain.RollContainer.rollMin, "RIGHT", 3, 0);
        f.DKPModesMain.RollContainer.rollMin.perc:SetShown(core.DB.modes.rolls.UsePerc);

        f.DKPModesMain.RollContainer.rollMax.perc = W.CreateText(f.DKPModesMain.RollContainer.rollMax, "caption", "%", "LEFT", "textMuted")
        f.DKPModesMain.RollContainer.rollMax.perc:SetPoint("LEFT", f.DKPModesMain.RollContainer.rollMax, "RIGHT", 3, 0);
        f.DKPModesMain.RollContainer.rollMax.perc:SetShown(core.DB.modes.rolls.UsePerc);

          -- Percent Rolls Checkbox

        f.DKPModesMain.RollContainer.UsePerc = W.CreateCheckbox(rollBody, nil, L["USEPERCENTAGE"]);
        f.DKPModesMain.RollContainer.UsePerc:SetChecked(core.DB.modes.rolls.UsePerc)
        f.DKPModesMain.RollContainer.UsePerc:SetPoint("TOPLEFT", rollBody, "TOPLEFT", COL1, -60);
        f.DKPModesMain.RollContainer.UsePerc:SetScript("OnClick", function(self)
        core.DB.modes.rolls.UsePerc = self:GetChecked();
        f.DKPModesMain.RollContainer.rollMin.perc:SetShown(self:GetChecked())
        f.DKPModesMain.RollContainer.rollMax.perc:SetShown(self:GetChecked())
        if f.DKPModesMain.RollContainer.rollMax:GetNumber() == 0 then
          f.DKPModesMain.RollContainer.rollMax:SetNumber(100)
        end
        PlaySound(808);
      end)
      f.DKPModesMain.RollContainer.UsePerc:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_LEFT");
        GameTooltip:SetText(L["USEPERCFORROLLS"], 0.25, 0.75, 0.90, 1, true);
        GameTooltip:AddLine(L["USEPERCROLLSTTDESC"], 1.0, 1.0, 1.0, true);
        GameTooltip:AddLine(L["USEPERCROLLSTTWARN"], 1.0, 0, 0, true);
        GameTooltip:Show();
      end)
      f.DKPModesMain.RollContainer.UsePerc:SetScript("OnLeave", function(self)
        GameTooltip:Hide()
      end)

        -- Add to Max Editbox
      f.DKPModesMain.RollContainer.AddMax = CreateFrame("EditBox", nil, rollBody, "BackdropTemplate")
     
        f.DKPModesMain.RollContainer.AddMax:SetAutoFocus(false)
        f.DKPModesMain.RollContainer.AddMax:SetMultiLine(false)
        f.DKPModesMain.RollContainer.AddMax:SetPoint("TOPLEFT", f.DKPModesMain.RollContainer.rollMax, "BOTTOMLEFT", 0, -12)
        f.DKPModesMain.RollContainer.AddMax:SetSize(60, W.H)
        f.DKPModesMain.RollContainer.AddMax:SetMaxLetters(6)
f.DKPModesMain.RollContainer.AddMax:SetText(core.DB.modes.rolls.AddToMax)
        f.DKPModesMain.RollContainer.AddMax:SetScript("OnEscapePressed", function(self)    -- clears focus on esc
          core.DB.modes.rolls.min = f.DKPModesMain.RollContainer.rollMin:GetNumber()
        core.DB.modes.rolls.max = f.DKPModesMain.RollContainer.rollMax:GetNumber()  
        core.DB.modes.rolls.AddToMax = f.DKPModesMain.RollContainer.AddMax:GetNumber()
            self:ClearFocus()
        end)
        f.DKPModesMain.RollContainer.AddMax:SetScript("OnTabPressed", function(self)    -- clears focus on esc
          core.DB.modes.rolls.min = f.DKPModesMain.RollContainer.rollMin:GetNumber()
        core.DB.modes.rolls.max = f.DKPModesMain.RollContainer.rollMax:GetNumber()  
        core.DB.modes.rolls.AddToMax = f.DKPModesMain.RollContainer.AddMax:GetNumber()
            f.DKPModesMain.RollContainer.rollMin:SetFocus()
        end)
        f.DKPModesMain.RollContainer.AddMax:SetScript("OnEnterPressed", function(self)    -- clears focus on esc
          core.DB.modes.rolls.min = f.DKPModesMain.RollContainer.rollMin:GetNumber()
        core.DB.modes.rolls.max = f.DKPModesMain.RollContainer.rollMax:GetNumber()  
        core.DB.modes.rolls.AddToMax = f.DKPModesMain.RollContainer.AddMax:GetNumber()
            self:ClearFocus()
        end)
        f.DKPModesMain.RollContainer.AddMax:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT");
        GameTooltip:SetText(L["ADDTOMAXROLL"], 0.25, 0.75, 0.90, 1, true);
        GameTooltip:AddLine(L["ADDTOMAXROLLTTDESC"], 1.0, 1.0, 1.0, true);
        GameTooltip:AddLine(L["ADDTOMAXROLLTTWARN"], 1.0, 0, 0, true);
        GameTooltip:Show();
      end)
        f.DKPModesMain.RollContainer.AddMax:SetScript("OnLeave", function(self)
          GameTooltip:Hide()
        end)
        W.StyleEditBox(f.DKPModesMain.RollContainer.AddMax, { numeric = true })

        -- Add to Max Header (label left of its field)
        f.DKPModesMain.RollContainer.AddMax.Header = W.CreateText(rollBody, "label", L["ADDTOMAXROLL"], "RIGHT")
        f.DKPModesMain.RollContainer.AddMax.Header:SetPoint("RIGHT", f.DKPModesMain.RollContainer.AddMax, "LEFT", -6, 0);
        
      -- hide default roll extra options if Ni Karma is selected
      if core.DB.modes.RollMode == "Ni Karma" then
        f.DKPModesMain.RollContainer.UsePerc:Hide()
        f.DKPModesMain.RollContainer.UsePerc.text:Hide()
        f.DKPModesMain.RollContainer.AddMax:Hide()
        f.DKPModesMain.RollContainer.AddMax.Header:Hide()
      end

      --------------

      ---
      -- Ni Karma sub section
      ---

      ---
      -- Max Karma
      ---

        f.DKPModesMain.RollContainer.maxKarma = CreateFrame("EditBox", nil, rollBody, "BackdropTemplate")
        f.DKPModesMain.RollContainer.maxKarma:SetAutoFocus(false)
        f.DKPModesMain.RollContainer.maxKarma:SetMultiLine(false)
        f.DKPModesMain.RollContainer.maxKarma:SetPoint("TOPLEFT", f.DKPModesMain.RollContainer.rollMax, "BOTTOMLEFT", 0, -12)
        f.DKPModesMain.RollContainer.maxKarma:SetSize(60, W.H)
        f.DKPModesMain.RollContainer.maxKarma:SetMaxLetters(6)
if core.DB.modes.rolls.maxKarma == nil then
          f.DKPModesMain.RollContainer.maxKarma:SetText("")
        else
          f.DKPModesMain.RollContainer.maxKarma:SetText(core.DB.modes.rolls.maxKarma)
        end

        
        f.DKPModesMain.RollContainer.maxKarma:SetScript(
          "OnEscapePressed", 
            function(self)    -- clears focus on esc
              core.DB.modes.rolls.maxKarma = f.DKPModesMain.RollContainer.maxKarma:GetNumber()
              self:ClearFocus()
            end
          )
        f.DKPModesMain.RollContainer.maxKarma:SetScript(
          "OnTabPressed", 
            function(self)    -- clears focus on esc
              core.DB.modes.rolls.maxKarma = f.DKPModesMain.RollContainer.maxKarma:GetNumber()
              self:ClearFocus()
            end
          )
        f.DKPModesMain.RollContainer.maxKarma:SetScript(
          "OnEnterPressed", 
            function(self)    -- clears focus on esc
              core.DB.modes.rolls.maxKarma = f.DKPModesMain.RollContainer.maxKarma:GetNumber()
              self:ClearFocus()
            end
          )
        f.DKPModesMain.RollContainer.maxKarma:SetScript(
          "OnEnter", 
            function(self)
              GameTooltip:SetOwner(self, "ANCHOR_RIGHT");
              GameTooltip:SetText(L["MINIMUMROLL"], 0.25, 0.75, 0.90, 1, true);
              GameTooltip:AddLine(L["MINIMUMROLLTTDESC"], 1.0, 1.0, 1.0, true);
              GameTooltip:Show();
            end
          )
        f.DKPModesMain.RollContainer.maxKarma:SetScript(
          "OnLeave",
            function(self)
              GameTooltip:Hide()
            end
          )
        W.StyleEditBox(f.DKPModesMain.RollContainer.maxKarma, { numeric = true })

        -- max karma header (label left of its field)
        f.DKPModesMain.RollContainer.maxKarma.Header = W.CreateText(rollBody, "label", "Max Karma to add", "RIGHT")
        f.DKPModesMain.RollContainer.maxKarma.Header:SetPoint("RIGHT", f.DKPModesMain.RollContainer.maxKarma, "LEFT", -6, 0);

      if core.DB.modes.RollMode == "Default" then
        f.DKPModesMain.RollContainer.maxKarma:Hide()
        f.DKPModesMain.RollContainer.maxKarma.Header:Hide()
      end


  -- Broadcast DKP Modes Button
  -- §12.4.4: primary, 170 wide, at BOTTOMRIGHT of the frame's content area (outside the scroll region, so it never
  -- scrolls or clips). AD-35.5 (BR-27.6): ONE button and ONE handler, shown on BOTH tabs (Modes and Options): it
  -- shows and hides with the window only (no pane OnShow/OnHide hooks).
  f.DKPModesMain.BroadcastSettings = self:CreateButton("BOTTOMRIGHT", f.Content, "BOTTOMRIGHT", 0, 0, L["BROADCASTSETTINGS"]);
  f.DKPModesMain.BroadcastSettings:SetSize(170, W.H)
  W.StyleButton(f.DKPModesMain.BroadcastSettings, "primary")
  f.DKPModesMain.BroadcastSettings:Show()
  f.DKPModesMain.BroadcastSettings:SetScript("OnClick", function()
    core.DB.modes.rolls.min = f.DKPModesMain.RollContainer.rollMin:GetNumber()
    core.DB.modes.rolls.max = f.DKPModesMain.RollContainer.rollMax:GetNumber()  
    core.DB.modes.rolls.AddToMax = f.DKPModesMain.RollContainer.AddMax:GetNumber()  
    core.DB.modes.rolls.maxKarma = f.DKPModesMain.RollContainer.maxKarma:GetNumber()

    if (core.DB.modes.rolls.min > core.DB.modes.rolls.max and core.DB.modes.rolls.max ~= 0 and core.DB.modes.rolls.UserPerc == false) or (core.DB.modes.rolls.UsePerc and (core.DB.modes.rolls.min < 0 or core.DB.modes.rolls.max > 100 or core.DB.modes.rolls.min > core.DB.modes.rolls.max)) then
      StaticPopupDialogs["NOTIFY_ROLLS"] = {
        text = "|CFFFF0000"..L["WARNING"].."|r: "..L["INVALIDROLLRANGE"],
        button1 = L["OK"],
        timeout = 0,
        whileDead = true,
        hideOnEscape = true,
        preferredIndex = 3,
      }
      StaticPopup_Show ("NOTIFY_ROLLS")
      return;
    end

    StaticPopupDialogs["SEND_MODES"] = {
      text = L["AREYOUSUREBROADCAST"],
      button1 = L["YES"],
      button2 = L["NO"],
      OnAccept = function()
        local temptable1 = {}
        table.insert(temptable1, core.DB.modes)
        table.insert(temptable1, core.DB.DKPBonus)
        table.insert(temptable1, core.DB.raiders)
        CommDKP.Sync:SendData("CommDKPDKPModes", temptable1)
        CommDKP:Print(L["DKPMODESENTCONF"])
        CommDKP.Sync:SendData("CommDKPMinBid", CommDKP:BuildBidBroadcastData("min"))   -- AD-36.1.1 (BR-28.1, CM-01)
        CommDKP.Sync:SendData("CommDKPMaxBid", CommDKP:BuildBidBroadcastData("max"))
      end,
      timeout = 0,
      whileDead = true,
      hideOnEscape = true,
      preferredIndex = 3,
    }
    StaticPopup_Show ("SEND_MODES")
  end);
  f.DKPModesMain.BroadcastSettings:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    GameTooltip:SetText(L["BROADCASTSETTINGS"], 0.25, 0.75, 0.90, 1, true)
    GameTooltip:AddLine(L["BROADCASTSETTTDESC"], 1.0, 1.0, 1.0, true);
    GameTooltip:Show()
  end)
  f.DKPModesMain.BroadcastSettings:SetScript("OnLeave", function()
    GameTooltip:Hide()
  end)

  -- Pane height = the visible card stack (Mode card fitted to its caption + Cost + Bid, + Roll when shown,
  -- with 8 px gaps); the region's rail covers any overflow. Recomputed on build, OnShow and every mode switch.
  -- AD-21.2 (BR-14.1): the Mode card follows its caption's rendered height; the relative card chain
  -- (Cost -> Mode BOTTOMLEFT -8, Bid -> Cost, Roll -> Bid) moves with it, and the pane height is the visible stack.
  local MODE_MIN_H, MODE_CHROME_H, COST_H, BID_H, ROLL_H = 130, 90, 131, 161, 115   -- 90 = 77 caption top + 10 pad + 3 inset
  local function LayoutModesMain()
    local pane = f.DKPModesMain
    local d = pane.ModeDescription
    local hc = d and d.GetStringHeight and d:GetStringHeight() or 0
    if not hc or hc < 1 then hc = 120 end                       -- fonts not laid out yet: assume 10 caption lines
    local modeH = math.max(MODE_MIN_H, math.ceil(hc) + MODE_CHROME_H)
    pane.ModeCard:SetHeight(modeH)
    local h = modeH + W.GUT + COST_H + W.GUT + BID_H
    if pane.RollContainer and pane.RollContainer:IsShown() then h = h + W.GUT + ROLL_H end
    pane:SetHeight(h)
    local sf = f.ScrollFrame
    if sf and sf.UpdateRail and sf.GetScrollChild and sf:GetScrollChild() == pane then
      local range = (sf.GetVerticalScrollRange and sf:GetVerticalScrollRange()) or 0
      if (sf:GetVerticalScroll() or 0) > range then sf:SetVerticalScroll(range) end   -- shrink: no stale offset
      sf:UpdateRail()
    end
  end
  f.DKPModesMain.LayoutModesMain = LayoutModesMain               -- exposed for H116 and the Gate 2 probe
  LayoutModesMain()
  f.DKPModesMain:HookScript("OnShow", LayoutModesMain)

  -- AD-35.6 (BR-27.7, G-27.9, G-27.10): read-only refresh of every Modes-tab control from core.DB.modes. Never calls a
  -- control's SetValue / OnClick and never writes core.DB (AC-27.11). Visibility re-applies the BUILD-TIME rules
  -- (:490-493, :534-537, :595-598, :655-681, :710-712, :737-739, :749-752, :1026-1031, :1098-1101) without their DB
  -- normalisation writes, then the existing LayoutModesMain re-fits the card stack (Roll card on/off).
  local function vis(o, on) if o then o:SetShown(on and true or false) end end
  local function txt(box, v) if box then box:SetText(v ~= nil and tostring(v) or "") end end
  function f.DKPModesMain.RefreshFromDB()
    local p, m = f.DKPModesMain, core.DB.modes or {}
    local r = type(m.rolls) == "table" and m.rolls or {}
    local mode, zs, cv = m.mode, m.ZeroSumBidType, m.costvalue
    local isMin, isStatic = mode == "Minimum Bid Values", mode == "Static Item Values"
    local isRoll, isZS = mode == "Roll Based Bidding", mode == "Zero Sum"
    DD:CloseDropDownMenus()                                          -- an open list would show stale checks
    -- Mode card
    CurMode = mode
    LocalMode = (isMin and L["MINBIDVALUESHEAD"]) or (isStatic and L["STATICITEMVALUESHEAD"])
      or (isRoll and L["ROLLBIDDINGHEAD"]) or (isZS and L["ZEROSUMHEAD"]) or nil
    DD:UIDropDownMenu_SetText(p.ModesDropDown, LocalMode)
    p.ModeDescriptionHeader:SetText(LocalMode or "")
    p.ModeDescription:SetText((isMin and MinBidDescription) or (isStatic and StaticDescription)
      or (isRoll and RollDescription) or (isZS and ZeroSumDescription) or "")
    -- Cost card
    DD:UIDropDownMenu_SetText(p.RoundDropDown, m.rounding)
    DD:UIDropDownMenu_SetText(p.ItemCostDropDown, L[string.upper(cv or "Integer")])
    LocalCostSel = (m.CostSelection == "First Bidder" and L["FIRSTBIDDER"])
      or (m.CostSelection == "Second Bidder or Min" and L["SECONDBIDDERORMIN"]) or L["SECONDBIDDER"]
    DD:UIDropDownMenu_SetText(p.CostSelection, LocalCostSel)
    txt(p.Inflation, m.Inflation or 0)
    -- Bid card (labels = the SetValue mappings, :305-311 and :559-578)
    local mb = m.MaxBehavior
    DD:UIDropDownMenu_SetText(p.MaxBidBehaviorDropDown, (mb == "Max DKP" and L["MAXBIDBEHAVIORMAXDKP"])
      or (mb == "Max Item Value" and L["MAXBIDBEHAVIORMAXITEMVALUE"]) or L["MAXBIDBEHAVIORMIN"])
    DD:UIDropDownMenu_SetText(p.ZeroSumType, zs == "Static" and L["STATIC"] or L["MINIMUMBID"])
    DD:UIDropDownMenu_SetText(p.ChannelsDropDown, L["OPENCHANNELS"])  -- multi-select: checks read core.DB at open
    txt(p.AntiSnipe, m.AntiSnipe)
    p.SubZeroBidding:SetChecked(m.SubZeroBidding == true)
    p.AllowNegativeBidders:SetChecked(m.AllowNegativeBidders == true)
    -- Roll card
    local rc = p.RollContainer
    DD:UIDropDownMenu_SetText(rc.RollBiddingModeDropdown, m.RollMode or "Default")
    txt(rc.rollMin, r.min); txt(rc.rollMax, r.max); txt(rc.AddMax, r.AddToMax); txt(rc.maxKarma, r.maxKarma)
    rc.UsePerc:SetChecked(r.UsePerc == true)
    vis(rc.rollMin.perc, r.UsePerc); vis(rc.rollMax.perc, r.UsePerc)
    -- Visibility (build-time rules, no writes)
    local zsStatic = isZS and zs == "Static"
    vis(p.ItemCostDropDown, not (isMin or isZS)); vis(p.ItemCostHeader, not (isMin or isZS))
    local maxBid = isMin or (isZS and zs ~= "Static")
    vis(p.MaxBidBehaviorDropDown, maxBid); vis(p.MaxBidBehaviorHeader, maxBid)
    local costSel = isMin or (isZS and zs == "Minimum Bid")
    vis(p.CostSelection, costSel); vis(p.CostSelectionHeader, costSel)
    vis(p.Inflation, isZS); vis(p.Inflation.Header, isZS)
    vis(p.ZeroSumType, isZS); vis(p.ZeroSumTypeHeader, isZS)
    local szHidden = cv == "Percent" or zsStatic
    vis(p.SubZeroBidding, not szHidden)
    vis(p.AllowNegativeBidders, not (szHidden or m.SubZeroBidding == false))
    vis(rc, isRoll)
    local karma = m.RollMode == "Ni Karma"
    vis(rc.UsePerc, not karma); vis(rc.UsePerc.text, not karma); vis(rc.AddMax, not karma); vis(rc.AddMax.Header, not karma)
    vis(rc.maxKarma, karma); vis(rc.maxKarma.Header, karma)
    LayoutModesMain()                                                -- local call (keeps H116's static count at 1)
  end
end

-- AD-36.1.1 (CDKP-028, BR-28.1 / CM-01): the ONE wire shape for CommDKPMinBid / CommDKPMaxBid, used by Modes ->
-- Broadcast Settings AND Options -> Broadcast Min / Max Bids:
--   { <MinBidBySlot | MaxBidBySlot>, { {teamIndex, <that team's CommDKP_MinBids | CommDKP_MaxBids table>}, ... } }
-- one entry per team in core.DB.teams (MinBids = itemID-keyed map, MaxBids = array; AD-12.3, C-28.7).
function CommDKP:BuildBidBroadcastData(kind)
  local isMax = (kind == "max")
  local teamTable = {}
  for _, v in ipairs(CommDKP:GetGuildTeamList(true)) do
    local teamIndex = tostring(v.index)
    table.insert(teamTable, { teamIndex, CommDKP:GetTable(isMax and CommDKP_MaxBids or CommDKP_MinBids, true, teamIndex) })
  end
  return { isMax and core.DB.MaxBidBySlot or core.DB.MinBidBySlot, teamTable }
end
