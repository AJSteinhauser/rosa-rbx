local ReplicatedStorage = game:GetService("ReplicatedStorage")
local PositionPacking = require(ReplicatedStorage.RosaRbx.broadcast["position-packing"])

local X_MAX = 2 ^ 21 - 1
local X_MIN = -(2 ^ 21)
local Y_MAX = 2 ^ 14 - 1
local Y_MIN = -(2 ^ 14)

return function()
	describe("PositionPacking", function()

		describe("pack() / unpack() round trip", function()
			it("round-trips zero for every field", function()
				local low, high = PositionPacking.pack(0, 0, 0, 0)
				local x, y, z, team = PositionPacking.unpack(low, high)
				expect(x).to.equal(0)
				expect(y).to.equal(0)
				expect(z).to.equal(0)
				expect(team).to.equal(0)
			end)

			it("round-trips positive values", function()
				local low, high = PositionPacking.pack(12345, 678, 98765, 3)
				local x, y, z, team = PositionPacking.unpack(low, high)
				expect(x).to.equal(12345)
				expect(y).to.equal(678)
				expect(z).to.equal(98765)
				expect(team).to.equal(3)
			end)

			it("round-trips negative values", function()
				local low, high = PositionPacking.pack(-12345, -678, -98765, 9)
				local x, y, z, team = PositionPacking.unpack(low, high)
				expect(x).to.equal(-12345)
				expect(y).to.equal(-678)
				expect(z).to.equal(-98765)
				expect(team).to.equal(9)
			end)

			it("round-trips x/z at the 22-bit signed extremes", function()
				local low, high = PositionPacking.pack(X_MAX, 0, X_MIN, 0)
				local x, _, z = PositionPacking.unpack(low, high)
				expect(x).to.equal(X_MAX)
				expect(z).to.equal(X_MIN)
			end)

			it("round-trips y at the 15-bit signed extremes", function()
				local low, high = PositionPacking.pack(0, Y_MAX, 0, 0)
				local _, y = PositionPacking.unpack(low, high)
				expect(y).to.equal(Y_MAX)

				low, high = PositionPacking.pack(0, Y_MIN, 0, 0)
				_, y = PositionPacking.unpack(low, high)
				expect(y).to.equal(Y_MIN)
			end)

			it("round-trips team across the full 5-bit unsigned range", function()
				for team = 0, 31 do
					local low, high = PositionPacking.pack(1, 2, 3, team)
					local _, _, _, unpackedTeam = PositionPacking.unpack(low, high)
					expect(unpackedTeam).to.equal(team)
				end
			end)

			it("does not let z bleed into x or team", function()
				local low, high = PositionPacking.pack(0, 0, X_MAX, 0)
				local x, y, z, team = PositionPacking.unpack(low, high)
				expect(x).to.equal(0)
				expect(y).to.equal(0)
				expect(z).to.equal(X_MAX)
				expect(team).to.equal(0)
			end)

			it("does not let x bleed into z, y, or team", function()
				-- x sits entirely in the low word; z straddles the low/high word
				-- boundary. A shift-amount mistake here would corrupt z's low bits.
				local low, high = PositionPacking.pack(X_MAX, 0, 0, 0)
				local x, y, z, team = PositionPacking.unpack(low, high)
				expect(x).to.equal(X_MAX)
				expect(y).to.equal(0)
				expect(z).to.equal(0)
				expect(team).to.equal(0)
			end)

			it("does not let y bleed into z or team", function()
				local low, high = PositionPacking.pack(0, Y_MAX, X_MAX, 0)
				local x, y, z, team = PositionPacking.unpack(low, high)
				expect(x).to.equal(0)
				expect(y).to.equal(Y_MAX)
				expect(z).to.equal(X_MAX)
				expect(team).to.equal(0)
			end)

			it("round-trips every field at its extreme simultaneously", function()
				local low, high = PositionPacking.pack(X_MAX, Y_MAX, X_MIN, 31)
				local x, y, z, team = PositionPacking.unpack(low, high)
				expect(x).to.equal(X_MAX)
				expect(y).to.equal(Y_MAX)
				expect(z).to.equal(X_MIN)
				expect(team).to.equal(31)
			end)
		end)

		describe("caller contract", function()
			it("requires integer input — pack() throws on a fractional value", function()
				-- pack() trusts its caller to have already rounded (PositionCollector
				-- does this); documenting the throw here pins down that contract so a
				-- future direct caller of PositionPacking doesn't get a silently wrong
				-- result instead of a loud failure.
				expect(function()
					PositionPacking.pack(1.5, 0, 0, 0)
				end).to.throw()
			end)

			it("requires finite input — pack() throws on NaN", function()
				local nan = 0 / 0
				expect(function()
					PositionPacking.pack(nan, 0, 0, 0)
				end).to.throw()
			end)
		end)

		describe("writeEntry()", function()
			it("writes 8 bytes at the given offset without touching neighbors", function()
				local buf = buffer.create(24)
				buffer.fill(buf, 0, 0xFF) -- sentinel to catch out-of-bounds writes

				PositionPacking.writeEntry(buf, 8, 111, 22, 333, 5)

				expect(buffer.readu8(buf, 0)).to.equal(0xFF)
				expect(buffer.readu8(buf, 7)).to.equal(0xFF)
				expect(buffer.readu8(buf, 16)).to.equal(0xFF)
				expect(buffer.readu8(buf, 23)).to.equal(0xFF)

				local low = buffer.readu32(buf, 8)
				local high = buffer.readu32(buf, 12)
				local x, y, z, team = PositionPacking.unpack(low, high)
				expect(x).to.equal(111)
				expect(y).to.equal(22)
				expect(z).to.equal(333)
				expect(team).to.equal(5)
			end)
		end)

	end)
end
