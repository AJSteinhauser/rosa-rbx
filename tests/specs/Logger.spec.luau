local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Logger = require(ReplicatedStorage.RosaRbx.utils["logger"])

return function()
	describe("Logger", function()

		it("error throws with the [Rosa]-prefixed message", function()
			local ok, err = pcall(function()
				Logger.error("boom")
			end)

			expect(ok).to.equal(false)
			expect(err:find("%[Rosa%] boom") ~= nil).to.equal(true)
		end)

	end)
end
