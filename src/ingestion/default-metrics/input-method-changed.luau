local Constants = require(script.Parent.Parent.Parent.models.constants)

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
	local delay            = (_services and _services.delay)            or task.delay

	local lastCategory = nil
	local changeToken  = 0

	-- Filters out categories the device can't plausibly produce for real: a Touch
	-- report with no touch digitizer, or a Gamepad report with nothing connected.
	local function isPlausible(category)
		if category == "Touch" then
			return UserInputService.TouchEnabled
		elseif category == "Gamepad" then
			return #UserInputService:GetConnectedGamepads() > 0
		end
		return true -- KeyboardAndMouse has no reliable "connected" signal to check
	end

	UserInputService.LastInputTypeChanged:Connect(function(inputType)
		-- Any input activity invalidates a not-yet-settled pending change, including
		-- one that flips right back to lastCategory before the debounce window closes.
		changeToken += 1
		local token = changeToken
		local category = getCategory(inputType)

		delay(Constants.INPUT_METHOD_DEBOUNCE_SECONDS, function()
			if token ~= changeToken then return end -- superseded by a later change
			if not category or category == lastCategory or not isPlausible(category) then return end

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
	end)
end
