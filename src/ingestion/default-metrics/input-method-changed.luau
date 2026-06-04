local function getCategory(inputType)
	if not inputType then return nil end
	local name = inputType.Name
	if name == "Touch" then
		return "Touch"
	elseif name:sub(1, 7) == "Gamepad" then
		return "Gamepad"
	elseif name == "Keyboard" or name:sub(1, 5) == "Mouse" then
		return "KeyboardAndMouse"
	end
	return nil
end

return function(handler, _services)
	local UserInputService = (_services and _services.UserInputService) or game:GetService("UserInputService")
	local Players          = (_services and _services.Players)          or game:GetService("Players")

	local lastCategory = nil

	UserInputService.LastInputTypeChanged:Connect(function(inputType)
		local category = getCategory(inputType)
		if not category or category == lastCategory then return end

		local player    = Players.LocalPlayer
		local character = player and player.Character
		local root      = character and character:FindFirstChild("HumanoidRootPart")

		handler:addClientEvent({
			tag      = "InputMethodChanged",
			position = root and root.Position or nil,
			custom   = { fromInput = lastCategory, toInput = category },
		})
		lastCategory = category
	end)
end
