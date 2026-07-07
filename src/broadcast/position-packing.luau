local Constants = require(script.Parent.constants)

-- Wire format is documented in constants.luau. Luau's `buffer` has no native u64
-- write, so each entry is written as two little-endian u32 words (low word first) —
-- bit-for-bit identical to one little-endian u64 write.

local X_BITS    = Constants.POSITION_X_BITS
local Z_BITS    = Constants.POSITION_Z_BITS
local Y_BITS    = Constants.POSITION_Y_BITS
local TEAM_BITS = Constants.POSITION_TEAM_BITS

local X_MASK    = bit32.lshift(1, X_BITS) - 1
local Z_MASK    = bit32.lshift(1, Z_BITS) - 1
local Y_MASK    = bit32.lshift(1, Y_BITS) - 1
local TEAM_MASK = bit32.lshift(1, TEAM_BITS) - 1

local Z_LOW_BITS  = 32 - X_BITS
local Z_LOW_MASK  = bit32.lshift(1, Z_LOW_BITS) - 1
local Z_HIGH_BITS = Z_BITS - Z_LOW_BITS

local PositionPacking = {}

-- bit32 ops silently truncate a fractional or non-finite number instead of
-- erroring, so pack()'s "caller must have already rounded" contract has to be
-- enforced explicitly here rather than relying on bit32 to catch it.
local function assertPackable(value: number)
	if value ~= value or value == math.huge or value == -math.huge then
		error("PositionPacking.pack: value must be finite, got " .. tostring(value))
	end
	if value % 1 ~= 0 then
		error("PositionPacking.pack: value must be an integer, got " .. tostring(value))
	end
end

-- bit32.band truncates to field width, which only preserves two's complement if
-- the value fits in that width's signed range — callers must stay in range.
function PositionPacking.pack(x: number, y: number, z: number, team: number): (number, number)
	assertPackable(x)
	assertPackable(y)
	assertPackable(z)
	assertPackable(team)

	local xEnc    = bit32.band(x, X_MASK)
	local zEnc    = bit32.band(z, Z_MASK)
	local yEnc    = bit32.band(y, Y_MASK)
	local teamEnc = bit32.band(team, TEAM_MASK)

	local zLow  = bit32.band(zEnc, Z_LOW_MASK)
	local zHigh = bit32.rshift(zEnc, Z_LOW_BITS)

	local lowWord  = bit32.bor(xEnc, bit32.lshift(zLow, X_BITS))
	local highWord = bit32.bor(zHigh, bit32.lshift(yEnc, Z_HIGH_BITS), bit32.lshift(teamEnc, Z_HIGH_BITS + Y_BITS))

	return lowWord, highWord
end

local function signExtend(value: number, bits: number): number
	local signBit = bit32.lshift(1, bits - 1)
	if bit32.band(value, signBit) ~= 0 then
		return value - bit32.lshift(1, bits)
	end
	return value
end

function PositionPacking.unpack(lowWord: number, highWord: number): (number, number, number, number)
	local xEnc = bit32.band(lowWord, X_MASK)
	local zLow = bit32.band(bit32.rshift(lowWord, X_BITS), Z_LOW_MASK)

	local zHigh  = bit32.band(highWord, bit32.lshift(1, Z_HIGH_BITS) - 1)
	local zEnc   = bit32.bor(zLow, bit32.lshift(zHigh, Z_LOW_BITS))
	local yEnc   = bit32.band(bit32.rshift(highWord, Z_HIGH_BITS), Y_MASK)
	local teamId = bit32.band(bit32.rshift(highWord, Z_HIGH_BITS + Y_BITS), TEAM_MASK)

	local x = signExtend(xEnc, X_BITS)
	local z = signExtend(zEnc, Z_BITS)
	local y = signExtend(yEnc, Y_BITS)

	return x, y, z, teamId
end

function PositionPacking.writeEntry(buf: buffer, byteOffset: number, x: number, y: number, z: number, team: number)
	local lowWord, highWord = PositionPacking.pack(x, y, z, team)
	buffer.writeu32(buf, byteOffset, lowWord)
	buffer.writeu32(buf, byteOffset + 4, highWord)
end

return PositionPacking
