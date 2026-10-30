-- Builds v1 telemetry envelopes (contracts/schemas/v1) and refuses payloads that
-- carry raw player identifiers or addresses. Pseudonymization of anything
-- identity-related must happen before Emit; this is a last-line guard, not a
-- substitute for the privacy review (D-08).
SentinelTelemetry = SentinelTelemetry or {}

local Envelope = {}

Envelope.SCHEMA_VERSION = '1'

Envelope.EVENT_TYPES = {
  connection_attempt = true,
  game_session = true,
  economic_mutation = true,
  game_abuse_signal = true,
  network_interval = true,
  security_incident = true,
}

local FORBIDDEN_KEYS = {
  ip = true, ip_address = true, address = true, endpoint = true,
  license = true, license2 = true, steam = true, discord = true, xbl = true,
  live = true, fivem = true, identifier = true, identifiers = true,
  hwid = true, token = true, tokens = true, password = true, secret = true,
}

local FORBIDDEN_VALUE_PREFIXES = {
  'license:', 'license2:', 'steam:', 'discord:', 'xbl:', 'live:', 'fivem:', 'ip:',
}

local function forbiddenKey(key)
  local k = string.lower(tostring(key))
  return FORBIDDEN_KEYS[k] or k:sub(-3) == '_ip' or k:sub(-9) == '_endpoint'
end

local function forbiddenValue(value)
  if type(value) ~= 'string' then
    return false
  end
  local v = string.lower(value)
  for _, prefix in ipairs(FORBIDDEN_VALUE_PREFIXES) do
    if v:sub(1, #prefix) == prefix then
      return true
    end
  end
  return v:match('%d+%.%d+%.%d+%.%d+') ~= nil
end

local function scan(tbl, depth)
  if depth > 4 then
    return 'payload_too_deep'
  end
  for key, value in pairs(tbl) do
    if forbiddenKey(key) or forbiddenValue(value) then
      return 'forbidden_field:' .. tostring(key)
    end
    if type(value) == 'table' then
      local err = scan(value, depth + 1)
      if err then
        return err
      end
    end
  end
  return nil
end

function Envelope.build(eventType, fields, nowIso, eventId)
  if not Envelope.EVENT_TYPES[eventType] then
    return nil, 'unknown_event_type'
  end
  if type(fields) ~= 'table' then
    return nil, 'fields_must_be_table'
  end
  local err = scan(fields, 1)
  if err then
    return nil, err
  end
  local env = {}
  for key, value in pairs(fields) do
    env[key] = value
  end
  env.schema_version = Envelope.SCHEMA_VERSION
  env.event_type = eventType
  env.event_id = eventId
  env.ts = nowIso
  return env
end

-- Maps a free-text FXServer drop reason to a coarse category so the raw
-- reason text (which can contain names or addresses) is never exported.
function Envelope.classifyDrop(reason)
  local r = string.lower(tostring(reason or ''))
  if r:find('timed out', 1, true) or r:find('timeout', 1, true) then
    return 'timeout'
  elseif r:find('crash', 1, true) then
    return 'crash'
  elseif r:find('kick', 1, true) or r:find('banned', 1, true) then
    return 'kicked'
  elseif r:find('exit', 1, true) or r:find('disconnect', 1, true) or r:find('quit', 1, true) then
    return 'quit'
  end
  return 'unknown'
end

SentinelTelemetry.Envelope = Envelope
