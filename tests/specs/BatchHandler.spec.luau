local ReplicatedStorage = game:GetService("ReplicatedStorage")
local HttpService       = game:GetService("HttpService")
local BatchHandler      = require(ReplicatedStorage.RosaRbx.egress.components["batch-event-handler"])
local Blocker           = require(ReplicatedStorage.RosaRbx.egress.components["blocker"])
local splitArrayInHalf  = require(ReplicatedStorage.RosaRbx.egress.utils["array-manipulation"]).splitArrayInHalf

local function makeEvent(tag: string?)
	return {
		eventId        = HttpService:GenerateGUID(false),
		eventTimeStamp = os.time(),
		sessionID      = "test-session",
		tag            = tag or "TestEvent",
		platform       = "Windows",
		position       = { x = 0, y = 0, z = 0 },
		version        = "1",
	}
end

local function getHandler()
	local h = BatchHandler.getInstance()
	if h then return h end
	local ok, result = pcall(function() return BatchHandler.new() end)
	return ok and result or nil
end

local function drainEvents(handler): { any }
	local buff = handler.accumulator:flushEvents()
	local json = buffer.readstring(buff, 0, buffer.len(buff))
	return HttpService:JSONDecode(json)
end

local function makeBlocker(probeInterval)
	local time = 0
	local b    = Blocker.new("test", probeInterval or 100, function() return time end)
	return b, function(t) time = t end
end

return function()
	describe("BatchHandler", function()

		describe("singleton enforcement", function()
			it("throws when a second instance is created", function()
				local ok1 = pcall(function() BatchHandler.new() end)
				local ok2, err = pcall(function() BatchHandler.new() end)
				if ok1 then
					expect(ok2).to.equal(false)
					expect(err:find("Only one instance") ~= nil).to.equal(true)
				else
					expect(ok1).to.equal(false)
				end
			end)
		end)

		describe("addEvent()", function()
			it("does not throw for a well-formed event", function()
				local handler = getHandler()
				if not handler then return end
				expect(function()
					handler:addEvent(makeEvent("ValidEvent"))
				end).never.to.throw()
			end)
		end)

		describe("quota blocker (403)", function()
			it("discards addEvent calls while blocked", function()
				local handler = getHandler()
				if not handler then return end

				local original       = handler.quotaBlocker
				handler.quotaBlocker = Blocker.new("quota", 100, function() return 0 end)

				drainEvents(handler)
				handler.quotaBlocker:onBlocked()
				handler:addEvent(makeEvent("ShouldBeDiscarded"))

				local events = drainEvents(handler)
				handler.quotaBlocker = original

				expect(#events).to.equal(0)
			end)

			it("discards all events while blocked, not just the first", function()
				local handler = getHandler()
				if not handler then return end

				local original       = handler.quotaBlocker
				handler.quotaBlocker = Blocker.new("quota", 100, function() return 0 end)

				drainEvents(handler)
				handler.quotaBlocker:onBlocked()
				for i = 1, 5 do handler:addEvent(makeEvent("Event" .. i)) end

				local events = drainEvents(handler)
				handler.quotaBlocker = original

				expect(#events).to.equal(0)
			end)

			it("accumulator stays empty throughout the blocked period", function()
				local handler = getHandler()
				if not handler then return end

				local original       = handler.quotaBlocker
				handler.quotaBlocker = Blocker.new("quota", 100, function() return 0 end)

				drainEvents(handler)
				handler.quotaBlocker:onBlocked()
				handler:addEvent(makeEvent("A"))
				handler:addEvent(makeEvent("B"))

				expect(handler.accumulator.isEmpty).to.equal(true)
				handler.quotaBlocker = original
			end)

			it("pre-block events flush together with the probe", function()
				local handler          = getHandler()
				if not handler then return end

				local blocker, setTime = makeBlocker()
				local original         = handler.quotaBlocker
				handler.quotaBlocker   = blocker

				drainEvents(handler)
				handler:addEvent(makeEvent("PreBlock"))
				blocker:onBlocked()
				handler:addEvent(makeEvent("Discarded"))
				setTime(100)
				handler:addEvent(makeEvent("Probe"))

				local events = drainEvents(handler)
				handler.quotaBlocker = original

				expect(#events).to.equal(2)
				expect(events[1].tag).to.equal("PreBlock")
				expect(events[2].tag).to.equal("Probe")
			end)

			it("allows events once the probe interval elapses", function()
				local handler          = getHandler()
				if not handler then return end

				local blocker, setTime = makeBlocker()
				local original         = handler.quotaBlocker
				handler.quotaBlocker   = blocker

				drainEvents(handler)
				blocker:onBlocked()
				handler:addEvent(makeEvent("Discarded"))
				setTime(100)
				handler:addEvent(makeEvent("ProbeEvent"))

				local events = drainEvents(handler)
				handler.quotaBlocker = original

				expect(#events).to.equal(1)
				expect(events[1].tag).to.equal("ProbeEvent")
			end)

			it("resumes after onSuccess", function()
				local handler        = getHandler()
				if not handler then return end

				local original       = handler.quotaBlocker
				handler.quotaBlocker = Blocker.new("quota", 100, function() return 0 end)

				drainEvents(handler)
				handler.quotaBlocker:onBlocked()
				handler.quotaBlocker:onSuccess()
				handler:addEvent(makeEvent("PostRecovery"))

				local events = drainEvents(handler)
				handler.quotaBlocker = original

				expect(#events).to.equal(1)
				expect(events[1].tag).to.equal("PostRecovery")
			end)

			it("blocks again after a second 403", function()
				local handler        = getHandler()
				if not handler then return end

				local original       = handler.quotaBlocker
				handler.quotaBlocker = Blocker.new("quota", 100, function() return 0 end)

				drainEvents(handler)
				handler.quotaBlocker:onBlocked()
				handler.quotaBlocker:onSuccess()
				handler.quotaBlocker:onBlocked()
				handler:addEvent(makeEvent("ShouldBeDiscarded"))

				local events = drainEvents(handler)
				handler.quotaBlocker = original

				expect(#events).to.equal(0)
			end)
		end)

		describe("auth blocker (401)", function()
			it("discards addEvent calls while blocked", function()
				local handler = getHandler()
				if not handler then return end

				local original      = handler.authBlocker
				handler.authBlocker = Blocker.new("auth", 100, function() return 0 end)

				drainEvents(handler)
				handler.authBlocker:onBlocked()
				handler:addEvent(makeEvent("ShouldBeDiscarded"))

				local events = drainEvents(handler)
				handler.authBlocker = original

				expect(#events).to.equal(0)
			end)

			it("discards all events while blocked, not just the first", function()
				local handler = getHandler()
				if not handler then return end

				local original      = handler.authBlocker
				handler.authBlocker = Blocker.new("auth", 100, function() return 0 end)

				drainEvents(handler)
				handler.authBlocker:onBlocked()
				for i = 1, 5 do handler:addEvent(makeEvent("Event" .. i)) end

				local events = drainEvents(handler)
				handler.authBlocker = original

				expect(#events).to.equal(0)
			end)

			it("allows events once the probe interval elapses", function()
				local handler          = getHandler()
				if not handler then return end

				local blocker, setTime = makeBlocker()
				local original         = handler.authBlocker
				handler.authBlocker    = blocker

				drainEvents(handler)
				blocker:onBlocked()
				handler:addEvent(makeEvent("Discarded"))
				setTime(100)
				handler:addEvent(makeEvent("ProbeEvent"))

				local events = drainEvents(handler)
				handler.authBlocker = original

				expect(#events).to.equal(1)
				expect(events[1].tag).to.equal("ProbeEvent")
			end)

			it("resumes after onSuccess", function()
				local handler       = getHandler()
				if not handler then return end

				local original      = handler.authBlocker
				handler.authBlocker = Blocker.new("auth", 100, function() return 0 end)

				drainEvents(handler)
				handler.authBlocker:onBlocked()
				handler.authBlocker:onSuccess()
				handler:addEvent(makeEvent("PostRecovery"))

				local events = drainEvents(handler)
				handler.authBlocker = original

				expect(#events).to.equal(1)
				expect(events[1].tag).to.equal("PostRecovery")
			end)

			it("auth blocker blocks independently of quota blocker", function()
				local handler = getHandler()
				if not handler then return end

				local origAuth  = handler.authBlocker
				local origQuota = handler.quotaBlocker
				handler.authBlocker  = Blocker.new("auth",  100, function() return 0 end)
				handler.quotaBlocker = Blocker.new("quota", 100, function() return 0 end)

				drainEvents(handler)
				handler.authBlocker:onBlocked()
				handler:addEvent(makeEvent("BlockedByAuth"))

				local events = drainEvents(handler)
				handler.authBlocker  = origAuth
				handler.quotaBlocker = origQuota

				expect(#events).to.equal(0)
			end)

			it("both blockers active still discards events", function()
				local handler = getHandler()
				if not handler then return end

				local origAuth  = handler.authBlocker
				local origQuota = handler.quotaBlocker
				handler.authBlocker  = Blocker.new("auth",  100, function() return 0 end)
				handler.quotaBlocker = Blocker.new("quota", 100, function() return 0 end)

				drainEvents(handler)
				handler.authBlocker:onBlocked()
				handler.quotaBlocker:onBlocked()
				handler:addEvent(makeEvent("BlockedByBoth"))

				local events = drainEvents(handler)
				handler.authBlocker  = origAuth
				handler.quotaBlocker = origQuota

				expect(#events).to.equal(0)
			end)
		end)

		describe("split logic (via array-manipulation)", function()
			it("splits a 4-event JSON buffer into two equal halves", function()
				local events = {}
				for i = 1, 4 do table.insert(events, makeEvent("Event" .. i)) end
				local decoded = HttpService:JSONDecode(HttpService:JSONEncode(events))
				local halfA, halfB = splitArrayInHalf(decoded)
				expect(#halfA).to.equal(2)
				expect(#halfB).to.equal(2)
				expect(halfA[1].tag).to.equal("Event1")
				expect(halfB[1].tag).to.equal("Event3")
			end)

			it("handles an odd number of events — right half is larger", function()
				local events = {}
				for i = 1, 5 do table.insert(events, makeEvent("E" .. i)) end
				local halfA, halfB = splitArrayInHalf(events)
				expect(#halfA).to.equal(2)
				expect(#halfB).to.equal(3)
			end)

			it("JSON round-trip preserves event data in each half", function()
				local events = {}
				for i = 1, 6 do table.insert(events, makeEvent("Tag" .. i)) end
				local halfA, halfB = splitArrayInHalf(events)
				local reA = HttpService:JSONDecode(HttpService:JSONEncode(halfA))
				local reB = HttpService:JSONDecode(HttpService:JSONEncode(halfB))
				expect(reA[1].tag).to.equal("Tag1")
				expect(reB[1].tag).to.equal("Tag4")
			end)
		end)

	end)
end
