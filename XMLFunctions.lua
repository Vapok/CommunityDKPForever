local _, core = ...;

-- UX §11.2.3: CommunityDKPUIPanelButtonNoTooltipTemplate / CommunityDKPButtonTemplate are restyled as flat bronze
-- buttons by CommDKP:StyleButton (Core.lua). The XML script bindings are kept, but they no longer re-texture the
-- Left/Middle/Right pieces: once styled, StyleButton's own hooks repaint every state, so these are delegates/no-ops.
-- The legacy textures below are only used if StyleButton is unavailable (no-Lua fallback).

local LEGACY_UP       = "Interface\\AddOns\\CommunityDKPForever\\Media\\Textures\\CommunityDKP-Button-Up"
local LEGACY_DOWN     = "Interface\\AddOns\\CommunityDKPForever\\Media\\Textures\\CommunityDKP-Button-Down"
local LEGACY_DISABLED = "Interface\\Buttons\\UI-Panel-Button-Disabled"

local function Style(self)
	local CommDKP = core and core.CommDKP
	if CommDKP and CommDKP.StyleButton then
		CommDKP:StyleButton(self)
		return true
	end
	return false
end

local function LegacyTexture(self, path)
	if self.Left then self.Left:SetTexture(path) end
	if self.Middle then self.Middle:SetTexture(path) end
	if self.Right then self.Right:SetTexture(path) end
end

function CommunityDKPButton_OnLoad(self)
	if Style(self) then return end
	if not self:IsEnabled() then LegacyTexture(self, LEGACY_DISABLED) end
end

function CommunityDKPButton_OnMouseDown(self)
	if self.cdkpStyled or Style(self) then return end
	if self:IsEnabled() then LegacyTexture(self, LEGACY_DOWN) end
end

function CommunityDKPButton_OnMouseUp(self)
	if self.cdkpStyled or Style(self) then return end
	if self:IsEnabled() then LegacyTexture(self, LEGACY_UP) end
end

function CommunityDKPButton_OnShow(self)
	if self.cdkpStyled or Style(self) then return end
	if self:IsEnabled() then LegacyTexture(self, LEGACY_UP) end
end

function CommunityDKPButton_OnDisable(self)
	if self.cdkpStyled or Style(self) then return end
	LegacyTexture(self, LEGACY_DISABLED)
end

function CommunityDKPButton_OnEnable(self)
	if self.cdkpStyled or Style(self) then return end
	LegacyTexture(self, LEGACY_UP)
end
