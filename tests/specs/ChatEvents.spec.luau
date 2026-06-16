local ReplicatedStorage = game:GetService("ReplicatedStorage")
local setupChatEvents   = require(ReplicatedStorage.RosaRbxPipeline.ingestion["default-metrics"]["chat-events"])

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

local function makePlayer(name)
	local chatted = makeSignal()
	return {
		Name     = name or "TestPlayer",
		Chatted  = chatted,
		_chatted = chatted,
	}
end

local function makeServices(existing)
	local playerAdded = makeSignal()
	return {
		playerAdded = playerAdded,
		Players = {
			PlayerAdded  = playerAdded,
			GetPlayers   = function() return existing or {} end,
		},
	}
end

return function()
	describe("ChatEvents", function()

		it("fires ChatMessage when player chats", function()
			local handler = makeHandler()
			local player  = makePlayer("Alice")
			local svc     = makeServices()

			setupChatEvents(handler, svc)
			svc.playerAdded:Fire(player)
			player._chatted:Fire("hello")

			expect(#handler.calls).to.equal(1)
			expect(handler.calls[1].event.tag).to.equal("ChatMessage")
			expect(handler.calls[1].player).to.equal(player)
		end)

		it("fires for players already in game at setup time", function()
			local handler = makeHandler()
			local player  = makePlayer("Bob")
			local svc     = makeServices({ player })

			setupChatEvents(handler, svc)
			player._chatted:Fire("hey")

			expect(#handler.calls).to.equal(1)
		end)

		it("fires multiple times for multiple messages", function()
			local handler = makeHandler()
			local player  = makePlayer("Carol")
			local svc     = makeServices({ player })

			setupChatEvents(handler, svc)
			player._chatted:Fire("first")
			player._chatted:Fire("second")

			expect(#handler.calls).to.equal(2)
		end)

	end)
end
