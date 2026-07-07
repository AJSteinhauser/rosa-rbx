local HttpService = game:GetService("HttpService")
local Constants = require(script.Parent.Parent.Parent.models.constants)
local Version   = require(script.Parent.Parent.Parent.models.version)
local JobId     = require(script.Parent.Parent.Parent.utils["job-id"])

local shardId = JobId.jobId

local function generateHeader(httpService)
	local secretService = httpService or HttpService
	return {
		["x-rosa-api-key"]         = secretService:GetSecret(Constants.SECRETS_KEY_LOOKUP),
		["x-rosa-idempotency-key"] = HttpService:GenerateGUID(false),
		["x-rosa-module-version"]  = Version,
		["x-shard-id"]             = shardId,
		["content-type"]           = "application/octet-stream"
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
