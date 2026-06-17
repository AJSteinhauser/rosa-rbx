local ReplicatedStorage    = game:GetService("ReplicatedStorage")
local setupProximityEvents = require(ReplicatedStorage.RosaRbx.ingestion["default-metrics"]["proximity-events"])

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

return function()
	describe("ProximityEvents", function()

		it("fires PromptTriggered with action and object in custom", function()
			local promptTriggered = makeSignal()
			local handler = makeHandler()
			local svc = {
				ProximityPromptService = { PromptTriggered = promptTriggered },
			}
			local player = { Name = "Alice" }
			local prompt = { ActionText = "Open", ObjectText = "Chest" }

			setupProximityEvents(handler, svc)
			promptTriggered:Fire(prompt, player)

			expect(#handler.calls).to.equal(1)
			local call = handler.calls[1]
			expect(call.event.tag).to.equal("PromptTriggered")
			expect(call.event.custom.action).to.equal("Open")
			expect(call.event.custom.object).to.equal("Chest")
			expect(call.player).to.equal(player)
		end)

		it("fires for multiple prompts independently", function()
			local promptTriggered = makeSignal()
			local handler = makeHandler()
			local svc = {
				ProximityPromptService = { PromptTriggered = promptTriggered },
			}
			local p1 = { Name = "Alice" }
			local p2 = { Name = "Bob" }

			setupProximityEvents(handler, svc)
			promptTriggered:Fire({ ActionText = "Buy", ObjectText = "Shop" }, p1)
			promptTriggered:Fire({ ActionText = "Talk", ObjectText = "NPC" }, p2)

			expect(#handler.calls).to.equal(2)
			expect(handler.calls[1].player).to.equal(p1)
			expect(handler.calls[2].player).to.equal(p2)
		end)

	end)
end
