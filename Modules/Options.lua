local _, core = ...;
local _G = _G;
local CommDKP = core.CommDKP;
local L = core.L;
local W = CommDKP.Widgets
local DD = CommDKP.DD                     -- AD-16.3: selector protocol (ChatFrame)

-- UX §12.3.5 geometry
local OPT_CARD_W = 534                    -- 14 px lane on the right for the pane rail
local OPT_SLOT_CARD_H = 260               -- 3 x 6 slot grid + Broadcast button
local OPT_COL2 = 264                      -- second column offset inside a card body
local OPT_BTN_W = math.floor((OPT_CARD_W - 6 - 2 * 12 - 3 * 8) / 4)   -- 4 equal action buttons
local OPT_SLIDER_W, OPT_SLIDER_X, OPT_SLIDER_GAP = 200, 34, 60

-- Re-skins an Options slider and moves it into its card body. The slider keeps its global "$parent..." name
-- (created as before, so the Low/High/Text globals still resolve); only SetParent/SetWidth change.
local function PlaceSlider(slider, body)
  W.StyleSlider(slider)
  slider:SetWidth(OPT_SLIDER_W)
  slider:SetParent(body)
end

-- 17 slot boxes in 3 columns x 6 rows; the input sits at its column's right edge (label to its left).
local function SlotGridPoint(box, body, i)
  local col, row = math.floor((i - 1) / 6), (i - 1) % 6
  box:SetPoint("TOPLEFT", body, "TOPLEFT", 12 + col * 172 + 172 - 54 - 12, -10 - row * 30)
end
local LibDD = LibStub:GetLibrary("LibUIDropDownMenu-4.0");
local moveTimerToggle = 0;
local validating = false

local function DrawPercFrame(box)
  --Draw % signs if set to percent
  CommDKP.ConfigTab4.DefaultMinBids.SlotBox[box].perc = W.CreateText(CommDKP.ConfigTab4.DefaultMinBids.SlotBox[box], "body", nil, "LEFT", "textMuted")
  CommDKP.ConfigTab4.DefaultMinBids.SlotBox[box].perc:SetPoint("LEFT", CommDKP.ConfigTab4.DefaultMinBids.SlotBox[box], "RIGHT", -15, 0);
  CommDKP.ConfigTab4.DefaultMinBids.SlotBox[box].perc:SetText("%")
  
  if core.DB.modes.mode == "Minimum Bid Values" or (core.DB.modes.mode == "Zero Sum" and core.DB.modes.ZeroSumBidType == "Minimum Bid") then
  CommDKP.ConfigTab4.DefaultMaxBids.SlotBox[box].perc = W.CreateText(CommDKP.ConfigTab4.DefaultMaxBids.SlotBox[box], "body", nil, "LEFT", "textMuted")
    CommDKP.ConfigTab4.DefaultMaxBids.SlotBox[box].perc:SetPoint("LEFT", CommDKP.ConfigTab4.DefaultMaxBids.SlotBox[box], "RIGHT", -15, 0);
    CommDKP.ConfigTab4.DefaultMaxBids.SlotBox[box].perc:SetText("%")
  end
end

local function SaveSettings()
  if CommDKP.ConfigTab4.default[1] then
    core.DB.DKPBonus.OnTimeBonus = CommDKP.ConfigTab4.default[1]:GetNumber();
    core.DB.DKPBonus.BossKillBonus = CommDKP.ConfigTab4.default[2]:GetNumber();
    core.DB.DKPBonus.CompletionBonus = CommDKP.ConfigTab4.default[3]:GetNumber();
    core.DB.DKPBonus.NewBossKillBonus = CommDKP.ConfigTab4.default[4]:GetNumber();
    core.DB.DKPBonus.UnexcusedAbsence = CommDKP.ConfigTab4.default[5]:GetNumber();
    if CommDKP.ConfigTab4.default[6]:GetNumber() < 0 then
      core.DB.DKPBonus.DecayPercentage = 0 - CommDKP.ConfigTab4.default[6]:GetNumber();
    else
      core.DB.DKPBonus.DecayPercentage = CommDKP.ConfigTab4.default[6]:GetNumber();
    end
    CommDKP.ConfigTab2.decayDKP:SetNumber(core.DB.DKPBonus.DecayPercentage);
    CommDKP.ConfigTab4.default[6]:SetNumber(core.DB.DKPBonus.DecayPercentage)
    core.DB.DKPBonus.BidTimer = CommDKP.ConfigTab4.bidTimer:GetNumber();

    core.DB.MinBidBySlot.Head = CommDKP.ConfigTab4.DefaultMinBids.SlotBox[1]:GetNumber()
    core.DB.MinBidBySlot.Neck = CommDKP.ConfigTab4.DefaultMinBids.SlotBox[2]:GetNumber()
    core.DB.MinBidBySlot.Shoulders = CommDKP.ConfigTab4.DefaultMinBids.SlotBox[3]:GetNumber()
    core.DB.MinBidBySlot.Cloak = CommDKP.ConfigTab4.DefaultMinBids.SlotBox[4]:GetNumber()
    core.DB.MinBidBySlot.Chest = CommDKP.ConfigTab4.DefaultMinBids.SlotBox[5]:GetNumber()
    core.DB.MinBidBySlot.Bracers = CommDKP.ConfigTab4.DefaultMinBids.SlotBox[6]:GetNumber()
    core.DB.MinBidBySlot.Hands = CommDKP.ConfigTab4.DefaultMinBids.SlotBox[7]:GetNumber()
    core.DB.MinBidBySlot.Belt = CommDKP.ConfigTab4.DefaultMinBids.SlotBox[8]:GetNumber()
    core.DB.MinBidBySlot.Legs = CommDKP.ConfigTab4.DefaultMinBids.SlotBox[9]:GetNumber()
    core.DB.MinBidBySlot.Boots = CommDKP.ConfigTab4.DefaultMinBids.SlotBox[10]:GetNumber()
    core.DB.MinBidBySlot.Ring = CommDKP.ConfigTab4.DefaultMinBids.SlotBox[11]:GetNumber()
    core.DB.MinBidBySlot.Trinket = CommDKP.ConfigTab4.DefaultMinBids.SlotBox[12]:GetNumber()
    core.DB.MinBidBySlot.OneHanded = CommDKP.ConfigTab4.DefaultMinBids.SlotBox[13]:GetNumber()
    core.DB.MinBidBySlot.TwoHanded = CommDKP.ConfigTab4.DefaultMinBids.SlotBox[14]:GetNumber()
    core.DB.MinBidBySlot.OffHand = CommDKP.ConfigTab4.DefaultMinBids.SlotBox[15]:GetNumber()
    core.DB.MinBidBySlot.Range = CommDKP.ConfigTab4.DefaultMinBids.SlotBox[16]:GetNumber()
    core.DB.MinBidBySlot.Other = CommDKP.ConfigTab4.DefaultMinBids.SlotBox[17]:GetNumber()

    if core.DB.modes.mode == "Minimum Bid Values" or (core.DB.modes.mode == "Zero Sum" and core.DB.modes.ZeroSumBidType == "Minimum Bid") then
      core.DB.MaxBidBySlot.Head = CommDKP.ConfigTab4.DefaultMaxBids.SlotBox[1]:GetNumber()
      core.DB.MaxBidBySlot.Neck = CommDKP.ConfigTab4.DefaultMaxBids.SlotBox[2]:GetNumber()
      core.DB.MaxBidBySlot.Shoulders = CommDKP.ConfigTab4.DefaultMaxBids.SlotBox[3]:GetNumber()
      core.DB.MaxBidBySlot.Cloak = CommDKP.ConfigTab4.DefaultMaxBids.SlotBox[4]:GetNumber()
      core.DB.MaxBidBySlot.Chest = CommDKP.ConfigTab4.DefaultMaxBids.SlotBox[5]:GetNumber()
      core.DB.MaxBidBySlot.Bracers = CommDKP.ConfigTab4.DefaultMaxBids.SlotBox[6]:GetNumber()
      core.DB.MaxBidBySlot.Hands = CommDKP.ConfigTab4.DefaultMaxBids.SlotBox[7]:GetNumber()
      core.DB.MaxBidBySlot.Belt = CommDKP.ConfigTab4.DefaultMaxBids.SlotBox[8]:GetNumber()
      core.DB.MaxBidBySlot.Legs = CommDKP.ConfigTab4.DefaultMaxBids.SlotBox[9]:GetNumber()
      core.DB.MaxBidBySlot.Boots = CommDKP.ConfigTab4.DefaultMaxBids.SlotBox[10]:GetNumber()
      core.DB.MaxBidBySlot.Ring = CommDKP.ConfigTab4.DefaultMaxBids.SlotBox[11]:GetNumber()
      core.DB.MaxBidBySlot.Trinket = CommDKP.ConfigTab4.DefaultMaxBids.SlotBox[12]:GetNumber()
      core.DB.MaxBidBySlot.OneHanded = CommDKP.ConfigTab4.DefaultMaxBids.SlotBox[13]:GetNumber()
      core.DB.MaxBidBySlot.TwoHanded = CommDKP.ConfigTab4.DefaultMaxBids.SlotBox[14]:GetNumber()
      core.DB.MaxBidBySlot.OffHand = CommDKP.ConfigTab4.DefaultMaxBids.SlotBox[15]:GetNumber()
      core.DB.MaxBidBySlot.Range = CommDKP.ConfigTab4.DefaultMaxBids.SlotBox[16]:GetNumber()
      core.DB.MaxBidBySlot.Other = CommDKP.ConfigTab4.DefaultMaxBids.SlotBox[17]:GetNumber()
      end
  end

  core.CommDKPUI:SetScale(core.DB.defaults.CommDKPScaleSize);
  core.DB.defaults.HistoryLimit = CommDKP.ConfigTab4.history:GetNumber();
  core.DB.defaults.DKPHistoryLimit = CommDKP.ConfigTab4.DKPHistory:GetNumber();
  core.DB.defaults.TooltipHistoryCount = CommDKP.ConfigTab4.TooltipHistory:GetNumber();
  CommDKP:DKPTable_Update()
end

function CommDKP:RefreshOptionsUI()
  -- AD-36.1.3 (BR-28.3, C-28.3): the Pricing tab follows received MinBid / MaxBid values even if Tab 4 was never built.
  -- No argument = sort + scroll offset kept (AD-25); the redraw no-ops until Tab 7 exists.
  if CommDKP.RefreshPriceTable then CommDKP:RefreshPriceTable() end
  local tab4 = CommDKP.ConfigTab4
  if not tab4 then return end
  -- N-34.3 (AD-34.8): guarded writes; an older sender with missing keys must not raise inside a comm handler.
  local function put(box, v) if box and v ~= nil then box:SetText(tostring(v)) end end
  if tab4.default and tab4.default[1] and core.DB and core.DB.DKPBonus then
    local b = core.DB.DKPBonus
    put(tab4.default[1], b.OnTimeBonus)
    put(tab4.default[2], b.BossKillBonus)
    put(tab4.default[3], b.CompletionBonus)
    put(tab4.default[4], b.NewBossKillBonus)
    put(tab4.default[5], b.UnexcusedAbsence)
    put(tab4.default[6], b.DecayPercentage)
    if tonumber(b.DecayPercentage) and CommDKP.ConfigTab2 and CommDKP.ConfigTab2.decayDKP then
      CommDKP.ConfigTab2.decayDKP:SetNumber(tonumber(b.DecayPercentage))
    end
    if tonumber(b.BidTimer) and tab4.bidTimerSlider then tab4.bidTimerSlider:SetValue(tonumber(b.BidTimer)) end
    put(tab4.bidTimer, b.BidTimer)
  end
  local SLOTS = { "Head", "Neck", "Shoulders", "Cloak", "Chest", "Bracers", "Hands", "Belt", "Legs", "Boots", "Ring", "Trinket", "OneHanded", "TwoHanded", "OffHand", "Range", "Other" }
  if tab4.DefaultMinBids and tab4.DefaultMinBids.SlotBox and core.DB and core.DB.MinBidBySlot then
    for i = 1, 17 do
      put(tab4.DefaultMinBids.SlotBox[i], core.DB.MinBidBySlot[SLOTS[i]])
    end
  end
  if tab4.DefaultMaxBids and tab4.DefaultMaxBids.SlotBox and core.DB and core.DB.MaxBidBySlot then
    for i = 1, 17 do
      put(tab4.DefaultMaxBids.SlotBox[i], core.DB.MaxBidBySlot[SLOTS[i]])
    end
  end
end

function CommDKP:Options()
  local default = {}
  CommDKP.ConfigTab4.default = default;
  CommDKP:CheckOfficer()

  -- UX §12.3.5: the pane is a stack of 534 px cards (the 14 px lane on the right holds the pane rail). No in-pane
  -- heading (Q7). Only the groups that exist for this user (officer / mode) get a card, so the stack closes up.
  local tab4 = CommDKP.ConfigTab4
  local stackY = 0
  local function NextCard(title, h)
    local card = W.CreateCard(tab4, title, OPT_CARD_W, h)
    card:SetPoint("TOPLEFT", tab4, "TOPLEFT", 0, -stackY)
    stackY = stackY + h + W.GUT
    return card, card.Body
  end
  local awardBody, minBody, maxBody
  local function GenBody()                 -- General card: created by the first control that needs it
    if not tab4.GeneralCard then tab4.GeneralCard = NextCard(L["CARDGENERAL"], 340) end
    return tab4.GeneralCard.Body
  end

  -- AD-20.3.1 (CDKP-013b, BR-13.3.1): the Actions card is created first so it sits at the pane top (y = 0).
  -- Its buttons are created further down and re-parented into it by ActionSlot(), so creation order is irrelevant.
  local actBody
  tab4.ActionsCard, actBody = NextCard(L["CARDACTIONS"], 71)
  local function ActionSlot(btn, col, tone)
    btn:SetParent(actBody)
    btn:SetSize(OPT_BTN_W, W.H)
    btn:ClearAllPoints()
    btn:SetPoint("LEFT", actBody, "LEFT", W.PAD + (col - 1) * (OPT_BTN_W + W.GUT), 0)
    W.StyleButton(btn, tone)
  end

  if core.IsOfficer == true then
    tab4.AwardCard, awardBody = NextCard(L["DEFAULTDKPAWARDVALUES"], 131)
    CommDKP.ConfigTab4.description = tab4.AwardCard.Header.Title      -- legacy key: the old gold sub-heading is the card title
  
    for i=1, 6 do
      CommDKP.ConfigTab4.default[i] = CreateFrame("EditBox", nil, awardBody, "BackdropTemplate")
            
      CommDKP.ConfigTab4.default[i]:SetAutoFocus(false)
      CommDKP.ConfigTab4.default[i]:SetMultiLine(false)
      CommDKP.ConfigTab4.default[i]:SetSize(60, W.H)
      CommDKP.ConfigTab4.default[i]:SetMaxLetters(6)
      CommDKP.ConfigTab4.default[i]:SetTextColor(1, 1, 1, 1)
      CommDKP.ConfigTab4.default[i]:SetTextInsets(10, 10, 5, 5)
      CommDKP.ConfigTab4.default[i]:SetScript("OnEscapePressed", function(self)    -- clears focus on esc
        self:HighlightText(0,0)
        SaveSettings()
        self:ClearFocus()
      end)
      CommDKP.ConfigTab4.default[i]:SetScript("OnEnterPressed", function(self)    -- clears focus on esc
        self:HighlightText(0,0)
        SaveSettings()
        self:ClearFocus()
      end)
      CommDKP.ConfigTab4.default[i]:SetScript("OnTabPressed", function(self)    -- clears focus on esc
        SaveSettings()
        if i == 6 then
          self:HighlightText(0,0)
          CommDKP.ConfigTab4.DefaultMinBids.SlotBox[1]:SetFocus()
          CommDKP.ConfigTab4.DefaultMinBids.SlotBox[1]:HighlightText()
        else
          self:HighlightText(0,0)
          CommDKP.ConfigTab4.default[i+1]:SetFocus()
          CommDKP.ConfigTab4.default[i+1]:HighlightText()
        end
      end)
      CommDKP.ConfigTab4.default[i]:SetScript("OnEnter", function(self)
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
      CommDKP.ConfigTab4.default[i]:SetScript("OnLeave", function(self)
        GameTooltip:Hide()
      end)
      W.StyleEditBox(CommDKP.ConfigTab4.default[i], { numeric = true })   -- after its own SetScripts (hooks chain)

      -- §12.3.5: 2 columns x 3 rows; the input sits at its column's right edge, the label to its left.
      local col, row = (i <= 3) and 0 or 1, (i - 1) % 3
      CommDKP.ConfigTab4.default[i]:SetPoint("TOPLEFT", awardBody, "TOPLEFT", 190 + col * 264, -10 - row * 32)
    end

    -- Modes Button
    CommDKP.ConfigTab4.ModesButton = self:CreateButton("TOPRIGHT", CommDKP.ConfigTab4, "TOPRIGHT", -40, -20, L["DKPMODES"]);
    CommDKP.ConfigTab4.ModesButton:SetSize(OPT_BTN_W, W.H)
    CommDKP.ConfigTab4.ModesButton:SetScript("OnClick", function()
      if core.IsOfficer ~= true then return end            -- AD-20.2.5 (PM-13.3): click-time officer gate
      CommDKP:ToggleDKPModesWindow()
    end);
    CommDKP.ConfigTab4.ModesButton:SetScript("OnEnter", function(self)
      GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
      GameTooltip:SetText(L["DKPMODES"], 0.25, 0.75, 0.90, 1, true)
      GameTooltip:AddLine(L["DKPMODESTTDESC2"], 1.0, 1.0, 1.0, true);
      GameTooltip:AddLine(L["DKPMODESTTWARN"], 1.0, 0, 0, true);
      GameTooltip:Show()
    end)
    CommDKP.ConfigTab4.ModesButton:SetScript("OnLeave", function()
    GameTooltip:Hide()
    end)
    if not core.IsOfficer then
      CommDKP.ConfigTab4.ModesButton:Hide()
    end
    CommDKP.ConfigTab4.default[1]:SetText(core.DB.DKPBonus.OnTimeBonus)
    CommDKP.ConfigTab4.default[1].tooltipText = L["ONTIMEBONUS"]
    CommDKP.ConfigTab4.default[1].tooltipDescription = L["ONTIMEBONUSTTDESC"]
      
    CommDKP.ConfigTab4.default[2]:SetText(core.DB.DKPBonus.BossKillBonus)
    CommDKP.ConfigTab4.default[2].tooltipText = L["BOSSKILLBONUS"]
    CommDKP.ConfigTab4.default[2].tooltipDescription = L["BOSSKILLBONUSTTDESC"]
       
    CommDKP.ConfigTab4.default[3]:SetText(core.DB.DKPBonus.CompletionBonus)
    CommDKP.ConfigTab4.default[3].tooltipText = L["RAIDCOMPLETIONBONUS"]
    CommDKP.ConfigTab4.default[3].tooltipDescription = L["RAIDCOMPLETEBONUSTT"]
      
    CommDKP.ConfigTab4.default[4]:SetText(core.DB.DKPBonus.NewBossKillBonus)
    CommDKP.ConfigTab4.default[4].tooltipText = L["NEWBOSSKILLBONUS"]
    CommDKP.ConfigTab4.default[4].tooltipDescription = L["NEWBOSSKILLTTDESC"]

    CommDKP.ConfigTab4.default[5]:SetText(core.DB.DKPBonus.UnexcusedAbsence)
    CommDKP.ConfigTab4.default[5]:SetNumeric(false)
    CommDKP.ConfigTab4.default[5].tooltipText = L["UNEXCUSEDABSENCE"]
    CommDKP.ConfigTab4.default[5].tooltipDescription = L["UNEXCUSEDTTDESC"]
    CommDKP.ConfigTab4.default[5].tooltipWarning = L["UNEXCUSEDTTWARN"]

    CommDKP.ConfigTab4.default[6]:SetText(core.DB.DKPBonus.DecayPercentage)
    CommDKP.ConfigTab4.default[6]:SetTextInsets(0, 15, 0, 0)
    CommDKP.ConfigTab4.default[6].tooltipText = L["DECAYPERCENTAGE"]
    CommDKP.ConfigTab4.default[6].tooltipDescription = L["DECAYPERCENTAGETTDESC"]
    CommDKP.ConfigTab4.default[6].tooltipWarning = L["DECAYPERCENTAGETTWARN"]

    --OnTimeBonus Header
    CommDKP.ConfigTab4.OnTimeHeader = W.CreateText(awardBody, "body", nil, "RIGHT")
    CommDKP.ConfigTab4.OnTimeHeader:SetPoint("RIGHT", CommDKP.ConfigTab4.default[1], "LEFT", -8, 0);
    CommDKP.ConfigTab4.OnTimeHeader:SetText(L["ONTIMEBONUS"])

    --BossKillBonus Header
    CommDKP.ConfigTab4.BossKillHeader = W.CreateText(awardBody, "body", nil, "RIGHT")
    CommDKP.ConfigTab4.BossKillHeader:SetPoint("RIGHT", CommDKP.ConfigTab4.default[2], "LEFT", -8, 0);
    CommDKP.ConfigTab4.BossKillHeader:SetText(L["BOSSKILLBONUS"])

    --CompletionBonus Header
    CommDKP.ConfigTab4.CompleteHeader = W.CreateText(awardBody, "body", nil, "RIGHT")
    CommDKP.ConfigTab4.CompleteHeader:SetPoint("RIGHT", CommDKP.ConfigTab4.default[3], "LEFT", -8, 0);
    CommDKP.ConfigTab4.CompleteHeader:SetText(L["RAIDCOMPLETIONBONUS"])

    --NewBossKillBonus Header
    CommDKP.ConfigTab4.NewBossHeader = W.CreateText(awardBody, "body", nil, "RIGHT")
    CommDKP.ConfigTab4.NewBossHeader:SetPoint("RIGHT", CommDKP.ConfigTab4.default[4], "LEFT", -8, 0);
    CommDKP.ConfigTab4.NewBossHeader:SetText(L["NEWBOSSKILLBONUS"])

    --UnexcusedAbsence Header
    CommDKP.ConfigTab4.UnexcusedHeader = W.CreateText(awardBody, "body", nil, "RIGHT")
    CommDKP.ConfigTab4.UnexcusedHeader:SetPoint("RIGHT", CommDKP.ConfigTab4.default[5], "LEFT", -8, 0);
    CommDKP.ConfigTab4.UnexcusedHeader:SetText(L["UNEXCUSEDABSENCE"])

    --DKP Decay Header
    CommDKP.ConfigTab4.DecayHeader = W.CreateText(awardBody, "body", nil, "RIGHT")
    CommDKP.ConfigTab4.DecayHeader:SetPoint("RIGHT", CommDKP.ConfigTab4.default[6], "LEFT", -8, 0);
    CommDKP.ConfigTab4.DecayHeader:SetText(L["DECAYAMOUNT"])

    CommDKP.ConfigTab4.DecayFooter = W.CreateText(CommDKP.ConfigTab4.default[6], "body", nil, "RIGHT", "textMuted")
    CommDKP.ConfigTab4.DecayFooter:SetPoint("LEFT", CommDKP.ConfigTab4.default[6], "RIGHT", -15, -1);
    CommDKP.ConfigTab4.DecayFooter:SetText("%")

    -- Default Minimum Bids Container Frame
    -- DefaultMinBids IS the card (key kept); its mode-dependent description text is the card title.
    CommDKP.ConfigTab4.DefaultMinBids, minBody = NextCard(L["DEFAULTMINBIDVALUES"], OPT_SLOT_CARD_H)
    CommDKP.ConfigTab4.DefaultMinBids.description = CommDKP.ConfigTab4.DefaultMinBids.Header.Title
      -- DEFAULT min bids Create EditBoxes
      local SlotBox = {}
      CommDKP.ConfigTab4.DefaultMinBids.SlotBox = SlotBox;

      for i=1, 17 do

        CommDKP.ConfigTab4.DefaultMinBids.SlotBox[i] = CreateFrame("EditBox", nil, minBody, "BackdropTemplate")
        
        CommDKP.ConfigTab4.DefaultMinBids.SlotBox[i]:SetAutoFocus(false)
        CommDKP.ConfigTab4.DefaultMinBids.SlotBox[i]:SetMultiLine(false)
        CommDKP.ConfigTab4.DefaultMinBids.SlotBox[i]:SetSize(54, W.H)
        CommDKP.ConfigTab4.DefaultMinBids.SlotBox[i]:SetMaxLetters(6)
        CommDKP.ConfigTab4.DefaultMinBids.SlotBox[i]:SetTextColor(1, 1, 1, 1)
        CommDKP.ConfigTab4.DefaultMinBids.SlotBox[i]:SetTextInsets(10, 10, 5, 5)
        CommDKP.ConfigTab4.DefaultMinBids.SlotBox[i]:SetScript("OnEscapePressed", function(self)    -- clears focus on esc
          self:HighlightText(0,0)
          SaveSettings()
          self:ClearFocus()
        end)
        CommDKP.ConfigTab4.DefaultMinBids.SlotBox[i]:SetScript("OnEnterPressed", function(self)    -- clears focus on esc
          self:HighlightText(0,0)
          SaveSettings()
          self:ClearFocus()
        end)
        CommDKP.ConfigTab4.DefaultMinBids.SlotBox[i]:SetScript("OnTabPressed", function(self)    -- clears focus on esc
          if i == 8 then
            self:HighlightText(0,0)
            CommDKP.ConfigTab4.DefaultMinBids.SlotBox[17]:SetFocus()
            CommDKP.ConfigTab4.DefaultMinBids.SlotBox[17]:HighlightText()
            SaveSettings()
          elseif i == 5 then
            self:HighlightText(0,0)
            CommDKP.UIConfig.TabMenu.ScrollFrame:SetVerticalScroll(200)
            CommDKP.ConfigTab4.DefaultMinBids.SlotBox[i+1]:SetFocus()
            CommDKP.ConfigTab4.DefaultMinBids.SlotBox[i+1]:HighlightText()
            SaveSettings()
          elseif i == 13 then
            self:HighlightText(0,0)
            CommDKP.UIConfig.TabMenu.ScrollFrame:SetVerticalScroll(200)
            CommDKP.ConfigTab4.DefaultMinBids.SlotBox[14]:SetFocus()
            CommDKP.ConfigTab4.DefaultMinBids.SlotBox[14]:HighlightText()
            SaveSettings()
          elseif i == 17 then
            self:HighlightText(0,0)
            CommDKP.ConfigTab4.DefaultMinBids.SlotBox[9]:SetFocus()
            CommDKP.ConfigTab4.DefaultMinBids.SlotBox[9]:HighlightText()
            SaveSettings()
          elseif i == 16 then
            self:HighlightText(0,0)
            CommDKP.UIConfig.TabMenu.ScrollFrame:SetVerticalScroll(1)
            CommDKP.ConfigTab4.default[1]:SetFocus()
            CommDKP.ConfigTab4.default[1]:HighlightText()
            SaveSettings()
          else
            self:HighlightText(0,0)
            CommDKP.ConfigTab4.DefaultMinBids.SlotBox[i+1]:SetFocus()
            CommDKP.ConfigTab4.DefaultMinBids.SlotBox[i+1]:HighlightText()
            SaveSettings()
          end
        end)
        CommDKP.ConfigTab4.DefaultMinBids.SlotBox[i]:SetScript("OnEnter", function(self)
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
        CommDKP.ConfigTab4.DefaultMinBids.SlotBox[i]:SetScript("OnLeave", function(self)
          GameTooltip:Hide()
        end)

        W.StyleEditBox(CommDKP.ConfigTab4.DefaultMinBids.SlotBox[i], { numeric = true })   -- after its own SetScripts

        -- Slot Headers
        CommDKP.ConfigTab4.DefaultMinBids.SlotBox[i].Header = W.CreateText(minBody, "body", nil, "RIGHT")
        CommDKP.ConfigTab4.DefaultMinBids.SlotBox[i].Header:SetPoint("RIGHT", CommDKP.ConfigTab4.DefaultMinBids.SlotBox[i], "LEFT", -6, 0);

        SlotGridPoint(CommDKP.ConfigTab4.DefaultMinBids.SlotBox[i], minBody, i)   -- §12.3.5: 3 columns x 6 rows
      end

      local prefix;
      if core.DB.modes.mode == "Minimum Bid Values" then
        prefix = L["MINIMUMBID"];
        CommDKP.ConfigTab4.DefaultMinBids.description:SetText("|CFFcca600"..L["DEFAULTMINBIDVALUES"].."|r");
      elseif core.DB.modes.mode == "Static Item Values" then
        CommDKP.ConfigTab4.DefaultMinBids.description:SetText("|CFFcca600"..L["DEFAULTITEMCOSTS"].."|r");
        if core.DB.modes.costvalue == "Integer" then
          prefix = L["DKPPRICE"]
        elseif core.DB.modes.costvalue == "Percent" then
          prefix = L["PERCENTCOST"]
        end
      elseif core.DB.modes.mode == "Roll Based Bidding" then
        CommDKP.ConfigTab4.DefaultMinBids.description:SetText("|CFFcca600"..L["DEFAULTITEMCOSTS"].."|r");
        if core.DB.modes.costvalue == "Integer" then
          prefix = L["DKPPRICE"]
        elseif core.DB.modes.costvalue == "Percent" then
          prefix = L["PERCENTCOST"]
        end
      elseif core.DB.modes.mode == "Zero Sum" then
        CommDKP.ConfigTab4.DefaultMinBids.description:SetText("|CFFcca600"..L["DEFAULTITEMCOSTS"].."|r");
        if core.DB.modes.costvalue == "Integer" then
          prefix = L["DKPPRICE"]
        elseif core.DB.modes.costvalue == "Percent" then
          prefix = L["PERCENTCOST"]
        end
      end
      CommDKP.ConfigTab4.DefaultMinBids.SlotBox[1].Header:SetText(L["HEAD"]..": ")
      CommDKP.ConfigTab4.DefaultMinBids.SlotBox[1]:SetText(core.DB.MinBidBySlot.Head)
      CommDKP.ConfigTab4.DefaultMinBids.SlotBox[1].tooltipText = L["HEAD"]
      CommDKP.ConfigTab4.DefaultMinBids.SlotBox[1].tooltipDescription = prefix.." "..L["FORHEADSLOT"]

      CommDKP.ConfigTab4.DefaultMinBids.SlotBox[2].Header:SetText(L["NECK"]..": ")
      CommDKP.ConfigTab4.DefaultMinBids.SlotBox[2]:SetText(core.DB.MinBidBySlot.Neck)
      CommDKP.ConfigTab4.DefaultMinBids.SlotBox[2].tooltipText = L["NECK"]
      CommDKP.ConfigTab4.DefaultMinBids.SlotBox[2].tooltipDescription = prefix.." "..L["FORNECKSLOT"]

      CommDKP.ConfigTab4.DefaultMinBids.SlotBox[3].Header:SetText(L["SHOULDERS"]..": ")
      CommDKP.ConfigTab4.DefaultMinBids.SlotBox[3]:SetText(core.DB.MinBidBySlot.Shoulders)
      CommDKP.ConfigTab4.DefaultMinBids.SlotBox[3].tooltipText = L["SHOULDERS"]
      CommDKP.ConfigTab4.DefaultMinBids.SlotBox[3].tooltipDescription = prefix.." "..L["FORSHOULDERSLOT"]

      CommDKP.ConfigTab4.DefaultMinBids.SlotBox[4].Header:SetText(L["CLOAK"]..": ")
      CommDKP.ConfigTab4.DefaultMinBids.SlotBox[4]:SetText(core.DB.MinBidBySlot.Cloak)
      CommDKP.ConfigTab4.DefaultMinBids.SlotBox[4].tooltipText = L["CLOAK"]
      CommDKP.ConfigTab4.DefaultMinBids.SlotBox[4].tooltipDescription = prefix.." "..L["FORBACKSLOT"]

      CommDKP.ConfigTab4.DefaultMinBids.SlotBox[5].Header:SetText(L["CHEST"]..": ")
      CommDKP.ConfigTab4.DefaultMinBids.SlotBox[5]:SetText(core.DB.MinBidBySlot.Chest)
      CommDKP.ConfigTab4.DefaultMinBids.SlotBox[5].tooltipText = L["CHEST"]
      CommDKP.ConfigTab4.DefaultMinBids.SlotBox[5].tooltipDescription = prefix.." "..L["FORCHESTSLOT"]

      CommDKP.ConfigTab4.DefaultMinBids.SlotBox[6].Header:SetText(L["BRACERS"]..": ")
      CommDKP.ConfigTab4.DefaultMinBids.SlotBox[6]:SetText(core.DB.MinBidBySlot.Bracers)
      CommDKP.ConfigTab4.DefaultMinBids.SlotBox[6].tooltipText = L["BRACERS"]
      CommDKP.ConfigTab4.DefaultMinBids.SlotBox[6].tooltipDescription = prefix.." "..L["FORWRISTSLOT"]

      CommDKP.ConfigTab4.DefaultMinBids.SlotBox[7].Header:SetText(L["HANDS"]..": ")
      CommDKP.ConfigTab4.DefaultMinBids.SlotBox[7]:SetText(core.DB.MinBidBySlot.Hands)
      CommDKP.ConfigTab4.DefaultMinBids.SlotBox[7].tooltipText = L["HANDS"]
      CommDKP.ConfigTab4.DefaultMinBids.SlotBox[7].tooltipDescription = prefix.." "..L["FORHANDSLOT"]

      CommDKP.ConfigTab4.DefaultMinBids.SlotBox[8].Header:SetText(L["BELT"]..": ")
      CommDKP.ConfigTab4.DefaultMinBids.SlotBox[8]:SetText(core.DB.MinBidBySlot.Belt)
      CommDKP.ConfigTab4.DefaultMinBids.SlotBox[8].tooltipText = L["BELT"]
      CommDKP.ConfigTab4.DefaultMinBids.SlotBox[8].tooltipDescription = prefix.." "..L["FORWAISTSLOT"]

      CommDKP.ConfigTab4.DefaultMinBids.SlotBox[9].Header:SetText(L["LEGS"]..": ")
      CommDKP.ConfigTab4.DefaultMinBids.SlotBox[9]:SetText(core.DB.MinBidBySlot.Legs)
      CommDKP.ConfigTab4.DefaultMinBids.SlotBox[9].tooltipText = L["LEGS"]
      CommDKP.ConfigTab4.DefaultMinBids.SlotBox[9].tooltipDescription = prefix.." "..L["FORLEGSLOT"]

      CommDKP.ConfigTab4.DefaultMinBids.SlotBox[10].Header:SetText(L["BOOTS"]..": ")
      CommDKP.ConfigTab4.DefaultMinBids.SlotBox[10]:SetText(core.DB.MinBidBySlot.Boots)
      CommDKP.ConfigTab4.DefaultMinBids.SlotBox[10].tooltipText = L["BOOTS"]
      CommDKP.ConfigTab4.DefaultMinBids.SlotBox[10].tooltipDescription = prefix.." "..L["FORFEETSLOT"]

      CommDKP.ConfigTab4.DefaultMinBids.SlotBox[11].Header:SetText(L["RINGS"]..": ")
      CommDKP.ConfigTab4.DefaultMinBids.SlotBox[11]:SetText(core.DB.MinBidBySlot.Ring)
      CommDKP.ConfigTab4.DefaultMinBids.SlotBox[11].tooltipText = L["RINGS"]
      CommDKP.ConfigTab4.DefaultMinBids.SlotBox[11].tooltipDescription = prefix.." "..L["FORFINGERSLOT"]

      CommDKP.ConfigTab4.DefaultMinBids.SlotBox[12].Header:SetText(L["TRINKET"]..": ")
      CommDKP.ConfigTab4.DefaultMinBids.SlotBox[12]:SetText(core.DB.MinBidBySlot.Trinket)
      CommDKP.ConfigTab4.DefaultMinBids.SlotBox[12].tooltipText = L["TRINKET"]
      CommDKP.ConfigTab4.DefaultMinBids.SlotBox[12].tooltipDescription = prefix.." "..L["FORTRINKETSLOT"]

      CommDKP.ConfigTab4.DefaultMinBids.SlotBox[13].Header:SetText(L["ONEHANDED"]..": ")
      CommDKP.ConfigTab4.DefaultMinBids.SlotBox[13]:SetText(core.DB.MinBidBySlot.OneHanded)
      CommDKP.ConfigTab4.DefaultMinBids.SlotBox[13].tooltipText = L["ONEHANDEDWEAPONS"]
      CommDKP.ConfigTab4.DefaultMinBids.SlotBox[13].tooltipDescription = prefix.." "..L["FORONEHANDSLOT"]

      CommDKP.ConfigTab4.DefaultMinBids.SlotBox[14].Header:SetText(L["TWOHANDED"]..": ")
      CommDKP.ConfigTab4.DefaultMinBids.SlotBox[14]:SetText(core.DB.MinBidBySlot.TwoHanded)
      CommDKP.ConfigTab4.DefaultMinBids.SlotBox[14].tooltipText = L["TWOHANDEDWEAPONS"]
      CommDKP.ConfigTab4.DefaultMinBids.SlotBox[14].tooltipDescription = prefix.." "..L["FORTWOHANDSLOT"]

      CommDKP.ConfigTab4.DefaultMinBids.SlotBox[15].Header:SetText(L["OFFHAND"]..": ")
      CommDKP.ConfigTab4.DefaultMinBids.SlotBox[15]:SetText(core.DB.MinBidBySlot.OffHand)
      CommDKP.ConfigTab4.DefaultMinBids.SlotBox[15].tooltipText = L["OFFHANDITEMS"]
      CommDKP.ConfigTab4.DefaultMinBids.SlotBox[15].tooltipDescription = prefix.." "..L["FOROFFHANDSLOT"]

      CommDKP.ConfigTab4.DefaultMinBids.SlotBox[16].Header:SetText(L["RANGE"]..": ")
      CommDKP.ConfigTab4.DefaultMinBids.SlotBox[16]:SetText(core.DB.MinBidBySlot.Range)
      CommDKP.ConfigTab4.DefaultMinBids.SlotBox[16].tooltipText = L["RANGE"]
      CommDKP.ConfigTab4.DefaultMinBids.SlotBox[16].tooltipDescription = prefix.." "..L["FORRANGESLOT"]

      CommDKP.ConfigTab4.DefaultMinBids.SlotBox[17].Header:SetText(L["OTHER"]..": ")
      CommDKP.ConfigTab4.DefaultMinBids.SlotBox[17]:SetText(core.DB.MinBidBySlot.Other)
      CommDKP.ConfigTab4.DefaultMinBids.SlotBox[17].tooltipText = L["OTHER"]
      CommDKP.ConfigTab4.DefaultMinBids.SlotBox[17].tooltipDescription = prefix.." "..L["FOROTHERSLOT"]

      if core.DB.modes.costvalue == "Percent" then
        for i=1, #CommDKP.ConfigTab4.DefaultMinBids.SlotBox do
          DrawPercFrame(i)
          CommDKP.ConfigTab4.DefaultMinBids.SlotBox[i]:SetTextInsets(0, 15, 0, 0)
        end
      end
      -- Broadcast Minimum Bids Button
      CommDKP.ConfigTab4.BroadcastMinBids = self:CreateButton("TOP", CommDKP.ConfigTab4, "BOTTOM", 30, 30, L["BCASTVALUES"]);
      CommDKP.ConfigTab4.BroadcastMinBids:ClearAllPoints();
      CommDKP.ConfigTab4.BroadcastMinBids:SetParent(minBody)
      CommDKP.ConfigTab4.BroadcastMinBids:SetPoint("BOTTOMRIGHT", minBody, "BOTTOMRIGHT", -W.PAD, W.PAD)
      CommDKP.ConfigTab4.BroadcastMinBids:SetSize(140, W.H)
      CommDKP.ConfigTab4.BroadcastMinBids:SetScript("OnClick", function()
        if core.IsOfficer ~= true then return end          -- AD-20.2.5 (PM-13.3): click-time officer gate
        StaticPopupDialogs["SEND_MINBIDS"] = {
          text = L["BCASTMINBIDCONFIRM"],
          button1 = L["YES"],
          button2 = L["NO"],
          OnAccept = function()
            SaveSettings()
            CommDKP.Sync:SendData("CommDKPMinBid", CommDKP:BuildBidBroadcastData("min"))   -- AD-36.1.1
            CommDKP:Print(L["MINBIDVALUESSENT"])
          end,
          timeout = 0,
          whileDead = true,
          hideOnEscape = true,
          preferredIndex = 3,
        }
        StaticPopup_Show ("SEND_MINBIDS")
      end);
      CommDKP.ConfigTab4.BroadcastMinBids:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText(L["BCASTVALUES"], 0.25, 0.75, 0.90, 1, true)
        GameTooltip:AddLine(L["BCASTVALUESTTDESC"], 1.0, 1.0, 1.0, true);
        GameTooltip:AddLine(L["BCASTVALUESTTWARN"], 1.0, 0, 0, true);
        GameTooltip:Show()
      end)
      CommDKP.ConfigTab4.BroadcastMinBids:SetScript("OnLeave", function()
        GameTooltip:Hide()
      end)
    -- Default Maximum Bids Container Frame
    if core.DB.modes.mode == "Minimum Bid Values" or (core.DB.modes.mode == "Zero Sum" and core.DB.modes.ZeroSumBidType == "Minimum Bid") then
      CommDKP.ConfigTab4.DefaultMaxBids, maxBody = NextCard(L["DEFAULTMAXBIDVALUES"], OPT_SLOT_CARD_H)
      CommDKP.ConfigTab4.DefaultMaxBids.description = CommDKP.ConfigTab4.DefaultMaxBids.Header.Title

      -- DEFAULT Max bids Create EditBoxes
      local SlotBox = {}
      CommDKP.ConfigTab4.DefaultMaxBids.SlotBox = SlotBox;

      for i=1, 17 do
        CommDKP.ConfigTab4.DefaultMaxBids.SlotBox[i] = CreateFrame("EditBox", nil, maxBody, "BackdropTemplate")

        
        CommDKP.ConfigTab4.DefaultMaxBids.SlotBox[i]:SetAutoFocus(false)
        CommDKP.ConfigTab4.DefaultMaxBids.SlotBox[i]:SetMultiLine(false)
        CommDKP.ConfigTab4.DefaultMaxBids.SlotBox[i]:SetSize(54, W.H)
        CommDKP.ConfigTab4.DefaultMaxBids.SlotBox[i]:SetMaxLetters(6)
        CommDKP.ConfigTab4.DefaultMaxBids.SlotBox[i]:SetTextColor(1, 1, 1, 1)
        CommDKP.ConfigTab4.DefaultMaxBids.SlotBox[i]:SetTextInsets(10, 10, 5, 5)
        CommDKP.ConfigTab4.DefaultMaxBids.SlotBox[i]:SetScript("OnEscapePressed", function(self)    -- clears focus on esc
          self:HighlightText(0,0)
          SaveSettings()
          self:ClearFocus()
        end)
        CommDKP.ConfigTab4.DefaultMaxBids.SlotBox[i]:SetScript("OnEnterPressed", function(self)    -- clears focus on esc
          self:HighlightText(0,0)
          SaveSettings()
          self:ClearFocus()
        end)
        CommDKP.ConfigTab4.DefaultMaxBids.SlotBox[i]:SetScript("OnTabPressed", function(self)    -- clears focus on esc
          if i == 8 then
            self:HighlightText(0,0)
            CommDKP.ConfigTab4.DefaultMaxBids.SlotBox[17]:SetFocus()
            CommDKP.ConfigTab4.DefaultMaxBids.SlotBox[17]:HighlightText()
            SaveSettings()
          elseif i == 5 then
            self:HighlightText(0,0)
            CommDKP.UIConfig.TabMenu.ScrollFrame:SetVerticalScroll(200)
            CommDKP.ConfigTab4.DefaultMaxBids.SlotBox[i+1]:SetFocus()
            CommDKP.ConfigTab4.DefaultMaxBids.SlotBox[i+1]:HighlightText()
            SaveSettings()
          elseif i == 13 then
            self:HighlightText(0,0)
            CommDKP.UIConfig.TabMenu.ScrollFrame:SetVerticalScroll(200)
            CommDKP.ConfigTab4.DefaultMaxBids.SlotBox[14]:SetFocus()
            CommDKP.ConfigTab4.DefaultMaxBids.SlotBox[14]:HighlightText()
            SaveSettings()
          elseif i == 17 then
            self:HighlightText(0,0)
            CommDKP.ConfigTab4.DefaultMaxBids.SlotBox[9]:SetFocus()
            CommDKP.ConfigTab4.DefaultMaxBids.SlotBox[9]:HighlightText()
            SaveSettings()
          elseif i == 16 then
            self:HighlightText(0,0)
            CommDKP.UIConfig.TabMenu.ScrollFrame:SetVerticalScroll(1)
            CommDKP.ConfigTab4.default[1]:SetFocus()
            CommDKP.ConfigTab4.default[1]:HighlightText()
            SaveSettings()
          else
            self:HighlightText(0,0)
            CommDKP.ConfigTab4.DefaultMaxBids.SlotBox[i+1]:SetFocus()
            CommDKP.ConfigTab4.DefaultMaxBids.SlotBox[i+1]:HighlightText()
            SaveSettings()
          end
        end)
        CommDKP.ConfigTab4.DefaultMaxBids.SlotBox[i]:SetScript("OnEnter", function(self)
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
        CommDKP.ConfigTab4.DefaultMaxBids.SlotBox[i]:SetScript("OnLeave", function(self)
          GameTooltip:Hide()
        end)

        -- Slot Headers
        W.StyleEditBox(CommDKP.ConfigTab4.DefaultMaxBids.SlotBox[i], { numeric = true })   -- after its own SetScripts

        CommDKP.ConfigTab4.DefaultMaxBids.SlotBox[i].Header = W.CreateText(maxBody, "body", nil, "RIGHT")
        CommDKP.ConfigTab4.DefaultMaxBids.SlotBox[i].Header:SetPoint("RIGHT", CommDKP.ConfigTab4.DefaultMaxBids.SlotBox[i], "LEFT", -6, 0);

        SlotGridPoint(CommDKP.ConfigTab4.DefaultMaxBids.SlotBox[i], maxBody, i)   -- §12.3.5: 3 columns x 6 rows
      end

      local prefix;

      prefix = L["MAXIMUMBID"];
      CommDKP.ConfigTab4.DefaultMaxBids.description:SetText("|CFFcca600"..L["DEFAULTMAXBIDVALUES"].."|r");

      CommDKP.ConfigTab4.DefaultMaxBids.SlotBox[1].Header:SetText(L["HEAD"]..": ")
      CommDKP.ConfigTab4.DefaultMaxBids.SlotBox[1]:SetText(core.DB.MaxBidBySlot.Head)
      CommDKP.ConfigTab4.DefaultMaxBids.SlotBox[1].tooltipText = L["HEAD"]
      CommDKP.ConfigTab4.DefaultMaxBids.SlotBox[1].tooltipDescription = prefix.." "..L["FORHEADSLOT"].." "..L["MAXIMUMBIDTTDESC"]
       
      CommDKP.ConfigTab4.DefaultMaxBids.SlotBox[2].Header:SetText(L["NECK"]..": ")
      CommDKP.ConfigTab4.DefaultMaxBids.SlotBox[2]:SetText(core.DB.MaxBidBySlot.Neck)
      CommDKP.ConfigTab4.DefaultMaxBids.SlotBox[2].tooltipText = L["NECK"]
      CommDKP.ConfigTab4.DefaultMaxBids.SlotBox[2].tooltipDescription = prefix.." "..L["FORNECKSLOT"].." "..L["MAXIMUMBIDTTDESC"]

      CommDKP.ConfigTab4.DefaultMaxBids.SlotBox[3].Header:SetText(L["SHOULDERS"]..": ")
      CommDKP.ConfigTab4.DefaultMaxBids.SlotBox[3]:SetText(core.DB.MaxBidBySlot.Shoulders)
      CommDKP.ConfigTab4.DefaultMaxBids.SlotBox[3].tooltipText = L["SHOULDERS"]
      CommDKP.ConfigTab4.DefaultMaxBids.SlotBox[3].tooltipDescription = prefix.." "..L["FORSHOULDERSLOT"].." "..L["MAXIMUMBIDTTDESC"]

      CommDKP.ConfigTab4.DefaultMaxBids.SlotBox[4].Header:SetText(L["CLOAK"]..": ")
      CommDKP.ConfigTab4.DefaultMaxBids.SlotBox[4]:SetText(core.DB.MaxBidBySlot.Cloak)
      CommDKP.ConfigTab4.DefaultMaxBids.SlotBox[4].tooltipText = L["CLOAK"]
      CommDKP.ConfigTab4.DefaultMaxBids.SlotBox[4].tooltipDescription = prefix.." "..L["FORBACKSLOT"].." "..L["MAXIMUMBIDTTDESC"]

      CommDKP.ConfigTab4.DefaultMaxBids.SlotBox[5].Header:SetText(L["CHEST"]..": ")
      CommDKP.ConfigTab4.DefaultMaxBids.SlotBox[5]:SetText(core.DB.MaxBidBySlot.Chest)
      CommDKP.ConfigTab4.DefaultMaxBids.SlotBox[5].tooltipText = L["CHEST"]
      CommDKP.ConfigTab4.DefaultMaxBids.SlotBox[5].tooltipDescription = prefix.." "..L["FORCHESTSLOT"].." "..L["MAXIMUMBIDTTDESC"]

      CommDKP.ConfigTab4.DefaultMaxBids.SlotBox[6].Header:SetText(L["BRACERS"]..": ")
      CommDKP.ConfigTab4.DefaultMaxBids.SlotBox[6]:SetText(core.DB.MaxBidBySlot.Bracers)
      CommDKP.ConfigTab4.DefaultMaxBids.SlotBox[6].tooltipText = L["BRACERS"]
      CommDKP.ConfigTab4.DefaultMaxBids.SlotBox[6].tooltipDescription = prefix.." "..L["FORWRISTSLOT"].." "..L["MAXIMUMBIDTTDESC"]

      CommDKP.ConfigTab4.DefaultMaxBids.SlotBox[7].Header:SetText(L["HANDS"]..": ")
      CommDKP.ConfigTab4.DefaultMaxBids.SlotBox[7]:SetText(core.DB.MaxBidBySlot.Hands)
      CommDKP.ConfigTab4.DefaultMaxBids.SlotBox[7].tooltipText = L["HANDS"]
      CommDKP.ConfigTab4.DefaultMaxBids.SlotBox[7].tooltipDescription = prefix.." "..L["FORHANDSLOT"].." "..L["MAXIMUMBIDTTDESC"]

      CommDKP.ConfigTab4.DefaultMaxBids.SlotBox[8].Header:SetText(L["BELT"]..": ")
      CommDKP.ConfigTab4.DefaultMaxBids.SlotBox[8]:SetText(core.DB.MaxBidBySlot.Belt)
      CommDKP.ConfigTab4.DefaultMaxBids.SlotBox[8].tooltipText = L["BELT"]
      CommDKP.ConfigTab4.DefaultMaxBids.SlotBox[8].tooltipDescription = prefix.." "..L["FORWAISTSLOT"].." "..L["MAXIMUMBIDTTDESC"]

      CommDKP.ConfigTab4.DefaultMaxBids.SlotBox[9].Header:SetText(L["LEGS"]..": ")
      CommDKP.ConfigTab4.DefaultMaxBids.SlotBox[9]:SetText(core.DB.MaxBidBySlot.Legs)
      CommDKP.ConfigTab4.DefaultMaxBids.SlotBox[9].tooltipText = L["LEGS"]
      CommDKP.ConfigTab4.DefaultMaxBids.SlotBox[9].tooltipDescription = prefix.." "..L["FORLEGSLOT"].." "..L["MAXIMUMBIDTTDESC"]

      CommDKP.ConfigTab4.DefaultMaxBids.SlotBox[10].Header:SetText(L["BOOTS"]..": ")
      CommDKP.ConfigTab4.DefaultMaxBids.SlotBox[10]:SetText(core.DB.MaxBidBySlot.Boots)
      CommDKP.ConfigTab4.DefaultMaxBids.SlotBox[10].tooltipText = L["BOOTS"]
      CommDKP.ConfigTab4.DefaultMaxBids.SlotBox[10].tooltipDescription = prefix.." "..L["FORFEETSLOT"].." "..L["MAXIMUMBIDTTDESC"]

      CommDKP.ConfigTab4.DefaultMaxBids.SlotBox[11].Header:SetText(L["RINGS"]..": ")
      CommDKP.ConfigTab4.DefaultMaxBids.SlotBox[11]:SetText(core.DB.MaxBidBySlot.Ring)
      CommDKP.ConfigTab4.DefaultMaxBids.SlotBox[11].tooltipText = L["RINGS"]
      CommDKP.ConfigTab4.DefaultMaxBids.SlotBox[11].tooltipDescription = prefix.." "..L["FORFINGERSLOT"].." "..L["MAXIMUMBIDTTDESC"]

      CommDKP.ConfigTab4.DefaultMaxBids.SlotBox[12].Header:SetText(L["TRINKET"]..": ")
      CommDKP.ConfigTab4.DefaultMaxBids.SlotBox[12]:SetText(core.DB.MaxBidBySlot.Trinket)
      CommDKP.ConfigTab4.DefaultMaxBids.SlotBox[12].tooltipText = L["TRINKET"]
      CommDKP.ConfigTab4.DefaultMaxBids.SlotBox[12].tooltipDescription = prefix.." "..L["FORTRINKETSLOT"].." "..L["MAXIMUMBIDTTDESC"]

      CommDKP.ConfigTab4.DefaultMaxBids.SlotBox[13].Header:SetText(L["ONEHANDED"]..": ")
      CommDKP.ConfigTab4.DefaultMaxBids.SlotBox[13]:SetText(core.DB.MaxBidBySlot.OneHanded)
      CommDKP.ConfigTab4.DefaultMaxBids.SlotBox[13].tooltipText = L["ONEHANDEDWEAPONS"]
      CommDKP.ConfigTab4.DefaultMaxBids.SlotBox[13].tooltipDescription = prefix.." "..L["FORONEHANDSLOT"].." "..L["MAXIMUMBIDTTDESC"]

      CommDKP.ConfigTab4.DefaultMaxBids.SlotBox[14].Header:SetText(L["TWOHANDED"]..": ")
      CommDKP.ConfigTab4.DefaultMaxBids.SlotBox[14]:SetText(core.DB.MaxBidBySlot.TwoHanded)
      CommDKP.ConfigTab4.DefaultMaxBids.SlotBox[14].tooltipText = L["TWOHANDEDWEAPONS"]
      CommDKP.ConfigTab4.DefaultMaxBids.SlotBox[14].tooltipDescription = prefix.." "..L["FORTWOHANDSLOT"].." "..L["MAXIMUMBIDTTDESC"]

      CommDKP.ConfigTab4.DefaultMaxBids.SlotBox[15].Header:SetText(L["OFFHAND"]..": ")
      CommDKP.ConfigTab4.DefaultMaxBids.SlotBox[15]:SetText(core.DB.MaxBidBySlot.OffHand)
      CommDKP.ConfigTab4.DefaultMaxBids.SlotBox[15].tooltipText = L["OFFHANDITEMS"]
      CommDKP.ConfigTab4.DefaultMaxBids.SlotBox[15].tooltipDescription = prefix.." "..L["FOROFFHANDSLOT"].." "..L["MAXIMUMBIDTTDESC"]

      CommDKP.ConfigTab4.DefaultMaxBids.SlotBox[16].Header:SetText(L["RANGE"]..": ")
      CommDKP.ConfigTab4.DefaultMaxBids.SlotBox[16]:SetText(core.DB.MaxBidBySlot.Range)
      CommDKP.ConfigTab4.DefaultMaxBids.SlotBox[16].tooltipText = L["RANGE"]
      CommDKP.ConfigTab4.DefaultMaxBids.SlotBox[16].tooltipDescription = prefix.." "..L["FORRANGESLOT"].." "..L["MAXIMUMBIDTTDESC"]

      CommDKP.ConfigTab4.DefaultMaxBids.SlotBox[17].Header:SetText(L["OTHER"]..": ")
      CommDKP.ConfigTab4.DefaultMaxBids.SlotBox[17]:SetText(core.DB.MaxBidBySlot.Other)
      CommDKP.ConfigTab4.DefaultMaxBids.SlotBox[17].tooltipText = L["OTHER"]
      CommDKP.ConfigTab4.DefaultMaxBids.SlotBox[17].tooltipDescription = prefix.." "..L["FOROTHERSLOT"].." "..L["MAXIMUMBIDTTDESC"]

      if core.DB.modes.costvalue == "Percent" then
        for i=1, #CommDKP.ConfigTab4.DefaultMaxBids.SlotBox do
          DrawPercFrame(i)
          CommDKP.ConfigTab4.DefaultMaxBids.SlotBox[i]:SetTextInsets(0, 15, 0, 0)
        end
      end
      -- Broadcast Maximum Bids Button
      CommDKP.ConfigTab4.BroadcastMaxBids = self:CreateButton("TOP", CommDKP.ConfigTab4, "BOTTOM", 30, 30, L["BCASTVALUES"]);
      CommDKP.ConfigTab4.BroadcastMaxBids:ClearAllPoints();
      CommDKP.ConfigTab4.BroadcastMaxBids:SetParent(maxBody)
      CommDKP.ConfigTab4.BroadcastMaxBids:SetPoint("BOTTOMRIGHT", maxBody, "BOTTOMRIGHT", -W.PAD, W.PAD)
      CommDKP.ConfigTab4.BroadcastMaxBids:SetSize(140, W.H)
      CommDKP.ConfigTab4.BroadcastMaxBids:SetScript("OnClick", function()
        if core.IsOfficer ~= true then return end          -- AD-20.2.5 (PM-13.3): click-time officer gate
        StaticPopupDialogs["SEND_MAXBIDS"] = {
          text = L["BCASTMAXBIDCONFIRM"],
          button1 = L["YES"],
          button2 = L["NO"],
          OnAccept = function()
            SaveSettings()
            CommDKP.Sync:SendData("CommDKPMaxBid", CommDKP:BuildBidBroadcastData("max"))   -- AD-36.1.1
            CommDKP:Print(L["MAXBIDVALUESSENT"])
          end,
          timeout = 0,
          whileDead = true,
          hideOnEscape = true,
          preferredIndex = 3,
        }
        StaticPopup_Show ("SEND_MAXBIDS")
      end);
      CommDKP.ConfigTab4.BroadcastMaxBids:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText(L["BCASTVALUES"], 0.25, 0.75, 0.90, 1, true)
        GameTooltip:AddLine(L["BCASTVALUESTTDESC"], 1.0, 1.0, 1.0, true);
        GameTooltip:AddLine(L["BCASTVALUESTTWARN"], 1.0, 0, 0, true);
        GameTooltip:Show()
      end)
      CommDKP.ConfigTab4.BroadcastMaxBids:SetScript("OnLeave", function()
        GameTooltip:Hide()
      end)
    end
    -- Bid Timer Slider
    CommDKP.ConfigTab4.bidTimerSlider = CreateFrame("SLIDER", "$parentBidTimerSlider", CommDKP.ConfigTab4, "CommDKPOptionsSliderTemplate");

    
    PlaceSlider(CommDKP.ConfigTab4.bidTimerSlider, GenBody())
    CommDKP.ConfigTab4.bidTimerSlider:SetPoint("TOPLEFT", GenBody(), "TOPLEFT", OPT_SLIDER_X, -28);
    CommDKP.ConfigTab4.bidTimerSlider:SetMinMaxValues(10, 90);
    CommDKP.ConfigTab4.bidTimerSlider:SetValue(core.DB.DKPBonus.BidTimer);
    CommDKP.ConfigTab4.bidTimerSlider:SetValueStep(1);
    CommDKP.ConfigTab4.bidTimerSlider.tooltipText = L["BIDTIMER"]
    CommDKP.ConfigTab4.bidTimerSlider.tooltipRequirement = L["BIDTIMERDEFAULTTTDESC"]
    CommDKP.ConfigTab4.bidTimerSlider:SetObeyStepOnDrag(true);
    getglobal(CommDKP.ConfigTab4.bidTimerSlider:GetName().."Low"):SetText("10")
    getglobal(CommDKP.ConfigTab4.bidTimerSlider:GetName().."High"):SetText("90")
    CommDKP.ConfigTab4.bidTimerSlider:SetScript("OnValueChanged", function(self)    -- clears focus on esc
      CommDKP.ConfigTab4.bidTimer:SetText(CommDKP.ConfigTab4.bidTimerSlider:GetValue())
    end)

  CommDKP.ConfigTab4.bidTimerHeader = W.CreateText(GenBody(), "label", nil, "CENTER")
    CommDKP.ConfigTab4.bidTimerHeader:SetPoint("BOTTOM", CommDKP.ConfigTab4.bidTimerSlider, "TOP", 0, 3);
    CommDKP.ConfigTab4.bidTimerHeader:SetText(L["BIDTIMER"])

  CommDKP.ConfigTab4.bidTimer = CreateFrame("EditBox", nil, GenBody(), "BackdropTemplate")
    
    CommDKP.ConfigTab4.bidTimer:SetAutoFocus(false)
    CommDKP.ConfigTab4.bidTimer:SetMultiLine(false)
  CommDKP.ConfigTab4.bidTimer:SetSize(54, W.H)
    CommDKP.ConfigTab4.bidTimer:SetMaxLetters(4)
    CommDKP.ConfigTab4.bidTimer:SetTextColor(1, 1, 1, 1)
    CommDKP.ConfigTab4.bidTimer:SetTextInsets(10, 10, 5, 5)
    CommDKP.ConfigTab4.bidTimer:SetScript("OnEscapePressed", function(self)    -- clears focus on esc
      self:ClearFocus()
    end)
    CommDKP.ConfigTab4.bidTimer:SetScript("OnEnterPressed", function(self)    -- clears focus on esc
      self:ClearFocus()
    end)
    CommDKP.ConfigTab4.bidTimer:SetScript("OnEditFocusLost", function(self)    -- clears focus on esc
      CommDKP.ConfigTab4.bidTimerSlider:SetValue(CommDKP.ConfigTab4.bidTimer:GetNumber());
    end)
    CommDKP.ConfigTab4.bidTimer:SetPoint("TOP", CommDKP.ConfigTab4.bidTimerSlider, "BOTTOM", 0, -3)     
    W.StyleEditBox(CommDKP.ConfigTab4.bidTimer, { numeric = true, align = "CENTER" })
    CommDKP.ConfigTab4.bidTimer:SetText(CommDKP.ConfigTab4.bidTimerSlider:GetValue())
  end -- the end

  -- Tooltip History Slider

  CommDKP.ConfigTab4.TooltipHistorySlider = CreateFrame("SLIDER", "$parentTooltipHistorySlider", CommDKP.ConfigTab4, "CommDKPOptionsSliderTemplate");
  if CommDKP.ConfigTab4.bidTimer then
    CommDKP.ConfigTab4.TooltipHistorySlider:SetPoint("LEFT", CommDKP.ConfigTab4.bidTimerSlider, "RIGHT", OPT_SLIDER_GAP, 0);
  else
    CommDKP.ConfigTab4.TooltipHistorySlider:SetPoint("TOPLEFT", GenBody(), "TOPLEFT", OPT_SLIDER_X, -28);
  end

  
  PlaceSlider(CommDKP.ConfigTab4.TooltipHistorySlider, GenBody())
  CommDKP.ConfigTab4.TooltipHistorySlider:SetMinMaxValues(5, 35);
  CommDKP.ConfigTab4.TooltipHistorySlider:SetValue(core.DB.defaults.TooltipHistoryCount);
  CommDKP.ConfigTab4.TooltipHistorySlider:SetValueStep(1);
  CommDKP.ConfigTab4.TooltipHistorySlider.tooltipText = L["TTHISTORYCOUNT"]
  CommDKP.ConfigTab4.TooltipHistorySlider.tooltipRequirement = L["TTHISTORYCOUNTTTDESC"]
  CommDKP.ConfigTab4.TooltipHistorySlider:SetObeyStepOnDrag(true);
  getglobal(CommDKP.ConfigTab4.TooltipHistorySlider:GetName().."Low"):SetText("5")
  getglobal(CommDKP.ConfigTab4.TooltipHistorySlider:GetName().."High"):SetText("35")
  CommDKP.ConfigTab4.TooltipHistorySlider:SetScript("OnValueChanged", function(self)    -- clears focus on esc
    CommDKP.ConfigTab4.TooltipHistory:SetText(CommDKP.ConfigTab4.TooltipHistorySlider:GetValue())
  end)

  CommDKP.ConfigTab4.TooltipHistoryHeader = W.CreateText(GenBody(), "label", nil, "CENTER")
  CommDKP.ConfigTab4.TooltipHistoryHeader:SetPoint("BOTTOM", CommDKP.ConfigTab4.TooltipHistorySlider, "TOP", 0, 3);
  CommDKP.ConfigTab4.TooltipHistoryHeader:SetText(L["TTHISTORYCOUNT"])

  CommDKP.ConfigTab4.TooltipHistory = CreateFrame("EditBox", nil, GenBody(), "BackdropTemplate")
  
  CommDKP.ConfigTab4.TooltipHistory:SetAutoFocus(false)
  CommDKP.ConfigTab4.TooltipHistory:SetMultiLine(false)
  CommDKP.ConfigTab4.TooltipHistory:SetSize(54, W.H)
  CommDKP.ConfigTab4.TooltipHistory:SetMaxLetters(4)
  CommDKP.ConfigTab4.TooltipHistory:SetTextColor(1, 1, 1, 1)
  CommDKP.ConfigTab4.TooltipHistory:SetTextInsets(10, 10, 5, 5)
  CommDKP.ConfigTab4.TooltipHistory:SetScript("OnEscapePressed", function(self)    -- clears focus on esc
    self:ClearFocus()
  end)
  CommDKP.ConfigTab4.TooltipHistory:SetScript("OnEnterPressed", function(self)    -- clears focus on esc
    self:ClearFocus()
  end)
  CommDKP.ConfigTab4.TooltipHistory:SetScript("OnEditFocusLost", function(self)    -- clears focus on esc
    CommDKP.ConfigTab4.TooltipHistorySlider:SetValue(CommDKP.ConfigTab4.TooltipHistory:GetNumber());
  end)
  CommDKP.ConfigTab4.TooltipHistory:SetPoint("TOP", CommDKP.ConfigTab4.TooltipHistorySlider, "BOTTOM", 0, -3)     
  W.StyleEditBox(CommDKP.ConfigTab4.TooltipHistory, { numeric = true, align = "CENTER" })
  CommDKP.ConfigTab4.TooltipHistory:SetText(CommDKP.ConfigTab4.TooltipHistorySlider:GetValue())


  -- Loot History Limit Slider
  CommDKP.ConfigTab4.historySlider = CreateFrame("SLIDER", "$parentHistorySlider", CommDKP.ConfigTab4, "CommDKPOptionsSliderTemplate");

  if CommDKP.ConfigTab4.bidTimer then
    CommDKP.ConfigTab4.historySlider:SetPoint("TOPLEFT", CommDKP.ConfigTab4.bidTimerSlider, "BOTTOMLEFT", 0, -50);
  else
    CommDKP.ConfigTab4.historySlider:SetPoint("TOPLEFT", CommDKP.ConfigTab4.TooltipHistorySlider, "BOTTOMLEFT", 0, -50);
  end

  

  
  PlaceSlider(CommDKP.ConfigTab4.historySlider, GenBody())
  CommDKP.ConfigTab4.historySlider:SetMinMaxValues(100, 2500);
  CommDKP.ConfigTab4.historySlider:SetValue(core.DB.defaults.HistoryLimit);
  CommDKP.ConfigTab4.historySlider:SetValueStep(25);
  CommDKP.ConfigTab4.historySlider.tooltipText = L["LOOTHISTORYLIMIT"]
  CommDKP.ConfigTab4.historySlider.tooltipRequirement = L["LOOTHISTLIMITTTDESC"]
  CommDKP.ConfigTab4.historySlider.tooltipWarning = L["LOOTHISTLIMITTTWARN"]
  CommDKP.ConfigTab4.historySlider:SetObeyStepOnDrag(true);
  getglobal(CommDKP.ConfigTab4.historySlider:GetName().."Low"):SetText("100")
  getglobal(CommDKP.ConfigTab4.historySlider:GetName().."High"):SetText("2500")
  CommDKP.ConfigTab4.historySlider:SetScript("OnValueChanged", function(self)    -- clears focus on esc
    CommDKP.ConfigTab4.history:SetText(CommDKP.ConfigTab4.historySlider:GetValue())
  end)

  CommDKP.ConfigTab4.HistoryHeader = W.CreateText(GenBody(), "label", nil, "CENTER")
  CommDKP.ConfigTab4.HistoryHeader:SetPoint("BOTTOM", CommDKP.ConfigTab4.historySlider, "TOP", 0, 3);
  CommDKP.ConfigTab4.HistoryHeader:SetText(L["LOOTHISTORYLIMIT"])

  CommDKP.ConfigTab4.history = CreateFrame("EditBox", nil, GenBody(), "BackdropTemplate")
 
  CommDKP.ConfigTab4.history:SetAutoFocus(false)
  CommDKP.ConfigTab4.history:SetMultiLine(false)
  CommDKP.ConfigTab4.history:SetSize(54, W.H)
  CommDKP.ConfigTab4.history:SetMaxLetters(4)
  CommDKP.ConfigTab4.history:SetTextColor(1, 1, 1, 1)
  CommDKP.ConfigTab4.history:SetTextInsets(10, 10, 5, 5)
  CommDKP.ConfigTab4.history:SetScript("OnEscapePressed", function(self)    -- clears focus on esc
    self:ClearFocus()
  end)
  CommDKP.ConfigTab4.history:SetScript("OnEnterPressed", function(self)    -- clears focus on esc
    self:ClearFocus()
  end)
  CommDKP.ConfigTab4.history:SetScript("OnEditFocusLost", function(self)    -- clears focus on esc
    CommDKP.ConfigTab4.historySlider:SetValue(CommDKP.ConfigTab4.history:GetNumber());
  end)
  CommDKP.ConfigTab4.history:SetPoint("TOP", CommDKP.ConfigTab4.historySlider, "BOTTOM", 0, -3)     
  W.StyleEditBox(CommDKP.ConfigTab4.history, { numeric = true, align = "CENTER" })
  CommDKP.ConfigTab4.history:SetText(CommDKP.ConfigTab4.historySlider:GetValue())

  -- DKP History Limit Slider
  CommDKP.ConfigTab4.DKPHistorySlider = CreateFrame("SLIDER", "$parentDKPHistorySlider", CommDKP.ConfigTab4, "CommDKPOptionsSliderTemplate");


  PlaceSlider(CommDKP.ConfigTab4.DKPHistorySlider, GenBody())
  CommDKP.ConfigTab4.DKPHistorySlider:SetPoint("LEFT", CommDKP.ConfigTab4.historySlider, "RIGHT", OPT_SLIDER_GAP, 0);
  CommDKP.ConfigTab4.DKPHistorySlider:SetMinMaxValues(100, 2500);
  CommDKP.ConfigTab4.DKPHistorySlider:SetValue(core.DB.defaults.DKPHistoryLimit);
  CommDKP.ConfigTab4.DKPHistorySlider:SetValueStep(25);
  CommDKP.ConfigTab4.DKPHistorySlider.tooltipText = L["DKPHISTORYLIMIT"]
  CommDKP.ConfigTab4.DKPHistorySlider.tooltipRequirement = L["DKPHISTLIMITTTDESC"]
  CommDKP.ConfigTab4.DKPHistorySlider.tooltipWarning = L["DKPHISTLIMITTTWARN"]
  CommDKP.ConfigTab4.DKPHistorySlider:SetObeyStepOnDrag(true);
  getglobal(CommDKP.ConfigTab4.DKPHistorySlider:GetName().."Low"):SetText("100")
  getglobal(CommDKP.ConfigTab4.DKPHistorySlider:GetName().."High"):SetText("2500")
  CommDKP.ConfigTab4.DKPHistorySlider:SetScript("OnValueChanged", function(self)    -- clears focus on esc
    CommDKP.ConfigTab4.DKPHistory:SetText(CommDKP.ConfigTab4.DKPHistorySlider:GetValue())
  end)

  CommDKP.ConfigTab4.DKPHistoryHeader = W.CreateText(GenBody(), "label", nil, "CENTER")
  CommDKP.ConfigTab4.DKPHistoryHeader:SetPoint("BOTTOM", CommDKP.ConfigTab4.DKPHistorySlider, "TOP", 0, 3);
  CommDKP.ConfigTab4.DKPHistoryHeader:SetText(L["DKPHISTORYLIMIT"])

  CommDKP.ConfigTab4.DKPHistory = CreateFrame("EditBox", nil, GenBody(), "BackdropTemplate")
  
  CommDKP.ConfigTab4.DKPHistory:SetAutoFocus(false)
  CommDKP.ConfigTab4.DKPHistory:SetMultiLine(false)
  CommDKP.ConfigTab4.DKPHistory:SetSize(54, W.H)
  CommDKP.ConfigTab4.DKPHistory:SetMaxLetters(4)
  CommDKP.ConfigTab4.DKPHistory:SetTextColor(1, 1, 1, 1)
  CommDKP.ConfigTab4.DKPHistory:SetTextInsets(10, 10, 5, 5)
  CommDKP.ConfigTab4.DKPHistory:SetScript("OnEscapePressed", function(self)    -- clears focus on esc
    self:ClearFocus()
  end)
  CommDKP.ConfigTab4.DKPHistory:SetScript("OnEnterPressed", function(self)    -- clears focus on esc
    self:ClearFocus()
  end)
  CommDKP.ConfigTab4.DKPHistory:SetScript("OnEditFocusLost", function(self)    -- clears focus on esc
    CommDKP.ConfigTab4.DKPHistorySlider:SetValue(CommDKP.ConfigTab4.history:GetNumber());
  end)
  CommDKP.ConfigTab4.DKPHistory:SetPoint("TOP", CommDKP.ConfigTab4.DKPHistorySlider, "BOTTOM", 0, -3)     
  W.StyleEditBox(CommDKP.ConfigTab4.DKPHistory, { numeric = true, align = "CENTER" })
  CommDKP.ConfigTab4.DKPHistory:SetText(CommDKP.ConfigTab4.DKPHistorySlider:GetValue())

  -- Bid Timer Size Slider
  CommDKP.ConfigTab4.TimerSizeSlider = CreateFrame("SLIDER", "$parentBidTimerSizeSlider", CommDKP.ConfigTab4, "CommDKPOptionsSliderTemplate");

 
  PlaceSlider(CommDKP.ConfigTab4.TimerSizeSlider, GenBody())
  CommDKP.ConfigTab4.TimerSizeSlider:SetPoint("TOPLEFT", CommDKP.ConfigTab4.historySlider, "BOTTOMLEFT", 0, -50);
  CommDKP.ConfigTab4.TimerSizeSlider:SetMinMaxValues(0.5, 2.0);
  CommDKP.ConfigTab4.TimerSizeSlider:SetValue(core.DB.defaults.BidTimerSize);
  CommDKP.ConfigTab4.TimerSizeSlider:SetValueStep(0.05);
  CommDKP.ConfigTab4.TimerSizeSlider.tooltipText = L["TIMERSIZE"]
  CommDKP.ConfigTab4.TimerSizeSlider.tooltipRequirement = L["TIMERSIZETTDESC"]
  CommDKP.ConfigTab4.TimerSizeSlider.tooltipWarning = L["TIMERSIZETTWARN"]
  CommDKP.ConfigTab4.TimerSizeSlider:SetObeyStepOnDrag(true);
  getglobal(CommDKP.ConfigTab4.TimerSizeSlider:GetName().."Low"):SetText("50%")
  getglobal(CommDKP.ConfigTab4.TimerSizeSlider:GetName().."High"):SetText("200%")
  CommDKP.ConfigTab4.TimerSizeSlider:SetScript("OnValueChanged", function(self)   
    CommDKP.ConfigTab4.TimerSize:SetText(CommDKP.ConfigTab4.TimerSizeSlider:GetValue())
    core.DB.defaults.BidTimerSize = CommDKP.ConfigTab4.TimerSizeSlider:GetValue();
    CommDKP.BidTimer:SetScale(core.DB.defaults.BidTimerSize);
  end)

  CommDKP.ConfigTab4.DKPHistoryHeader = W.CreateText(GenBody(), "label", nil, "CENTER")
  CommDKP.ConfigTab4.DKPHistoryHeader:SetPoint("BOTTOM", CommDKP.ConfigTab4.TimerSizeSlider, "TOP", 0, 3);
  CommDKP.ConfigTab4.DKPHistoryHeader:SetText(L["TIMERSIZE"])

  CommDKP.ConfigTab4.TimerSize = CreateFrame("EditBox", nil, GenBody(), "BackdropTemplate")

  
  CommDKP.ConfigTab4.TimerSize:SetAutoFocus(false)
  CommDKP.ConfigTab4.TimerSize:SetMultiLine(false)
  CommDKP.ConfigTab4.TimerSize:SetSize(54, W.H)
  CommDKP.ConfigTab4.TimerSize:SetMaxLetters(4)
  CommDKP.ConfigTab4.TimerSize:SetTextColor(1, 1, 1, 1)
  CommDKP.ConfigTab4.TimerSize:SetTextInsets(10, 10, 5, 5)
  CommDKP.ConfigTab4.TimerSize:SetScript("OnEscapePressed", function(self)    -- clears focus on esc
    self:ClearFocus()
  end)
  CommDKP.ConfigTab4.TimerSize:SetScript("OnEnterPressed", function(self)    -- clears focus on esc
    self:ClearFocus()
  end)
  CommDKP.ConfigTab4.TimerSize:SetScript("OnEditFocusLost", function(self)    -- clears focus on esc
    CommDKP.ConfigTab4.TimerSizeSlider:SetValue(CommDKP.ConfigTab4.TimerSize:GetNumber());
  end)
  CommDKP.ConfigTab4.TimerSize:SetPoint("TOP", CommDKP.ConfigTab4.TimerSizeSlider, "BOTTOM", 0, -3)     
  W.StyleEditBox(CommDKP.ConfigTab4.TimerSize, { numeric = true, align = "CENTER" })
  CommDKP.ConfigTab4.TimerSize:SetText(CommDKP.ConfigTab4.TimerSizeSlider:GetValue())

  -- UI Scale Size Slider
  CommDKP.ConfigTab4.CommDKPScaleSize = CreateFrame("SLIDER", "$parentCommDKPScaleSizeSlider", CommDKP.ConfigTab4, "CommDKPOptionsSliderTemplate");

  
  PlaceSlider(CommDKP.ConfigTab4.CommDKPScaleSize, GenBody())
  CommDKP.ConfigTab4.CommDKPScaleSize:SetPoint("TOPLEFT", CommDKP.ConfigTab4.DKPHistorySlider, "BOTTOMLEFT", 0, -50);
  CommDKP.ConfigTab4.CommDKPScaleSize:SetMinMaxValues(0.5, 2.0);
  CommDKP.ConfigTab4.CommDKPScaleSize:SetValue(core.DB.defaults.CommDKPScaleSize);
  CommDKP.ConfigTab4.CommDKPScaleSize:SetValueStep(0.05);
  CommDKP.ConfigTab4.CommDKPScaleSize.tooltipText = L["CommDKPSCALESIZE"]
  CommDKP.ConfigTab4.CommDKPScaleSize.tooltipRequirement = L["CommDKPSCALESIZETTDESC"]
  CommDKP.ConfigTab4.CommDKPScaleSize.tooltipWarning = L["CommDKPSCALESIZETTWARN"]
  CommDKP.ConfigTab4.CommDKPScaleSize:SetObeyStepOnDrag(true);
  getglobal(CommDKP.ConfigTab4.CommDKPScaleSize:GetName().."Low"):SetText("50%")
  getglobal(CommDKP.ConfigTab4.CommDKPScaleSize:GetName().."High"):SetText("200%")
  CommDKP.ConfigTab4.CommDKPScaleSize:SetScript("OnValueChanged", function(self)   
    CommDKP.ConfigTab4.UIScaleSize:SetText(CommDKP.ConfigTab4.CommDKPScaleSize:GetValue())
    core.DB.defaults.CommDKPScaleSize = CommDKP.ConfigTab4.CommDKPScaleSize:GetValue();
  end)

  CommDKP.ConfigTab4.DKPHistoryHeader = W.CreateText(GenBody(), "label", nil, "CENTER")
  CommDKP.ConfigTab4.DKPHistoryHeader:SetPoint("BOTTOM", CommDKP.ConfigTab4.CommDKPScaleSize, "TOP", 0, 3);
  CommDKP.ConfigTab4.DKPHistoryHeader:SetText(L["MAINGUISIZE"])

  CommDKP.ConfigTab4.UIScaleSize = CreateFrame("EditBox", nil, GenBody(), "BackdropTemplate")
  
  CommDKP.ConfigTab4.UIScaleSize:SetAutoFocus(false)
  CommDKP.ConfigTab4.UIScaleSize:SetMultiLine(false)
  CommDKP.ConfigTab4.UIScaleSize:SetSize(54, W.H)
  CommDKP.ConfigTab4.UIScaleSize:SetMaxLetters(4)
  CommDKP.ConfigTab4.UIScaleSize:SetTextColor(1, 1, 1, 1)
  CommDKP.ConfigTab4.UIScaleSize:SetTextInsets(10, 10, 5, 5)
  CommDKP.ConfigTab4.UIScaleSize:SetScript("OnEscapePressed", function(self)    -- clears focus on esc
    self:ClearFocus()
  end)
  CommDKP.ConfigTab4.UIScaleSize:SetScript("OnEnterPressed", function(self)    -- clears focus on esc
    self:ClearFocus()
  end)
  CommDKP.ConfigTab4.UIScaleSize:SetScript("OnEditFocusLost", function(self)    -- clears focus on esc
    CommDKP.ConfigTab4.CommDKPScaleSize:SetValue(CommDKP.ConfigTab4.UIScaleSize:GetNumber());
  end)
  CommDKP.ConfigTab4.UIScaleSize:SetPoint("TOP", CommDKP.ConfigTab4.CommDKPScaleSize, "BOTTOM", 0, -3)     
  W.StyleEditBox(CommDKP.ConfigTab4.UIScaleSize, { numeric = true, align = "CENTER" })
  CommDKP.ConfigTab4.UIScaleSize:SetText(CommDKP.ConfigTab4.CommDKPScaleSize:GetValue())

  -- Suppress Broadcast Notifications checkbox
  CommDKP.ConfigTab4.SuppressNotifications = W.CreateCheckbox(GenBody(), nil, "");
  CommDKP.ConfigTab4.SuppressNotifications:SetPoint("TOPLEFT", GenBody(), "TOPLEFT", W.PAD, -214)
  CommDKP.ConfigTab4.SuppressNotifications:SetChecked(core.DB.defaults.SuppressNotifications)
  CommDKP.ConfigTab4.SuppressNotifications.text:SetText(L["SUPPRESSNOTIFICATIONS"]);
  CommDKP.ConfigTab4.SuppressNotifications:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    GameTooltip:SetText(L["SUPPRESSNOTIFICATIONS"], 0.25, 0.75, 0.90, 1, true)
    GameTooltip:AddLine(L["SUPPRESSNOTIFYTTDESC"], 1.0, 1.0, 1.0, true);
    GameTooltip:AddLine(L["SUPPRESSNOTIFYTTWARN"], 1.0, 0, 0, true);
    GameTooltip:Show()
  end)
  CommDKP.ConfigTab4.SuppressNotifications:SetScript("OnLeave", function()
    GameTooltip:Hide()
  end)
  CommDKP.ConfigTab4.SuppressNotifications:SetScript("OnClick", function()
    if CommDKP.ConfigTab4.SuppressNotifications:GetChecked() then
      CommDKP:Print(L["NOTIFICATIONSLIKETHIS"].." |cffff0000"..L["HIDDEN"].."|r.")
      core.DB["defaults"]["SuppressNotifications"] = true;
    else
      core.DB["defaults"]["SuppressNotifications"] = false;
      CommDKP:Print(L["NOTIFICATIONSLIKETHIS"].." |cff00ff00"..L["VISIBLE"].."|r.")
    end
    PlaySound(808)
  end)

  -- Combat Logging checkbox
  CommDKP.ConfigTab4.CombatLogging = W.CreateCheckbox(GenBody(), nil, "");
  CommDKP.ConfigTab4.CombatLogging:SetPoint("TOPLEFT", CommDKP.ConfigTab4.SuppressNotifications, "BOTTOMLEFT", 0, -8)
  CommDKP.ConfigTab4.CombatLogging:SetChecked(core.DB.defaults.AutoLog)
  CommDKP.ConfigTab4.CombatLogging.text:SetText(L["AUTOCOMBATLOG"]);
  CommDKP.ConfigTab4.CombatLogging:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    GameTooltip:SetText(L["AUTOCOMBATLOG"], 0.25, 0.75, 0.90, 1, true)
    GameTooltip:AddLine(L["AUTOCOMBATLOGTTDESC"], 1.0, 1.0, 1.0, true);
    GameTooltip:AddLine(L["AUTOCOMBATLOGTTWARN"], 1.0, 0, 0, true);
    GameTooltip:Show()
  end)
  CommDKP.ConfigTab4.CombatLogging:SetScript("OnLeave", function()
    GameTooltip:Hide()
  end)
  CommDKP.ConfigTab4.CombatLogging:SetScript("OnClick", function(self)
    core.DB.defaults.AutoLog = self:GetChecked()
    PlaySound(808)
  end)

  if core.DB.defaults.AutoOpenBid == nil then
    core.DB.defaults.AutoOpenBid = true
  end

  CommDKP.ConfigTab4.AutoOpenCheckbox = W.CreateCheckbox(GenBody(), nil, "");
  CommDKP.ConfigTab4.AutoOpenCheckbox:SetChecked(core.DB.defaults.AutoOpenBid)
  CommDKP.ConfigTab4.AutoOpenCheckbox.text:SetText(L["AUTOOPEN"]);
  CommDKP.ConfigTab4.AutoOpenCheckbox:SetPoint("TOPLEFT", CommDKP.ConfigTab4.CombatLogging, "BOTTOMLEFT", 0, -8);
  CommDKP.ConfigTab4.AutoOpenCheckbox:SetScript("OnClick", function(self)
    core.DB.defaults.AutoOpenBid = self:GetChecked()
  end)
  CommDKP.ConfigTab4.AutoOpenCheckbox:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_LEFT");
    GameTooltip:SetText(L["AUTOOPEN"], 0.25, 0.75, 0.90, 1, true);
    GameTooltip:AddLine(L["AUTOOPENTTDESC"], 1.0, 1.0, 1.0, true);
    GameTooltip:Show();
  end)
  CommDKP.ConfigTab4.AutoOpenCheckbox:SetScript("OnLeave", function(self)
    GameTooltip:Hide()
  end)

  if core.IsOfficer == true then
    CommDKP.ConfigTab4.AutoAwardLootCheckbox = W.CreateCheckbox(GenBody(), nil, "");
    CommDKP.ConfigTab4.AutoAwardLootCheckbox:SetChecked(core.DB.defaults.AutoAwardLoot)
    CommDKP.ConfigTab4.AutoAwardLootCheckbox.text:SetText(L["AUTOAWARDLOOT"]);
    CommDKP.ConfigTab4.AutoAwardLootCheckbox:SetPoint("TOPLEFT", CommDKP.ConfigTab4.AutoOpenCheckbox, "BOTTOMLEFT", 0, -8);
    CommDKP.ConfigTab4.AutoAwardLootCheckbox:SetScript("OnClick", function(self)
      core.DB.defaults.AutoAwardLoot = self:GetChecked()

      if core.DB.defaults.AutoAwardLoot == false then
        core.DB.pendingLoot = {}
      end

    end)
    CommDKP.ConfigTab4.AutoAwardLootCheckbox:SetScript("OnEnter", function(self)
      GameTooltip:SetOwner(self, "ANCHOR_LEFT");
      GameTooltip:SetText(L["AUTOAWARDLOOT"], 0.25, 0.75, 0.90, 1, true);
      GameTooltip:AddLine(L["AUTOAWARDLOOTDESC"], 1.0, 1.0, 1.0, true);
      GameTooltip:Show();
    end)
    CommDKP.ConfigTab4.AutoAwardLootCheckbox:SetScript("OnLeave", function(self)
      GameTooltip:Hide()
    end)
    
    -- Suppress Broadcast Notifications checkbox
    CommDKP.ConfigTab4.SuppressTells = W.CreateCheckbox(GenBody(), nil, "");
    CommDKP.ConfigTab4.SuppressTells:SetPoint("TOPLEFT", CommDKP.ConfigTab4.SuppressNotifications, "TOPLEFT", OPT_COL2, 0)
    CommDKP.ConfigTab4.SuppressTells:SetChecked(core.DB.defaults.SuppressTells)
    CommDKP.ConfigTab4.SuppressTells.text:SetText(L["SUPPRESSBIDWHISP"]);
    CommDKP.ConfigTab4.SuppressTells:SetScript("OnEnter", function(self)
      GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
      GameTooltip:SetText(L["SUPPRESSBIDWHISP"], 0.25, 0.75, 0.90, 1, true)
      GameTooltip:AddLine(L["SuppressBIDWHISPTTDESC"], 1.0, 1.0, 1.0, true);
      GameTooltip:AddLine(L["SuppressBIDWHISPTTWARN"], 1.0, 0, 0, true);
      GameTooltip:Show()
    end)
    CommDKP.ConfigTab4.SuppressTells:SetScript("OnLeave", function()
      GameTooltip:Hide()
    end)
    CommDKP.ConfigTab4.SuppressTells:SetScript("OnClick", function()
      if CommDKP.ConfigTab4.SuppressTells:GetChecked() then
        CommDKP:Print(L["BIDWHISPARENOW"].." |cffff0000"..L["HIDDEN"].."|r.")
        core.DB["defaults"]["SuppressTells"] = true;
      else
        core.DB["defaults"]["SuppressTells"] = false;
        CommDKP:Print(L["BIDWHISPARENOW"].." |cff00ff00"..L["VISIBLE"].."|r.")
      end
      PlaySound(808)
    end)

    if core.DB.defaults.DecreaseDisenchantValue == nil then
      core.DB.defaults.DecreaseDisenchantValue = false
    end
  
    CommDKP.ConfigTab4.DecreaseDisenchantCheckbox = W.CreateCheckbox(GenBody(), nil, "");
    CommDKP.ConfigTab4.DecreaseDisenchantCheckbox:SetPoint("TOPLEFT", CommDKP.ConfigTab4.CombatLogging, "TOPLEFT", OPT_COL2, 0)
    CommDKP.ConfigTab4.DecreaseDisenchantCheckbox:SetChecked(core.DB.defaults.DecreaseDisenchantValue)
    CommDKP.ConfigTab4.DecreaseDisenchantCheckbox.text:SetText(L["DECREASEDISENCHANT"]);
    CommDKP.ConfigTab4.DecreaseDisenchantCheckbox:SetScript("OnClick", function(self)
      core.DB.defaults.DecreaseDisenchantValue = self:GetChecked()
    end)
    CommDKP.ConfigTab4.DecreaseDisenchantCheckbox:SetScript("OnEnter", function(self)
      GameTooltip:SetOwner(self, "ANCHOR_LEFT");
      GameTooltip:SetText(L["DECREASEDISENCHANT"], 0.25, 0.75, 0.90, 1, true);
      GameTooltip:AddLine(L["DECREASEDISENCHANTTTDESC"], 1.0, 1.0, 1.0, true);
      GameTooltip:Show();
    end)
    CommDKP.ConfigTab4.DecreaseDisenchantCheckbox:SetScript("OnLeave", function(self)
      GameTooltip:Hide()
    end)
  
  end

  -- Save Settings Button (Actions card is created at the top of the pane, AD-20.3.1)
  if CommDKP.ConfigTab4.ModesButton then ActionSlot(CommDKP.ConfigTab4.ModesButton, 1) end
  CommDKP.ConfigTab4.submitSettings = self:CreateButton("BOTTOMLEFT", CommDKP.ConfigTab4, "BOTTOMLEFT", 30, 30, L["SAVESETTINGS"]);
  CommDKP.ConfigTab4.submitSettings:ClearAllPoints();
  ActionSlot(CommDKP.ConfigTab4.submitSettings, 4, "primary")

  CommDKP.ConfigTab4.submitSettings:SetScript("OnClick", function()
    if core.IsOfficer == true then
      for i=1, 6 do
        if not tonumber(CommDKP.ConfigTab4.default[i]:GetText()) then
          StaticPopupDialogs["OPTIONS_VALIDATION"] = {
            text = L["INVALIDOPTIONENTRY"].." "..CommDKP.ConfigTab4.default[i].tooltipText..". "..L["PLEASEUSENUMS"],
            button1 = L["OK"],
            timeout = 0,
            whileDead = true,
            hideOnEscape = true,
            preferredIndex = 3,
          }
          StaticPopup_Show ("OPTIONS_VALIDATION")

        return;
        end
      end
      for i=1, 17 do
        if not tonumber(CommDKP.ConfigTab4.DefaultMinBids.SlotBox[i]:GetText()) then
          StaticPopupDialogs["OPTIONS_VALIDATION"] = {
            text = L["INVALIDMINBIDENTRY"].." "..CommDKP.ConfigTab4.DefaultMinBids.SlotBox[i].tooltipText..". "..L["PLEASEUSENUMS"],
            button1 = L["OK"],
            timeout = 0,
            whileDead = true,
            hideOnEscape = true,
            preferredIndex = 3,
          }
          StaticPopup_Show ("OPTIONS_VALIDATION")

        return;
        end
      end
    end
    
    SaveSettings()
    if core.IsOfficer == true and IsInGuild() then
      CommDKP.Sync:SendData("CommDKPDKPModes", { core.DB.modes, core.DB.DKPBonus, core.DB.raiders })
    end
    CommDKP:Print(L["DEFAULTSETSAVED"])
  end)

  -- Chatframe Selection 
  CommDKP.ConfigTab4.ChatFrame = DD:Create_UIDropDownMenu("CommDKPChatFrameSelectDropDown", GenBody());
  if not core.DB.defaults.ChatFrames then core.DB.defaults.ChatFrames = {} end

  DD:UIDropDownMenu_Initialize(CommDKP.ConfigTab4.ChatFrame, function(self, level, menuList)
    
  local SelectedFrame = DD:UIDropDownMenu_CreateInfo()
    SelectedFrame.func = self.SetValue

    SelectedFrame.keepShownOnClick = true;
    SelectedFrame.isNotRadio = true;

    for i = 1, NUM_CHAT_WINDOWS do
      local name = GetChatWindowInfo(i)
      if name ~= "" then
        SelectedFrame.text, SelectedFrame.arg1, SelectedFrame.checked = name, name, core.DB.defaults.ChatFrames[name]
        DD:UIDropDownMenu_AddButton(SelectedFrame)
      end
    end
  end)

  CommDKP.ConfigTab4.ChatFrame:SetPoint("TOPLEFT", CommDKP.ConfigTab4.AutoOpenCheckbox, "TOPLEFT", OPT_COL2, 3)
  DD:UIDropDownMenu_SetWidth(CommDKP.ConfigTab4.ChatFrame, 240)
  DD:UIDropDownMenu_SetText(CommDKP.ConfigTab4.ChatFrame, "Addon Notifications")

  function CommDKP.ConfigTab4.ChatFrame:SetValue(arg1)
    core.DB.defaults.ChatFrames[arg1] = not core.DB.defaults.ChatFrames[arg1]
    LibDD:CloseDropDownMenus()
  end



  -- Position Bid Timer Button
  CommDKP.ConfigTab4.moveTimer = self:CreateButton("BOTTOMRIGHT", CommDKP.ConfigTab4, "BOTTOMRIGHT", -50, 30, L["MOVEBIDTIMER"]);
  CommDKP.ConfigTab4.moveTimer:ClearAllPoints();
  ActionSlot(CommDKP.ConfigTab4.moveTimer, 2)

  CommDKP.ConfigTab4.moveTimer:SetScript("OnClick", function()
    if moveTimerToggle == 0 then
      CommDKP:StartTimer(120, L["MOVEME"])
      CommDKP.ConfigTab4.moveTimer:SetText(L["HIDEBIDTIMER"])
      moveTimerToggle = 1;
    else
      CommDKP.BidTimer:SetScript("OnUpdate", nil)
      CommDKP.BidTimer:Hide()
      CommDKP.ConfigTab4.moveTimer:SetText(L["MOVEBIDTIMER"])
      moveTimerToggle = 0;
    end
  end)

  -- wipe tables button
  CommDKP.ConfigTab4.WipeTables = self:CreateButton("BOTTOMRIGHT", CommDKP.ConfigTab4, "BOTTOMRIGHT", -50, 30, L["WIPETABLES"]);
  CommDKP.ConfigTab4.WipeTables:ClearAllPoints();
  ActionSlot(CommDKP.ConfigTab4.WipeTables, 3, "caution")

  CommDKP.ConfigTab4.WipeTables:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT");
    GameTooltip:SetText(L["WIPETABLES"], 0.25, 0.75, 0.90, 1, true);
    GameTooltip:AddLine(L["WIPETABLESTTDESC"], 1.0, 1.0, 1.0, true);
    GameTooltip:Show();
  end)
  CommDKP.ConfigTab4.WipeTables:SetScript("OnLeave", function(self)
    GameTooltip:Hide()
  end)
  CommDKP.ConfigTab4.WipeTables:SetScript("OnClick", function()

    StaticPopupDialogs["WIPE_TABLES"] = {
      text = L["WIPETABLESCONF"],
      button1 = L["YES"],
      button2 = L["NO"],
      OnAccept = function()
        CommDKP:SetTable(CommDKP_Whitelist, false, nil);
        CommDKP:SetTable(CommDKP_DKPTable, true, nil);
        CommDKP:SetTable(CommDKP_Loot, true, nil);
        CommDKP:SetTable(CommDKP_DKPHistory, true, nil);
        CommDKP:SetTable(CommDKP_Archive, true, nil);
        CommDKP:SetTable(CommDKP_Standby, true, nil);
        CommDKP:SetTable(CommDKP_MinBids, true, nil);
        CommDKP:SetTable(CommDKP_MaxBids, true, nil);

        CommDKP:SetTable(CommDKP_DKPTable, true, {});
        CommDKP:SetTable(CommDKP_Loot, true, {});
        CommDKP:SetTable(CommDKP_DKPHistory, true, {});
        CommDKP:SetTable(CommDKP_Archive, true, {});
        CommDKP:SetTable(CommDKP_Whitelist, false, {});
        CommDKP:SetTable(CommDKP_Standby, true, {});
        CommDKP:SetTable(CommDKP_MinBids, true, {});
        CommDKP:SetTable(CommDKP_MaxBids, true, {});
        -- AD-29.2 (CDKP-021, BR-21.3): show the empty state in all 4 views, flip the pip, and announce the wipe's seed.
        CommDKP:LootHistory_Reset()
        if CommDKP.ConfigTab5 and CommDKP.ConfigTab5.looter then
          CommDKP:LootHistory_Update(L["NOFILTER"])
        end
        if CommDKP.ConfigTab6 and CommDKP.ConfigTab6.history then
          CommDKP:DKPHistory_Update(true)
        end
        CommDKP:RefreshPriceTable(true)
        CommDKP:FilterDKPTable(core.currentSort, "reset")
        CommDKP:StatusVerify_Update()
        if IsInGuild() and core.Initialized then
          CommDKP:SendSeedData()
        end
      end,
      timeout = 0,
      whileDead = true,
      hideOnEscape = true,
      preferredIndex = 3,
    }
    StaticPopup_Show ("WIPE_TABLES")
  end)

  -- Options Footer (empty frame to push bottom of scrollframe down)
  CommDKP.ConfigTab4.OptionsFooterFrame = CreateFrame("Frame", nil, CommDKP.ConfigTab4);
  CommDKP.ConfigTab4.OptionsFooterFrame:SetPoint("TOPLEFT", CommDKP.ConfigTab4, "TOPLEFT", 0, -stackY)
  CommDKP.ConfigTab4.OptionsFooterFrame:SetSize(OPT_CARD_W, 1);
  CommDKP.ConfigTab4:SetHeight(math.max(482, stackY))      -- §12.3.5: ~1031 px of cards in a 482 px viewport
  
end
