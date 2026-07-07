local ReplicatedStorage = game:GetService("ReplicatedStorage")
local LeaderElection = require(ReplicatedStorage.RosaRbx.broadcast["leader-election"])

local function makeHashMap(initial)
	local value = initial
	return {
		UpdateAsync = function(_, _key, transformFn, _expiration)
			value = transformFn(value)
			return value
		end,
	}
end

-- These specs run inside real Studio, where the real RunService:IsStudio() is
-- true. Force it false so LeaderElection exercises the live-server/MemoryStore
-- path instead of the Studio shortcut (covered separately below).
local function liveServer()
	return { IsStudio = function() return false end }
end

return function()
	describe("LeaderElection", function()

		describe("tryElectOrRenew()", function()
			it("elects itself when no leader exists", function()
				local election = LeaderElection.new({ hashMap = makeHashMap(nil), jobId = "job-A", RunService = liveServer() })
				expect(election:tryElectOrRenew()).to.equal(true)
			end)

			it("renews when it is already the leader", function()
				local election = LeaderElection.new({ hashMap = makeHashMap("job-A"), jobId = "job-A", RunService = liveServer() })
				expect(election:tryElectOrRenew()).to.equal(true)
			end)

			it("does not take over a live lease held by another server", function()
				local election = LeaderElection.new({ hashMap = makeHashMap("job-B"), jobId = "job-A", RunService = liveServer() })
				expect(election:tryElectOrRenew()).to.equal(false)
			end)

			it("leaves another server's lease value untouched", function()
				local capturedTransformResult = "unset"
				local hashMap = {
					UpdateAsync = function(_, _key, transformFn)
						capturedTransformResult = transformFn("job-B")
						return "job-B" -- simulates UpdateAsync aborting the write
					end,
				}
				local election = LeaderElection.new({ hashMap = hashMap, jobId = "job-A", RunService = liveServer() })
				election:tryElectOrRenew()
				expect(capturedTransformResult).to.equal(nil)
			end)

			it("returns false and does not throw when UpdateAsync errors", function()
				local hashMap = {
					UpdateAsync = function()
						error("network error")
					end,
				}
				local election = LeaderElection.new({ hashMap = hashMap, jobId = "job-A", RunService = liveServer() })
				local result
				expect(function()
					result = election:tryElectOrRenew()
				end).never.to.throw()
				expect(result).to.equal(false)
			end)

			it("elects then renews in sequence on the same instance", function()
				local election = LeaderElection.new({ hashMap = makeHashMap(nil), jobId = "job-A", RunService = liveServer() })
				expect(election:tryElectOrRenew()).to.equal(true) -- elects (was nil)
				expect(election:tryElectOrRenew()).to.equal(true) -- renews (already us)
				expect(election:tryElectOrRenew()).to.equal(true) -- renews again
			end)

			it("enforces mutual exclusion between two instances sharing one store", function()
				local sharedHashMap = makeHashMap(nil)
				local serverA = LeaderElection.new({ hashMap = sharedHashMap, jobId = "job-A", RunService = liveServer() })
				local serverB = LeaderElection.new({ hashMap = sharedHashMap, jobId = "job-B", RunService = liveServer() })

				expect(serverA:tryElectOrRenew()).to.equal(true)  -- A claims the empty lease
				expect(serverB:tryElectOrRenew()).to.equal(false) -- B can't take it from A
				expect(serverA:tryElectOrRenew()).to.equal(true)  -- A keeps renewing
				expect(serverB:tryElectOrRenew()).to.equal(false) -- B still locked out
			end)

			it("works correctly with an empty-string jobId (game.JobId on a live server)", function()
				-- Roblox's game.JobId is "" in some contexts rather than nil — must
				-- not be confused with "no leader" (nil) by an accidental falsy check.
				local election = LeaderElection.new({ hashMap = makeHashMap(nil), jobId = "", RunService = liveServer() })
				expect(election:tryElectOrRenew()).to.equal(true)
				expect(election:isLeader()).to.equal(true)

				local other = LeaderElection.new({ hashMap = election.hashMap, jobId = "job-B", RunService = liveServer() })
				expect(other:tryElectOrRenew()).to.equal(false)
			end)

			it("only uses UpdateAsync's first return value, ignoring any extra ones (e.g. real MemoryStore's keyInfo)", function()
				local hashMap = {
					UpdateAsync = function(_, _key, transformFn)
						return transformFn(nil), { fakeKeyInfo = true }
					end,
				}
				local election = LeaderElection.new({ hashMap = hashMap, jobId = "job-A", RunService = liveServer() })
				expect(election:tryElectOrRenew()).to.equal(true)
			end)

			it("passes LEADER_LEASE_TTL_SECONDS to UpdateAsync's expiration by default", function()
				local capturedExpiration
				local hashMap = {
					UpdateAsync = function(_, _key, transformFn, expiration)
						capturedExpiration = expiration
						return transformFn(nil)
					end,
				}
				local election = LeaderElection.new({ hashMap = hashMap, jobId = "job-A", RunService = liveServer() })
				election:tryElectOrRenew()
				expect(capturedExpiration).to.equal(35)
			end)

			it("uses a caller-supplied ttlSeconds instead of the default when given one", function()
				local capturedExpiration
				local hashMap = {
					UpdateAsync = function(_, _key, transformFn, expiration)
						capturedExpiration = expiration
						return transformFn(nil)
					end,
				}
				local election = LeaderElection.new({ hashMap = hashMap, jobId = "job-A", RunService = liveServer() })
				election:tryElectOrRenew(35 * 60)
				expect(capturedExpiration).to.equal(35 * 60)
			end)
		end)

		describe("connectHashMap() (GetHashMap retry)", function()
			it("returns false without throwing from tryElectOrRenew() while still connecting", function()
				local election = LeaderElection.new({ hashMap = makeHashMap(nil), jobId = "job-A", RunService = liveServer() })
				election.hashMap = nil -- simulate GetHashMap not having succeeded yet

				local result
				expect(function()
					result = election:tryElectOrRenew()
				end).never.to.throw()
				expect(result).to.equal(false)
			end)

			it("retries GetHashMap with backoff until it succeeds, then elects normally", function()
				local fakeHashMap = makeHashMap(nil)
				local attempts = 0
				local memoryStoreService = {
					GetHashMap = function()
						attempts += 1
						if attempts < 3 then
							error("MemoryStore unavailable")
						end
						return fakeHashMap
					end,
				}
				local waitedFor = {}
				local election = LeaderElection.new({
					MemoryStoreService = memoryStoreService,
					jobId = "job-A",
					RunService = liveServer(),
					wait = function(seconds) table.insert(waitedFor, seconds) end,
				})

				expect(attempts).to.equal(3)
				expect(election.hashMap).to.equal(fakeHashMap)
				expect(waitedFor[1]).to.equal(0) -- backoffSeconds(0)
				expect(waitedFor[2]).to.equal(1) -- backoffSeconds(1)
				expect(election:tryElectOrRenew()).to.equal(true)
			end)
		end)

		describe("isLeader()", function()
			it("defaults to false before any election attempt", function()
				local election = LeaderElection.new({ hashMap = makeHashMap(nil), jobId = "job-A", RunService = liveServer() })
				expect(election:isLeader()).to.equal(false)
			end)

			it("reflects the last tryElectOrRenew() result without re-querying MemoryStore", function()
				local calls = 0
				local hashMap = {
					UpdateAsync = function(_, _key, transformFn)
						calls += 1
						return transformFn(nil)
					end,
				}
				local election = LeaderElection.new({ hashMap = hashMap, jobId = "job-A", RunService = liveServer() })
				election:tryElectOrRenew()
				expect(calls).to.equal(1)
				expect(election:isLeader()).to.equal(true)
				expect(calls).to.equal(1)
			end)
		end)

		describe("in Studio", function()
			local function studio()
				return { IsStudio = function() return true end }
			end

			it("assumes leadership immediately, without a hashMap", function()
				local election = LeaderElection.new({ jobId = "job-A", RunService = studio() })
				expect(election:tryElectOrRenew()).to.equal(true)
				expect(election:isLeader()).to.equal(true)
			end)

			it("never calls GetHashMap", function()
				local getHashMapCalled = false
				local memoryStoreService = {
					GetHashMap = function()
						getHashMapCalled = true
						return makeHashMap(nil)
					end,
				}
				local election = LeaderElection.new({ jobId = "job-A", RunService = studio(), MemoryStoreService = memoryStoreService })
				election:tryElectOrRenew()

				expect(getHashMapCalled).to.equal(false)
				expect(election.hashMap).to.equal(nil)
			end)

			it("never calls UpdateAsync even if a hashMap is somehow present", function()
				local updateAsyncCalled = false
				local hashMap = {
					UpdateAsync = function()
						updateAsyncCalled = true
						return "job-A"
					end,
				}
				local election = LeaderElection.new({ jobId = "job-A", RunService = studio(), hashMap = hashMap })
				expect(election:tryElectOrRenew()).to.equal(true)
				expect(updateAsyncCalled).to.equal(false)
			end)
		end)

	end)
end
