-- Pure helpers for rp_qbx_bridge (no natives, unit tested).
RpQbxBridge = RpQbxBridge or {}

local Logic = {}

-- Qbox money types that the ledger owns. Anything else (e.g. crypto) stays
-- outside the ledger and must be disabled or handled separately.
Logic.CURRENCY_BY_TYPE = {
  cash = 'game_cash',
  bank = 'game_bank',
}

function Logic.currencyFor(moneyType)
  return Logic.CURRENCY_BY_TYPE[moneyType]
end

-- Audit actor label for a character. Lowercased because telemetry refs are
-- lowercase; the citizenid itself is stored unchanged as the account owner.
function Logic.actorFor(citizenid)
  return 'cid-' .. string.lower(citizenid)
end

function Logic.validCitizenId(citizenid)
  return type(citizenid) == 'string' and citizenid:match('^[%w][%w_.%-]*$') ~= nil and #citizenid <= 64
end

-- Decides what the money guard does with a Qbox add/remove/setMoney hook.
--   payload  = { source, moneyType, amount } from qbx_core
--   syncing  = true while this resource itself is mirroring the ledger
--   mode     = 'enforce' | 'observe'
-- Returns allow (boolean) and an abuse-signal kind or nil.
function Logic.guard(payload, syncing, mode)
  if syncing then
    return true, nil
  end
  if type(payload) ~= 'table' or not Logic.currencyFor(payload.moneyType) then
    return true, nil
  end
  -- A direct change to ledger-owned money from some other resource.
  if mode == 'observe' then
    return true, 'economy_anomaly'
  end
  return false, 'economy_anomaly'
end

-- Idempotency keys keep the citizenid's case: citizenids are case-sensitive,
-- and lowercasing could make two characters share a key.
-- One paycheck per character per paycheck window.
function Logic.paycheckKey(citizenid, now, windowS)
  return ('pay-%s-%d'):format(citizenid, now // windowS)
end

function Logic.openingKey(citizenid, moneyType)
  return ('open-%s-%s'):format(citizenid, moneyType)
end

-- First row of a CALL result in either the flat-rows or multi-result-set shape
-- (same tolerance as rp_economy until the oxmysql shape is confirmed).
function Logic.firstRow(result)
  if type(result) ~= 'table' then
    return nil
  end
  local row = result[1]
  if type(row) == 'table' and row.account_id == nil and type(row[1]) == 'table' then
    row = row[1]
  end
  return type(row) == 'table' and row or nil
end

RpQbxBridge.Logic = Logic
