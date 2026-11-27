local _, core = ...;
local _G = _G;
local CommDKP = core.CommDKP;
local L = core.L;
local W = CommDKP.Widgets

-- UX §12.4.4 Misc pane: 4 cards (456 wide, the pane's right 10 px lane holds the rail), checkboxes in 2 columns.
local CARD_W, COL2_X = 456, 233
local function PlaceCheck(cb, card, col, row)
	cb:SetPoint("TOPLEFT", card.Body, "TOPLEFT", col == 2 and COL2_X or W.PAD, -12 - (row - 1) * 24)
end

function CommDKP:DKPModes_Misc()
    local f = core.ModesWindow.DKPModesMisc;

    f.AutoAwardContainer = W.CreateCard(f, L["CARDAUTOAWARD"], CARD_W, 64)
    f.AutoAwardContainer:SetPoint("TOPLEFT", f, "TOPLEFT", 0, 0)

	    -- AutoAward DKP Checkbox
		f.AutoAwardContainer.AutoAward = W.CreateCheckbox(f.AutoAwardContainer.Body, nil, L["AUTOAWARD"]);
		f.AutoAwardContainer.AutoAward:SetChecked(core.DB.modes.AutoAward)
		PlaceCheck(f.AutoAwardContainer.AutoAward, f.AutoAwardContainer, 1, 1)
		f.AutoAwardContainer.AutoAward:SetScript("OnClick", function(self)
			core.DB.modes.AutoAward = self:GetChecked();
			if self:GetChecked() == false then
				f.AutoAwardContainer.IncStandby:SetChecked(false)
				core.DB.DKPBonus.AutoIncStandby = false;
			end
			PlaySound(808);
		end)
		f.AutoAwardContainer.AutoAward:SetScript("OnEnter", function(self)
			GameTooltip:SetOwner(self, "ANCHOR_RIGHT");
			GameTooltip:SetText(L["AUTOAWARD"], 0.25, 0.75, 0.90, 1, true);
			GameTooltip:AddLine(L["AUTOAWARDTTDESC"], 1.0, 1.0, 1.0, true);
			GameTooltip:Show();
		end)
		f.AutoAwardContainer.AutoAward:SetScript("OnLeave", function(self)
			GameTooltip:Hide()
		end)

		-- Include Standby Checkbox
		f.AutoAwardContainer.IncStandby = W.CreateCheckbox(f.AutoAwardContainer.Body, nil, L["INCLUDESTANDBY"]);
		f.AutoAwardContainer.IncStandby:SetChecked(core.DB.DKPBonus.AutoIncStandby)
		PlaceCheck(f.AutoAwardContainer.IncStandby, f.AutoAwardContainer, 2, 1)
		f.AutoAwardContainer.IncStandby:SetScript("OnClick", function(self)
			core.DB.DKPBonus.AutoIncStandby = self:GetChecked();
			if self:GetChecked() == true then
				f.AutoAwardContainer.AutoAward:SetChecked(true)
				core.DB.modes.AutoAward = true;
			end
			PlaySound(808);
		end)
		f.AutoAwardContainer.IncStandby:SetScript("OnEnter", function(self)
			GameTooltip:SetOwner(self, "ANCHOR_RIGHT");
			GameTooltip:SetText(L["INCLUDESTANDBY"], 0.25, 0.75, 0.90, 1, true);
			GameTooltip:AddLine(L["INCLUDESBYTTDESC"], 1.0, 1.0, 1.0, true);
			GameTooltip:AddLine(L["INCLUDESBYTTWARN"], 1.0, 0, 0, true);
			GameTooltip:Show();
		end)
		f.AutoAwardContainer.IncStandby:SetScript("OnLeave", function(self)
			GameTooltip:Hide()
		end)

	-- Announce Highest Bidder Container
	f.AnnounceBidContainer = W.CreateCard(f, L["CARDANNOUNCE"], CARD_W, 88)
    f.AnnounceBidContainer:SetPoint("TOPLEFT", f.AutoAwardContainer, "BOTTOMLEFT", 0, -8)

		-- Announce Highest Bid
		f.AnnounceBidContainer.AnnounceBid = W.CreateCheckbox(f.AnnounceBidContainer.Body, nil, L["ANNOUNCEBID"]);
		f.AnnounceBidContainer.AnnounceBid:SetChecked(core.DB.modes.AnnounceBid)
		PlaceCheck(f.AnnounceBidContainer.AnnounceBid, f.AnnounceBidContainer, 1, 1)
		f.AnnounceBidContainer.AnnounceBid:SetScript("OnClick", function(self)
			core.DB.modes.AnnounceBid = self:GetChecked();
			if self:GetChecked() == false then
				f.AnnounceBidContainer.AnnounceBidName:SetChecked(false)
				core.DB.modes.AnnounceBidName = false;
			end
			PlaySound(808);
		end)
		f.AnnounceBidContainer.AnnounceBid:SetScript("OnEnter", function(self)
			GameTooltip:SetOwner(self, "ANCHOR_RIGHT");
			GameTooltip:SetText(L["ANNOUNCEBID"], 0.25, 0.75, 0.90, 1, true);
			GameTooltip:AddLine(L["ANNOUNCEBIDTTDESC"], 1.0, 1.0, 1.0, true);
			GameTooltip:Show();
		end)
		f.AnnounceBidContainer.AnnounceBid:SetScript("OnLeave", function(self)
			GameTooltip:Hide()
		end)

		-- Include Name Announce Highest Bid
		f.AnnounceBidContainer.AnnounceBidName = W.CreateCheckbox(f.AnnounceBidContainer.Body, nil, L["INCLUDENAME"]);
		f.AnnounceBidContainer.AnnounceBidName:SetChecked(core.DB.modes.AnnounceBidName)
		PlaceCheck(f.AnnounceBidContainer.AnnounceBidName, f.AnnounceBidContainer, 2, 1)
		f.AnnounceBidContainer.AnnounceBidName:SetScript("OnClick", function(self)
			core.DB.modes.AnnounceBidName = self:GetChecked();
			if self:GetChecked() == true then
				f.AnnounceBidContainer.AnnounceBid:SetChecked(true)
				core.DB.modes.AnnounceBid = true;
			end
			PlaySound(808);
		end)
		f.AnnounceBidContainer.AnnounceBidName:SetScript("OnEnter", function(self)
			GameTooltip:SetOwner(self, "ANCHOR_RIGHT");
			GameTooltip:SetText(L["INCLUDENAME"], 0.25, 0.75, 0.90, 1, true);
			GameTooltip:AddLine(L["INCLUDENAMETTDESC"], 1.0, 1.0, 1.0, true);
			GameTooltip:Show();
		end)
		f.AnnounceBidContainer.AnnounceBidName:SetScript("OnLeave", function(self)
			GameTooltip:Hide()
		end)

		-- Use Raid Warning for Announcements
		f.AnnounceBidContainer.AnnounceRaidWarning = W.CreateCheckbox(f.AnnounceBidContainer.Body, nil, L["ANNOUNCEINRAIDWARNING"]);  -- Translate/Localize
		f.AnnounceBidContainer.AnnounceRaidWarning:SetChecked(core.DB.modes.AnnounceRaidWarning)
		PlaceCheck(f.AnnounceBidContainer.AnnounceRaidWarning, f.AnnounceBidContainer, 1, 2)
		f.AnnounceBidContainer.AnnounceRaidWarning:SetScript("OnClick", function(self)
			core.DB.modes.AnnounceRaidWarning = self:GetChecked();
			PlaySound(808);
		end)
		f.AnnounceBidContainer.AnnounceRaidWarning:SetScript("OnEnter", function(self)
			GameTooltip:SetOwner(self, "ANCHOR_RIGHT");
			GameTooltip:SetText(L["ANNOUNCEINRAIDWARNING"], 0.25, 0.75, 0.90, 1, true);
			GameTooltip:AddLine(L["ANNOUNCEINRAIDWARNINGDESC"], 1.0, 1.0, 1.0, true);
			GameTooltip:Show();
		end)
		f.AnnounceBidContainer.AnnounceRaidWarning:SetScript("OnLeave", function(self)
			GameTooltip:Hide()
		end)

		-- Decline lower bids
		f.AnnounceBidContainer.DeclineLowerBids = W.CreateCheckbox(f.AnnounceBidContainer.Body, nil, L["DECLINELOWBIDS"]);
		f.AnnounceBidContainer.DeclineLowerBids:SetChecked(core.DB.modes.DeclineLowerBids)
		PlaceCheck(f.AnnounceBidContainer.DeclineLowerBids, f.AnnounceBidContainer, 2, 2)
		f.AnnounceBidContainer.DeclineLowerBids:SetScript("OnClick", function(self)
			core.DB.modes.DeclineLowerBids = self:GetChecked();
		end)
		f.AnnounceBidContainer.DeclineLowerBids:SetScript("OnEnter", function(self)
			GameTooltip:SetOwner(self, "ANCHOR_RIGHT");
			GameTooltip:SetText(L["DECLINELOWBIDS"], 0.25, 0.75, 0.90, 1, true);
			GameTooltip:AddLine(L["DECLINELOWBIDSTTDESC"], 1.0, 1.0, 1.0, true);
			GameTooltip:Show();
		end)
		f.AnnounceBidContainer.DeclineLowerBids:SetScript("OnLeave", function(self)
			GameTooltip:Hide()
		end)

	--Misc Options Container
	f.MiscContainer = W.CreateCard(f, L["CARDMISC"], CARD_W, 88)
    f.MiscContainer:SetPoint("TOPLEFT", f.AnnounceBidContainer, "BOTTOMLEFT", 0, -8)

		-- Standby On Boss Kill Checkbox
		f.MiscContainer.Standby = W.CreateCheckbox(f.MiscContainer.Body, nil, L["STANDBYOPTIN"]);
		f.MiscContainer.Standby:SetChecked(core.DB.modes.StandbyOptIn)
		PlaceCheck(f.MiscContainer.Standby, f.MiscContainer, 1, 1)
		f.MiscContainer.Standby:SetScript("OnClick", function(self)
			core.DB.modes.StandbyOptIn = self:GetChecked();
			PlaySound(808);
		end)
		f.MiscContainer.Standby:SetScript("OnEnter", function(self)
			GameTooltip:SetOwner(self, "ANCHOR_RIGHT");
			GameTooltip:SetText(L["STANDBYOPTIN"], 0.25, 0.75, 0.90, 1, true);
			GameTooltip:AddLine(L["STANDBYOPTINTTDESC"], 1.0, 1.0, 1.0, true);
			GameTooltip:AddLine(L["STANDBYOPTINTTWARN"], 1.0, 0, 0, true);
			GameTooltip:Show();
		end)
		f.MiscContainer.Standby:SetScript("OnLeave", function(self)
			GameTooltip:Hide()
		end)

		-- Announce Award to Guild
		f.MiscContainer.AnnounceAward = W.CreateCheckbox(f.MiscContainer.Body, nil, L["ANNOUNCEAWARD"]);
		f.MiscContainer.AnnounceAward:SetChecked(core.DB.modes.AnnounceAward)
		PlaceCheck(f.MiscContainer.AnnounceAward, f.MiscContainer, 2, 1)
		f.MiscContainer.AnnounceAward:SetScript("OnClick", function(self)
			core.DB.modes.AnnounceAward = self:GetChecked();
			PlaySound(808);
		end)
		f.MiscContainer.AnnounceAward:SetScript("OnEnter", function(self)
			GameTooltip:SetOwner(self, "ANCHOR_RIGHT");
			GameTooltip:SetText(L["ANNOUNCEAWARD"], 0.25, 0.75, 0.90, 1, true);
			GameTooltip:AddLine(L["ANNOUNCEAWARDTTDESC"], 1.0, 1.0, 1.0, true);
			GameTooltip:Show();
		end)
		f.MiscContainer.AnnounceAward:SetScript("OnLeave", function(self)
			GameTooltip:Hide()
		end)

		-- Broadcast Bid Table to Raid
		f.MiscContainer.BroadcastBids = W.CreateCheckbox(f.MiscContainer.Body, nil, L["BROADCASTBIDS"]);
		f.MiscContainer.BroadcastBids:SetChecked(core.DB.modes.BroadcastBids)
		PlaceCheck(f.MiscContainer.BroadcastBids, f.MiscContainer, 1, 2)
		f.MiscContainer.BroadcastBids:SetScript("OnClick", function(self)
			core.DB.modes.BroadcastBids = self:GetChecked();
			PlaySound(808);
		end)
		f.MiscContainer.BroadcastBids:SetScript("OnEnter", function(self)
			GameTooltip:SetOwner(self, "ANCHOR_RIGHT");
			GameTooltip:SetText(L["BROADCASTBIDS"], 0.25, 0.75, 0.90, 1, true);
			GameTooltip:AddLine(L["BROADCASTBIDSTTDESC"], 1.0, 1.0, 1.0, true);
			GameTooltip:Show();
		end)
		f.MiscContainer.BroadcastBids:SetScript("OnLeave", function(self)
			GameTooltip:Hide()
		end)

		-- Log Bids/Rolls
		f.MiscContainer.StoreBids = W.CreateCheckbox(f.MiscContainer.Body, nil, L["LOGBIDS"]);
		f.MiscContainer.StoreBids:SetChecked(core.DB.modes.StoreBids)
		PlaceCheck(f.MiscContainer.StoreBids, f.MiscContainer, 2, 2)
		f.MiscContainer.StoreBids:SetScript("OnClick", function(self)
			core.DB.modes.StoreBids = self:GetChecked();
			PlaySound(808);
		end)
		f.MiscContainer.StoreBids:SetScript("OnEnter", function(self)
			GameTooltip:SetOwner(self, "ANCHOR_RIGHT");
			GameTooltip:SetText(L["LOGBIDS"], 0.25, 0.75, 0.90, 1, true);
			GameTooltip:AddLine(L["LOGBIDSTTDESC"], 1.0, 1.0, 1.0, true);
			GameTooltip:Show();
		end)
		f.MiscContainer.StoreBids:SetScript("OnLeave", function(self)
			GameTooltip:Hide()
		end)

	--DKP Award Options Container
	f.DKPAwardContainer = W.CreateCard(f, L["CARDAWARDELIG"], CARD_W, 64)
    f.DKPAwardContainer:SetPoint("TOPLEFT", f.MiscContainer, "BOTTOMLEFT", 0, -8)

    	-- Online Only Checkbox
	    if core.DB.modes.OnlineOnly == nil then core.DB.modes.OnlineOnly = false end
		f.DKPAwardContainer.OnlineOnly = W.CreateCheckbox(f.DKPAwardContainer.Body, nil, L["ONLINEONLY"]);
		f.DKPAwardContainer.OnlineOnly:SetChecked(core.DB.modes.OnlineOnly)
		PlaceCheck(f.DKPAwardContainer.OnlineOnly, f.DKPAwardContainer, 1, 1)
		f.DKPAwardContainer.OnlineOnly:SetScript("OnClick", function(self)
			core.DB.modes.OnlineOnly = self:GetChecked();
			PlaySound(808);
		end)
		f.DKPAwardContainer.OnlineOnly:SetScript("OnEnter", function(self)
			GameTooltip:SetOwner(self, "ANCHOR_RIGHT");
			GameTooltip:SetText(L["ONLINEONLY"], 0.25, 0.75, 0.90, 1, true);
			GameTooltip:AddLine(L["ONLINEONLYTTDESC"], 1.0, 1.0, 1.0, true);
			GameTooltip:Show();
		end)
		f.DKPAwardContainer.OnlineOnly:SetScript("OnLeave", function(self)
			GameTooltip:Hide()
		end)

		-- Same Zone Only Checkbox
	    if core.DB.modes.SameZoneOnly == nil then core.DB.modes.SameZoneOnly = false end
		f.DKPAwardContainer.SameZoneOnly = W.CreateCheckbox(f.DKPAwardContainer.Body, nil, L["INZONEONLY"]);
		f.DKPAwardContainer.SameZoneOnly:SetChecked(core.DB.modes.SameZoneOnly)
		PlaceCheck(f.DKPAwardContainer.SameZoneOnly, f.DKPAwardContainer, 2, 1)
		f.DKPAwardContainer.SameZoneOnly:SetScript("OnClick", function(self)
			core.DB.modes.SameZoneOnly = self:GetChecked();
			PlaySound(808);
		end)
		f.DKPAwardContainer.SameZoneOnly:SetScript("OnEnter", function(self)
			GameTooltip:SetOwner(self, "ANCHOR_RIGHT");
			GameTooltip:SetText(L["INZONEONLY"], 0.25, 0.75, 0.90, 1, true);
			GameTooltip:AddLine(L["INZONEONLYTTDESC"], 1.0, 1.0, 1.0, true);
			GameTooltip:Show();
		end)
		f.DKPAwardContainer.SameZoneOnly:SetScript("OnLeave", function(self)
			GameTooltip:Hide()
		end)

	-- Pane height = the 4 cards + 3 gaps (64 + 88 + 88 + 64 + 24): no empty scroll range below the last card.
	f:SetHeight(328)

	-- AD-35.6 (BR-27.7, G-27.10): read-only refresh. SetChecked from stored values only: no OnClick, no core.DB write
	-- (the build-time OnlineOnly/SameZoneOnly nil -> false defaults are NOT repeated here; AC-27.11).
	function f.RefreshFromDB()
		local m, b = core.DB.modes or {}, core.DB.DKPBonus or {}
		local function chk(cb, v) if cb then cb:SetChecked(v == true) end end
		chk(f.AutoAwardContainer.AutoAward, m.AutoAward)
		chk(f.AutoAwardContainer.IncStandby, b.AutoIncStandby)
		chk(f.AnnounceBidContainer.AnnounceBid, m.AnnounceBid)
		chk(f.AnnounceBidContainer.AnnounceBidName, m.AnnounceBidName)
		chk(f.AnnounceBidContainer.AnnounceRaidWarning, m.AnnounceRaidWarning)
		chk(f.AnnounceBidContainer.DeclineLowerBids, m.DeclineLowerBids)
		chk(f.MiscContainer.Standby, m.StandbyOptIn)
		chk(f.MiscContainer.AnnounceAward, m.AnnounceAward)
		chk(f.MiscContainer.BroadcastBids, m.BroadcastBids)
		chk(f.MiscContainer.StoreBids, m.StoreBids)
		chk(f.DKPAwardContainer.OnlineOnly, m.OnlineOnly)
		chk(f.DKPAwardContainer.SameZoneOnly, m.SameZoneOnly)
	end
end
