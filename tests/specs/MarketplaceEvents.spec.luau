local ReplicatedStorage    = game:GetService("ReplicatedStorage")
local setupMarketplaceEvents = require(ReplicatedStorage.RosaRbx.ingestion["default-metrics"]["marketplace-events"])

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

local function makeServices(players)
	local productFinished  = makeSignal()
	local gamePassFinished = makeSignal()
	local playerMap = {}
	for _, p in players or {} do
		playerMap[p.UserId] = p
	end
	return {
		productFinished  = productFinished,
		gamePassFinished = gamePassFinished,
		MarketplaceService = {
			PromptProductPurchaseFinished  = productFinished,
			PromptGamePassPurchaseFinished = gamePassFinished,
		},
		Players = {
			GetPlayerByUserId = function(_, userId) return playerMap[userId] end,
		},
	}
end

return function()
	describe("MarketplaceEvents", function()

		it("fires ProductPurchased on successful product purchase", function()
			local player  = { Name = "Alice", UserId = 1 }
			local handler = makeHandler()
			local svc     = makeServices({ player })

			setupMarketplaceEvents(handler, svc)
			svc.productFinished:Fire(1, 9001, true)

			expect(#handler.calls).to.equal(1)
			expect(handler.calls[1].event.tag).to.equal("ProductPurchased")
			expect(handler.calls[1].event.custom.productId).to.equal(9001)
			expect(handler.calls[1].player).to.equal(player)
		end)

		it("fires ProductDeclined when purchase is cancelled", function()
			local player  = { Name = "Bob", UserId = 2 }
			local handler = makeHandler()
			local svc     = makeServices({ player })

			setupMarketplaceEvents(handler, svc)
			svc.productFinished:Fire(2, 9001, false)

			expect(handler.calls[1].event.tag).to.equal("ProductDeclined")
		end)

		it("fires GamePassPurchased on successful game pass purchase", function()
			local player  = { Name = "Carol", UserId = 3 }
			local handler = makeHandler()
			local svc     = makeServices({ player })

			setupMarketplaceEvents(handler, svc)
			svc.gamePassFinished:Fire(player, 42, true)

			expect(#handler.calls).to.equal(1)
			expect(handler.calls[1].event.tag).to.equal("GamePassPurchased")
			expect(handler.calls[1].event.custom.gamePassId).to.equal(42)
		end)

		it("fires GamePassDeclined when game pass purchase is cancelled", function()
			local player  = { Name = "Dave", UserId = 4 }
			local handler = makeHandler()
			local svc     = makeServices({ player })

			setupMarketplaceEvents(handler, svc)
			svc.gamePassFinished:Fire(player, 42, false)

			expect(handler.calls[1].event.tag).to.equal("GamePassDeclined")
		end)

		it("does not fire if player cannot be found by userId", function()
			local handler = makeHandler()
			local svc     = makeServices({}) -- no players registered

			setupMarketplaceEvents(handler, svc)
			svc.productFinished:Fire(999, 9001, true)

			expect(#handler.calls).to.equal(0)
		end)

	end)
end
