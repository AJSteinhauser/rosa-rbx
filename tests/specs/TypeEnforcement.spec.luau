local ReplicatedStorage = game:GetService("ReplicatedStorage")
local enforce           = require(ReplicatedStorage.RosaRbxPipeline.ingestion["type-enforcement"]).enforce

local function validEvent()
	return {
		eventId        = "guid-123",
		eventTimeStamp = 1700000000,
		sessionID      = "session-abc",
		tag            = "TestEvent",
		platform       = "Windows",
		position       = { x = 1, y = 2, z = 3 },
		version        = "1",
	}
end

local function expectFails(fn)
	expect(pcall(fn)).to.equal(false)
end

local function expectPasses(fn)
	expect(pcall(fn)).to.equal(true)
end

return function()
	describe("TypeEnforcement.enforce()", function()

		describe("valid events", function()
			it("accepts a minimal valid event", function()
				expectPasses(function() enforce(validEvent()) end)
			end)

			it("accepts a fully-populated event", function()
				local e = validEvent()
				e.quantity = 5
				e.teamId   = "Red"
				e.mapName  = "Desert"
				e.custom   = { weapon = "Sword", damage = 42 }
				expectPasses(function() enforce(e) end)
			end)
		end)

		describe("top-level type check", function()
			it("rejects a non-table event", function()
				expectFails(function() enforce("not a table") end)
			end)
		end)

		describe("tag field", function()
			it("rejects a missing tag", function()
				local e = validEvent(); e.tag = nil
				expectFails(function() enforce(e) end)
			end)

			it("rejects a numeric tag", function()
				local e = validEvent(); e.tag = 123
				expectFails(function() enforce(e) end)
			end)

			it("accepts an empty string tag", function()
				local e = validEvent(); e.tag = ""
				expectPasses(function() enforce(e) end)
			end)
		end)

		describe("position field", function()
			it("rejects a missing position", function()
				local e = validEvent(); e.position = nil
				expectFails(function() enforce(e) end)
			end)

			it("rejects position as a string", function()
				local e = validEvent(); e.position = "0,0,0"
				expectFails(function() enforce(e) end)
			end)

			it("rejects non-number position.x", function()
				local e = validEvent(); e.position.x = "zero"
				expectFails(function() enforce(e) end)
			end)

			it("rejects non-number position.y", function()
				local e = validEvent(); e.position.y = "zero"
				expectFails(function() enforce(e) end)
			end)

			it("rejects non-number position.z", function()
				local e = validEvent(); e.position.z = "zero"
				expectFails(function() enforce(e) end)
			end)

			it("accepts zero for all position components", function()
				local e = validEvent(); e.position = { x = 0, y = 0, z = 0 }
				expectPasses(function() enforce(e) end)
			end)

			it("accepts negative position values", function()
				local e = validEvent(); e.position = { x = -100, y = -50, z = -200 }
				expectPasses(function() enforce(e) end)
			end)
		end)

		describe("eventTimeStamp field", function()
			it("rejects a missing eventTimeStamp", function()
				local e = validEvent(); e.eventTimeStamp = nil
				expectFails(function() enforce(e) end)
			end)

			it("rejects a string eventTimeStamp", function()
				local e = validEvent(); e.eventTimeStamp = "now"
				expectFails(function() enforce(e) end)
			end)
		end)

		describe("sessionID field", function()
			it("rejects a missing sessionID", function()
				local e = validEvent(); e.sessionID = nil
				expectFails(function() enforce(e) end)
			end)

			it("rejects a numeric sessionID", function()
				local e = validEvent(); e.sessionID = 999
				expectFails(function() enforce(e) end)
			end)
		end)

		describe("platform field", function()
			it("rejects a missing platform", function()
				local e = validEvent(); e.platform = nil
				expectFails(function() enforce(e) end)
			end)

			it("rejects a numeric platform", function()
				local e = validEvent(); e.platform = 1
				expectFails(function() enforce(e) end)
			end)
		end)

		describe("optional: quantity", function()
			it("accepts nil quantity", function()
				local e = validEvent(); e.quantity = nil
				expectPasses(function() enforce(e) end)
			end)

			it("accepts a valid number quantity", function()
				local e = validEvent(); e.quantity = 7
				expectPasses(function() enforce(e) end)
			end)

			it("rejects a string quantity", function()
				local e = validEvent(); e.quantity = "seven"
				expectFails(function() enforce(e) end)
			end)
		end)

		describe("optional: teamId", function()
			it("accepts nil teamId", function()
				local e = validEvent(); e.teamId = nil
				expectPasses(function() enforce(e) end)
			end)

			it("rejects a numeric teamId", function()
				local e = validEvent(); e.teamId = 1
				expectFails(function() enforce(e) end)
			end)
		end)

		describe("optional: mapName", function()
			it("accepts nil mapName", function()
				local e = validEvent(); e.mapName = nil
				expectPasses(function() enforce(e) end)
			end)

			it("rejects a boolean mapName", function()
				local e = validEvent(); e.mapName = true
				expectFails(function() enforce(e) end)
			end)
		end)

		describe("optional: version", function()
			it("accepts nil version", function()
				local e = validEvent(); e.version = nil
				expectPasses(function() enforce(e) end)
			end)

			it("rejects a numeric version", function()
				local e = validEvent(); e.version = 2
				expectFails(function() enforce(e) end)
			end)
		end)

		describe("optional: custom", function()
			it("accepts nil custom", function()
				local e = validEvent(); e.custom = nil
				expectPasses(function() enforce(e) end)
			end)

			it("accepts string and number custom values", function()
				local e = validEvent(); e.custom = { weapon = "Sword", damage = 42 }
				expectPasses(function() enforce(e) end)
			end)

			it("rejects custom as a string", function()
				local e = validEvent(); e.custom = "metadata"
				expectFails(function() enforce(e) end)
			end)

			it("rejects a boolean custom value", function()
				local e = validEvent(); e.custom = { active = true }
				expectFails(function() enforce(e) end)
			end)

			it("rejects a nested table custom value", function()
				local e = validEvent(); e.custom = { nested = { a = 1 } }
				expectFails(function() enforce(e) end)
			end)

			it("rejects custom that encodes to more than 500 characters", function()
				local e   = validEvent()
				local big = {}
				for i = 1, 20 do
					big["key_" .. i] = string.rep("v", 20)
				end
				e.custom = big
				expectFails(function() enforce(e) end)
			end)

			it("accepts custom well under the 500-char limit", function()
				local e = validEvent(); e.custom = { k = "v" }
				expectPasses(function() enforce(e) end)
			end)
		end)

	end)
end
