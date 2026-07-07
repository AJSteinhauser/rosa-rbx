local Constants = require(script.Parent.constants)

return function(attempt: number): number
	return math.min(2 ^ attempt - 1, Constants.RETRY_MAX_BACKOFF_SECONDS)
end
