local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ScalingBuffer = require(ReplicatedStorage.RosaRbxPipeline.utils["scaling-buffer"])

local function readAll(buf: buffer): string
	return buffer.readstring(buf, 0, buffer.len(buf))
end

return function()
	describe("ScalingBuffer", function()

		describe("new()", function()
			it("starts with size 0", function()
				expect(ScalingBuffer.new():size()).to.equal(0)
			end)

			it("getBuffer() on empty buffer returns zero-length buffer", function()
				local result = ScalingBuffer.new():getBuffer()
				expect(buffer.len(result)).to.equal(0)
			end)
		end)

		describe("push_string()", function()
			it("increases size by string length", function()
				local b = ScalingBuffer.new()
				b:push_string("hello")
				expect(b:size()).to.equal(5)
			end)

			it("accumulates size across multiple pushes", function()
				local b = ScalingBuffer.new()
				b:push_string("abc")
				b:push_string("de")
				expect(b:size()).to.equal(5)
			end)

			it("stores the correct data", function()
				local b = ScalingBuffer.new()
				b:push_string("hello world")
				expect(readAll(b:getBuffer())).to.equal("hello world")
			end)

			it("concatenates multiple pushes in order", function()
				local b = ScalingBuffer.new()
				b:push_string("foo")
				b:push_string("bar")
				expect(readAll(b:getBuffer())).to.equal("foobar")
			end)

			it("handles empty string push (size unchanged)", function()
				local b = ScalingBuffer.new()
				b:push_string("")
				expect(b:size()).to.equal(0)
			end)

			it("triggers auto-resize across the 100KB boundary", function()
				local b     = ScalingBuffer.new()
				local chunk = string.rep("x", 10_000)
				for _ = 1, 12 do -- 120KB total
					b:push_string(chunk)
				end
				expect(b:size()).to.equal(120_000)
				expect(buffer.len(b:getBuffer())).to.equal(120_000)
			end)

			-- Bug regression: single push larger than AUTO_ALLOCATE_SIZE (100KB)
			it("handles a single push larger than AUTO_ALLOCATE_SIZE without crashing", function()
				local b    = ScalingBuffer.new()
				local big  = string.rep("z", 150_000) -- 150KB > 100KB allocation chunk
				b:push_string(big)
				expect(b:size()).to.equal(150_000)
				expect(readAll(b:getBuffer())).to.equal(big)
			end)

			it("handles multiple oversized pushes sequentially", function()
				local b   = ScalingBuffer.new()
				local big = string.rep("a", 120_000)
				b:push_string(big)
				b:push_string(big)
				expect(b:size()).to.equal(240_000)
			end)

			it("data integrity is preserved through multiple resize cycles", function()
				local b      = ScalingBuffer.new()
				local pieces = {}
				for i = 1, 5 do
					local s = string.rep(tostring(i), 30_000) -- 30KB each, 150KB total
					b:push_string(s)
					table.insert(pieces, s)
				end
				expect(readAll(b:getBuffer())).to.equal(table.concat(pieces))
			end)
		end)

		describe("push_u8()", function()
			it("writes one byte and advances size by 1", function()
				local b = ScalingBuffer.new()
				b:push_u8(42)
				expect(b:size()).to.equal(1)
				expect(buffer.readu8(b:getBuffer(), 0)).to.equal(42)
			end)

			it("writes 0 correctly", function()
				local b = ScalingBuffer.new()
				b:push_u8(0)
				expect(buffer.readu8(b:getBuffer(), 0)).to.equal(0)
			end)

			it("writes max u8 (255)", function()
				local b = ScalingBuffer.new()
				b:push_u8(255)
				expect(buffer.readu8(b:getBuffer(), 0)).to.equal(255)
			end)

			it("writes multiple u8 values at correct offsets", function()
				local b = ScalingBuffer.new()
				b:push_u8(10)
				b:push_u8(20)
				b:push_u8(30)
				local result = b:getBuffer()
				expect(buffer.readu8(result, 0)).to.equal(10)
				expect(buffer.readu8(result, 1)).to.equal(20)
				expect(buffer.readu8(result, 2)).to.equal(30)
			end)
		end)

		describe("push_u16()", function()
			it("writes two bytes and advances size by 2", function()
				local b = ScalingBuffer.new()
				b:push_u16(1000)
				expect(b:size()).to.equal(2)
				expect(buffer.readu16(b:getBuffer(), 0)).to.equal(1000)
			end)

			it("writes 0 correctly", function()
				local b = ScalingBuffer.new()
				b:push_u16(0)
				expect(buffer.readu16(b:getBuffer(), 0)).to.equal(0)
			end)

			it("writes max u16 (65535)", function()
				local b = ScalingBuffer.new()
				b:push_u16(65535)
				expect(buffer.readu16(b:getBuffer(), 0)).to.equal(65535)
			end)
		end)

		describe("push_u32()", function()
			it("writes four bytes and advances size by 4", function()
				local b = ScalingBuffer.new()
				b:push_u32(100000)
				expect(b:size()).to.equal(4)
				expect(buffer.readu32(b:getBuffer(), 0)).to.equal(100000)
			end)

			it("writes 0 correctly", function()
				local b = ScalingBuffer.new()
				b:push_u32(0)
				expect(buffer.readu32(b:getBuffer(), 0)).to.equal(0)
			end)

			it("writes max u32 (4294967295)", function()
				local b = ScalingBuffer.new()
				b:push_u32(4294967295)
				expect(buffer.readu32(b:getBuffer(), 0)).to.equal(4294967295)
			end)
		end)

		describe("mixed push types", function()
			it("interleaves u8, u16, u32, and string at correct offsets", function()
				local b = ScalingBuffer.new()
				b:push_u8(0xAA)    -- offset 0, size 1
				b:push_u16(0xBBCC) -- offset 1, size 2
				b:push_u32(0xDDEEFF00) -- offset 3, size 4
				b:push_string("hi")    -- offset 7, size 2
				expect(b:size()).to.equal(9)
				local result = b:getBuffer()
				expect(buffer.readu8(result, 0)).to.equal(0xAA)
				expect(buffer.readu16(result, 1)).to.equal(0xBBCC)
				expect(buffer.readu32(result, 3)).to.equal(0xDDEEFF00)
				expect(buffer.readstring(result, 7, 2)).to.equal("hi")
			end)
		end)

		describe("getBuffer()", function()
			it("returns a buffer whose length equals size()", function()
				local b = ScalingBuffer.new()
				b:push_string("test")
				expect(buffer.len(b:getBuffer())).to.equal(b:size())
			end)

			it("returns an independent copy — mutating it does not affect internal state", function()
				local b = ScalingBuffer.new()
				b:push_string("abc")
				local copy1 = b:getBuffer()
				buffer.writeu8(copy1, 0, 0xFF)
				local copy2 = b:getBuffer()
				-- Internal data should still read 'a'
				expect(buffer.readu8(copy2, 0)).to.equal(string.byte("a"))
			end)

			it("successive calls return equal content", function()
				local b = ScalingBuffer.new()
				b:push_string("hello")
				expect(readAll(b:getBuffer())).to.equal(readAll(b:getBuffer()))
			end)
		end)

	end)
end
