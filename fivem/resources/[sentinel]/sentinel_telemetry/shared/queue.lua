-- Bounded FIFO ring buffer (SEC-002/014). When full, new items are dropped and
-- counted instead of growing memory or blocking the game thread.
SentinelTelemetry = SentinelTelemetry or {}

local Queue = {}
Queue.__index = Queue

function Queue.new(capacity)
  assert(math.type(capacity) == 'integer' and capacity > 0, 'capacity must be a positive integer')
  return setmetatable({
    capacity = capacity,
    items = {},
    head = 1,
    size = 0,
    enqueued = 0,
    dropped = 0,
  }, Queue)
end

function Queue:push(item)
  if self.size >= self.capacity then
    self.dropped = self.dropped + 1
    return false
  end
  local tail = (self.head + self.size - 1) % self.capacity + 1
  self.items[tail] = item
  self.size = self.size + 1
  self.enqueued = self.enqueued + 1
  return true
end

function Queue:drain(max)
  local out = {}
  local n = math.min(max or self.size, self.size)
  for i = 1, n do
    out[i] = self.items[self.head]
    self.items[self.head] = nil
    self.head = self.head % self.capacity + 1
  end
  self.size = self.size - n
  return out
end

function Queue:stats()
  return {
    capacity = self.capacity,
    queued = self.size,
    enqueued = self.enqueued,
    dropped = self.dropped,
  }
end

SentinelTelemetry.Queue = Queue
