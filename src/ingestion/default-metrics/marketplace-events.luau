return function(handler, _services)
	local MarketplaceService = (_services and _services.MarketplaceService) or game:GetService("MarketplaceService")
	local Players            = (_services and _services.Players)            or game:GetService("Players")

	local robuxPriceById: { [number]: number } = {}

	local function getRobuxPrice(id: number, infoType: Enum.InfoType): number
		if robuxPriceById[id] == nil then
			local ok, info = pcall(function()
				return MarketplaceService:GetProductInfo(id, infoType)
			end)
			robuxPriceById[id] = (ok and info and info.PriceInRobux) or 0
		end
		return robuxPriceById[id]
	end

	MarketplaceService.PromptProductPurchaseFinished:Connect(function(userId, productId, isPurchased)
		local player = Players:GetPlayerByUserId(userId)
		if not player then return end

		if isPurchased then
			handler:addServerEvent(player, {
				tag      = "ProductPurchased",
				quantity = getRobuxPrice(productId, Enum.InfoType.Product),
				custom   = { productId = productId },
			})
		else
			handler:addServerEvent(player, {
				tag    = "ProductDeclined",
				custom = { productId = productId },
			})
		end
	end)

	MarketplaceService.PromptGamePassPurchaseFinished:Connect(function(player, gamePassId, wasPurchased)
		if wasPurchased then
			handler:addServerEvent(player, {
				tag      = "GamePassPurchased",
				quantity = getRobuxPrice(gamePassId, Enum.InfoType.GamePass),
				custom   = { gamePassId = gamePassId },
			})
		else
			handler:addServerEvent(player, {
				tag    = "GamePassDeclined",
				custom = { gamePassId = gamePassId },
			})
		end
	end)
end
