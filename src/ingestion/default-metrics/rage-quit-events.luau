local DEFAULT_THRESHOLD     = 0.5
local DEFAULT_DEATH_WEIGHT  = 0.5
local DEFAULT_DEATH_TAU     = 15
local DEFAULT_DAMAGE_WEIGHT = 0.3
local DEFAULT_DAMAGE_TAU    = 10
local DEFAULT_HEALTH_WEIGHT = 0.2

return function(handler, userConfig, _services)
	local Players = (_services and _services.Players) or game:GetService("Players")
	local getTime = (_services and _services.getTime) or os.clock

	local cfg = (userConfig.defaultMetrics and userConfig.defaultMetrics.rageQuit) or {}
	local threshold    = cfg.threshold    or DEFAULT_THRESHOLD
	local deathWeight  = cfg.deathWeight  or DEFAULT_DEATH_WEIGHT
	local deathTau     = cfg.deathTau     or DEFAULT_DEATH_TAU
	local damageWeight = cfg.damageWeight or DEFAULT_DAMAGE_WEIGHT
	local damageTau    = cfg.damageTau    or DEFAULT_DAMAGE_TAU
	local healthWeight = cfg.healthWeight or DEFAULT_HEALTH_WEIGHT

	local states = {} -- [Player] = { healthPct, lastHealth, lastDeath, lastDamageTime, damageAccum }

	local function watchCharacter(player: Player, character: Model)
		local humanoid = character:WaitForChild("Humanoid") :: Humanoid
		local s = states[player]
		if not s then
			s = { healthPct = 1 }
			states[player] = s
		end
		s.healthPct  = humanoid.Health / humanoid.MaxHealth
		s.lastHealth = humanoid.Health

		humanoid.HealthChanged:Connect(function(newHealth)
			local delta = s.lastHealth - newHealth
			s.lastHealth = newHealth
			s.healthPct  = newHealth / humanoid.MaxHealth
			if delta >= 0.5 then
				local now = getTime()
				local decayed = s.lastDamageTime
					and (s.damageAccum or 0) * math.exp(-(now - s.lastDamageTime) / damageTau)
					or 0
				s.damageAccum    = math.min(decayed + delta / humanoid.MaxHealth, 1)
				s.lastDamageTime = now
			end
		end)

		humanoid.Died:Connect(function()
			s.lastDeath = getTime()
		end)
	end

	local function decay(lastTime, tau, now)
		if not lastTime then return 0 end
		return math.exp(-(now - lastTime) / tau)
	end

	local function watchPlayer(player: Player)
		states[player] = { healthPct = 1 }
		player.CharacterAdded:Connect(function(character)
			watchCharacter(player, character)
		end)
	end

	Players.PlayerAdded:Connect(watchPlayer)

	Players.PlayerRemoving:Connect(function(player)
		local s = states[player]
		states[player] = nil
		if not s then return end

		local now = getTime()
		local deathScore  = deathWeight  * decay(s.lastDeath, deathTau, now)
		local damageScore = damageWeight * decay(s.lastDamageTime, damageTau, now) * (s.damageAccum or 0)
		local healthScore = healthWeight * (1 - s.healthPct)
		local score = deathScore + damageScore + healthScore
		if score < threshold then return end

		handler:addServerEvent(player, {
			tag      = "RageQuit",
			quantity = math.floor(score * 100) / 100,
			custom   = {
				deathAgeSec = s.lastDeath and math.floor(now - s.lastDeath) or nil,
				healthPct   = math.floor(s.healthPct * 100),
			},
		})
	end)

	for _, player in Players:GetPlayers() do
		watchPlayer(player)
		if player.Character then
			task.spawn(watchCharacter, player, player.Character)
		end
	end
end
