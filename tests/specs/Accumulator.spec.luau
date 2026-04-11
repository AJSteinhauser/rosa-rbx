local ReplicatedStorage = game:GetService("ReplicatedStorage")
local HttpService       = game:GetService("HttpService")
local Accumulator       = require(ReplicatedStorage.RosaRbxPipeline.egress.components.accumulator)

local function makeEvent(sessionID: string?, tag: string?)
	return {
		eventId        = HttpService:GenerateGUID(false),
		eventTimeStamp = os.time(),
		sessionID      = sessionID or "session-1",
		tag            = tag or "TestEvent",
		platform       = "Windows",
		position       = { x = 0, y = 0, z = 0 },
		version        = "1",
	}
end

local function bufferToString(buf: buffer): string
	return buffer.readstring(buf, 0, buffer.len(buf))
end

return function()
	describe("Accumulator", function()

		describe("addEvent()", function()
			it("returns false when buffer is far below the flush threshold", function()
				local acc = Accumulator.new()
				expect(acc:addEvent(makeEvent())).to.equal(false)
			end)

			it("rate-limits a single session after too many rapid events", function()
				local acc   = Accumulator.new()
				local event = makeEvent("session-limited")
				-- Bucket capacity is 20. Send 25 events at the same clock instant.
				for _ = 1, 25 do
					acc:addEvent(event)
				end
				local events = HttpService:JSONDecode(bufferToString(acc:flushEvents()))
				-- At most 20 events accepted (bucket cap), at least 1 got through.
				expect(#events > 0).to.equal(true)
				expect(#events <= 20).to.equal(true)
			end)

			it("tracks separate sessions independently", function()
				local acc = Accumulator.new()
				for _ = 1, 20 do
					acc:addEvent(makeEvent("session-A"))
					acc:addEvent(makeEvent("session-B"))
				end
				local events = HttpService:JSONDecode(bufferToString(acc:flushEvents()))
				expect(#events).to.equal(40)
			end)
		end)

		describe("flushEvents()", function()
			it("returns a buffer that decodes as a valid JSON array", function()
				local acc = Accumulator.new()
				acc:addEvent(makeEvent())
				local parsed = HttpService:JSONDecode(bufferToString(acc:flushEvents()))
				expect(typeof(parsed)).to.equal("table")
			end)

			it("produces valid JSON with a single event — no leading comma", function()
				local acc = Accumulator.new()
				acc:addEvent(makeEvent("s1", "Click"))
				local json = bufferToString(acc:flushEvents())
				expect(json:sub(1, 2)).to.equal("[{")
				expect(json:sub(-1)).to.equal("]")
			end)

			it("produces valid JSON with multiple events", function()
				local acc = Accumulator.new()
				acc:addEvent(makeEvent("s1", "A"))
				acc:addEvent(makeEvent("s1", "B"))
				acc:addEvent(makeEvent("s1", "C"))
				local events = HttpService:JSONDecode(bufferToString(acc:flushEvents()))
				expect(#events).to.equal(3)
			end)

			it("preserves event fields through encode/decode round-trip", function()
				local acc   = Accumulator.new()
				local event = makeEvent("round-trip", "RoundTrip")
				acc:addEvent(event)
				local events = HttpService:JSONDecode(bufferToString(acc:flushEvents()))
				expect(events[1].tag).to.equal("RoundTrip")
				expect(events[1].sessionID).to.equal("round-trip")
				expect(events[1].platform).to.equal("Windows")
			end)

			it("resets the accumulator so the next flush starts fresh", function()
				local acc = Accumulator.new()
				acc:addEvent(makeEvent("s1", "First"))
				acc:flushEvents()

				acc:addEvent(makeEvent("s1", "Second"))
				local events = HttpService:JSONDecode(bufferToString(acc:flushEvents()))
				expect(#events).to.equal(1)
				expect(events[1].tag).to.equal("Second")
			end)

			it("returns an empty JSON array when no events were added", function()
				local acc = Accumulator.new()
				expect(bufferToString(acc:flushEvents())).to.equal("[]")
			end)

			it("returns valid JSON after multiple flush cycles", function()
				local acc = Accumulator.new()
				for cycle = 1, 3 do
					acc:addEvent(makeEvent("s1", "Cycle" .. cycle))
					local events = HttpService:JSONDecode(bufferToString(acc:flushEvents()))
					expect(#events).to.equal(1)
					expect(events[1].tag).to.equal("Cycle" .. cycle)
				end
			end)
		end)

	end)
end
