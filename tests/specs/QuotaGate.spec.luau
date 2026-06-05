local ReplicatedStorage = game:GetService("ReplicatedStorage")
local QuotaGate         = require(ReplicatedStorage.RosaRbxPipeline.egress.components["quota-gate"])

local function makeGate(probeInterval)
	local time = 0
	local gate = QuotaGate.new(function() return time end, probeInterval or 1800)
	return gate, function(t) time = t end
end

return function()
	describe("QuotaGate", function()

		describe("initial state", function()

			it("is not blocked by default", function()
				local gate = QuotaGate.new()
				expect(gate:isBlocked()).to.equal(false)
			end)

		end)

		describe("onQuotaExceeded()", function()

			it("blocks events immediately after 403", function()
				local gate, setTime = makeGate()
				setTime(0)
				gate:onQuotaExceeded()
				expect(gate:isBlocked()).to.equal(true)
			end)

			it("remains blocked within the probe interval", function()
				local gate, setTime = makeGate(1800)
				setTime(0)
				gate:onQuotaExceeded()
				setTime(1799)
				expect(gate:isBlocked()).to.equal(true)
			end)

			it("unblocks once the probe interval elapses", function()
				local gate, setTime = makeGate(1800)
				setTime(0)
				gate:onQuotaExceeded()
				setTime(1800)
				expect(gate:isBlocked()).to.equal(false)
			end)

			it("resets the timer on a repeated 403 (failed probe)", function()
				local gate, setTime = makeGate(1800)
				setTime(0)
				gate:onQuotaExceeded()
				setTime(1800) -- probe window opens
				expect(gate:isBlocked()).to.equal(false)
				-- probe fires but gets 403 again
				gate:onQuotaExceeded()
				setTime(1810) -- only 10s after second hit — still blocked
				expect(gate:isBlocked()).to.equal(true)
			end)

			it("requires a full interval after a failed probe", function()
				local gate, setTime = makeGate(1800)
				setTime(0)
				gate:onQuotaExceeded()
				setTime(1800) -- probe window opens
				gate:onQuotaExceeded() -- probe failed, timer resets at t=1800
				setTime(3600) -- 1800s after second hit
				expect(gate:isBlocked()).to.equal(false)
			end)

		end)

		describe("onSuccess()", function()

			it("clears blocked state when probe succeeds", function()
				local gate, setTime = makeGate(1800)
				setTime(0)
				gate:onQuotaExceeded()
				setTime(1800) -- probe window opens
				gate:onSuccess() -- probe succeeded
				expect(gate:isBlocked()).to.equal(false)
			end)

			it("remains unblocked after successful recovery", function()
				local gate, setTime = makeGate(1800)
				setTime(0)
				gate:onQuotaExceeded()
				setTime(1800)
				gate:onSuccess()
				setTime(1801)
				expect(gate:isBlocked()).to.equal(false)
			end)

			it("is a no-op when quota was never exceeded", function()
				local gate = QuotaGate.new()
				expect(function()
					gate:onSuccess()
				end).never.to.throw()
				expect(gate:isBlocked()).to.equal(false)
			end)

			it("allows events again after recovery", function()
				local gate, setTime = makeGate(1800)
				setTime(0)
				gate:onQuotaExceeded()
				setTime(1800)
				gate:onSuccess()
				-- Simulating a new 403 after recovery starts a fresh block
				gate:onQuotaExceeded()
				expect(gate:isBlocked()).to.equal(true)
			end)

		end)

		describe("probe interval", function()

			it("respects a custom probe interval", function()
				local gate, setTime = makeGate(60) -- 60 second interval
				setTime(0)
				gate:onQuotaExceeded()
				setTime(59)
				expect(gate:isBlocked()).to.equal(true)
				setTime(60)
				expect(gate:isBlocked()).to.equal(false)
			end)

			it("blocks at exactly the boundary (exclusive end)", function()
				local gate, setTime = makeGate(100)
				setTime(0)
				gate:onQuotaExceeded()
				setTime(99)
				expect(gate:isBlocked()).to.equal(true)
				setTime(100)
				expect(gate:isBlocked()).to.equal(false)
			end)

		end)

		describe("multiple exceed/recover cycles", function()

			it("handles exceed → recover → exceed → recover correctly", function()
				local gate, setTime = makeGate(100)
				setTime(0)

				gate:onQuotaExceeded()
				expect(gate:isBlocked()).to.equal(true)

				setTime(100)
				gate:onSuccess() -- first recovery
				expect(gate:isBlocked()).to.equal(false)

				gate:onQuotaExceeded() -- second exceed
				expect(gate:isBlocked()).to.equal(true)

				setTime(200)
				gate:onSuccess() -- second recovery
				expect(gate:isBlocked()).to.equal(false)
			end)

		end)

	end)
end
