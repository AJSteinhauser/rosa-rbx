-- Dynamically resizing buffer for accumulating string/binary data.
-- Grows in 100KB chunks to avoid frequent reallocations.

local AUTO_ALLOCATE_SIZE = 100_000

local ScalingBuffer = {}
ScalingBuffer.__index = ScalingBuffer

function ScalingBuffer.new()
	local self = setmetatable({}, ScalingBuffer)
	self.currentSize = 0
	self.buf = buffer.create(AUTO_ALLOCATE_SIZE)
	return self
end

function ScalingBuffer:size(): number
	return self.currentSize
end

-- extraNeeded lets callers request more than the default chunk when a single
-- push would exceed the standard allocation size (e.g. a >100KB string).
function ScalingBuffer:resizeBuffer(extraNeeded: number?)
	local extra = math.max(extraNeeded or 0, AUTO_ALLOCATE_SIZE)
	local newBuf = buffer.create(self.currentSize + extra)
	buffer.copy(newBuf, 0, self.buf, 0, self.currentSize)
	self.buf = newBuf
end

function ScalingBuffer:push_u8(value: number)
	if self.currentSize + 1 >= buffer.len(self.buf) then
		self:resizeBuffer()
	end
	buffer.writeu8(self.buf, self.currentSize, value)
	self.currentSize += 1
end

function ScalingBuffer:push_u16(value: number)
	if self.currentSize + 2 >= buffer.len(self.buf) then
		self:resizeBuffer()
	end
	buffer.writeu16(self.buf, self.currentSize, value)
	self.currentSize += 2
end

function ScalingBuffer:push_u32(value: number)
	if self.currentSize + 4 >= buffer.len(self.buf) then
		self:resizeBuffer()
	end
	buffer.writeu32(self.buf, self.currentSize, value)
	self.currentSize += 4
end

function ScalingBuffer:push_string(value: string)
	if self.currentSize + #value >= buffer.len(self.buf) then
		self:resizeBuffer(#value)
	end
	buffer.writestring(self.buf, self.currentSize, value)
	self.currentSize += #value
end

-- Returns a tightly-sized copy of the accumulated data.
function ScalingBuffer:getBuffer(): buffer
	local result = buffer.create(self.currentSize)
	buffer.copy(result, 0, self.buf, 0, self.currentSize)
	return result
end

return ScalingBuffer
