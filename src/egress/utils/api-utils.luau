local HttpService = game:GetService("HttpService")
local Constants = require(script.Parent.Parent.Parent.models.constants)
local ApiModels = require(script.Parent.Parent.models.api)
local Rng       = require(script.Parent.Parent.Parent.utils.rng)

-- Equal jitter: wait between 50% and 100% of the nominal backoff so a fleet of
-- instances that failed at the same instant don't retry in lockstep (thundering herd).
local function jitteredBackoff(attempts: number): number
	local nominal = 2 ^ attempts
	local jitter  = Constants.RETRY_BACKOFF_JITTER
	return nominal * (1 - jitter) + nominal * jitter * Rng.next()
end

-- Sends an HTTP request, retrying only brief transient failures with jittered backoff.
-- Returns (response, totalAttempts). On exhaustion or a non-retryable status it returns
-- the last response (Success = false) so the caller can trip the appropriate blocker,
-- rather than throwing and losing that decision.
local function sendRetryHandler(request: RequestAsyncRequest, attempts: number?): (HttpResponseData, number)
	attempts = attempts or 0

	local response = HttpService:RequestAsync(request)

	if response.Success then
		return response, attempts + 1
	end

	local retryable = ApiModels.RETRYABLE_HTTP_STATUS_CODES[response.StatusCode]
	if not retryable or attempts >= Constants.MAX_HTTP_RETRY_ATTEMPTS then
		return response, attempts + 1
	end

	task.wait(jitteredBackoff(attempts))
	return sendRetryHandler(request, attempts + 1)
end

return {
	sendRetryHandler = sendRetryHandler,
}
