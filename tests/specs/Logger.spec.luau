local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Logger = require(ReplicatedStorage.RosaRbx.utils["logger"])

return function()
	describe("Logger", function()

		it("info does not error", function()
			expect(function()
				Logger.info("test message")
			end).never.to.throw()
		end)

		it("warn does not error", function()
			expect(function()
				Logger.warn("test message")
			end).never.to.throw()
		end)

		it("error throws with the [Rosa]-prefixed message", function()
			local ok, err = pcall(function()
				Logger.error("boom")
			end)

			expect(ok).to.equal(false)
			expect(err:find("%[Rosa%] boom") ~= nil).to.equal(true)
		end)

	end)
end
