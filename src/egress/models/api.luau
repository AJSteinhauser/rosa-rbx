-- HTTP status codes that are safe to retry after a backoff delay.
local RETRYABLE_HTTP_STATUS_CODES = {
	[408] = true, -- Request Timeout
	[429] = true, -- Too Many Requests
	[500] = true, -- Internal Server Error
	[502] = true, -- Bad Gateway
	[503] = true, -- Service Unavailable
	[504] = true, -- Gateway Timeout
}

return {
	RETRYABLE_HTTP_STATUS_CODES = RETRYABLE_HTTP_STATUS_CODES,
}
