local PROMPT_COOLDOWN = 2 -- seconds; suppresses shown-hidden-shown spam per prompt

local INPUT_TYPE_NAMES = {
	[Enum.ProximityPromptInputType.Keyboard] = "KeyboardAndMouse",
	[Enum.ProximityPromptInputType.Gamepad]  = "Gamepad",
	[Enum.ProximityPromptInputType.Touch]    = "Touch",
}

local function getPartPosition(instance)
	if not instance then return nil end
	if instance:IsA("BasePart") then
		return instance.Position
	elseif instance:IsA("Model") and instance.PrimaryPart then
		return instance.PrimaryPart.Position
	end
	return nil
end

return function(handler, _services)
	local ProximityPromptService = (_services and _services.ProximityPromptService) or game:GetService("ProximityPromptService")
	local Players                = (_services and _services.Players)                or game:GetService("Players")
	local getTime                = (_services and _services.getTime)                or os.clock

	local lastShown = {} -- [prompt] = timestamp; client has one player so this is implicitly per-player

	ProximityPromptService.PromptShown:Connect(function(prompt, inputType)
		local now = getTime()
		if lastShown[prompt] and (now - lastShown[prompt]) < PROMPT_COOLDOWN then return end
		lastShown[prompt] = now

		local player    = Players.LocalPlayer
		local character = player and player.Character
		local root      = character and character:FindFirstChild("HumanoidRootPart")
		local pos       = root and root.Position

		local promptPos = getPartPosition(prompt.Parent)
		local dist      = pos and promptPos and math.floor((pos - promptPos).Magnitude) or nil

		handler:addClientEvent({
			tag      = "ProximityPromptShown",
			position = pos,
			custom   = {
				promptName       = prompt.ObjectText ~= "" and prompt.ObjectText or prompt.ActionText,
				distanceToPrompt = dist,
				inputType        = INPUT_TYPE_NAMES[inputType] or tostring(inputType),
			},
		})
	end)
end
