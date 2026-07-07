local ReplicatedStorage = game:GetService("ReplicatedStorage")
local backoffSeconds = require(ReplicatedStorage.RosaRbx.broadcast.backoff)

return function()
	describe("backoff", function()
		it("returns 0 for the first attempt", function()
			expect(backoffSeconds(0)).to.equal(0)
		end)

		it("doubles (minus one) with each subsequent attempt", function()
			expect(backoffSeconds(1)).to.equal(1)
			expect(backoffSeconds(2)).to.equal(3)
		end)

		it("caps at RETRY_MAX_BACKOFF_SECONDS instead of growing unbounded", function()
			expect(backoffSeconds(3)).to.equal(5) -- 2^3 - 1 = 7, capped to 5
			expect(backoffSeconds(10)).to.equal(5)
			expect(backoffSeconds(100)).to.equal(5)
		end)
	end)
end
