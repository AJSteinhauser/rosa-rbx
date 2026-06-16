local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SessionManager    = require(ReplicatedStorage.RosaRbxPipeline.ingestion["session-manager"])

-- SessionManager only uses player as a table key — a plain table works.
local function mockPlayer(name: string)
	return { Name = name } :: any
end

return function()
	describe("SessionManager", function()

		describe("getSessionId()", function()
			it("returns a non-empty string", function()
				local sm = SessionManager.new()
				local id = sm:getSessionId(mockPlayer("Alice"))
				expect(typeof(id)).to.equal("string")
				expect(#id > 0).to.equal(true)
			end)

			it("returns the same session ID on repeated calls for the same player", function()
				local sm     = SessionManager.new()
				local player = mockPlayer("Bob")
				expect(sm:getSessionId(player)).to.equal(sm:getSessionId(player))
			end)

			it("returns different IDs for different players", function()
				local sm  = SessionManager.new()
				local idA = sm:getSessionId(mockPlayer("PlayerA"))
				local idB = sm:getSessionId(mockPlayer("PlayerB"))
				expect(idA).never.to.equal(idB)
			end)

			it("generates a new ID after the session is cleared", function()
				local sm     = SessionManager.new()
				local player = mockPlayer("Charlie")
				local id1    = sm:getSessionId(player)
				sm.sessionStore[player] = nil
				local id2 = sm:getSessionId(player)
				expect(id1).never.to.equal(id2)
			end)

			it("each new SessionManager instance has an independent store", function()
				local player = mockPlayer("Eve")
				local idA    = SessionManager.new():getSessionId(player)
				local idB    = SessionManager.new():getSessionId(player)
				expect(idA).never.to.equal(idB)
			end)

		end)

	end)
end
