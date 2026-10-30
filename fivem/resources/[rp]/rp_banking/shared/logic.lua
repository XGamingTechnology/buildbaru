-- Pure banking rules (no natives, unit tested). The client only sends an
-- intent; every check that matters happens on the server.
RpBanking = RpBanking or {}

local Logic = {}

-- kind -> source money type, destination money type
Logic.ROUTES = {
  deposit = { 'cash', 'bank' },
  withdraw = { 'bank', 'cash' },
  transfer = { 'bank', 'bank' },
}

function Logic.route(kind)
  local route = Logic.ROUTES[kind]
  if not route then
    return nil
  end
  return route[1], route[2]
end

-- Values crossing the network may arrive as integral floats; accept those and
-- reject anything fractional, non-finite or non-numeric.
function Logic.toInteger(value)
  if math.type(value) == 'integer' then
    return value
  end
  if math.type(value) == 'float' and value == math.floor(value) and value > -2^53 and value < 2^53 then
    return math.tointeger(value)
  end
  return nil
end

-- req = { amount, requestId, targetId? } as sent by the client.
-- Returns a normalized copy, or nil and an error code.
function Logic.validate(kind, req, limits)
  if not Logic.ROUTES[kind] or type(req) ~= 'table' then
    return nil, 'BANK_INVALID_REQUEST'
  end
  local amount = Logic.toInteger(req.amount)
  if not amount or amount <= 0 or amount > limits.maxAmount then
    return nil, 'BANK_INVALID_AMOUNT'
  end
  if type(req.requestId) ~= 'string' or #req.requestId < 8 or #req.requestId > 40
      or not req.requestId:match('^[%w%-]+$') then
    return nil, 'BANK_INVALID_REQUEST'
  end
  local out = { amount = amount, requestId = req.requestId }
  if kind == 'transfer' then
    out.targetId = Logic.toInteger(req.targetId)
    if not out.targetId or out.targetId <= 0 then
      return nil, 'BANK_INVALID_TARGET'
    end
  end
  return out
end

-- Idempotency key: a client retry of the same request replays instead of
-- moving money twice. Scoped by character and kind.
function Logic.keyFor(citizenid, kind, requestId)
  local key = ('bank-%s-%s-%s'):format(citizenid, kind, requestId)
  if #key > 80 or not key:match('^[%w_.:%-]+$') then
    return nil
  end
  return key
end

function Logic.isNear(pos, points, radius)
  if type(pos) ~= 'table' and type(pos) ~= 'userdata' and type(pos) ~= 'vector3' then
    return false
  end
  local r2 = radius * radius
  for _, p in ipairs(points) do
    local dx, dy, dz = pos.x - p.x, pos.y - p.y, pos.z - p.z
    if dx * dx + dy * dy + dz * dz <= r2 then
      return true
    end
  end
  return false
end

-- Sliding-window limiter keyed by character.
local RateLimiter = {}
RateLimiter.__index = RateLimiter

function RateLimiter.new(max, windowS)
  return setmetatable({ max = max, windowS = windowS, hits = {} }, RateLimiter)
end

function RateLimiter:allow(key, now)
  local kept = {}
  for _, ts in ipairs(self.hits[key] or {}) do
    if now - ts < self.windowS then
      kept[#kept + 1] = ts
    end
  end
  if #kept >= self.max then
    self.hits[key] = kept
    return false
  end
  kept[#kept + 1] = now
  self.hits[key] = kept
  return true
end

function RateLimiter:prune(now)
  for key, list in pairs(self.hits) do
    if #list == 0 or now - list[#list] >= self.windowS then
      self.hits[key] = nil
    end
  end
end

Logic.RateLimiter = RateLimiter

RpBanking.Logic = Logic
