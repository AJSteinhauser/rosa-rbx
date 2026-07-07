local ReplicatedStorage = game:GetService("ReplicatedStorage")
local PositionBroadcaster = require(ReplicatedStorage.RosaRbx.broadcast["position-broadcaster"])
local Constants = require(ReplicatedStorage.RosaRbx.broadcast.constants)

local function response(success, statusCode)
	return { Success = success, StatusCode = statusCode, StatusMessage = "", Body = "" }
end

local function makeHttpService(responses)
	local svc = { callCount = 0 }
	svc.RequestAsync = function(_, _request)
		svc.callCount += 1
		return responses[svc.callCount] or responses[#responses]
	end
	svc.GetSecret = function() return "fake-secret" end
	return svc
end

-- Lets a test drive the max-duration ceiling without a real 30-minute wait: the
-- fake `wait` advances the fake clock instead of yielding.
local function makeClock(start: number?)
	local t = start or 0
	local function now() return t end
	local function advance(seconds: number) t += seconds end
	return now, advance
end

return function()
	describe("PositionBroadcaster", function()

		describe("sendPositions()", function()
			it("returns (true, true) on a 200 response", function()
				local broadcaster = PositionBroadcaster.new({ HttpService = makeHttpService({ response(true, 200) }) })
				local shouldContinue, succeeded = broadcaster:sendPositions()
				expect(shouldContinue).to.equal(true)
				expect(succeeded).to.equal(true)
			end)

			it("returns (false, true) on a 204 response", function()
				local broadcaster = PositionBroadcaster.new({ HttpService = makeHttpService({ response(true, 204) }) })
				local shouldContinue, succeeded = broadcaster:sendPositions()
				expect(shouldContinue).to.equal(false)
				expect(succeeded).to.equal(true)
			end)

			it("returns (true, false) and does not throw when the request fails", function()
				local broadcaster = PositionBroadcaster.new({
					HttpService = makeHttpService({ response(false, 500) }),
					wait = function() end,
				})
				local shouldContinue, succeeded
				expect(function()
					shouldContinue, succeeded = broadcaster:sendPositions()
				end).never.to.throw()
				expect(shouldContinue).to.equal(true)
				expect(succeeded).to.equal(false)
			end)

			it("sends the packed buffer to the positions route", function()
				local seenRequest
				local http = {
					RequestAsync = function(_, request)
						seenRequest = request
						return response(true, 200)
					end,
					GetSecret = function() return "fake-secret" end,
				}
				local broadcaster = PositionBroadcaster.new({ HttpService = http })
				broadcaster:sendPositions()

				expect(seenRequest.Url).to.equal(Constants.BROADCAST_POSITIONS_API_ROUTE)
				expect(seenRequest.Method).to.equal("POST")
				expect(type(seenRequest.Body)).to.equal("string")
			end)
		end)

		describe("onSignalReceived() / start() / stop()", function()
			it("broadcasts until the server responds with the stop status", function()
				local http = makeHttpService({ response(true, 204) })
				local broadcaster = PositionBroadcaster.new({ HttpService = http, wait = function() end })

				broadcaster:onSignalReceived()

				expect(http.callCount).to.equal(1)
				expect(broadcaster.isBroadcasting).to.equal(false)
			end)

			it("ignores a duplicate signal received while already broadcasting", function()
				local sendCount = 0
				local broadcaster
				local http = {
					RequestAsync = function()
						sendCount += 1
						if sendCount >= 2 then
							return response(true, 204)
						end
						return response(true, 200)
					end,
					GetSecret = function() return "fake-secret" end,
				}
				local waitCalls = 0
				local wait = function()
					waitCalls += 1
					if waitCalls == 1 then
						-- Simulate MessagingService delivering the same signal twice.
						broadcaster:onSignalReceived()
					end
				end
				broadcaster = PositionBroadcaster.new({ HttpService = http, wait = wait })

				broadcaster:onSignalReceived()

				expect(sendCount).to.equal(2)
			end)

			it("start() is a no-op when already broadcasting", function()
				local broadcaster = PositionBroadcaster.new({ HttpService = makeHttpService({}), wait = function() end })
				broadcaster.isBroadcasting = true

				local sendCalled = false
				broadcaster.sendPositions = function()
					sendCalled = true
					return false, true
				end
				broadcaster:start()

				expect(sendCalled).to.equal(false)
			end)

			it("keeps looping after sendPositions() throws instead of getting stuck broadcasting forever", function()
				local broadcaster = PositionBroadcaster.new({ HttpService = makeHttpService({}), wait = function() end })

				local callCount = 0
				broadcaster.sendPositions = function()
					callCount += 1
					if callCount == 1 then
						error("simulated packing failure, e.g. a non-finite position")
					end
					return callCount < 3, true -- stop on the 3rd successful call
				end

				expect(function()
					broadcaster:start()
				end).never.to.throw()

				expect(callCount).to.equal(3)
				expect(broadcaster.isBroadcasting).to.equal(false)
			end)

			it("does not set a cooldown when the server stops it normally via 204", function()
				-- Only the safety ceilings should impose a cooldown — an explicit,
				-- well-behaved stop from the server must not be penalized with one.
				local http = makeHttpService({ response(true, 204) })
				local broadcaster = PositionBroadcaster.new({ HttpService = http, wait = function() end })

				broadcaster:onSignalReceived()

				expect(broadcaster.isBroadcasting).to.equal(false)
				expect(broadcaster.cooldownUntil).to.equal(nil)
			end)
		end)

		describe("max duration ceiling", function()
			it("stops on its own once the max broadcast duration elapses, even though the server keeps saying continue", function()
				local http = makeHttpService({ response(true, 200) }) -- server never sends 204
				local now, advance = makeClock(0)
				local wait = function(seconds) advance(seconds) end
				local broadcaster = PositionBroadcaster.new({ HttpService = http, wait = wait, now = now })

				broadcaster:onSignalReceived()

				expect(broadcaster.isBroadcasting).to.equal(false)
				expect(now() >= Constants.BROADCAST_MAX_DURATION_SECONDS).to.equal(true)
				expect(broadcaster.cooldownUntil).to.be.ok()
			end)

			it("ignores a new signal received during the post-ceiling cooldown", function()
				local http = makeHttpService({ response(true, 200) })
				local now, advance = makeClock(0)
				local wait = function(seconds) advance(seconds) end
				local broadcaster = PositionBroadcaster.new({ HttpService = http, wait = wait, now = now })

				broadcaster:onSignalReceived() -- runs until the ceiling trips
				local callCountAtCeiling = http.callCount

				broadcaster:onSignalReceived() -- arrives while still cooling down

				expect(broadcaster.isBroadcasting).to.equal(false)
				expect(http.callCount).to.equal(callCountAtCeiling)
			end)

			it("accepts a new signal once the cooldown has elapsed", function()
				local http = makeHttpService({ response(true, 204) }) -- stops itself on the next call
				local now, advance = makeClock(0)
				local wait = function(seconds) advance(seconds) end
				local broadcaster = PositionBroadcaster.new({ HttpService = http, wait = wait, now = now })

				broadcaster.isBroadcasting = false
				broadcaster.cooldownUntil = 100
				advance(101) -- past the cooldown

				broadcaster:onSignalReceived()

				expect(http.callCount).to.equal(1)
			end)

			it("trips exactly at the boundary (>=), not one cycle late", function()
				local checkCount = 0
				local now = function()
					checkCount += 1
					if checkCount == 1 then return 0 end -- startedAt
					return Constants.BROADCAST_MAX_DURATION_SECONDS -- every check thereafter: exactly at the ceiling
				end
				local broadcaster = PositionBroadcaster.new({ wait = function() end, now = now })

				local sendCalls = 0
				broadcaster.sendPositions = function()
					sendCalls += 1
					return true, true
				end

				broadcaster:start()

				expect(sendCalls).to.equal(0) -- ceiling check trips before ever sending
				expect(broadcaster.isBroadcasting).to.equal(false)
				expect(broadcaster.cooldownUntil).to.be.ok()
			end)

			it("does not trip one second before the boundary", function()
				local checkCount = 0
				local now = function()
					checkCount += 1
					if checkCount == 1 then return 0 end
					return Constants.BROADCAST_MAX_DURATION_SECONDS - 1
				end
				local broadcaster = PositionBroadcaster.new({ wait = function() end, now = now })

				local sendCalls = 0
				broadcaster.sendPositions = function()
					sendCalls += 1
					return false, true -- stop normally right after, so the loop can't run forever
				end

				broadcaster:start()

				expect(sendCalls).to.equal(1) -- ceiling had not tripped yet, so it proceeded to send
				expect(broadcaster.cooldownUntil).to.equal(nil) -- stopped normally, not via the ceiling
			end)

			it("trips on the very first check if the clock jumps far past the ceiling in one step (e.g. the server process was frozen/suspended)", function()
				local checkCount = 0
				local now = function()
					checkCount += 1
					if checkCount == 1 then return 0 end
					return Constants.BROADCAST_MAX_DURATION_SECONDS * 10 -- huge overshoot in a single step
				end
				local broadcaster = PositionBroadcaster.new({ wait = function() end, now = now })

				local sendCalls = 0
				broadcaster.sendPositions = function()
					sendCalls += 1
					return true, true
				end

				broadcaster:start()

				expect(sendCalls).to.equal(0)
				expect(broadcaster.isBroadcasting).to.equal(false)
				expect(broadcaster.cooldownUntil).to.be.ok()
			end)
		end)

		describe("consecutive-failure ceiling", function()
			it("gives up and enters cooldown after too many consecutive failures, instead of retrying forever", function()
				local http = makeHttpService({ response(false, 500) }) -- server unreachable/erroring
				local broadcaster = PositionBroadcaster.new({ HttpService = http, wait = function() end })

				broadcaster:onSignalReceived()

				expect(broadcaster.isBroadcasting).to.equal(false)
				expect(broadcaster.cooldownUntil).to.be.ok()
				expect(broadcaster.consecutiveFailures >= Constants.MAX_CONSECUTIVE_SEND_FAILURES).to.equal(true)
			end)

			it("resets the failure counter on any success, so intermittent failures never trip the ceiling", function()
				local broadcaster = PositionBroadcaster.new({ wait = function() end })

				local callCount = 0
				broadcaster.sendPositions = function()
					callCount += 1
					if callCount > 30 then
						return false, true -- end the test
					end
					local succeeded = callCount % 2 == 0 -- alternates fail/succeed
					return true, succeeded
				end

				broadcaster:start()

				expect(callCount).to.equal(31)
				expect(broadcaster.cooldownUntil).to.equal(nil)
			end)

			it("recovers cleanly after a cooldown — a fresh session isn't sabotaged by the previous session's failure count", function()
				local phase = "failing"
				local http = {
					RequestAsync = function()
						if phase == "failing" then
							return response(false, 500)
						end
						return response(true, 204) -- healthy again; stops itself right away
					end,
					GetSecret = function() return "fake-secret" end,
				}
				local now, advance = makeClock(0)
				local wait = function(seconds) advance(seconds) end
				local broadcaster = PositionBroadcaster.new({ HttpService = http, wait = wait, now = now })

				broadcaster:onSignalReceived() -- fails repeatedly until the failure ceiling trips
				expect(broadcaster.consecutiveFailures >= Constants.MAX_CONSECUTIVE_SEND_FAILURES).to.equal(true)
				expect(broadcaster.cooldownUntil).to.be.ok()

				advance(Constants.BROADCAST_COOLDOWN_SECONDS + 1) -- let the cooldown fully elapse
				phase = "recovered"

				broadcaster:onSignalReceived()

				expect(broadcaster.consecutiveFailures).to.equal(0) -- not still carrying the old count
				expect(broadcaster.isBroadcasting).to.equal(false)  -- stopped normally via the 204
			end)
		end)

	end)
end
