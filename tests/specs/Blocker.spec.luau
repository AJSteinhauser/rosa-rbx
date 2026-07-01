local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Blocker           = require(ReplicatedStorage.RosaRbx.egress.components["blocker"])

local function makeBlocker(probeInterval, maxInterval, jitterFraction, random)
	local time = 0
	local b    = Blocker.new("test", probeInterval or 1800, function() return time end, maxInterval, jitterFraction, random)
	return b, function(t) time = t end
end

return function()
	describe("Blocker", function()

		describe("initial state", function()

			it("is not blocked by default", function()
				expect(Blocker.new("test"):isBlocked()).to.equal(false)
			end)

		end)

		describe("onBlocked()", function()

			it("blocks immediately", function()
				local b, setTime = makeBlocker()
				setTime(0)
				b:onBlocked()
				expect(b:isBlocked()).to.equal(true)
			end)

			it("remains blocked within the probe interval", function()
				local b, setTime = makeBlocker(1800)
				setTime(0)
				b:onBlocked()
				setTime(1799)
				expect(b:isBlocked()).to.equal(true)
			end)

			it("unblocks once the probe interval elapses", function()
				local b, setTime = makeBlocker(1800)
				setTime(0)
				b:onBlocked()
				setTime(1800)
				expect(b:isBlocked()).to.equal(false)
			end)

			it("resets the timer on a repeated call (failed probe)", function()
				local b, setTime = makeBlocker(1800)
				setTime(0)
				b:onBlocked()
				setTime(1800)
				b:onBlocked() -- failed probe; timer resets at t=1800
				setTime(1810)
				expect(b:isBlocked()).to.equal(true)
			end)

			it("requires a full interval after a failed probe", function()
				local b, setTime = makeBlocker(1800)
				setTime(0)
				b:onBlocked()
				setTime(1800)
				b:onBlocked()
				setTime(3600)
				expect(b:isBlocked()).to.equal(false)
			end)

		end)

		describe("onSuccess()", function()

			it("clears the blocked state", function()
				local b, setTime = makeBlocker()
				setTime(0)
				b:onBlocked()
				b:onSuccess()
				expect(b:isBlocked()).to.equal(false)
			end)

			it("is a no-op when never blocked", function()
				local b = Blocker.new("test")
				expect(function() b:onSuccess() end).never.to.throw()
				expect(b:isBlocked()).to.equal(false)
			end)

			it("allows a fresh block after recovery", function()
				local b, setTime = makeBlocker()
				setTime(0)
				b:onBlocked()
				b:onSuccess()
				b:onBlocked()
				expect(b:isBlocked()).to.equal(true)
			end)

		end)

		describe("probe interval", function()

			it("respects a custom probe interval", function()
				local b, setTime = makeBlocker(60)
				setTime(0)
				b:onBlocked()
				setTime(59)
				expect(b:isBlocked()).to.equal(true)
				setTime(60)
				expect(b:isBlocked()).to.equal(false)
			end)

			it("boundary is exclusive (blocks at n-1, opens at n)", function()
				local b, setTime = makeBlocker(100)
				setTime(0)
				b:onBlocked()
				setTime(99)
				expect(b:isBlocked()).to.equal(true)
				setTime(100)
				expect(b:isBlocked()).to.equal(false)
			end)

		end)

		describe("multiple block/recover cycles", function()

			it("handles block → recover → block → recover correctly", function()
				local b, setTime = makeBlocker(100)
				setTime(0)

				b:onBlocked()
				expect(b:isBlocked()).to.equal(true)
				setTime(100)
				b:onSuccess()
				expect(b:isBlocked()).to.equal(false)

				b:onBlocked()
				expect(b:isBlocked()).to.equal(true)
				setTime(200)
				b:onSuccess()
				expect(b:isBlocked()).to.equal(false)
			end)

		end)

		describe("two independent instances", function()

			it("quota and auth blockers have separate state", function()
				local quota, setQTime = makeBlocker(100)
				local auth,  setATime = makeBlocker(100)

				setQTime(0)
				setATime(0)
				quota:onBlocked()

				expect(quota:isBlocked()).to.equal(true)
				expect(auth:isBlocked()).to.equal(false)
			end)

			it("recovering one does not affect the other", function()
				local quota, setQTime = makeBlocker(100)
				local auth,  _        = makeBlocker(100)

				setQTime(0)
				quota:onBlocked()
				auth:onBlocked()
				quota:onSuccess()

				expect(quota:isBlocked()).to.equal(false)
				expect(auth:isBlocked()).to.equal(true)
			end)

		end)

		describe("exponential backoff (maxInterval set)", function()

			it("doubles the interval on each consecutive failed probe", function()
				local b, setTime = makeBlocker(100, 10000)
				setTime(0)
				b:onBlocked() -- interval = 100
				setTime(100)
				b:onBlocked() -- failed probe; interval = 200
				setTime(299)
				expect(b:isBlocked()).to.equal(true)
				setTime(300)
				expect(b:isBlocked()).to.equal(false)
			end)

			it("caps growth at maxInterval", function()
				local b, setTime = makeBlocker(100, 350)
				setTime(0)
				b:onBlocked() -- interval = 100
				setTime(100)
				b:onBlocked() -- interval = 200
				setTime(300)
				b:onBlocked() -- interval = min(400, 350) = 350
				setTime(649)
				expect(b:isBlocked()).to.equal(true)
				setTime(650)
				expect(b:isBlocked()).to.equal(false)
			end)

			it("resets to base interval after a success", function()
				local b, setTime = makeBlocker(100, 10000)
				setTime(0)
				b:onBlocked() -- interval = 100
				setTime(100)
				b:onBlocked() -- interval = 200
				setTime(300)
				b:onSuccess()

				b:onBlocked() -- interval back to base = 100
				setTime(399)
				expect(b:isBlocked()).to.equal(true)
				setTime(400)
				expect(b:isBlocked()).to.equal(false)
			end)

			it("does not grow when maxInterval is omitted (default behavior)", function()
				local b, setTime = makeBlocker(100)
				setTime(0)
				b:onBlocked() -- interval = 100
				setTime(100)
				b:onBlocked() -- would be 200, but no maxInterval given so capped at base = 100
				setTime(199)
				expect(b:isBlocked()).to.equal(true)
				setTime(200)
				expect(b:isBlocked()).to.equal(false)
			end)

		end)

		describe("jitter", function()

			it("shortens the interval by up to jitterFraction", function()
				-- jitter 0.5, random = 1.0 → interval reduced by full 50%
				local b, setTime = makeBlocker(100, 100, 0.5, function() return 1.0 end)
				setTime(0)
				b:onBlocked() -- interval = 100 * (1 - 0.5*1.0) = 50
				setTime(49)
				expect(b:isBlocked()).to.equal(true)
				setTime(50)
				expect(b:isBlocked()).to.equal(false)
			end)

			it("never lengthens the interval (random = 0 keeps full interval)", function()
				local b, setTime = makeBlocker(100, 100, 0.5, function() return 0 end)
				setTime(0)
				b:onBlocked() -- interval = 100 * (1 - 0.5*0) = 100
				setTime(99)
				expect(b:isBlocked()).to.equal(true)
				setTime(100)
				expect(b:isBlocked()).to.equal(false)
			end)

		end)

		describe("Retry-After override", function()

			it("acts as a floor longer than the exponential interval", function()
				local b, setTime = makeBlocker(100, 10000)
				setTime(0)
				b:onBlocked(500) -- exponential = 100, Retry-After = 500 wins
				setTime(499)
				expect(b:isBlocked()).to.equal(true)
				setTime(500)
				expect(b:isBlocked()).to.equal(false)
			end)

			it("is ignored when shorter than the exponential interval", function()
				local b, setTime = makeBlocker(100, 10000)
				setTime(0)
				b:onBlocked()   -- interval = 100
				setTime(100)
				b:onBlocked(20) -- exponential = 200, Retry-After 20 is smaller → 200 wins
				setTime(299)
				expect(b:isBlocked()).to.equal(true)
				setTime(300)
				expect(b:isBlocked()).to.equal(false)
			end)

			it("is capped at maxInterval", function()
				local b, setTime = makeBlocker(100, 350)
				setTime(0)
				b:onBlocked(99999) -- Retry-After huge, but capped at maxInterval = 350
				setTime(349)
				expect(b:isBlocked()).to.equal(true)
				setTime(350)
				expect(b:isBlocked()).to.equal(false)
			end)

		end)

	end)
end
