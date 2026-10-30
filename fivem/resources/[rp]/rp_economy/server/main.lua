-- rp_economy server (RP-002, RP-004, RP-005, G-04). Money moves only through
-- the server-side Transfer export backed by the econ_transfer procedure.
-- There are deliberately NO client-triggerable net events in this resource:
-- gameplay resources validate the player action server-side, then call
-- exports.rp_economy:Transfer with their own idempotency key.
local Validate = RpEconomy.Validate

local limits = {
  maxAmount = GetConvarInt('rp_economy_max_transfer', 100000000),
}

-- Telemetry is optional and must never break or delay a transfer.
local function emit(fields)
  if GetResourceState('sentinel_telemetry') ~= 'started' then
    return
  end
  pcall(function()
    exports.sentinel_telemetry:Emit('economic_mutation', fields)
  end)
end

local function report(req, status, row, code)
  emit({
    tx_id = row and ('tx-%d'):format(row.tx_id) or nil,
    account_ref = ('acct-%d'):format(math.type(req.from) == 'integer' and req.from or 0),
    counterparty_ref = ('acct-%d'):format(math.type(req.to) == 'integer' and req.to or 0),
    delta = -(math.type(req.amount) == 'integer' and req.amount or 0),
    currency = row and row.currency or nil,
    cause = req.reason,
    idempotency_key = req.idempotencyKey,
    actor_ref = req.actor,
    status = status,
    reject_code = code,
  })
end

-- req = { from, to, amount, reason, actor, idempotencyKey }
-- The currency is a property of the accounts, never of the request.
-- returns { ok = true, txId, status = 'committed'|'replayed' }
--      or { ok = false, code = 'ECON_*' }
local function Transfer(req)
  local valid, code = Validate.transfer(req, limits)
  if not valid then
    return { ok = false, code = code }
  end

  local success, result = pcall(MySQL.query.await, 'CALL econ_transfer(?, ?, ?, ?, ?, ?)', {
    req.idempotencyKey, req.from, req.to, req.amount, req.reason, req.actor,
  })
  if not success then
    code = Validate.mapDbError(result)
    report(req, 'rejected', nil, code)
    return { ok = false, code = code }
  end

  local row = Validate.extractCallRow(result)
  if not row then
    return { ok = false, code = 'ECON_UNAVAILABLE' }
  end
  report(req, row.status, row)
  return { ok = true, txId = row.tx_id, status = row.status }
end

exports('Transfer', Transfer)
