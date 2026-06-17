local ReplicatedStorage = game:GetService("ReplicatedStorage")
local setupToolEvents   = require(ReplicatedStorage.RosaRbx.ingestion["default-metrics"]["tool-events"])

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

local function makeTool(name)
	return {
		Name       = name,
		IsA        = function(_, class) return class == "Tool" end,
		Equipped   = makeSignal(),
		Activated  = makeSignal(),
		Destroying = makeSignal(),
	}
end

local function makeCharacter(tools)
	local childAdded = makeSignal()
	return {
		_childAdded = childAdded,
		GetChildren = function() return tools or {} end,
		ChildAdded  = childAdded,
	}
end

local function makeBackpack()
	return {
		GetChildren = function() return {} end,
		ChildAdded  = makeSignal(),
	}
end

local function makePlayer(character)
	local characterAdded = makeSignal()
	local backpack = makeBackpack()
	return {
		Name            = "TestPlayer",
		Character       = character or nil,
		CharacterAdded  = characterAdded,
		_characterAdded = characterAdded,
		WaitForChild    = function(_, name)
			if name == "Backpack" then return backpack end
		end,
	}
end

local function makeServices(players)
	local playerAdded = makeSignal()
	return {
		playerAdded = playerAdded,
		Players = {
			PlayerAdded  = playerAdded,
			GetPlayers   = function() return players or {} end,
		},
	}
end

return function()
	describe("ToolEvents", function()

		it("fires ToolEquipped when tool in character is equipped", function()
			local tool      = makeTool("Sword")
			local character = makeCharacter({ tool })
			local player    = makePlayer(character)
			local handler   = makeHandler()
			local svc       = makeServices({ player })

			setupToolEvents(handler, svc)
			tool.Equipped:Fire()

			expect(#handler.calls).to.equal(1)
			expect(handler.calls[1].event.tag).to.equal("ToolEquipped")
			expect(handler.calls[1].event.custom.toolName).to.equal("Sword")
		end)

		it("fires ToolActivated when tool is activated", function()
			local tool      = makeTool("Gun")
			local character = makeCharacter({ tool })
			local player    = makePlayer(character)
			local handler   = makeHandler()
			local svc       = makeServices({ player })

			setupToolEvents(handler, svc)
			tool.Activated:Fire()

			expect(#handler.calls).to.equal(1)
			expect(handler.calls[1].event.tag).to.equal("ToolActivated")
			expect(handler.calls[1].event.custom.toolName).to.equal("Gun")
		end)

		it("does not double-connect the same tool", function()
			local tool      = makeTool("Sword")
			local character = makeCharacter({ tool })
			local player    = makePlayer(character)
			local handler   = makeHandler()
			local svc       = makeServices({ player })

			setupToolEvents(handler, svc)
			-- Simulate tool re-entering character (e.g. re-equip after unequip)
			character._childAdded:Fire(tool)
			tool.Equipped:Fire()

			expect(#handler.calls).to.equal(1) -- only one connection despite two scans
		end)

		it("connects tools added to character after setup", function()
			local character = makeCharacter({})
			local player    = makePlayer(character)
			local handler   = makeHandler()
			local svc       = makeServices({ player })

			setupToolEvents(handler, svc)
			local newTool = makeTool("Axe")
			newTool.IsA = function(_, class) return class == "Tool" end
			character._childAdded:Fire(newTool)
			newTool.Activated:Fire()

			expect(#handler.calls).to.equal(1)
			expect(handler.calls[1].event.custom.toolName).to.equal("Axe")
		end)

		it("connects tools via CharacterAdded", function()
			local tool      = makeTool("Staff")
			local character = makeCharacter({ tool })
			local player    = makePlayer(nil)
			local handler   = makeHandler()
			local svc       = makeServices()

			setupToolEvents(handler, svc)
			svc.playerAdded:Fire(player)
			player._characterAdded:Fire(character)
			tool.Equipped:Fire()

			expect(#handler.calls).to.equal(1)
			expect(handler.calls[1].event.tag).to.equal("ToolEquipped")
		end)

	end)
end
