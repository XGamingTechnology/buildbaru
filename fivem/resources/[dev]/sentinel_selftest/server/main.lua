-- sentinel_selftest: staging-only smoke checks that run inside FXServer and
-- record evidence the unit tests cannot (oxmysql CALL shape, exports across
-- resources, DB privileges). Never ensure this resource in production.
--
-- Runs only when `set sentinel_selftest 1` and the database name ends in
-- _staging or _test. Needs the synthetic accounts from
-- deploy/staging/seed_selftest.sql.
if GetConvar('sentinel_selftest', '0') ~= '1' then
  return
end

local results = {}

local function check(name, ok, detail)
  results[#results + 1] = ok and true or false
  print(('[selftest] %s %s%s'):format(ok and 'PASS' or 'FAIL', name, detail and (' -- ' .. detail) or ''))
end

local function skip(name, why)
  print(('[selftest] SKIP %s -- %s'):format(name, why))
end

local function summary()
  local passed = 0
  for _, ok in ipairs(results) do
    if ok then
      passed = passed + 1
    end
  end
  print(('[selftest] SUMMARY %s %d/%d'):format(passed == #results and 'PASS' or 'FAIL', passed, #results))
end

local function accountId(ref)
  return MySQL.scalar.await(
    "SELECT account_id FROM econ_accounts WHERE owner_kind = 'character' AND owner_ref = ? AND currency = 'game_cash'",
    { ref })
end

local function transfer(req)
  return exports.rp_economy:Transfer(req)
end

local function run()
  local db = MySQL.scalar.await('SELECT DATABASE()')
  if type(db) ~= 'string' or not (db:match('_staging$') or db:match('_test$')) then
    print(('[selftest] refusing to run against database %q'):format(tostring(db)))
    return
  end

  for _, res in ipairs({ 'oxmysql', 'sentinel_telemetry', 'sentinel_admission', 'rp_economy' }) do
    check('resource started: ' .. res, GetResourceState(res) == 'started', GetResourceState(res))
  end

  local a, b = accountId('selftest-a'), accountId('selftest-b')
  check('synthetic accounts seeded', a ~= nil and b ~= nil, ('a=%s b=%s'):format(tostring(a), tostring(b)))
  if not (a and b) then
    return summary()
  end

  -- Evidence for Validate.extractCallRow: the exact shape oxmysql returns.
  local stamp = ('%x'):format(os.time())
  local raw = MySQL.query.await('CALL econ_transfer(?, ?, ?, ?, ?, ?)',
    { 'selftest-raw-' .. stamp, a, b, 1, 'selftest', 'selftest' })
  print('[selftest] raw CALL result shape: ' .. json.encode(raw))
  check('raw CALL returned rows', type(raw) == 'table')

  local key = 'selftest-xfer-' .. stamp
  local req = { from = b, to = a, amount = 1, reason = 'selftest', actor = 'selftest', idempotencyKey = key }
  local first = transfer(req)
  check('Transfer commits via export', first.ok and first.status == 'committed', json.encode(first))
  local again = transfer(req)
  check('same key is replayed, not re-applied',
    again.ok and again.status == 'replayed' and again.txId == first.txId, json.encode(again))

  local conflict = transfer({ from = b, to = a, amount = 2, reason = 'selftest', actor = 'selftest', idempotencyKey = key })
  check('same key, different amount is a conflict', conflict.code == 'ECON_IDEMPOTENCY_CONFLICT', json.encode(conflict))

  local broke = transfer({ from = a, to = b, amount = 99999999, reason = 'selftest', actor = 'selftest',
    idempotencyKey = 'selftest-broke-' .. stamp })
  check('overspend is refused', broke.code == 'ECON_INSUFFICIENT_FUNDS', json.encode(broke))

  local fractional = transfer({ from = a, to = b, amount = 1.5, reason = 'selftest', actor = 'selftest',
    idempotencyKey = 'selftest-frac-' .. stamp })
  check('fractional amount is refused', fractional.code == 'ECON_INVALID_AMOUNT', json.encode(fractional))

  local total = tonumber(MySQL.scalar.await('SELECT SUM(balance) FROM econ_accounts'))
  check('ledger reconciles (sum of balances = 0)', total == 0, tostring(total))

  -- The app user must not be able to edit balances directly (least privilege).
  local ok, affected = pcall(MySQL.update.await,
    'UPDATE econ_accounts SET balance = balance + 1 WHERE account_id = ?', { a })
  check('app DB user cannot UPDATE balances', not ok or not affected or affected == 0,
    ('pcall=%s affected=%s'):format(tostring(ok), tostring(affected)))

  local before = exports.sentinel_telemetry:GetStats()
  local accepted = exports.sentinel_telemetry:Emit('game_session', { session_ref = 'sess-selftest', phase = 'joined' })
  local refused = exports.sentinel_telemetry:Emit('game_session', { session_ref = 'sess-selftest', ip = '192.0.2.1' })
  local after = exports.sentinel_telemetry:GetStats()
  check('telemetry accepts a valid event', accepted == true and after.enqueued == before.enqueued + 1)
  check('telemetry refuses an IP field', refused == false and after.rejected == before.rejected + 1)

  local active = MySQL.scalar.await('SELECT COUNT(*) FROM ops_active_mitigations')
  check('operator workflow view readable', active ~= nil, tostring(active))

  -- Qbox stack (ADR 0003). Skipped when Qbox is not installed on this host.
  if GetResourceState('qbx_core') == 'missing' then
    skip('Qbox checks', 'qbx_core is not installed')
  else
    for _, res in ipairs({ 'ox_lib', 'qbx_core', 'rp_qbx_bridge', 'rp_banking' }) do
      check('resource started: ' .. res, GetResourceState(res) == 'started', GetResourceState(res))
    end

    local qbxConfig = LoadResourceFile('qbx_core', 'config/server.lua') or ''
    check('qbx_core paychecks routed through the ledger',
      qbxConfig:find('rp_qbx_bridge:Paycheck', 1, true) ~= nil)

    if GetResourceState('rp_qbx_bridge') == 'started' then
      -- A synthetic citizenid that no real character uses.
      local cid = 'SELFTEST01'
      local first = exports.rp_qbx_bridge:AccountId(cid, 'bank')
      local second = exports.rp_qbx_bridge:AccountId(cid, 'bank')
      check('bridge opens one ledger account per character and type',
        first ~= nil and first == second, ('%s / %s'):format(tostring(first), tostring(second)))
      local minted = tonumber(MySQL.scalar.await(
        'SELECT COUNT(*) FROM econ_transactions WHERE idempotency_key = ?', { 'open-' .. cid .. '-bank' }))
      local expectMint = GetConvarInt('rp_qbx_opening_bank', 5000) > 0 and 1 or 0
      check('opening balance minted exactly once', minted == expectMint, tostring(minted))
      check('bridge refuses an invalid citizenid',
        exports.rp_qbx_bridge:AccountId('license:abc', 'bank') == nil)
      check('bridge refuses money types outside the ledger',
        exports.rp_qbx_bridge:AccountId(cid, 'crypto') == nil)
      local total = tonumber(MySQL.scalar.await('SELECT SUM(balance) FROM econ_accounts'))
      check('ledger still reconciles after bridge minting', total == 0, tostring(total))
    end
    skip('money guard, paycheck and banking', 'need a connected client; see deploy/staging/README.md')
  end

  summary()
end

CreateThread(function()
  Wait(3000) -- let the other resources finish starting
  local ok, err = pcall(run)
  if not ok then
    check('selftest crashed', false, tostring(err))
    summary()
  end
end)
