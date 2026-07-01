-- HTTP status codes that are safe to retry inline after a short backoff.
-- 429 is deliberately NOT here: it means the server is asking us to back off, so it
-- trips the rate-limit blocker (halting the whole instance) instead of retrying harder.
-- Sustained 5xx also trips the server blocker once these inline retries are exhausted.
local RETRYABLE_HTTP_STATUS_CODES = {
	[408] = true, -- Request Timeout
	[500] = true, -- Internal Server Error
	[502] = true, -- Bad Gateway
	[503] = true, -- Service Unavailable
	[504] = true, -- Gateway Timeout
}

return {
	RETRYABLE_HTTP_STATUS_CODES = RETRYABLE_HTTP_STATUS_CODES,
}
