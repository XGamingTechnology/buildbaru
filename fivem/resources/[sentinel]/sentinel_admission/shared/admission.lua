-- Pure admission logic (NET-005/006/007, SEC-004). No FiveM natives here so
-- the rules can be unit tested; server/main.lua wires it to deferrals.
--
-- Principles:
--   * Observe mode by default: decisions are recorded, nobody is turned away
--     except by the capacity queue.
--   * An IP/endpoint is never a player identity (CGNAT). Sharing a network
--     source is recorded as a count and never rejects on its own.
--   * Rate limiting is a short, expiring cooldown, never a ban.
--   * Raw license/endpoint values stay in memory, mapped to random refs; only
--     refs and counts leave this module.
SentinelAdmission = SentinelAdmission or {}

local Admission = {}
Admission.__index = Admission

Admission.DEFAULTS = {
  mode = 'observe',          -- 'observe' | 'enforce'
  maxPlayers = 48,
  queueCapacity = 200,
  queueTimeoutS = 900,
  reserveTtlS = 180,         -- slot held between admit and playerJoining
  rateWindowS = 60,
  rateMaxAttempts = 6,       -- per identity per window
  cooldownS = 30,
  refTtlS = 3600,            -- forget pseudonym mappings after inactivity
}

local function copyDefaults(cfg)
  local out = {}
  for key, value in pairs(Admission.DEFAULTS) do
    out[key] = value
  end
  for key, value in pairs(cfg or {}) do
    out[key] = value
  end
  assert(out.mode == 'observe' or out.mode == 'enforce', 'mode must be observe or enforce')
  return out
end

-- random: function returning a non-negative integer (injected for tests).
function Admission.new(cfg, random)
  return setmetatable({
    cfg = copyDefaults(cfg),
    random = random or function() return math.random(0, 0x7fffffff) end,
    refs = {},          -- kind .. raw -> { ref, seen }
    refSeq = 0,
    attempts = {},      -- identityRef -> { timestamps }
    cooldownUntil = {}, -- identityRef -> time
    queue = {},         -- array of { token, identityRef, enqueuedAt }
    reserved = {},      -- identityRef -> reservedAt
    active = {},        -- server id -> sourceRef
    sourceCounts = {},  -- sourceRef -> active sessions
  }, Admission)
end

function Admission:ref(kind, raw, now)
  if raw == nil or raw == '' then
    return nil
  end
  local key = kind .. '\0' .. raw
  local entry = self.refs[key]
  if not entry then
    self.refSeq = self.refSeq + 1
    entry = { ref = ('%s-%08x%x'):format(kind, self.random() % 0x100000000, self.refSeq) }
    self.refs[key] = entry
  end
  entry.seen = now
  return entry.ref
end

function Admission:prune(now)
  for identityRef, list in pairs(self.attempts) do
    if #list == 0 or now - list[#list] > self.cfg.rateWindowS then
      self.attempts[identityRef] = nil
    end
  end
  for identityRef, untilTs in pairs(self.cooldownUntil) do
    if untilTs <= now then
      self.cooldownUntil[identityRef] = nil
    end
  end
  self:reservedCount(now)

  -- Refs still referenced by sessions, queue, reservations or cooldowns stay,
  -- otherwise a long session would split its shared-source count.
  local inUse = {}
  for _, sourceRef in pairs(self.active) do
    inUse[sourceRef] = true
  end
  for _, entry in ipairs(self.queue) do
    if entry.identityRef then
      inUse[entry.identityRef] = true
    end
  end
  for identityRef in pairs(self.reserved) do
    inUse[identityRef] = true
  end
  for identityRef in pairs(self.cooldownUntil) do
    inUse[identityRef] = true
  end
  for key, entry in pairs(self.refs) do
    if not inUse[entry.ref] and now - entry.seen > self.cfg.refTtlS then
      self.refs[key] = nil
    end
  end
end

function Admission:recordAttempt(identityRef, now)
  local list = self.attempts[identityRef] or {}
  local kept = {}
  for _, ts in ipairs(list) do
    if now - ts < self.cfg.rateWindowS then
      kept[#kept + 1] = ts
    end
  end
  kept[#kept + 1] = now
  self.attempts[identityRef] = kept
  return #kept
end

function Admission:sharedCount(sourceRef)
  return sourceRef and (self.sourceCounts[sourceRef] or 0) or 0
end

-- input = { identity = raw license or nil, source = raw endpoint or nil }
-- Returns a decision table:
--   outcome  'accepted' | 'deferred' | 'rejected'  (what actually happens)
--   would    same set; what enforce mode would do
--   reason   short machine reason or 'none'
--   identityRef, sourceRef, sharedCount, retryAfterS
function Admission:evaluate(input, now)
  local identityRef = self:ref('p', input.identity, now)
  local sourceRef = self:ref('s', input.source, now)
  local decision = {
    identityRef = identityRef,
    sourceRef = sourceRef,
    sharedCount = self:sharedCount(sourceRef),
    would = 'accepted',
    reason = 'none',
  }

  if not identityRef then
    decision.would, decision.reason = 'rejected', 'missing_identity'
  else
    local attempts = self:recordAttempt(identityRef, now)
    local cooldown = self.cooldownUntil[identityRef]
    if cooldown and cooldown > now then
      decision.would, decision.reason = 'deferred', 'cooldown'
      decision.retryAfterS = cooldown - now
    elseif attempts > self.cfg.rateMaxAttempts then
      self.cooldownUntil[identityRef] = now + self.cfg.cooldownS
      decision.would, decision.reason = 'deferred', 'rate_limited'
      decision.retryAfterS = self.cfg.cooldownS
    end
  end

  decision.outcome = self.cfg.mode == 'enforce' and decision.would or 'accepted'
  return decision
end

-- Capacity queue (functional in both modes). A reconnect by the same identity
-- keeps its place instead of going to the back.
function Admission:enqueue(token, identityRef, now)
  for index, entry in ipairs(self.queue) do
    if identityRef and entry.identityRef == identityRef then
      entry.token = token
      return index
    end
  end
  if #self.queue >= self.cfg.queueCapacity then
    return nil, 'queue_full'
  end
  self.queue[#self.queue + 1] = { token = token, identityRef = identityRef, enqueuedAt = now }
  return #self.queue
end

function Admission:position(token)
  for index, entry in ipairs(self.queue) do
    if entry.token == token then
      return index, #self.queue
    end
  end
  return nil, #self.queue
end

function Admission:leave(token)
  for index, entry in ipairs(self.queue) do
    if entry.token == token then
      table.remove(self.queue, index)
      return true
    end
  end
  return false
end

function Admission:reservedCount(now)
  local n = 0
  for identityRef, at in pairs(self.reserved) do
    if now - at > self.cfg.reserveTtlS then
      self.reserved[identityRef] = nil
    else
      n = n + 1
    end
  end
  return n
end

-- Returns 'admit', 'wait' or 'timeout'. Only the head of the queue is admitted,
-- and only while connected + reserved players stay below maxPlayers.
function Admission:tryAdmit(token, playerCount, now)
  local index = self:position(token)
  if not index then
    return 'timeout'
  end
  local entry = self.queue[index]
  if now - entry.enqueuedAt > self.cfg.queueTimeoutS then
    table.remove(self.queue, index)
    return 'timeout'
  end
  if index ~= 1 or playerCount + self:reservedCount(now) >= self.cfg.maxPlayers then
    return 'wait'
  end
  table.remove(self.queue, 1)
  -- Observe mode may admit a player without identity; reserve by token then.
  self.reserved[entry.identityRef or ('t:' .. tostring(token))] = now
  return 'admit'
end

function Admission:onJoined(serverId, identity, source, now)
  local identityRef = self:ref('p', identity, now)
  if identityRef then
    self.reserved[identityRef] = nil
  end
  local sourceRef = self:ref('s', source, now)
  if sourceRef then
    self.active[serverId] = sourceRef
    self.sourceCounts[sourceRef] = (self.sourceCounts[sourceRef] or 0) + 1
  end
end

function Admission:onDropped(serverId)
  local sourceRef = self.active[serverId]
  self.active[serverId] = nil
  if sourceRef then
    local n = (self.sourceCounts[sourceRef] or 1) - 1
    self.sourceCounts[sourceRef] = n > 0 and n or nil
  end
end

SentinelAdmission.Admission = Admission
