-- rp_banking server (replaces legacy pri_banking). Deposit, withdraw and
-- player-to-player transfer, all as ledger transfers through rp_economy.
-- The client sends only an intent; the server checks the character, amount,
-- rate limit and that the player is standing at a bank. Draft, unverified on
-- FXServer.
local Logic = RpBanking.Logic
local Config = RpBanking.Config

local limiter = Logic.RateLimiter.new(Config.rateMax, Config.rateWindowS)
local limits = { maxAmount = Config.maxAmount }

local function signal(citizenid, ruleId, kind)
  if GetResourceState('sentinel_telemetry') ~= 'started' then
    return
  end
  pcall(function()
    exports.sentinel_telemetry:Emit('game_abuse_signal', {
      subject_ref = 'cid-' .. string.lower(citizenid),
      rule_id = ruleId,
      signal_kind = kind,
      score = 0.3,
    })
  end)
end

local function handle(src, kind, raw)
  local player = exports.qbx_core:GetPlayer(src)
  if not player then
    return { ok = false, code = 'BANK_NOT_LOADED' }
  end
  local citizenid = player.PlayerData.citizenid

  local req, code = Logic.validate(kind, raw, limits)
  if not req then
    return { ok = false, code = code }
  end
  if not limiter:allow(citizenid, os.time()) then
    signal(citizenid, 'BANK-002', 'rate_limit')
    return { ok = false, code = 'BANK_RATE_LIMITED' }
  end
  if not Logic.isNear(GetEntityCoords(GetPlayerPed(src)), Config.locations, Config.radius) then
    signal(citizenid, 'BANK-001', 'impossible_state')
    return { ok = false, code = 'BANK_TOO_FAR' }
  end

  local fromType, toType = Logic.route(kind)
  local toCitizen, targetSrc = citizenid, nil
  if kind == 'transfer' then
    local target = req.targetId ~= src and exports.qbx_core:GetPlayer(req.targetId)
    if not target then
      return { ok = false, code = 'BANK_INVALID_TARGET' }
    end
    toCitizen, targetSrc = target.PlayerData.citizenid, req.targetId
  end

  local key = Logic.keyFor(citizenid, kind, req.requestId)
  local from = exports.rp_qbx_bridge:AccountId(citizenid, fromType)
  local to = exports.rp_qbx_bridge:AccountId(toCitizen, toType)
  if not key or not from or not to then
    return { ok = false, code = 'ECON_UNAVAILABLE' }
  end

  local result = exports.rp_economy:Transfer({
    from = from,
    to = to,
    amount = req.amount,
    reason = 'bank_' .. kind,
    actor = 'cid-' .. string.lower(citizenid),
    idempotencyKey = key,
  })

  exports.rp_qbx_bridge:Sync(src)
  if targetSrc then
    exports.rp_qbx_bridge:Sync(targetSrc)
    if result.ok and result.status == 'committed' then
      TriggerClientEvent('ox_lib:notify', targetSrc, {
        type = 'success',
        description = ('Anda menerima transfer bank $%d'):format(req.amount),
      })
    end
  end
  return result
end

for kind in pairs(Logic.ROUTES) do
  lib.callback.register('rp_banking:' .. kind, function(src, req)
    return handle(src, kind, req)
  end)
end

CreateThread(function()
  while true do
    Wait(60000)
    limiter:prune(os.time())
  end
end)
