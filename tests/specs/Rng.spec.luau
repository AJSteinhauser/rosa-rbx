local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Rng = require(ReplicatedStorage.RosaRbx.utils["rng"])

local SEED_MODULUS = 2147483647

return function()
	describe("Rng.next", function()

		it("stays within [0, 1) across many calls", function()
			for _ = 1, 200 do
				local value = Rng.next()
				expect(value >= 0).to.equal(true)
				expect(value < 1).to.equal(true)
			end
		end)

		it("does not return the same value on every call", function()
			local seen = {}
			for _ = 1, 20 do
				seen[Rng.next()] = true
			end
			-- If NextNumber() were somehow stuck, every draw would collide into one key.
			local distinctCount = 0
			for _ in seen do distinctCount += 1 end
			expect(distinctCount > 1).to.equal(true)
		end)

	end)

	describe("Rng.computeSeed", function()

		it("returns a number in [0, SEED_MODULUS)", function()
			for _, jobId in { "", "abc", "ABCDEF0123456789" } do
				local seed = Rng.computeSeed(jobId, os.time(), 12345)
				expect(typeof(seed)).to.equal("number")
				expect(seed >= 0).to.equal(true)
				expect(seed < SEED_MODULUS).to.equal(true)
			end
		end)

		it("is deterministic for the same inputs", function()
			local a = Rng.computeSeed("some-job-id", 1000, 500)
			local b = Rng.computeSeed("some-job-id", 1000, 500)
			expect(a).to.equal(b)
		end)

		it("does not error on an empty jobId (the Studio fallback case)", function()
			expect(function()
				Rng.computeSeed("", os.time(), 0)
			end).never.to.throw()
		end)

		it("produces different seeds for different jobIds at the same instant", function()
			-- This is the whole point of folding jobId in: a fleet of servers that boot
			-- at the exact same os.time()/os.clock() must still diverge.
			local a = Rng.computeSeed("job-aaaa", 1000, 0)
			local b = Rng.computeSeed("job-bbbb", 1000, 0)
			expect(a).never.to.equal(b)
		end)

		it("produces different seeds for different clock readings with the same jobId", function()
			local a = Rng.computeSeed("same-job-id", 1000, 111)
			local b = Rng.computeSeed("same-job-id", 1000, 222)
			expect(a).never.to.equal(b)
		end)

		it("feeds into Random.new without erroring, for both empty and non-empty jobIds", function()
			for _, jobId in { "", "some-job-id" } do
				local seed = Rng.computeSeed(jobId, os.time(), math.floor(os.clock() * 1e6))
				expect(function()
					local generator = Random.new(seed)
					generator:NextNumber()
				end).never.to.throw()
			end
		end)

	end)
end
