local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RealHttpService = game:GetService("HttpService")
local LeaderPoller = require(ReplicatedStorage.RosaRbx.broadcast["leader-poller"])

local function response(success, statusCode, body)
	return { Success = success, StatusCode = statusCode, StatusMessage = "", Body = body or "" }
end

-- Repeats the last response for calls beyond the list, like ApiUtils.spec's fake.
local function makeHttpService(responses)
	local svc = { callCount = 0 }
	svc.RequestAsync = function(_, _request)
		svc.callCount += 1
		return responses[svc.callCount] or responses[#responses]
	end
	svc.JSONDecode = function(_, json)
		return RealHttpService:JSONDecode(json)
	end
	svc.GetSecret = function() return "fake-secret" end
	return svc
end

local function makeLeaderElection(isLeader)
	return { tryElectOrRenew = function() return isLeader end }
end

local function makeBroadcastSignal()
	local signal = { publishCount = 0 }
	signal.publishStart = function()
		signal.publishCount += 1
	end
	return signal
end

return function()
	describe("LeaderPoller", function()

		describe("poll()", function()
			it("does not call the ingestion server when not the leader", function()
				local http = makeHttpService({ response(true, 200, RealHttpService:JSONEncode({ activeViewer = true })) })
				local broadcastSignal = makeBroadcastSignal()
				local poller = LeaderPoller.new(makeLeaderElection(false), broadcastSignal, { HttpService = http })

				poller:poll()

				expect(http.callCount).to.equal(0)
				expect(broadcastSignal.publishCount).to.equal(0)
			end)

			it("publishes the start signal when leader and activeViewer is true", function()
				local http = makeHttpService({ response(true, 200, RealHttpService:JSONEncode({ activeViewer = true })) })
				local broadcastSignal = makeBroadcastSignal()
				local poller = LeaderPoller.new(makeLeaderElection(true), broadcastSignal, { HttpService = http })

				poller:poll()

				expect(http.callCount).to.equal(1)
				expect(broadcastSignal.publishCount).to.equal(1)
			end)

			it("does not publish when activeViewer is false", function()
				local http = makeHttpService({ response(true, 200, RealHttpService:JSONEncode({ activeViewer = false })) })
				local broadcastSignal = makeBroadcastSignal()
				local poller = LeaderPoller.new(makeLeaderElection(true), broadcastSignal, { HttpService = http })

				poller:poll()

				expect(broadcastSignal.publishCount).to.equal(0)
			end)

			it("does not publish and does not throw when the poll request fails", function()
				local http = makeHttpService({ response(false, 500) })
				local broadcastSignal = makeBroadcastSignal()
				local poller = LeaderPoller.new(makeLeaderElection(true), broadcastSignal, { HttpService = http, wait = function() end })

				expect(function()
					poller:poll()
				end).never.to.throw()
				expect(broadcastSignal.publishCount).to.equal(0)
			end)

			it("does not throw and does not publish when the response body is not a JSON object", function()
				-- A bare `true`/number/string body would crash `decoded.activeViewer`
				-- if not type-checked first (see leader-poller.luau).
				for _, encoded in { RealHttpService:JSONEncode(true), RealHttpService:JSONEncode(42), "not json at all" } do
					local http = makeHttpService({ response(true, 200, encoded) })
					local broadcastSignal = makeBroadcastSignal()
					local poller = LeaderPoller.new(makeLeaderElection(true), broadcastSignal, { HttpService = http })

					expect(function()
						poller:poll()
					end).never.to.throw()
					expect(broadcastSignal.publishCount).to.equal(0)
				end
			end)

			it("does not publish when activeViewer is truthy but not the literal boolean true", function()
				-- A malformed/wrongly-typed value (a truthy string, or 1/0 instead of
				-- a real boolean) must not be misread as "active" and trigger an
				-- accidental fleet-wide broadcast — see leader-poller.luau.
				for _, activeViewerValue in { "true", "false", 1, 0, "1", {} } do
					local http = makeHttpService({
						response(true, 200, RealHttpService:JSONEncode({ activeViewer = activeViewerValue })),
					})
					local broadcastSignal = makeBroadcastSignal()
					local poller = LeaderPoller.new(makeLeaderElection(true), broadcastSignal, { HttpService = http })

					poller:poll()

					expect(broadcastSignal.publishCount).to.equal(0)
				end
			end)

		end)

		describe("not-entitled cadence", function()
			it("slows the poll interval way down after a 402", function()
				local http = makeHttpService({ response(false, 402) })
				local poller = LeaderPoller.new(makeLeaderElection(true), makeBroadcastSignal(), { HttpService = http })

				expect(poller.pollIntervalSeconds).to.equal(15)
				poller:poll()
				expect(poller.pollIntervalSeconds).to.equal(30 * 60)
			end)

			it("still renews the leader lease every cycle while not entitled, just with a longer TTL", function()
				local http = makeHttpService({ response(false, 402), response(false, 402) })
				local capturedTtls = {}
				local election = {
					tryElectOrRenew = function(_, ttl)
						table.insert(capturedTtls, ttl)
						return true
					end,
				}
				local poller = LeaderPoller.new(election, makeBroadcastSignal(), { HttpService = http })

				poller:poll() -- normal cadence going in
				poller:poll() -- now in not-entitled mode

				expect(#capturedTtls).to.equal(2)
				expect(capturedTtls[1]).to.equal(35)      -- LEADER_LEASE_TTL_SECONDS
				expect(capturedTtls[2]).to.equal(35 * 60)  -- BROADCAST_NOT_ENTITLED_LEASE_TTL_SECONDS
			end)

			it("resumes the normal interval once a poll comes back as something other than 402", function()
				local http = makeHttpService({
					response(false, 402),
					response(true, 200, RealHttpService:JSONEncode({ activeViewer = true })),
				})
				local broadcastSignal = makeBroadcastSignal()
				local poller = LeaderPoller.new(makeLeaderElection(true), broadcastSignal, { HttpService = http })

				poller:poll()
				expect(poller.pollIntervalSeconds).to.equal(30 * 60)

				poller:poll()
				expect(poller.pollIntervalSeconds).to.equal(15)
				expect(broadcastSignal.publishCount).to.equal(1)
			end)

			it("start()'s wait loop uses the current pollIntervalSeconds, not a fixed constant", function()
				local http = makeHttpService({
					response(true, 200, RealHttpService:JSONEncode({ activeViewer = false })),
					response(false, 402),
				})
				local waitedFor = {}
				local poller
				local wait = function(seconds)
					table.insert(waitedFor, seconds)
					if #waitedFor >= 2 then poller:stop() end
				end
				poller = LeaderPoller.new(makeLeaderElection(true), makeBroadcastSignal(), { HttpService = http, wait = wait })

				poller:start()

				expect(waitedFor[1]).to.equal(15)
				expect(waitedFor[2]).to.equal(30 * 60)
			end)
		end)

		describe("start() / stop()", function()
			it("stops issuing polls once stopped", function()
				local pollCount = 0
				local fakeElection = {
					tryElectOrRenew = function()
						pollCount += 1
						return false
					end,
				}
				local broadcastSignal = makeBroadcastSignal()
				local waitCalls = 0
				local poller
				local wait = function()
					waitCalls += 1
					if waitCalls >= 3 then
						poller:stop()
					end
				end
				poller = LeaderPoller.new(fakeElection, broadcastSignal, { HttpService = makeHttpService({}), wait = wait })

				poller:start()

				expect(pollCount >= 3).to.equal(true)
				expect(poller.running).to.equal(false)
			end)

			it("keeps looping after poll() throws instead of dying silently", function()
				local poller = LeaderPoller.new(makeLeaderElection(false), makeBroadcastSignal(), {
					HttpService = makeHttpService({}),
					wait = function() end,
				})

				local callCount = 0
				poller.poll = function()
					callCount += 1
					if callCount == 1 then
						error("simulated unexpected failure")
					end
					if callCount >= 3 then
						poller:stop()
					end
				end

				expect(function()
					poller:start()
				end).never.to.throw()

				expect(callCount >= 3).to.equal(true)
			end)

			it("start() is a no-op when already running", function()
				local poller = LeaderPoller.new(makeLeaderElection(false), makeBroadcastSignal(), {
					HttpService = makeHttpService({}),
					wait = function() end,
				})
				poller.running = true -- simulate an in-flight loop without actually spawning one

				local pollCalled = false
				poller.poll = function()
					pollCalled = true
				end
				poller:start()

				expect(pollCalled).to.equal(false)
			end)
		end)

	end)
end
