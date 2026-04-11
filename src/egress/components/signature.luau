local HttpService = game:GetService("HttpService")
local Constants = require(script.Parent.Parent.models.constants)

-- Generates HTTP headers for an API request.
-- The api-secret is fetched from Roblox secrets (never exposed in plaintext).
-- The idempotency-key prevents duplicate processing if the request is retried.
local function generateHeader()
	return {
		["api-secret"]      = HttpService:GetSecret(Constants.SECRETS_KEY_LOOKUP),
		["idempotency-key"] = HttpService:GenerateGUID(false),
	}
end

-- Once Roblox supports hashing secrets, a proper HMAC signature can be generated:
--
-- local function generateHeader(data: buffer)
--     local EncodingService = game:GetService("EncodingService")
--     local timestamp = os.time()
--     local nonce = math.random(0, 255)
--     local bodyHash = EncodingService:ComputeBufferHash(data, Enum.HashAlgorithm.Sha256)
--     local apiKey = HttpService:GetSecret(Constants.SECRETS_KEY_LOOKUP)
--     apiKey:AddSuffix(string.format("%d+%d+%s", timestamp, nonce, bodyHash))
--     local signature = EncodingService:ComputeStringHash(apiKey, Enum.HashAlgorithm.Sha256)
--     return {
--         ["Rosa-Signature"] = signature,
--         ["Rosa-Timestamp"] = timestamp,
--         ["Rosa-Nonce"]     = nonce,
--     }
-- end

return {
	generateHeader = generateHeader,
}
