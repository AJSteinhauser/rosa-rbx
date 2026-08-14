local DEFAULT_WARMUP_SECONDS          = 10
local DEFAULT_WARMUP_MAX_SECONDS      = 30
local DEFAULT_BASELINE_WINDOW_SECONDS = 30
local DEFAULT_RECENT_WINDOW_SECONDS   = 3
local DEFAULT_DROP_RATIO              = 0.5

return function(handler, config, _services)
	local RunService      = (_services and _services.RunService)      or game:GetService("RunService")
	local Players         = (_services and _services.Players)         or game:GetService("Players")
	local ContentProvider = (_services and _services.ContentProvider) or game:GetService("ContentProvider")
	local getTime         = (_services and _services.getTime)         or os.clock

	local cfg = config.fpsDrop or {}
	local warmupSeconds    = cfg.warmupSeconds        or DEFAULT_WARMUP_SECONDS
	-- Clamped so a misconfigured ceiling below the floor can't silently disable itself.
	local warmupMaxSeconds = math.max(cfg.warmupMaxSeconds or DEFAULT_WARMUP_MAX_SECONDS, warmupSeconds)
	local baselineWindow   = cfg.baselineWindowSeconds or DEFAULT_BASELINE_WINDOW_SECONDS
	local recentWindow     = cfg.recentWindowSeconds   or DEFAULT_RECENT_WINDOW_SECONDS
	local dropRatio        = cfg.dropRatio             or DEFAULT_DROP_RATIO

	local startTime       = getTime()
	local lastSampleTime  = nil
	local firstSampleTime = nil
	local baselineFps     = nil
	local recentFps       = nil
	local dipping         = false

	-- warmupMaxSeconds forces warmup to end even if the asset queue never drains.
	local function stillWarmingUp(now)
		local elapsed = now - startTime
		if elapsed < warmupSeconds then return true end
		if elapsed >= warmupMaxSeconds then return false end
		return ContentProvider.RequestQueueSize > 0
	end

	local function getRootPosition()
		local player    = Players.LocalPlayer
		local character = player and player.Character
		local root      = character and character:FindFirstChild("HumanoidRootPart")
		return root and root.Position
	end

	RunService.RenderStepped:Connect(function()
		local now = getTime()

		if stillWarmingUp(now) then
			lastSampleTime = nil -- discard stale dt across the warmup boundary
			return
		end

		if not lastSampleTime then
			lastSampleTime = now
			return
		end

		local dt = now - lastSampleTime
		lastSampleTime = now
		if dt <= 0 then return end
		local instantFps = 1 / dt

		if not baselineFps then
			baselineFps     = instantFps
			recentFps       = instantFps
			firstSampleTime = now
			return
		end

		baselineFps = baselineFps + (instantFps - baselineFps) * math.min(dt / baselineWindow, 1)
		recentFps   = recentFps   + (instantFps - recentFps)   * math.min(dt / recentWindow, 1)

		if now - firstSampleTime < recentWindow then return end -- let the EMAs settle before judging

		local isDrop = recentFps <= baselineFps * dropRatio
		if isDrop and not dipping then
			dipping = true
			handler:addClientEvent({
				tag      = "FpsDrop",
				position = getRootPosition(),
				quantity = math.floor(recentFps),
				custom   = {
					baselineFps = math.floor(baselineFps),
					dropPct     = math.floor((1 - recentFps / baselineFps) * 100),
				},
			})
		elseif not isDrop and dipping then
			dipping = false
		end
	end)
end
