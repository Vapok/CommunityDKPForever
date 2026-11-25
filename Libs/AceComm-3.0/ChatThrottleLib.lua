--
-- ChatThrottleLib by Mikk
--
-- Manages AddOn chat output to keep player from getting kicked off.
--
-- ChatThrottleLib:SendChatMessage/:SendAddonMessage functions that accept
-- a Priority ("BULK", "NORMAL", "ALERT") as well as prefix for SendChatMessage.
--
-- Priorities get an equal share of available bandwidth when fully loaded.
-- Communication channels are separated on extension+chattype+destination and
-- get round-robinned. (Destination only matters for whispers and channels,
-- obviously)
--
-- Will install hooks for SendChatMessage and SendAddonMessage to measure
-- bandwidth bypassing the library and use less bandwidth itself.
--
--
-- Fully embeddable library. Just copy this file into your addon directory,
-- add it to the .toc, and it's done.
--
-- Can run as a standalone addon also, but, really, just embed it! :-)
--
-- LICENSE: ChatThrottleLib is released into the Public Domain
--
-- CommunityDKPForever patch (CDKP-002), based on v24:
--   * Resolves send/hook targets defensively: C_ChatInfo.* first, falling back to the
--     legacy globals only when they still exist as functions (12.1.5 engine safe).
--   * Honors Enum.SendAddonMessageResult: throttled sends are re-queued with a short
--     back-off instead of being silently dropped.
--   * F2-a (AD-1 Layer B): encounter messaging lockdown keeps messages queued (no direct
--     sends while locked; lockdown results retried like throttle), and callbacks receive
--     the real delivery status as didSend instead of always true.
--   * Version 24.1 so it supersedes legacy <=v24 copies but yields to upstream v25+.
--

local CTL_VERSION = 24.1

local _G = _G

if _G.ChatThrottleLib then
	if _G.ChatThrottleLib.version >= CTL_VERSION then
		-- There's already a newer (or same) version loaded. Buh-bye.
		return
	elseif not _G.ChatThrottleLib.securelyHooked then
		print("ChatThrottleLib: Warning: There's an ANCIENT ChatThrottleLib.lua (pre-wow 2.0, <v16) in an addon somewhere. Get the addon updated or copy in a newer ChatThrottleLib.lua (>=v16) in it!")
		-- ATTEMPT to unhook; this'll behave badly if someone else has hooked...
		-- ... and if someone has securehooked, they can kiss that goodbye too... >.<
		_G.SendChatMessage = _G.ChatThrottleLib.ORIG_SendChatMessage
		if _G.ChatThrottleLib.ORIG_SendAddonMessage then
			_G.SendAddonMessage = _G.ChatThrottleLib.ORIG_SendAddonMessage
		end
	end
	_G.ChatThrottleLib.ORIG_SendChatMessage = nil
	_G.ChatThrottleLib.ORIG_SendAddonMessage = nil
end

if not _G.ChatThrottleLib then
	_G.ChatThrottleLib = {}
end

ChatThrottleLib = _G.ChatThrottleLib  -- in case some addon does "local ChatThrottleLib" above us and we're copypasted (AceComm-2, sigh)
local ChatThrottleLib = _G.ChatThrottleLib

ChatThrottleLib.version = CTL_VERSION



------------------ TWEAKABLES -----------------

ChatThrottleLib.MAX_CPS = 800			  -- 2000 seems to be safe if NOTHING ELSE is happening. let's call it 800.
ChatThrottleLib.MSG_OVERHEAD = 40		-- Guesstimate overhead for sending a message; source+dest+chattype+protocolstuff

ChatThrottleLib.BURST = 4000				-- WoW's server buffer seems to be about 32KB. 8KB should be safe, but seen disconnects on _some_ servers. Using 4KB now.

ChatThrottleLib.MIN_FPS = 20				-- Reduce output CPS to half (and don't burst) if FPS drops below this value


local setmetatable = setmetatable
local table_remove = table.remove
local tostring = tostring
local GetTime = GetTime
local math_min = math.min
local math_max = math.max
local next = next
local strlen = string.len
local GetFramerate = GetFramerate
local strlower = string.lower
local unpack,type,pairs,wipe = unpack,type,pairs,table.wipe
local UnitInRaid,UnitInParty = UnitInRaid,UnitInParty


-----------------------------------------------------------------------
-- API resolution (12.1.5 engine: legacy chat globals may be absent)

-- Resolved at call time so late-loaded/hooked replacements are honored.
local function GetChatMessageSender()
	local C = _G.C_ChatInfo
	if C and type(C.SendChatMessage) == "function" then
		return C.SendChatMessage
	end
	return _G.SendChatMessage
end

local function GetAddonMessageSender()
	local C = _G.C_ChatInfo
	if C and type(C.SendAddonMessage) == "function" then
		return C.SendAddonMessage
	end
	return _G.SendAddonMessage
end

-- Enum.SendAddonMessageResult values that mean "try again later" (CDKP-002 F2-a / AD-1 Layer B).
-- Built by name so we don't hard-code numeric enum values.
--   ThrottleResults: server rate limit  (e.g. AddonMessageThrottle, ChannelThrottle)
--   LockdownResults: encounter/instance messaging lockdown (e.g. AddOnMessageLockdown)
local ThrottleResults, LockdownResults = {}, {}
local SuccessResult
do
	local results = _G.Enum and _G.Enum.SendAddonMessageResult
	if type(results) == "table" then
		for name, value in pairs(results) do
			if type(name) == "string" then
				if name:find("Throttle") then
					ThrottleResults[value] = true
				elseif name:find("Lockdown") then
					LockdownResults[value] = true
				end
			end
		end
		SuccessResult = results.Success
	end
end

-- Result means "not delivered yet, keep it at the head of the queue and retry later".
local function IsRetryResult(result)
	return result ~= nil and (ThrottleResults[result] == true or LockdownResults[result] == true)
end

-- Result means "delivered". Legacy/void senders return nil or true.
local function IsOkResult(result)
	return result == nil or result == true or (SuccessResult ~= nil and result == SuccessResult)
end

-- Encounter/instance messaging lockdown. Guarded lookups: either API may be absent on 1.60.1.
local function IsMessagingLocked()
	local C = _G.C_ChatInfo
	if C and type(C.InChatMessagingLockdown) == "function" then
		if C.InChatMessagingLockdown() then
			return true
		end
	end
	local inEncounter = _G.IsEncounterInProgress
	return (type(inEncounter) == "function" and inEncounter()) and true or false
end


-----------------------------------------------------------------------
-- Double-linked ring implementation

local Ring = {}
local RingMeta = { __index = Ring }

function Ring:New()
	local ret = {}
	setmetatable(ret, RingMeta)
	return ret
end

function Ring:Add(obj)	-- Append at the "far end" of the ring (aka just before the current position)
	if self.pos then
		obj.prev = self.pos.prev
		obj.prev.next = obj
		obj.next = self.pos
		obj.next.prev = obj
	else
		obj.next = obj
		obj.prev = obj
		self.pos = obj
	end
end

function Ring:Remove(obj)
	obj.next.prev = obj.prev
	obj.prev.next = obj.next
	if self.pos == obj then
		self.pos = obj.next
		if self.pos == obj then
			self.pos = nil
		end
	end
end



-----------------------------------------------------------------------
-- Recycling bin for pipes
-- A pipe is a plain integer-indexed queue of messages
-- Pipes normally live in Rings of pipes  (3 rings total, one per priority)

ChatThrottleLib.PipeBin = nil -- pre-v19, drastically different
local PipeBin = setmetatable({}, {__mode="k"})

local function DelPipe(pipe)
	PipeBin[pipe] = true
end

local function NewPipe()
	local pipe = next(PipeBin)
	if pipe then
		wipe(pipe)
		PipeBin[pipe] = nil
		return pipe
	end
	return {}
end




-----------------------------------------------------------------------
-- Recycling bin for messages

ChatThrottleLib.MsgBin = nil -- pre-v19, drastically different
local MsgBin = setmetatable({}, {__mode="k"})

local function DelMsg(msg)
	msg[1] = nil
	-- there's more parameters, but they're very repetetive so the string pool doesn't suffer really, and it's faster to just not delete them.
	MsgBin[msg] = true
end

local function NewMsg()
	local msg = next(MsgBin)
	if msg then
		MsgBin[msg] = nil
		return msg
	end
	return {}
end


-----------------------------------------------------------------------
-- ChatThrottleLib:Init
-- Initialize queues, set up frame for OnUpdate, etc


function ChatThrottleLib:Init()

	-- Set up queues
	if not self.Prio then
		self.Prio = {}
		self.Prio["ALERT"] = { ByName = {}, Ring = Ring:New(), avail = 0 }
		self.Prio["NORMAL"] = { ByName = {}, Ring = Ring:New(), avail = 0 }
		self.Prio["BULK"] = { ByName = {}, Ring = Ring:New(), avail = 0 }
	end

	-- v4: total send counters per priority
	for _, Prio in pairs(self.Prio) do
		Prio.nTotalSent = Prio.nTotalSent or 0
	end

	if not self.avail then
		self.avail = 0 -- v5
	end
	if not self.nTotalSent then
		self.nTotalSent = 0 -- v5
	end


	-- Set up a frame to get OnUpdate events
	if not self.Frame then
		self.Frame = CreateFrame("Frame")
		self.Frame:Hide()
	end
	self.Frame:SetScript("OnUpdate", self.OnUpdate)
	self.Frame:SetScript("OnEvent", self.OnEvent)	-- v11: Monitor P_E_W so we can throttle hard for a few seconds
	self.Frame:RegisterEvent("PLAYER_ENTERING_WORLD")
	self.OnUpdateDelay = 0
	self.LastAvailUpdate = GetTime()
	self.HardThrottlingBeginTime = GetTime()	-- v11: Throttle hard for a few seconds after startup

	-- Hook SendChatMessage and SendAddonMessage so we can measure unpiped traffic and avoid overloads (v7)
	if not self.securelyHooked then
		-- Use secure hooks as of v16. Old regular hook support yanked out in v21.
		self.securelyHooked = true
		local C = _G.C_ChatInfo
		local function chatHook(...)
			return ChatThrottleLib.Hook_SendChatMessage(...)
		end
		local function addonHook(...)
			return ChatThrottleLib.Hook_SendAddonMessage(...)
		end

		--SendChatMessage: hook the namespaced API and, if it is a distinct function,
		--the legacy global too (over-counting bandwidth is safer than under-counting).
		local globalChat = _G.SendChatMessage
		if C and type(C.SendChatMessage) == "function" then
			local namespacedChat = C.SendChatMessage
			hooksecurefunc(C, "SendChatMessage", chatHook)
			if type(globalChat) == "function" and globalChat ~= namespacedChat then
				hooksecurefunc("SendChatMessage", chatHook)
			end
		elseif type(globalChat) == "function" then
			hooksecurefunc("SendChatMessage", chatHook)
		end

		--SendAddonMessage
		if C and type(C.SendAddonMessage) == "function" then
			hooksecurefunc(C, "SendAddonMessage", addonHook)
		elseif type(_G.SendAddonMessage) == "function" then
			hooksecurefunc("SendAddonMessage", addonHook)
		end
		if C and type(C.SendAddonMessageLogged) == "function" then
			hooksecurefunc(C, "SendAddonMessageLogged", addonHook)
		end
	end
	self.nBypass = 0
end


-----------------------------------------------------------------------
-- ChatThrottleLib.Hook_SendChatMessage / .Hook_SendAddonMessage

local bMyTraffic = false

function ChatThrottleLib.Hook_SendChatMessage(text, chattype, language, destination, ...)
	if bMyTraffic then
		return
	end
	local self = ChatThrottleLib
	local size = strlen(tostring(text or "")) + strlen(tostring(destination or "")) + self.MSG_OVERHEAD
	self.avail = self.avail - size
	self.nBypass = self.nBypass + size	-- just a statistic
end
function ChatThrottleLib.Hook_SendAddonMessage(prefix, text, chattype, destination, ...)
	if bMyTraffic then
		return
	end
	local self = ChatThrottleLib
	local size = tostring(text or ""):len() + tostring(prefix or ""):len();
	size = size + tostring(destination or ""):len() + self.MSG_OVERHEAD
	self.avail = self.avail - size
	self.nBypass = self.nBypass + size	-- just a statistic
end



-----------------------------------------------------------------------
-- ChatThrottleLib:UpdateAvail
-- Update self.avail with how much bandwidth is currently available

function ChatThrottleLib:UpdateAvail()
	local now = GetTime()
	local MAX_CPS = self.MAX_CPS;
	local newavail = MAX_CPS * (now - self.LastAvailUpdate)
	local avail = self.avail

	if now - self.HardThrottlingBeginTime < 5 then
		-- First 5 seconds after startup/zoning: VERY hard clamping to avoid irritating the server rate limiter, it seems very cranky then
		avail = math_min(avail + (newavail*0.1), MAX_CPS*0.5)
		self.bChoking = true
	elseif GetFramerate() < self.MIN_FPS then		-- GetFrameRate call takes ~0.002 secs
		avail = math_min(MAX_CPS, avail + newavail*0.5)
		self.bChoking = true		-- just a statistic
	else
		avail = math_min(self.BURST, avail + newavail)
		self.bChoking = false
	end

	avail = math_max(avail, 0-(MAX_CPS*2))	-- Can go negative when someone is eating bandwidth past the lib. but we refuse to stay silent for more than 2 seconds; if they can do it, we can.

	self.avail = avail
	self.LastAvailUpdate = now

	return avail
end


-----------------------------------------------------------------------
-- Despooling logic
-- Reminder:
-- - We have 3 Priorities, each containing a "Ring" construct ...
-- - ... made up of N "Pipe"s (1 for each destination/pipename)
-- - and each pipe contains messages

function ChatThrottleLib:Despool(Prio)
	if IsMessagingLocked() then
		-- Keep everything queued until the lockdown clears. Clamp the priority's budget so the
		-- bandwidth handed out by OnUpdate while locked can't release one huge burst afterwards.
		Prio.avail = math_min(Prio.avail, self.BURST)
		return
	end
	local ring = Prio.Ring
	while ring.pos and Prio.avail > ring.pos[1].nSize do
		local pipe = ring.pos
		local msg = pipe[1]
		local didSend=false
		local lowerDest = strlower(msg[3] or "")
		if lowerDest == "raid" and not UnitInRaid("player") then
			-- do nothing
		elseif lowerDest == "party" and not UnitInParty("player") then
			-- do nothing
		else
			bMyTraffic = true
			local result = msg.f(unpack(msg, 1, msg.n))
			bMyTraffic = false
			if IsRetryResult(result) then
				-- Throttle or lockdown: keep the message at the head of its pipe and back off ~1s.
				self.avail = math_min(self.avail, -self.MAX_CPS)
				Prio.avail = math_min(Prio.avail, self.BURST)
				return
			end
			-- Bandwidth was spent on the attempt either way; only real deliveries count as sent.
			Prio.avail = Prio.avail - msg.nSize
			didSend = IsOkResult(result)
			if didSend then
				Prio.nTotalSent = Prio.nTotalSent + msg.nSize
			end
		end
		-- Message is done (sent, failed permanently, or dropped because we left the group): dequeue it.
		table_remove(pipe, 1)
		if not pipe[1] then  -- did we remove last msg in this pipe?
			ring:Remove(pipe)
			Prio.ByName[pipe.name] = nil
			DelPipe(pipe)
		else
			ring.pos = pipe.next
		end
		-- notify caller of delivery (even if we didn't send it)
		if msg.callbackFn then
			msg.callbackFn (msg.callbackArg, didSend)
		end
		-- USER CALLBACK MAY ERROR
		if didSend then
			DelMsg(msg)
		end
	end
end


function ChatThrottleLib.OnEvent(this,event)
	-- v11: We know that the rate limiter is touchy after login. Assume that it's touchy after zoning, too.
	local self = ChatThrottleLib
	if event == "PLAYER_ENTERING_WORLD" then
		self.HardThrottlingBeginTime = GetTime()	-- Throttle hard for a few seconds after zoning
		self.avail = 0
	end
end


function ChatThrottleLib.OnUpdate(this,delay)
	local self = ChatThrottleLib

	self.OnUpdateDelay = self.OnUpdateDelay + delay
	if self.OnUpdateDelay < 0.08 then
		return
	end
	self.OnUpdateDelay = 0

	self:UpdateAvail()

	if self.avail < 0  then
		return -- argh. some bastard is spewing stuff past the lib. just bail early to save cpu.
	end

	-- See how many of our priorities have queued messages (we only have 3, don't worry about the loop)
	local n = 0
	for prioname,Prio in pairs(self.Prio) do
		if Prio.Ring.pos or Prio.avail < 0 then
			n = n + 1
		end
	end

	-- Anything queued still?
	if n<1 then
		-- Nope. Move spillover bandwidth to global availability gauge and clear self.bQueueing
		for prioname, Prio in pairs(self.Prio) do
			self.avail = self.avail + Prio.avail
			Prio.avail = 0
		end
		self.bQueueing = false
		self.Frame:Hide()
		return
	end

	-- There's stuff queued. Hand out available bandwidth to priorities as needed and despool their queues
	local avail = self.avail/n
	self.avail = 0

	for prioname, Prio in pairs(self.Prio) do
		if Prio.Ring.pos or Prio.avail < 0 then
			Prio.avail = Prio.avail + avail
			if Prio.Ring.pos and Prio.avail > Prio.Ring.pos[1].nSize then
				self:Despool(Prio)
				-- Note: We might not get here if the user-supplied callback function errors out! Take care!
			end
		end
	end

end




-----------------------------------------------------------------------
-- Spooling logic

function ChatThrottleLib:Enqueue(prioname, pipename, msg)
	local Prio = self.Prio[prioname]
	local pipe = Prio.ByName[pipename]
	if not pipe then
		self.Frame:Show()
		pipe = NewPipe()
		pipe.name = pipename
		Prio.ByName[pipename] = pipe
		Prio.Ring:Add(pipe)
	end

	pipe[#pipe + 1] = msg

	self.bQueueing = true
end

function ChatThrottleLib:SendChatMessage(prio, prefix,   text, chattype, language, destination, queueName, callbackFn, callbackArg)
	if not self or not prio or not prefix or not text or not self.Prio[prio] then
		error('Usage: ChatThrottleLib:SendChatMessage("{BULK||NORMAL||ALERT}", "prefix", "text"[, "chattype"[, "language"[, "destination"]]]', 2)
	end
	if callbackFn and type(callbackFn)~="function" then
		error('ChatThrottleLib:ChatMessage(): callbackFn: expected function, got '..type(callbackFn), 2)
	end

	local nSize = text:len()

	if nSize>255 then
		error("ChatThrottleLib:SendChatMessage(): message length cannot exceed 255 bytes", 2)
	end

	nSize = nSize + self.MSG_OVERHEAD

	-- Check if there's room in the global available bandwidth gauge to send directly
	-- (never while messaging is locked: queue instead and let Despool retry after the lock clears)
	if not self.bQueueing and not IsMessagingLocked() and nSize < self:UpdateAvail() then
		bMyTraffic = true
		local result = GetChatMessageSender()(text, chattype, language, destination)
		bMyTraffic = false
		if not IsRetryResult(result) then
			local ok = IsOkResult(result)
			self.avail = self.avail - nSize
			if ok then
				self.Prio[prio].nTotalSent = self.Prio[prio].nTotalSent + nSize
			end
			if callbackFn then
				callbackFn (callbackArg, ok)
			end
			-- USER CALLBACK MAY ERROR
			return
		end
		-- Throttle or lockdown: back off ~1s and fall through to queue the message.
		self.avail = math_min(self.avail, -self.MAX_CPS)
	end

	-- Message needs to be queued
	local msg = NewMsg()
	msg.f = GetChatMessageSender()
	msg[1] = text
	msg[2] = chattype or "SAY"
	msg[3] = language
	msg[4] = destination
	msg.n = 4
	msg.nSize = nSize
	msg.callbackFn = callbackFn
	msg.callbackArg = callbackArg

	self:Enqueue(prio, queueName or (prefix..(chattype or "SAY")..(destination or "")), msg)
end


function ChatThrottleLib:SendAddonMessage(prio, prefix, text, chattype, target, queueName, callbackFn, callbackArg)
	if not self or not prio or not prefix or not text or not chattype or not self.Prio[prio] then
		error('Usage: ChatThrottleLib:SendAddonMessage("{BULK||NORMAL||ALERT}", "prefix", "text", "chattype"[, "target"])', 2)
	end
	if callbackFn and type(callbackFn)~="function" then
		error('ChatThrottleLib:SendAddonMessage(): callbackFn: expected function, got '..type(callbackFn), 2)
	end

	local nSize = text:len();

	if nSize>255 then
		error("ChatThrottleLib:SendAddonMessage(): message length cannot exceed 255 bytes", 2)
	end

	nSize = nSize + self.MSG_OVERHEAD;

	local sendAddonMessage = GetAddonMessageSender()

	-- Check if there's room in the global available bandwidth gauge to send directly
	-- (never while messaging is locked: queue instead and let Despool retry after the lock clears)
	if not self.bQueueing and not IsMessagingLocked() and nSize < self:UpdateAvail() then
		bMyTraffic = true
		local result = sendAddonMessage(prefix, text, chattype, target)
		bMyTraffic = false
		if not IsRetryResult(result) then
			local ok = IsOkResult(result)
			self.avail = self.avail - nSize
			if ok then
				self.Prio[prio].nTotalSent = self.Prio[prio].nTotalSent + nSize
			end
			if callbackFn then
				callbackFn (callbackArg, ok)
			end
			-- USER CALLBACK MAY ERROR
			return
		end
		-- Throttle or lockdown: back off ~1s and fall through to queue the message.
		self.avail = math_min(self.avail, -self.MAX_CPS)
	end

	-- Message needs to be queued
	local msg = NewMsg()
	msg.f = sendAddonMessage
	msg[1] = prefix
	msg[2] = text
	msg[3] = chattype
	msg[4] = target
	msg.n = (target~=nil) and 4 or 3;
	msg.nSize = nSize
	msg.callbackFn = callbackFn
	msg.callbackArg = callbackArg

	self:Enqueue(prio, queueName or (prefix..chattype..(target or "")), msg)
end




-----------------------------------------------------------------------
-- Get the ball rolling!

ChatThrottleLib:Init()

--[[ WoWBench debugging snippet
if(WOWB_VER) then
	local function SayTimer()
		print("SAY: "..GetTime().." "..arg1)
	end
	ChatThrottleLib.Frame:SetScript("OnEvent", SayTimer)
	ChatThrottleLib.Frame:RegisterEvent("CHAT_MSG_SAY")
end
]]


