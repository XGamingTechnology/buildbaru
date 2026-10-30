-- sentinel_admission server (NET-005/006/007, SEC-004). Wires the pure
-- Admission logic to playerConnecting deferrals.
--
-- Failure policy (NET-007): if this resource errors, the player is let in.
-- An admission bug must never lock the whole community out.
local Admission = SentinelAdmission.Admission

local mode = GetConvar('sentinel_admission_mode', 'observe')
if mode ~= 'observe' and mode ~= 'enforce' then
  print(('[sentinel_admission] unknown mode %q, falling back to observe'):format(mode))
  mode = 'observe'
end

local admission = Admission.new({
  mode = mode,
  maxPlayers = GetConvarInt('sv_maxclients', 48),
  queueCapacity = GetConvarInt('sentinel_admission_queue_capacity', 200),
  queueTimeoutS = GetConvarInt('sentinel_admission_queue_timeout_s', 900),
  rateWindowS = GetConvarInt('sentinel_admission_rate_window_s', 60),
  rateMaxAttempts = GetConvarInt('sentinel_admission_rate_max', 6),
  cooldownS = GetConvarInt('sentinel_admission_cooldown_s', 30),
})

local POLL_MS = 2000

local MESSAGES = {
  checking = 'Memeriksa koneksi...',
  queue = 'Server penuh. Posisi antrean Anda: %d dari %d.',
  queue_full = 'Antrean sedang penuh. Silakan coba lagi beberapa menit lagi.',
  timeout = 'Waktu tunggu antrean habis. Silakan sambung ulang.',
  missing_identity = 'Akun Rockstar/FiveM tidak terdeteksi. Pastikan Anda login lalu sambung ulang.',
  cooldown = 'Terlalu banyak percobaan masuk. Coba lagi dalam %d detik.',
}

local function emit(fields)
  if GetResourceState('sentinel_telemetry') ~= 'started' then
    return
  end
  pcall(function()
    exports.sentinel_telemetry:Emit('connection_attempt', fields)
  end)
end

local function report(decision, outcome, startedMs, reason, position)
  emit({
    source_ref_pseudonym = decision and decision.identityRef or 'unknown',
    outcome = outcome,
    would_outcome = decision and decision.would or nil,
    elapsed_ms = math.max(0, GetGameTimer() - startedMs),
    edge_reason = reason or (decision and decision.reason) or 'none',
    admission_mode = mode,
    shared_source_count = decision and decision.sharedCount or nil,
    queue_position = position,
  })
end

local function stillConnecting(src)
  return GetPlayerEndpoint(src) ~= nil
end

local function handleConnecting(src, deferrals, startedMs)
  deferrals.update(MESSAGES.checking)
  local now = os.time()
  local decision = admission:evaluate({
    identity = GetPlayerIdentifierByType(src, 'license'),
    source = GetPlayerEndpoint(src),
  }, now)

  if decision.outcome ~= 'accepted' then
    local message = MESSAGES[decision.reason] or MESSAGES.cooldown
    deferrals.done(message:format(decision.retryAfterS or 0))
    report(decision, decision.outcome, startedMs)
    return
  end

  local token = tostring(src)
  local position, err = admission:enqueue(token, decision.identityRef, now)
  if not position then
    deferrals.done(MESSAGES.queue_full)
    report(decision, 'rejected', startedMs, err)
    return
  end

  while true do
    if not stillConnecting(src) then
      admission:leave(token)
      report(decision, 'timeout', startedMs, 'client_left')
      return
    end
    local state = admission:tryAdmit(token, GetNumPlayerIndices(), os.time())
    if state == 'admit' then
      break
    elseif state == 'timeout' then
      deferrals.done(MESSAGES.timeout)
      report(decision, 'timeout', startedMs, 'queue_timeout')
      return
    end
    local current, total = admission:position(token)
    deferrals.update(MESSAGES.queue:format(current or 0, total))
    Wait(POLL_MS)
  end

  deferrals.done()
  report(decision, 'accepted', startedMs, nil, position)
end

AddEventHandler('playerConnecting', function(_, _, deferrals)
  local src = source
  local startedMs = GetGameTimer()
  deferrals.defer()
  Wait(0)
  local ok, err = pcall(handleConnecting, src, deferrals, startedMs)
  if not ok then
    print(('[sentinel_admission] error, failing open: %s'):format(err))
    admission:leave(tostring(src))
    deferrals.done()
    report(nil, 'error', startedMs, 'admission_error')
  end
end)

AddEventHandler('playerJoining', function()
  local src = source
  admission:onJoined(src, GetPlayerIdentifierByType(src, 'license'), GetPlayerEndpoint(src), os.time())
end)

AddEventHandler('playerDropped', function()
  admission:onDropped(source)
end)

CreateThread(function()
  while true do
    Wait(60000)
    admission:prune(os.time())
  end
end)
