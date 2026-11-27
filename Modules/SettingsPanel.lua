--[[
  SettingsPanel.lua  (CDKP-006 BR-1, AD-5.5)

  Registers a small *launcher* category under Options -> AddOns. The real options stay in ConfigTab4
  inside the main window (it is anchored throughout UIConfig; reparenting it would break layout/scale).
  The launcher only goes through CommDKP:Toggle(), and only touches UIConfig after Toggle() created it.
]]
local addonName, core = ...
local CommDKP, L = core.CommDKP, core.L

local OPTIONS_TAB = "CommDKPCommDKP.ConfigTabMenuTab4"   -- same global name CommDKP:Toggle() uses

-- Shared by the launcher button and the /dkp settings fallback (AD-6.4).
function CommDKP:OpenOptionsTab()
	if not core.Initialized then
		CommDKP:Print("CommunityDKP has not completed initialization.")
		return
	end
	if SettingsPanel and SettingsPanel:IsShown() and not InCombatLockdown() then HideUIPanel(SettingsPanel) end
	if not (CommDKP.UIConfig and CommDKP.UIConfig:IsShown()) then
		CommDKP:Toggle()
	end
	-- UX §11.1.3: forced select expands the workspace (ShowState stays in sync) and never toggles it closed.
	local tab = _G[OPTIONS_TAB]
	if tab and tab:IsShown() then CommDKP:SelectSideTab(4, true) end
end

local panel = CreateFrame("Frame")
panel.name = "CommunityDKP Forever"

local title = panel:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
title:SetPoint("TOPLEFT", 16, -16)
local tocTitle = C_AddOns.GetAddOnMetadata(addonName, "Title") or panel.name
local version = C_AddOns.GetAddOnMetadata(addonName, "Version")
title:SetText(version and (tocTitle .. "  |cffffffffv" .. version .. "|r") or tocTitle)

local desc = panel:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
desc:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -8)
desc:SetPoint("RIGHT", panel, "RIGHT", -16, 0)
desc:SetJustifyH("LEFT")
desc:SetText(L["SETTINGSPANELDESC"])

local open = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
open:SetPoint("TOPLEFT", desc, "BOTTOMLEFT", 0, -16)
open:SetSize(200, 24)
open:SetText(L["OPENDKPWINDOW"])
open:SetScript("OnClick", function() CommDKP:OpenOptionsTab() end)

if Settings and Settings.RegisterCanvasLayoutCategory then
	local category = Settings.RegisterCanvasLayoutCategory(panel, panel.name)
	Settings.RegisterAddOnCategory(category)
	core.SettingsCategoryID = category:GetID()
end
