return function(handler, _services)
	local GuiService = (_services and _services.GuiService) or game:GetService("GuiService")

	GuiService.MenuOpened:Connect(function()
		handler:addClientEvent({ tag = "SettingsOpened" })
	end)
end
