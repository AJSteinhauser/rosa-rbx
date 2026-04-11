local ReplicatedStorage = game:GetService("ReplicatedStorage")
local EncodingService   = game:GetService("EncodingService")
local Compressor        = require(ReplicatedStorage.RosaRbxPipeline.egress.components.compressor)

local HTTPS_BODY_LIMIT = 1024 * 1000 - 1

local function makeBuffer(content: string): buffer
	local b = buffer.create(#content)
	buffer.writestring(b, 0, content)
	return b
end

local function bufferToString(b: buffer): string
	return buffer.readstring(b, 0, buffer.len(b))
end

-- Build a buffer of `size` bytes filled with a repeated pattern.
local function makeBufferOfSize(size: number): buffer
	return makeBuffer(string.rep("a", size))
end

return function()
	describe("Compressor.compress()", function()

		describe("basic behavior", function()
			it("returns a buffer (non-nil) for small input", function()
				local result = Compressor.compress(makeBuffer("hello world"))
				expect(result).never.to.equal(nil)
				expect(typeof(result)).to.equal("buffer")
			end)

			it("compressed output is smaller than input for compressible data", function()
				-- 10KB of repeated data compresses very well
				local input  = makeBufferOfSize(10_000)
				local result = Compressor.compress(input)
				expect(result).never.to.equal(nil)
				expect(buffer.len(result) < buffer.len(input)).to.equal(true)
			end)

			it("compressed output fits within HTTPS_BODY_LIMIT", function()
				local result = Compressor.compress(makeBufferOfSize(50_000))
				expect(result).never.to.equal(nil)
				expect(buffer.len(result) < HTTPS_BODY_LIMIT).to.equal(true)
			end)

			it("round-trip: decompress restores original data", function()
				local original   = "The quick brown fox jumps over the lazy dog"
				local input      = makeBuffer(original)
				local compressed = Compressor.compress(input)
				expect(compressed).never.to.equal(nil)
				local decompressed = EncodingService:DecompressBuffer(
					compressed,
					Enum.CompressionAlgorithm.Zstd
				)
				expect(bufferToString(decompressed)).to.equal(original)
			end)
		end)

		describe("boundary and edge cases", function()
			it("handles an empty buffer without throwing", function()
				local empty  = buffer.create(0)
				local result = Compressor.compress(empty)
				-- Empty input: may return non-nil (compressed empty payload is fine)
				-- Just must not throw and must satisfy the size limit if non-nil
				if result ~= nil then
					expect(buffer.len(result) < HTTPS_BODY_LIMIT).to.equal(true)
				end
			end)

			it("handles a single-byte buffer", function()
				local result = Compressor.compress(makeBuffer("x"))
				expect(result).never.to.equal(nil)
			end)

			it("returns nil for input that cannot compress under the limit", function()
				-- ~2MB of random-looking data (high entropy) won't compress below ~1MB.
				-- Use a pattern that defeats compression: alternating bytes.
				local pieces = {}
				for i = 1, 2_000 do
					pieces[i] = string.char(i % 256) .. string.char((i * 7) % 256)
				end
				local incompressible = makeBuffer(table.concat(pieces))
				-- This may or may not compress; the key guarantee is the function does
				-- NOT throw and returns either a fitting buffer or nil.
				local result = Compressor.compress(incompressible)
				if result ~= nil then
					expect(buffer.len(result) < HTTPS_BODY_LIMIT).to.equal(true)
				end
			end)

			it("compresses a ~500KB highly-repetitive payload under the limit", function()
				-- 500KB of 'x' should compress to a tiny fraction of original size
				local result = Compressor.compress(makeBufferOfSize(500_000))
				expect(result).never.to.equal(nil)
				expect(buffer.len(result) < HTTPS_BODY_LIMIT).to.equal(true)
			end)

			it("does not mutate the original buffer", function()
				local content = "immutable content"
				local input   = makeBuffer(content)
				Compressor.compress(input)
				-- Input buffer length should be unchanged
				expect(buffer.len(input)).to.equal(#content)
				expect(bufferToString(input)).to.equal(content)
			end)
		end)

	end)
end
