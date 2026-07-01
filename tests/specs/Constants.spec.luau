local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Constants = require(ReplicatedStorage.RosaRbx.models.constants)
local ApiModels = require(ReplicatedStorage.RosaRbx.egress.models.api)

return function()
	describe("Constants", function()

		it("ACCUMULATOR_BUCKET_SIZE is a positive number", function()
			expect(typeof(Constants.ACCUMULATOR_BUCKET_SIZE)).to.equal("number")
			expect(Constants.ACCUMULATOR_BUCKET_SIZE > 0).to.equal(true)
		end)

		it("ACCUMULATOR_LEAK_PER_SECOND is a positive number", function()
			expect(typeof(Constants.ACCUMULATOR_LEAK_PER_SECOND)).to.equal("number")
			expect(Constants.ACCUMULATOR_LEAK_PER_SECOND > 0).to.equal(true)
		end)

		it("HTTPS_BODY_LIMIT is roughly 1MB", function()
			expect(typeof(Constants.HTTPS_BODY_LIMIT)).to.equal("number")
			expect(Constants.HTTPS_BODY_LIMIT).to.be.near(1024 * 1000, 10)
		end)

		it("BODY_OVERSHOOT_TARGET is larger than HTTPS_BODY_LIMIT", function()
			expect(Constants.BODY_OVERSHOOT_TARGET > Constants.HTTPS_BODY_LIMIT).to.equal(true)
		end)

		it("MAX_HTTP_RETRY_ATTEMPTS is a positive integer", function()
			expect(typeof(Constants.MAX_HTTP_RETRY_ATTEMPTS)).to.equal("number")
			expect(Constants.MAX_HTTP_RETRY_ATTEMPTS > 0).to.equal(true)
			expect(Constants.MAX_HTTP_RETRY_ATTEMPTS % 1).to.equal(0)
		end)

		it("SECRETS_KEY_LOOKUP is a non-empty string", function()
			expect(typeof(Constants.SECRETS_KEY_LOOKUP)).to.equal("string")
			expect(#Constants.SECRETS_KEY_LOOKUP > 0).to.equal(true)
		end)

		it("EVENTS_API_ROUTE is an HTTPS URL", function()
			expect(typeof(Constants.EVENTS_API_ROUTE)).to.equal("string")
			expect(Constants.EVENTS_API_ROUTE:sub(1, 8)).to.equal("https://")
		end)

		it("EVENTS_API_ROUTE contains INGESTION_BASE_API_ROUTE as a prefix", function()
			expect(Constants.EVENTS_API_ROUTE:sub(1, #Constants.INGESTION_BASE_API_ROUTE))
				.to.equal(Constants.INGESTION_BASE_API_ROUTE)
		end)

	end)

	describe("ApiModels.RETRYABLE_HTTP_STATUS_CODES", function()

		it("is a table", function()
			expect(typeof(ApiModels.RETRYABLE_HTTP_STATUS_CODES)).to.equal("table")
		end)

		it("includes 408 (Request Timeout)", function()
			expect(ApiModels.RETRYABLE_HTTP_STATUS_CODES[408]).to.equal(true)
		end)

		it("does not mark 429 as inline-retryable (trips the rate-limit blocker instead)", function()
			expect(ApiModels.RETRYABLE_HTTP_STATUS_CODES[429]).never.to.equal(true)
		end)

		it("includes 500 (Internal Server Error)", function()
			expect(ApiModels.RETRYABLE_HTTP_STATUS_CODES[500]).to.equal(true)
		end)

		it("includes 502 (Bad Gateway)", function()
			expect(ApiModels.RETRYABLE_HTTP_STATUS_CODES[502]).to.equal(true)
		end)

		it("includes 503 (Service Unavailable)", function()
			expect(ApiModels.RETRYABLE_HTTP_STATUS_CODES[503]).to.equal(true)
		end)

		it("includes 504 (Gateway Timeout)", function()
			expect(ApiModels.RETRYABLE_HTTP_STATUS_CODES[504]).to.equal(true)
		end)

		it("does not mark 200 as retryable", function()
			expect(ApiModels.RETRYABLE_HTTP_STATUS_CODES[200]).never.to.equal(true)
		end)

		it("does not mark 404 as retryable", function()
			expect(ApiModels.RETRYABLE_HTTP_STATUS_CODES[404]).never.to.equal(true)
		end)

		it("does not mark 401 as retryable", function()
			expect(ApiModels.RETRYABLE_HTTP_STATUS_CODES[401]).never.to.equal(true)
		end)

	end)
end
