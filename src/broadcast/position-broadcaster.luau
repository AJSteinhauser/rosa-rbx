local Constants         = require(script.Parent.constants)
local PositionCollector = require(script.Parent["position-collector"])
local Logger            = require(script.Parent.Parent.utils.logger)
local ApiUtils          = require(script.Parent.Parent.egress.utils["api-utils"])
local Signature         = require(script.Parent.Parent.egress.components.signature)

local PositionBroadcaster = {}
PositionBroadcaster.__index = PositionBroadcaster

function PositionBroadcaster.new(_services)
	local self = setmetatable({}, PositionBroadcaster)
	self._services           = _services
	self.httpService         = (_services and _services.HttpService) or game:GetService("HttpService")
	self.wait                = (_services and _services.wait) or task.wait
	self.now                 = (_services and _services.now) or os.clock
	self.isBroadcasting      = false
	self.consecutiveFailures = 0
	self.cooldownUntil       = nil
	return self
end

function PositionBroadcaster:onSignalReceived()
	self:start()
end

function PositionBroadcaster:start()
	if self.isBroadcasting then return end

	if self.httpService.HttpEnabled == false then
		Logger.warn("PositionBroadcaster: HTTP requests are disabled (Allow HTTP Requests / Studio Access to API Services); not starting broadcast")
		return
	end

	local startedAt = self.now()
	if self.cooldownUntil and startedAt < self.cooldownUntil then
		return
	end

	self.isBroadcasting      = true
	self.consecutiveFailures = 0
	Logger.info("PositionBroadcaster: broadcast started")

	task.spawn(function()
		while self.isBroadcasting do
			if self.now() - startedAt >= Constants.BROADCAST_MAX_DURATION_SECONDS then
				Logger.warn(string.format(
					"PositionBroadcaster: hit the %ds max broadcast duration; stopping and entering a %ds cooldown regardless of server response",
					Constants.BROADCAST_MAX_DURATION_SECONDS, Constants.BROADCAST_COOLDOWN_SECONDS
				))
				self:enterCooldownAndStop()
				break
			end

			-- pcall so a bad sendPositions() can't strand isBroadcasting stuck true.
			local ok, shouldContinue, succeeded = pcall(function()
				return self:sendPositions()
			end)
			if not ok then
				Logger.warn("PositionBroadcaster: sendPositions() errored: " .. tostring(shouldContinue))
				shouldContinue, succeeded = true, false
			end

			self.consecutiveFailures = succeeded and 0 or self.consecutiveFailures + 1
			if self.consecutiveFailures >= Constants.MAX_CONSECUTIVE_SEND_FAILURES then
				Logger.warn("PositionBroadcaster: giving up after too many consecutive send failures")
				self:enterCooldownAndStop()
				break
			end

			if not shouldContinue then
				self:stop()
				break
			end

			self.wait(Constants.BROADCAST_SEND_INTERVAL_SECONDS)
		end
	end)
end

function PositionBroadcaster:enterCooldownAndStop()
	self.cooldownUntil = self.now() + Constants.BROADCAST_COOLDOWN_SECONDS
	self:stop()
end

function PositionBroadcaster:stop()
	if not self.isBroadcasting then return end
	self.isBroadcasting = false
	Logger.info("PositionBroadcaster: broadcast stopped")
end

-- Returns (shouldContinue, requestSucceeded): shouldContinue is false only on an
-- explicit 204; requestSucceeded is false only when the request itself failed.
function PositionBroadcaster:sendPositions(): (boolean, boolean)
	local buf = PositionCollector.collect(self._services)

	local request = {
		Url     = Constants.BROADCAST_POSITIONS_API_ROUTE,
		Method  = "POST",
		Body    = buffer.tostring(buf),
		Headers = Signature.generateHeader(self.httpService),
	}

	local response = ApiUtils.sendRetryHandler(request, nil, { HttpService = self.httpService, wait = self.wait })
	if not response.Success then
		Logger.warn(string.format("PositionBroadcaster: send failed with status %d", response.StatusCode))
		return true, false
	end

	return response.StatusCode ~= Constants.BROADCAST_STOP_STATUS, true
end

return PositionBroadcaster
