local _, core = ...;
local _G = _G;
local CommDKP = core.CommDKP;
local L = core.L;
local W = CommDKP.Widgets


local function CreateRow(parent, id) -- Create 3 buttons for each row in the list

	local f;

	f = CreateFrame("Button", "$parentLine"..id, parent, "BackdropTemplate")

	f.PriceInfo = {}
	f:SetSize(core.TableWidth, core.TableRowHeight)
	W.StyleRow(f, id)                      -- §12.2.10: stripe on odd rows + bg3 hover (replaces ListBox-Highlight / talent-blue-glow)
	--f:SetScript("OnClick", DKPTable_OnClick)
	for i=1, 3 do
		f.PriceInfo[i] = W.CreateText(f, "body", nil, "LEFT");
		if (i==1) then
			f.PriceInfo[i].rowCounter = W.CreateText(f, "caption", nil, "LEFT", "textMuted");
			f.PriceInfo[i].rowCounter:SetPoint("LEFT", f, "LEFT", 3, 0);
			f.PriceInfo[i]:SetSize((370)-1, core.TableRowHeight);
			if f.PriceInfo[i].SetWordWrap then f.PriceInfo[i]:SetWordWrap(false) end
		end
		if (i==2) then
			f.PriceInfo[i]:SetJustifyH("CENTER")
			f.PriceInfo[i]:SetSize((60)-1, core.TableRowHeight);
		end
		if (i==3) then
			f.PriceInfo[i]:SetJustifyH("CENTER")
			f.PriceInfo[i]:SetSize((70)-1, core.TableRowHeight);
		end
	end
	f.PriceInfo[1]:SetPoint("LEFT", 30, 0);
	f.PriceInfo[2]:SetPoint("CENTER", 155, 0)
	f.PriceInfo[3]:SetPoint("RIGHT", 15, 0)

	--f:SetScript("OnMouseDown", function(self, button)
	--	if button == "RightButton" then
	--		RightClickMenu(self)
	--	end
	--end)

	return f
end

-- AD-25.2.2 (CDKP-016b): the one Pricing-list sort. Column/direction from core.PriceSort (nil = login default A->Z);
-- never reads core.currentSort (Roster-owned, F1). Total order (F7): primary key -> item A->Z (nil last) -> itemID.
function CommDKP:SortPriceTable()
	if type(core.PriceTable) ~= "table" then core.PriceTable = {} end
	local s = core.PriceSort
	local id, ascend = "item", true
	if type(s) == "table" and (s.id == "item" or s.id == "minbid" or s.id == "disenchants") then
		id, ascend = s.id, (s.ascend and true or false)
	end
	table.sort(core.PriceTable, function(a, b)
		if id ~= "item" then
			local va, vb = tonumber(a[id]) or 0, tonumber(b[id]) or 0
			if va ~= vb then
				if ascend then return va > vb else return va < vb end	-- legacy PriceListSort direction
			end
		end
		local na = type(a.item) == "string" and a.item or nil
		local nb = type(b.item) == "string" and b.item or nil
		if na ~= nb then
			if na == nil then return false end		-- nil item last (init.lua:872-882), both directions
			if nb == nil then return true end
			if id == "item" and not ascend then return na > nb end
			return na < nb
		end
		return tostring(a.itemID or "") < tostring(b.itemID or "")
	end)
end

-- AD-25.2.4 (BR-16.11): redraw core.PriceTable at the FauxScrollFrame's current row offset, clamped to the new length,
-- and leave template bar + AD-16.2 rail on the same value (no jump on the next wheel). No-op until PriceTab_Create ran.
function CommDKP:PriceTable_Redraw(resetScroll)
	local pt = CommDKP.ConfigTab7 and CommDKP.ConfigTab7.PriceTable
	if not (pt and pt.Rows and pt.Rows[1]) then return end
	local h = core.TableRowHeight
	local rows = 0
	if not resetScroll then
		if FauxScrollFrame_GetOffset then rows = tonumber(FauxScrollFrame_GetOffset(pt)) or 0
		else rows = tonumber(pt.offset) or 0 end
	end
	local maxRows = #core.PriceTable - (core.PriceNumRows or 0)
	if maxRows < 0 then maxRows = 0 end
	rows = math.floor(rows)
	if rows > maxRows then rows = maxRows end
	if rows < 0 then rows = 0 end
	pt.offset = rows								-- the field FauxScrollFrame_GetOffset / OnVerticalScroll use
	CommDKP:PriceTable_Update(rows * h)				-- ends with FauxScrollFrame_Update -> new min/max -> rail sync
	local sb = pt.ScrollBar
	if sb and sb.GetValue and sb.SetValue and (sb:GetValue() or 0) ~= rows * h then
		sb:SetValue(rows * h)						-- in game: OnValueChanged -> OnVerticalScroll -> same rows (idempotent)
	end
	if pt.cdkpRailSync then pt.cdkpRailSync() end	-- F10 backstop
end

-- AD-25.2.3 (CDKP-016b, BR-16.9): rebuild core.PriceTable from the current team's MinBids, re-apply the
-- Pricing sort (no toggle), and redraw at the preserved (clamped) offset. Safe before the tab exists (BR-16.12).
-- resetScroll = true -> draw from the top (team switch, tab creation).
function CommDKP:RefreshPriceTable(resetScroll)
	core.PriceTable = CommDKP:FormatPriceTable()
	CommDKP:SortPriceTable()
	CommDKP:PriceTable_Redraw(resetScroll)
end

function CommDKP:ProcessDisenchant(loot)
	-- AD-23.2.1: lockdown guard first; a refused call changes nothing and leaves the window open (matches Award).
	if CommDKP.IsMessagingRestricted and CommDKP:IsMessagingRestricted() then
		CommDKP:Print(L["BIDDINGLOCKED"])
		return
	end

	-- AD-23.2.1 / AD-23.2.2: resolve through the shared parser (AD-12.3 / C-23.1); no local link regex.
	local itemName, itemLink, itemIcon, _, itemKey = CommDKP:ParseItemLink(loot)
	if not itemKey then return end
	itemLink = itemLink or loot
	itemName = itemName or itemLink

	-- AD-23.2.3: can only process through the bidding process
	if not (core.BiddingWindow and core.BiddingWindow:IsShown()) then return end
	local mode = core.DB.modes.mode
	local staticStyle = mode == "Static Item Values" or mode == "Roll Based Bidding"
		or (mode == "Zero Sum" and core.DB.modes.ZeroSumBidType == "Static")

	CommDKP:ResetBidToggle()	-- CDKP-006 (AD-5.3): resets Bidding.lua's own toggle; never rebinds OnClick
	core.BidInProgress = false
	CommDKP:BroadcastStopBidTimer()

	local minBids  = CommDKP:GetTable(CommDKP_MinBids, true)	-- read once; current team
	local existing = minBids[itemKey]
	local cost     = CommDKP_round(core.BiddingWindow.cost:GetNumber(), core.DB.modes.rounding)
	local updatedDisenchants = ((existing and tonumber(existing.disenchants)) or 0) + 1

	-- AD-23.2.4: D7 rule (computed values, then per-mode writes)
	local minbid, lastbid
	if staticStyle then
		minbid = cost	-- used ONLY for a new entry (legacy: pre-cut cost)
		CommDKP:SendChat("No bids for ".." "..itemLink.." for "..cost.." "..L["DKP"].." and will be disenchanted. This will be disenchant number "..updatedDisenchants, "RAID_WARNING")
		lastbid = cost
		if core.DB.defaults.DecreaseDisenchantValue then
			if cost == 0 then updatedDisenchants = 0 end	-- legacy reset
			--TODO: Make this less hardcodeded
			if updatedDisenchants >= 3 then
				lastbid = CommDKP_round(cost/2, core.DB.modes.rounding)
				if lastbid < 5 then lastbid = 5 end
			end
		end
	else
		minbid = CommDKP_round(core.BiddingWindow.minBid:GetNumber(), core.DB.modes.rounding)
		CommDKP:SendChat("No bids for ".." "..itemLink.." and will be disenchanted. This will be disenchant number "..updatedDisenchants, "RAID_WARNING")
	end

	if existing == nil then
		minBids[itemKey] = { item = itemName, minbid = minbid, link = itemLink, icon = itemIcon,
			disenchants = updatedDisenchants, lastbid = lastbid or 0, itemID = itemKey }
		core.BiddingWindow.CustomMinBid:SetShown(true)	-- legacy, new-entry only, all modes
		core.BiddingWindow.CustomMinBid:SetChecked(core.DB.defaults.CustomMinBid)
	else
		if staticStyle then existing.lastbid = lastbid else existing.minbid = minbid end
		existing.disenchants = updatedDisenchants
		existing.item   = existing.item   or itemName	-- D4 fix: never nil
		existing.link   = existing.link   or itemLink
		existing.icon   = existing.icon   or itemIcon
		existing.itemID = existing.itemID or itemKey
	end
	local entry = minBids[itemKey]

	-- AD-23.2.5: immediate local refresh (must precede Hide/ClearBidWindow), then broadcast
	CommDKP:RefreshPriceTable()	-- AD-25 (S3)
	CommDKP.Sync:SendData("CommDKPSetPrice", entry)
	core.BiddingWindow:Hide()
	CommDKP:ClearBidWindow()
end

function CommDKP:PriceTable_Update(scrollOffset)
	local pt = CommDKP.ConfigTab7 and CommDKP.ConfigTab7.PriceTable		-- AD-25.2.6 (BR-16.12 / E5)
	if not (pt and pt.Rows and pt.Rows[1]) or type(core.PriceTable) ~= "table" then return end
	scrollOffset = tonumber(scrollOffset) or 0

	local numOptions = #core.PriceTable
	local numOfRows = core.PriceNumRows;
	local index, row
	local offset = CommDKP_round(scrollOffset / core.TableRowHeight, 0)

	for i=1, numOfRows do     -- hide all rows before displaying them 1 by 1 as they show values
		row = CommDKP.ConfigTab7.PriceTable.Rows[i];
		row:Hide();
	end
	for i=1, numOfRows do     -- show rows if they have values
		row = CommDKP.ConfigTab7.PriceTable.Rows[i]
		index = tonumber(offset) + i;
		if core.PriceTable[index] then
			row:Show()
			row.index = index
			local curItemName = core.PriceTable[index].item;
			local curItemPrice = core.PriceTable[index].minbid;

			local curDisenchants = 0;

			if core.PriceTable[index]["disenchants"] ~= nil then
				curDisenchants = core.PriceTable[index].disenchants;
			else
				core.PriceTable[index]["disenchants"] = curDisenchants;
			end

			if core.PriceTable[index]["link"] ~= nil then
				curItemName = core.PriceTable[index].link;
				CommDKP.ConfigTab7.PriceTable.Rows[i]:SetScript("OnEnter", function(self)
					GameTooltip:SetOwner(self:GetParent(), "ANCHOR_BOTTOMRIGHT", 0, 500);
					GameTooltip:SetHyperlink(curItemName)
					GameTooltip:Show();
				end)
				CommDKP.ConfigTab7.PriceTable.Rows[i]:SetScript("OnLeave", function()
					GameTooltip:Hide()
				end)
			else
				CommDKP.ConfigTab7.PriceTable.Rows[i]:SetScript("OnEnter", nil)
				CommDKP.ConfigTab7.PriceTable.Rows[i]:SetScript("OnLeave", nil)
			end
			row.PriceInfo[1]:SetText(curItemName)
			row.PriceInfo[1].rowCounter:SetText(index)
		
			row.PriceInfo[2]:SetText(curItemPrice)
			
			row.PriceInfo[3]:SetText(curDisenchants)
		else
			row:Hide()
		end
	end

	if #core.PriceTable == 0 then  		-- Displays "No Entries Returned" if the result of filter combinations yields an empty table
		--CommDKP_RestoreFilterOptions()
		CommDKP.ConfigTab7.PriceTable.Rows[1].PriceInfo[1].rowCounter:SetText("")
		CommDKP.ConfigTab7.PriceTable.Rows[1].PriceInfo[1]:SetText("")
		CommDKP.ConfigTab7.PriceTable.Rows[1].PriceInfo[2]:SetText("|cffff6060"..L["NOENTRIESRETURNED"].."|r")
		CommDKP.ConfigTab7.PriceTable.Rows[1].PriceInfo[3]:SetText("")

		if CommDKP.ConfigTab7.PriceTable.Rows[1].PriceInfo[3].rollrange then CommDKP.ConfigTab7.PriceTable.Rows[1].PriceInfo[3].rollrange:SetText("") end
		CommDKP.ConfigTab7.PriceTable.Rows[1]:SetScript("OnEnter", nil)
		CommDKP.ConfigTab7.PriceTable.Rows[1]:SetScript("OnMouseDown", function()
			CommDKP_RestoreFilterOptions() 		-- restores filter selections to default on click.
		end)
		CommDKP.ConfigTab7.PriceTable.Rows[1]:SetScript("OnClick", function()
			CommDKP_RestoreFilterOptions() 		-- restores filter selections to default on click.
		end)
		CommDKP.ConfigTab7.PriceTable.Rows[1]:Show()
	--else
		--CommDKP.ConfigTab7.PriceTable.Rows[1]:SetScript("OnMouseDown", function(self, button)
		--	if button == "RightButton" then
		--		RightClickMenu(self)
		--	end
		--end)
		--CommDKP.ConfigTab7.PriceTable.Rows[1]:SetScript("OnClick", DKPTable_OnClick)
	end


	FauxScrollFrame_Update(CommDKP.ConfigTab7.PriceTable, numOptions, numOfRows, core.TableRowHeight, nil, nil, nil, nil, nil, nil, true) -- alwaysShowScrollBar= true to stop frame from hiding

end

function CommDKP:PriceListSort(id, reset)        -- passing a non-"Clear" reset keeps the direction (legacy)
	if not (id == "item" or id == "minbid" or id == "disenchants") then return end	-- AD-25 F1: never a Roster id
	local PriceSortButtons = core.PriceSortButtons
	local button = PriceSortButtons and PriceSortButtons[id]
	if not button then return end

	if reset and reset ~= "Clear" then
		button.Ascend = button.Ascend
	else
		button.Ascend = not button.Ascend
	end
	for k, v in pairs(PriceSortButtons) do
		if v ~= button then v.Ascend = nil end
	end
	core.PriceSort = { id = id, ascend = button.Ascend and true or false }	-- AD-25.2.1; NO core.currentSort write (C-25.2)
	CommDKP:SortPriceTable()
	CommDKP:PriceTable_Redraw(true)			-- C-25.4: top of list, bar/rail follow
end

function CommDKP:PriceTab_Create()

	local numOfRows = core.PriceNumRows;
	local PriceSortButtons = core.PriceSortButtons

	-- UX §12.3.7: one Loot Prices card (0,0) 548 x 482. Its title replaces the deleted large heading (Q7).
	local card = W.CreateCard(CommDKP.ConfigTab7, L["PRICETITLE"], 548, 482)
	card:SetPoint("TOPLEFT", CommDKP.ConfigTab7, "TOPLEFT", 0, 0)
	CommDKP.ConfigTab7.PriceCard = card
	local body = card.Body

	CommDKP.ConfigTab7.description = W.CreateCaption(body, L["PRICEDESC"], 2);
	CommDKP.ConfigTab7.description:SetPoint("TOPLEFT", body, "TOPLEFT", W.PAD, -8);
	CommDKP.ConfigTab7.description:SetWidth(548 - 6 - 2 * W.PAD);

	-- Faux table: 22 rows x 18 = 396 px under a 20 px column strip; rail at the table's right (AD-16.2 (f)).
	CommDKP.ConfigTab7.PriceTable = CreateFrame("ScrollFrame", "CommDKPPriceScrollFrame", body, "FauxScrollFrameTemplate")
		CommDKP.ConfigTab7.PriceTable:SetSize(core.TableWidth, core.TableRowHeight*numOfRows)
	CommDKP.ConfigTab7.PriceTable:SetPoint("TOPLEFT", body, "TOPLEFT", W.PAD, -56)


	CommDKP.ConfigTab7.PriceTable:SetClipsChildren(false);

	CommDKP.ConfigTab7.PriceTable.ScrollBar = FauxScrollFrame_GetChildFrames(CommDKP.ConfigTab7.PriceTable)
	CommDKP.ConfigTab7.PriceTable.Rows = {}

	for i=1, numOfRows do
		CommDKP.ConfigTab7.PriceTable.Rows[i] = CreateRow(CommDKP.ConfigTab7.PriceTable, i)
		if i==1 then
			CommDKP.ConfigTab7.PriceTable.Rows[i]:SetPoint("TOPLEFT", CommDKP.ConfigTab7.PriceTable, "TOPLEFT", 0, 0)
		else
			CommDKP.ConfigTab7.PriceTable.Rows[i]:SetPoint("TOPLEFT", CommDKP.ConfigTab7.PriceTable.Rows[i-1], "BOTTOMLEFT")
		end
	end

	CommDKP.ConfigTab7.PriceTable:SetScript("OnVerticalScroll", function(self, offset)
		FauxScrollFrame_OnVerticalScroll(self, offset, core.TableRowHeight, CommDKP:PriceTable_Update(offset))
	end)
	W.AttachFauxRail(CommDKP.ConfigTab7.PriceTable, body)

	-- §12.2.10 column strip (20 px, popup/table variant): sort buttons keep their click handlers.
	CommDKP.ConfigTab7.PriceTable.Headers = W.CreateColumnStrip(body, 20, "CommDKPPriceTableHeaders")

	CommDKP.ConfigTab7.PriceTable.Headers:SetSize(core.TableWidth, 20)
	CommDKP.ConfigTab7.PriceTable.Headers:SetPoint("BOTTOMLEFT", CommDKP.ConfigTab7.PriceTable, "TOPLEFT", 0, 0)
	CommDKP.ConfigTab7.PriceTable.Headers:Show()

	PriceSortButtons.item = CreateFrame("Button", "$ParentPriceSortButtonItem", CommDKP.ConfigTab7.PriceTable.Headers)
	PriceSortButtons.disenchants = CreateFrame("Button", "$ParentPriceSortButtonDisenchants", CommDKP.ConfigTab7.PriceTable.Headers)
	PriceSortButtons.minbid = CreateFrame("Button", "$ParentPriceSortButtonDkp", CommDKP.ConfigTab7.PriceTable.Headers)

	PriceSortButtons.minbid:SetPoint("BOTTOM", CommDKP.ConfigTab7.PriceTable.Headers, "BOTTOM", 130, 1)
	PriceSortButtons.item:SetPoint("RIGHT", PriceSortButtons.minbid, "LEFT", 0, 0)
	PriceSortButtons.disenchants:SetPoint("LEFT", PriceSortButtons.minbid, "RIGHT")

	for k, v in pairs(PriceSortButtons) do
		v.Id = k
		if k == "minbid" then
			v:SetSize((60), core.TableRowHeight)
		elseif k == "item" then
			v:SetSize((370), core.TableRowHeight)
		else
			v:SetSize((70), core.TableRowHeight)
		end
		v:SetScript("OnClick", function(self) CommDKP:PriceListSort(self.Id, "Clear") end)
	end

	-- §12.2.10: gold GameFontNormalSmall column labels.
	PriceSortButtons.item.t = W.CreateText(PriceSortButtons.item, "label", "Item Name", "LEFT")
	PriceSortButtons.item.t:SetPoint("LEFT", PriceSortButtons.item, "LEFT", 50, 0);

 	PriceSortButtons.disenchants.t = W.CreateText(PriceSortButtons.disenchants, "label", "Disenchants", "CENTER")
	PriceSortButtons.disenchants.t:SetPoint("CENTER", PriceSortButtons.disenchants, "CENTER", 0, 0);

	PriceSortButtons.minbid.t = W.CreateText(PriceSortButtons.minbid, "label", "DKP", "CENTER")
	PriceSortButtons.minbid.t:SetPoint("CENTER", PriceSortButtons.minbid, "CENTER", 0, 0);
	core.PriceSortButtons = PriceSortButtons;

	CommDKP:RefreshPriceTable(true)	-- AD-25 (S9)
end
