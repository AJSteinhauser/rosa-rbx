local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Helpers           = require(ReplicatedStorage.RosaRbxPipeline.utils.helpers)

return function()
	describe("helpers.vector3ToPosition()", function()

		it("converts a Vector3 to a table with x/y/z fields", function()
			local pos = Helpers.vector3ToPosition(Vector3.new(1, 2, 3))
			expect(typeof(pos)).to.equal("table")
			expect(pos.x).to.equal(1)
			expect(pos.y).to.equal(2)
			expect(pos.z).to.equal(3)
		end)

		it("handles zero vector", function()
			local pos = Helpers.vector3ToPosition(Vector3.new(0, 0, 0))
			expect(pos.x).to.equal(0)
			expect(pos.y).to.equal(0)
			expect(pos.z).to.equal(0)
		end)

		it("handles negative components", function()
			local pos = Helpers.vector3ToPosition(Vector3.new(-10, -20.5, -30))
			expect(pos.x).to.equal(-10)
			expect(pos.y).to.equal(-20.5)
			expect(pos.z).to.equal(-30)
		end)

		it("handles large values", function()
			local pos = Helpers.vector3ToPosition(Vector3.new(999999, 888888, 777777))
			expect(pos.x).to.equal(999999)
			expect(pos.y).to.equal(888888)
			expect(pos.z).to.equal(777777)
		end)

		it("result is a plain table, not a Vector3", function()
			local pos = Helpers.vector3ToPosition(Vector3.new(1, 2, 3))
			expect(typeof(pos)).to.equal("table")
			expect((pos :: any).Magnitude).to.equal(nil)
		end)

		it("returns a new table each call — references are independent", function()
			local vec  = Vector3.new(5, 5, 5)
			local pos1 = Helpers.vector3ToPosition(vec)
			local pos2 = Helpers.vector3ToPosition(vec)
			expect(pos1 == pos2).to.equal(false)
			pos1.x = 999
			expect(pos2.x).to.equal(5)
		end)

	end)
end
