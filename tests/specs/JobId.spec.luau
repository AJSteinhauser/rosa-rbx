local ReplicatedStorage = game:GetService("ReplicatedStorage")
local JobId = require(ReplicatedStorage.RosaRbx.utils["job-id"])

return function()
	describe("JobId.resolve", function()

		it("passes through a non-empty jobId untouched", function()
			local called = false
			local result = JobId.resolve("live-server-guid", function()
				called = true
				return "should-not-be-used"
			end)
			expect(result).to.equal("live-server-guid")
			expect(called).to.equal(false)
		end)

		it("generates a replacement when jobId is empty (the Studio case)", function()
			local result = JobId.resolve("", function()
				return "generated-guid"
			end)
			expect(result).to.equal("generated-guid")
		end)

		it("gives two empty-jobId resolutions distinct results when the generator does", function()
			local a = JobId.resolve("", function() return "guid-a" end)
			local b = JobId.resolve("", function() return "guid-b" end)
			expect(a).never.to.equal(b)
		end)

	end)

	describe("JobId.jobId", function()

		it("is a non-empty string", function()
			expect(typeof(JobId.jobId)).to.equal("string")
			expect(#JobId.jobId > 0).to.equal(true)
		end)

	end)
end
