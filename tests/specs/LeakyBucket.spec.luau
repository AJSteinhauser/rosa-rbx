local ReplicatedStorage = game:GetService("ReplicatedStorage")
local LeakyBucket = require(ReplicatedStorage.RosaRbx.utils["leaky-bucket"])

return function()
	describe("LeakyBucket", function()

		describe("new()", function()
			it("starts with level 0", function()
				local b = LeakyBucket.new(10, 5)
				expect(b:getLevel(0)).to.equal(0)
			end)

			it("stores capacity and leak rate", function()
				local b = LeakyBucket.new(42, 7)
				expect(b.capacity).to.equal(42)
				expect(b.leakRatePerSec).to.equal(7)
			end)
		end)

		describe("allow()", function()

			-- Basic allow/deny
			it("allows the first event on an empty bucket", function()
				expect(LeakyBucket.new(10, 5):allow(1, 0)).to.equal(true)
			end)

			it("allows events until capacity is reached", function()
				local b = LeakyBucket.new(3, 0)
				expect(b:allow(1, 0)).to.equal(true)
				expect(b:allow(1, 0)).to.equal(true)
				expect(b:allow(1, 0)).to.equal(true)
			end)

			it("denies the event that would exceed capacity", function()
				local b = LeakyBucket.new(3, 0)
				b:allow(3, 0)
				expect(b:allow(1, 0)).to.equal(false)
			end)

			-- Exact capacity boundary: level + cost == capacity should be ALLOWED
			it("allows when level + cost equals capacity exactly", function()
				local b = LeakyBucket.new(5, 0)
				b:allow(3, 0) -- level = 3
				expect(b:allow(2, 0)).to.equal(true) -- 3+2 == 5, not > 5
			end)

			it("denies when level + cost is one over capacity", function()
				local b = LeakyBucket.new(5, 0)
				b:allow(5, 0) -- full
				expect(b:allow(1, 0)).to.equal(false)
			end)

			it("denies when a single cost exceeds capacity", function()
				expect(LeakyBucket.new(3, 0):allow(4, 0)).to.equal(false)
			end)

			-- Cost default
			it("defaults cost to 1", function()
				local b = LeakyBucket.new(1, 0)
				expect(b:allow(nil, 0)).to.equal(true)
				expect(b:allow(nil, 0)).to.equal(false)
			end)

			-- Fractional costs
			it("supports fractional costs", function()
				local b = LeakyBucket.new(1, 0)
				expect(b:allow(0.5, 0)).to.equal(true)
				expect(b:allow(0.5, 0)).to.equal(true)
				expect(b:allow(0.5, 0)).to.equal(false)
			end)

			-- Invalid costs
			it("throws when cost is zero", function()
				expect(function()
					LeakyBucket.new(10, 5):allow(0, 0)
				end).to.throw()
			end)

			it("throws when cost is negative", function()
				expect(function()
					LeakyBucket.new(10, 5):allow(-1, 0)
				end).to.throw()
			end)

			-- Time-based drain
			it("allows again after enough time passes to drain the bucket", function()
				local b = LeakyBucket.new(3, 3) -- drains 3/s
				b:allow(3, 0)                    -- full at t=0
				expect(b:allow(1, 0)).to.equal(false)
				expect(b:allow(1, 1)).to.equal(true) -- fully drained at t=1
			end)

			it("allows partial refill — only what drained fits", function()
				local b = LeakyBucket.new(4, 2) -- drains 2/s
				b:allow(4, 0)                    -- full at t=0
				-- at t=1, drained 2 → level=2, room=2
				expect(b:allow(2, 1)).to.equal(true)
				expect(b:allow(1, 1)).to.equal(false)
			end)

			it("handles time going backwards — does not decrease level", function()
				local b = LeakyBucket.new(10, 5)
				b:allow(5, 100)  -- level=5 at t=100
				-- t=50 is "before" lastTime=100; elapsed = max(0, 50-100) = 0 → no leak
				local levelBefore = b:getLevel(100)
				b:allow(1, 50)   -- t=50 < lastTime; no leak applied
				-- level should still be ~6 (5 + 1 new allow, no leak because t went backwards)
				expect(b:getLevel(50)).to.be.near(6, 0.01)
			end)

		end)

		describe("getLevel()", function()
			it("reflects current level after allowing", function()
				local b = LeakyBucket.new(10, 0) -- no leak
				b:allow(3, 0)
				expect(b:getLevel(0)).to.be.near(3, 0.001)
			end)

			it("decreases as time passes", function()
				local b = LeakyBucket.new(10, 2) -- 2/s drain
				b:allow(4, 0)
				expect(b:getLevel(1)).to.be.near(2, 0.01)
			end)

			it("never goes below zero", function()
				local b = LeakyBucket.new(10, 10)
				b:allow(1, 0)
				expect(b:getLevel(1000)).to.equal(0)
			end)

			it("with leakRate=0 the level never drains", function()
				local b = LeakyBucket.new(5, 0)
				b:allow(5, 0)
				expect(b:getLevel(9999)).to.equal(5)
			end)

			it("defaults now to os.clock() when not provided", function()
				local b = LeakyBucket.new(10, 0)
				b:allow(2, os.clock())
				-- getLevel with no arg should not throw and return ~2
				local level = b:getLevel()
				expect(level).to.be.near(2, 0.5)
			end)
		end)

	end)
end
