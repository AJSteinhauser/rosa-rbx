local Constants        = require(script.Parent.constants)
local PositionPacking  = require(script.Parent["position-packing"])
local Logger           = require(script.Parent.Parent.utils.logger)

local PositionCollector = {}

-- Alphabetizes before assigning ids so the mapping is deterministic across
-- servers regardless of what order a getAllTeams override hands back.
local function buildTeamIdMap(teamNames: { string }): { [string]: number }
	local sortedNames = table.clone(teamNames)
	table.sort(sortedNames)

	local map = {}
	for i, name in sortedNames do
		local id = i - 1
		if id >= Constants.MAX_TEAM_COUNT then
			Logger.warn(string.format(
				"More than %d teams exist; extra teams collapse into NO_TEAM_ID",
				Constants.MAX_TEAM_COUNT
			))
			break
		end
		map[name] = id
	end
	return map
end

-- bit32 ops error on non-finite input, so NaN/Infinity must be zeroed out here
-- rather than just clamped alongside out-of-range values.
local function sanitizeAxis(value: number, bits: number): number
	if value ~= value or value == math.huge or value == -math.huge then
		return 0
	end
	local limit = 2 ^ (bits - 1)
	return math.clamp(math.round(value), -limit, limit - 1)
end

-- getPosition/getTeamName/getAllTeams all come from userConfig —
-- event-ingestion-handler.luau injects a default for each (HumanoidRootPart,
-- Roblox Team objects) if the game hasn't overridden them, so no separate
-- defaults are invented here.
function PositionCollector.collect(_services): buffer
	local players     = (_services and _services.Players) or game:GetService("Players")
	local getPosition = _services and _services.getPosition
	local getTeamName = _services and _services.getTeamName
	local getAllTeams = _services and _services.getAllTeams

	local teamIdMap = buildTeamIdMap(getAllTeams and getAllTeams() or {})

	local entries = {}
	for _, player in players:GetPlayers() do
		local position = getPosition and getPosition(player)
		if position then
			local teamName = getTeamName and getTeamName(player)
			table.insert(entries, {
				position = position,
				teamId   = (teamName and teamIdMap[teamName]) or Constants.NO_TEAM_ID,
			})
		end
	end

	local buf = buffer.create(#entries * Constants.POSITION_ENTRY_BYTE_SIZE)
	for i, entry in entries do
		local offset = (i - 1) * Constants.POSITION_ENTRY_BYTE_SIZE
		PositionPacking.writeEntry(
			buf, offset,
			sanitizeAxis(entry.position.X, Constants.POSITION_X_BITS),
			sanitizeAxis(entry.position.Y, Constants.POSITION_Y_BITS),
			sanitizeAxis(entry.position.Z, Constants.POSITION_Z_BITS),
			entry.teamId
		)
	end

	return buf
end

return PositionCollector
