local _, core = ...;
local _G = _G;
local CommDKP = core.CommDKP;
local L = core.L;

--
--  When clicking a box off, unchecks "All" as well and flags checkAll to false
--
local checkAll = true;                    -- changes to false when less than all of the boxes are checked
local curReason;                          -- stores user input in dropdown 

local function ScrollFrame_OnMouseWheel(self, delta)          -- scroll function for all but the DKPTable frame
	local newValue = self:GetVerticalScroll() - (delta * 20);   -- DKPTable frame uses FauxScrollFrame_OnVerticalScroll()
	
	if (newValue < 0) then
		newValue = 0;
	elseif (newValue > self:GetVerticalScrollRange()) then
		newValue = self:GetVerticalScrollRange();
	end
	
	self:SetVerticalScroll(newValue);
end

function CommDKPFilterChecks(self)         -- sets/unsets check boxes in conjunction with "All" button, then runs CommDKP:FilterDKPTable() above
	local verifyCheck = true; -- switches to false if the below loop finds anything unchecked
	if (self:GetChecked() == false and not CommDKP.ConfigTab1.checkBtn[11]) then
		core.CurView = "limited"
		core.CurSubView = "raid"
		CommDKP.ConfigTab1.checkBtn[9]:SetChecked(false);
		checkAll = false;
		verifyCheck = false
	end
	for i=1, 8 do             -- checks all boxes to see if all are checked, if so, checks "All" as well
		if CommDKP.ConfigTab1.checkBtn[i]:GetChecked() == false then
			verifyCheck = false;
		end
	end
	if (verifyCheck == true) then
		CommDKP.ConfigTab1.checkBtn[10]:SetChecked(true);
	else
		CommDKP.ConfigTab1.checkBtn[10]:SetChecked(false);
	end
	for k,v in pairs(core.classes) do
		if (CommDKP.ConfigTab1.checkBtn[k]:GetChecked() == true) then
			core.classFiltered[v] = true;
		else
			core.classFiltered[v] = false;
		end
	end
	PlaySound(808)
	CommDKP:FilterDKPTable(core.currentSort, "reset");
end

---------------------------------------
-- CDKP-006 F6-b (AD-8.3): tab logic owned by the addon. The Mainline tab-template helpers read
-- parentKey fields whose names have already changed once, so we never call them.
---------------------------------------
-- UX §9.2 (DKP Modes window only, opt-in via frame.useRetailTabs): Accountant-Classic style tabs built
-- from scratch on native 12.x atlases. The legacy CommDKPTabButtonTemplate path is untouched (§9.2.0).
local RETAIL_TAB_HTILE = true          -- §9.2.1: flip to false if the center strip shows seams in game
local RETAIL_FONT_NORMAL    = "GameFontNormalSmall"     -- inactive: gold
local RETAIL_FONT_HIGHLIGHT = "GameFontHighlightSmall"  -- hover / active: white

local function HasAtlas(name)
	return C_Texture and C_Texture.GetAtlasInfo and C_Texture.GetAtlasInfo(name) ~= nil
end

-- Mirrors Accountant_Classic/Core/Tabs.lua createRetailTabTextures + createTab (no XML template, so no
-- inherited <TexCoords>/<Size>/file= state can pollute the atlas textures).
local function CreateRetailTab(frame, i)
	local tab = CreateFrame("Button", frame:GetName().."Tab"..i, frame)   -- NO CommDKPTabButtonTemplate
	tab:SetID(i)
	tab:SetSize(10, 32)
	tab:EnableMouse(true)
	if tab.SetMotionScriptsWhileDisabled then tab:SetMotionScriptsWhileDisabled(true) end  -- tooltip on active tab

	local function tex(atlas)
		local t = tab:CreateTexture(nil, "BACKGROUND")    -- fresh region: no TexCoords / Size / file
		t:SetAtlas(atlas, true)
		return t
	end
	tab.Left        = tex("uiframe-tab-left");         tab.Left:SetPoint("TOPLEFT",  tab, "TOPLEFT",  -3, 0)
	tab.Right       = tex("uiframe-tab-right");        tab.Right:SetPoint("TOPRIGHT", tab, "TOPRIGHT",  7, 0)
	tab.Middle      = tex("_uiframe-tab-center")
	tab.LeftActive  = tex("uiframe-activetab-left");   tab.LeftActive:SetPoint("TOPLEFT",  tab, "TOPLEFT",  -1, 0)
	tab.RightActive = tex("uiframe-activetab-right");  tab.RightActive:SetPoint("TOPRIGHT", tab, "TOPRIGHT",  8, 0)
	tab.MiddleActive= tex("_uiframe-activetab-center")
	for _, pair in ipairs({ { tab.Middle, tab.Left, tab.Right }, { tab.MiddleActive, tab.LeftActive, tab.RightActive } }) do
		local m, l, r = pair[1], pair[2], pair[3]
		if RETAIL_TAB_HTILE then m:SetHorizTile(true) end
		m:SetPoint("LEFT", l, "RIGHT"); m:SetPoint("RIGHT", r, "LEFT")   -- 2-point span: width comes from the tab
	end

	local text = tab:CreateFontString(nil, "ARTWORK", RETAIL_FONT_NORMAL)
	text:SetPoint("CENTER", tab, "CENTER", 0, 2)
	if tab.SetFontString then tab:SetFontString(text) end   -- tab:SetText() / state fonts drive this FontString
	if tab.SetNormalFontObject then
		tab:SetNormalFontObject(GameFontNormalSmall or RETAIL_FONT_NORMAL)              -- inactive: gold
		tab:SetHighlightFontObject(GameFontHighlightSmall or RETAIL_FONT_HIGHLIGHT)     -- hover: white
		tab:SetDisabledFontObject(GameFontHighlightSmall or RETAIL_FONT_HIGHLIGHT)      -- active (Disable()d): white
	end
	tab.Text = text
	tab.isRetailArt = true
	return tab
end

-- Replicates the legacy TabResize(tab, 0, nil, minW, maxW) on our own parentKeys.
local function TabResize(tab)
	if tab.isRetailArt then                                -- UX §9.2.3
		local minW, maxW = 44, tab.maxTextWidth or 88
		local capW  = (tab.Left:GetWidth() or 0) + (tab.Right:GetWidth() or 0)
		local sides = math.max(capW, 44)                   -- floor at the real cap art: caps can never cross
		tab.Text:SetWidth(0)
		local w = tab.Text:GetStringWidth()
		if w > maxW then w = maxW end
		if w < minW then w = minW end
		tab.Text:SetWidth(w)                               -- truncation -> IsTruncated() tooltip still works
		tab:SetWidth(w + sides)                            -- NO Middle/MiddleActive:SetWidth: the 2-point anchors span it
		return
	end
	local minW, maxW = 36, tab.maxTextWidth or 57
	local sides = 2 * tab.Left:GetWidth()
	tab.Text:SetWidth(0)                                   -- measure natural width
	local w = tab.Text:GetStringWidth()
	if w > maxW then w = maxW end
	if w < minW then w = minW end
	tab.Text:SetWidth(w)                                   -- truncates (enables IsTruncated tooltip)
	tab.Middle:SetWidth(w); tab.MiddleActive:SetWidth(w)
	tab:SetWidth(w + sides)
end

local function TabSetSelected(tab, selected)
	tab.Left:SetShown(not selected); tab.Middle:SetShown(not selected); tab.Right:SetShown(not selected)
	tab.LeftActive:SetShown(selected); tab.MiddleActive:SetShown(selected); tab.RightActive:SetShown(selected)
	if selected then tab:Disable() else tab:Enable() end   -- legacy behaviour: the selected tab is disabled
	if tab.isRetailArt then                                -- belt and braces: don't rely on button-state font swap
		tab.Text:SetFontObject(selected and RETAIL_FONT_HIGHLIGHT or RETAIL_FONT_NORMAL)
	end
end

local function SelectTab(frame, id)
	frame.selectedTab = id                                 -- same field the Blizzard helpers used
	for i = 1, frame.numTabs do
		TabSetSelected(_G[frame:GetName().."Tab"..i], i == id)
	end
end

local function Tab_OnEvent(self)
	if self:IsVisible() then TabResize(self) end
end

local function Tab_OnEnter(self)
	if self.isRetailArt and self:IsEnabled() then self.Text:SetFontObject(RETAIL_FONT_HIGHLIGHT) end   -- hover: white
	if self.Text:IsTruncated() then
		GameTooltip:SetOwner(self, "ANCHOR_RIGHT");
		GameTooltip:SetText(self.Text:GetText());
	end
end

local function RetailTab_OnLeave(self)
	if self:IsEnabled() then self.Text:SetFontObject(RETAIL_FONT_NORMAL) end   -- back to gold (active tab stays white)
	GameTooltip_Hide()
end

local function Tab_OnClick(self)
	SelectTab(self:GetParent(), self:GetID());
	
	if self:GetID() > 4 then
		self:GetParent().ScrollFrame.ScrollBar:Show()
	elseif self:GetID() == 4 and core.IsOfficer == true then
		self:GetParent().ScrollFrame.ScrollBar:Show()
	else
		self:GetParent().ScrollFrame.ScrollBar:Hide()
	end

	if self:GetID() == 5 then
		CommDKP:LootHistory_Update(L["NOFILTER"]);
	elseif self:GetID() == 6 then
		CommDKP:DKPHistory_Update(true)
	end

	if self:GetID() == 7 then
		self:GetParent().ScrollFrame.ScrollBar:Hide()
	end

	local scrollChild = self:GetParent().ScrollFrame:GetScrollChild();
	if (scrollChild) then
		scrollChild:Hide();
	end
	
	PlaySound(808)
	self:GetParent().ScrollFrame:SetScrollChild(self.content);
	self.content:Show();
	self:GetParent().ScrollFrame:SetVerticalScroll(0)
end

function CommDKP:SetTabs(frame, numTabs, width, height, ...)
	frame.numTabs = numTabs;
	
	local contents = {};
	local frameName = frame:GetName();
	
	-- UX §9.2.2: opt-in retail tabs (DKP Modes window only); falls back to legacy when atlases are missing.
	local retail = frame.useRetailTabs and HasAtlas("uiframe-tab-left") and true or false

	for i = 1, numTabs do
		local tab
		if retail then
			tab = CreateRetailTab(frame, i)                              -- no SetFrameLevel(+4): AC parity
		else
			tab = CreateFrame("Button", frameName.."Tab"..i, frame, "CommDKPTabButtonTemplate");
			tab:SetID(i);
			tab:SetFrameLevel(tab:GetFrameLevel() + 4)                   -- was XML OnLoad
		end
		if GetLocale() == "enUS" and (i == 2 or i == 5 or i == 6) then   -- was the XML OnShow name check
			tab.maxTextWidth = frame.maxTabWidth or 88                     -- corrects width on tabs for English client
		end
		tab:SetScript("OnShow", TabResize)
		tab:RegisterEvent("DISPLAY_SIZE_CHANGED")
		tab:SetScript("OnEvent", Tab_OnEvent)
		tab:SetScript("OnEnter", Tab_OnEnter)
		tab:SetScript("OnLeave", retail and RetailTab_OnLeave or GameTooltip_Hide)
		tab:SetText(select(i, ...));
		if not retail then                                                -- legacy look kept verbatim (§9.2.0)
			tab.Text:SetFontObject("CommDKPSmallOutlineCenter")
			tab.Text:SetTextColor(0.7, 0.7, 0.86, 1)
		end
		TabResize(tab)                                                  -- OnShow doesn't fire under a hidden parent
		tab:SetScript("OnClick", Tab_OnClick);
		
		tab.content = CreateFrame("Frame", nil, frame.ScrollFrame);
		tab.content:SetSize(width, height);
		tab.content:Hide();
				
		table.insert(contents, tab.content);
		
		if retail then                                                    -- UX §9.2.4: Accountant_Classic Tabs.lua:95-100
			if (i == 1) then
				tab:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 15, -20);
			else
				tab:SetPoint("LEFT", _G[frameName.."Tab"..(i - 1)], "RIGHT", 5, 0);
			end
		elseif (i == 1) then
			tab:SetPoint("TOPLEFT", frame, "BOTTOMLEFT", -5, 1);
		else
			tab:SetPoint("TOPLEFT", _G[frameName.."Tab"..(i - 1)], "TOPRIGHT", -17, 0);
		end
	end

	Tab_OnClick(_G[frameName.."Tab1"]);
	
	return unpack(contents);
end

---------------------------------------
-- Populate Tabs 
---------------------------------------
function CommDKP:ConfigMenuTabs()
	---------------------------------------
	-- TabMenu
	---------------------------------------

	CommDKP.UIConfig.TabMenu = CreateFrame("Frame", "CommDKPCommDKP.ConfigTabMenu", CommDKP.UIConfig, "BackdropTemplate");
	
	CommDKP.UIConfig.TabMenu:SetPoint("TOPRIGHT", CommDKP.UIConfig, "TOPRIGHT", -25, -25); --Moves the entire tabframe (defaults -25, -25)
	CommDKP.UIConfig.TabMenu:SetSize(535, 510);  --default: 477,510
	CommDKP:ApplyBackdrop(CommDKP.UIConfig.TabMenu, "BorderOnly", "ContainerBg", "ContainerBorder")
	CommDKP.UIConfig.TabMenuBG = CommDKP.UIConfig.TabMenu:CreateTexture(nil, "OVERLAY", nil);
	CommDKP.UIConfig.TabMenuBG:SetColorTexture(0, 0, 0, 1)
	CommDKP.UIConfig.TabMenuBG:SetPoint("TOPLEFT", CommDKP.UIConfig.TabMenu, "TOPLEFT", 2, -2);
	CommDKP.UIConfig.TabMenuBG:SetSize(536, 511);
	CommDKP.UIConfig.TabMenuBG:SetTexture("Interface\\AddOns\\CommunityDKPForever\\Media\\Textures\\menu-bg");

	-- TabMenu ScrollFrame and ScrollBar
	CommDKP.UIConfig.TabMenu.ScrollFrame = CreateFrame("ScrollFrame", nil, CommDKP.UIConfig.TabMenu, "UIPanelScrollFrameTemplate");
	CommDKP.UIConfig.TabMenu.ScrollFrame:ClearAllPoints();
	CommDKP.UIConfig.TabMenu.ScrollFrame:SetPoint("TOPLEFT",  CommDKP.UIConfig.TabMenu, "TOPLEFT", 4, -8);
	CommDKP.UIConfig.TabMenu.ScrollFrame:SetPoint("BOTTOMRIGHT", CommDKP.UIConfig.TabMenu, "BOTTOMRIGHT", -3, 4);
	CommDKP.UIConfig.TabMenu.ScrollFrame:SetClipsChildren(false);
	CommDKP.UIConfig.TabMenu.ScrollFrame:SetScript("OnMouseWheel", ScrollFrame_OnMouseWheel);
	


	CommDKP.ConfigTab1, CommDKP.ConfigTab2, CommDKP.ConfigTab3, CommDKP.ConfigTab4, CommDKP.ConfigTab5, CommDKP.ConfigTab6, CommDKP.ConfigTab7 = CommDKP:SetTabs(CommDKP.UIConfig.TabMenu, 7, 533, 490, L["FILTERS"], L["ADJUSTDKP"], L["MANAGE"], L["OPTIONS"], L["LOOTHISTORY"], L["DKPHISTORY"], L["PRICETAB"]);

	---------------------------------------
	-- MENU TAB 1
	---------------------------------------
	CommDKP.ConfigTab1.text = CommDKP.ConfigTab1:CreateFontString(nil, "OVERLAY")   -- Filters header
	CommDKP.ConfigTab1.text:ClearAllPoints();
	CommDKP.ConfigTab1.text:SetFontObject("CommDKPLargeCenter")
	CommDKP.ConfigTab1.text:SetPoint("TOPLEFT", CommDKP.ConfigTab1, "TOPLEFT", 15, -10);
	CommDKP.ConfigTab1.text:SetText(L["FILTERS"]);
	CommDKP.ConfigTab1.text:SetScale(1.2)

	local checkBtn = {}
	CommDKP.ConfigTab1.checkBtn = checkBtn;

	-- Create CheckBoxes
	for i=1, 11 do
		CommDKP.ConfigTab1.checkBtn[i] = CreateFrame("CheckButton", nil, CommDKP.ConfigTab1, "UICheckButtonTemplate");
		if i <= 10 then CommDKP.ConfigTab1.checkBtn[i]:SetChecked(true) else CommDKP.ConfigTab1.checkBtn[i]:SetChecked(false) end;
		CommDKP.ConfigTab1.checkBtn[i]:SetID(i)
		if i <= 9 then
			CommDKP.ConfigTab1.checkBtn[i].text:SetText("|cff5151de"..API_CLASSES[core.classes[i]].."|r");
		end
		if i==10 then
			CommDKP.ConfigTab1.checkBtn[i]:SetScript("OnClick",
				function()
					for j=1, 10 do
						if (checkAll) then
							CommDKP.ConfigTab1.checkBtn[j]:SetChecked(false)
						else
							CommDKP.ConfigTab1.checkBtn[j]:SetChecked(true)
						end
					end
					checkAll = not checkAll;
					CommDKPFilterChecks(CommDKP.ConfigTab1.checkBtn[9]);
				end)

			for k,v in pairs(core.classes) do               -- sets core.classFiltered table with all values
				if (CommDKP.ConfigTab1.checkBtn[k]:GetChecked() == true) then
					core.classFiltered[v] = true;
				else
					core.classFiltered[v] = false;
				end
			end
		elseif i==11 then
			CommDKP.ConfigTab1.checkBtn[i]:SetScript("OnClick", function(self)
				CommDKP.ConfigTab1.checkBtn[12]:SetChecked(false);
				CommDKPFilterChecks(self)
			end)
		else
			CommDKP.ConfigTab1.checkBtn[i]:SetScript("OnClick", CommDKPFilterChecks)
		end
		CommDKP.ConfigTab1.checkBtn[i].text:SetFontObject("CommDKPSmall")
	end

	-- Class Check Buttons:
	CommDKP.ConfigTab1.checkBtn[1]:SetPoint("TOPLEFT", CommDKP.ConfigTab1, "TOPLEFT", 60, -70);
	CommDKP.ConfigTab1.checkBtn[2]:SetPoint("TOPLEFT", CommDKP.ConfigTab1.checkBtn[1], "TOPRIGHT", 50, 0);
	CommDKP.ConfigTab1.checkBtn[3]:SetPoint("TOPLEFT", CommDKP.ConfigTab1.checkBtn[2], "TOPRIGHT", 50, 0);
	CommDKP.ConfigTab1.checkBtn[4]:SetPoint("TOPLEFT", CommDKP.ConfigTab1.checkBtn[3], "TOPRIGHT", 50, 0);
	CommDKP.ConfigTab1.checkBtn[5]:SetPoint("TOPLEFT", CommDKP.ConfigTab1.checkBtn[4], "TOPRIGHT", 50, 0);
	CommDKP.ConfigTab1.checkBtn[6]:SetPoint("TOPLEFT", CommDKP.ConfigTab1.checkBtn[1], "BOTTOMLEFT", 0, -10);
	CommDKP.ConfigTab1.checkBtn[7]:SetPoint("TOPLEFT", CommDKP.ConfigTab1.checkBtn[2], "BOTTOMLEFT", 0, -10);
	CommDKP.ConfigTab1.checkBtn[8]:SetPoint("TOPLEFT", CommDKP.ConfigTab1.checkBtn[3], "BOTTOMLEFT", 0, -10);
	CommDKP.ConfigTab1.checkBtn[9]:SetPoint("TOPLEFT", CommDKP.ConfigTab1.checkBtn[4], "BOTTOMLEFT", 0, -10);

	CommDKP.ConfigTab1.checkBtn[10]:SetPoint("BOTTOMRIGHT", CommDKP.ConfigTab1.checkBtn[3], "TOPLEFT", 50, 0);
	CommDKP.ConfigTab1.checkBtn[10].text:SetText("|cff5151de"..L["ALLCLASSES"].."|r");
	CommDKP.ConfigTab1.checkBtn[11]:SetPoint("TOPLEFT", CommDKP.ConfigTab1.checkBtn[6], "BOTTOMLEFT", 50, 0);
	CommDKP.ConfigTab1.checkBtn[11].text:SetText("|cff5151de"..L["INPARTYRAID"].."|r");         -- executed in filterDKPTable (CommunityDKP.lua)

	CommDKP.ConfigTab1.checkBtn[12] = CreateFrame("CheckButton", nil, CommDKP.ConfigTab1, "UICheckButtonTemplate");
	CommDKP.ConfigTab1.checkBtn[12]:SetID(12)
	CommDKP.ConfigTab1.checkBtn[12].text:SetText("|cff5151de"..L["ONLINE"].."|r");
	CommDKP.ConfigTab1.checkBtn[12].text:SetFontObject("CommDKPSmall")
	CommDKP.ConfigTab1.checkBtn[12]:SetScript("OnClick", CommDKPFilterChecks)
	CommDKP.ConfigTab1.checkBtn[12]:SetPoint("TOPLEFT", CommDKP.ConfigTab1.checkBtn[11], "TOPRIGHT", 100, 0);

	CommDKP.ConfigTab1.checkBtn[13] = CreateFrame("CheckButton", nil, CommDKP.ConfigTab1, "UICheckButtonTemplate");
	CommDKP.ConfigTab1.checkBtn[13]:SetID(13)
	CommDKP.ConfigTab1.checkBtn[13].text:SetText("|cff5151de"..L["NOTINRAIDFILTER"].."|r");
	CommDKP.ConfigTab1.checkBtn[13].text:SetFontObject("CommDKPSmall")
	CommDKP.ConfigTab1.checkBtn[13]:SetScript("OnClick", function(self)
		CommDKP.ConfigTab1.checkBtn[13]:SetChecked(false);
		CommDKPFilterChecks(self)
	end)
	CommDKP.ConfigTab1.checkBtn[13]:SetPoint("TOPLEFT", CommDKP.ConfigTab1.checkBtn[12], "TOPRIGHT", 65, 0);

	core.ClassGraph = CommDKP:ClassGraph()  -- draws class graph on tab1

	---------------------------------------
	-- Adjust DKP TAB
	---------------------------------------
	CommDKP:AdjustDKPTab_Create()

	---------------------------------------
	-- Price  TAB
	---------------------------------------
	CommDKP:PriceTab_Create()

	---------------------------------------
	-- Manage DKP TAB
	---------------------------------------
	CommDKP.ConfigTab3.header = CommDKP.ConfigTab3:CreateFontString(nil, "OVERLAY")
	CommDKP.ConfigTab3.header:ClearAllPoints();
	CommDKP.ConfigTab3.header:SetFontObject("CommDKPLargeCenter");
	CommDKP.ConfigTab3.header:SetPoint("TOPLEFT", CommDKP.ConfigTab3, "TOPLEFT", 15, -10);
	CommDKP.ConfigTab3.header:SetText(L["MANAGEDKP"]);
	CommDKP.ConfigTab3.header:SetScale(1.2)

	-- Populate Manage Tab
	CommDKP:ManageEntries()

	---------------------------------------
	-- Loot History TAB
	---------------------------------------
	CommDKP.ConfigTab5.text = CommDKP.ConfigTab5:CreateFontString(nil, "OVERLAY")
	CommDKP.ConfigTab5.text:ClearAllPoints();
	CommDKP.ConfigTab5.text:SetFontObject("CommDKPLargeLeft");
	CommDKP.ConfigTab5.text:SetPoint("TOPLEFT", CommDKP.ConfigTab5, "TOPLEFT", 15, -10);
	CommDKP.ConfigTab5.text:SetText(L["LOOTHISTORY"]);
	CommDKP.ConfigTab5.text:SetScale(1.2)
	CommDKP.ConfigTab5.inst = CommDKP.ConfigTab5:CreateFontString(nil, "OVERLAY")
	CommDKP.ConfigTab5.inst:ClearAllPoints();
	CommDKP.ConfigTab5.inst:SetFontObject("CommDKPSmallRight");
	CommDKP.ConfigTab5.inst:SetTextColor(0.3, 0.3, 0.3, 0.7)
	CommDKP.ConfigTab5.inst:SetPoint("TOPRIGHT", CommDKP.ConfigTab5, "TOPRIGHT", -40, -43);
	CommDKP.ConfigTab5.inst:SetText(L["LOOTHISTINST1"]);
	-- Populate Loot History (LootHistory.lua)
	local looter = {}
	CommDKP.ConfigTab5.looter = looter
	local lootFrame = {}
	CommDKP.ConfigTab5.lootFrame = lootFrame
	for i=1, #CommDKP:GetTable(CommDKP_Loot, true) do
		CommDKP.ConfigTab5.lootFrame[i] = CreateFrame("Frame", "CommDKPLootHistoryFrame"..i, CommDKP.ConfigTab5);
	end
	if #CommDKP:GetTable(CommDKP_Loot, true) > 0 then
		CommDKP:LootHistory_Update(L["NOFILTER"])
		CommDKP:CreateSortBox();
	end
	---------------------------------------
	-- DKP History Tab
	---------------------------------------
	CommDKP.ConfigTab6.text = CommDKP.ConfigTab6:CreateFontString(nil, "OVERLAY")
	CommDKP.ConfigTab6.text:ClearAllPoints();
	CommDKP.ConfigTab6.text:SetFontObject("CommDKPLargeLeft");
	CommDKP.ConfigTab6.text:SetPoint("TOPLEFT", CommDKP.ConfigTab6, "TOPLEFT", 15, -10);
	CommDKP.ConfigTab6.text:SetText(L["DKPHISTORY"]);
	CommDKP.ConfigTab6.text:SetScale(1.2)

	CommDKP.ConfigTab6.inst = CommDKP.ConfigTab6:CreateFontString(nil, "OVERLAY")
	CommDKP.ConfigTab6.inst:ClearAllPoints();
	CommDKP.ConfigTab6.inst:SetFontObject("CommDKPSmallRight");
	CommDKP.ConfigTab6.inst:SetTextColor(0.3, 0.3, 0.3, 0.7)
	CommDKP.ConfigTab6.inst:SetPoint("TOPRIGHT", CommDKP.ConfigTab6, "TOPRIGHT", -40, -43);
	if #CommDKP:GetTable(CommDKP_DKPHistory, true) > 0 then
		CommDKP:DKPHistory_Update()
	end
	CommDKP:DKPHistoryFilterBox_Create()
end
