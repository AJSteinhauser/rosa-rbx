local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ApiUtils = require(ReplicatedStorage.RosaRbx.egress.utils["api-utils"])
local Constants = require(ReplicatedStorage.RosaRbx.models.constants)

local function response(success, statusCode)
	return { Success = success, StatusCode = statusCode, StatusMessage = "", Body = "" }
end

-- Returns a fake HttpService that replays `responses` in order, repeating the
-- last one if RequestAsync is called more times than there are responses.
local function makeHttpService(responses)
	local svc = { callCount = 0 }
	svc.RequestAsync = function(_, _request)
		svc.callCount += 1
		return responses[svc.callCount] or responses[#responses]
	end
	return svc
end

local function makeWait()
	local waits = {}
	return waits, function(seconds) table.insert(waits, seconds) end
end

return function()
	describe("sendRetryHandler", function()

		it("returns immediately on success without waiting", function()
			local http           = makeHttpService({ response(true, 200) })
			local waits, wait    = makeWait()

			local result, attempts = ApiUtils.sendRetryHandler({}, nil, { HttpService = http, wait = wait })

			expect(result.Success).to.equal(true)
			expect(attempts).to.equal(1)
			expect(http.callCount).to.equal(1)
			expect(#waits).to.equal(0)
		end)

		it("does not retry a non-retryable status code", function()
			for _, code in { 400, 401, 403, 404, 429 } do
				local http        = makeHttpService({ response(false, code) })
				local waits, wait = makeWait()

				local result, attempts = ApiUtils.sendRetryHandler({}, nil, { HttpService = http, wait = wait })

				expect(result.Success).to.equal(false)
				expect(result.StatusCode).to.equal(code)
				expect(attempts).to.equal(1)
				expect(http.callCount).to.equal(1)
				expect(#waits).to.equal(0)
			end
		end)

		it("retries a retryable status code and succeeds once the transient failure clears", function()
			local http        = makeHttpService({ response(false, 503), response(true, 200) })
			local waits, wait = makeWait()

			local result, attempts = ApiUtils.sendRetryHandler({}, nil, { HttpService = http, wait = wait })

			expect(result.Success).to.equal(true)
			expect(attempts).to.equal(2)
			expect(http.callCount).to.equal(2)
			expect(#waits).to.equal(1)
		end)

		it("gives up after MAX_HTTP_RETRY_ATTEMPTS retries and returns the last failure", function()
			local http        = makeHttpService({ response(false, 500) })
			local waits, wait = makeWait()

			local result, attempts = ApiUtils.sendRetryHandler({}, nil, { HttpService = http, wait = wait })

			local expectedRequests = Constants.MAX_HTTP_RETRY_ATTEMPTS + 1
			expect(result.Success).to.equal(false)
			expect(result.StatusCode).to.equal(500)
			expect(attempts).to.equal(expectedRequests)
			expect(http.callCount).to.equal(expectedRequests)
			expect(#waits).to.equal(Constants.MAX_HTTP_RETRY_ATTEMPTS)
		end)

		it("treats every code in RETRYABLE_HTTP_STATUS_CODES as retryable", function()
			local ApiModels = require(ReplicatedStorage.RosaRbx.egress.models["api"])
			for code in ApiModels.RETRYABLE_HTTP_STATUS_CODES do
				local http        = makeHttpService({ response(false, code), response(true, 200) })
				local waits, wait = makeWait()

				local result, attempts = ApiUtils.sendRetryHandler({}, nil, { HttpService = http, wait = wait })

				expect(result.Success).to.equal(true)
				expect(attempts).to.equal(2)
				expect(#waits).to.equal(1)
			end
		end)

		it("passes the same request table through to every retry attempt", function()
			local seen  = {}
			local http  = {
				RequestAsync = function(_, request)
					table.insert(seen, request)
					if #seen < 2 then return response(false, 500) end
					return response(true, 200)
				end,
			}
			local _, wait = makeWait()
			local request = { Url = "https://example.com" }

			ApiUtils.sendRetryHandler(request, nil, { HttpService = http, wait = wait })

			expect(#seen).to.equal(2)
			expect(seen[1]).to.equal(request)
			expect(seen[2]).to.equal(request)
		end)

	end)

	describe("jitteredBackoff", function()

		it("returns the lower bound of the jitter range when random() is 0", function()
			local jitter = Constants.RETRY_BACKOFF_JITTER
			for attempts = 0, 3 do
				local nominal  = 2 ^ attempts
				local expected = nominal * (1 - jitter)
				expect(ApiUtils.jitteredBackoff(attempts, function() return 0 end)).to.be.near(expected, 1e-6)
			end
		end)

		it("returns the full nominal backoff when random() is 1", function()
			for attempts = 0, 3 do
				local nominal = 2 ^ attempts
				expect(ApiUtils.jitteredBackoff(attempts, function() return 1 end)).to.be.near(nominal, 1e-6)
			end
		end)

		it("stays within [nominal * (1 - jitter), nominal] for the default RNG", function()
			local jitter = Constants.RETRY_BACKOFF_JITTER
			for attempts = 0, 4 do
				local nominal = 2 ^ attempts
				for _ = 1, 20 do
					local value = ApiUtils.jitteredBackoff(attempts)
					expect(value >= nominal * (1 - jitter)).to.equal(true)
					expect(value <= nominal).to.equal(true)
				end
			end
		end)

	end)
end
