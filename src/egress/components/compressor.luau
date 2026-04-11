local EncodingService = game:GetService("EncodingService")
local Constants = require(script.Parent.Parent.models.constants)

-- Attempts to compress a buffer using Zstd at increasing compression levels.
-- Returns the compressed buffer if it fits within HTTPS_BODY_LIMIT, otherwise nil.
local function compress(data: buffer): buffer?
	for compressionAmount = 1, 21, 5 do
		local compressed = EncodingService:CompressBuffer(
			data,
			Enum.CompressionAlgorithm.Zstd,
			compressionAmount
		)
		if buffer.len(compressed) < Constants.HTTPS_BODY_LIMIT then
			return compressed
		end
	end
	return nil
end

return {
	compress = compress,
}
