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

local function decodeFlush(acc): { any }
	return HttpService:JSONDecode(bufferToString(acc:flushEvents()))
end

return function()
	describe("Accumulator", function()

		describe("addEvent()", function()
			it("returns false when buffer is far below the flush threshold", function()
				local acc = Accumulator.new()
				expect(acc:addEvent(makeEvent())).to.equal(false)
			end)

			it("rate-limits a session after hitting bucket capacity", function()
				local acc   = Accumulator.new()
				local event = makeEvent("limited-session")
				-- Bucket cap is 20. Send 25 at the same clock instant → 5 are rejected.
				for _ = 1, 25 do
					acc:addEvent(event)
				end
				local events = decodeFlush(acc)
				expect(#events > 0).to.equal(true)
				expect(#events <= 20).to.equal(true)
			end)

			-- Key invariant: rate-limited events are silently dropped, NOT added to buffer
			it("rate-limited events are not present in the flushed buffer", function()
				local acc   = Accumulator.new()
				local event = makeEvent("drop-test")
				local accepted = 0
				for _ = 1, 25 do
					-- addEvent returns false for both "below threshold" AND "rate limited"
					-- but the bucket fills up, so events beyond cap won't be encoded.
					acc:addEvent(event)
					accepted += 1
				end
				local events = decodeFlush(acc)
				-- The number of decoded events must not exceed bucket capacity
				expect(#events <= 20).to.equal(true)
			end)

			it("different sessions have independent rate limits", function()
				local acc = Accumulator.new()
				-- Each session can accept 20 events before hitting its own bucket cap
				for _ = 1, 20 do
					acc:addEvent(makeEvent("session-A"))
					acc:addEvent(makeEvent("session-B"))
				end
				local events = decodeFlush(acc)
				expect(#events).to.equal(40)
			end)

			it("same bucket object reused across addEvent calls for same session", function()
				local acc    = Accumulator.new()
				local event1 = makeEvent("timed", "Before")
				acc:addEvent(event1)
				local bucket1 = acc:getOrCreateBucket("timed")
				acc:addEvent(event1)
				local bucket2 = acc:getOrCreateBucket("timed")
				expect(bucket1).to.equal(bucket2)
				decodeFlush(acc)
			end)
		end)

		describe("flushEvents()", function()
			it("returns a buffer that decodes as a valid JSON array", function()
				local acc = Accumulator.new()
				acc:addEvent(makeEvent())
				local parsed = HttpService:JSONDecode(bufferToString(acc:flushEvents()))
				expect(typeof(parsed)).to.equal("table")
			end)

			it("single event produces valid JSON — no leading comma", function()
				local acc = Accumulator.new()
				acc:addEvent(makeEvent("s1", "Click"))
				local json = bufferToString(acc:flushEvents())
				expect(json:sub(1, 2)).to.equal("[{")
				expect(json:sub(-1)).to.equal("]")
			end)

			it("multiple events produce a valid JSON array", function()
				local acc = Accumulator.new()
				acc:addEvent(makeEvent("s1", "A"))
				acc:addEvent(makeEvent("s1", "B"))
				acc:addEvent(makeEvent("s1", "C"))
				expect(#decodeFlush(acc)).to.equal(3)
			end)

			it("event fields survive JSON encode/decode round-trip", function()
				local acc   = Accumulator.new()
				local event = makeEvent("round-trip", "RoundTrip")
				acc:addEvent(event)
				local events = decodeFlush(acc)
				expect(events[1].tag).to.equal("RoundTrip")
				expect(events[1].sessionID).to.equal("round-trip")
				expect(events[1].platform).to.equal("Windows")
				expect(events[1].position.x).to.equal(0)
			end)

			it("returns [] when no events were added", function()
				expect(bufferToString(Accumulator.new():flushEvents())).to.equal("[]")
			end)

			it("resets state so the next batch starts fresh", function()
				local acc = Accumulator.new()
				acc:addEvent(makeEvent("s1", "First"))
				acc:flushEvents() -- discard

				acc:addEvent(makeEvent("s1", "Second"))
				local events = decodeFlush(acc)
				expect(#events).to.equal(1)
				expect(events[1].tag).to.equal("Second")
			end)

			it("isEmpty flag resets after flush so first event of next batch has no comma", function()
				local acc = Accumulator.new()
				acc:addEvent(makeEvent("s1", "Batch1"))
				acc:flushEvents()
				acc:addEvent(makeEvent("s1", "Batch2"))
				local json = bufferToString(acc:flushEvents())
				-- Must start with "[{" not "[," in the new batch
				expect(json:sub(1, 2)).to.equal("[{")
			end)

			it("produces correct results over multiple consecutive flush cycles", function()
				local acc = Accumulator.new()
				for cycle = 1, 5 do
					acc:addEvent(makeEvent("s1", "Cycle" .. cycle))
					local events = decodeFlush(acc)
					expect(#events).to.equal(1)
					expect(events[1].tag).to.equal("Cycle" .. cycle)
				end
			end)

			it("handles events with optional fields (custom, quantity, teamId)", function()
				local acc = Accumulator.new()
				local event = makeEvent("opts", "WithOpts")
				event.quantity = 3
				event.teamId   = "Blue"
				event.custom   = { weapon = "Bow", damage = 10 }
				acc:addEvent(event)
				local events = decodeFlush(acc)
				expect(events[1].quantity).to.equal(3)
				expect(events[1].teamId).to.equal("Blue")
				expect(events[1].custom.weapon).to.equal("Bow")
			end)
		end)

	end)
end
