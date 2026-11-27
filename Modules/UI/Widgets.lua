-------------------------------------
-- CDKP-009 (AD-16.2 / AD-16.3 / AD-16.4): shared UI v2 widget kit.
-- The ONLY place the UI v2 looks are built (BR-9.3.7). Everything here is presentation: no DKP logic,
-- no comms, no SavedVariables (BR-9.5). Loaded directly after Core.lua (.toc); nothing builds UI before
-- ADDON_LOADED, so every function below only runs at window-construction time.
--
-- Behavioral rules (AD-16.2 (e)):
--   1. Hook, never replace: HookScript on every script the logic may already own. SetScript only on frames
--      the kit itself creates and has not handed to the logic.
--   2. Never reparent or rename a frame the logic created.
--   3. Idempotent: a second Style* call is a no-op (frame.cdkpStyled).
--   4. No writes into value fields: placeholders, notes and captions are separate FontStrings.
--   5. Palette by role name only (core.Palette[...]). Data colors pass through untouched (Q8).
-- Taint (AD-16.3 (c)): no Blizzard UIDropDownMenu / MenuUtil / secure templates / SetAttribute /
-- hooksecurefunc / SetPropagateKeyboardInput / UISpecialFrames insertion for lists. Insecure addon frames only.
-- (AD-19.2 012c exception: ONE instance hooksecurefunc(cb, "SetChecked", PaintCheck) on insecure addon CheckButtons.)
-- AD-27: the kit also owns a child plaque on the shared L_DropDownList frames for the 4 registered context menus. It never SetScripts or hooks the library's frames.
-------------------------------------
local _, core = ...
local CommDKP = core.CommDKP
local W = {}
CommDKP.Widgets = W

-------------------------------------
-- Constants (AD-16.2 (b), Q10, Q13)
-------------------------------------
W.H, W.CARD_HDR, W.PAGE_HDR, W.PLAQUE_HDR = 22, 22, 28, 20
W.PAD, W.GUT = 12, 8
W.ROW = core.TableRowHeight or 18
W.LIST_ROW, W.LIST_MAX_ROWS = 20, 10
-- AD-32.1 (CDKP-024): list geometry. A row takes 2*LIST_INSET + LIST_GUTTER_L + LIST_GUTTER_R = 48 px of panel width
-- away from its label (NewRow). A scrolling list (> LIST_MAX_ROWS) adds a dedicated LIST_RAIL_COL column for the 6 px
-- rail (panel RIGHT - 3 .. RIGHT - 9). LIST_SAFETY absorbs pixel snapping of the 4 anchored edges at any UI scale.
W.LIST_INSET, W.LIST_GUTTER_L, W.LIST_GUTTER_R = 4, 24, 16
W.LIST_RAIL_COL, W.LIST_SAFETY = 10, 12
W.LIST_MIN_W, W.LIST_MIN_W1 = 72, 80                  -- sub-menu floor / level-1 floor (the button width wins when larger)
W.LIST_ROW_CHROME = 2 * W.LIST_INSET + W.LIST_GUTTER_L + W.LIST_GUTTER_R   -- 48
W.FOREVER_TEMPLATE = "PortraitFrameTemplate"
W.FOREVER_LAYOUT   = "ButtonFrameTemplateNoPortrait"
W.FOREVER_BORDER   = { 1, 0.84, 0.45, 1 }
W.FOREVER_BG_TINT  = { 0.55, 0.45, 0.33 }      -- Q10: today's shipped value; { 1, 1, 1 } = ForeverGold's untinted rock
W.LIST_STRATA      = "FULLSCREEN_DIALOG"       -- above focused floaters (FULLSCREEN, §10.1.3) and UIConfig (DIALOG)
-- AD-16.3 (e) R2: the Broadcast Status toast (Sync.lua:74) is also pinned to FULLSCREEN_DIALOG and its template
-- children climb past level 20, so the list stack sits well above it: catcher 90 < panel L1 110 < L2 120 < L3 130.
W.LIST_CATCHER_LEVEL, W.LIST_PANEL_LEVEL = 90, 100
W.CHECK_DISABLED_ALPHA = 0.45
-- AD-19.2 (012c) / UX §13.1.2 with ruling R3: the box stays 16x16, the glyph is 14x14 centred.
W.CHECK_SIZE = 16
W.CHECK_GLYPH_SIZE = 14
W.CHECK_FILL_ON       = { 0.278, 0.200, 0.102, 1 }   -- #47331A
W.CHECK_FILL_ON_HOVER = { 0.337, 0.251, 0.122, 1 }   -- #56401F
W.CHECK_GLYPH         = { 1.00, 0.922, 0.580, 1 }    -- #FFEB94

local MEDIA = "Interface\\AddOns\\CommunityDKPForever\\Media\\Textures\\"
W.TEX = {
	check     = MEDIA .. "cdkp-check",
	chevron   = MEDIA .. "cdkp-chevron-down",
	close     = MEDIA .. "cdkp-close",
	pip       = MEDIA .. "cdkp-pip",
	medallion = MEDIA .. "cdkp-medallion",
	chevronDouble = MEDIA .. "cdkp-chevron-double",   -- AD-19.2 (012c) (f)
	changelog     = MEDIA .. "cdkp-changelog",
}
W.FONT = {
	title   = "GameFontNormalLarge",
	heading = "GameFontNormal",
	body    = "GameFontHighlight",
	caption = "GameFontHighlightSmall",
	label   = "GameFontNormalSmall",
	readout = "GameFontNormalHuge",
	bodyOutline = "GameFontHighlightSmallOutline",   -- AD-16.3 (e) R3: text drawn over the bid timer bar
}

local function Pal() return core.Palette or core.Palettes.Forever end
local function C(role) return Pal()[role] or core.Palettes.Forever[role] end

-- 12.1.5 Secret Value defense: every kit SetText routes through here.
function W.SafeText(s)
	if issecretvalue and s ~= nil and issecretvalue(s) then return "?" end
	return tostring(s == nil and "" or s)
end
local SafeText = W.SafeText

-- AD-16.4 (d): template probe (moved from Core.lua). Headless (no C_XMLUtil) -> false -> plaque path.
function W.HasTemplate(name)
	return (C_XMLUtil and C_XMLUtil.GetTemplateInfo and C_XMLUtil.GetTemplateInfo(name) ~= nil) and true or false
end

-- Every new FontString on a UI surface comes from here; call sites never SetFont (BR-9.3.7).
function W.CreateText(parent, role, text, justifyH, colorRole)
	local fs = parent:CreateFontString(nil, "OVERLAY")
	fs:SetFontObject(W.FONT[role or "body"] or role)
	if justifyH then fs:SetJustifyH(justifyH) end
	if colorRole then fs:SetTextColor(unpack(C(colorRole))) end
	if text ~= nil then fs:SetText(SafeText(text)) end
	return fs
end

-- Shared backdrop through the one allowlisted SetBackdrop (CommDKP:ApplyBackdrop, AD-5.4). Tolerates headless cores.
local function Backdrop(f, key, bg, border)
	if CommDKP.ApplyBackdrop and core.Backdrops and core.Backdrops[key] then
		CommDKP:ApplyBackdrop(f, key, bg, border)
	end
end

-- Hook, never replace (AD-16.2 (e) 1) also has to survive the logic's LATER SetScript calls: most call sites style a
-- widget (or get it pre-styled from CommDKP:CreateButton) and only then SetScript("OnEnter", tooltip), which would
-- silently drop the kit's paint hooks. KeepHooks re-attaches `fn` after any SetScript on one of `events`; the logic's
-- own script is installed first and runs unchanged. Instance-level method on an insecure addon frame only.
local function KeepHooks(frame, events, fn)
	if not (frame and frame.SetScript and frame.HookScript) then return end
	local set = {}
	for _, ev in ipairs(events) do set[ev] = true end
	local hooks = frame.cdkpKeptHooks
	if not hooks then
		hooks = {}
		frame.cdkpKeptHooks = hooks
		local rawSetScript = frame.SetScript
		frame.SetScript = function(self, event, handler, ...)
			rawSetScript(self, event, handler, ...)
			for _, h in ipairs(hooks) do
				if h.events[event] then self:HookScript(event, h.fn) end
			end
		end
	end
	hooks[#hooks + 1] = { events = set, fn = fn }
	for ev in pairs(set) do frame:HookScript(ev, fn) end
end
W.KeepHooks = KeepHooks

-------------------------------------
-- Pixel border + button fonts (moved from Core.lua §11.2.3, same public names)
-------------------------------------
-- AD-21.4.3 (BR-14.3, supersedes AD-19.2 (a)): every 1-px edge/rule is N whole physical pixels (N = max(1, round(px per
-- unit)) at the texture's CURRENT effective scale) and is not engine-snapped, so it can never round to 0 px at any UI
-- scale, window position or scroll offset. Re-applied on the owner's OnShow and on UI-scale / display-size changes.
local pixelEdges = setmetatable({}, { __mode = "k" })   -- texture -> true (horizontal: height) / false (vertical: width)

local function PxPerUnit(region)
	local es = region.GetEffectiveScale and region:GetEffectiveScale() or 1
	if not es or es <= 0 then es = 1 end
	local ph = 768
	if GetPhysicalScreenSize then
		local _, h = GetPhysicalScreenSize()
		if h and h > 0 then ph = h end
	end
	return es * ph / 768
end

local function ApplyOnePixel(t)
	local horizontal = pixelEdges[t]
	if horizontal == nil then return end
	local ppu = PxPerUnit(t)
	local units = math.max(1, math.floor(ppu + 0.5)) / ppu
	if horizontal then t:SetHeight(units) else t:SetWidth(units) end
end

local function RefreshOwnerEdges(owner)
	local list = owner and owner.cdkpPixelEdgeList
	if list then for i = 1, #list do ApplyOnePixel(list[i]) end end
end

function W.RefreshPixelEdges()
	for t in pairs(pixelEdges) do ApplyOnePixel(t) end
end

local function SetOnePixel(t, horizontal)
	pixelEdges[t] = horizontal and true or false
	if t.SetSnapToPixelGrid then t:SetSnapToPixelGrid(false) end
	if t.SetTexelSnappingBias then t:SetTexelSnappingBias(0) end
	local owner = t.GetParent and t:GetParent()
	if owner then
		owner.cdkpPixelEdgeList = owner.cdkpPixelEdgeList or {}
		table.insert(owner.cdkpPixelEdgeList, t)
		if not owner.cdkpPixelEdgeHook and owner.HookScript then
			owner.cdkpPixelEdgeHook = true
			KeepHooks(owner, { "OnShow" }, RefreshOwnerEdges)   -- survives a later SetScript("OnShow") (AD-16.2 (e) 1)
		end
	end
	ApplyOnePixel(t)
end

if CreateFrame then   -- headless-safe; one driver for scale/resolution changes
	local drv = CreateFrame("Frame")
	pcall(drv.RegisterEvent, drv, "UI_SCALE_CHANGED")
	pcall(drv.RegisterEvent, drv, "DISPLAY_SIZE_CHANGED")
	drv:SetScript("OnEvent", function() W.RefreshPixelEdges() end)
end

-- AD-19.2 (012c) (b): textures live on `frame`, anchored to `anchorTo or frame` (lets the checkbox paint on the
-- CheckButton itself around an invisible layout box). Every 2-argument caller is unchanged.
function CommDKP:CreatePixelBorder(frame, color, anchorTo)
	local e = {}
	local a = anchorTo or frame
	for _, side in ipairs({ "TOP", "BOTTOM", "LEFT", "RIGHT" }) do
		local t = frame:CreateTexture(nil, "BORDER")
		if side == "TOP" or side == "BOTTOM" then
			t:SetPoint(side .. "LEFT", a, side .. "LEFT"); t:SetPoint(side .. "RIGHT", a, side .. "RIGHT"); SetOnePixel(t, true)
		else
			t:SetPoint("TOP" .. side, a, "TOP" .. side); t:SetPoint("BOTTOM" .. side, a, "BOTTOM" .. side); SetOnePixel(t, false)
		end
		e[#e + 1] = t
	end
	CommDKP:SetPixelBorderColor(e, color)
	return e
end

function CommDKP:SetPixelBorderColor(e, c)
	for _, t in ipairs(e) do t:SetColorTexture(unpack(c)) end
end
W.CreatePixelBorder = function(frame, color, anchorTo) return CommDKP:CreatePixelBorder(frame, color, anchorTo) end
W.SetPixelBorderColor = function(e, c) return CommDKP:SetPixelBorderColor(e, c) end

-- §11.2.3 button font objects (parchment / dim tan). Guarded for headless test environments.
if CreateFont and not _G.CommDKPButtonFont then
	local f = CreateFont("CommDKPButtonFont")
	if GameFontHighlight then f:CopyFontObject(GameFontHighlight) end
	f:SetTextColor(0.949, 0.902, 0.812)
	local d = CreateFont("CommDKPButtonFontDisabled")
	if GameFontDisable then d:CopyFontObject(GameFontDisable) end
	d:SetTextColor(0.494, 0.435, 0.349)
end

-------------------------------------
-- Buttons (§12.2.4): flat bronze, 1 px rule, optional tone
-------------------------------------
local function PaintButton(self)
	local P = Pal()
	if not (self.cdkpFill and self.cdkpEdges) then return end
	local on = self:IsEnabled()
	local over = on and self:IsMouseOver()
	local down = on and self:GetButtonState() == "PUSHED"
	self.cdkpFill:SetColorTexture(unpack((down and P.bg4) or (over and P.bg3) or P.bg2))
	local edge = (over or down) and P.trim or P.line
	local tone = self.cdkpTone
	if tone == "primary" and on then edge = P.trim
	elseif tone == "caution" and on then edge = P.warning or edge
	elseif tone == "pill" then edge = (over or down) and P.trim or P.trimQuiet end   -- AD-19.2 (012c) (f)
	CommDKP:SetPixelBorderColor(self.cdkpEdges, edge)
	if self.cdkpWash then
		self.cdkpWash:SetShown(tone == "primary" and on and true or false)
	end
	local fs = self.GetFontString and self:GetFontString()
	if fs and fs.SetTextColor and tone == "caution" then
		fs:SetTextColor(unpack(on and (P.warning or P.text) or P.textDisabled))
	end
end
W.PaintButton = PaintButton

-- Idempotent re-skin. Keeps the Button object, global name, SetText/GetText, Enable/Disable and OnClick
-- (HookScript only, never SetScript). tone: nil | "primary" | "caution".
function W.StyleButton(b, tone)
	if not b then return end
	local P = Pal()
	for _, k in ipairs({ "Left", "Middle", "Right" }) do if b[k] and b[k].Hide then b[k]:Hide() end end   -- UIPanelButton pieces
	if tone ~= nil then b.cdkpTone = tone end
	if not b.cdkpStyled then
		if b.ClearNormalTexture then
			b:ClearNormalTexture(); b:ClearPushedTexture(); b:ClearDisabledTexture(); b:ClearHighlightTexture()
		elseif b.SetNormalTexture then
			b:SetNormalTexture(""); b:SetPushedTexture(""); b:SetDisabledTexture(""); b:SetHighlightTexture("")
		end
		b.cdkpFill = b.cdkpFill or b:CreateTexture(nil, "BACKGROUND")
		b.cdkpFill:SetAllPoints()
		b.cdkpEdges = b.cdkpEdges or CommDKP:CreatePixelBorder(b, P.line)
		if _G.CommDKPButtonFont and b.SetNormalFontObject then
			b:SetNormalFontObject("CommDKPButtonFont")            -- GameFontHighlight + text #F2E6CF
			b:SetHighlightFontObject("CommDKPButtonFont")
			b:SetDisabledFontObject("CommDKPButtonFontDisabled")  -- GameFontDisable + textDisabled #7E6F59
		end
		if b.SetPushedTextOffset then b:SetPushedTextOffset(1, -1) end
		KeepHooks(b, { "OnEnter", "OnLeave", "OnMouseDown", "OnMouseUp", "OnEnable", "OnDisable", "OnShow" }, PaintButton)
		b.cdkpStyled = true
	end
	if b.cdkpTone == "primary" and not b.cdkpWash then
		b.cdkpWash = b:CreateTexture(nil, "BACKGROUND", nil, 1)
		b.cdkpWash:SetAllPoints()
		b.cdkpWash:SetColorTexture(unpack(P.ruby))
	end
	PaintButton(b)
end
-- Forwarder kept for XMLFunctions.lua and CommDKP:CreateButton (AD-16.2 (c)).
function CommDKP:StyleButton(b, tone) return W.StyleButton(b, tone) end

function W.CreateButton(parent, text, onClick, opts)
	opts = opts or {}
	local b = CreateFrame("Button", opts.name, parent)
	b:SetHeight(W.H)
	local fs = b:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
	fs:SetPoint("CENTER")
	if b.SetFontString then b:SetFontString(fs) end
	b:SetText(SafeText(text))
	local tw = (fs.GetStringWidth and fs:GetStringWidth()) or 0
	b:SetWidth(opts.width or math.max(56, tw + 16))
	if onClick then b:SetScript("OnClick", onClick) end
	W.StyleButton(b, opts.tone)
	return b
end

-- 16x16 flat [X] (plaque close): cdkp-close glyph in textMuted, trim on hover.
function W.CreateCloseButton(parent, onClick)
	local b = CreateFrame("Button", nil, parent)
	b:SetSize(16, 16)
	b.Glyph = b:CreateTexture(nil, "ARTWORK")
	b.Glyph:SetAllPoints()
	b.Glyph:SetTexture(W.TEX.close)
	b.Glyph:SetVertexColor(unpack(C("textMuted")))
	b:SetScript("OnEnter", function(self) self.Glyph:SetVertexColor(unpack(C("trim"))) end)
	b:SetScript("OnLeave", function(self) self.Glyph:SetVertexColor(unpack(C("textMuted"))) end)
	if onClick then b:SetScript("OnClick", onClick) end
	return b
end

-- 22x21 icon button with a gold glyph (e.g. [«] collapse, [»] pop-out).
function W.CreateIconButton(parent, glyph, tooltip, onClick)
	local b = CreateFrame("Button", nil, parent)
	b:SetSize(22, 21)
	W.StyleButton(b)
	b.Glyph = b:CreateTexture(nil, "ARTWORK")
	b.Glyph:SetSize(14, 14)
	b.Glyph:SetPoint("CENTER")
	b.Glyph:SetTexture(glyph)
	b.Glyph:SetVertexColor(unpack(C("gold")))
	if tooltip then
		b:HookScript("OnEnter", function(self)
			if not GameTooltip then return end
			GameTooltip:SetOwner(self, "ANCHOR_RIGHT"); GameTooltip:SetText(SafeText(tooltip), 1, 0.82, 0); GameTooltip:Show()
		end)
		b:HookScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
	end
	if onClick then b:SetScript("OnClick", onClick) end
	return b
end

-- AD-19.2 (012c) (f) / UX §13.4.2: labelled pill button (double chevron + word), 24 tall, single 1-unit edge.
-- side == "left": « glyph then label; side == "right": label then » glyph (mirrored).
local PILL_HOVER = { 1.00, 0.902, 0.502, 1 }   -- #FFE680
function W.CreatePillButton(parent, text, side, onClick)
	local b = CreateFrame("Button", nil, parent)
	W.StyleButton(b, "pill")
	b.Glyph = b:CreateTexture(nil, "ARTWORK")
	b.Glyph:SetSize(14, 14)
	b.Glyph:SetTexture(W.TEX.chevronDouble)
	b.Label = W.CreateText(b, "label", text, side == "right" and "RIGHT" or "LEFT")
	if b.Label.SetWordWrap then b.Label:SetWordWrap(false) end
	local function Layout(dx, dy)
		b.Glyph:ClearAllPoints(); b.Label:ClearAllPoints()
		if side == "right" then
			b.Glyph:SetPoint("RIGHT", b, "RIGHT", -7 + dx, dy)
			b.Label:SetPoint("RIGHT", b.Glyph, "LEFT", -5, 0)
		else
			b.Glyph:SetPoint("LEFT", b, "LEFT", 7 + dx, dy)
			b.Label:SetPoint("LEFT", b.Glyph, "RIGHT", 5, 0)
		end
	end
	if side == "right" then b.Glyph:SetTexCoord(1, 0, 0, 1) end
	Layout(0, 0)
	local tw = (b.Label.GetStringWidth and b.Label:GetStringWidth()) or 0
	b:SetSize(7 + 14 + 5 + tw + 9, 24)
	local function Paint(self)
		local over = self:IsEnabled() and self:IsMouseOver()
		local c = over and PILL_HOVER or C("gold")
		self.Glyph:SetVertexColor(unpack(c)); self.Label:SetTextColor(unpack(c))
		local down = self:IsEnabled() and self:GetButtonState() == "PUSHED"
		if down then Layout(1, -1) else Layout(0, 0) end
	end
	KeepHooks(b, { "OnEnter", "OnLeave", "OnMouseDown", "OnMouseUp", "OnEnable", "OnDisable", "OnShow" }, Paint)
	Paint(b)
	if onClick then b:SetScript("OnClick", onClick) end
	return b
end

-------------------------------------
-- Card / page header (§12.2.2)
-------------------------------------
local function AddDropShadow(f)
	local sc = C("edgeShadow")
	local r = f:CreateTexture(nil, "BACKGROUND", nil, -8)
	r:SetColorTexture(unpack(sc)); r:SetWidth(2)
	r:SetPoint("TOPLEFT", f, "TOPRIGHT", 0, -2); r:SetPoint("BOTTOMLEFT", f, "BOTTOMRIGHT", 0, -2)
	local b = f:CreateTexture(nil, "BACKGROUND", nil, -8)
	b:SetColorTexture(unpack(sc)); b:SetHeight(2)
	b:SetPoint("TOPLEFT", f, "BOTTOMLEFT", 2, 0); b:SetPoint("TOPRIGHT", f, "BOTTOMRIGHT", 0, 0)
	f.cdkpShadow = { r, b }
end

local function BuildHeaderBand(f, height, titleFont)
	local h = CreateFrame("Frame", nil, f)
	h:SetPoint("TOPLEFT", f, "TOPLEFT", 3, -3)
	h:SetPoint("TOPRIGHT", f, "TOPRIGHT", -3, -3)
	h:SetHeight(height)
	h.Fill = h:CreateTexture(nil, "BACKGROUND")
	h.Fill:SetAllPoints(); h.Fill:SetColorTexture(unpack(C("bg2")))
	h.Rule = h:CreateTexture(nil, "BORDER")
	h.Rule:SetPoint("BOTTOMLEFT"); h.Rule:SetPoint("BOTTOMRIGHT"); SetOnePixel(h.Rule, true)
	h.Rule:SetColorTexture(unpack(C("trim")))
	h.Title = W.CreateText(h, titleFont, nil, "LEFT")
	h.Title:SetPoint("LEFT", h, "LEFT", W.PAD, 0)
	if h.Title.SetWordWrap then h.Title:SetWordWrap(false) end
	h.Note = W.CreateText(h, "caption", nil, "RIGHT", "textMuted")
	h.Note:SetPoint("RIGHT", h, "RIGHT", -W.PAD, 0)
	h.Actions = CreateFrame("Frame", nil, h)
	h.Actions:SetPoint("TOPRIGHT", h, "TOPRIGHT", 0, 0)
	h.Actions:SetSize(1, height)
	return h
end

-- opts = { name?, icon?, note?, page = bool, footer = px?, noHeader = bool }
function W.CreateCard(parent, title, w, h, opts)
	opts = opts or {}
	local card = CreateFrame("Frame", opts.name, parent, "BackdropTemplate")
	if w and h then card:SetSize(w, h) end
	Backdrop(card, "Card", "bg1", "trimQuiet")
	AddDropShadow(card)
	local hdrH = opts.page and W.PAGE_HDR or W.CARD_HDR
	if not opts.noHeader then
		card.Header = BuildHeaderBand(card, hdrH, opts.page and "title" or "heading")
		if opts.icon then
			card.Header.Icon = card.Header:CreateTexture(nil, "ARTWORK")
			card.Header.Icon:SetSize(16, 16)
			card.Header.Icon:SetPoint("LEFT", card.Header, "LEFT", W.PAD, 0)
			card.Header.Icon:SetTexture(opts.icon)
			card.Header.Title:ClearAllPoints()
			card.Header.Title:SetPoint("LEFT", card.Header, "LEFT", W.PAD + 22, 0)
		end
		card.Header.Title:SetText(SafeText(title))
		if opts.note then card.Header.Note:SetText(SafeText(opts.note)) end
	else
		hdrH = 0
	end
	card.Body = CreateFrame("Frame", nil, card)
	card.Body:SetPoint("TOPLEFT", card, "TOPLEFT", 3, -3 - hdrH)
	if opts.footer then
		card.Footer = CreateFrame("Frame", nil, card)
		card.Footer:SetPoint("BOTTOMLEFT", card, "BOTTOMLEFT", 3, 3)
		card.Footer:SetPoint("BOTTOMRIGHT", card, "BOTTOMRIGHT", -3, 3)
		card.Footer:SetHeight(opts.footer)
		card.Footer.Fill = card.Footer:CreateTexture(nil, "BACKGROUND")
		card.Footer.Fill:SetAllPoints(); card.Footer.Fill:SetColorTexture(unpack(C("bg2")))
		card.Footer.Rule = card.Footer:CreateTexture(nil, "BORDER")
		card.Footer.Rule:SetPoint("TOPLEFT"); card.Footer.Rule:SetPoint("TOPRIGHT"); SetOnePixel(card.Footer.Rule, true)
		card.Footer.Rule:SetColorTexture(unpack(C("line")))
		card.Body:SetPoint("BOTTOMRIGHT", card.Footer, "TOPRIGHT", 0, 0)
	else
		card.Body:SetPoint("BOTTOMRIGHT", card, "BOTTOMRIGHT", -3, 3)
	end
	function card:SetTitle(s) if self.Header then self.Header.Title:SetText(SafeText(s)) end end
	function card:SetNote(s) if self.Header then self.Header.Note:SetText(SafeText(s)) end end
	function card:AddHeaderButton(btn)
		if not self.Header then return end
		local a = self.Header.Actions
		a.buttons = a.buttons or {}
		btn:SetParent(a); btn:ClearAllPoints()
		local prev = a.buttons[#a.buttons]
		if prev then btn:SetPoint("RIGHT", prev, "LEFT", -2, 0) else btn:SetPoint("TOPRIGHT", a, "TOPRIGHT", 0, 0) end
		a.buttons[#a.buttons + 1] = btn
		self.Header.Note:ClearAllPoints()
		self.Header.Note:SetPoint("RIGHT", btn, "LEFT", -W.PAD, 0)
	end
	return card
end

-- Standalone page header panel (TabMenu.Header). .Title (alias .HeaderText kept by the caller), .CollapseBtn.
function W.CreatePageHeader(parent, title, onCollapse)
	local p = CreateFrame("Frame", nil, parent, "BackdropTemplate")
	Backdrop(p, "Card", "bg1", "trimQuiet")
	p.Band = BuildHeaderBand(p, W.PAGE_HDR, "title")
	p.Title = p.Band.Title
	p.Title:SetText(SafeText(title))
	if onCollapse then
		p.CollapseBtn = W.CreatePillButton(p.Band, COLLAPSE or "Collapse", "left", onCollapse)   -- AD-19.2 (012c) (f)
		p.CollapseBtn:SetPoint("RIGHT", p.Band, "RIGHT", -4, 0)
	end
	return p
end

-------------------------------------
-- Plaque (§12.2.3)
-------------------------------------
-- bg0 fill + tooltip edge; trimQuiet at rest, trim while hovered.
function W.ApplyPlaqueEdge(frame)
	if not frame or frame.cdkpPlaqueEdge then return frame end
	Backdrop(frame, "Plaque", "bg0", "trimQuiet")
	frame.cdkpPlaqueEdge = true
	if frame.HookScript then
		frame:HookScript("OnEnter", function(self) if self.SetBackdropBorderColor then self:SetBackdropBorderColor(unpack(C("trim"))) end end)
		frame:HookScript("OnLeave", function(self)
			if self.SetBackdropBorderColor and not (self.IsMouseOver and self:IsMouseOver()) then
				self:SetBackdropBorderColor(unpack(C("trimQuiet")))
			end
		end)
	end
	return frame
end

local function NewPlaque(parent, frameType, name)
	local p = CreateFrame(frameType or "Frame", name, parent or UIParent, "BackdropTemplate")
	W.ApplyPlaqueEdge(p)
	return p
end

-- AD-16.2 signature: W.CreatePlaque(parent, frameType?, name?).
-- Convenience form: W.CreatePlaque(parent, name, w, h, title, opts) (detected by a numeric 3rd argument).
function W.CreatePlaque(parent, a2, a3, a4, a5, a6)
	if type(a3) == "number" then
		local p = NewPlaque(parent, "Frame", a2)
		p:SetSize(a3, a4 or a3)
		if a5 ~= nil then W.AddPlaqueHeader(p, a5, a6) end
		if p.SetMovable then p:SetMovable(true) end
		if p.RegisterForDrag then p:RegisterForDrag("LeftButton") end
		return p
	end
	return NewPlaque(parent, a2, a3)
end

-- 20 px bg2 band + 1 px trim rule, 14 px medallion emblem, gold title. Sets p.Header, p.TitleLabel, p.Emblem.
function W.AddPlaqueHeader(p, title, opts)
	local band = CreateFrame("Frame", nil, p)
	band:SetPoint("TOPLEFT", p, "TOPLEFT", 3, -3)
	band:SetPoint("TOPRIGHT", p, "TOPRIGHT", -3, -3)
	band:SetHeight(W.PLAQUE_HDR)
	band.Fill = band:CreateTexture(nil, "BACKGROUND")
	band.Fill:SetAllPoints(); band.Fill:SetColorTexture(unpack(C("bg2")))
	band.Rule = band:CreateTexture(nil, "BORDER")
	band.Rule:SetPoint("BOTTOMLEFT"); band.Rule:SetPoint("BOTTOMRIGHT"); SetOnePixel(band.Rule, true)
	band.Rule:SetColorTexture(unpack(C("trim")))
	p.Emblem = band:CreateTexture(nil, "ARTWORK")
	p.Emblem:SetSize(14, 14)
	p.Emblem:SetPoint("LEFT", band, "LEFT", 4, 0)
	p.Emblem:SetTexture(W.TEX.medallion)
	p.TitleLabel = W.CreateText(band, "heading", title, "LEFT")
	p.TitleLabel:SetPoint("LEFT", p.Emblem, "RIGHT", 4, 0)
	p.TitleLabel:SetPoint("RIGHT", band, "RIGHT", -24, 0)
	if p.TitleLabel.SetWordWrap then p.TitleLabel:SetWordWrap(false) end
	band.Actions = CreateFrame("Frame", nil, band)
	band.Actions:SetPoint("RIGHT", band, "RIGHT", -4, 0)
	band.Actions:SetSize(1, W.PLAQUE_HDR)
	p.Header = band
	if p.RegisterForDrag then p:RegisterForDrag("LeftButton") end
	return band
end

-------------------------------------
-- Context-menu plaque (CDKP-019, AD-27): opaque bg0 + 1 px trimQuiet behind the 4 LibDD right-click menus.
-- The carrier is OUR child frame on each shared L_DropDownList<n>; the library's frames are never SetScript/
-- HookScript-ed (a newer library copy re-SetScripts them, AD-27.1.2 F3). Independent of the Blizzard
-- tooltip-backdrop globals and of which library copy won LibStub (RC-1/RC-2).
-------------------------------------
local contextMenus = setmetatable({}, { __mode = "k" })   -- menuFrame -> true

local function IsOurContextMenu(frame)
	if frame == nil then return false end
	if contextMenus[frame] then return true end
	return type(frame) == "table" and frame.cdkpContextMenu == true
end
W.IsOurContextMenu = IsOurContextMenu

local function LibBackdropRegions(list)
	-- Every region a library copy may use to draw the list background (Rev 78: Border/MenuBackdrop;
	-- newer revisions: the same names, or a NineSlice). Deduplicated; never our own plaque.
	local name, out, seen = list.GetName and list:GetName(), {}, {}
	local cands = { list.MenuBackdrop, list.Border, list.NineSlice,
		name and _G[name .. "MenuBackdrop"], name and _G[name .. "Border"] }
	for i = 1, 5 do
		local r = cands[i]
		if r and not seen[r] and r ~= list.cdkpPlaque and r.Hide and r.Show and r.IsShown then
			seen[r] = true; out[#out + 1] = r
		end
	end
	return out
end

local SyncContextMenuPlaque   -- forward

local function AttachContextMenuPlaque(list)
	if not list or list.cdkpPlaque or not CreateFrame then return list and list.cdkpPlaque end
	local p = CreateFrame("Frame", nil, list, "BackdropTemplate")   -- unnamed: no new global
	p:SetAllPoints(list)
	p:EnableMouse(false)
	p:SetFrameLevel(list:GetFrameLevel())
	p:SetScript("OnShow", function(self) SyncContextMenuPlaque(self:GetParent()) end)
	p:SetScript("OnHide", function(self) W._ReleaseContextMenuPlaque(self:GetParent()) end)
	Backdrop(p, "Fill")                                            -- AD-5.4 allowlisted SetBackdrop; no colours yet
	local bg = C("bg0")
	if p.SetBackdropColor then p:SetBackdropColor(bg[1], bg[2], bg[3], 1) end   -- BR-19.2: bg0 at FULL alpha
	p.cdkpEdges = CommDKP:CreatePixelBorder(p, C("trimQuiet"))   -- AD-21.4.3 whole-pixel 1 px edge
	p:SetAlpha(0)                                                  -- invisible until an owned menu shows
	list.cdkpPlaque = p
	-- p stays :Show()n for life (D-27.1): its OnShow/OnHide follow the list's visibility.
	return p
end

function W.EnsureContextMenuPlaques()
	local maxLevels = tonumber(_G.L_UIDROPDOWNMENU_MAXLEVELS) or 2
	for i = 1, maxLevels do
		local list = _G["L_DropDownList" .. i]
		if list and not list.cdkpPlaque then AttachContextMenuPlaque(list) end
	end
end

SyncContextMenuPlaque = function(list)
	local p = list and list.cdkpPlaque
	if not p then return end
	W.EnsureContextMenuPlaques()                       -- levels created since registration (F7)
	if IsOurContextMenu(_G.L_UIDROPDOWNMENU_OPEN_MENU) then
		p:SetFrameLevel(list:GetFrameLevel())          -- below the item buttons (level + 1), every show (F4)
		list.cdkpHidden = list.cdkpHidden or {}
		for _, r in ipairs(LibBackdropRegions(list)) do
			if list.cdkpHidden[r] == nil then list.cdkpHidden[r] = r:IsShown() and true or false end
			r:Hide()                                   -- no tooltip box under our plaque (AC-19.3: no double border)
		end
		p:SetAlpha(1)
		list.cdkpOwned = true
	else
		-- Another addon's menu: the owning library copy has JUST set its own Border/MenuBackdrop for this
		-- open (LibUIDropDownMenu.lua:1526-1532 runs before listFrame:Show()). Never override it (BR-19.3).
		p:SetAlpha(0)
		list.cdkpHidden = nil
		list.cdkpOwned = false
	end
end
W._SyncContextMenuPlaque = SyncContextMenuPlaque     -- headless entry point (H129), same pattern as W._Collect

function W._ReleaseContextMenuPlaque(list)
	if not list then return end
	if list.cdkpHidden then
		for r, wasShown in pairs(list.cdkpHidden) do
			if wasShown and r.Show then r:Show() end   -- restore exactly what WE hid, nothing else
		end
	end
	list.cdkpHidden = nil
	list.cdkpOwned = false
	if list.cdkpPlaque then list.cdkpPlaque:SetAlpha(0) end
end

-- One line at each of the 4 creation sites (AD-27.2.3). Returns the frame unchanged.
function W.RegisterContextMenu(menuFrame)
	if not menuFrame then return menuFrame end
	contextMenus[menuFrame] = true
	menuFrame.cdkpContextMenu = true
	W.EnsureContextMenuPlaques()
	return menuFrame
end

if CreateFrame then   -- a library copy loaded after us may have created/replaced list frames
	local drv = CreateFrame("Frame")
	pcall(drv.RegisterEvent, drv, "PLAYER_LOGIN")
	pcall(drv.RegisterEvent, drv, "ADDON_LOADED")
	drv:SetScript("OnEvent", function() W.EnsureContextMenuPlaques() end)
end

-------------------------------------
-- Window chrome (AD-16.4): PortraitFrameTemplate + NoPortrait NineSlice, gold tint, rock Bg, no Inset well
-------------------------------------
-- opts = { titleInset? }  (nil = main window: the title stays after the medallion in the template's TitleContainer)
function CommDKP:ApplyForeverChrome(f, opts)
	if not f then return end
	local ns = f.NineSlice
	if ns then
		local ok = NineSliceUtil and NineSliceUtil.ApplyLayoutByName
			and pcall(NineSliceUtil.ApplyLayoutByName, ns, W.FOREVER_LAYOUT)
		if not ok and ButtonFrameTemplate_HidePortrait then pcall(ButtonFrameTemplate_HidePortrait, f) end
		if ns.SetBorderColor then pcall(ns.SetBorderColor, ns, unpack(W.FOREVER_BORDER)) end   -- shipped path, verified in game
	end
	if f.PortraitContainer and f.PortraitContainer.Hide then f.PortraitContainer:Hide() end
	if f.portrait and f.portrait.Hide then f.portrait:Hide() end
	if f.Bg and f.Bg.SetVertexColor then f.Bg:SetVertexColor(unpack(W.FOREVER_BG_TINT)) end           -- Q10
	if f.TopTileStreaks and f.TopTileStreaks.Show then f.TopTileStreaks:Show() end
	if opts and opts.titleInset and f.TitleContainer then                                             -- popups: no medallion
		f.TitleContainer:ClearAllPoints()
		f.TitleContainer:SetPoint("TOPLEFT",  f, "TOPLEFT",  opts.titleInset, -1)
		f.TitleContainer:SetPoint("TOPRIGHT", f, "TOPRIGHT", -24, -1)                                    -- clear of CloseButton
	end
	local t = (f.GetTitleText and f:GetTitleText()) or (f.TitleContainer and f.TitleContainer.TitleText)
	if t then
		t:SetFontObject(W.FONT.title); t:SetJustifyH("LEFT"); if t.SetWordWrap then t:SetWordWrap(false) end
		if f.TitleContainer then
			t:ClearAllPoints()
			t:SetPoint("LEFT", f.TitleContainer, "LEFT", 0, 0); t:SetPoint("RIGHT", f.TitleContainer, "RIGHT", 0, 0)
		end
		f.TitleLabel = t
	end
	f.cdkpChrome = "window"
end

-- Works for both chrome styles: writes f.TitleLabel, falling back to f:SetTitle. leftInset (legacy §11.1.2 form)
-- re-anchors the title left-aligned after an inset on the title bar.
function CommDKP:SetForeverTitle(f, text, leftInset)
	text = SafeText(text)
	local t = f.TitleLabel or (f.GetTitleText and f:GetTitleText()) or f.TitleText
		or (f.TitleContainer and f.TitleContainer.TitleText)
	if not t and f.SetTitle then
		f:SetTitle(text)
		t = f.GetTitleText and f:GetTitleText()
		if t then f.TitleLabel = t end
		return t
	end
	if not t then
		t = f:CreateFontString(nil, "OVERLAY", W.FONT.heading)
		t:SetPoint("TOPLEFT", f, "TOPLEFT", 16, -6)
		t:SetJustifyH("LEFT")
	end
	if leftInset then
		local bar = f.TitleBg or f.TitleContainer or f
		t:ClearAllPoints()
		t:SetPoint("LEFT", bar, "LEFT", leftInset, 0)
		if f.CloseButton then t:SetPoint("RIGHT", f.CloseButton, "LEFT", -4, 0) end
		t:SetJustifyH("LEFT")
		if t.SetWordWrap then t:SetWordWrap(false) end
	end
	t:SetText(text); f.TitleLabel = t
	return t
end

-- Returns f with f.cdkpChrome = "window" | "plaque"; never errors on a missing template. Never BasicFrameTemplateWithInset.
function W.CreateChromeFrame(name, parent, style, title, chromeOpts)
	local f
	if style == "window" and W.HasTemplate(W.FOREVER_TEMPLATE) then
		local ok, fr = pcall(CreateFrame, "Frame", name, parent, W.FOREVER_TEMPLATE)
		if ok and fr then
			f = fr
			CommDKP:ApplyForeverChrome(f, chromeOpts)
			if f.SetTitle then f:SetTitle(SafeText(title)) end
			CommDKP:SetForeverTitle(f, title)
			f.closeBtn = f.CloseButton                                -- §11 alias
		end
	end
	if not f then                                                    -- "plaque", or the probe fallback (ForeverGold MainWindow.lua:539-547)
		f = W.CreatePlaque(parent, "Frame", name)                      -- BackdropTemplate -> SetBackdrop is legal
		W.AddPlaqueHeader(f, title or "", chromeOpts)                  -- sets f.TitleLabel
		if not (chromeOpts and chromeOpts.noClose) then
			f.CloseButton = W.CreateCloseButton(f, function() f:Hide() end)
			f.CloseButton:SetPoint("RIGHT", f.Header, "RIGHT", -4, 0)
			f.closeBtn = f.CloseButton
		end
		f.cdkpChrome = "plaque"
	end
	return f
end

-- AD-33.1 (CDKP-025, BR-25.2/25.4/25.5): the 58x58 top-left corner dice medallion (UX §11.1.2). The ONE code path for the
-- main window (CommDKPConfigMedallion) and the Change Log (CommDKP_ChangeLogMedallion), so the two can never drift.
-- Decorative: EnableMouse(false) lets clicks/drags fall through to f. Drawn above the NineSlice border.
-- Plaque fallback: hides the 14 px header emblem and re-anchors the title to clear the medallion.
-- Window path: the caller passes chromeOpts nil so the template's TitleContainer (after the medallion) holds the title.
-- The caller owns SetClampRectInsets (the medallion overhangs 10 px left and 12 px up). Idempotent per frame.
function W.AttachMedallion(f, globalName)
	if not f then return nil end
	if f.Medallion then return f.Medallion end
	local medallion = CreateFrame("Frame", globalName, f)
	medallion:SetSize(58, 58)
	medallion:SetPoint("TOPLEFT", f, "TOPLEFT", -10, 12)
	medallion:SetFrameLevel(((f.NineSlice and f.NineSlice:GetFrameLevel()) or f:GetFrameLevel()) + 5)
	medallion:EnableMouse(false)
	medallion.Icon = medallion:CreateTexture(nil, "ARTWORK")
	medallion.Icon:SetAllPoints()
	medallion.Icon:SetTexture(W.TEX.medallion)
	f.Medallion = medallion
	if f.cdkpChrome == "plaque" and f.Header and f.TitleLabel then   -- fallback: clear the medallion, no 14 px emblem
		if f.Emblem then f.Emblem:Hide() end
		f.TitleLabel:ClearAllPoints()
		f.TitleLabel:SetPoint("LEFT", f.Header, "LEFT", 52, 0)
		f.TitleLabel:SetPoint("RIGHT", f.Header, "RIGHT", -24, 0)
	end
	return medallion
end

-- THE CONTENT FRAME: every interior card anchors to f.Content, never to f (BR-9.4.4 1-line flip).
-- f.ContentInset is a legacy alias (B3).
function W.LayoutContent(f)
	local win = (f.cdkpChrome == "window")
	f.Content = f.Content or CreateFrame("Frame", nil, f)
	f.Content:ClearAllPoints()
	f.Content:SetPoint("TOPLEFT",     f, "TOPLEFT",     win and 12 or 8,  win and -30 or -26)
	f.Content:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", win and -12 or -8, win and 12 or 8)
	f.ContentInset = f.Content
	return f.Content
end

-- opts = { style = "window"|"plaque" (default "window"), group?, escape? = true, floater? = true, movable? = true, noClose? }
-- Created hidden: the first Show() fires OnShow -> floater registry focus (§10.1.3).
-- NOTE: callers must use HookScript (not SetScript) for OnShow/OnHide/OnMouseDown afterwards.
function CommDKP:CreateForeverWindow(name, w, h, title, opts)
	opts = opts or {}
	local f = W.CreateChromeFrame(name, UIParent, opts.style or "window", title,
		{ titleInset = 16, noClose = opts.noClose })
	f:SetSize(w, h)
	W.LayoutContent(f)
	f:SetClampedToScreen(true); f:SetToplevel(true)
	f:SetFrameStrata("MEDIUM")                           -- real strata assigned by FocusWindow
	f:EnableMouse(true)
	if opts.movable ~= false then
		f:SetMovable(true); f:RegisterForDrag("LeftButton")
		f:SetScript("OnDragStart", f.StartMoving)        -- OnMouseDown (registry hook) already focused it
		f:SetScript("OnDragStop",  f.StopMovingOrSizing)
	end
	if opts.escape ~= false and name then
		local present = false
		for _, n in ipairs(UISpecialFrames) do
			if n == name then present = true; break end
		end
		if not present then tinsert(UISpecialFrames, name) end
	end
	f:Hide()
	if opts.floater ~= false and CommDKP.RegisterFloater then CommDKP:RegisterFloater(f, opts.group) end
	return f, f.Content
end

-------------------------------------
-- Checkbox (§12.2.5, B6)
-------------------------------------
-- AD-19.2 (012c) (c) / UX §13.1.2 (c): two independent checked cues (amber fill + trim edge, bright glyph).
local function PaintCheck(cb)
	if not cb.cdkpBoxFill then return end
	local on = cb:IsEnabled()
	local over = on and cb.IsMouseOver and cb:IsMouseOver()
	local checked = cb.GetChecked and cb:GetChecked() and true or false
	local fill = checked and (over and W.CHECK_FILL_ON_HOVER or W.CHECK_FILL_ON) or (over and C("bg2") or C("bg0"))
	cb.cdkpBoxFill:SetColorTexture(unpack(fill))
	CommDKP:SetPixelBorderColor(cb.cdkpBoxEdges, (checked or over) and C("trim") or C("trimQuiet"))
	if cb.cdkpCheck then cb.cdkpCheck:SetVertexColor(unpack(W.CHECK_GLYPH)) end
	if cb.cdkpCheckDisabled then cb.cdkpCheckDisabled:SetVertexColor(unpack(W.CHECK_GLYPH)) end
	if cb.SetAlpha then cb:SetAlpha(on and 1 or W.CHECK_DISABLED_ALPHA) end
end

local function UpdateCheckHit(cb)
	local lbl = cb.text or cb.Text
	local lw = (lbl and lbl.GetStringWidth and lbl:GetStringWidth()) or 0
	if cb.SetHitRectInsets then cb:SetHitRectInsets(0, -(lw + 6), -3, -3) end
end

-- Idempotent re-skin of an existing CheckButton (XML / template-built / kit-built).
function W.StyleCheckButton(cb, label)
	if not cb then return end
	if not cb.cdkpStyled then
		if cb.SetNormalTexture then
			if cb.ClearNormalTexture then cb:ClearNormalTexture() else cb:SetNormalTexture("") end
			if cb.ClearPushedTexture then cb:ClearPushedTexture() else cb:SetPushedTexture("") end
			if cb.ClearHighlightTexture then cb:ClearHighlightTexture() else cb:SetHighlightTexture("") end
			if cb.ClearDisabledCheckedTexture then cb:ClearDisabledCheckedTexture()
			elseif cb.SetDisabledCheckedTexture then cb:SetDisabledCheckedTexture("") end
		end
		-- AD-19.2 (012c) (c): `box` is an invisible layout anchor only. Fill, edges and glyphs are textures on the
		-- CheckButton itself, so no child frame can draw over the checked glyph (UX §13.1.1 (1)).
		local box = CreateFrame("Frame", nil, cb)
		box:SetSize(W.CHECK_SIZE, W.CHECK_SIZE)
		box:SetPoint("LEFT", cb, "LEFT", 0, 0)
		if box.EnableMouse then box:EnableMouse(false) end
		cb.cdkpBox = box
		cb.cdkpBoxFill = cb:CreateTexture(nil, "BACKGROUND")
		cb.cdkpBoxFill:SetAllPoints(box)
		if cb.cdkpBoxFill.SetSnapToPixelGrid then cb.cdkpBoxFill:SetSnapToPixelGrid(false); cb.cdkpBoxFill:SetTexelSnappingBias(0) end
		cb.cdkpBoxEdges = CommDKP:CreatePixelBorder(cb, C("trimQuiet"), box)
		box.Fill, box.Edges = cb.cdkpBoxFill, cb.cdkpBoxEdges   -- compat aliases
		local chk = cb:CreateTexture(nil, "OVERLAY")
		chk:SetSize(W.CHECK_GLYPH_SIZE, W.CHECK_GLYPH_SIZE)
		chk:SetPoint("CENTER", box, "CENTER", 0, 0)
		chk:SetTexture(W.TEX.check)
		cb.cdkpCheck = chk
		cb:SetCheckedTexture(chk)
		local dchk = cb:CreateTexture(nil, "OVERLAY")
		dchk:SetSize(W.CHECK_GLYPH_SIZE, W.CHECK_GLYPH_SIZE)
		dchk:SetPoint("CENTER", box, "CENTER", 0, 0)
		dchk:SetTexture(W.TEX.check)
		cb.cdkpCheckDisabled = dchk
		if cb.SetDisabledCheckedTexture then cb:SetDisabledCheckedTexture(dchk) end   -- BR-12.1.3: disabled+checked keeps its glyph
		local lbl = cb.text or cb.Text
		if not lbl then
			local n = cb.GetName and cb:GetName()
			lbl = cb:CreateFontString(n and (n .. "Text") or nil, "OVERLAY", W.FONT.body)
		end
		lbl:ClearAllPoints()
		lbl:SetPoint("LEFT", box, "RIGHT", 6, 0)
		lbl:SetFontObject(W.FONT.body)
		lbl:SetJustifyH("LEFT")
		lbl:SetTextColor(unpack(C("text")))
		cb.text, cb.Text = lbl, lbl
		KeepHooks(cb, { "OnEnter", "OnLeave", "OnEnable", "OnDisable", "OnShow", "OnClick" }, PaintCheck)
		KeepHooks(cb, { "OnShow" }, UpdateCheckHit)
		if hooksecurefunc then hooksecurefunc(cb, "SetChecked", PaintCheck) end   -- programmatic toggles repaint (AD-19.2 (c))
		cb.cdkpStyled = true
	end
	if label ~= nil then cb.text:SetText(SafeText(label)) end
	UpdateCheckHit(cb)
	PaintCheck(cb)
	return cb
end
W.StyleCheckbox = W.StyleCheckButton

-- Template-free CheckButton (no UICheckButtonTemplate). cb.text == cb.Text; label named name.."Text" (template parity).
function W.CreateCheckbox(parent, name, labelText, onClick)
	local cb = CreateFrame("CheckButton", name, parent)
	cb:SetSize(16, 16)
	local lbl = cb:CreateFontString(name and (name .. "Text") or nil, "OVERLAY", W.FONT.body)   -- global name..'Text' (template parity)
	cb.text, cb.Text = lbl, lbl
	W.StyleCheckButton(cb, labelText or "")
	if onClick then cb:SetScript("OnClick", onClick) end
	return cb
end

-------------------------------------
-- Edit box (§12.2.6, B5, B11)
-------------------------------------
local function PaintEdit(eb)
	if not eb.cdkpEdges then return end
	local focused = eb.HasFocus and eb:HasFocus()
	local over = (not focused) and eb.cdkpHover
	eb.cdkpFill:SetColorTexture(unpack(over and C("bg3") or C("bg1")))
	CommDKP:SetPixelBorderColor(eb.cdkpEdges, focused and C("trim") or (over and C("trimQuiet")) or C("line"))
	local ph = eb.cdkpPlaceholder
	if ph then
		local empty = (eb:GetText() or "") == ""
		ph:SetShown(empty and not focused and true or false)
	end
end

-- opts = { placeholder?, align = "LEFT"|"RIGHT"|"CENTER", numeric? (alignment only, B11), keepSize? }
-- Keeps the same EditBox: GetText/SetText/GetNumber/SetNumber, SetNumeric state (never changed), every script
-- (HookScript only). Call AFTER the call site's own SetScript calls so the hooks chain onto them.
function W.StyleEditBox(eb, opts)
	if not eb then return end
	opts = opts or {}
	if not eb.cdkpStyled then
		if eb.ClearBackdrop then eb:ClearBackdrop() end           -- retire the BackdropTemplate box (no SetBackdrop)
		eb.cdkpFill = eb:CreateTexture(nil, "BACKGROUND")
		eb.cdkpFill:SetAllPoints()
		eb.cdkpEdges = CommDKP:CreatePixelBorder(eb, C("line"))
		if eb.SetTextInsets then eb:SetTextInsets(5, 5, 0, 0) end
		if eb.SetFontObject then eb:SetFontObject(W.FONT.body) end
		if eb.SetTextColor then eb:SetTextColor(unpack(C("text"))) end
		if not opts.keepSize and eb.SetHeight then eb:SetHeight(W.H) end
		KeepHooks(eb, { "OnEditFocusGained", "OnEditFocusLost", "OnTextChanged", "OnShow" }, PaintEdit)
		KeepHooks(eb, { "OnEnter" }, function(self) self.cdkpHover = true; PaintEdit(self) end)
		KeepHooks(eb, { "OnLeave" }, function(self) self.cdkpHover = false; PaintEdit(self) end)
		eb.cdkpStyled = true
	end
	if opts.placeholder ~= nil then
		if not eb.cdkpPlaceholder then
			eb.cdkpPlaceholder = W.CreateText(eb, "caption", nil, "LEFT", "textDisabled")
			eb.cdkpPlaceholder:SetPoint("LEFT", eb, "LEFT", 5, 0)
			eb.cdkpPlaceholder:SetPoint("RIGHT", eb, "RIGHT", -5, 0)
		end
		eb.cdkpPlaceholder:SetText(SafeText(opts.placeholder))
	end
	local align = opts.align or (opts.numeric and "RIGHT") or nil
	if align and eb.SetJustifyH then eb:SetJustifyH(align) end
	PaintEdit(eb)
	return eb
end

-- Multi-line read-only output (Export). box.EditBox, box:SetText(s), box:HighlightText().
function W.CreateReadOnlyTextBox(parent, w, h)
	local box = CreateFrame("Frame", nil, parent)
	box:SetSize(w, h)
	box.Fill = box:CreateTexture(nil, "BACKGROUND")
	box.Fill:SetAllPoints(); box.Fill:SetColorTexture(unpack(C("bg0")))
	box.Edges = CommDKP:CreatePixelBorder(box, C("line"))
	local sf = W.CreateScrollRegion(box, { step = 40 })
	sf:SetPoint("TOPLEFT", box, "TOPLEFT", 4, -4)
	sf:SetPoint("BOTTOMRIGHT", box, "BOTTOMRIGHT", -14, 4)
	local eb = CreateFrame("EditBox", nil, sf.ScrollChild)
	eb:SetMultiLine(true)
	eb:SetAutoFocus(false)
	eb:SetFontObject(W.FONT.caption)
	eb:SetWidth(w - 22)
	eb:SetPoint("TOPLEFT", sf.ScrollChild, "TOPLEFT", 0, 0)
	eb:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
	eb:SetScript("OnTextChanged", function(self, userInput)
		if userInput and box.cdkpText then self:SetText(box.cdkpText); self:HighlightText() end   -- read-only
		if sf.UpdateRail then sf:UpdateRail() end
	end)
	box.EditBox, box.ScrollFrame = eb, sf
	function box:SetText(s) self.cdkpText = SafeText(s); self.EditBox:SetText(self.cdkpText) end
	function box:GetText() return self.EditBox:GetText() end
	function box:HighlightText(...) self.EditBox:HighlightText(...) end
	return box
end

-------------------------------------
-- Sliders (§12.2.9)
-------------------------------------
-- Re-skins CommDKPOptionsSliderTemplate instances. Keeps GetValue/SetValue, OnValueChanged (hooks only),
-- and the .Text / .Low / .High FontStrings (Low/High are hidden, not removed).
function W.StyleSlider(s)
	if not s or s.cdkpStyled then return s end
	if s.ClearBackdrop then s:ClearBackdrop() end
	local track = CreateFrame("Frame", nil, s)
	track:SetPoint("LEFT", s, "LEFT", 0, 0)
	track:SetPoint("RIGHT", s, "RIGHT", 0, 0)
	track:SetHeight(4)
	track.Fill = track:CreateTexture(nil, "BACKGROUND")
	track.Fill:SetAllPoints(); track.Fill:SetColorTexture(unpack(C("bg3")))
	track.Edges = CommDKP:CreatePixelBorder(track, C("line"))
	if track.SetFrameLevel and s.GetFrameLevel then track:SetFrameLevel(math.max(0, (s:GetFrameLevel() or 1) - 1)) end
	s.cdkpTrack = track
	local thumb = s.GetThumbTexture and s:GetThumbTexture()
	if not thumb then thumb = s:CreateTexture(nil, "OVERLAY"); s:SetThumbTexture(thumb) end
	thumb:SetTexture(nil)
	thumb:SetColorTexture(unpack(C("trim")))
	thumb:SetSize(10, 14)
	local inner = s:CreateTexture(nil, "OVERLAY", nil, 1)
	inner:SetPoint("TOPLEFT", thumb, "TOPLEFT", 1, -1)
	inner:SetPoint("BOTTOMRIGHT", thumb, "BOTTOMRIGHT", -1, 1)
	inner:SetColorTexture(unpack(C("bg4")))
	local fill = s:CreateTexture(nil, "ARTWORK")
	fill:SetPoint("TOPLEFT", track, "TOPLEFT", 1, -1)
	fill:SetPoint("BOTTOMLEFT", track, "BOTTOMLEFT", 1, 1)
	fill:SetPoint("RIGHT", thumb, "CENTER", 0, 0)
	fill:SetColorTexture(unpack(C("trimQuiet")))
	s.cdkpThumb, s.cdkpThumbInner, s.cdkpFillBar = thumb, inner, fill
	local n = s.GetName and s:GetName()
	s.Text = s.Text or (n and _G[n .. "Text"]) or nil
	s.Low  = s.Low  or (n and _G[n .. "Low"]) or nil
	s.High = s.High or (n and _G[n .. "High"]) or nil
	if s.Low and s.Low.Hide then s.Low:Hide() end
	if s.High and s.High.Hide then s.High:Hide() end
	if s.Text and s.Text.SetFontObject then s.Text:SetFontObject(W.FONT.label) end
	s.cdkpStyled = true
	return s
end

function W.CreateSlider(parent, name, minV, maxV, step, width)
	local tmpl = W.HasTemplate("CommDKPOptionsSliderTemplate") and "CommDKPOptionsSliderTemplate" or nil
	local s = CreateFrame("Slider", name, parent, tmpl)
	s:SetOrientation("HORIZONTAL")
	s:SetSize(width or 144, 14)
	s:SetMinMaxValues(minV or 0, maxV or 100)
	if s.SetValueStep then s:SetValueStep(step or 1) end
	if s.SetObeyStepOnDrag then s:SetObeyStepOnDrag(true) end
	if not s.Text then s.Text = W.CreateText(s, "label"); s.Text:SetPoint("BOTTOM", s, "TOP", 0, 2) end
	if not s.Low then s.Low = W.CreateText(s, "caption"); s.Low:SetPoint("TOPLEFT", s, "BOTTOMLEFT", 0, -2) end
	if not s.High then s.High = W.CreateText(s, "caption"); s.High:SetPoint("TOPRIGHT", s, "BOTTOMRIGHT", 0, -2) end
	s.Low:SetText(SafeText(minV)); s.High:SetText(SafeText(maxV))
	return W.StyleSlider(s)
end

-------------------------------------
-- Thin scroll rail (§12.2.8, AD-16.2 (f))
-------------------------------------
-- 6 px track (bg0 + 1 px rule) with a 4 px trimQuiet thumb (trim on hover/drag). Placed right of `anchorTo`.
function W.CreateRail(parent, anchorTo)
	local rail = CreateFrame("Slider", nil, parent)
	rail:SetOrientation("VERTICAL")
	rail:SetWidth(6)
	if anchorTo then
		rail:SetPoint("TOPLEFT", anchorTo, "TOPRIGHT", 4, 0)
		rail:SetPoint("BOTTOMLEFT", anchorTo, "BOTTOMRIGHT", 4, 0)
	end
	rail.Track = rail:CreateTexture(nil, "BACKGROUND")
	rail.Track:SetAllPoints(); rail.Track:SetColorTexture(unpack(C("bg0")))
	rail.Edges = CommDKP:CreatePixelBorder(rail, C("rule"))
	local thumb = rail:CreateTexture(nil, "OVERLAY")
	thumb:SetColorTexture(unpack(C("trimQuiet")))
	thumb:SetSize(4, 18)
	rail:SetThumbTexture(thumb)
	rail.Thumb = thumb
	rail:SetMinMaxValues(0, 0)
	rail:SetValue(0)
	rail:SetScript("OnEnter", function(self) self.Thumb:SetColorTexture(unpack(C("trim"))) end)
	rail:SetScript("OnLeave", function(self)
		if not self.cdkpDragging then self.Thumb:SetColorTexture(unpack(C("trimQuiet"))) end
	end)
	rail:SetScript("OnMouseDown", function(self) self.cdkpDragging = true; self.Thumb:SetColorTexture(unpack(C("trim"))) end)
	rail:SetScript("OnMouseUp", function(self) self.cdkpDragging = false; self.Thumb:SetColorTexture(unpack(C("trimQuiet"))) end)
	-- thumb length = viewport / (viewport + range), min 18
	function rail:SetViewport(view, range)
		local h = (self.GetHeight and self:GetHeight()) or 0
		if h > 0 and view and view > 0 then
			self.Thumb:SetHeight(math.max(18, math.floor(h * view / (view + math.max(0, range or 0)))))
		end
	end
	rail:Hide()
	return rail
end

-- Rail on a FauxScrollFrameTemplate frame. Zero change to row recycling: the template bar stays SHOWN and
-- functional (alpha 0, mouse off); FauxScrollFrame_Update / OnVerticalScroll / the wheel keep driving it.
function W.AttachFauxRail(sf, host)
	if not sf or sf.cdkpRail then return sf and sf.cdkpRail end
	local n = sf.GetName and sf:GetName()
	local sb = sf.ScrollBar or (n and _G[n .. "ScrollBar"])
	if not sb then return nil end
	sb:SetAlpha(0); sb:EnableMouse(false)
	for _, k in ipairs({ "ScrollUpButton", "ScrollDownButton" }) do
		local bn = sb.GetName and sb:GetName()
		local b = sb[k] or (bn and _G[bn .. k])
		if b then b:SetAlpha(0); b:EnableMouse(false) end
	end
	local rail = W.CreateRail(host or sf:GetParent(), sf)
	local syncing
	local function sync()
		local lo, hi = sb:GetMinMaxValues()
		lo, hi = lo or 0, hi or 0
		rail:SetShown(hi > lo)                              -- hidden when nothing overflows
		syncing = true
		rail:SetMinMaxValues(lo, hi)
		if sb.GetValueStep and rail.SetValueStep then rail:SetValueStep(sb:GetValueStep() or 1) end
		rail:SetValue(sb:GetValue() or 0)
		syncing = false
		rail:SetViewport(sf.GetHeight and sf:GetHeight(), hi - lo)
	end
	sb:HookScript("OnMinMaxChanged", sync)               -- fired by FauxScrollFrame_Update
	sb:HookScript("OnValueChanged", sync)                -- wheel / programmatic scroll
	if rail.SetObeyStepOnDrag then rail:SetObeyStepOnDrag(true) end   -- row-quantized offsets
	rail:SetScript("OnValueChanged", function(_, v)       -- user drag -> the template bar -> the existing pipeline
		if not syncing then sb:SetValue(v) end
	end)
	rail:EnableMouseWheel(true)
	rail:SetScript("OnMouseWheel", function(_, delta)
		local h = sf.GetScript and sf:GetScript("OnMouseWheel")
		if h then h(sf, delta) end
	end)
	sf.cdkpRail = rail
	sf.cdkpRailSync = sync
	sync()
	return rail
end
W.AttachScrollRail = W.AttachFauxRail   -- (scrollFrame, hostCard?) convenience name

-- Rail on an existing template-free ScrollFrame (officer CommDKP_BidWindowTable). Its offset logic is untouched.
function W.AttachRegionRail(sf, host)
	if not sf or sf.cdkpRail then return sf and sf.cdkpRail end
	local rail = W.CreateRail(host or sf:GetParent(), sf)
	local syncing
	local function sync()
		local range = (sf.GetVerticalScrollRange and sf:GetVerticalScrollRange()) or 0
		rail:SetShown(range > 0)
		syncing = true
		rail:SetMinMaxValues(0, range)
		rail:SetValue((sf.GetVerticalScroll and sf:GetVerticalScroll()) or 0)
		syncing = false
		rail:SetViewport(sf.GetHeight and sf:GetHeight(), range)
	end
	sf:HookScript("OnScrollRangeChanged", sync)
	sf:HookScript("OnVerticalScroll", sync)
	rail:SetScript("OnValueChanged", function(_, v) if not syncing then sf:SetVerticalScroll(v) end end)
	rail:EnableMouseWheel(true)
	rail:SetScript("OnMouseWheel", function(_, delta)
		local h = sf.GetScript and sf:GetScript("OnMouseWheel")
		if h then h(sf, delta) end
	end)
	sf.cdkpRail, sf.cdkpRailSync = rail, sync
	sync()
	return rail
end

-- Template-free ScrollFrame (replaces UIPanelScrollFrameTemplate). sf.ScrollChild, sf.ScrollBar (= the rail Slider),
-- sf:UpdateRail(). opts = { name?, step = 40, fades = true }
function W.CreateScrollRegion(parent, opts)
	opts = opts or {}
	local step = opts.step or 40
	local sf = CreateFrame("ScrollFrame", opts.name, parent)
	local child = CreateFrame("Frame", nil, sf)
	child:SetSize(1, 1)
	sf:SetScrollChild(child)
	sf.ScrollChild = child
	sf:EnableMouseWheel(true)
	local rail = W.CreateRail(parent, sf)
	sf.ScrollBar = rail
	local syncing
	function sf:UpdateRail()
		local range = (self.GetVerticalScrollRange and self:GetVerticalScrollRange()) or 0
		local scrolls = range > 1                                   -- AD-19 R2 / BR-12.11.3: <= 1 unit is "fits" -> rail hidden
		rail:SetShown(scrolls)
		if not scrolls and (self:GetVerticalScroll() or 0) ~= 0 then self:SetVerticalScroll(0) end   -- re-enters once, then stable
		syncing = true
		rail:SetMinMaxValues(0, range)
		rail:SetValue(self:GetVerticalScroll() or 0)
		syncing = false
		rail:SetViewport(self:GetHeight(), range)
		if self.cdkpFadeTop then
			local cur = self:GetVerticalScroll() or 0
			self.cdkpFadeTop:SetShown(scrolls and cur > 0)
			self.cdkpFadeBottom:SetShown(scrolls and cur < range)
		end
	end
	sf:SetScript("OnScrollRangeChanged", function(self) self:UpdateRail() end)
	sf:SetScript("OnVerticalScroll", function(self) self:UpdateRail() end)
	sf:SetScript("OnMouseWheel", function(self, delta)
		local range = (self.GetVerticalScrollRange and self:GetVerticalScrollRange()) or 0
		local v = math.max(0, math.min(range, (self:GetVerticalScroll() or 0) - delta * step))
		self:SetVerticalScroll(v)
		self:UpdateRail()
	end)
	sf:SetScript("OnSizeChanged", function(self, w)
		local sc = (self.GetScrollChild and self:GetScrollChild()) or child   -- tab panes swap the child (ShowTabPane)
		if w and w > 0 and sc then sc:SetWidth(w) end
		self:UpdateRail()
	end)
	rail:SetScript("OnValueChanged", function(_, v) if not syncing then sf:SetVerticalScroll(v); sf:UpdateRail() end end)
	rail:EnableMouseWheel(true)
	rail:SetScript("OnMouseWheel", function(_, delta) sf:GetScript("OnMouseWheel")(sf, delta) end)
	if opts.fades ~= false then
		local sc = C("edgeShadow")
		local top = sf:CreateTexture(nil, "OVERLAY")
		top:SetPoint("TOPLEFT"); top:SetPoint("TOPRIGHT"); top:SetHeight(10)
		top:SetColorTexture(1, 1, 1, 1)
		if top.SetGradient and CreateColor then
			pcall(top.SetGradient, top, "VERTICAL", CreateColor(sc[1], sc[2], sc[3], 0), CreateColor(sc[1], sc[2], sc[3], sc[4]))
		else
			top:SetColorTexture(sc[1], sc[2], sc[3], sc[4] / 2)
		end
		local bot = sf:CreateTexture(nil, "OVERLAY")
		bot:SetPoint("BOTTOMLEFT"); bot:SetPoint("BOTTOMRIGHT"); bot:SetHeight(10)
		bot:SetColorTexture(1, 1, 1, 1)
		if bot.SetGradient and CreateColor then
			pcall(bot.SetGradient, bot, "VERTICAL", CreateColor(sc[1], sc[2], sc[3], sc[4]), CreateColor(sc[1], sc[2], sc[3], 0))
		else
			bot:SetColorTexture(sc[1], sc[2], sc[3], sc[4] / 2)
		end
		top:Hide(); bot:Hide()
		sf.cdkpFadeTop, sf.cdkpFadeBottom = top, bot
	end
	return sf
end

-- Grows a scroll child so its range covers `last` (the bottom-most entry) plus `pad`. Layout-only; call after the
-- entries are anchored. No-op until both rects resolve (window hidden).
function W.FitScrollChild(child, last, pad)
	if not (child and last and child.GetTop and last.GetBottom) then return end
	local top, bottom = child:GetTop(), last:GetBottom()
	if top and bottom then child:SetHeight(math.max(1, top - bottom + (pad or 0))) end
end

-------------------------------------
-- Table rows, column strip (§12.2.10)
-------------------------------------
-- name? keeps a legacy global header-frame name (so "$parent..." sort-button names still resolve).
function W.CreateColumnStrip(parent, h, name)
	local s = CreateFrame("Frame", name, parent)
	s:SetHeight(h or 24)
	s.Fill = s:CreateTexture(nil, "BACKGROUND")
	s.Fill:SetAllPoints(); s.Fill:SetColorTexture(0, 0, 0, 0.18)
	s.Rule = s:CreateTexture(nil, "BORDER")
	s.Rule:SetPoint("BOTTOMLEFT"); s.Rule:SetPoint("BOTTOMRIGHT"); SetOnePixel(s.Rule, true)
	s.Rule:SetColorTexture(unpack(C("line")))
	return s
end

-- Stripe (odd rows) + hover fill; idempotent. Existing row frames and their scripts are kept (HookScript).
local function RowHoverOn(self) if self.cdkpHover then self.cdkpHover:Show() end end
local function RowHoverOff(self) if self.cdkpHover and not self.cdkpSelected then self.cdkpHover:Hide() end end
function W.StyleRow(row, index)
	if not row then return end
	if not row.cdkpRowStyled then
		row.cdkpStripe = row:CreateTexture(nil, "BACKGROUND", nil, 1)
		row.cdkpStripe:SetAllPoints(); row.cdkpStripe:SetColorTexture(unpack(C("stripe")))
		row.cdkpHover = row:CreateTexture(nil, "BACKGROUND", nil, 2)
		row.cdkpHover:SetAllPoints(); row.cdkpHover:SetColorTexture(unpack(C("bg3"))); row.cdkpHover:Hide()
		-- Faux-table rows get their OnEnter/OnLeave (tooltips) re-SetScript on every refresh: KeepHooks re-attaches.
		KeepHooks(row, { "OnEnter" }, RowHoverOn)
		KeepHooks(row, { "OnLeave" }, RowHoverOff)
		row.cdkpRowStyled = true
	end
	row.cdkpStripe:SetShown(index ~= nil and (index % 2 == 1) or false)
	return row
end

-- isAlt convenience form: W.StyleTableRow(row, true) == stripe.
function W.StyleTableRow(row, isAlt)
	return W.StyleRow(row, isAlt and 1 or 0)
end

-- Selected row: bg3 fill + 1 px trim pixel border (replaces ListBox-Highlight).
function W.SetRowSelected(row, selected)
	if not row then return end
	if not row.cdkpRowStyled then W.StyleRow(row, nil) end
	if not row.cdkpSelEdges then
		row.cdkpSelEdges = CommDKP:CreatePixelBorder(row, C("trim"))
	end
	row.cdkpSelected = selected and true or false
	for _, t in ipairs(row.cdkpSelEdges) do t:SetShown(row.cdkpSelected) end
	row.cdkpHover:SetShown(row.cdkpSelected or (row.IsMouseOver and row:IsMouseOver()) or false)
end

-------------------------------------
-- Sync status pip (§12.2.11)
-------------------------------------
-- Keeps the SeedVerify frame and its OnEnter/OnLeave; only adds art. iconTex is the existing SeedVerifyIcon.
function W.StyleStatusPip(frame, icon)
	if not frame or frame.cdkpPip then return icon end
	local ring = frame:CreateTexture(nil, "BACKGROUND")
	ring:SetSize(16, 16); ring:SetPoint("CENTER")
	ring:SetTexture(W.TEX.pip); ring:SetVertexColor(unpack(C("trimQuiet")))
	if icon then
		icon:ClearAllPoints()
		icon:SetSize(10, 10); icon:SetPoint("CENTER", frame, "CENTER", 0, 0)
		icon:SetTexture(W.TEX.pip)
		if icon.SetDrawLayer then icon:SetDrawLayer("ARTWORK") end
	end
	local hl = frame:CreateTexture(nil, "OVERLAY")
	hl:SetSize(4, 4); hl:SetPoint("CENTER", frame, "CENTER", -1.5, 1.5)
	hl:SetTexture(W.TEX.pip); hl:SetVertexColor(1, 1, 1, 0.45)
	frame.cdkpPip = { ring = ring, fill = icon, highlight = hl }
	return icon
end

-- ood == true -> negative (out of date); false -> positive (in sync).
function W.SetPipState(icon, ood)
	if not icon then return end
	icon:SetVertexColor(unpack(ood and C("negative") or C("positive")))
end

-------------------------------------
-- Notes, captions, progress (§12.2.12)
-------------------------------------
function W.CreateWarnNote(parent, text)
	local n = CreateFrame("Frame", nil, parent)
	local wc = C("warning")
	n.Fill = n:CreateTexture(nil, "BACKGROUND")
	n.Fill:SetAllPoints(); n.Fill:SetColorTexture(wc[1], wc[2], wc[3], 0.07)
	n.Edges = CommDKP:CreatePixelBorder(n, { wc[1], wc[2], wc[3], 0.45 })
	n.Bar = n:CreateTexture(nil, "BORDER", nil, 1)
	n.Bar:SetPoint("TOPLEFT"); n.Bar:SetPoint("BOTTOMLEFT"); n.Bar:SetWidth(2)
	n.Bar:SetColorTexture(unpack(wc))
	local glyph = "Interface\\DialogFrame\\UI-Dialog-Icon-AlertNew"
	local textLeft = 8
	if not GetFileIDFromPath or GetFileIDFromPath(glyph) then
		n.Icon = n:CreateTexture(nil, "ARTWORK")
		n.Icon:SetSize(14, 14); n.Icon:SetPoint("TOPLEFT", n, "TOPLEFT", 8, -8)
		n.Icon:SetTexture(glyph)
		textLeft = 28
	end
	n.Text = W.CreateText(n, "caption", text, "LEFT", "warning")
	n.Text:SetPoint("TOPLEFT", n, "TOPLEFT", textLeft, -8)
	n.Text:SetPoint("RIGHT", n, "RIGHT", -8, 0)
	if n.Text.SetWordWrap then n.Text:SetWordWrap(true) end
	if n.Text.SetSpacing then n.Text:SetSpacing(2) end
	function n:Fit()
		local lines = (self.Text.GetNumLines and self.Text:GetNumLines()) or 1
		self:SetHeight(math.max(1, lines) * 13 + 16)
	end
	n:Fit()
	return n
end

-- AD-19.2 (012c) (d) / BR-12.3: captions are never truncated. maxLines is a sizing hint only (kept for callers).
function W.CreateCaption(parent, text, maxLines)
	local fs = W.CreateText(parent, "caption", text, "LEFT", "textMuted")
	if fs.SetWordWrap then fs:SetWordWrap(true) end
	return fs
end

function W.CreateProgressBar(parent, w, h)
	local holder = CreateFrame("Frame", nil, parent)
	holder:SetSize(w, h)
	holder.Fill = holder:CreateTexture(nil, "BACKGROUND")
	holder.Fill:SetAllPoints(); holder.Fill:SetColorTexture(unpack(C("bg3")))
	holder.Edges = CommDKP:CreatePixelBorder(holder, C("line"))
	local bar = CreateFrame("StatusBar", nil, holder)
	bar:SetPoint("TOPLEFT", holder, "TOPLEFT", 1, -1)
	bar:SetPoint("BOTTOMRIGHT", holder, "BOTTOMRIGHT", -1, 1)
	bar:SetStatusBarTexture("Interface\\Buttons\\WHITE8X8")
	bar:SetStatusBarColor(unpack(C("trimQuiet")))
	bar:SetMinMaxValues(0, 100); bar:SetValue(0)
	bar.Text = W.CreateText(bar, "caption", "", "CENTER")
	bar.Text:SetPoint("CENTER", holder, "CENTER", 0, 0)
	bar.Holder = holder
	return bar
end

-------------------------------------
-- Selector dropdown (§12.2.7, AD-16.3) + the CommDKP.DD LibDD-protocol adapter
-------------------------------------
-- Rows are collected by running the call site's own initializer (byte-for-byte unchanged) while a collect
-- context is active; DD:UIDropDownMenu_AddButton appends to it instead of LibDD's shared L_DropDownList frames.
-- Row fields honored (AD-16.3 (b)3): text, value, arg1, arg2, func, checked, isTitle, notCheckable, notClickable,
-- disabled, hasArrow, menuList, keepShownOnClick, isNotRadio, colorCode, tooltipTitle/Text/OnButton, icon, justifyH.
-- AD-16.3 (e) R1: `fontObject` is ACCEPTED AND IGNORED (never read here); every row renders in W.FONT.body and
-- isTitle rows in gold W.FONT.label. Call sites delete their `X.fontObject = ...` line when they move to DD:.
local collecting = nil           -- { rows = {} } while an initializer runs in collect mode
local panels = {}                -- one pooled list panel per level
local catcher                    -- full-screen insecure click-catcher behind the panels
local openOwner                  -- the Forever dropdown whose list is open

local function Lib()
	if W._lib == nil and LibStub then
		local ok, lib = pcall(LibStub.GetLibrary, LibStub, "LibUIDropDownMenu-4.0", true)
		W._lib = (ok and lib) or false
	end
	return W._lib or nil
end

local function Collect(dd, level, menuList, value)
	local rows = {}
	if not dd.cdkpInit then return rows end
	local prev = collecting
	local savedValue, savedLevel = L_UIDROPDOWNMENU_MENU_VALUE, L_UIDROPDOWNMENU_MENU_LEVEL
	L_UIDROPDOWNMENU_MENU_VALUE, L_UIDROPDOWNMENU_MENU_LEVEL = value, level
	collecting = { rows = rows, level = level }
	local ok, err = pcall(dd.cdkpInit, dd, level, menuList)
	collecting = prev
	L_UIDROPDOWNMENU_MENU_VALUE, L_UIDROPDOWNMENU_MENU_LEVEL = savedValue, savedLevel
	if not ok then
		local h = geterrorhandler and geterrorhandler()
		if h then h(err) end
	end
	return rows
end
W._Collect = Collect

local function PaintDropdown(dd)
	if not dd.cdkpEdges then return end
	local on = dd:IsEnabled()
	local open = (openOwner == dd)
	local over = on and (open or (dd.IsMouseOver and dd:IsMouseOver()))
	dd.cdkpFill:SetColorTexture(unpack(over and C("bg3") or C("bg2")))
	CommDKP:SetPixelBorderColor(dd.cdkpEdges, over and C("trim") or C("line"))
	dd.Text:SetTextColor(unpack(on and C("text") or C("textDisabled")))
	dd.Caret:SetVertexColor(unpack(on and C("gold") or C("textDisabled")))
	if open then dd.Caret:SetTexCoord(0, 1, 1, 0) else dd.Caret:SetTexCoord(0, 1, 0, 1) end
end

local CloseLevels   -- forward

local function EnsureCatcher()
	if catcher then return catcher end
	catcher = CreateFrame("Button", nil, UIParent)
	catcher:SetAllPoints(UIParent)
	catcher:SetFrameStrata(W.LIST_STRATA)
	catcher:SetFrameLevel(W.LIST_CATCHER_LEVEL)
	catcher:EnableMouse(true)
	if catcher.RegisterForClicks then catcher:RegisterForClicks("AnyUp", "AnyDown") end
	catcher:SetScript("OnMouseDown", function() CloseLevels(1) end)
	catcher:Hide()
	return catcher
end

-- AD-32.1: the exact string RenderPanel draws (colour codes have no width), the font the row draws it in, and its
-- natural (unconstrained) width. GetUnboundedStringWidth is the 12.x API (it ignores any width/anchor constraint);
-- GetStringWidth is the fallback. On an unanchored, hidden probe the two return the same value.
local function RowText(info)
	local txt = SafeText(info.text)
	if info.colorCode then txt = info.colorCode .. txt .. "|r" end
	return txt
end
local function RowFont(info) return info.isTitle and W.FONT.label or W.FONT.body end
local function NaturalWidth(fs)
	local w = (fs.GetUnboundedStringWidth and fs:GetUnboundedStringWidth())
		or (fs.GetStringWidth and fs:GetStringWidth()) or 0
	return tonumber(w) or 0
end
W.NaturalWidth = NaturalWidth   -- exported for H134 / AD-32.2

-- AD-32.1.3 (BR-24.2): rows end LIST_INSET from the panel's right edge, plus the rail column when the list scrolls.
-- Re-applied whenever panel.scrolls changes (panels and rows are pooled per level and reused across dropdowns).
local function AnchorRow(row, panel, i)
	local y = -W.LIST_INSET - (i - 1) * W.LIST_ROW
	local right = W.LIST_INSET + (panel.scrolls and W.LIST_RAIL_COL or 0)
	row:ClearAllPoints()
	row:SetPoint("TOPLEFT", panel, "TOPLEFT", W.LIST_INSET, y)
	row:SetPoint("TOPRIGHT", panel, "TOPRIGHT", -right, y)
	row.cdkpRight = right
end

local function RowChecked(row)
	local info, dd = row.info, row.owner
	local c = info.checked
	if type(c) == "function" then c = c(row) end
	if c == nil and dd and dd.cdkpSelected ~= nil and info.value ~= nil and not info.notCheckable then
		c = (info.value == dd.cdkpSelected)
	end
	return c and true or false
end

local function PaintRow(row)
	local info = row.info
	if not info then return end
	local P = Pal()
	local checked = (not info.notCheckable and not info.isTitle) and RowChecked(row) or false
	row.checked = checked
	local multi = info.isNotRadio and info.keepShownOnClick and not info.notCheckable
	row.Box:SetShown(multi and true or false)
	if multi and row.Box.Fill and row.Box.Edges then
		row.Box.Fill:SetColorTexture(unpack(checked and W.CHECK_FILL_ON or C("bg0")))
		CommDKP:SetPixelBorderColor(row.Box.Edges, checked and C("trim") or C("trimQuiet"))
	end
	if row.Check then
		row.Check:SetVertexColor(unpack(multi and W.CHECK_GLYPH or C("gold")))
	end
	row.Check:SetShown(checked)
	if info.isTitle then
		row.Label:SetFontObject(W.FONT.label)
		row.Label:SetTextColor(unpack(P.gold))
	else
		row.Label:SetFontObject(W.FONT.body)
		local dis = info.disabled
		row.Label:SetTextColor(unpack(dis and P.textDisabled or (checked and P.gold) or P.text))
	end
	row.Arrow:SetShown(info.hasArrow and true or false)
end

local OpenLevel   -- forward

local function Row_OnEnter(row)
	local info = row.info
	if not info then return end
	if not (info.isTitle or info.disabled or info.notClickable) then row.Hover:Show() end
	local lvl = row.level
	if info.hasArrow and not info.disabled then
		OpenLevel(row.owner, lvl + 1, row, info)
	else
		CloseLevels(lvl + 1)
	end
	if (info.tooltipTitle or info.tooltipText) and info.tooltipOnButton and GameTooltip then
		GameTooltip:SetOwner(row, "ANCHOR_RIGHT")
		GameTooltip:SetText(SafeText(info.tooltipTitle or ""), 1, 0.82, 0)
		if info.tooltipText then GameTooltip:AddLine(SafeText(info.tooltipText), 1, 1, 1, true) end
		GameTooltip:Show()
	end
end

local function Row_OnLeave(row)
	row.Hover:Hide()
	if GameTooltip and GameTooltip.GetOwner and GameTooltip:GetOwner() == row then GameTooltip:Hide() end
end

-- Blizzard UIDropDownMenuButton_OnClick order (AD-16.3 (b) 4).
local function Row_OnClick(row)
	local info = row.info
	if not info or info.isTitle or info.disabled or info.notClickable then return end
	if info.hasArrow and not info.func then
		OpenLevel(row.owner, row.level + 1, row, info)
		return
	end
	local c = info.checked
	if type(c) == "function" then c = c(row) end
	if info.keepShownOnClick and not info.notCheckable then
		c = not c
	else
		CloseLevels(1)
	end
	if type(info.checked) ~= "function" then info.checked = c end
	-- Blizzard's list button also carries .menuList (LootHistory's FilterSetValue reads self.menuList).
	row.value, row.arg1, row.arg2, row.checked, row.menuList = info.value, info.arg1, info.arg2, c, info.menuList
	if info.func then info.func(row, info.arg1, info.arg2, c) end
	if info.keepShownOnClick and row:IsShown() then PaintRow(row) end
end

local function NewRow(panel, i)
	local row = CreateFrame("Button", nil, panel)
	row:SetHeight(W.LIST_ROW)
	AnchorRow(row, panel, i)
	row.Hover = row:CreateTexture(nil, "BACKGROUND")
	row.Hover:SetAllPoints(); row.Hover:SetColorTexture(unpack(C("bg3"))); row.Hover:Hide()
	row.Box = CreateFrame("Frame", nil, row)
	row.Box:SetSize(W.CHECK_SIZE, W.CHECK_SIZE); row.Box:SetPoint("LEFT", row, "LEFT", 4, 0)
	if row.Box.EnableMouse then row.Box:EnableMouse(false) end
	row.Box.Fill = row:CreateTexture(nil, "BACKGROUND", nil, 1)   -- AD-34.7 (F-34.1): above Hover (BG 0), below Edges (BORDER)
	row.Box.Fill:SetAllPoints(row.Box); row.Box.Fill:SetColorTexture(unpack(C("bg0")))
	if row.Box.Fill.SetSnapToPixelGrid then row.Box.Fill:SetSnapToPixelGrid(false); row.Box.Fill:SetTexelSnappingBias(0) end
	row.Box.Edges = CommDKP:CreatePixelBorder(row, C("trimQuiet"), row.Box)
	local rawBoxSetShown = row.Box.SetShown
	function row.Box:SetShown(v)
		local s = v and true or false
		if rawBoxSetShown then rawBoxSetShown(self, s) elseif s then self:Show() else self:Hide() end
		if self.Fill then self.Fill:SetShown(s) end
		if self.Edges then for _, t in ipairs(self.Edges) do t:SetShown(s) end end
	end
	row.Box:SetShown(false)
	row.Check = row:CreateTexture(nil, "OVERLAY")
	row.Check:SetSize(W.CHECK_GLYPH_SIZE, W.CHECK_GLYPH_SIZE); row.Check:SetPoint("CENTER", row.Box, "CENTER", 0, 0)
	row.Check:SetTexture(W.TEX.check); row.Check:SetVertexColor(unpack(C("gold")))
	row.Label = W.CreateText(row, "body", nil, "LEFT")
	row.Label:SetPoint("LEFT", row, "LEFT", W.LIST_GUTTER_L, 0)
	row.Label:SetPoint("RIGHT", row, "RIGHT", -W.LIST_GUTTER_R, 0)
	if row.Label.SetWordWrap then row.Label:SetWordWrap(false) end
	row.Icon = row:CreateTexture(nil, "ARTWORK")
	row.Icon:SetSize(14, 14); row.Icon:SetPoint("RIGHT", row.Label, "LEFT", -2, 0); row.Icon:Hide()
	row.Arrow = row:CreateTexture(nil, "OVERLAY")
	row.Arrow:SetSize(10, 10); row.Arrow:SetPoint("RIGHT", row, "RIGHT", -4, 0)
	row.Arrow:SetTexture(W.TEX.chevron); row.Arrow:SetVertexColor(unpack(C("gold")))
	if row.Arrow.SetRotation then row.Arrow:SetRotation(math.pi / 2) end
	row:SetScript("OnEnter", Row_OnEnter)
	row:SetScript("OnLeave", Row_OnLeave)
	row:SetScript("OnClick", Row_OnClick)
	return row
end

local function RenderPanel(panel)
	local data, offset = panel.data or {}, panel.offset or 0
	local right = W.LIST_INSET + (panel.scrolls and W.LIST_RAIL_COL or 0)
	local visible = math.min(#data, W.LIST_MAX_ROWS)
	for i = 1, W.LIST_MAX_ROWS do
		local row = panel.rows[i]
		local info = data[i + offset]
		if i <= visible and info then
			if not row then row = NewRow(panel, i); panel.rows[i] = row end
			if row.cdkpRight ~= right then AnchorRow(row, panel, i) end
			row.info, row.owner, row.level = info, panel.owner, panel.level
			row.value, row.arg1, row.arg2, row.menuList = info.value, info.arg1, info.arg2, info.menuList
			row.Label:SetText(RowText(info))
			row.Label:SetJustifyH(info.justifyH or "LEFT")
			if info.icon then row.Icon:SetTexture(info.icon); row.Icon:Show() else row.Icon:Hide() end
			row.Hover:Hide()
			PaintRow(row)
			row:Show()
		elseif row then
			row.info = nil
			row:Hide()
		end
	end
	if panel.rail then
		local range = math.max(0, #data - W.LIST_MAX_ROWS)
		panel.rail:SetShown(range > 0)
		panel.cdkpSyncing = true
		panel.rail:SetMinMaxValues(0, range)
		panel.rail:SetValue(offset)
		panel.cdkpSyncing = false
	end
end

local function GetPanel(level)
	local panel = panels[level]
	if panel then return panel end
	panel = CreateFrame("Frame", nil, UIParent, "BackdropTemplate")
	W.ApplyPlaqueEdge(panel)
	panel:SetFrameStrata(W.LIST_STRATA)
	panel:SetFrameLevel(W.LIST_PANEL_LEVEL + level * 10)
	panel:SetClampedToScreen(true)
	panel:EnableMouse(true)
	panel:EnableMouseWheel(true)
	panel.level, panel.rows, panel.offset = level, {}, 0
	panel:SetScript("OnMouseWheel", function(self, delta)
		local range = math.max(0, #(self.data or {}) - W.LIST_MAX_ROWS)
		self.offset = math.max(0, math.min(range, (self.offset or 0) - delta))
		RenderPanel(self)
	end)
	panel.rail = W.CreateRail(panel)
	panel.rail:SetPoint("TOPRIGHT", panel, "TOPRIGHT", -3, -4)
	panel.rail:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", -3, 4)
	if panel.rail.SetValueStep then panel.rail:SetValueStep(1) end
	panel.rail:SetScript("OnValueChanged", function(_, v)
		if panel.cdkpSyncing then return end
		panel.offset = math.floor((v or 0) + 0.5)
		RenderPanel(panel)
	end)
	panel:Hide()
	panels[level] = panel
	return panel
end

-- Closes Forever list levels >= level (1 = all).
CloseLevels = function(level)
	level = level or 1
	for lvl, panel in pairs(panels) do
		if lvl >= level and panel:IsShown() then panel:Hide() end
	end
	if level <= 1 then
		local owner = openOwner
		openOwner = nil
		if catcher then catcher:Hide() end
		if owner then PaintDropdown(owner) end
	end
end
W.CloseLists = function(level) CloseLevels(level) end

OpenLevel = function(dd, level, anchorRow, parentInfo)
	if not dd then return end
	CloseLevels(level + 1)
	local menuList = parentInfo and parentInfo.menuList or dd.menuList
	local value = parentInfo and parentInfo.value or nil
	local data = Collect(dd, level, menuList, value)
	local panel = GetPanel(level)
	panel.owner, panel.data, panel.offset, panel.dropdown = dd, data, 0, dd
	local scrolls = #data > W.LIST_MAX_ROWS
	panel.scrolls = scrolls                                                -- read by RenderPanel/AnchorRow (BR-24.2)
	-- AD-32.1 (BR-24.1): measure every row in the font it is drawn with, rounded up to whole UI units.
	local probe = panel.Probe or W.CreateText(panel, "body")               -- parented to the panel: same effective scale as the rows
	panel.Probe = probe; probe:Hide()
	local widest = 0
	for _, d in ipairs(data) do
		probe:SetFontObject(RowFont(d))
		probe:SetText(RowText(d))
		widest = math.max(widest, math.ceil(NaturalWidth(probe)))
	end
	local rowChrome = W.LIST_ROW_CHROME + (scrolls and W.LIST_RAIL_COL or 0) + W.LIST_SAFETY   -- 60, or 70 with the rail
	local minW = (level == 1) and math.max((dd.GetWidth and dd:GetWidth()) or W.LIST_MIN_W1, W.LIST_MIN_W1) or W.LIST_MIN_W
	local width = math.max(minW, widest + rowChrome)
	local screenW = (UIParent and UIParent.GetWidth and UIParent:GetWidth()) or 0
	if screenW > 0 and width > screenW then width = screenW end           -- the only cap: the screen (BR-24.1)
	panel:SetWidth(width)
	panel:SetHeight(math.min(#data, W.LIST_MAX_ROWS) * W.LIST_ROW + 8)
	panel:ClearAllPoints()
	if level == 1 or not anchorRow then
		panel:SetPoint("TOPLEFT", dd, "BOTTOMLEFT", 0, -2)
	else
		panel:SetPoint("TOPLEFT", anchorRow, "TOPRIGHT", 2, 0)
	end
	RenderPanel(panel)
	EnsureCatcher():Show()
	panel:Show()
	return panel
end

function W.OpenList(dd, level) return OpenLevel(dd, level or 1) end
function W.GetListPanel(level) return panels[level or 1] end

-- AD-32.2.3 (BR-24.3b): a closed button whose value is cut shows the full value on hover. It is appended to a
-- call-site tooltip when one is already up (owner == dd), otherwise it is the whole tooltip. Text from dd.Text is
-- addon-set (never a secret value); GameTooltip on an insecure addon button is combat-safe.
local function ClosedTextCut(dd)
	local fs = dd.Text
	local s = fs and fs:GetText()
	if s == nil or s == "" then return false end
	if fs.IsTruncated and fs:IsTruncated() then return true, s end
	local avail = (fs.GetWidth and fs:GetWidth()) or 0
	if avail <= 0 then avail = ((dd.GetWidth and dd:GetWidth()) or 0) - 25 end   -- RC-6: LEFT+6 .. Caret(10 @ -5) - 4
	return NaturalWidth(fs) > avail + 0.5, s
end
local function TruncTip_OnEnter(dd)
	if not GameTooltip then return end
	local cut, s = ClosedTextCut(dd)
	if not cut then return end
	if GameTooltip.GetOwner and GameTooltip:GetOwner() == dd and GameTooltip:IsShown() then
		GameTooltip:AddLine(s, 1, 1, 1, true)                 -- after the call-site's own title/lines
	else
		GameTooltip:SetOwner(dd, "ANCHOR_RIGHT")
		GameTooltip:SetText(s, 1, 1, 1, 1, true)
	end
	GameTooltip:Show()
	dd.cdkpTruncTip = true
end
local function TruncTip_OnLeave(dd)
	if dd.cdkpTruncTip and GameTooltip and GameTooltip.GetOwner and GameTooltip:GetOwner() == dd then GameTooltip:Hide() end
	dd.cdkpTruncTip = nil
end

-- opts = { name?, width?, height? = W.H }
function W.CreateDropdown(parent, opts)
	opts = opts or {}
	local dd = CreateFrame("Button", opts.name, parent)
	dd.cdkpForever = true
	dd:SetSize(opts.width or 150, opts.height or W.H)
	dd.cdkpFill = dd:CreateTexture(nil, "BACKGROUND")
	dd.cdkpFill:SetAllPoints()
	dd.cdkpEdges = CommDKP:CreatePixelBorder(dd, C("line"))
	dd.Caret = dd:CreateTexture(nil, "OVERLAY")
	dd.Caret:SetSize(10, 10); dd.Caret:SetPoint("RIGHT", dd, "RIGHT", -5, 0)
	dd.Caret:SetTexture(W.TEX.chevron)
	dd.Text = W.CreateText(dd, "body", nil, "LEFT")
	dd.Text:SetPoint("LEFT", dd, "LEFT", 6, 0)
	dd.Text:SetPoint("RIGHT", dd.Caret, "LEFT", -4, 0)
	if dd.Text.SetWordWrap then dd.Text:SetWordWrap(false) end
	-- Kit methods. No SetValue/GetValue (B2): those names belong to the call sites.
	function dd:SetText(s) self.Text:SetText(SafeText(s)) end
	function dd:GetText() return self.Text:GetText() end
	function dd:SetSelection(value, label)
		self.cdkpSelected = value
		if label ~= nil then self:SetText(label) end
	end
	function dd:GetSelection() return self.cdkpSelected end
	function dd:SetEnabled(on)
		if on then self:Enable() else self:Disable(); if openOwner == self then CloseLevels(1) end end
		PaintDropdown(self)
	end
	function dd:Open(level)
		if level == nil or level == 1 then
			local lib = Lib()
			if lib and lib.CloseDropDownMenus then lib:CloseDropDownMenus() end   -- never a context menu + a selector
			CloseLevels(1)
			openOwner = self
			OpenLevel(self, 1)
			PaintDropdown(self)
		end
	end
	function dd:Close() if openOwner == self then CloseLevels(1) end end
	function dd:IsOpen() return openOwner == self end
	dd:SetScript("OnClick", function(self)
		if not self:IsEnabled() then return end
		if openOwner == self then self:Close() else self:Open(1) end
	end)
	KeepHooks(dd, { "OnEnter", "OnLeave" }, PaintDropdown)   -- call sites SetScript tooltips afterwards
	KeepHooks(dd, { "OnEnter" }, TruncTip_OnEnter)   -- AD-32.2.3: KeepHooks re-hooks after any later call-site SetScript,
	KeepHooks(dd, { "OnLeave" }, TruncTip_OnLeave)   -- so this always runs AFTER the call-site tooltip handler
	KeepHooks(dd, { "OnHide" }, function(self) if openOwner == self then CloseLevels(1) end end)
	PaintDropdown(dd)
	return dd
end

-- CommDKP.DD: drop-in for the LibDD call protocol. Forever dropdowns (dd.cdkpForever) are served by the kit;
-- every other frame, and every method not listed here, passes through to LibUIDropDownMenu-4.0 unchanged.
local DD = {}
CommDKP.DD, W.DD = DD, DD
setmetatable(DD, { __index = function(_, k)
	local lib = Lib()
	local v = lib and lib[k]
	if type(v) == "function" then return function(_, ...) return v(lib, ...) end end
	return v
end })

local function isForever(dd) return type(dd) == "table" and dd.cdkpForever == true end
local function pass(method, ...)
	local lib = Lib()
	if lib and lib[method] then return lib[method](lib, ...) end
end

function DD:Create_UIDropDownMenu(name, parent)
	return W.CreateDropdown(parent, { name = name })
end

function DD:UIDropDownMenu_Initialize(dd, fn, displayMode, level, menuList)
	if not isForever(dd) then return pass("UIDropDownMenu_Initialize", dd, fn, displayMode, level, menuList) end
	dd.cdkpInit, dd.menuList, dd.displayMode = fn, menuList, displayMode
	Collect(dd, 1, menuList, nil)                    -- LibDD calls the initializer once on Initialize; keep its side effects
end

function DD:UIDropDownMenu_CreateInfo() return {} end

function DD:UIDropDownMenu_AddButton(info, level)
	if collecting then
		local copy = {}
		for k, v in pairs(info or {}) do copy[k] = v end
		collecting.rows[#collecting.rows + 1] = copy
		return
	end
	return pass("UIDropDownMenu_AddButton", info, level)
end

function DD:UIDropDownMenu_SetText(dd, s)
	if isForever(dd) then return dd:SetText(s) end
	return pass("UIDropDownMenu_SetText", dd, s)
end

function DD:UIDropDownMenu_GetText(dd)
	if isForever(dd) then return dd:GetText() end
	return pass("UIDropDownMenu_GetText", dd)
end

function DD:UIDropDownMenu_JustifyText(dd, j, ...)
	if isForever(dd) then return dd.Text:SetJustifyH(j) end
	return pass("UIDropDownMenu_JustifyText", dd, j, ...)
end

function DD:UIDropDownMenu_SetWidth(dd, w, pad, ...)
	if isForever(dd) then return dd:SetWidth(w) end
	return pass("UIDropDownMenu_SetWidth", dd, w, pad, ...)
end

function DD:UIDropDownMenu_SetSelectedValue(dd, value, ...)
	if isForever(dd) then return dd:SetSelection(value) end
	return pass("UIDropDownMenu_SetSelectedValue", dd, value, ...)
end

function DD:UIDropDownMenu_GetSelectedValue(dd)
	if isForever(dd) then return dd:GetSelection() end
	return pass("UIDropDownMenu_GetSelectedValue", dd)
end

function DD:UIDropDownMenu_EnableDropDown(dd)
	if isForever(dd) then return dd:SetEnabled(true) end
	return pass("UIDropDownMenu_EnableDropDown", dd)
end

function DD:UIDropDownMenu_DisableDropDown(dd)
	if isForever(dd) then return dd:SetEnabled(false) end
	return pass("UIDropDownMenu_DisableDropDown", dd)
end

function DD:ToggleDropDownMenu(level, value, dd, ...)
	if isForever(dd) then
		if dd:IsOpen() then dd:Close() else dd:Open(level or 1) end
		return
	end
	return pass("ToggleDropDownMenu", level, value, dd, ...)
end

function DD:CloseDropDownMenus(level)
	CloseLevels(level or 1)
	return pass("CloseDropDownMenus", level)
end
