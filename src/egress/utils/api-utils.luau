local HttpService = game:GetService("HttpService")
local Constants = require(script.Parent.Parent.models.constants)
local ApiModels = require(script.Parent.Parent.models.api)

-- Sends an HTTP request and retries on transient failures with exponential backoff.
-- Returns (response, totalAttempts). Errors if retry limit is exceeded.
local function sendRetryHandler(request: RequestAsyncRequest, retryCount: number?): (RequestAsyncResponse, number)
	retryCount = retryCount or 0

	if retryCount > Constants.MAX_HTTP_RETRY_ATTEMPTS then
		error("ROSA API request failed: exceeded max retry attempts")
	end

	local response = HttpService:RequestAsync(request)

	if not response.Success then
		if not ApiModels.RETRYABLE_HTTP_STATUS_CODES[response.StatusCode] then
			return response, retryCount
		end
		task.wait(2 ^ retryCount)
		return sendRetryHandler(request, retryCount + 1)
	end

	return response, retryCount + 1
end

return {
	sendRetryHandler = sendRetryHandler,
}
