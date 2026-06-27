local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService        = game:GetService("RunService")
local UserInputService  = game:GetService("UserInputService")
local EventBuilder      = require(script.Parent["event-builder"])
local TypeEnforcement   = require(script.Parent["type-enforcement"])
local BatchHandler      = require(script.Parent.Parent.egress.components["batch-event-handler"])
local DefaultMetrics    = require(script.Parent["default-metrics"])
local Types             = require(script.Parent.types)

-- Central coordinator for event ingestion.
--
-- SERVER: Creates RemoteEvent/BindableEvent infrastructure, validates and batches events.
-- CLIENT: Connects to existing RemoteEvents, responds to platform detection requests.

-- On the client, wire up the platform listener as soon as this module is required.
-- This runs once at module load time so it works even if new() is called late.
if not RunService:IsServer() then
	task.spawn(function()
		local platformModule = script.Parent["player-platform-manager"]
		local platformRemote = platformModule:WaitForChild("PlatformManager") :: RemoteEvent
		platformRemote.OnClientEvent:Connect(function(request)
			if request == "getPlatform" then
				platformRemote:FireServer(UserInputService.PreferredInput)
			end
		end)
	end)
end

local EventIngestionHandler = {}
EventIngestionHandler.__index = EventIngestionHandler

function EventIngestionHandler.new(userConfig)
	local self = setmetatable({}, EventIngestionHandler)

	if not userConfig.getPosition then
		userConfig.getPosition = function(player: Player): Vector3?
			local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart") :: BasePart
			return root and root.Position or nil
		end
	end

	self.userConfig            = userConfig
	self.customPlayerDataHook  = userConfig.customPlayerDataHook
	self.isServer              = RunService:IsServer()
	self.logStudioEvents       = userConfig.logStudioEvents == true
	self.isStudio              = RunService:IsStudio()

	if self.isServer then
		-- Create streams before setting up connections so they exist when listeners fire
		self.serverEventStream = Instance.new("BindableEvent")
		self.serverEventStream.Name = "ServerEventStream"

		self.clientEventStream = Instance.new("RemoteEvent")
		self.clientEventStream.Name   = "RosaClientEventStream"
		self.clientEventStream.Parent = ReplicatedStorage

		self.eventBuilder       = EventBuilder.new(userConfig)
		self.batchHandler       = BatchHandler.new()
		self.internalClientTags = {}

		self:setupServerConnections()

		if userConfig.defaultMetrics then
			DefaultMetrics.setup(self, userConfig.defaultMetrics, userConfig)
		end
	else
		-- Wait for the server to create the client event stream
		self.clientEventStream = ReplicatedStorage:WaitForChild("RosaClientEventStream")
		if userConfig.defaultMetrics then
			DefaultMetrics.setupClient(self, userConfig.defaultMetrics)
		end
	end

	return self
end

function EventIngestionHandler:setupServerConnections()
	-- Forward validated client events to the ingestion pipeline
	if self.userConfig.clientEvents and self.userConfig.clientEvents.enabled then
		self.clientEventStream.OnServerEvent:Connect(function(player, event)
			local whitelist = self.userConfig.clientEvents.whitelistedEventTags
			if whitelist and not table.find(whitelist, event.tag) and not self.internalClientTags[event.tag] then
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
function EventIngestionHandler:registerEvent(player: Player, eventRequest: Types.EventRequest)
  if not self.isServer then error("Server only function") end
  if self.isStudio and not self.logStudioEvents then return end
	task.spawn(function()
		if self.customPlayerDataHook then
			local hookData = self.customPlayerDataHook(player)
			if hookData and typeof(hookData) == "table" then
				local merged = {}
				for k, v in pairs(hookData) do merged[k] = v end
				if eventRequest.custom then
					for k, v in pairs(eventRequest.custom) do merged[k] = v end
				end
				eventRequest = table.clone(eventRequest)
				eventRequest.custom = merged
			end
		end
		local fullEvent = self.eventBuilder:buildEvent(player, eventRequest)
		if not fullEvent then return end
		TypeEnforcement.enforce(fullEvent)
		self.batchHandler:addEvent(fullEvent)
	end)
end

-- Queues an event for ingestion. Works from both server and client scripts.
function EventIngestionHandler:allowClientTag(tag: string)
	if not self.isServer then error("Server only function") end
	self.internalClientTags[tag] = true
end

function EventIngestionHandler:addServerEvent(player: Player, eventRequest: Types.EventRequest)
  if not self.isServer then error("Server only function") end
  self.serverEventStream:Fire(player, eventRequest)
end

function EventIngestionHandler:addClientEvent(eventRequest: Types.EventRequest)
  if self.isServer then error("Client only function") end
  self.clientEventStream:FireServer(eventRequest)
end

return EventIngestionHandler
