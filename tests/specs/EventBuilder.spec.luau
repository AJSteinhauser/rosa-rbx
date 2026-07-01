local ReplicatedStorage = game:GetService("ReplicatedStorage")
local EventBuilder      = require(ReplicatedStorage.RosaRbx.ingestion["event-builder"])

local function makeHttpService()
	local n = 0
	return {
		GenerateGUID = function(_, _urlSafe)
			n += 1
			return "guid-" .. n
		end,
	}
end

local function makeBuilder(config, overrides)
	overrides = overrides or {}
	local services = {
		HttpService     = overrides.HttpService or makeHttpService(),
		sessionManager  = overrides.sessionManager or {
			getSessionId = function(_, _player) return "session-1" end,
		},
		platformManager = overrides.platformManager or {
			getPlatform = function(_, _player) return Enum.UserInputType.Gamepad1 end,
		},
		getPlaceVersion = overrides.getPlaceVersion or function() return "42" end,
	}
	return EventBuilder.new(config, services), services
end

local function makePlayer()
	return { Name = "TestPlayer" }
end

return function()
	describe("EventBuilder:buildEvent position resolution", function()

		it("returns nil when no position is available", function()
			local builder = makeBuilder({ getPosition = function() return nil end })
			local event   = builder:buildEvent(makePlayer(), { tag = "Test" })

			expect(event).to.equal(nil)
		end)

		it("uses eventRequest.position when explicitly provided, skipping config.getPosition", function()
			local calledConfigGetPosition = false
			local builder = makeBuilder({
				getPosition = function() calledConfigGetPosition = true; return Vector3.new(9, 9, 9) end,
			})

			local event = builder:buildEvent(makePlayer(), { tag = "Test", position = Vector3.new(1, 2, 3) })

			expect(calledConfigGetPosition).to.equal(false)
			expect(event.position.x).to.equal(1)
			expect(event.position.y).to.equal(2)
			expect(event.position.z).to.equal(3)
		end)

		it("falls back to config.getPosition(player) when eventRequest.position is absent", function()
			local builder = makeBuilder({
				getPosition = function(player) return Vector3.new(4, 5, 6) end,
			})

			local event = builder:buildEvent(makePlayer(), { tag = "Test" })

			expect(event.position.x).to.equal(4)
			expect(event.position.y).to.equal(5)
			expect(event.position.z).to.equal(6)
		end)

	end)

	describe("EventBuilder:buildEvent platform resolution", function()

		it("converts an EnumItem platform to its Name", function()
			local builder = makeBuilder(
				{ getPosition = function() return Vector3.new(0, 0, 0) end },
				{ platformManager = { getPlatform = function() return Enum.UserInputType.Gamepad1 end } }
			)

			local event = builder:buildEvent(makePlayer(), { tag = "Test" })

			expect(event.platform).to.equal("Gamepad1")
		end)

		it("stringifies a non-EnumItem platform (e.g. the 'Unknown' timeout fallback)", function()
			local builder = makeBuilder(
				{ getPosition = function() return Vector3.new(0, 0, 0) end },
				{ platformManager = { getPlatform = function() return "Unknown" end } }
			)

			local event = builder:buildEvent(makePlayer(), { tag = "Test" })

			expect(event.platform).to.equal("Unknown")
		end)

	end)

	describe("EventBuilder:buildEvent version resolution", function()

		it("uses config.getVersion() when provided", function()
			local builder = makeBuilder({
				getPosition = function() return Vector3.new(0, 0, 0) end,
				getVersion  = function() return "1.2.3" end,
			})

			local event = builder:buildEvent(makePlayer(), { tag = "Test" })

			expect(event.version).to.equal("1.2.3")
		end)

		it("falls back to getPlaceVersion() when config.getVersion is absent", function()
			local builder = makeBuilder(
				{ getPosition = function() return Vector3.new(0, 0, 0) end },
				{ getPlaceVersion = function() return "99" end }
			)

			local event = builder:buildEvent(makePlayer(), { tag = "Test" })

			expect(event.version).to.equal("99")
		end)

	end)

	describe("EventBuilder:buildEvent field passthrough", function()

		it("pulls sessionID from the injected sessionManager", function()
			local builder = makeBuilder(
				{ getPosition = function() return Vector3.new(0, 0, 0) end },
				{ sessionManager = { getSessionId = function(_, player) return "session-for-" .. player.Name end } }
			)

			local event = builder:buildEvent(makePlayer(), { tag = "Test" })

			expect(event.sessionID).to.equal("session-for-TestPlayer")
		end)

		it("includes teamId and mapName when the config hooks are present", function()
			local builder = makeBuilder({
				getPosition  = function() return Vector3.new(0, 0, 0) end,
				getTeamName  = function() return "Red" end,
				getMapName   = function() return "Skyline" end,
			})

			local event = builder:buildEvent(makePlayer(), { tag = "Test" })

			expect(event.teamId).to.equal("Red")
			expect(event.mapName).to.equal("Skyline")
		end)

		it("omits teamId and mapName when the config hooks are absent", function()
			local builder = makeBuilder({ getPosition = function() return Vector3.new(0, 0, 0) end })

			local event = builder:buildEvent(makePlayer(), { tag = "Test" })

			expect(event.teamId).to.equal(nil)
			expect(event.mapName).to.equal(nil)
		end)

		it("passes tag, quantity, and custom through unchanged", function()
			local builder = makeBuilder({ getPosition = function() return Vector3.new(0, 0, 0) end })
			local custom  = { foo = "bar" }

			local event = builder:buildEvent(makePlayer(), { tag = "Damage", quantity = 12, custom = custom })

			expect(event.tag).to.equal("Damage")
			expect(event.quantity).to.equal(12)
			expect(event.custom).to.equal(custom)
		end)

		it("generates a unique eventId per event via the injected HttpService", function()
			local builder = makeBuilder({ getPosition = function() return Vector3.new(0, 0, 0) end })

			local event1 = builder:buildEvent(makePlayer(), { tag = "Test" })
			local event2 = builder:buildEvent(makePlayer(), { tag = "Test" })

			expect(typeof(event1.eventId)).to.equal("string")
			expect(event1.eventId).never.to.equal(event2.eventId)
		end)

		it("stamps eventTimeStamp with a positive number", function()
			local builder = makeBuilder({ getPosition = function() return Vector3.new(0, 0, 0) end })

			local event = builder:buildEvent(makePlayer(), { tag = "Test" })

			expect(typeof(event.eventTimeStamp)).to.equal("number")
			expect(event.eventTimeStamp > 0).to.equal(true)
		end)

	end)
end
