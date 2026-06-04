return function(handler, _services)
	local Players = (_services and _services.Players) or game:GetService("Players")

	local localPlayer = Players.LocalPlayer
	if not localPlayer then return end

	localPlayer.FriendStatusChanged:Connect(function(otherPlayer, status)
		if status == Enum.FriendStatus.FriendRequestSent then
			local localChar = localPlayer.Character
			local localRoot = localChar and localChar:FindFirstChild("HumanoidRootPart")
			local otherChar = otherPlayer.Character
			local otherRoot = otherChar and otherChar:FindFirstChild("HumanoidRootPart")

			local dist = nil
			if localRoot and otherRoot then
				dist = math.floor((localRoot.Position - otherRoot.Position).Magnitude)
			end

			handler:addClientEvent({
				tag    = "FriendRequestSent",
				custom = {
					distanceStuds   = dist,
					serverOccupancy = #Players:GetPlayers(),
				},
			})
		elseif status == Enum.FriendStatus.FriendRequestReceived then
			handler:addClientEvent({ tag = "FriendRequestReceived" })
		end
	end)
end
