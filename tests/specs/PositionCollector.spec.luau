local ReplicatedStorage = game:GetService("ReplicatedStorage")
local PositionCollector = require(ReplicatedStorage.RosaRbx.broadcast["position-collector"])
local PositionPacking   = require(ReplicatedStorage.RosaRbx.broadcast["position-packing"])
local Constants         = require(ReplicatedStorage.RosaRbx.broadcast.constants)

local function makePlayer(x: number?, y: number?, z: number?, team: any?)
	local position = x and Vector3.new(x, y, z) or nil
	return { Position = position, Team = team }
end

local function makeTeam(name: string)
	return { Name = name }
end

-- Mirrors the defaults event-ingestion-handler.luau injects onto userConfig in
-- production (HumanoidRootPart position, Roblox Team objects). Tests override
-- any of these to exercise different behavior.
local function makeServices(players, teams)
	return {
		Players     = { GetPlayers = function() return players end },
		getPosition = function(player) return player.Position end,
		getTeamName = function(player) return player.Team and player.Team.Name or nil end,
		getAllTeams = function()
			local names = {}
			for _, team in teams do
				table.insert(names, team.Name)
			end
			return names
		end,
	}
end

-- Unpacks every 8-byte entry in buf into { x, y, z, team } tables, in order.
local function unpackAll(buf: buffer)
	local count = buffer.len(buf) / Constants.POSITION_ENTRY_BYTE_SIZE
	local results = {}
	for i = 0, count - 1 do
		local offset = i * Constants.POSITION_ENTRY_BYTE_SIZE
		local low  = buffer.readu32(buf, offset)
		local high = buffer.readu32(buf, offset + 4)
		local x, y, z, team = PositionPacking.unpack(low, high)
		table.insert(results, { x = x, y = y, z = z, team = team })
	end
	return results
end

return function()
	describe("PositionCollector", function()

		describe("collect()", function()
			it("returns an empty buffer when there are no players", function()
				local buf = PositionCollector.collect(makeServices({}, {}))
				expect(buffer.len(buf)).to.equal(0)
			end)

			it("packs one entry per player with a rounded position", function()
				local players = { makePlayer(1.4, 2.6, -3.5) }
				local buf = PositionCollector.collect(makeServices(players, {}))
				local entries = unpackAll(buf)

				expect(#entries).to.equal(1)
				expect(entries[1].x).to.equal(1)
				expect(entries[1].y).to.equal(3)
				expect(entries[1].z).to.equal(-4) -- math.round rounds halves away from zero, not toward +inf
			end)

			it("skips players getPosition returns nil for", function()
				local players = { makePlayer(0, 0, 0), makePlayer(nil) }
				local buf = PositionCollector.collect(makeServices(players, {}))
				expect(#unpackAll(buf)).to.equal(1)
			end)

			it("delegates to _services.getPosition rather than reading the player directly", function()
				local players = { { Position = Vector3.new(0, 0, 0) } }
				local services = makeServices(players, {})
				services.getPosition = function() return Vector3.new(9, 8, 7) end

				local buf = PositionCollector.collect(services)
				local entry = unpackAll(buf)[1]

				expect(entry.x).to.equal(9)
				expect(entry.y).to.equal(8)
				expect(entry.z).to.equal(7)
			end)

			it("gives every player NO_TEAM_ID when _services.getTeamName isn't provided, even if Team is set", function()
				-- No built-in fallback to player.Team.Name — matches event-builder.luau,
				-- where teamId is nil unless the game configures getTeamName.
				local players = { makePlayer(0, 0, 0, makeTeam("Red")) }
				local services = makeServices(players, { makeTeam("Red") })
				services.getTeamName = nil

				local buf = PositionCollector.collect(services)
				expect(unpackAll(buf)[1].team).to.equal(Constants.NO_TEAM_ID)
			end)

			describe("team ids", function()
				it("assigns ids alphabetically by team name, independent of GetTeams() order", function()
					local teamZ, teamA, teamM = makeTeam("Zebras"), makeTeam("Aardvarks"), makeTeam("Mules")
					local players = {
						makePlayer(0, 0, 0, teamZ),
						makePlayer(0, 0, 0, teamA),
						makePlayer(0, 0, 0, teamM),
					}
					-- Deliberately out of alphabetical order.
					local buf = PositionCollector.collect(makeServices(players, { teamZ, teamA, teamM }))
					local entries = unpackAll(buf)

					expect(entries[1].team).to.equal(2) -- Zebras: 3rd alphabetically
					expect(entries[2].team).to.equal(0) -- Aardvarks: 1st alphabetically
					expect(entries[3].team).to.equal(1) -- Mules: 2nd alphabetically
				end)

				it("gives unassigned players NO_TEAM_ID", function()
					local players = { makePlayer(0, 0, 0, nil) }
					local buf = PositionCollector.collect(makeServices(players, { makeTeam("Solo") }))
					expect(unpackAll(buf)[1].team).to.equal(Constants.NO_TEAM_ID)
				end)

				it("collapses teams beyond MAX_TEAM_COUNT into NO_TEAM_ID instead of aliasing", function()
					local teams = {}
					for i = 1, Constants.MAX_TEAM_COUNT + 1 do
						-- Zero-padded names so alphabetical order matches creation order.
						table.insert(teams, makeTeam(string.format("Team%02d", i)))
					end
					local overflowTeam = teams[#teams]
					local players = { makePlayer(0, 0, 0, overflowTeam) }

					local buf = PositionCollector.collect(makeServices(players, teams))

					expect(unpackAll(buf)[1].team).to.equal(Constants.NO_TEAM_ID)
				end)

				it("assigns a real id to exactly MAX_TEAM_COUNT teams — the boundary is not off-by-one", function()
					local teams = {}
					for i = 1, Constants.MAX_TEAM_COUNT do
						table.insert(teams, makeTeam(string.format("Team%02d", i)))
					end
					local lastTeam = teams[#teams] -- alphabetically last of exactly MAX_TEAM_COUNT teams
					local players = { makePlayer(0, 0, 0, lastTeam) }

					local buf = PositionCollector.collect(makeServices(players, teams))

					-- Must get a real id (MAX_TEAM_COUNT - 1), not fall through to NO_TEAM_ID.
					expect(unpackAll(buf)[1].team).to.equal(Constants.MAX_TEAM_COUNT - 1)
				end)

				it("does not crash when two teams share the same name, and still assigns a valid id to each", function()
					local teamA, teamB = makeTeam("Red"), makeTeam("Red")
					local players = { makePlayer(0, 0, 0, teamA), makePlayer(0, 0, 0, teamB) }

					local buf
					expect(function()
						buf = PositionCollector.collect(makeServices(players, { teamA, teamB }))
					end).never.to.throw()

					local entries = unpackAll(buf)
					expect(entries[1].team >= 0 and entries[1].team < Constants.MAX_TEAM_COUNT).to.equal(true)
					expect(entries[2].team >= 0 and entries[2].team < Constants.MAX_TEAM_COUNT).to.equal(true)
				end)

				it("falls back to NO_TEAM_ID for a player whose Team isn't in GetTeams() (e.g. a team destroyed mid-transition)", function()
					local orphanTeam = makeTeam("Ghost")
					local players = { makePlayer(0, 0, 0, orphanTeam) }
					-- orphanTeam is deliberately NOT included in the teams list.
					local buf = PositionCollector.collect(makeServices(players, { makeTeam("Other") }))

					expect(unpackAll(buf)[1].team).to.equal(Constants.NO_TEAM_ID)
				end)

				it("uses _services.getAllTeams instead of GetTeams() when overridden", function()
					local players = { makePlayer(0, 0, 0, makeTeam("Solo")) }

					local services = makeServices(players, {}) -- GetTeams() would return nothing
					services.getAllTeams = function() return { "Other", "Solo" } end

					local buf = PositionCollector.collect(services)
					expect(unpackAll(buf)[1].team).to.equal(1) -- Solo: 2nd alphabetically
				end)

				it("alphabetizes a getAllTeams override's return value regardless of the order given", function()
					local teamA, teamB = makeTeam("Aardvarks"), makeTeam("Bravos")
					local players = { makePlayer(0, 0, 0, teamA), makePlayer(0, 0, 0, teamB) }

					local services = makeServices(players, {})
					-- Deliberately returned out of alphabetical order — the override only
					-- needs to return names, the module handles consistent ordering.
					services.getAllTeams = function() return { "Bravos", "Aardvarks" } end

					local buf = PositionCollector.collect(services)
					local entries = unpackAll(buf)

					expect(entries[1].team).to.equal(0) -- Aardvarks: 1st alphabetically
					expect(entries[2].team).to.equal(1) -- Bravos: 2nd alphabetically
				end)

				it("uses _services.getTeamName instead of player.Team when overridden", function()
					-- Player has no Team object at all — getTeamName is the only source of truth.
					local players = { makePlayer(0, 0, 0, nil) }

					local services = makeServices(players, { makeTeam("Aardvarks"), makeTeam("Bravos") })
					services.getTeamName = function() return "Bravos" end

					local buf = PositionCollector.collect(services)
					expect(unpackAll(buf)[1].team).to.equal(1) -- Bravos: 2nd alphabetically
				end)
			end)

			describe("at scale", function()
				it("packs many players into correctly ordered, non-overlapping entries", function()
					local players = {}
					for i = 1, 50 do
						table.insert(players, makePlayer(i, i * 2, -i, nil))
					end

					local buf = PositionCollector.collect(makeServices(players, {}))
					local entries = unpackAll(buf)

					expect(#entries).to.equal(50)
					for i, entry in entries do
						expect(entry.x).to.equal(i)
						expect(entry.y).to.equal(i * 2)
						expect(entry.z).to.equal(-i)
					end
				end)
			end)

			describe("non-finite / out-of-range positions", function()
				it("maps NaN coordinates to 0 instead of erroring", function()
					local nan = 0 / 0
					local players = { makePlayer(nan, nan, nan) }

					local buf
					expect(function()
						buf = PositionCollector.collect(makeServices(players, {}))
					end).never.to.throw()

					local entry = unpackAll(buf)[1]
					expect(entry.x).to.equal(0)
					expect(entry.y).to.equal(0)
					expect(entry.z).to.equal(0)
				end)

				it("maps +/-infinity to 0 instead of erroring", function()
					local players = { makePlayer(math.huge, -math.huge, math.huge) }

					local buf
					expect(function()
						buf = PositionCollector.collect(makeServices(players, {}))
					end).never.to.throw()

					local entry = unpackAll(buf)[1]
					expect(entry.x).to.equal(0)
					expect(entry.y).to.equal(0)
					expect(entry.z).to.equal(0)
				end)

				it("clamps out-of-range coordinates to the field's signed extreme instead of aliasing", function()
					local players = { makePlayer(50000000, 0, -50000000) }

					local buf
					expect(function()
						buf = PositionCollector.collect(makeServices(players, {}))
					end).never.to.throw()

					local entry = unpackAll(buf)[1]
					expect(entry.x).to.equal(2 ^ 21 - 1)
					expect(entry.z).to.equal(-(2 ^ 21))
				end)

				it("clamps an out-of-range y coordinate to the 15-bit extreme", function()
					local players = { makePlayer(0, 999999, 0) }
					local buf = PositionCollector.collect(makeServices(players, {}))
					expect(unpackAll(buf)[1].y).to.equal(2 ^ 14 - 1)
				end)
			end)
		end)

	end)
end
