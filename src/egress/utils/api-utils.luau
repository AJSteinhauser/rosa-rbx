local DefaultHttpService = game:GetService("HttpService")
local Constants = require(script.Parent.Parent.Parent.models.constants)
local ApiModels = require(script.Parent.Parent.models.api)
local Rng       = require(script.Parent.Parent.Parent.utils.rng)

-- Equal jitter: wait between 50% and 100% of the nominal backoff so a fleet of
-- instances that failed at the same instant don't retry in lockstep (thundering herd).
local function jitteredBackoff(attempts: number, random: (() -> number)?): number
	local nominal = 2 ^ attempts
	local jitter  = Constants.RETRY_BACKOFF_JITTER
	return nominal * (1 - jitter) + nominal * jitter * (random or Rng.next)()
end

-- Sends an HTTP request, retrying only brief transient failures with jittered backoff.
-- Returns (response, totalAttempts). On exhaustion or a non-retryable status it returns
-- the last response (Success = false) so the caller can trip the appropriate blocker,
-- rather than throwing and losing that decision.
--
-- _services (HttpService, wait, random) is for tests; production callers omit it.
local function sendRetryHandler(request: RequestAsyncRequest, attempts: number?, _services): (HttpResponseData, number)
	attempts = attempts or 0

	local HttpService = (_services and _services.HttpService) or DefaultHttpService
	local wait        = (_services and _services.wait) or task.wait
	local random      = _services and _services.random

	local response = HttpService:RequestAsync(request)

	if response.Success then
		return response, attempts + 1
	end

	local retryable = ApiModels.RETRYABLE_HTTP_STATUS_CODES[response.StatusCode]
	if not retryable or attempts >= Constants.MAX_HTTP_RETRY_ATTEMPTS then
		return response, attempts + 1
	end

	wait(jitteredBackoff(attempts, random))
	return sendRetryHandler(request, attempts + 1, _services)
end

return {
	sendRetryHandler = sendRetryHandler,
	jitteredBackoff  = jitteredBackoff,
}
