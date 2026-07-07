local ACCUMULATOR_BUCKET_SIZE    = 20
local ACCUMULATOR_LEAK_PER_SECOND = 20

local HTTPS_BODY_LIMIT      = 1024 * 1000 - 1       -- ~1MB
local BODY_OVERSHOOT_TARGET = 1.25 * HTTPS_BODY_LIMIT -- flush trigger

local HEARTBEAT_FLUSH_INTERVAL = 200
local HEARTBEAT_FLUSH_JITTER   = 0.25 -- fraction; flushes fire up to 25% early to de-sync the fleet

-- Inline retries only cover brief transients (a pod restart); sustained failures
-- trip a blocker instead, so this stays small to avoid retry-storm amplification.
local MAX_HTTP_RETRY_ATTEMPTS = 4
local RETRY_BACKOFF_JITTER    = 0.5 -- equal-jitter fraction on the 2^attempt backoff

local QUOTA_BLOCKER_INTERVAL     = 5  * 60      -- 5 minutes; base interval, doubles on repeated failure
local QUOTA_BLOCKER_MAX_INTERVAL = 2  * 60 * 60 -- 2 hours; backoff cap
local AUTH_BLOCKER_INTERVAL      = 30 * 60      -- 30 minutes; base interval, doubles on repeated failure
local AUTH_BLOCKER_MAX_INTERVAL  = 2  * 60 * 60 -- 2 hours; backoff cap

-- 429 Too Many Requests: server explicitly asking us to back off. Honors Retry-After.
local RATE_LIMIT_BLOCKER_INTERVAL     = 30       -- 30 seconds; base, doubles on repeated 429
local RATE_LIMIT_BLOCKER_MAX_INTERVAL = 10 * 60  -- 10 minutes; backoff cap

-- 5xx server errors: back the whole instance off rather than hammering a sick server.
local SERVER_BLOCKER_INTERVAL     = 30       -- 30 seconds; base, doubles on repeated 5xx
local SERVER_BLOCKER_MAX_INTERVAL = 10 * 60  -- 10 minutes; backoff cap

local BLOCKER_JITTER = 0.25 -- fraction; spreads probe times across the fleet

-- Background HID noise (Steam Input virtualizing a controller, wireless dongles that
-- expose a phantom joystick, etc.) can flip LastInputTypeChanged without real player
-- input. Require the new category to hold for this long before treating it as real.
local INPUT_METHOD_DEBOUNCE_SECONDS = 0.5

local SECRETS_KEY_LOOKUP = "ROSA_API_KEY"

local DEV_MODE = false
local INGESTION_BASE_API_ROUTE = "https://api.rosaanalytic.com"
local INGESTION_LOCAL_BASE_API_ROUTE = "http://127.0.0.1:3000"

local BASE_API = DEV_MODE and INGESTION_LOCAL_BASE_API_ROUTE or INGESTION_BASE_API_ROUTE
local EVENTS_API_ROUTE = BASE_API .. "/api/events"

local CUSTOM_FIELD_MAX_ENCODED_SIZE = 500

local SCALING_BUFFER_CHUNK_SIZE = 100_000

return {
	ACCUMULATOR_BUCKET_SIZE          = ACCUMULATOR_BUCKET_SIZE,
	ACCUMULATOR_LEAK_PER_SECOND      = ACCUMULATOR_LEAK_PER_SECOND,
	HTTPS_BODY_LIMIT                 = HTTPS_BODY_LIMIT,
	BODY_OVERSHOOT_TARGET            = BODY_OVERSHOOT_TARGET,
	HEARTBEAT_FLUSH_INTERVAL         = HEARTBEAT_FLUSH_INTERVAL,
	HEARTBEAT_FLUSH_JITTER           = HEARTBEAT_FLUSH_JITTER,
	MAX_HTTP_RETRY_ATTEMPTS          = MAX_HTTP_RETRY_ATTEMPTS,
	RETRY_BACKOFF_JITTER             = RETRY_BACKOFF_JITTER,
	QUOTA_BLOCKER_INTERVAL           = QUOTA_BLOCKER_INTERVAL,
	QUOTA_BLOCKER_MAX_INTERVAL       = QUOTA_BLOCKER_MAX_INTERVAL,
	AUTH_BLOCKER_INTERVAL            = AUTH_BLOCKER_INTERVAL,
	AUTH_BLOCKER_MAX_INTERVAL        = AUTH_BLOCKER_MAX_INTERVAL,
	RATE_LIMIT_BLOCKER_INTERVAL      = RATE_LIMIT_BLOCKER_INTERVAL,
	RATE_LIMIT_BLOCKER_MAX_INTERVAL  = RATE_LIMIT_BLOCKER_MAX_INTERVAL,
	SERVER_BLOCKER_INTERVAL          = SERVER_BLOCKER_INTERVAL,
	SERVER_BLOCKER_MAX_INTERVAL      = SERVER_BLOCKER_MAX_INTERVAL,
	BLOCKER_JITTER                   = BLOCKER_JITTER,
	INPUT_METHOD_DEBOUNCE_SECONDS    = INPUT_METHOD_DEBOUNCE_SECONDS,
	SECRETS_KEY_LOOKUP               = SECRETS_KEY_LOOKUP,
	DEV_MODE                         = DEV_MODE,
	INGESTION_BASE_API_ROUTE         = INGESTION_BASE_API_ROUTE,
	INGESTION_LOCAL_BASE_API_ROUTE   = INGESTION_LOCAL_BASE_API_ROUTE,
	EVENTS_API_ROUTE                 = EVENTS_API_ROUTE,
	CUSTOM_FIELD_MAX_ENCODED_SIZE    = CUSTOM_FIELD_MAX_ENCODED_SIZE,
	SCALING_BUFFER_CHUNK_SIZE        = SCALING_BUFFER_CHUNK_SIZE,
}
