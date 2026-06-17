local ReplicatedStorage        = game:GetService("ReplicatedStorage")
local setupHumanoidStateEvents = require(ReplicatedStorage.RosaRbx.ingestion["default-metrics"]["humanoid-state-events"])

local function makeSignal()
	local cbs = {}
	return {
		Connect = function(_, fn) table.insert(cbs, fn) end,
		Fire    = function(_, ...) for _, fn in cbs do fn(...) end end,
	}
end

local function makeHandler()
	local calls = {}
	return {
		calls = calls,
		addServerEvent = function(_, player, event)
			table.insert(calls, { player = player, event = event })
		end,
	}
end

local function makeHumanoid()
	local stateChanged = makeSignal()
	return {
		StateChanged  = stateChanged,
		_stateChanged = stateChanged,
	}
end

local function makeCharacter(humanoid, rootPos)
	local root = rootPos and { Position = rootPos } or nil
	return {
		WaitForChild = function(_, name)
			if name == "Humanoid" then return humanoid end
		end,
		FindFirstChild = function(_, name)
			if name == "HumanoidRootPart" then return root end
		end,
	}
end

local function makePlayer()
	local characterAdded = makeSignal()
	return {
		Name            = "TestPlayer",
		Character       = nil,
		CharacterAdded  = characterAdded,
		_characterAdded = characterAdded,
	}
end

local function makeServices(players, getTime)
	local playerAdded = makeSignal()
	return {
		playerAdded = playerAdded,
		getTime     = getTime,
		Players = {
			PlayerAdded  = playerAdded,
			GetPlayers   = function() return players or {} end,
		},
	}
end

return function()
	describe("HumanoidStateEvents", function()

		it("fires HumanoidStateChange for Landed state", function()
			local handler   = makeHandler()
			local humanoid  = makeHumanoid()
			local character = makeCharacter(humanoid)
			local player    = makePlayer()
			local svc       = makeServices()

			setupHumanoidStateEvents(handler, svc)
			svc.playerAdded:Fire(player)
			player._characterAdded:Fire(character)
			humanoid._stateChanged:Fire(Enum.HumanoidStateType.Running, Enum.HumanoidStateType.Landed)

			expect(#handler.calls).to.equal(1)
			expect(handler.calls[1].event.tag).to.equal("HumanoidStateChange")
			expect(handler.calls[1].event.custom.state).to.equal("Landed")
		end)

		it("fires for Freefall state", function()
			local handler   = makeHandler()
			local humanoid  = makeHumanoid()
			local character = makeCharacter(humanoid)
			local player    = makePlayer()
			local svc       = makeServices()

			setupHumanoidStateEvents(handler, svc)
			svc.playerAdded:Fire(player)
			player._characterAdded:Fire(character)
			humanoid._stateChanged:Fire(Enum.HumanoidStateType.Jumping, Enum.HumanoidStateType.Freefall)

			expect(#handler.calls).to.equal(1)
			expect(handler.calls[1].event.custom.state).to.equal("Freefall")
		end)

		it("does not fire for untracked states", function()
			local handler   = makeHandler()
			local humanoid  = makeHumanoid()
			local character = makeCharacter(humanoid)
			local player    = makePlayer()
			local svc       = makeServices()

			setupHumanoidStateEvents(handler, svc)
			svc.playerAdded:Fire(player)
			player._characterAdded:Fire(character)
			humanoid._stateChanged:Fire(Enum.HumanoidStateType.Jumping, Enum.HumanoidStateType.Running)

			expect(#handler.calls).to.equal(0)
		end)

		it("includes position from HumanoidRootPart", function()
			local pos       = Vector3.new(10, 5, 20)
			local handler   = makeHandler()
			local humanoid  = makeHumanoid()
			local character = makeCharacter(humanoid, pos)
			local player    = makePlayer()
			local svc       = makeServices()

			setupHumanoidStateEvents(handler, svc)
			svc.playerAdded:Fire(player)
			player._characterAdded:Fire(character)
			humanoid._stateChanged:Fire(Enum.HumanoidStateType.Running, Enum.HumanoidStateType.Landed)

			expect(handler.calls[1].event.position).to.equal(pos)
		end)

		it("position is nil when HumanoidRootPart absent", function()
			local handler   = makeHandler()
			local humanoid  = makeHumanoid()
			local character = makeCharacter(humanoid, nil)
			local player    = makePlayer()
			local svc       = makeServices()

			setupHumanoidStateEvents(handler, svc)
			svc.playerAdded:Fire(player)
			player._characterAdded:Fire(character)
			humanoid._stateChanged:Fire(Enum.HumanoidStateType.Running, Enum.HumanoidStateType.Landed)

			expect(handler.calls[1].event.position).to.equal(nil)
		end)

		it("attaches to characters for existing players", function()
			local handler   = makeHandler()
			local humanoid  = makeHumanoid()
			local character = makeCharacter(humanoid)
			local player    = makePlayer()
			local svc       = makeServices({ player })

			setupHumanoidStateEvents(handler, svc)
			player._characterAdded:Fire(character)
			humanoid._stateChanged:Fire(Enum.HumanoidStateType.Running, Enum.HumanoidStateType.Landed)

			expect(#handler.calls).to.equal(1)
		end)

	end)

	describe("HumanoidStateEvents debounce", function()

		it("suppresses same state fired again within cooldown window", function()
			local time    = 0
			local handler = makeHandler()
			local humanoid  = makeHumanoid()
			local character = makeCharacter(humanoid)
			local player    = makePlayer()
			local svc       = makeServices({ player }, function() return time end)

			setupHumanoidStateEvents(handler, svc)
			player._characterAdded:Fire(character)

			time = 0
			humanoid._stateChanged:Fire(Enum.HumanoidStateType.Freefall, Enum.HumanoidStateType.Landed)
			time = 0.4 -- within 1s cooldown
			humanoid._stateChanged:Fire(Enum.HumanoidStateType.Freefall, Enum.HumanoidStateType.Landed)

			expect(#handler.calls).to.equal(1)
		end)

		it("allows same state after cooldown expires", function()
			local time    = 0
			local handler = makeHandler()
			local humanoid  = makeHumanoid()
			local character = makeCharacter(humanoid)
			local player    = makePlayer()
			local svc       = makeServices({ player }, function() return time end)

			setupHumanoidStateEvents(handler, svc)
			player._characterAdded:Fire(character)

			time = 0
			humanoid._stateChanged:Fire(Enum.HumanoidStateType.Freefall, Enum.HumanoidStateType.Landed)
			time = 1.1 -- past 1s cooldown
			humanoid._stateChanged:Fire(Enum.HumanoidStateType.Freefall, Enum.HumanoidStateType.Landed)

			expect(#handler.calls).to.equal(2)
		end)

		it("different states have independent cooldowns", function()
			local time    = 0
			local handler = makeHandler()
			local humanoid  = makeHumanoid()
			local character = makeCharacter(humanoid)
			local player    = makePlayer()
			local svc       = makeServices({ player }, function() return time end)

			setupHumanoidStateEvents(handler, svc)
			player._characterAdded:Fire(character)

			time = 0
			humanoid._stateChanged:Fire(Enum.HumanoidStateType.Jumping, Enum.HumanoidStateType.Freefall)
			time = 0.2
			humanoid._stateChanged:Fire(Enum.HumanoidStateType.Freefall, Enum.HumanoidStateType.Landed) -- different state, not suppressed

			expect(#handler.calls).to.equal(2)
			expect(handler.calls[1].event.custom.state).to.equal("Freefall")
			expect(handler.calls[2].event.custom.state).to.equal("Landed")
		end)

		it("cooldown resets per character spawn", function()
			local time    = 0
			local handler = makeHandler()
			local humanoid1 = makeHumanoid()
			local humanoid2 = makeHumanoid()
			local char1     = makeCharacter(humanoid1)
			local char2     = makeCharacter(humanoid2)
			local player    = makePlayer()
			local svc       = makeServices({ player }, function() return time end)

			setupHumanoidStateEvents(handler, svc)

			-- first character: fire Landed, then within cooldown
			player._characterAdded:Fire(char1)
			time = 0
			humanoid1._stateChanged:Fire(Enum.HumanoidStateType.Freefall, Enum.HumanoidStateType.Landed)
			time = 0.3 -- within cooldown on char1

			-- new character spawn: cooldown resets because lastFired is local to watchCharacter
			player._characterAdded:Fire(char2)
			humanoid2._stateChanged:Fire(Enum.HumanoidStateType.Freefall, Enum.HumanoidStateType.Landed)

			expect(#handler.calls).to.equal(2)
		end)

		it("multiple players have independent cooldown state", function()
			local time     = 0
			local handler  = makeHandler()
			local humanoidA = makeHumanoid()
			local humanoidB = makeHumanoid()
			local charA     = makeCharacter(humanoidA)
			local charB     = makeCharacter(humanoidB)
			local playerA   = makePlayer()
			local playerB   = makePlayer()
			local svc       = makeServices({ playerA, playerB }, function() return time end)

			setupHumanoidStateEvents(handler, svc)
			playerA._characterAdded:Fire(charA)
			playerB._characterAdded:Fire(charB)

			time = 0
			humanoidA._stateChanged:Fire(Enum.HumanoidStateType.Freefall, Enum.HumanoidStateType.Landed)
			humanoidB._stateChanged:Fire(Enum.HumanoidStateType.Freefall, Enum.HumanoidStateType.Landed)
			time = 0.5 -- within cooldown
			humanoidA._stateChanged:Fire(Enum.HumanoidStateType.Freefall, Enum.HumanoidStateType.Landed)
			humanoidB._stateChanged:Fire(Enum.HumanoidStateType.Freefall, Enum.HumanoidStateType.Landed)

			-- each player fires once (second fire suppressed), so 2 total
			expect(#handler.calls).to.equal(2)
		end)

	end)
end
