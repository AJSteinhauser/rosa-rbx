local ModelsConstants = require(script.Parent.Parent.models.constants)

local BASE_API = ModelsConstants.DEV_MODE
	and ModelsConstants.INGESTION_LOCAL_BASE_API_ROUTE
	or ModelsConstants.INGESTION_BASE_API_ROUTE

local LEADER_HASHMAP_NAME          = "RosaBroadcastCoordination"
local LEADER_KEY                   = "leader"
local LEADER_LEASE_TTL_SECONDS     = 35
local LEADER_POLL_INTERVAL_SECONDS = 10

local BROADCAST_SEND_INTERVAL_SECONDS = 10

-- Backstop only, not the primary cutoff — the ingestion server's viewer state
-- already expires in 30s.
local BROADCAST_MAX_DURATION_SECONDS = 2 * 60 * 60
local BROADCAST_COOLDOWN_SECONDS     = 5 * 60
local MAX_CONSECUTIVE_SEND_FAILURES  = 10

local MESSAGING_TOPIC_START = "RosaBroadcastStart"

local RETRY_MAX_BACKOFF_SECONDS = 5

local BROADCAST_POLL_API_ROUTE      = BASE_API .. "/api/status"
local BROADCAST_POSITIONS_API_ROUTE = BASE_API .. "/api/live-positions"

local BROADCAST_CONTINUE_STATUS     = 200
local BROADCAST_STOP_STATUS         = 204
local BROADCAST_NOT_ENTITLED_STATUS = 402
local BROADCAST_NOT_ENTITLED_POLL_INTERVAL_SECONDS = 30 * 60
local BROADCAST_NOT_ENTITLED_LEASE_TTL_SECONDS     = 35 * 60

-- Wire format: one 8-byte little-endian entry per player, no header, no player
-- identity — the ingestion server only aggregates positions, so entries are
-- anonymous. Bit layout within the 64-bit value, low bit to high bit:
--   x    : 22 bits, signed, raw studs rounded to the nearest integer
--   z    : 22 bits, signed, raw studs rounded to the nearest integer
--   y    : 15 bits, signed, raw studs rounded to the nearest integer
--   team : 5 bits,  unsigned, index into the team name list from
--          position-collector.luau's getAllTeams (alphabetized before
--          assigning ids). Supports up to 31 teams (0-30); NO_TEAM_ID (31) is
--          reserved for players with no team assigned.
local POSITION_X_BITS    = 22
local POSITION_Z_BITS    = 22
local POSITION_Y_BITS    = 15
local POSITION_TEAM_BITS = 5
local POSITION_ENTRY_BYTE_SIZE = 8

local NO_TEAM_ID    = 31
local MAX_TEAM_COUNT = NO_TEAM_ID

return {
	LEADER_HASHMAP_NAME           = LEADER_HASHMAP_NAME,
	LEADER_KEY                    = LEADER_KEY,
	LEADER_LEASE_TTL_SECONDS      = LEADER_LEASE_TTL_SECONDS,
	LEADER_POLL_INTERVAL_SECONDS  = LEADER_POLL_INTERVAL_SECONDS,
	BROADCAST_SEND_INTERVAL_SECONDS = BROADCAST_SEND_INTERVAL_SECONDS,
	BROADCAST_MAX_DURATION_SECONDS = BROADCAST_MAX_DURATION_SECONDS,
	BROADCAST_COOLDOWN_SECONDS     = BROADCAST_COOLDOWN_SECONDS,
	MAX_CONSECUTIVE_SEND_FAILURES  = MAX_CONSECUTIVE_SEND_FAILURES,
	MESSAGING_TOPIC_START         = MESSAGING_TOPIC_START,
	RETRY_MAX_BACKOFF_SECONDS     = RETRY_MAX_BACKOFF_SECONDS,
	BROADCAST_POLL_API_ROUTE      = BROADCAST_POLL_API_ROUTE,
	BROADCAST_POSITIONS_API_ROUTE = BROADCAST_POSITIONS_API_ROUTE,
	BROADCAST_CONTINUE_STATUS     = BROADCAST_CONTINUE_STATUS,
	BROADCAST_STOP_STATUS         = BROADCAST_STOP_STATUS,
	BROADCAST_NOT_ENTITLED_STATUS = BROADCAST_NOT_ENTITLED_STATUS,
	BROADCAST_NOT_ENTITLED_POLL_INTERVAL_SECONDS = BROADCAST_NOT_ENTITLED_POLL_INTERVAL_SECONDS,
	BROADCAST_NOT_ENTITLED_LEASE_TTL_SECONDS     = BROADCAST_NOT_ENTITLED_LEASE_TTL_SECONDS,
	POSITION_X_BITS               = POSITION_X_BITS,
	POSITION_Z_BITS               = POSITION_Z_BITS,
	POSITION_Y_BITS               = POSITION_Y_BITS,
	POSITION_TEAM_BITS            = POSITION_TEAM_BITS,
	POSITION_ENTRY_BYTE_SIZE      = POSITION_ENTRY_BYTE_SIZE,
	NO_TEAM_ID                    = NO_TEAM_ID,
	MAX_TEAM_COUNT                = MAX_TEAM_COUNT,
}
