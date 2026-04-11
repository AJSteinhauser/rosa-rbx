local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService        = game:GetService("RunService")
local UserInputService  = game:GetService("UserInputService")
local EventBuilder      = require(script.Parent["event-builder"])
local TypeEnforcement   = require(script.Parent["type-enforcement"])
local BatchHandler      = require(script.Parent.Parent.egress.components["batch-event-handler"])

-- Central coordinator for event ingestion.
--
-- SERVER: Creates RemoteEvent/BindableEvent infrastructure, validates and batches events.
-- CLIENT: Connects to existing RemoteEvents, responds to platform detection requests.
--
-- Usage (server script):
--   local handler = EventIngestionHandler.new(userConfig)
--   handler:addEvent(player, { tag = "Kill", quantity = 1 })
--
-- Usage (client script):
--   local handler = EventIngestionHandler.new(userConfig)
--   handler:addEvent(player, { tag = "ItemPickup" })  -- fires to server automatically

-- On the client, wire up the platform listener as soon as this module is required.
-- This runs once at module load time so it works even if new() is called late.
if not RunService:IsServer() then
	task.spawn(function()
		local platformModule = script.Parent["player-platform-manager"]
		local platformRemote = platformModule:WaitForChild("PlatformManager") :: RemoteEvent
		platformRemote.OnClientEvent:Connect(function(request)
			if request == "getPlatform" then
				platformRemote:FireServer(UserInputService.Platform)
			end
		end)
	end)
end

local EventIngestionHandler = {}
EventIngestionHandler.__index = EventIngestionHandler

function EventIngestionHandler.new(userConfig)
	local self = setmetatable({}, EventIngestionHandler)
	self.userConfig = userConfig
	self.isServer   = RunService:IsServer()

	if self.isServer then
		-- Create streams before setting up connections so they exist when listeners fire
		self.serverEventStream = Instance.new("BindableEvent")
		self.serverEventStream.Name = "ServerEventStream"

		self.clientEventStream = Instance.new("RemoteEvent")
		self.clientEventStream.Name   = "RosaClientEventStream"
		self.clientEventStream.Parent = ReplicatedStorage

		self.eventBuilder = EventBuilder.new(userConfig)
		self.batchHandler = BatchHandler.new()

		self:setupServerConnections()
	else
		-- Wait for the server to create the client event stream
		self.clientEventStream = ReplicatedStorage:WaitForChild("RosaClientEventStream")
	end

	return self
end

function EventIngestionHandler:setupServerConnections()
	-- Forward validated client events to the ingestion pipeline
	if self.userConfig.clientEvents.enabled then
		self.clientEventStream.OnServerEvent:Connect(function(player, event)
			local whitelist = self.userConfig.clientEvents.whitelistedEventTags
			if whitelist and not table.find(whitelist, event.tag) then
				warn(`{event.tag} is not a whitelisted client event.`)
				return
			end
			self:registerEvent(player, event)
		end)
	end

	-- Forward server-side events from the BindableEvent
	self.serverEventStream.Event:Connect(function(player, event)
		self:registerEvent(player, event)
	end)
end

-- Runs event building and batching in a separate task to avoid blocking the caller.
-- Platform detection may yield, so this must not run on the main thread.
function EventIngestionHandler:registerEvent(player: Player, eventRequest)
	task.spawn(function()
		local fullEvent = self.eventBuilder:buildEvent(player, eventRequest)
		TypeEnforcement.enforce(fullEvent)
		self.batchHandler:addEvent(fullEvent)
	end)
end

-- Queues an event for ingestion. Works from both server and client scripts.
function EventIngestionHandler:addEvent(player: Player, eventRequest)
	if self.isServer then
		self.serverEventStream:Fire(player, eventRequest)
	else
		-- On the client, player arg is provided by Roblox automatically on the server
		self.clientEventStream:FireServer(eventRequest)
	end
end

return EventIngestionHandler
