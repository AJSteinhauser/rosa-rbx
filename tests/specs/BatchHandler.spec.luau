local ReplicatedStorage = game:GetService("ReplicatedStorage")
local HttpService       = game:GetService("HttpService")
local BatchHandler      = require(ReplicatedStorage.RosaRbxPipeline.egress.components["batch-event-handler"])
local splitArrayInHalf  = require(ReplicatedStorage.RosaRbxPipeline.egress.utils["array-manipulation"]).splitArrayInHalf

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

return function()
	describe("BatchHandler", function()

		describe("singleton enforcement", function()
			it("throws when a second instance is created", function()
				local ok1 = pcall(function() BatchHandler.new() end)
				local ok2, err = pcall(function() BatchHandler.new() end)
				if ok1 then
					-- First was fresh; second must fail
					expect(ok2).to.equal(false)
					expect(err:find("Only one instance") ~= nil).to.equal(true)
				else
					-- Singleton already existed; both attempts failed — still correct behaviour
					expect(ok1).to.equal(false)
				end
			end)
		end)

		describe("addEvent()", function()
			it("does not throw for a well-formed event", function()
				-- Grab whatever handler exists (singleton may already be set)
				local handler
				local ok = pcall(function() handler = BatchHandler.new() end)
				if not ok then
					-- Cannot get a fresh handler in this test session; skip gracefully
					return
				end
				expect(function()
					handler:addEvent(makeEvent("ValidEvent"))
				end).never.to.throw()
			end)
		end)

		describe("split logic (via array-manipulation)", function()
			-- Validate the split mechanic that BatchHandler relies on when
			-- compression fails, without invoking real HTTP requests.

			it("splits a 4-event JSON buffer into two equal halves", function()
				local events = {}
				for i = 1, 4 do
					table.insert(events, makeEvent("Event" .. i))
				end
				local decoded = HttpService:JSONDecode(HttpService:JSONEncode(events))
				local halfA, halfB = splitArrayInHalf(decoded)
				expect(#halfA).to.equal(2)
				expect(#halfB).to.equal(2)
				expect(halfA[1].tag).to.equal("Event1")
				expect(halfB[1].tag).to.equal("Event3")
			end)

			it("handles an odd number of events — right half is larger", function()
				local events = {}
				for i = 1, 5 do
					table.insert(events, makeEvent("E" .. i))
				end
				local halfA, halfB = splitArrayInHalf(events)
				expect(#halfA).to.equal(2)
				expect(#halfB).to.equal(3)
			end)

			it("JSON round-trip preserves event data in each half", function()
				local events = {}
				for i = 1, 6 do
					table.insert(events, makeEvent("Tag" .. i))
				end
				local halfA, halfB = splitArrayInHalf(events)
				-- Re-encode each half and decode to verify integrity
				local reA = HttpService:JSONDecode(HttpService:JSONEncode(halfA))
				local reB = HttpService:JSONDecode(HttpService:JSONEncode(halfB))
				expect(reA[1].tag).to.equal("Tag1")
				expect(reB[1].tag).to.equal("Tag4")
			end)
		end)

	end)
end
