-- rp_qbx_bridge (replaces legacy pri_base; ADR 0003). Makes the econ ledger
-- the single source of truth for Qbox cash and bank:
--   * opens ledger accounts per character (idempotent) with opening balances
--     minted from the treasury,
--   * mirrors ledger balances into Qbox PlayerData.money (display/compat only),
--   * guards Qbox add/remove/setMoney so other resources cannot change
--     ledger-owned money directly (enforce) or are reported (observe),
--   * routes Qbox paychecks through the ledger (see docs/QBOX.md).
-- Unverified on FXServer until the staging selftest covers it.
local Logic = RpQbxBridge.Logic

local mode = GetConvar('rp_qbx_money_guard', 'enforce')
if mode ~= 'enforce' and mode ~= 'observe' then
  print(('[rp_qbx_bridge] unknown guard mode %q, using enforce'):format(mode))
  mode = 'enforce'
end

local opening = {
  cash = GetConvarInt('rp_qbx_opening_cash', 500),
  bank = GetConvarInt('rp_qbx_opening_bank', 5000),
}
local paycheckWindowS = GetConvarInt('rp_qbx_paycheck_window_s', 600)

local syncing = false
local treasury = {}
local accountCache = {}

local function emitSignal(citizenid, hookName)
  if GetResourceState('sentinel_telemetry') ~= 'started' then
    return
  end
  pcall(function()
    exports.sentinel_telemetry:Emit('game_abuse_signal', {
      subject_ref = citizenid and Logic.actorFor(citizenid) or 'unknown',
      rule_id = 'ECON-001',
      signal_kind = 'economy_anomaly',
      score = 0.5,
    })
  end)
  print(('[rp_qbx_bridge] %s direct Qbox %s on ledger money (%s)')
    :format(mode == 'enforce' and 'blocked' or 'observed', hookName, citizenid or 'offline'))
end

local function treasuryId(moneyType)
  if not treasury[moneyType] then
    treasury[moneyType] = MySQL.scalar.await(
      "SELECT account_id FROM econ_accounts WHERE owner_kind = 'system' AND owner_ref = 'treasury' AND currency = ?",
      { Logic.currencyFor(moneyType) })
  end
  return treasury[moneyType]
end

local function balanceOf(accountId)
  return tonumber(MySQL.scalar.await('SELECT balance FROM econ_accounts WHERE account_id = ?', { accountId }))
end

-- Returns the ledger account id for a character's cash or bank, opening it
-- (and minting the opening balance once) when it does not exist yet.
local function AccountId(citizenid, moneyType)
  if not Logic.validCitizenId(citizenid) or not Logic.currencyFor(moneyType) then
    return nil
  end
  local cacheKey = citizenid .. ':' .. moneyType
  if accountCache[cacheKey] then
    return accountCache[cacheKey]
  end

  local row = Logic.firstRow(MySQL.query.await('CALL econ_open_account(?, ?, ?)',
    { 'character', citizenid, Logic.currencyFor(moneyType) }))
  if not row or not row.account_id then
    return nil
  end

  -- Keyed by character and type, so a crash between open and mint is safe to
  -- retry: the mint replays instead of paying twice.
  if opening[moneyType] > 0 then
    local result = exports.rp_economy:Transfer({
      from = treasuryId(moneyType),
      to = row.account_id,
      amount = opening[moneyType],
      reason = 'opening_balance',
      actor = 'rp-qbx-bridge',
      idempotencyKey = Logic.openingKey(citizenid, moneyType),
    })
    if not result.ok then
      print(('[rp_qbx_bridge] opening balance for %s/%s failed: %s'):format(citizenid, moneyType, result.code))
      return nil
    end
  end

  accountCache[cacheKey] = row.account_id
  return row.account_id
end

-- Copies ledger balances into the Qbox player's money (mirror only).
local function Sync(src)
  local player = exports.qbx_core:GetPlayer(src)
  if not player then
    return false
  end
  local citizenid = player.PlayerData.citizenid
  for moneyType in pairs(Logic.CURRENCY_BY_TYPE) do
    local accountId = AccountId(citizenid, moneyType)
    local balance = accountId and balanceOf(accountId)
    if balance then
      syncing = true
      local ok, err = pcall(function()
        exports.qbx_core:SetMoney(src, moneyType, balance, 'ledger_sync')
      end)
      syncing = false
      if not ok then
        print(('[rp_qbx_bridge] mirror failed for %s/%s: %s'):format(citizenid, moneyType, err))
      end
    end
  end
  return true
end

-- Qbox paycheck through the ledger. Wire it via config.sendPaycheck in
-- qbx_core (docs/QBOX.md); the window must equal the paycheck interval.
local function Paycheck(src, amount)
  local player = exports.qbx_core:GetPlayer(src)
  if not player or math.type(amount) ~= 'integer' or amount <= 0 then
    return { ok = false, code = 'ECON_INVALID_REQUEST' }
  end
  local citizenid = player.PlayerData.citizenid
  local result = exports.rp_economy:Transfer({
    from = treasuryId('bank'),
    to = AccountId(citizenid, 'bank'),
    amount = amount,
    reason = 'paycheck',
    actor = 'rp-qbx-bridge',
    idempotencyKey = Logic.paycheckKey(citizenid, os.time(), paycheckWindowS),
  })
  Sync(src)
  return result
end

exports('AccountId', AccountId)
exports('Sync', Sync)
exports('Paycheck', Paycheck)

local function citizenOf(source)
  local player = source and exports.qbx_core:GetPlayer(source)
  return player and player.PlayerData.citizenid or nil
end

CreateThread(function()
  for _, hookName in ipairs({ 'addMoney', 'removeMoney', 'setMoney' }) do
    exports.qbx_core:registerHook(hookName, function(payload)
      local allow, signal = Logic.guard(payload, syncing, mode)
      if signal then
        emitSignal(citizenOf(payload.source), hookName)
      end
      return allow
    end)
  end

  -- Resource restart: re-mirror everyone already loaded.
  for src in pairs(exports.qbx_core:GetQBPlayers() or {}) do
    Sync(src)
  end
end)

AddEventHandler('QBCore:Server:PlayerLoaded', function(player)
  local src = player.PlayerData.source
  CreateThread(function()
    Sync(src)
  end)
end)
