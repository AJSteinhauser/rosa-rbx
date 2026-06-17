local ReplicatedStorage = game:GetService("ReplicatedStorage")
local splitArrayInHalf  = require(ReplicatedStorage.RosaRbx.egress.utils["array-manipulation"]).splitArrayInHalf

return function()
	describe("splitArrayInHalf()", function()

		it("splits an even-length array at the midpoint", function()
			local left, right = splitArrayInHalf({ 1, 2, 3, 4 })
			expect(#left).to.equal(2)
			expect(#right).to.equal(2)
			expect(left[1]).to.equal(1)
			expect(left[2]).to.equal(2)
			expect(right[1]).to.equal(3)
			expect(right[2]).to.equal(4)
		end)

		it("splits an odd-length array with left getting the smaller half", function()
			local left, right = splitArrayInHalf({ 1, 2, 3, 4, 5 })
			expect(#left).to.equal(2) -- floor(5/2) = 2
			expect(#right).to.equal(3)
			expect(left[1]).to.equal(1)
			expect(right[1]).to.equal(3)
		end)

		it("handles a two-element array", function()
			local left, right = splitArrayInHalf({ "a", "b" })
			expect(#left).to.equal(1)
			expect(#right).to.equal(1)
			expect(left[1]).to.equal("a")
			expect(right[1]).to.equal("b")
		end)

		it("handles a single-element array — left empty, right has the element", function()
			local left, right = splitArrayInHalf({ 42 })
			expect(#left).to.equal(0)
			expect(#right).to.equal(1)
			expect(right[1]).to.equal(42)
		end)

		it("handles an empty array", function()
			local left, right = splitArrayInHalf({})
			expect(#left).to.equal(0)
			expect(#right).to.equal(0)
		end)

		it("does not mutate the original array", function()
			local original = { 10, 20, 30, 40 }
			splitArrayInHalf(original)
			expect(#original).to.equal(4)
			expect(original[1]).to.equal(10)
			expect(original[4]).to.equal(40)
		end)

		it("preserves order within each half", function()
			local left, right = splitArrayInHalf({ "a", "b", "c", "d", "e", "f" })
			expect(left[1]).to.equal("a")
			expect(left[2]).to.equal("b")
			expect(left[3]).to.equal("c")
			expect(right[1]).to.equal("d")
			expect(right[2]).to.equal("e")
			expect(right[3]).to.equal("f")
		end)

	end)
end
