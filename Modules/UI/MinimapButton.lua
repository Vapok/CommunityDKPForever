-------------------------------------
-- CDKP-012e (AD-19.2 (e) / UX §13.6.1 / BR-12.9): moveable minimap button. No library (LibDBIcon recipe).
-- Angle (degrees) lives in core.DB.defaults.minimapPos (ruling R6, default 225). Local only: `defaults` is never
-- part of any Sync/broadcast payload (AC-12.9). Insecure Button, no secure templates: a click in combat follows
-- the same rules as /dkp (BR-12.9.4).
-------------------------------------
local _, core = ...
local CommDKP, L = core.CommDKP, core.L
local W = CommDKP.Widgets

local MINIMAP_DEFAULT_ANGLE = 225            -- R6 / Q13-C
local TEX_BG        = "Interface\\Minimap\\UI-Minimap-Background"
local TEX_RING      = "Interface\\Minimap\\MiniMap-TrackingBorder"
local TEX_HIGHLIGHT = "Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight"

-- AD-22.4.3 (CDKP-015c): layer contract (supersedes UX §13.6.1 sizes/anchors/texcoords)
local BTN_SIZE   = 32
local RING_SIZE  = 52                   -- Blizzard MiniMapTrackingFrame border size (C-22.4); opening centre = (16, -16)
local RING_X, RING_Y = 0, 0             -- TOPLEFT offset; the ONLY knob if the in-game screenshot shows a residual offset
local BG_SIZE    = 24
local ICON_SIZE  = 28                   -- AD-22.4.2 option (1) "flush"
local ICON_COORD = { 0, 1, 0, 1 }       -- BR-083.4: round full-canvas art, symmetric (zero) crop
local PUSH_X, PUSH_Y = 1, -1            -- BR-083.5: 1 px down-right

local function HasTexture(path) return not GetFileIDFromPath or GetFileIDFromPath(path) ~= nil end
local function Loc(key, fallback) return (L and L[key]) or fallback end

local function GetAngle() local d = core.DB and core.DB.defaults; return (d and tonumber(d.minimapPos)) or MINIMAP_DEFAULT_ANGLE end
local function SaveAngle(a) if core.DB and core.DB.defaults then core.DB.defaults.minimapPos = a % 360 end end  -- local only, never synced

local function Place(b)
	local a, r = math.rad(GetAngle()), (Minimap:GetWidth() / 2) + 5
	b:ClearAllPoints(); b:SetPoint("CENTER", Minimap, "CENTER", math.cos(a) * r, math.sin(a) * r)
end

-- GetCenter is in Minimap space, so the cursor is divided by Minimap's effective scale (AD-19.2 (e) correction).
local function DragUpdate(self)
	local mx, my = Minimap:GetCenter()
	if not mx then return end
	local cx, cy = GetCursorPosition()
	local sc = Minimap:GetEffectiveScale()
	SaveAngle(math.deg(math.atan2(cy / sc - my, cx / sc - mx)))
	Place(self)
end

function CommDKP:UpdateMinimapButtonPosition(angle)
	if angle ~= nil and tonumber(angle) then SaveAngle(tonumber(angle)) end
	if CommDKP.MinimapButton then Place(CommDKP.MinimapButton) end
end

-- AD-22.4.4: pushed feedback. Only the icon moves; every restore re-applies anchor, size and texcoord.
local function SetIconPushed(b, down)
	if not b.Icon then return end
	b.Icon:ClearAllPoints()
	b.Icon:SetPoint("CENTER", b, "CENTER", down and PUSH_X or 0, down and PUSH_Y or 0)
	b.Icon:SetSize(ICON_SIZE, ICON_SIZE)
	b.Icon:SetTexCoord(unpack(ICON_COORD))
	b.isPushed = down and true or nil
end

function CommDKP:CreateMinimapButton()   -- idempotent; layers / sizes / texture probe per AD-22.4.3 (was UX §13.6.1)
	if CommDKP.MinimapButton or not Minimap then return CommDKP.MinimapButton end

	local b = CreateFrame("Button", "CommDKPMinimapButton", Minimap)
	b:SetSize(BTN_SIZE, BTN_SIZE)
	b:SetFrameStrata("MEDIUM")
	b:SetFrameLevel(8)
	b:RegisterForClicks("LeftButtonUp")
	b:RegisterForDrag("LeftButton")

	local hasBg, hasRing, hasHi = HasTexture(TEX_BG), HasTexture(TEX_RING), HasTexture(TEX_HIGHLIGHT)
	if hasBg then
		b.Background = b:CreateTexture(nil, "BACKGROUND")
		b.Background:SetSize(BG_SIZE, BG_SIZE); b.Background:SetPoint("CENTER", b, "CENTER", 0, 0)
		b.Background:SetTexture(TEX_BG)
	end

	b.Icon = b:CreateTexture(nil, "ARTWORK")
	b.Icon:SetTexture(W and W.TEX and W.TEX.medallion or "Interface\\AddOns\\CommunityDKPForever\\Media\\Textures\\cdkp-medallion")
	SetIconPushed(b, false)                  -- rest state: CENTER (0, 0), 28 x 28, full texcoords

	if hasRing then
		b.Ring = b:CreateTexture(nil, "OVERLAY")
		b.Ring:SetSize(RING_SIZE, RING_SIZE); b.Ring:SetPoint("TOPLEFT", b, "TOPLEFT", RING_X, RING_Y)  -- art not centred in its canvas (S1)
		b.Ring:SetTexture(TEX_RING)
	end
	if hasHi then
		b:SetHighlightTexture(TEX_HIGHLIGHT, "ADD")
		local hl = b:GetHighlightTexture()
		if hl then hl:ClearAllPoints(); hl:SetPoint("CENTER", b, "CENTER", 0, 0); hl:SetSize(BTN_SIZE, BTN_SIZE) end
	end
	if not (hasBg and hasRing and hasHi) then   -- UX §13.6.1 texture probe fallback: 1-unit trim ring
		local P = core.Palette or (core.Palettes and core.Palettes.Forever) or {}
		b.FallbackEdges = CommDKP:CreatePixelBorder(b, P.trim or { 0.8, 0.65, 0.35, 1 })
	end

	b:SetScript("OnClick", function() CommDKP:Toggle() end)
	b:SetScript("OnMouseDown", function(self, button)
		if button == "LeftButton" then SetIconPushed(self, true) end
	end)
	b:SetScript("OnMouseUp", function(self) SetIconPushed(self, false) end)   -- fires before OnClick
	b:SetScript("OnDragStart", function(self)
		SetIconPushed(self, false)
		self.isDragging = true
		self:SetScript("OnUpdate", DragUpdate)
	end)
	b:SetScript("OnDragStop", function(self)
		self.isDragging = nil
		self:SetScript("OnUpdate", nil)
		Place(self)
		SetIconPushed(self, false)
	end)
	b:SetScript("OnEnter", function(self)
		if self.isDragging then return end
		GameTooltip:SetOwner(self, "ANCHOR_LEFT")
		GameTooltip:SetText(Loc("MINIMAPTT1", "CommunityDKP Forever"), 1, 0.82, 0)
		GameTooltip:AddLine(Loc("MINIMAPTT2", "Click: open/close"), 1, 1, 1)
		GameTooltip:AddLine(Loc("MINIMAPTT3", "Drag: move"), 1, 1, 1)
		GameTooltip:Show()
	end)
	b:SetScript("OnLeave", function(self) GameTooltip:Hide(); SetIconPushed(self, false) end)
	b:SetScript("OnHide", function(self) SetIconPushed(self, false) end)

	Place(b); CommDKP.MinimapButton = b; return b
end
