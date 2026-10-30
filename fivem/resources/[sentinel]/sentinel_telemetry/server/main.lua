-- sentinel_telemetry server (SEC-001/002/014). Emit() only enqueues; a
-- background thread ships batches asynchronously. No game code ever waits on
-- Sentinel, and Sentinel being down never kicks or blocks players.
local Queue = SentinelTelemetry.Queue
local Envelope = SentinelTelemetry.Envelope

local cfg = {
  capacity = GetConvarInt('sentinel_queue_capacity', 5000),
  batchSize = GetConvarInt('sentinel_batch_size', 200),
  flushMs = GetConvarInt('sentinel_flush_ms', 2000),
  intervalS = GetConvarInt('sentinel_interval_s', 60),
  -- Empty URL = observe mode: count locally, send nothing.
  url = GetConvar('sentinel_ingest_url', ''),
  -- Secret: set only in the untracked secrets.cfg.
  token = GetConvar('sentinel_ingest_token', ''),
}

local queue = Queue.new(cfg.capacity)
local counters = { rejected = 0, sent = 0, sendFailures = 0, droppedAfterSend = 0, observed = 0 }
local seq = 0
local inflight = false
local sessions = {}

local function nowIso()
  return os.date('!%Y-%m-%dT%H:%M:%SZ')
end

local function nextId(prefix)
  seq = seq + 1
  return ('%s-%x-%x'):format(prefix, os.time(), seq)
end

local function Emit(eventType, fields)
  local env, err = Envelope.build(eventType, fields, nowIso(), nextId('evt'))
  if not env then
    counters.rejected = counters.rejected + 1
    return false, err
  end
  return queue:push(env)
end

local function GetStats()
  local stats = queue:stats()
  for key, value in pairs(counters) do
    stats[key] = value
  end
  stats.mode = cfg.url == '' and 'observe' or 'ship'
  return stats
end

exports('Emit', Emit)
exports('GetStats', GetStats)

local function flush()
  if inflight then
    return
  end
  local batch = queue:drain(cfg.batchSize)
  if #batch == 0 then
    return
  end
  if cfg.url == '' then
    counters.observed = counters.observed + #batch
    return
  end
  inflight = true
  -- Failed batches are dropped and counted, never retried unboundedly.
  PerformHttpRequest(cfg.url, function(status)
    inflight = false
    if status >= 200 and status < 300 then
      counters.sent = counters.sent + #batch
    else
      counters.sendFailures = counters.sendFailures + 1
      counters.droppedAfterSend = counters.droppedAfterSend + #batch
    end
  end, 'POST', json.encode({ events = batch }), {
    ['Content-Type'] = 'application/json',
    ['Authorization'] = 'Bearer ' .. cfg.token,
  })
end

CreateThread(function()
  while true do
    Wait(cfg.flushMs)
    flush()
  end
end)

CreateThread(function()
  while true do
    Wait(cfg.intervalS * 1000)
    local stats = GetStats()
    Emit('network_interval', {
      source = 'fxserver',
      interval_s = cfg.intervalS,
      metrics = {
        players = GetNumPlayerIndices(),
        telemetry_dropped = stats.dropped + stats.droppedAfterSend,
        telemetry_queued = stats.queued,
      },
    })
    if stats.mode == 'observe' then
      print(('[sentinel_telemetry] observe mode: observed=%d dropped=%d rejected=%d queued=%d')
        :format(stats.observed, stats.dropped, stats.rejected, stats.queued))
    end
  end
end)

-- Session lifecycle. session_ref is a random server-side handle; no
-- license/IP/name leaves this resource.
AddEventHandler('playerJoining', function()
  local src = source
  sessions[src] = { ref = nextId('sess'), joinedAt = os.time() }
  Emit('game_session', { session_ref = sessions[src].ref, phase = 'joined' })
end)

AddEventHandler('playerDropped', function(reason)
  local src = source
  local session = sessions[src]
  sessions[src] = nil
  if not session then
    return
  end
  Emit('game_session', {
    session_ref = session.ref,
    phase = 'dropped',
    duration_s = os.time() - session.joinedAt,
    drop_category = Envelope.classifyDrop(reason),
  })
end)
