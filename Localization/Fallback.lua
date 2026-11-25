-- AD-6.5: locale fallback. Each non-English Localization.*.lua file replaces core.L wholesale when its
-- GetLocale() matches, so keys it doesn't translate would be nil. This file loads after all of them
-- (TOC: right after Localization.tw.lua, before embeds.xml) and falls back to the English table.
-- Every module captures `local L = core.L` later, i.e. this same table, so the fallback reaches them all.
local _, core = ...
if core.L_EN and core.L ~= core.L_EN and getmetatable(core.L) == nil then
	setmetatable(core.L, { __index = core.L_EN })
end
