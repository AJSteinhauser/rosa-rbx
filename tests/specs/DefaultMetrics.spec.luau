local ReplicatedStorage = game:GetService("ReplicatedStorage")
local DefaultMetrics    = require(ReplicatedStorage.RosaRbx.ingestion["default-metrics"])

-- This suite locks in the config.<group> ~= false / == true gating in
-- default-metrics/init.luau. A one-line typo here silently enables or
-- disables a metric for every game using the SDK, so every group gets an
-- isolated "default enabled/disabled" + "explicit override" pair.

local function makeSignal()
	local cbs = {}
	return {
		Connect = function(_, fn) table.insert(cbs, fn) end,
		Fire    = function(_, ...) for _, fn in cbs do fn(...) end end,
	}
end

local function makeHandler()
	local serverCalls = {}
	local clientCalls = {}
	local allowedTags = {}
	return {
		serverCalls    = serverCalls,
		clientCalls    = clientCalls,
		allowedTags    = allowedTags,
		addServerEvent = function(_, player, event) table.insert(serverCalls, { player = player, event = event }) end,
		addClientEvent = function(_, event) table.insert(clientCalls, event) end,
		allowClientTag = function(_, tag) allowedTags[tag] = true end,
	}
end

local function findServerTag(handler, tag)
	for _, call in handler.serverCalls do
		if call.event.tag == tag then return call.event end
	end
	return nil
end

local function findClientTag(handler, tag)
	for _, event in handler.clientCalls do
		if event.tag == tag then return event end
	end
	return nil
end

local function makeHumanoid()
	return {
		Health        = 100,
		MaxHealth     = 100,
		HealthChanged = makeSignal(),
		StateChanged  = makeSignal(),
		Died          = makeSignal(),
		Jumping       = makeSignal(),
	}
end

local function makeTool(name)
	return {
		Name       = name,
		Equipped   = makeSignal(),
		Activated  = makeSignal(),
		Destroying = makeSignal(),
		IsA        = function(_, className) return className == "Tool" end,
	}
end

-- A single fake player/character/humanoid/backpack fixture shared across every
-- module in a test. Only the group under test is ever enabled at once, so
-- there's no cross-talk even though most modules watch the same player.
local function makePlayer()
	local humanoid = makeHumanoid()
	local root     = { Position = Vector3.new(0, 0, 0) }
	local backpack = { items = {}, GetChildren = function(self) return self.items end, ChildAdded = makeSignal() }
	local character = {
		WaitForChild   = function(_, name) if name == "Humanoid" then return humanoid end end,
		FindFirstChild = function(_, name) if name == "HumanoidRootPart" then return root end end,
	}
	local teamChanged = makeSignal()

	return {
		Name           = "TestPlayer",
		UserId         = 1,
		Team           = nil,
		Character      = nil,
		CharacterAdded = makeSignal(),
		Chatted        = makeSignal(),
		humanoid       = humanoid,
		character      = character,
		backpack       = backpack,
		WaitForChild   = function(_, name) if name == "Backpack" then return backpack end end,
		GetPropertyChangedSignal = function(_, name) if name == "Team" then return teamChanged end end,
		fireTeamChanged = function() teamChanged:Fire() end,
	}
end

local function makeServices(player, overrides)
	local services = {
		Players = {
			PlayerAdded       = makeSignal(),
			PlayerRemoving    = makeSignal(),
			GetPlayers        = function() return { player } end,
			GetPlayerByUserId = function(_, userId) if player.UserId == userId then return player end end,
			LocalPlayer       = player,
		},
		RunService = {
			Heartbeat = makeSignal(),
			IsStudio  = function() return true end,
		},
		HttpService = {
			GenerateGUID = function() return "guid" end,
		},
		MarketplaceService = {
			PromptProductPurchaseFinished   = makeSignal(),
			PromptGamePassPurchaseFinished  = makeSignal(),
		},
		ProximityPromptService = {
			PromptTriggered = makeSignal(),
		},
		GuiService = {
			MenuOpened = makeSignal(),
		},
		UserInputService = {
			LastInputTypeChanged = makeSignal(),
			TouchEnabled         = true,
			GetConnectedGamepads = function() return { Enum.UserInputType.Gamepad1 } end,
		},
		getTime = function() return 0 end,
		random  = function() return 0 end,
		delay   = function(_, fn) fn() end, -- synchronous: bypasses InputMethodChanged's debounce in tests
	}
	for k, v in (overrides or {}) do services[k] = v end
	return services
end

local ALL_GROUPS = {
	"playerEvents", "characterEvents", "humanoidStateEvents", "paths", "proximityEvents",
	"toolEvents", "damageEvents", "idleDetection", "marketplaceEvents", "chatEvents",
	"teamEvents", "jumpEvents", "inputMethodChanged", "settingsEvents",
}

-- Every group disabled; callers flip on/override just the one(s) under test.
local function allDisabledConfig()
	local config = {}
	for _, group in ALL_GROUPS do config[group] = false end
	return config
end

local function makeUserConfig(player, config)
	return {
		defaultMetrics = config,
		getPosition = function(p)
			return p.Character and p.Character.Position or nil
		end,
	}
end

return function()

	describe("DefaultMetrics.setup server group gating", function()

		it("playerEvents: fires by default, silent when disabled", function()
			for _, enabled in { true, false } do
				local player  = makePlayer()
				local handler = makeHandler()
				local config  = allDisabledConfig()
				if enabled then config.playerEvents = nil end
				local services = makeServices(player)

				DefaultMetrics.setup(handler, config, makeUserConfig(player, config), services)
				services.Players.PlayerAdded:Fire(player)

				local joined = findServerTag(handler, "PlayerJoin")
				if enabled then expect(joined).to.be.ok() else expect(joined).never.to.be.ok() end
			end
		end)

		it("characterEvents: fires by default, silent when disabled", function()
			for _, enabled in { true, false } do
				local player  = makePlayer()
				local handler = makeHandler()
				local config  = allDisabledConfig()
				if enabled then config.characterEvents = nil end
				local services = makeServices(player)

				DefaultMetrics.setup(handler, config, makeUserConfig(player, config), services)
				player.CharacterAdded:Fire(player.character)
				player.humanoid.Died:Fire()

				local spawned = findServerTag(handler, "CharacterSpawn")
				local died    = findServerTag(handler, "CharacterDeath")
				if enabled then
					expect(spawned).to.be.ok()
					expect(died).to.be.ok()
				else
					expect(spawned).never.to.be.ok()
					expect(died).never.to.be.ok()
				end
			end
		end)

		it("humanoidStateEvents: fires by default, silent when disabled", function()
			for _, enabled in { true, false } do
				local player  = makePlayer()
				local handler = makeHandler()
				local config  = allDisabledConfig()
				if enabled then config.humanoidStateEvents = nil end
				local services = makeServices(player)

				DefaultMetrics.setup(handler, config, makeUserConfig(player, config), services)
				player.CharacterAdded:Fire(player.character)
				player.humanoid.StateChanged:Fire(nil, Enum.HumanoidStateType.Landed)

				local event = findServerTag(handler, "HumanoidStateChange")
				if enabled then expect(event).to.be.ok() else expect(event).never.to.be.ok() end
			end
		end)

		it("paths: fires by default, silent when disabled", function()
			for _, enabled in { true, false } do
				local player  = makePlayer()
				local handler = makeHandler()
				local config  = allDisabledConfig()
				if enabled then config.paths = nil end
				player.Character = { Position = Vector3.new(0, 0, 0) }
				local services = makeServices(player)

				DefaultMetrics.setup(handler, config, makeUserConfig(player, config), services)

				local event = findServerTag(handler, "_PathStart")
				if enabled then expect(event).to.be.ok() else expect(event).never.to.be.ok() end
			end
		end)

		it("proximityEvents: fires by default, silent when disabled", function()
			for _, enabled in { true, false } do
				local player  = makePlayer()
				local handler = makeHandler()
				local config  = allDisabledConfig()
				if enabled then config.proximityEvents = nil end
				local services = makeServices(player)

				DefaultMetrics.setup(handler, config, makeUserConfig(player, config), services)
				services.ProximityPromptService.PromptTriggered:Fire({ ActionText = "Open", ObjectText = "Door" }, player)

				local event = findServerTag(handler, "PromptTriggered")
				if enabled then expect(event).to.be.ok() else expect(event).never.to.be.ok() end
			end
		end)

		it("toolEvents: fires by default, silent when disabled", function()
			for _, enabled in { true, false } do
				local player  = makePlayer()
				local handler = makeHandler()
				local config  = allDisabledConfig()
				if enabled then config.toolEvents = nil end
				local services = makeServices(player)

				DefaultMetrics.setup(handler, config, makeUserConfig(player, config), services)
				local tool = makeTool("Sword")
				player.backpack.ChildAdded:Fire(tool)
				tool.Activated:Fire()

				local event = findServerTag(handler, "ToolActivated")
				if enabled then expect(event).to.be.ok() else expect(event).never.to.be.ok() end
			end
		end)

		it("damageEvents: fires by default, silent when disabled", function()
			for _, enabled in { true, false } do
				local player  = makePlayer()
				local handler = makeHandler()
				local config  = allDisabledConfig()
				if enabled then config.damageEvents = nil end
				local services = makeServices(player)

				DefaultMetrics.setup(handler, config, makeUserConfig(player, config), services)
				player.CharacterAdded:Fire(player.character)
				player.humanoid.HealthChanged:Fire(90) -- delta = 10

				local event = findServerTag(handler, "DamageTaken")
				if enabled then expect(event).to.be.ok() else expect(event).never.to.be.ok() end
			end
		end)

		it("idleDetection: fires by default, silent when disabled", function()
			for _, enabled in { true, false } do
				local player  = makePlayer()
				local handler = makeHandler()
				local config  = allDisabledConfig()
				config.idleThresholdSeconds = 1
				if enabled then config.idleDetection = nil end
				player.Character = { Position = Vector3.new(0, 0, 0) }

				local time = 0
				local services = makeServices(player, { getTime = function() return time end })

				DefaultMetrics.setup(handler, config, makeUserConfig(player, config), services)
				services.RunService.Heartbeat:Fire() -- begin tracking
				time = 2
				services.RunService.Heartbeat:Fire() -- exceeds 1s threshold, idle confirmed
				player.Character.Position = Vector3.new(100, 0, 0)
				time = 3
				services.RunService.Heartbeat:Fire() -- moves, ends idle period

				local event = findServerTag(handler, "PlayerIdle")
				if enabled then expect(event).to.be.ok() else expect(event).never.to.be.ok() end
			end
		end)

		it("marketplaceEvents: fires by default, silent when disabled", function()
			for _, enabled in { true, false } do
				local player  = makePlayer()
				local handler = makeHandler()
				local config  = allDisabledConfig()
				if enabled then config.marketplaceEvents = nil end
				local services = makeServices(player)

				DefaultMetrics.setup(handler, config, makeUserConfig(player, config), services)
				services.MarketplaceService.PromptProductPurchaseFinished:Fire(player.UserId, 42, true)

				local event = findServerTag(handler, "ProductPurchased")
				if enabled then expect(event).to.be.ok() else expect(event).never.to.be.ok() end
			end
		end)

		it("chatEvents: fires by default, silent when disabled", function()
			for _, enabled in { true, false } do
				local player  = makePlayer()
				local handler = makeHandler()
				local config  = allDisabledConfig()
				if enabled then config.chatEvents = nil end
				local services = makeServices(player)

				DefaultMetrics.setup(handler, config, makeUserConfig(player, config), services)
				player.Chatted:Fire()

				local event = findServerTag(handler, "ChatMessage")
				if enabled then expect(event).to.be.ok() else expect(event).never.to.be.ok() end
			end
		end)

		it("teamEvents: fires by default, silent when disabled", function()
			for _, enabled in { true, false } do
				local player  = makePlayer()
				local handler = makeHandler()
				local config  = allDisabledConfig()
				if enabled then config.teamEvents = nil end
				local services = makeServices(player)

				DefaultMetrics.setup(handler, config, makeUserConfig(player, config), services)
				player.Team = { Name = "Red" }
				player.fireTeamChanged()

				local event = findServerTag(handler, "TeamChanged")
				if enabled then expect(event).to.be.ok() else expect(event).never.to.be.ok() end
			end
		end)

		local function jumpEventsScenario(configureJumpEvents)
			local player  = makePlayer()
			local handler = makeHandler()
			local config  = allDisabledConfig()
			configureJumpEvents(config)
			local services = makeServices(player)

			DefaultMetrics.setup(handler, config, makeUserConfig(player, config), services)
			player.CharacterAdded:Fire(player.character)
			player.humanoid.Jumping:Fire(true)

			return findServerTag(handler, "PlayerJump")
		end

		it("jumpEvents: silent when left unset (opt-in, not opt-out)", function()
			local event = jumpEventsScenario(function(config) config.jumpEvents = nil end)
			expect(event).never.to.be.ok()
		end)

		it("jumpEvents: silent when explicitly false", function()
			local event = jumpEventsScenario(function(config) config.jumpEvents = false end)
			expect(event).never.to.be.ok()
		end)

		it("jumpEvents: fires when explicitly true", function()
			local event = jumpEventsScenario(function(config) config.jumpEvents = true end)
			expect(event).to.be.ok()
		end)

	end)

	describe("DefaultMetrics.setup client-tag allowlisting", function()

		it("allows inputMethodChanged by default, blocks when disabled", function()
			for _, enabled in { true, false } do
				local player  = makePlayer()
				local handler = makeHandler()
				local config  = allDisabledConfig()
				if enabled then config.inputMethodChanged = nil end

				DefaultMetrics.setup(handler, config, makeUserConfig(player, config), makeServices(player))

				expect(handler.allowedTags["InputMethodChanged"] == true).to.equal(enabled)
			end
		end)

		it("allows settingsEvents by default, blocks when disabled", function()
			for _, enabled in { true, false } do
				local player  = makePlayer()
				local handler = makeHandler()
				local config  = allDisabledConfig()
				if enabled then config.settingsEvents = nil end

				DefaultMetrics.setup(handler, config, makeUserConfig(player, config), makeServices(player))

				expect(handler.allowedTags["SettingsOpened"] == true).to.equal(enabled)
			end
		end)

	end)

	describe("DefaultMetrics.setupClient group gating", function()

		it("inputMethodChanged: fires by default, silent when disabled", function()
			for _, enabled in { true, false } do
				local player  = makePlayer()
				local handler = makeHandler()
				local config  = allDisabledConfig()
				if enabled then config.inputMethodChanged = nil end
				local services = makeServices(player)

				DefaultMetrics.setupClient(handler, config, services)
				services.UserInputService.LastInputTypeChanged:Fire(Enum.UserInputType.Keyboard)

				local event = findClientTag(handler, "InputMethodChanged")
				if enabled then expect(event).to.be.ok() else expect(event).never.to.be.ok() end
			end
		end)

		it("settingsEvents: fires by default, silent when disabled", function()
			for _, enabled in { true, false } do
				local player  = makePlayer()
				local handler = makeHandler()
				local config  = allDisabledConfig()
				if enabled then config.settingsEvents = nil end
				local services = makeServices(player)

				DefaultMetrics.setupClient(handler, config, services)
				services.GuiService.MenuOpened:Fire()

				local event = findClientTag(handler, "SettingsOpened")
				if enabled then expect(event).to.be.ok() else expect(event).never.to.be.ok() end
			end
		end)

	end)
end
