local ReplicatedStorage = game:GetService("ReplicatedStorage")
local HttpService       = game:GetService("HttpService")
local enforce           = require(ReplicatedStorage.RosaRbx.ingestion["type-enforcement"]).enforce

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

-- Build a custom table whose JSON encoding is exactly `targetLen` characters.
-- This is used to probe the 500-char boundary.
local function customOfEncodedLength(targetLen: number)
	-- Start with a known small base and pad the value string until we hit the target.
	-- {"k":"<padding>"} has overhead of 8 chars ({"k":""}), so value length = target - 8.
	local valueLen = targetLen - 8
	assert(valueLen >= 0, "targetLen too small")
	return { k = string.rep("x", valueLen) }
end

return function()
	describe("TypeEnforcement.enforce()", function()

		describe("valid events", function()
			it("accepts a minimal valid event", function()
				expectPasses(function() enforce(validEvent()) end)
			end)

			it("accepts a fully-populated event with all optional fields", function()
				local e = validEvent()
				e.quantity = 5
				e.teamId   = "Red"
				e.mapName  = "Desert"
				e.custom   = { weapon = "Sword", damage = 42 }
				expectPasses(function() enforce(e) end)
			end)

			it("accepts eventTimeStamp of 0 (Unix epoch)", function()
				local e = validEvent(); e.eventTimeStamp = 0
				expectPasses(function() enforce(e) end)
			end)

			it("accepts negative eventTimeStamp (no range restriction)", function()
				local e = validEvent(); e.eventTimeStamp = -1
				expectPasses(function() enforce(e) end)
			end)
		end)

		describe("top-level type check", function()
			it("rejects a non-table event (string)", function()
				expectFails(function() enforce("not a table") end)
			end)
		end)

		describe("tag field", function()
			it("rejects nil tag", function()
				local e = validEvent(); e.tag = nil
				expectFails(function() enforce(e) end)
			end)

			it("rejects numeric tag", function()
				local e = validEvent(); e.tag = 123
				expectFails(function() enforce(e) end)
			end)

			it("rejects boolean tag", function()
				local e = validEvent(); e.tag = false
				expectFails(function() enforce(e) end)
			end)

			it("accepts empty string tag", function()
				local e = validEvent(); e.tag = ""
				expectPasses(function() enforce(e) end)
			end)
		end)

		describe("position field", function()
			it("rejects nil position", function()
				local e = validEvent(); e.position = nil
				expectFails(function() enforce(e) end)
			end)

			it("rejects position as a string", function()
				local e = validEvent(); e.position = "0,0,0"
				expectFails(function() enforce(e) end)
			end)

			it("rejects position missing z (typeof nil ~= number)", function()
				local e = validEvent(); e.position = { x = 1, y = 2 }
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

			it("accepts all-zero position", function()
				local e = validEvent(); e.position = { x = 0, y = 0, z = 0 }
				expectPasses(function() enforce(e) end)
			end)

			it("accepts negative position values", function()
				local e = validEvent(); e.position = { x = -100, y = -50, z = -200 }
				expectPasses(function() enforce(e) end)
			end)

			it("accepts extra fields in position table (only x/y/z checked)", function()
				local e = validEvent()
				e.position = { x = 1, y = 2, z = 3, w = 4 }
				expectPasses(function() enforce(e) end)
			end)
		end)

		describe("eventTimeStamp field", function()
			it("rejects nil eventTimeStamp", function()
				local e = validEvent(); e.eventTimeStamp = nil
				expectFails(function() enforce(e) end)
			end)

			it("rejects string eventTimeStamp", function()
				local e = validEvent(); e.eventTimeStamp = "now"
				expectFails(function() enforce(e) end)
			end)

			it("rejects boolean eventTimeStamp", function()
				local e = validEvent(); e.eventTimeStamp = true
				expectFails(function() enforce(e) end)
			end)
		end)

		describe("sessionID field", function()
			it("rejects nil sessionID", function()
				local e = validEvent(); e.sessionID = nil
				expectFails(function() enforce(e) end)
			end)

			it("rejects numeric sessionID", function()
				local e = validEvent(); e.sessionID = 999
				expectFails(function() enforce(e) end)
			end)
		end)

		describe("platform field", function()
			it("rejects nil platform", function()
				local e = validEvent(); e.platform = nil
				expectFails(function() enforce(e) end)
			end)

			it("rejects numeric platform", function()
				local e = validEvent(); e.platform = 1
				expectFails(function() enforce(e) end)
			end)
		end)

		describe("optional: quantity", function()
			it("accepts nil quantity", function()
				local e = validEvent(); e.quantity = nil
				expectPasses(function() enforce(e) end)
			end)

			it("accepts quantity = 0", function()
				local e = validEvent(); e.quantity = 0
				expectPasses(function() enforce(e) end)
			end)

			it("accepts negative quantity (no range restriction)", function()
				local e = validEvent(); e.quantity = -1
				expectPasses(function() enforce(e) end)
			end)

			it("accepts a large quantity", function()
				local e = validEvent(); e.quantity = 1e9
				expectPasses(function() enforce(e) end)
			end)

			it("rejects string quantity", function()
				local e = validEvent(); e.quantity = "seven"
				expectFails(function() enforce(e) end)
			end)

			it("rejects boolean quantity", function()
				local e = validEvent(); e.quantity = true
				expectFails(function() enforce(e) end)
			end)
		end)

		describe("optional: teamId", function()
			it("accepts nil teamId", function()
				local e = validEvent(); e.teamId = nil
				expectPasses(function() enforce(e) end)
			end)

			it("accepts empty string teamId", function()
				local e = validEvent(); e.teamId = ""
				expectPasses(function() enforce(e) end)
			end)

			it("rejects numeric teamId", function()
				local e = validEvent(); e.teamId = 1
				expectFails(function() enforce(e) end)
			end)
		end)

		describe("optional: mapName", function()
			it("accepts nil mapName", function()
				local e = validEvent(); e.mapName = nil
				expectPasses(function() enforce(e) end)
			end)

			it("rejects boolean mapName", function()
				local e = validEvent(); e.mapName = true
				expectFails(function() enforce(e) end)
			end)
		end)

		describe("optional: version", function()
			it("accepts nil version", function()
				local e = validEvent(); e.version = nil
				expectPasses(function() enforce(e) end)
			end)

			it("rejects numeric version", function()
				local e = validEvent(); e.version = 2
				expectFails(function() enforce(e) end)
			end)
		end)

		describe("optional: custom", function()
			it("accepts nil custom", function()
				local e = validEvent(); e.custom = nil
				expectPasses(function() enforce(e) end)
			end)

			it("accepts an empty custom table", function()
				local e = validEvent(); e.custom = {}
				expectPasses(function() enforce(e) end)
			end)

			it("accepts string and number custom values", function()
				local e = validEvent()
				e.custom = { weapon = "Sword", damage = 42 }
				expectPasses(function() enforce(e) end)
			end)

			it("accepts numeric array-style keys with valid values", function()
				local e = validEvent()
				e.custom = { [1] = "hello", [2] = 99 }
				expectPasses(function() enforce(e) end)
			end)

			it("rejects custom as a string (not a table)", function()
				local e = validEvent(); e.custom = "metadata"
				expectFails(function() enforce(e) end)
			end)

			it("rejects boolean custom value", function()
				local e = validEvent(); e.custom = { active = true }
				expectFails(function() enforce(e) end)
			end)

			it("rejects nested table custom value", function()
				local e = validEvent(); e.custom = { nested = { a = 1 } }
				expectFails(function() enforce(e) end)
			end)

			-- Boundary: exactly 500 encoded chars should PASS (check is > 500, not >= 500)
			it("accepts custom whose JSON encoding is exactly 500 characters", function()
				local e = validEvent()
				e.custom = customOfEncodedLength(500)
				local encoded = HttpService:JSONEncode(e.custom)
				-- Verify our helper produced the right length
				expect(#encoded).to.equal(500)
				expectPasses(function() enforce(e) end)
			end)

			it("rejects custom whose JSON encoding is 501 characters", function()
				local e = validEvent()
				e.custom = customOfEncodedLength(501)
				expectFails(function() enforce(e) end)
			end)
		end)

	end)
end
