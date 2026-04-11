local ReplicatedStorage = game:GetService("ReplicatedStorage")
local LeakyBucket = require(ReplicatedStorage.RosaRbxPipeline.utils["leaky-bucket"])

return function()
	describe("LeakyBucket", function()

		describe("new()", function()
			it("creates a bucket with zero level", function()
				local bucket = LeakyBucket.new(10, 5)
				expect(bucket:getLevel(os.clock())).to.equal(0)
			end)
		end)

		describe("allow()", function()
			it("permits an event when bucket is empty", function()
				local bucket = LeakyBucket.new(10, 5)
				expect(bucket:allow(1, 0)).to.equal(true)
			end)

			it("increments level on each allowed event", function()
				local bucket = LeakyBucket.new(10, 5)
				bucket:allow(1, 0)
				bucket:allow(1, 0)
				expect(bucket:getLevel(0)).to.be.near(2, 0.001)
			end)

			it("denies when level would exceed capacity", function()
				local bucket = LeakyBucket.new(3, 5)
				bucket:allow(1, 0)
				bucket:allow(1, 0)
				bucket:allow(1, 0)
				expect(bucket:allow(1, 0)).to.equal(false)
			end)

			it("denies immediately when cost equals capacity on a full bucket", function()
				local bucket = LeakyBucket.new(5, 10)
				bucket:allow(5, 0)
				expect(bucket:allow(1, 0)).to.equal(false)
			end)

			it("denies when a single cost exceeds capacity", function()
				local bucket = LeakyBucket.new(3, 5)
				expect(bucket:allow(4, 0)).to.equal(false)
			end)

			it("allows again after enough time has passed to drain the bucket", function()
				local bucket = LeakyBucket.new(3, 3) -- drains 3 per second
				bucket:allow(3, 0)                    -- fill to capacity at t=0
				expect(bucket:allow(1, 0)).to.equal(false)
				expect(bucket:allow(1, 1)).to.equal(true)  -- fully drained after 1s
			end)

			it("defaults cost to 1", function()
				local bucket = LeakyBucket.new(1, 5)
				expect(bucket:allow(nil, 0)).to.equal(true)
				expect(bucket:allow(nil, 0)).to.equal(false)
			end)

			it("supports fractional costs", function()
				local bucket = LeakyBucket.new(1, 5)
				expect(bucket:allow(0.5, 0)).to.equal(true)
				expect(bucket:allow(0.5, 0)).to.equal(true)
				expect(bucket:allow(0.5, 0)).to.equal(false)
			end)
		end)

		describe("getLevel()", function()
			it("reflects current level after allowing", function()
				local bucket = LeakyBucket.new(10, 5)
				bucket:allow(3, 0)
				expect(bucket:getLevel(0)).to.be.near(3, 0.001)
			end)

			it("decreases as time passes", function()
				local bucket = LeakyBucket.new(10, 2) -- drains 2 per second
				bucket:allow(4, 0)
				expect(bucket:getLevel(1)).to.be.near(2, 0.01)
			end)

			it("never goes below zero", function()
				local bucket = LeakyBucket.new(10, 10)
				bucket:allow(1, 0)
				expect(bucket:getLevel(1000)).to.equal(0)
			end)
		end)

	end)
end
