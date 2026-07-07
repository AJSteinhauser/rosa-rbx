local MessagingService = game:GetService("MessagingService")
local Constants         = require(script.Parent.constants)
local Logger            = require(script.Parent.Parent.utils.logger)
local backoffSeconds    = require(script.Parent.backoff)

local BroadcastSignal = {}
BroadcastSignal.__index = BroadcastSignal

function BroadcastSignal.new(_services)
	local self = setmetatable({}, BroadcastSignal)
	self.messagingService = (_services and _services.MessagingService) or MessagingService
	self.wait              = (_services and _services.wait) or task.wait
	return self
end

function BroadcastSignal:publishStart()
	local ok, err = pcall(function()
		self.messagingService:PublishAsync(Constants.MESSAGING_TOPIC_START, true)
	end)
	if not ok then
		Logger.warn("BroadcastSignal: PublishAsync failed: " .. tostring(err))
	end
end

function BroadcastSignal:onStart(callback: () -> ())
	task.spawn(function()
		local attempt = 0
		while true do
			local ok, err = pcall(function()
				self.messagingService:SubscribeAsync(Constants.MESSAGING_TOPIC_START, function()
					local callOk, callErr = pcall(callback)
					if not callOk then
						Logger.warn("BroadcastSignal: onStart callback errored: " .. tostring(callErr))
					end
				end)
			end)
			if ok then
				return
			end
			Logger.warn("BroadcastSignal: SubscribeAsync failed, retrying: " .. tostring(err))
			self.wait(backoffSeconds(attempt))
			attempt += 1
		end
	end)
end

return BroadcastSignal
