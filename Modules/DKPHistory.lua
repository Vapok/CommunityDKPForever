local _, core = ...;
local _G = _G;
local CommDKP = core.CommDKP;
local L = core.L;
local LibDD = LibStub:GetLibrary("LibUIDropDownMenu-4.0");
local DD = CommDKP.DD                     -- AD-16.3: selector protocol (the right-click menuFrame below stays on LibDD, Q4)
local W = CommDKP.Widgets

local filter;
local filterDropdown, curfilterName       -- CDKP-012f2: file-local (were accidental globals)
local menuFrame = LibDD:Create_UIDropDownMenu("CommDKPDeleteDKPMenuFrame", UIParent)
CommDKP.Widgets.RegisterContextMenu(menuFrame) -- CDKP-019 (AD-27.2.3)
local reasonDropdown                      -- AD-22.3.3: global frame name "CommDKPDKPHistoryReasonDropDown"
local reasonSel                           -- nil = No Filter; never written into `filter` / `activeFilter` (S9)
local classCache = {}                     -- raw reason string -> { group, base, zone, boss, label }

---------------------------------------
-- AD-22.2.2 / AD-22.3.2: Filter card geometry — caption re-fit (idempotent; overrides the 300-px creation width)
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
-- AD-22.3.3 (CDKP-015b): Reason classifier
---------------------------------------
local STANDBY_SUFFIX = " (Standby)"                         -- AutoAward.lua:67 literal (not localised at the source)
local EXCLUDED = { ["Delete Entry"] = true, ["Migration Correction"] = true }
local function StripSuffix(s, suf)
	if #s > #suf and strsub(s, -#suf) == suf then return strsub(s, 1, -#suf - 1), true end
	return s, false
end
-- Returns group ("STANDARD" | "BOSSKILL" | "OTHER"), base, zone, boss, label; or nil for excluded / blank reasons.
local function ClassifyReason(raw)
	if type(raw) ~= "string" or raw:match("^%s*$") or EXCLUDED[raw] then return nil end
	local c = classCache[raw]
	if c then return c[1], c[2], c[3], c[4], c[5] end
	local fk = " (" .. (L["FIRSTKILL"] or "First Kill") .. ")"
	local base, a, b = raw, true, true
	while a or b do base, a = StripSuffix(base, STANDBY_SUFFIX); base, b = StripSuffix(base, fk) end   -- any order, repeated
	local g, zone, boss, label
	local op = (L["OTHER"] or "Other") .. " - "
	if strsub(base, 1, #op) == op and #base > #op then                       -- 1. "Other - " first (text may hold ": ")
		g, label = "OTHER", strsub(base, #op + 1)
	else
		zone, boss = base:match("^(.-): (.+)$")                               -- 2. "Zone: Boss" (first ": ")
		if zone and zone ~= "" then g, label = "BOSSKILL", boss
		else g, zone, boss, label = "STANDARD", nil, nil, base end            -- 3. everything else
	end
	classCache[raw] = { g, base, zone, boss, label }
	return g, base, zone, boss, label
end
function CommDKP:ClassifyDKPReason(raw) return ClassifyReason(raw) end     -- AD-22.1 testability seam (pure)

---------------------------------------
-- AD-22.3.4 (CDKP-015b): Reason menu — shared helpers (own copy; AD-22.2.3), index, builder, setter
---------------------------------------
local PAGE = 20                                             -- "paged in 20s exactly like the existing dropdowns"
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

-- Field-by-field comparison (never table identity: the menu rebuilds its tables on every open).
local function SameSel(a, b)
	if a == nil or b == nil then return a == b end
	return a.kind == b.kind and a.base == b.base and a.zone == b.zone and a.boss == b.boss
end

-- Index (rebuilt on every open): STANDARD / OTHER distinct bases; BOSSKILL zones -> bosses.
local function BuildReasonIndex()
	local std, other, zones, byZone = {}, {}, {}, {}
	local seenStd, seenOther = {}, {}
	for _, e in ipairs(CommDKP:GetTable(CommDKP_DKPHistory, true)) do
		local g, base, zone, boss, label = ClassifyReason(e.reason)
		if g == "STANDARD" then
			if not seenStd[base] then
				seenStd[base] = true
				std[#std + 1] = { label = base, sel = { kind = "base", group = "STANDARD", base = base, label = base } }
			end
		elseif g == "OTHER" then
			if not seenOther[base] then
				seenOther[base] = true
				other[#other + 1] = { label = label, sel = { kind = "base", group = "OTHER", base = base, label = label } }
			end
		elseif g == "BOSSKILL" then
			local z = byZone[zone]
			if not z then z = { label = zone, bosses = {}, seen = {} }; byZone[zone] = z; zones[#zones + 1] = z end
			if not z.seen[boss] then z.seen[boss] = true; z.bosses[#z.bosses + 1] = { label = boss } end
		end
	end
	SortAZ(std); SortAZ(other); SortAZ(zones)
	for _, z in ipairs(zones) do SortAZ(z.bosses) end
	return std, other, zones, byZone
end

local SetReason                                             -- forward declaration (defined below ReasonInit)

-- true when page `p` of `items` holds an entry satisfying pred(item)
local function PageAny(items, p, pred)
	for i = (p - 1) * PAGE + 1, math.min(p * PAGE, #items) do
		if pred(items[i]) then return true end
	end
	return false
end

-- menuList is a table tag: dispatch by `kind`, not by level number (AD-22.3.4).
local function ReasonInit(self, level, menuList)
	level = level or 1
	local std, other, zones, byZone = BuildReasonIndex()

	local function EmitSel(item)
		DD:UIDropDownMenu_AddButton({ text = item.label, isNotRadio = true, checked = SameSel(reasonSel, item.sel),
			func = function() SetReason(item.sel) end }, level)
	end
	local function SelChecked(items)
		return function(p) return PageAny(items, p, function(it) return SameSel(reasonSel, it.sel) end) end
	end
	local function EmitZone(z)
		DD:UIDropDownMenu_AddButton({ text = z.label, hasArrow = true, isNotRadio = true,
			checked = (reasonSel and reasonSel.zone == z.label) and true or false,
			menuList = { kind = "bzone", zone = z.label } }, level)
	end

	if level == 1 then
		DD:UIDropDownMenu_AddButton({ text = L["NOFILTER"], isNotRadio = true, checked = reasonSel == nil,
			func = function() SetReason(nil) end }, level)
		Separator(level)
		AddPaged(level, std, nil, EmitSel, function(p) return { kind = "std", page = p } end, SelChecked(std))
		if #zones > 0 then
			DD:UIDropDownMenu_AddButton({ text = L["BOSSKILLBONUS"] or "Boss Kill Bonus", hasArrow = true, isNotRadio = true,
				menuList = { kind = "boss" }, checked = (reasonSel and reasonSel.kind ~= "base") and true or false }, level)
		end
		if #other > 0 then
			DD:UIDropDownMenu_AddButton({ text = L["OTHER"] or "Other", hasArrow = true, isNotRadio = true,
				menuList = { kind = "other" }, checked = (reasonSel and reasonSel.group == "OTHER") and true or false }, level)
		end
		return
	end

	local kind = type(menuList) == "table" and menuList.kind
	if kind == "std" then
		AddPaged(level, std, menuList.page, EmitSel)
	elseif kind == "boss" then
		if not menuList.page then
			local allText = L["ALLBOSSKILLS"] or "All Boss Kills"
			DD:UIDropDownMenu_AddButton({ text = allText, isNotRadio = true,
				checked = (reasonSel and reasonSel.kind == "allboss") and true or false,
				func = function() SetReason({ kind = "allboss", label = allText }) end }, level)
		end
		AddPaged(level, zones, menuList.page, EmitZone,
			function(p) return { kind = "boss", page = p } end,
			function(p) return PageAny(zones, p, function(z) return reasonSel ~= nil and reasonSel.zone == z.label end) end)
	elseif kind == "bzone" then
		local zone = menuList.zone
		local z = byZone[zone]
		if not z then return end
		local function EmitBoss(b)
			local sel = { kind = "boss", zone = zone, boss = b.label, label = b.label }
			DD:UIDropDownMenu_AddButton({ text = b.label, isNotRadio = true, checked = SameSel(reasonSel, sel),
				func = function() SetReason(sel) end }, level)
		end
		if not menuList.page then
			local sel = { kind = "zone", zone = zone, label = zone }
			DD:UIDropDownMenu_AddButton({ text = string.format(L["ALLZONE_FMT"] or "All %s", zone), isNotRadio = true,
				checked = SameSel(reasonSel, sel), func = function() SetReason(sel) end }, level)
		end
		AddPaged(level, z.bosses, menuList.page, EmitBoss,
			function(p) return { kind = "bzone", zone = zone, page = p } end,
			function(p) return reasonSel ~= nil and reasonSel.kind == "boss" and reasonSel.zone == zone
				and PageAny(z.bosses, p, function(b) return b.label == reasonSel.boss end) end)
	elseif kind == "other" then
		AddPaged(level, other, menuList.page, EmitSel, function(p) return { kind = "other", page = p } end, SelChecked(other))
	end
end

SetReason = function(sel)                                   -- the only writer of reasonSel (re-pick keeps it; no toggle)
	reasonSel = sel                                         -- nil = No Filter; never touches filter/activeFilter
	if reasonDropdown then DD:UIDropDownMenu_SetText(reasonDropdown, sel and sel.label or L["NOFILTER"]) end
	DD:CloseDropDownMenus()
	CommDKP:DKPHistory_Update(true)                         -- reset = true -> DKPHistory_Reset -> scroll 0
end


function CommDKP:SortDKPHistoryTable()             -- sorts the DKP History Table by date/time
  table.sort(CommDKP:GetTable(CommDKP_DKPHistory, true), function(a, b)
    return a["date"] > b["date"]
  end)
end

local function GetSortOptions()
	local PlayerList = {}
	for i=1, #CommDKP:GetTable(CommDKP_DKPTable, true) do
		local playerSearch = CommDKP:Table_Search(PlayerList, CommDKP:GetTable(CommDKP_DKPTable, true)[i].player)
		if not playerSearch then
			tinsert(PlayerList, CommDKP:GetTable(CommDKP_DKPTable, true)[i].player)
		end
	end
	table.sort(PlayerList, function(a, b)
		return a < b
	end)
	return PlayerList;
end

function CommDKP:DKPHistoryFilterBox_Create()
	local PlayerList = GetSortOptions();
	local curSelected = 0;

	-- Create the dropdown, and configure its appearance
	if not filterDropdown then
		filterDropdown = DD:Create_UIDropDownMenu("CommDKPDKPHistoryFilterNameDropDown", CommDKP.ConfigTab6.FilterCard.Body);
	end

	-- Create and bind the initialization function to the dropdown menu
		DD:UIDropDownMenu_Initialize(filterDropdown, function(self, level, menuList)

		local filterName = DD:UIDropDownMenu_CreateInfo()
		local ranges = {1}
		while ranges[#ranges] < #PlayerList do
			table.insert(ranges, ranges[#ranges]+20)
		end

		if (level or 1) == 1 then
			local numSubs = ceil(#PlayerList/20)
			filterName.func = self.FilterSetValue
			filterName.text, filterName.arg1, filterName.arg2, filterName.checked, filterName.isNotRadio = L["NOFILTER"], L["NOFILTER"], L["NOFILTER"], L["NOFILTER"] == curfilterName, true
			DD:UIDropDownMenu_AddButton(filterName)
			filterName.text, filterName.arg1, filterName.arg2, filterName.checked, filterName.isNotRadio = L["DELETEDENTRY"], L["DELETEDENTRY"], L["DELETEDENTRY"], L["DELETEDENTRY"] == curfilterName, true
			DD:UIDropDownMenu_AddButton(filterName)

			for i=1, numSubs do
				local max = i*20;
				if max > #PlayerList then max = #PlayerList end
				filterName.text, filterName.checked, filterName.menuList, filterName.hasArrow = strsub(PlayerList[((i*20)-19)], 1, 1).."-"..strsub(PlayerList[max], 1, 1), curSelected >= (i*20)-19 and curSelected <= i*20, i, true
				DD:UIDropDownMenu_AddButton(filterName)
			end

		else
			filterName.func = self.FilterSetValue
			for i=ranges[menuList], ranges[menuList]+19 do
				if PlayerList[i] then
					local classSearch = CommDKP:Table_Search(CommDKP:GetTable(CommDKP_DKPTable, true), PlayerList[i])
				    local c;

				    if classSearch then
				     	c = CommDKP:GetCColors(CommDKP:GetTable(CommDKP_DKPTable, true)[classSearch[1][1]].class)
				    else
				     	c = { hex="ff444444" }
				    end
					filterName.text, filterName.arg1, filterName.arg2, filterName.checked, filterName.isNotRadio = "|c"..c.hex..PlayerList[i].."|r", PlayerList[i], "|c"..c.hex..PlayerList[i].."|r", PlayerList[i] == curfilterName, true
					DD:UIDropDownMenu_AddButton(filterName, level)
				end
			end
		end
	end)

	filterDropdown:ClearAllPoints()
	filterDropdown:SetPoint("LEFT", CommDKP.ConfigTab6.FilterCard.Body, "LEFT", W.PAD, 0)   -- §12.3.6 Filter card

	DD:UIDropDownMenu_SetWidth(filterDropdown, FILTER_DD_W)                     -- was 200 (AD-22.3.2)
	DD:UIDropDownMenu_SetText(filterDropdown, curfilterName or L["NOFILTER"])

	-- AD-22.3.2 (CDKP-015b): Reason dropdown, side by side with the player filter (no officer gate, BR-15.5.3)
	if not reasonDropdown then
		reasonDropdown = DD:Create_UIDropDownMenu("CommDKPDKPHistoryReasonDropDown", CommDKP.ConfigTab6.FilterCard.Body)
		function reasonDropdown:ReasonSetValue(sel) SetReason(sel) end          -- test/automation seam
	end
	DD:UIDropDownMenu_Initialize(reasonDropdown, ReasonInit)
	reasonDropdown:ClearAllPoints()
	reasonDropdown:SetPoint("LEFT", filterDropdown, "RIGHT", W.GUT, 0)
	DD:UIDropDownMenu_SetWidth(reasonDropdown, FILTER_DD_W)
	DD:UIDropDownMenu_SetText(reasonDropdown, reasonSel and reasonSel.label or L["NOFILTER"])
	LayoutFilterCaption(CommDKP.ConfigTab6)

  -- Dropdown Menu Function
  function filterDropdown:FilterSetValue(newValue, arg2)
    if curfilterName ~= newValue then curfilterName = newValue else curfilterName = nil end
    DD:UIDropDownMenu_SetText(filterDropdown, arg2)

    if newValue == L["NOFILTER"] then
    	filter = nil;
    	curSelected = 0
    elseif newValue == L["DELETEDENTRY"] then
    	filter = newValue;
    	curSelected = 0
    else
	    filter = newValue;
	    local search = CommDKP:Table_Search(PlayerList, newValue)
	    curSelected = search and search[1] or 0
    end

    CommDKP:DKPHistory_Update(true)
    LibDD:CloseDropDownMenus()
  end
end

-- `header` = the entry's one-line description (the shipped `history[item].d` text, now built by EntryHeader below).
local function CommDKPDeleteDKPEntry(index, header)
	-- pop confirmation. If yes, cycles through CommDKP:GetTable(CommDKP_DKPHistory, true).players and every name it finds, it refunds them (or strips them of) dkp.
	-- if deleted is the weekly decay,     curdkp * (100 / (100 - decayvalue))
	local reason_header = header or "";
	if strfind(reason_header, L["OTHER"].."- ") then reason_header = reason_header:gsub(L["OTHER"].." -- ", "") end
	if strfind(reason_header, "%%") then
		reason_header = gsub(reason_header, "%%", "%%%%")
	end
	local confirm_string = L["CONFIRMDELETEENTRY1"]..":\n\n"..reason_header.."\n\n|CFFFF0000"..L["WARNING"].."|r: "..L["DELETEENTRYREFUNDCONF"];

	StaticPopupDialogs["CONFIRM_DELETE"] = {

		text = confirm_string,
		button1 = L["YES"],
		button2 = L["NO"],
		OnAccept = function()

		-- add new entry and add "delted_by" field to entry being "deleted". make new entry exact opposite of "deleted" entry
		-- new entry gets "deletes", old entry gets "deleted_by", deletes = deleted_by index. and vice versa
			local search = CommDKP:Table_Search(CommDKP:GetTable(CommDKP_DKPHistory, true), index, "index")

			if search then
				local players = {strsplit(",", strsub(CommDKP:GetTable(CommDKP_DKPHistory, true)[search[1][1]].players, 1, -2))} 	-- cuts off last "," from string to avoid creating an empty value
				local dkp, mod;
				local dkpString = "";
				local curOfficer = CommDKP:GetPlayerName()
				if not curOfficer then return end  -- AD-10.4
				local curTime = time()
				local newIndex = curOfficer.."-"..curTime

				if strfind(CommDKP:GetTable(CommDKP_DKPHistory, true)[search[1][1]].dkp, "%-%d*%.?%d+%%") then 		-- determines if it's a mass decay
					dkp = {strsplit(",", CommDKP:GetTable(CommDKP_DKPHistory, true)[search[1][1]].dkp)}
					mod = "perc";
				else
					dkp = CommDKP:GetTable(CommDKP_DKPHistory, true)[search[1][1]].dkp
					mod = "whole"
				end

				for i=1, #players do
					if mod == "perc" then
						local search = CommDKP:Table_Search(CommDKP:GetTable(CommDKP_DKPTable, true), players[i])

						if search then
							local inverted = tonumber(dkp[i]) * -1
							CommDKP:GetTable(CommDKP_DKPTable, true)[search[1][1]].dkp = CommDKP:GetTable(CommDKP_DKPTable, true)[search[1][1]].dkp + inverted
							dkpString = dkpString..inverted..",";

							if i == #players then
								dkpString = dkpString..dkp[#dkp]
							end
						end
					else
						local search = CommDKP:Table_Search(CommDKP:GetTable(CommDKP_DKPTable, true), players[i])

						if search then
							local inverted = tonumber(dkp) * -1

							CommDKP:GetTable(CommDKP_DKPTable, true)[search[1][1]].dkp = CommDKP:GetTable(CommDKP_DKPTable, true)[search[1][1]].dkp + inverted

							if tonumber(dkp) > 0 then
								CommDKP:GetTable(CommDKP_DKPTable, true)[search[1][1]].lifetime_gained = CommDKP:GetTable(CommDKP_DKPTable, true)[search[1][1]].lifetime_gained + inverted
							end

							dkpString = inverted;
						end
					end
				end

				CommDKP:GetTable(CommDKP_DKPHistory, true)[search[1][1]].deletedby = newIndex
				table.insert(CommDKP:GetTable(CommDKP_DKPHistory, true), 1, { players=CommDKP:GetTable(CommDKP_DKPHistory, true)[search[1][1]].players, dkp=dkpString, date=curTime, reason="Delete Entry", index=newIndex, deletes=index })
				CommDKP.Sync:SendData("CommDKPDelSync", CommDKP:GetTable(CommDKP_DKPHistory, true)[1])

				if CommDKP.ConfigTab6.history and CommDKP.ConfigTab6:IsShown() then
					CommDKP:DKPHistory_Update(true)
				end

				CommDKP:StatusVerify_Update()
				CommDKP:DKPTable_Update()
			end
		end,
		timeout = 0,
		whileDead = true,
		hideOnEscape = true,
		preferredIndex = 3,
	}
	StaticPopup_Show ("CONFIRM_DELETE")
end

local function RightClickDKPMenu(self, index, header)
	local search = CommDKP:Table_Search(CommDKP:GetTable(CommDKP_DKPHistory, true), index, "index")

	if search then
		local menu = {
		{ text = (header or ""):gsub(L["OTHER"].." -- ", ""), isTitle = true},
		{ text = L["DELETEDKPENTRY"], func = function()
			CommDKPDeleteDKPEntry(index, header)
		end },
		}
		LibDD:EasyMenu(menu, menuFrame, "cursor", 0 , 0, "MENU", 2);
	end
end

---------------------------------------
-- CDKP-012f2 (AD-19.2 (f) Part 2, UX §13.5, ruling R5): DKP Log as a cellular spreadsheet table.
-- Sticky 24 px column strip + NUM_ROWS recycled 18 px rows in a FauxScrollFrame (virtualized: no "Load More").
-- Columns (Σ 510): Date 84 L | Players 132 L | DKP 62 R | Reason 232 L (AD-22.3.1; the officer lives in the tooltip)
-- CommDKP.ConfigTab6.history = the recycled row array (a non-nil table once built): 6+ external call sites gate
-- their DKP-log refresh on it (comm.lua, ZeroSumBank.lua, RaidTimer.lua, AdjustDKP.lua, AutoAward.lua).
---------------------------------------
local NUM_ROWS = 19                                  -- R5: the §13.5.1 fallback count (534 x 403 Log card)
local ROW_H = core.TableRowHeight or 18
local TABLE_W = 510
local CELL_PAD = 6
local COLUMNS = {   -- AD-22.3.1 (CDKP-015b): Σ 510; By (84) removed -> Date +18, Players +12, Reason +54; Date text 72 px
	{ key = "date",    w = 84,  align = "LEFT",  label = function() return L["LOGCOL_DATE"] or "Date" end },
	{ key = "players", w = 132, align = "LEFT",  label = function() return L["LOGCOL_PLAYERS"] or "Players" end },
	{ key = "dkp",     w = 62,  align = "RIGHT", label = function() return L["DKP"] or "DKP" end },
	{ key = "reason",  w = 232, align = "LEFT",  label = function() return L["REASON"] or "Reason" end },
}
local GUIDE_COLOR = { 0.478, 0.373, 0.165, 0.35 }    -- trimQuiet @ 35 % (§13.5.1)

local activeFilter                                   -- the filter the current row set was built with
local infoCache = {}                                 -- entry -> described display fields (rebuilt per Update)

local function C(role)
	local p = core.Palette or (core.Palettes and core.Palettes.Forever) or {}
	return p[role] or { 1, 1, 1, 1 }
end

local function ClassHex(player)
	local s = CommDKP:Table_Search(CommDKP:GetTable(CommDKP_DKPTable, true), player, "player")
	if s then
		local c = CommDKP:GetCColors(CommDKP:GetTable(CommDKP_DKPTable, true)[s[1][1]].class)
		if c and c.hex then return c.hex end
	end
	return "ff444444"
end

-- AD-22.3.5 (CDKP-015b): reason filter predicate (excluded reasons never match an active filter)
local function ReasonMatch(raw, sel)
	if not sel then return true end
	local g, base, zone, boss = ClassifyReason(raw)
	if not g then return false end
	if sel.kind == "base"    then return base == sel.base end
	if sel.kind == "allboss" then return g == "BOSSKILL" end
	if sel.kind == "zone"    then return g == "BOSSKILL" and zone == sel.zone end
	if sel.kind == "boss"    then return g == "BOSSKILL" and zone == sel.zone and boss == sel.boss end
	return false
end

-- AD-19.2 (f) data parity: the shipped :281-297 predicates, verbatim, as one pure builder.
-- AD-22.3.5: each table.insert guard gains `and RM(<entry>)` (the reason filter, ANDed after the existing predicates).
local function BuildDKPRows(filter, sel)
	local hist = CommDKP:GetTable(CommDKP_DKPHistory, true)
	local byIndex
	if sel and filter == L["DELETEDENTRY"] then                         -- one pass, not a Table_Search per row
		byIndex = {}
		for _, e in ipairs(hist) do if e.index then byIndex[e.index] = e end end
	end
	local function RM(e)
		if not sel then return true end
		local src = e
		if byIndex then src = byIndex[e.deletes] end                    -- Deleted view: the original entry (may be nil)
		return src ~= nil and ReasonMatch(src.reason, sel)
	end
	local DKPHistory = {}
	if filter and filter ~= L["DELETEDENTRY"] then
		for i=1, #CommDKP:GetTable(CommDKP_DKPHistory, true) do
			if not CommDKP:GetTable(CommDKP_DKPHistory, true)[i].deletes and not CommDKP:GetTable(CommDKP_DKPHistory, true)[i].deletedby and CommDKP:GetTable(CommDKP_DKPHistory, true)[i].reason ~= "Migration Correction" and (strfind(CommDKP:GetTable(CommDKP_DKPHistory, true)[i].players, ","..filter..",") or strfind(CommDKP:GetTable(CommDKP_DKPHistory, true)[i].players, filter..",") == 1) and RM(CommDKP:GetTable(CommDKP_DKPHistory, true)[i]) then
				table.insert(DKPHistory, CommDKP:GetTable(CommDKP_DKPHistory, true)[i])
			end
		end
	elseif filter and filter == L["DELETEDENTRY"] then
		for i=1, #CommDKP:GetTable(CommDKP_DKPHistory, true) do
			if CommDKP:GetTable(CommDKP_DKPHistory, true)[i].deletes and RM(CommDKP:GetTable(CommDKP_DKPHistory, true)[i]) then
				table.insert(DKPHistory, CommDKP:GetTable(CommDKP_DKPHistory, true)[i])
			end
		end
	elseif not filter then
		for i=1, #CommDKP:GetTable(CommDKP_DKPHistory, true) do
			if not CommDKP:GetTable(CommDKP_DKPHistory, true)[i].deletes and not CommDKP:GetTable(CommDKP_DKPHistory, true)[i].hidden and not CommDKP:GetTable(CommDKP_DKPHistory, true)[i].deletedby and RM(CommDKP:GetTable(CommDKP_DKPHistory, true)[i]) then
				table.insert(DKPHistory, CommDKP:GetTable(CommDKP_DKPHistory, true)[i])
			end
		end
	end
	return DKPHistory
end

-- "yy/mm/dd HH:MM:SS" -> "mm/dd/yy", "HH:MM:SS", yy, mm, dd
local function SplitDate(thedate)
	local day = strtrim(strsub(thedate, 1, 8), " ")
	local date1, date2, date3 = strsplit("/", day)
	return (date2 or "").."/"..(date3 or "").."/"..(date1 or ""), strtrim(strsub(thedate, 10), " "), date1, date2, date3
end

-- Shipped :359-462 field derivation: the Deleted view displays the deleted (original) entry's players / reason /
-- dkp / date; info.officer (tooltip / header) is the row entry's own officer (`strsplit("-", index)`, else "Unknown").
local function Describe(entry)
	local info = infoCache[entry]
	if info then return info end
	info = {}
	local src = entry
	if activeFilter == L["DELETEDENTRY"] and entry.deletes then
		local search = CommDKP:Table_Search(CommDKP:GetTable(CommDKP_DKPHistory, true), entry.deletes, "index")
		if search then
			local orig = CommDKP:GetTable(CommDKP_DKPHistory, true)[search[1][1]]
			src = orig
			if orig.deletedby then
				info.delOfficer = strsplit("-", orig.deletedby)
				info.delDate = CommDKP:FormatTime(entry.date) or ""
			end
		end
	end

	local players = tostring(src.players or "")
	local reason = tostring(src.reason or "")
	if strfind(reason, L["OTHER"].." - ") == 1 then
		reason = reason:gsub(L["OTHER"].." -- ", "")
	end
	local dkp = tostring(src.dkp or "")
	info.reason = reason
	info.date = CommDKP:FormatTime(src.date) or ""
	info.officer = entry.index and strsplit("-", entry.index) or "Unknown"

	-- Recipients (shipped :395-398: the trailing "," leaves an empty last piece)
	local list = { strsplit(",", players) }
	if list[1] ~= nil and #list > 1 then tremove(list, #list) end
	info.players = list

	-- DKP cell (shipped :447-462; the duplicated-string bug at :458 is dropped)
	info.decayList = nil
	if not strfind(dkp, "-") then
		info.dkp, info.gain = "+"..dkp, true
	else
		local decay = { strsplit(",", dkp) }
		if strfind(dkp, "%-%d*%.?%d+%%") then info.decayList = decay end    -- mass decay: per-player amounts + the %
		if activeFilter and activeFilter ~= L["DELETEDENTRY"] and strfind(reason, L["WEEKLYDECAY"]) then
			-- get substring till player name and split to get correct player index for decay list
			local playerIndex = { strsplit(",", string.sub(players, 1, strfind(players, activeFilter..","))) }
			info.dkp = tostring(decay[#playerIndex] or decay[#decay])
		elseif strfind(reason, L["WEEKLYDECAY"]) or strfind(reason, "Migration Correction") then
			info.dkp = tostring(decay[#decay])
		else
			info.dkp = dkp
		end
		info.gain = false
	end
	infoCache[entry] = info
	return info
end

local function DKPColored(info)
	return (info.gain and "|cff00ff00" or "|cffff0000")..info.dkp.."|r"
end

-- The entry's one-line description, in the shipped `.d` format (right-click menu title + delete confirmation).
local function EntryHeader(entry)
	local info = Describe(entry)
	local _, clock = SplitDate(info.date)
	return DKPColored(info).." "..L["DKP"].." - |cff616ccf"..info.reason.."|r |cff555555("..clock..")|r by |c"..ClassHex(info.officer)..info.officer.."|r"
end

local function PlayerName(name)
	return "|c"..ClassHex(name)..name.."|r"
end

---------------------------------------
-- Tooltip (UX §13.5.3): "Reason  DKP" heading; "N players, by Officer  MM/DD/YY HH:MM"; every recipient in two
-- class-coloured columns (decay: each name with its own amount); the shipped "Deleted by" block is kept.
---------------------------------------
local function Row_OnEnter(self)
	local entry = self.entry
	if not entry then return end
	local info = Describe(entry)
	local tip = GameTooltip
	tip:SetOwner(self, "ANCHOR_RIGHT", 0, 0)
	local g = C("gold")
	tip:SetText(info.reason.."  "..DKPColored(info), g[1], g[2], g[3], 1, true)
	local day, clock = SplitDate(info.date)
	local n = #info.players
	local m = C("textMuted")
	tip:AddLine(string.format(L["LOGTIP_PLAYERSBY"] or "%d player(s), by %s", n, PlayerName(info.officer)).."  "..day.." "..strsub(clock, 1, 5), m[1], m[2], m[3])
	tip:AddLine(" ")
	local cells = {}
	for k, name in ipairs(info.players) do
		local s = PlayerName(name)
		if info.decayList and info.decayList[k] then s = s.." |cffff0000"..info.decayList[k].."|r" end
		cells[#cells + 1] = s
	end
	for k = 1, #cells, 2 do
		tip:AddDoubleLine(cells[k], cells[k + 1] or " ")
	end
	if info.delOfficer then
		local d, t, y, mo, dd = SplitDate(info.delDate)
		tip:AddLine(" ")
		tip:AddLine(L["DELETEDBY"], 0.25, 0.75, 0.90, 1, true)
		tip:AddDoubleLine(PlayerName(info.delOfficer), (mo or "").."/"..(dd or "").."/"..(y or "").." @ "..t, 1,0,0,1,1,1)
	end
	tip:Show()
end

local function Row_OnLeave()
	GameTooltip:Hide()
end

-- Shipped :413-419: right-click officer delete menu, never in the Deleted view.
local function Row_OnMouseDown(self, button)
	local entry = self.entry
	if not entry then return end
	if button == "RightButton" and activeFilter ~= L["DELETEDENTRY"] then
		if core.IsOfficer == true then
			RightClickDKPMenu(self, entry.index, EntryHeader(entry))
		end
	end
end

---------------------------------------
-- Table frame (built lazily on the first DKPHistory_Update; AD-19.2 (f) shared table frame)
---------------------------------------
local Refresh

local function BuildDKPLogTable(tab)
	if tab.LogTable then return tab.LogTable end
	local body = tab.LogCard and tab.LogCard.Body
	if not body then return nil end
	if tab.LogScroll then tab.LogScroll:Hide() end       -- the pre-012f feed region retires

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

	local sf = CreateFrame("ScrollFrame", "CommDKPDKPLogScroll", body, "FauxScrollFrameTemplate")
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
		for _, col in ipairs(COLUMNS) do
			local fs = W.CreateText(row, "body", nil, col.align)
			fs:SetWordWrap(false)
			fs:SetHeight(ROW_H)
			fs:SetPoint("LEFT", row, "LEFT", cx + CELL_PAD, 0)
			fs:SetWidth(col.w - 2 * CELL_PAD)
			row.cells[col.key] = fs
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
	tab.history = rows                                   -- AD-19.2 (f) invariant: a non-nil table (the row array)
	tab.rows = tab.rows or {}
	return sf
end

local function PaintRow(row, entry, prev)
	row.entry = entry
	local cells = row.cells
	local info = Describe(entry)
	local deletedView = activeFilter == L["DELETEDENTRY"]
	local day = SplitDate(info.date)

	-- Date
	cells.date:SetText(day)
	cells.date:SetTextColor(unpack(C(deletedView and "textDisabled" or "textMuted")))

	-- Players: one recipient -> class-coloured name; several -> gold "N Players" (full list in the tooltip)
	local n = #info.players
	if n == 1 then
		cells.players:SetText(deletedView and info.players[1] or PlayerName(info.players[1]))
		cells.players:SetTextColor(unpack(C(deletedView and "textDisabled" or "text")))
	else
		cells.players:SetText(string.format(L["LOGCOL_NPLAYERS"] or "%d Players", n))
		cells.players:SetTextColor(unpack(C(deletedView and "textDisabled" or "gold")))
	end

	-- DKP: green +X / red -X / red decay %
	if deletedView then
		cells.dkp:SetText(info.dkp)
		cells.dkp:SetTextColor(unpack(C("textDisabled")))
	else
		cells.dkp:SetText(DKPColored(info))
		cells.dkp:SetTextColor(unpack(C("text")))
	end

	-- Reason
	cells.reason:SetText(W.SafeText(info.reason))
	cells.reason:SetTextColor(unpack(C(deletedView and "textDisabled" or "text")))

	row.dayRule:SetShown(prev ~= nil and SplitDate(Describe(prev).date) ~= day)
	row:Show()
end

Refresh = function()
	local tab = CommDKP.ConfigTab6
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

function CommDKP:DKPHistory_Reset()
	local tab = CommDKP.ConfigTab6
	if not tab then return end
	for _, row in ipairs(tab.LogRows or {}) do row.entry = nil; row:Hide() end
	ResetOffset(tab.LogTable)
end

function CommDKP:DKPHistory_Update(reset)
	CommDKP:SortDKPHistoryTable()

	if not CommDKP.UIConfig:IsShown() then 			-- prevents history update from firing if the DKP window is not opened (eliminate lag). Update run when opened
		return;
	end
	local tab = CommDKP.ConfigTab6
	if not tab then return end

	if reset then
		CommDKP:DKPHistory_Reset()
	end

	activeFilter = filter
	infoCache = {}
	tab.rows = BuildDKPRows(filter, reasonSel)                -- AD-22.3.5: reasonSel is file-local, persists across refreshes

	-- R5: keep the officer right-click instruction in the Filter card caption.
	if tab.inst then
		LayoutFilterCaption(tab)                             -- AD-22.3.2
		tab.inst:SetText(core.IsOfficer == true and L["LOOTHISTINST3"] or "")
		tab.inst:Show()
	end

	if not BuildDKPLogTable(tab) then return end
	Refresh()
end
