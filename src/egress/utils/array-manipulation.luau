-- Splits a table into two halves. Left gets indices 1..mid, right gets mid+1..n.
-- Returns two new tables; the original is not modified.
local function splitArrayInHalf(array: { any }): ({ any }, { any })
	local size = #array
	local mid = math.floor(size / 2)

	local left = {}
	local right = {}
	table.move(array, 1, mid, 1, left)
	table.move(array, mid + 1, size, 1, right)

	return left, right
end

return {
	splitArrayInHalf = splitArrayInHalf,
}
