-- Pure validation helpers for rp_economy (RP-004, G-04). No FiveM natives here
-- so the rules can be unit tested outside FXServer.
RpEconomy = RpEconomy or {}

local Validate = {}

-- Codes raised by econ_transfer (db/migrations/0001) plus resource-level codes.
Validate.CODES = {
  ECON_INVALID_REQUEST = true,
  ECON_INVALID_AMOUNT = true,
  ECON_SAME_ACCOUNT = true,
  ECON_INVALID_IDEMPOTENCY_KEY = true,
  ECON_ACCOUNT_NOT_FOUND = true,
  ECON_ACCOUNT_FROZEN = true,
  ECON_CURRENCY_MISMATCH = true,
  ECON_INSUFFICIENT_FUNDS = true,
  ECON_IDEMPOTENCY_CONFLICT = true,
  ECON_APPEND_ONLY = true,
  -- Outcome unknown (DB down, timeout, unexpected result). The caller must
  -- retry with the SAME idempotency key; never assume success or failure.
  ECON_UNAVAILABLE = true,
}

local function isPositiveInt(v)
  return math.type(v) == 'integer' and v > 0
end

function Validate.transfer(req, limits)
  if type(req) ~= 'table' then
    return false, 'ECON_INVALID_REQUEST'
  end
  if not isPositiveInt(req.from) or not isPositiveInt(req.to) then
    return false, 'ECON_INVALID_REQUEST'
  end
  if req.from == req.to then
    return false, 'ECON_SAME_ACCOUNT'
  end
  if not isPositiveInt(req.amount) or req.amount > limits.maxAmount then
    return false, 'ECON_INVALID_AMOUNT'
  end
  if type(req.idempotencyKey) ~= 'string' or not req.idempotencyKey:match('^[%w_.:%-]+$')
      or #req.idempotencyKey < 8 or #req.idempotencyKey > 80 then
    return false, 'ECON_INVALID_IDEMPOTENCY_KEY'
  end
  if type(req.reason) ~= 'string' or not req.reason:match('^[a-z0-9_]+$') or #req.reason > 64 then
    return false, 'ECON_INVALID_REQUEST'
  end
  -- No ':' so platform identifiers (license:, steam:, ...) cannot be used as actors.
  if type(req.actor) ~= 'string' or not req.actor:match('^[a-z0-9][a-z0-9_.%-]*$') or #req.actor > 64 then
    return false, 'ECON_INVALID_REQUEST'
  end
  return true
end

-- Extracts a known ECON_* code from a database error; anything else is
-- treated as an unknown outcome.
function Validate.mapDbError(message)
  local code = tostring(message):match('ECON_[A-Z_]+')
  if code and Validate.CODES[code] then
    return code
  end
  return 'ECON_UNAVAILABLE'
end

-- Accepts the result of CALL econ_transfer(...) in either the flat-rows or the
-- multi-result-set shape and returns the (tx_id, status) row, or nil.
-- The exact oxmysql shape is unverified until tested on FXServer.
function Validate.extractCallRow(result)
  if type(result) ~= 'table' then
    return nil
  end
  local row = result[1]
  if type(row) == 'table' and row.tx_id == nil and type(row[1]) == 'table' then
    row = row[1]
  end
  if type(row) ~= 'table' or row.tx_id == nil then
    return nil
  end
  if row.status ~= 'committed' and row.status ~= 'replayed' then
    return nil
  end
  return row
end

RpEconomy.Validate = Validate
