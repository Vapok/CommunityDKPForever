local _, core = ...;
local _G = _G;
local CommDKP = core.CommDKP;
local L = core.L;
local LibDD = LibStub:GetLibrary("LibUIDropDownMenu-4.0");
local DD = CommDKP.DD                     -- AD-16.3: selector protocol (the right-click menuFrame below stays on LibDD, Q4)
local W = CommDKP.Widgets
local menu = {}
local curDropDownMenuFilterCategory = L["NOFILTER"];
local curfilterValue = nil;
local sortDropdown, curSelected       -- CDKP-012f1: file-local (were accidental globals)
local zoneBossDropdown                 -- AD-22.2.3: global frame name "CommDKPLootZoneBossDropDown"
local curZoneFilter, curBossFilter     -- nil = No Filter; curBossFilter is only ever set together with curZoneFilter
local activeFilter                     -- the filter the current row set was built with (hoisted for SetZoneBoss, AD-22.2.3)

local menuFrame = LibDD:Create_UIDropDownMenu("CommDKPDeleteLootMenuFrame", UIParent)
CommDKP.Widgets.RegisterContextMenu(menuFrame) -- CDKP-019 (AD-27.2.3)

---------------------------------------
-- AD-22.2.2: Filter card geometry — caption re-fit (idempotent; overrides the 300-px creation width)
---------------------------------------
local FILTER_DD_W, FILTER_CAP_W = 160, 160      -- AD-22.2.2
local function LayoutFilterCaption(tab)
	local inst, body = tab and tab.inst, tab and tab.FilterCard and tab.FilterCard.Body
	if not (inst and body) then return end
	inst:ClearAllPoints()
	inst:SetPoint("RIGHT", body, "RIGHT", -W.PAD, 0)
	inst:SetWidth(FILTER_CAP_W)
	inst:SetJustifyH("RIGHT")
end

---------------------------------------
-- AD-22.2.3 (CDKP-015a): Zone / Boss filter dropdown — helpers, index, menu builder, setter
---------------------------------------
local PAGE = 20                                             -- "paged in 20s exactly like the existing dropdowns"
local function Blank(s) return type(s) ~= "string" or s:match("^%s*$") ~= nil end
local function SortAZ(list)                                 -- list of { label = string, ... }; case-insensitive, stable tiebreak
	table.sort(list, function(a, b)
		local la, lb = a.label:lower(), b.label:lower()
		if la ~= lb then return la < lb end
		return a.label < b.label
	end)
end
local function Initial(s) return s:match("^[%z\1-\127\194-\244][\128-\191]*") or "" end   -- UTF-8 safe first glyph
local function Separator(level) DD:UIDropDownMenu_AddButton({ text = "", disabled = true, notCheckable = true }, level) end
-- Emits `items` at `level`: all of them if <= 20; else range rows ("A-F") that open pageMenu(p); or one page if `page` is set.
local function AddPaged(level, items, page, emit, pageMenu, pageChecked)
	if page then
		for i = (page - 1) * PAGE + 1, math.min(page * PAGE, #items) do emit(items[i]) end
	elseif #items <= PAGE then
		for i = 1, #items do emit(items[i]) end
	else
		for p = 1, math.ceil(#items / PAGE) do
			local first, last = items[(p - 1) * PAGE + 1], items[math.min(p * PAGE, #items)]
			DD:UIDropDownMenu_AddButton({ text = Initial(first.label) .. "-" .. Initial(last.label), hasArrow = true,
				isNotRadio = true, menuList = pageMenu(p), checked = pageChecked and pageChecked(p) or false }, level)
		end
	end
end

-- Index (rebuilt on every open, C-22.3): every non-blank .zone in CommDKP_Loot; each zone's distinct non-blank .boss.
local function BuildZoneBossIndex()
	local zones, byZone = {}, {}
	for _, e in ipairs(CommDKP:GetTable(CommDKP_Loot, true)) do
		if not Blank(e.zone) then
			local z = byZone[e.zone]
			if not z then z = { label = e.zone, bosses = {}, seen = {} }; byZone[e.zone] = z; zones[#zones + 1] = z end
			if not Blank(e.boss) and not z.seen[e.boss] then z.seen[e.boss] = true; z.bosses[#z.bosses + 1] = { label = e.boss } end
		end
	end
	SortAZ(zones); for _, z in ipairs(zones) do SortAZ(z.bosses) end
	return zones, byZone
end

local SetZoneBoss                                           -- forward declaration (defined below ZoneBossInit)

-- true when `value` sits in page `p` of `items` (by label)
local function PageHas(items, p, value)
	if value == nil then return false end
	for i = (p - 1) * PAGE + 1, math.min(p * PAGE, #items) do
		if items[i].label == value then return true end
	end
	return false
end

-- menuList is a table tag: dispatch by `kind`, not by level number (AD-22.2.3).
local function ZoneBossInit(self, level, menuList)
	level = level or 1
	local zones, byZone = BuildZoneBossIndex()

	local function EmitZone(z)
		DD:UIDropDownMenu_AddButton({ text = z.label, hasArrow = true, isNotRadio = true,
			checked = curZoneFilter == z.label, menuList = { kind = "zone", zone = z.label } }, level)
	end

	if level == 1 then
		DD:UIDropDownMenu_AddButton({ text = L["NOFILTER"], isNotRadio = true, checked = curZoneFilter == nil,
			func = function() SetZoneBoss(nil, nil) end }, level)
		Separator(level)
		AddPaged(level, zones, nil, EmitZone,
			function(p) return { kind = "zones", page = p } end,
			function(p) return PageHas(zones, p, curZoneFilter) end)
		return
	end

	local kind = type(menuList) == "table" and menuList.kind
	if kind == "zones" then
		AddPaged(level, zones, menuList.page, EmitZone)
	elseif kind == "zone" then
		local zone = menuList.zone
		local z = byZone[zone]
		if not z then return end
		local function EmitBoss(b)
			DD:UIDropDownMenu_AddButton({ text = b.label, isNotRadio = true,
				checked = curZoneFilter == zone and curBossFilter == b.label,
				func = function() SetZoneBoss(zone, b.label) end }, level)
		end
		if not menuList.page then
			DD:UIDropDownMenu_AddButton({ text = string.format(L["ALLZONE_FMT"] or "All %s", zone), isNotRadio = true,
				checked = curZoneFilter == zone and curBossFilter == nil,
				func = function() SetZoneBoss(zone, nil) end }, level)
		end
		AddPaged(level, z.bosses, menuList.page, EmitBoss,
			function(p) return { kind = "zone", zone = zone, page = p } end,
			function(p) return curZoneFilter == zone and PageHas(z.bosses, p, curBossFilter) end)
	end
end

local function ZoneBossLabel() return curBossFilter or curZoneFilter or L["NOFILTER"] end
SetZoneBoss = function(zone, boss)                          -- the only writer of curZoneFilter / curBossFilter
	curZoneFilter = (not Blank(zone)) and zone or nil
	curBossFilter = (curZoneFilter and not Blank(boss)) and boss or nil
	if zoneBossDropdown then DD:UIDropDownMenu_SetText(zoneBossDropdown, ZoneBossLabel()) end
	DD:CloseDropDownMenus()
	CommDKP:LootHistory_Update(activeFilter or L["NOFILTER"])   -- non-nil arg -> LootHistory_Reset -> scroll 0 (BR-15.3.6)
end



function CommDKP:SortLootTable()             -- sorts the Loot History Table by date
  table.sort(CommDKP:GetTable(CommDKP_Loot, true), function(a, b)
    return a["date"] > b["date"]
  end)
end

local function SortPlayerTable(arg)             -- sorts player list alphabetically
  table.sort(arg, function(a, b)
    return a < b
  end)
end

-- |cffa335ee|Hitem:19138::::::::60:::::::|h[Band of Sulfuras]|h|r
local function SortItemTable(arg)
	table.sort(arg, function(a,b)
		-- sort table by itemName of each itemLink
		return strsub(tostring(a), strfind(tostring(a), "%[") + 1, strfind(tostring(a), "%]") - 1) < strsub(tostring(b), strfind(tostring(b), "%[") + 1, strfind(tostring(b), "%]") - 1) 
	end)
end

local function GetSortOptions()
	local PlayerList = {}
	for i=1, #CommDKP:GetTable(CommDKP_Loot, true) do
		local playerSearch = CommDKP:Table_Search(PlayerList, CommDKP:GetTable(CommDKP_Loot, true)[i].player)
		if not playerSearch and not CommDKP:GetTable(CommDKP_Loot, true)[i].de then
			tinsert(PlayerList, CommDKP:GetTable(CommDKP_Loot, true)[i].player)
		end
	end
	SortPlayerTable(PlayerList)
	return PlayerList;
end

local function GetItemHistoryList() 
	local _ItemList = {}
	-- we look at saved variable and find every unique item looted?
	for i=1, #CommDKP:GetTable(CommDKP_Loot, true) do
		
		--Validate that the value is ACTUALLY an item link.
		local itemString = string.match(CommDKP:GetTable(CommDKP_Loot, true)[i].loot, "item[%-?%d:]+")

		if itemString then

			local itemSearch = CommDKP:Table_Search(_ItemList, CommDKP:GetTable(CommDKP_Loot, true)[i].loot)

			if not itemSearch then
				tinsert(_ItemList, CommDKP:GetTable(CommDKP_Loot, true)[i].loot)
			end
		end
	end
	SortItemTable(_ItemList)
	return _ItemList;
end

local function DeleteLootHistoryEntry(index)
	local search = CommDKP:Table_Search(CommDKP:GetTable(CommDKP_Loot, true), index, "index");
	local search_player = CommDKP:Table_Search(CommDKP:GetTable(CommDKP_DKPTable, true), CommDKP:GetTable(CommDKP_Loot, true)[search[1][1]].player);
	local curTime = time()
	local curOfficer = CommDKP:GetPlayerName()
	if not curOfficer then return end  -- AD-10.4
	local newIndex = curOfficer.."-"..curTime

	
	CommDKP:StatusVerify_Update()
	CommDKP:LootHistory_Reset()

	local tempTable = {
		player = CommDKP:GetTable(CommDKP_Loot, true)[search[1][1]].player,
		loot =  CommDKP:GetTable(CommDKP_Loot, true)[search[1][1]].loot,
		zone = CommDKP:GetTable(CommDKP_Loot, true)[search[1][1]].zone,
		date = time(),
		boss = CommDKP:GetTable(CommDKP_Loot, true)[search[1][1]].boss,
		cost = -CommDKP:GetTable(CommDKP_Loot, true)[search[1][1]].cost,
		index = newIndex,
		deletes = CommDKP:GetTable(CommDKP_Loot, true)[search[1][1]].index
	}

	if search_player then
		CommDKP:GetTable(CommDKP_DKPTable, true)[search_player[1][1]].dkp = CommDKP:GetTable(CommDKP_DKPTable, true)[search_player[1][1]].dkp + tempTable.cost 							-- refund previous looter
		CommDKP:GetTable(CommDKP_DKPTable, true)[search_player[1][1]].lifetime_spent = CommDKP:GetTable(CommDKP_DKPTable, true)[search_player[1][1]].lifetime_spent + tempTable.cost 		-- remove from lifetime_spent
	end

	CommDKP:GetTable(CommDKP_Loot, true)[search[1][1]].deletedby = newIndex

	table.insert(CommDKP:GetTable(CommDKP_Loot, true), 1, tempTable)
	CommDKP.Sync:SendData("CommDKPDelLoot", tempTable)
	CommDKP:SortLootTable()
	CommDKP:DKPTable_Update()
	CommDKP:LootHistory_Update(L["NOFILTER"]);
end

local function CommDKPDeleteMenu(index)
	local search = CommDKP:Table_Search(CommDKP:GetTable(CommDKP_Loot, true), index, "index")
	local search2 = CommDKP:Table_Search(CommDKP:GetTable(CommDKP_DKPTable, true), CommDKP:GetTable(CommDKP_Loot, true)[search[1][1]]["player"])
	local c, deleteString;
	if search2 then
		c = CommDKP:GetCColors(CommDKP:GetTable(CommDKP_DKPTable, true)[search2[1][1]].class)
		deleteString = L["CONFIRMDELETEENTRY1"]..": |c"..c.hex..CommDKP:GetTable(CommDKP_Loot, true)[search[1][1]]["player"].."|r "..L["WON"].." "..CommDKP:GetTable(CommDKP_Loot, true)[search[1][1]]["loot"].." "..L["FOR"].." "..-CommDKP:GetTable(CommDKP_Loot, true)[search[1][1]]["cost"].." "..L["DKP"].."?\n\n("..L["THISWILLREFUND"].." |c"..c.hex..CommDKP:GetTable(CommDKP_Loot, true)[search[1][1]].player.."|r "..-CommDKP:GetTable(CommDKP_Loot, true)[search[1][1]]["cost"].." "..L["DKP"]..")";
	else
		deleteString = L["CONFIRMDELETEENTRY1"]..": |cff444444"..CommDKP:GetTable(CommDKP_Loot, true)[search[1][1]]["player"].."|r "..L["WON"].." "..CommDKP:GetTable(CommDKP_Loot, true)[search[1][1]]["loot"].." "..L["FOR"].." "..-CommDKP:GetTable(CommDKP_Loot, true)[search[1][1]]["cost"].." "..L["DKP"].."?\n\n("..L["THISWILLREFUND"].." |cff444444"..CommDKP:GetTable(CommDKP_Loot, true)[search[1][1]].player.."|r "..-DKP_Loot[search[1][1]]["cost"].." "..L["DKP"]..")";
	end

	StaticPopupDialogs["DELETE_LOOT_ENTRY"] = {
	  text = deleteString,
	  button1 = L["YES"],
	  button2 = L["NO"],
	  OnAccept = function()
	    DeleteLootHistoryEntry(index)
	  end,
	  timeout = 0,
	  whileDead = true,
	  hideOnEscape = true,
	  preferredIndex = 3,
	}
	StaticPopup_Show ("DELETE_LOOT_ENTRY")
end

local function RightClickLootMenu(self, index)  -- called by right click function on ~201 row:SetScript
	local search = CommDKP:Table_Search(CommDKP:GetTable(CommDKP_Loot, true), index, "index")
	menu = {
		{ text = CommDKP:GetTable(CommDKP_Loot, true)[search[1][1]]["loot"].." "..L["FOR"].." "..CommDKP:GetTable(CommDKP_Loot, true)[search[1][1]]["cost"].." "..L["DKP"], isTitle = true},
		{ text = "Delete Entry", func = function()
			CommDKPDeleteMenu(index)
		end },
		{ text = L["REASSIGNSELECTED"], func = function()
			local path = CommDKP:GetTable(CommDKP_Loot, true)[search[1][1]]

			if #core.SelectedData == 1 then
				CommDKP:AwardConfirm(core.SelectedData[1].player, -path.cost, path.boss, path.zone, path.loot, index)
			elseif #core.SelectedData > 1 then
				StaticPopupDialogs["TOO_MANY_SELECTED_LOOT"] = {
				text = L["TOOMANYPLAYERSSELECT"],
				button1 = L["OK"],
				timeout = 0,
				whileDead = true,
				hideOnEscape = true,
				preferredIndex = 3,
			}
			StaticPopup_Show ("TOO_MANY_SELECTED_LOOT")
			else
				CommDKP:AwardConfirm(path.player, -path.cost, path.boss, path.zone, path.loot, index)
			end
		end }
	}
	LibDD:EasyMenu(menu, menuFrame, "cursor", 0 , 0, "MENU");
end

-- CDKP-012f1: the legacy feed frames (ConfigMenuTabs still pre-creates empty `lootFrame`s) stay hidden; the cellular
-- table's recycled rows are blanked and repainted by the next LootHistory_Update.
function CommDKP:ClearLootHistoryFrames()
	local tab = CommDKP.ConfigTab5
	if not tab then return end
	for _, fs in ipairs(tab.looter or {}) do fs:SetText("") end
	for _, f in ipairs(tab.lootFrame or {}) do f:Hide() end
	for _, row in ipairs(tab.LogRows or {}) do row.entry = nil; row:Hide() end
end


function CommDKP:CreateSortBox()
	local PlayerList = GetSortOptions();
	local ItemList = GetItemHistoryList();
	curSelected = 0;

	-- Create the dropdown, and configure its appearance
	if not sortDropdown then
		sortDropdown = DD:Create_UIDropDownMenu("CommDKPConfigFilterNameDropDown", CommDKP.ConfigTab5.FilterCard.Body);
	end

	-- Create and bind the initialization function to the dropdown menu
		DD:UIDropDownMenu_Initialize(sortDropdown, function(self, level, menuList)
		
		local dropDownMenuItem = DD:UIDropDownMenu_CreateInfo()
		local displayLimit = 20 -- control how many items will be created in Levels 2 and 3

		if (level or 1) == 1 then
			
			-- made it a bit more clear to read for now
			-- add no filter button
			dropDownMenuItem.func = self.FilterSetValue
			dropDownMenuItem.text = L["NOFILTER"]
			dropDownMenuItem.value = L["NOFILTER"]
			dropDownMenuItem.arg1 = L["NOFILTER"]
			dropDownMenuItem.arg2 = L["NOFILTER"]
			dropDownMenuItem.checked = (L["NOFILTER"] == curDropDownMenuFilterCategory)
			dropDownMenuItem.isNotRadio = true
			DD:UIDropDownMenu_AddButton(dropDownMenuItem, level)

			-- add deleted entries button
			dropDownMenuItem.text = L["DELETEDENTRY"] 
			dropDownMenuItem.value = L["DELETEDENTRY"] 
			dropDownMenuItem.arg1 = L["DELETEDENTRY"] 
			dropDownMenuItem.arg2 = L["DELETEDENTRY"]
			dropDownMenuItem.checked = L["DELETEDENTRY"] == curDropDownMenuFilterCategory
			dropDownMenuItem.hasArrow = false -- should probably check if players table holds any values
			dropDownMenuItem.isNotRadio = true
			DD:UIDropDownMenu_AddButton(dropDownMenuItem, level)

			-- add separator
			--wipe(dropDownMenuItem)
			dropDownMenuItem.text = ""
			dropDownMenuItem.disabled = 1
			dropDownMenuItem.isNotRadio = true
			DD:UIDropDownMenu_AddButton(dropDownMenuItem, level)
			dropDownMenuItem.disabled = nil
		
			-- add players section
			dropDownMenuItem.text =  L["PLAYERS"] 
			dropDownMenuItem.value =  L["PLAYERS"] 
			dropDownMenuItem.arg1 = L["PLAYERS"] 
			dropDownMenuItem.arg2 = L["PLAYERS"]
			dropDownMenuItem.value = L["PLAYERS"] -- for submenu handling in level 2
			dropDownMenuItem.checked = L["PLAYERS"] == curDropDownMenuFilterCategory
			dropDownMenuItem.isNotRadio = true
			dropDownMenuItem.hasArrow = true -- should probably check if items table holds any values
			DD:UIDropDownMenu_AddButton(dropDownMenuItem, level)

			-- add items section
			dropDownMenuItem.text =  L["ITEMS"] 
			dropDownMenuItem.value =  L["ITEMS"] 
			dropDownMenuItem.arg1 = L["ITEMS"] 
			dropDownMenuItem.arg2 = L["ITEMS"]
			dropDownMenuItem.value = L["ITEMS"] -- for submenu handling in level 2
			dropDownMenuItem.checked = L["ITEMS"] == curDropDownMenuFilterCategory
			dropDownMenuItem.isNotRadio = true
			DD:UIDropDownMenu_AddButton(dropDownMenuItem, level)

		-- level 2 to handle players and items
		elseif (level or 2) == 2 then

			if L_UIDROPDOWNMENU_MENU_VALUE == L["PLAYERS"] then

				for i=1, ceil(#PlayerList/displayLimit) do 
					local max = i*displayLimit;
					if max > #PlayerList then max = #PlayerList end
					dropDownMenuItem.text = strsub(PlayerList[((i*displayLimit)-(displayLimit-1))], 1, 1).."-"..strsub(PlayerList[max], 1, 1) 
					dropDownMenuItem.checked = curSelected >= (i*displayLimit)-(displayLimit-1) and curSelected <= i*displayLimit
					dropDownMenuItem.menuList = i -- to know which subLevel of players we are on
					dropDownMenuItem.value = L["PLAYERS"] -- for submenu handling in level 3
					dropDownMenuItem.hasArrow = true
					dropDownMenuItem.isNotRadio = true
					dropDownMenuItem.checked = (curDropDownMenuFilterCategory == L["PLAYERS"] and (curSelected >= (1+(i-1)*displayLimit) and curSelected <= 1+(i-1)*displayLimit+(displayLimit-1)))
					DD:UIDropDownMenu_AddButton(dropDownMenuItem, level)
				end

			elseif L_UIDROPDOWNMENU_MENU_VALUE == L["ITEMS"] then

				for i=1, ceil(#ItemList/displayLimit) do 
					local max = i*displayLimit;
					if max > #ItemList then max = #ItemList end
					dropDownMenuItem.text = ItemList[((i*displayLimit)-(displayLimit-1))]
					dropDownMenuItem.text = strsub(ItemList[((i*displayLimit)-(displayLimit-1))], strfind(ItemList[((i*displayLimit)-(displayLimit-1))], "%[", 1) + 1, strfind(ItemList[((i*displayLimit)-(displayLimit-1))], "%[", 1) + 1).."-"..strsub(ItemList[max], strfind(ItemList[max], "%[", 1) + 1, strfind(ItemList[max], "%[", 1) + 1)
					dropDownMenuItem.menuList = i -- to know which subLevel of items we are on
					dropDownMenuItem.value = L["ITEMS"] -- for submenu handling in level 3
					dropDownMenuItem.hasArrow = true
					dropDownMenuItem.isNotRadio = true
					dropDownMenuItem.checked = (curDropDownMenuFilterCategory == L["ITEMS"] and (curSelected >= (1+(i-1)*displayLimit) and curSelected <= 1+(i-1)*displayLimit+(displayLimit-1)))
					DD:UIDropDownMenu_AddButton(dropDownMenuItem, level)
				end

			end
		else -- level 3

			dropDownMenuItem.func = self.FilterSetValue
			if L_UIDROPDOWNMENU_MENU_VALUE == L["PLAYERS"] then

				--for i=playersRange[menuList], playersRange[menuList]+(displayLimit-1) do
				-- depending on menuList value from higher level this should give
				-- for i.e menuList = 3
				-- for i = 1+(3-1)*20 = 41 ,  1+(3-1)*20+(20-1) = 60 do
				for i=1+(menuList-1)*displayLimit, 1+(menuList-1)*displayLimit+(displayLimit-1) do
					if PlayerList[i] then
						
						local classSearch = CommDKP:Table_Search(CommDKP:GetTable(CommDKP_DKPTable, true), PlayerList[i])
						local c;

						if classSearch then
							-- CommDKP:GetCColors(CommDKP:GetTable(CommDKP_DKPTable, true)[classSearch[1][1]].class)

							c = CommDKP:GetCColors(CommDKP:GetTable(CommDKP_DKPTable, true)[classSearch[1][1]].class)
						else
							c = { hex="ff444444" }
						end
						dropDownMenuItem.text = "|c"..c.hex..PlayerList[i].."|r" 
						dropDownMenuItem.value = "|c"..c.hex..PlayerList[i].."|r" 
						dropDownMenuItem.arg1 = PlayerList[i]
						dropDownMenuItem.arg2 = L["PLAYERS"]
						dropDownMenuItem.isNotRadio = true
						dropDownMenuItem.checked =  PlayerList[i] == curfilterValue
						dropDownMenuItem.menuList = i
						DD:UIDropDownMenu_AddButton(dropDownMenuItem, level)
					end
				end
				
			elseif L_UIDROPDOWNMENU_MENU_VALUE == L["ITEMS"] then

				for  i=1+(menuList-1)*displayLimit, 1+(menuList-1)*displayLimit+(displayLimit-1) do
					if ItemList[i] then
						dropDownMenuItem.text = ItemList[i]
						dropDownMenuItem.value = ItemList[i]
						dropDownMenuItem.arg1 = ItemList[i]
						dropDownMenuItem.arg2 = L["ITEMS"]
						dropDownMenuItem.isNotRadio = true
						dropDownMenuItem.checked =  ItemList[i] == curfilterValue
						dropDownMenuItem.menuList = i
						DD:UIDropDownMenu_AddButton(dropDownMenuItem, level)
					end
				end
			end
		end
	end)

	sortDropdown:ClearAllPoints()
	sortDropdown:SetPoint("LEFT", CommDKP.ConfigTab5.FilterCard.Body, "LEFT", W.PAD, 0)   -- §12.3.6 Filter card

	DD:UIDropDownMenu_SetWidth(sortDropdown, FILTER_DD_W)                       -- was 200 (AD-22.2.2)
	DD:UIDropDownMenu_SetText(sortDropdown, curDropDownMenuFilterCategory or "Filter Name")

  -- Dropdown Menu Function
  function sortDropdown:FilterSetValue(newValue, arg2)
 
	-- text  - display string
	-- value - formatted string for player class color
	-- arg1  - actual value which we filter by
	-- arg2  - decode which filtering is going on
	 	-- L["NOFILTER"]
		-- L["DELETEDENTRY"] 
		-- L["PLAYERS"]
		-- L["ITEMS"]

	if curDropDownMenuFilterCategory ~= arg2 then 
		curDropDownMenuFilterCategory = arg2 
		if curfilterValue == nil or curfilterValue ~= newValue then
			curfilterValue = newValue
		end
	elseif curDropDownMenuFilterCategory == arg2 then
		if curfilterValue == nil or curfilterValue ~= newValue then
			curfilterValue = newValue
		elseif curfilterValue == newValue then
			curDropDownMenuFilterCategory = nil
			curfilterValue = nil
		end
	end
	
	if curDropDownMenuFilterCategory == nil and curfilterValue == nil then
		curSelected = 0
		DD:UIDropDownMenu_SetText(sortDropdown, L["NOFILTER"])
	elseif arg2 == L["NOFILTER"] or arg2 == L["DELETEDENTRY"] then
		curSelected = 0
		DD:UIDropDownMenu_SetText(sortDropdown, newValue)
	elseif arg2 == L["ITEMS"] then
		curSelected = self.menuList
		DD:UIDropDownMenu_SetText(sortDropdown, newValue)
	elseif arg2 == L["PLAYERS"] then
		curSelected = self.menuList
		DD:UIDropDownMenu_SetText(sortDropdown, self.value)
	end

	if curDropDownMenuFilterCategory == nil and curfilterValue == nil then
		CommDKP:LootHistory_Update(L["NOFILTER"])
	else
		CommDKP:LootHistory_Update(newValue)
	end
    
    LibDD:CloseDropDownMenus()
  end

	-- AD-22.2.3 (CDKP-015a): Zone / Boss dropdown shares the sortDropdown lifecycle
	if not zoneBossDropdown then
		zoneBossDropdown = DD:Create_UIDropDownMenu("CommDKPLootZoneBossDropDown", CommDKP.ConfigTab5.FilterCard.Body)
		function zoneBossDropdown:ZoneBossSetValue(zone, boss) SetZoneBoss(zone, boss) end   -- test/automation seam
	end
	DD:UIDropDownMenu_Initialize(zoneBossDropdown, ZoneBossInit)
	zoneBossDropdown:ClearAllPoints()
	zoneBossDropdown:SetPoint("LEFT", sortDropdown, "RIGHT", W.GUT, 0)
	DD:UIDropDownMenu_SetWidth(zoneBossDropdown, FILTER_DD_W)
	DD:UIDropDownMenu_SetText(zoneBossDropdown, ZoneBossLabel())                 -- label truth after every rebuild
	LayoutFilterCaption(CommDKP.ConfigTab5)
end

---------------------------------------
-- CDKP-012f1 (AD-19.2 (f) Part 1, UX §13.5, ruling R5): Loot Log as a cellular spreadsheet table.
-- Sticky 24 px column strip + NUM_ROWS recycled 18 px rows in a FauxScrollFrame (virtualized: no "Load More").
-- Columns (Σ 510): Date 84 L | Player 96 L | Item 176 L | Cost 52 R | Boss / Zone 102 L (AD-22.2.1)
---------------------------------------
local tooltip = CreateFrame("GameTooltip", "CommDKPLootLogTooltip", UIParent, "GameTooltipTemplate")
local NUM_ROWS = 19                                  -- R5: the §13.5.1 fallback count (534 x 403 Log card)
local ROW_H = core.TableRowHeight or 18
local TABLE_W = 510
local CELL_PAD = 6
local COLUMNS = {   -- AD-22.2.1 (CDKP-015a): Σ 510; Date text area 84 − 12 = 72 px (BR-15.1.4 / BR-15.2.1)
	{ key = "date",   w = 84,  align = "LEFT",  label = function() return L["LOGCOL_DATE"] or "Date" end },
	{ key = "player", w = 96,  align = "LEFT",  label = function() return L["PLAYER"] or "Player" end },
	{ key = "item",   w = 176, align = "LEFT",  label = function() return L["ITEM"] or "Item" end },
	{ key = "cost",   w = 52,  align = "RIGHT", label = function() return L["LOGCOL_COST"] or "Cost" end },
	{ key = "boss",   w = 102, align = "LEFT",  label = function() return L["LOGCOL_BOSSZONE"] or "Boss / Zone" end },
}
local function ColW(key) for _, c in ipairs(COLUMNS) do if c.key == key then return c.w end end return 0 end
local BOSS_TEXT_W = ColW("boss") - 2 * CELL_PAD      -- 90; BR-15.2.3: looked up by key, never by index
local ITEM_ICON_X, ITEM_TEXT_X = 5, 26               -- §13.5.2: 16x16 icon at +5, link text at +26
local GUIDE_COLOR = { 0.478, 0.373, 0.165, 0.35 }    -- trimQuiet @ 35 % (§13.5.1)

-- activeFilter is declared at file top (AD-22.2.3: SetZoneBoss reads it)
local dateCache = {}                                 -- entry -> FormatTime string of its displayed date

local function C(role)
	local p = core.Palette or (core.Palettes and core.Palettes.Forever) or {}
	return p[role] or { 1, 1, 1, 1 }
end

local function ClassHex(player)
	local s = CommDKP:Table_Search(CommDKP:GetTable(CommDKP_DKPTable, true), player)
	if s then
		local c = CommDKP:GetCColors(CommDKP:GetTable(CommDKP_DKPTable, true)[s[1][1]].class)
		if c and c.hex then return c.hex end
	end
	return "ff444444"
end

local function ItemIcon(link)
	if type(link) ~= "string" or not C_Item then return nil end
	local icon
	if C_Item.GetItemInfoInstant then icon = select(5, C_Item.GetItemInfoInstant(link)) end
	if not icon and C_Item.GetItemIconByID then
		local id = tonumber(link:match("item:(%d+)"))
		if id then icon = C_Item.GetItemIconByID(id) end
	end
	return icon
end

-- AD-19.2 (f) data parity: the shipped :439-464 predicates, verbatim, as one pure builder.
-- `category` is the dropdown category the shipped code read from curDropDownMenuFilterCategory.
local function ZoneBossMatch(e, zone, boss)                -- BR-15.3.3: exact, on the row entry's own stored strings
	if not zone then return true end
	if e.zone ~= zone then return false end
	return boss == nil or e.boss == boss
end
local function BuildLootRows(filter, category, zone, boss)   -- AD-22.2.4: zone/boss ANDed into every guard
	local LootTable = {}
	if filter and filter ~= L["NOFILTER"] and filter ~= L["DELETEDENTRY"] then
		-- items or players
		for i=1, #CommDKP:GetTable(CommDKP_Loot, true) do
			if category == L["PLAYERS"] then
				if not CommDKP:GetTable(CommDKP_Loot, true)[i].deletes and not CommDKP:GetTable(CommDKP_Loot, true)[i].deletedby and not CommDKP:GetTable(CommDKP_Loot, true)[i].hidden and CommDKP:GetTable(CommDKP_Loot, true)[i].player == filter and ZoneBossMatch(CommDKP:GetTable(CommDKP_Loot, true)[i], zone, boss) then
					table.insert(LootTable, CommDKP:GetTable(CommDKP_Loot, true)[i])
				end
			elseif category == L["ITEMS"] then
				if not CommDKP:GetTable(CommDKP_Loot, true)[i].deletes and not CommDKP:GetTable(CommDKP_Loot, true)[i].deletedby and not CommDKP:GetTable(CommDKP_Loot, true)[i].hidden and CommDKP:GetTable(CommDKP_Loot, true)[i].loot == filter and ZoneBossMatch(CommDKP:GetTable(CommDKP_Loot, true)[i], zone, boss) then
					table.insert(LootTable, CommDKP:GetTable(CommDKP_Loot, true)[i])
				end
			end
		end
	elseif filter and filter == L["DELETEDENTRY"] then
		for i=1, #CommDKP:GetTable(CommDKP_Loot, true) do
			if CommDKP:GetTable(CommDKP_Loot, true)[i].deletes and ZoneBossMatch(CommDKP:GetTable(CommDKP_Loot, true)[i], zone, boss) then
				table.insert(LootTable, CommDKP:GetTable(CommDKP_Loot, true)[i])
			end
		end
	else -- no filter
		for i=1, #CommDKP:GetTable(CommDKP_Loot, true) do
			if not CommDKP:GetTable(CommDKP_Loot, true)[i].deletes and not CommDKP:GetTable(CommDKP_Loot, true)[i].deletedby and not CommDKP:GetTable(CommDKP_Loot, true)[i].hidden and ZoneBossMatch(CommDKP:GetTable(CommDKP_Loot, true)[i], zone, boss) then
				table.insert(LootTable, CommDKP:GetTable(CommDKP_Loot, true)[i])
			end
		end
	end
	return LootTable
end

-- Shipped :483-489: in the Deleted view the displayed date is the deleted (original) entry's date.
local function DeletedOriginal(entry)
	if not entry.deletes then return nil end
	local s = CommDKP:Table_Search(CommDKP:GetTable(CommDKP_Loot, true), entry.deletes, "index")
	return s and CommDKP:GetTable(CommDKP_Loot, true)[s[1][1]] or nil
end

local function DisplayDate(entry)
	local d = dateCache[entry]
	if d then return d end
	local src = entry.date
	if activeFilter == L["DELETEDENTRY"] then
		local orig = DeletedOriginal(entry)
		if orig and orig.date then src = orig.date end
	end
	d = CommDKP:FormatTime(src) or ""
	dateCache[entry] = d
	return d
end

-- "yy/mm/dd HH:MM:SS" -> "mm/dd/yy", "HH:MM:SS", yy, mm, dd
local function SplitDate(thedate)
	local day = strtrim(strsub(thedate, 1, 8), " ")
	local date1, date2, date3 = strsplit("/", day)
	return (date2 or "").."/"..(date3 or "").."/"..(date1 or ""), strtrim(strsub(thedate, 10), " "), date1, date2, date3, day
end

local function LootCost(entry)
	local cost = tonumber(entry.cost) or 0
	if cost < 0 then cost = cost * -1 end
	return cost
end

---------------------------------------
-- Tooltip (shipped :575-672, moved verbatim into the row; reads row.entry). Additions: (Reassigned) and the
-- UX "Zone: Boss  MM/DD/YY HH:MM" last line.
---------------------------------------
local function Row_OnEnter(self)
	local entry = self.entry
	if not entry then return end
	local filter = activeFilter
	local itemToLink = entry["loot"]
	local history = 0;
	local c
	tooltip:SetOwner(self, "ANCHOR_RIGHT", 0, 0)
	if type(itemToLink) == "string" and itemToLink:find("item[%-?%d:]+") then
		tooltip:SetHyperlink(itemToLink)
	else
		tooltip:SetText(tostring(itemToLink or ""))
	end
	tooltip:AddLine(" ")

	local awardOfficer

	if filter == L["DELETEDENTRY"] then
		awardOfficer = strsplit("-", entry.deletes)
	else
		awardOfficer = strsplit("-", entry.index)
	end

	local awarded_by_search = CommDKP:Table_Search(CommDKP:GetTable(CommDKP_DKPTable, true), awardOfficer, "player")
	if awarded_by_search then
		c = CommDKP:GetCColors(CommDKP:GetTable(CommDKP_DKPTable, true)[awarded_by_search[1][1]].class)
	else
		c = { hex="ff444444" }
	end

	if entry.bids or entry.dkp or entry.rolls then  		-- displays bids/rolls/dkp values if "Log Bids" checked in modes
		local path;

		tooltip:AddLine(" ")
		if entry.bids then
			tooltip:AddLine(L["BIDS"]..":", 0.25, 0.75, 0.90)
			table.sort(entry.bids, function(a, b)
				return a["bid"] > b["bid"]
			end)
			path = entry.bids
		elseif entry.dkp then
			tooltip:AddLine(L["DKPVALUES"]..":", 0.25, 0.75, 0.90)
			table.sort(entry.dkp, function(a, b)
				return a["dkp"] > b["dkp"]
			end)
			path = entry.dkp
		elseif entry.rolls then
			tooltip:AddLine(L["ROLLS"]..":", 0.25, 0.75, 0.90)
			table.sort(entry.rolls, function(a, b)
				return a["roll"] > b["roll"]
			end)
			path = entry.rolls
		end
		for j=1, #path do
			local col;
			local bidder = path[j].bidder
			local s = CommDKP:Table_Search(CommDKP:GetTable(CommDKP_DKPTable, true), bidder)
			local path2 = path[j].bid or path[j].dkp or path[j].roll

			if s then
				col = CommDKP:GetCColors(CommDKP:GetTable(CommDKP_DKPTable, true)[s[1][1]].class)
			else
				col = { hex="ff444444" }
			end
			if bidder == entry.player then
				tooltip:AddLine("|c"..col.hex..bidder.."|r: |cff00ff00"..path2.."|r")
			else
				tooltip:AddLine("|c"..col.hex..bidder.."|r: |cffff0000"..path2.."|r")
			end
		end
	end
	for j=1, #CommDKP:GetTable(CommDKP_Loot, true) do
		if CommDKP:GetTable(CommDKP_Loot, true)[j]["loot"] == itemToLink and entry.date ~= CommDKP:GetTable(CommDKP_Loot, true)[j].date and not CommDKP:GetTable(CommDKP_Loot, true)[j].deletedby and not CommDKP:GetTable(CommDKP_Loot, true)[j].deletes then
			local col;
			local s = CommDKP:Table_Search(CommDKP:GetTable(CommDKP_DKPTable, true), CommDKP:GetTable(CommDKP_Loot, true)[j].player)
			if s then
				col = CommDKP:GetCColors(CommDKP:GetTable(CommDKP_DKPTable, true)[s[1][1]].class)
			else
				col = { hex="ff444444" }
			end
			if history == 0 then
				tooltip:AddLine(" ");
				tooltip:AddLine(L["ALSOWONBY"]..":", 0.25, 0.75, 0.90, 1, true);
				history = 1;
			end
			tooltip:AddDoubleLine("|c"..col.hex..CommDKP:GetTable(CommDKP_Loot, true)[j].player.."|r |cffffffff("..date("%m/%d/%y", CommDKP:GetTable(CommDKP_Loot, true)[j].date)..")|r", "|cffff0000"..-CommDKP:GetTable(CommDKP_Loot, true)[j].cost.." "..L["DKP"].."|r", 1.0, 0, 0)
		end
	end
	if filter == L["DELETEDENTRY"] then
		local orig = DeletedOriginal(entry)
		if orig and orig.deletedby then
			local delOfficer,_ = strsplit("-", orig.deletedby)
			local col
			local del_date = CommDKP:FormatTime(entry.date)
			local del_date1, del_date2, del_date3 = strsplit("/", strtrim(strsub(del_date, 1, 8), " "))
			local s = CommDKP:Table_Search(CommDKP:GetTable(CommDKP_DKPTable, true), delOfficer, "player")
			if s then
				col = CommDKP:GetCColors(CommDKP:GetTable(CommDKP_DKPTable, true)[s[1][1]].class)
			else
				col = { hex="ff444444"}
			end
			tooltip:AddLine(" ")
			tooltip:AddLine(L["DELETEDBY"], 0.25, 0.75, 0.90, 1, true)
			tooltip:AddDoubleLine("|c"..col.hex..delOfficer.."|r", del_date2.."/"..del_date3.."/"..del_date1.." @ "..strtrim(strsub(del_date, 10), " "),1,0,0,1,1,1)
		end
	end
	tooltip:AddLine(" ")
	tooltip:AddDoubleLine(L["AWARDEDBY"], "|c"..c.hex..awardOfficer.."|r", 0.25, 0.75, 0.90)
	if entry.reassigned then
		tooltip:AddLine("|cff555555("..L["REASSIGNED"]..")|r")
	end
	-- UX §13.5.2 last line: "Zone: Boss  MM/DD/YY HH:MM" (the full Boss / Zone text when the cell truncates).
	local day, clock = SplitDate(DisplayDate(entry))
	tooltip:AddLine(tostring(entry.zone or "")..": "..tostring(entry.boss or "").."  "..day.." "..strsub(clock, 1, 5), 0.73, 0.65, 0.54)
	tooltip:Show();
end

local function Row_OnLeave()
	tooltip:Hide()
end

-- Shipped :673-689: right-click officer menu (never in the Deleted view); Shift/Alt-click chat links.
local function Row_OnMouseDown(self, button)
	local entry = self.entry
	if not entry then return end
	local filter = activeFilter
	if button == "RightButton" and filter ~= L["DELETEDENTRY"] then
		if core.IsOfficer == true then
			RightClickLootMenu(self, entry.index)
		end
	elseif button == "LeftButton" then
		local itemToLink = entry["loot"]
		if IsShiftKeyDown() then
			ChatFrame1EditBox:Show();
			ChatFrame1EditBox:SetText(ChatFrame1EditBox:GetText()..itemToLink)	-- CDKP-004: itemToLink is already the stored item link
			ChatFrame1EditBox:SetFocus();
		elseif IsAltKeyDown() then
			local _, _, date1, date2, date3 = SplitDate(DisplayDate(entry))
			ChatFrame1EditBox:Show();
			ChatFrame1EditBox:SetText(ChatFrame1EditBox:GetText()..entry["player"].." "..L["WON"].." "..itemToLink.." "..L["OFF"].." "..entry["boss"].." "..L["IN"].." "..entry["zone"].." ("..date2.."/"..date3.."/"..date1..") "..L["FOR"].." "..-entry["cost"].." "..L["DKP"])
			ChatFrame1EditBox:SetFocus();
		end
	end
end

---------------------------------------
-- Table frame (built lazily on the first LootHistory_Update; AD-19.2 (f) shared table frame)
---------------------------------------
local Refresh

local function CreateCell(row, col, x)
	local fs = W.CreateText(row, "body", nil, col.align)
	fs:SetWordWrap(false)
	fs:SetHeight(ROW_H)
	if col.key == "item" then
		fs:SetPoint("LEFT", row, "LEFT", x + ITEM_TEXT_X, 0)
		fs:SetWidth(col.w - ITEM_TEXT_X - CELL_PAD)
	else
		fs:SetPoint("LEFT", row, "LEFT", x + CELL_PAD, 0)
		fs:SetWidth(col.w - 2 * CELL_PAD)
	end
	return fs
end

local function BuildLootLogTable(tab)
	if tab.LogTable then return tab.LogTable end
	local body = tab.LogCard and tab.LogCard.Body
	if not body then return nil end
	if tab.LogScroll then tab.LogScroll:Hide() end       -- the pre-012f feed region retires (kept for 012f2 parity)

	-- Sticky column strip (outside the scroll frame) with gold labels and 16 px rule ticks at the boundaries.
	local strip = W.CreateColumnStrip(body, 24)
	strip:SetPoint("TOPLEFT", body, "TOPLEFT", 4, 0)
	strip:SetWidth(TABLE_W)
	strip.Labels, strip.Ticks = {}, {}
	local x = 0
	for ci, col in ipairs(COLUMNS) do
		local lbl = W.CreateText(strip, "label", col.label(), col.align, "gold")
		lbl:SetWordWrap(false)
		lbl:SetPoint("LEFT", strip, "LEFT", x + CELL_PAD, 0)
		lbl:SetWidth(col.w - 2 * CELL_PAD)
		strip.Labels[ci] = lbl
		if ci > 1 then
			local tick = strip:CreateTexture(nil, "ARTWORK")
			tick:SetColorTexture(unpack(C("rule")))
			tick:SetWidth(1); tick:SetHeight(16)
			tick:SetPoint("LEFT", strip, "LEFT", x, 0)
			strip.Ticks[#strip.Ticks + 1] = tick
		end
		x = x + col.w
	end

	local sf = CreateFrame("ScrollFrame", "CommDKPLootLogScroll", body, "FauxScrollFrameTemplate")
	sf:SetPoint("TOPLEFT", body, "TOPLEFT", 4, -24)
	sf:SetSize(TABLE_W, NUM_ROWS * ROW_H)
	sf:SetScript("OnVerticalScroll", function(self, off)
		FauxScrollFrame_OnVerticalScroll(self, off, ROW_H, Refresh)
	end)

	-- Recycled rows (Buttons, so the hover/click surface is the whole row).
	local rows = {}
	for i = 1, NUM_ROWS do
		local row = CreateFrame("Button", nil, body)
		row:SetSize(TABLE_W, ROW_H)
		row:SetPoint("TOPLEFT", sf, "TOPLEFT", 0, -(i - 1) * ROW_H)
		W.StyleRow(row, i)
		row.cells = {}
		local cx = 0
		for ci, col in ipairs(COLUMNS) do
			row.cells[col.key] = CreateCell(row, col, cx)
			if col.key == "item" then
				row.icon = row:CreateTexture(nil, "ARTWORK")
				row.icon:SetSize(16, 16)
				row.icon:SetPoint("LEFT", row, "LEFT", cx + ITEM_ICON_X, 0)
			end
			cx = cx + col.w
		end
		-- Day break: 1 px trim @ 30 % at the top of the first row of a new date.
		row.dayRule = row:CreateTexture(nil, "ARTWORK")
		row.dayRule:SetPoint("TOPLEFT", row, "TOPLEFT", 0, 0)
		row.dayRule:SetPoint("TOPRIGHT", row, "TOPRIGHT", 0, 0)
		row.dayRule:SetHeight(1)
		local t = C("trim")
		row.dayRule:SetColorTexture(t[1], t[2], t[3], 0.30)
		row.dayRule:Hide()
		-- Reassigned: 2 px warning bar at the row's left edge.
		row.reassignBar = row:CreateTexture(nil, "ARTWORK")
		row.reassignBar:SetPoint("TOPLEFT", row, "TOPLEFT", 0, 0)
		row.reassignBar:SetPoint("BOTTOMLEFT", row, "BOTTOMLEFT", 0, 0)
		row.reassignBar:SetWidth(2)
		row.reassignBar:SetColorTexture(unpack(C("warning")))
		row.reassignBar:Hide()
		row:SetScript("OnEnter", Row_OnEnter)
		row:SetScript("OnLeave", Row_OnLeave)
		row:SetScript("OnMouseDown", Row_OnMouseDown)
		row:Hide()
		rows[i] = row
	end

	-- Vertical cell guides: full row-area height, on a mouse-transparent overlay above the rows.
	local grid = CreateFrame("Frame", nil, body)
	grid:SetAllPoints(sf)
	grid:SetFrameLevel((rows[NUM_ROWS]:GetFrameLevel() or 0) + 2)
	if grid.EnableMouse then grid:EnableMouse(false) end
	grid.Guides = {}
	x = 0
	for ci, col in ipairs(COLUMNS) do
		if ci > 1 then
			local g = grid:CreateTexture(nil, "OVERLAY")
			g:SetColorTexture(unpack(GUIDE_COLOR))
			g:SetWidth(1)
			g:SetPoint("TOPLEFT", grid, "TOPLEFT", x, 0)
			g:SetPoint("BOTTOMLEFT", grid, "BOTTOMLEFT", x, 0)
			grid.Guides[#grid.Guides + 1] = g
		end
		x = x + col.w
	end

	W.AttachFauxRail(sf, body)

	tab.LogTable = sf
	tab.LogStrip = strip
	tab.LogGrid = grid
	tab.LogRows = rows
	tab.rows = tab.rows or {}
	return sf
end

local function PaintRow(row, entry, prev)
	row.entry = entry
	local cells = row.cells
	local deletedView = activeFilter == L["DELETEDENTRY"]
	local thedate = DisplayDate(entry)
	local day = SplitDate(thedate)

	-- Date
	cells.date:SetText(day)
	cells.date:SetTextColor(unpack(C(deletedView and "textDisabled" or "textMuted")))

	-- Player (class colour; fallback ff444444)
	local player = tostring(entry.player or "")
	if deletedView then
		cells.player:SetText(player)
		cells.player:SetTextColor(unpack(C("textDisabled")))
	else
		cells.player:SetText("|c"..ClassHex(player)..player.."|r")
		cells.player:SetTextColor(unpack(C("text")))
	end

	-- Item: icon + quality-coloured link (kept coloured in the Deleted view)
	cells.item:SetText(W.SafeText(entry.loot))
	cells.item:SetTextColor(unpack(C("text")))
	local icon = ItemIcon(entry.loot)
	row.icon:SetTexture(icon or "Interface\\Icons\\INV_Misc_QuestionMark")
	row.icon:SetDesaturated(deletedView and true or false)

	-- Cost: -X in legacy red, 0 muted
	local cost = LootCost(entry)
	if cost == 0 then
		cells.cost:SetText("0")
		cells.cost:SetTextColor(unpack(C(deletedView and "textDisabled" or "textMuted")))
	elseif deletedView then
		cells.cost:SetText("-"..cost)
		cells.cost:SetTextColor(unpack(C("textDisabled")))
	else
		cells.cost:SetText("|cffff0000-"..cost.."|r")
		cells.cost:SetTextColor(unpack(C("text")))
	end

	-- Boss / Zone: boss, zone appended muted when it fits (else it lives in the tooltip's last line)
	local boss, zone = tostring(entry.boss or ""), tostring(entry.zone or "")
	cells.boss:SetTextColor(unpack(C(deletedView and "textDisabled" or "text")))
	if zone ~= "" and not deletedView then
		cells.boss:SetText(boss.." |cffb9a789"..zone.."|r")
		local w = cells.boss:GetStringWidth() or 0
		if w > BOSS_TEXT_W then cells.boss:SetText(boss) end
	else
		cells.boss:SetText(boss)
	end

	row.dayRule:SetShown(prev ~= nil and SplitDate(DisplayDate(prev)) ~= day)
	row.reassignBar:SetShown(entry.reassigned and true or false)
	row:Show()
end

Refresh = function()
	local tab = CommDKP.ConfigTab5
	local sf = tab and tab.LogTable
	if not sf then return end
	local data = tab.rows or {}
	FauxScrollFrame_Update(sf, #data, NUM_ROWS, ROW_H, nil, nil, nil, nil, nil, nil, true)
	local offset = FauxScrollFrame_GetOffset(sf) or 0
	for i = 1, NUM_ROWS do
		local row = tab.LogRows[i]
		local idx = offset + i
		local entry = data[idx]
		if entry then
			PaintRow(row, entry, data[idx - 1])
		else
			row.entry = nil
			row:Hide()
		end
	end
	if sf.cdkpRailSync then sf.cdkpRailSync() end
end

local function ResetOffset(sf)
	if not sf then return end
	FauxScrollFrame_SetOffset(sf, 0)
	local n = sf.GetName and sf:GetName()
	local sb = sf.ScrollBar or (n and _G[n .. "ScrollBar"])
	if sb and sb.SetValue then sb:SetValue(0) end
end

function CommDKP:LootHistory_Reset()
	local tab = CommDKP.ConfigTab5
	if not tab then return end
	CommDKP:ClearLootHistoryFrames();
	ResetOffset(tab.LogTable)
end

function CommDKP:LootHistory_Update(filter)				-- if "filter" is included in call, runs set assigned for when a filter is selected in dropdown.
	if not CommDKP.UIConfig:IsShown() then
		return
	end
	local tab = CommDKP.ConfigTab5
	CommDKP:SortLootTable()

	if filter and filter == L["NOFILTER"] then
		curDropDownMenuFilterCategory = L["NOFILTER"]
		CommDKP:CreateSortBox()
	end
	if filter then
		CommDKP:LootHistory_Reset()
	end

	activeFilter = filter
	dateCache = {}
	tab.rows = BuildLootRows(filter, curDropDownMenuFilterCategory, curZoneFilter, curBossFilter)

	LayoutFilterCaption(tab)                                   -- AD-22.2.2: re-fit before text is set
	tab.inst:SetText(L["LOOTHISTINST1"]);
	if core.IsOfficer == true then
		tab.inst:SetText(L["LOOTHISTINST1"].."\n"..L["LOOTHISTINST2"].."\n"..L["LOOTHISTINST3"])
	end

	if not BuildLootLogTable(tab) then return end
	Refresh()
end
