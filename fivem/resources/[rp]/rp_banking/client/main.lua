-- rp_banking client: bank counters with an ox_lib menu. It only collects the
-- player's intent; the server decides. Draft, unverified in game.
local Config = RpBanking.Config

local MESSAGES = {
  BANK_INVALID_AMOUNT = 'Jumlah tidak valid.',
  BANK_INVALID_TARGET = 'Penerima tidak ditemukan.',
  BANK_RATE_LIMITED = 'Terlalu cepat, coba lagi sebentar.',
  BANK_TOO_FAR = 'Anda harus berada di bank.',
  BANK_NOT_LOADED = 'Karakter belum dimuat.',
  ECON_INSUFFICIENT_FUNDS = 'Saldo tidak cukup.',
  ECON_ACCOUNT_FROZEN = 'Rekening sedang dibekukan.',
  ECON_UNAVAILABLE = 'Bank sedang sibuk, coba lagi.',
}

local function newRequestId()
  return ('%x%04x%04x'):format(GetGameTimer(), math.random(0, 0xffff), math.random(0, 0xffff))
end

local function submit(kind, req)
  local result = lib.callback.await('rp_banking:' .. kind, false, req)
  -- Unknown outcome: retrying with the same requestId is safe (idempotent).
  if result and result.code == 'ECON_UNAVAILABLE' then
    Wait(1000)
    result = lib.callback.await('rp_banking:' .. kind, false, req)
  end
  if result and result.ok then
    lib.notify({ type = 'success', description = 'Transaksi berhasil.' })
  else
    lib.notify({ type = 'error', description = MESSAGES[result and result.code] or 'Transaksi gagal.' })
  end
end

local function prompt(kind, title, withTarget)
  local rows = { { type = 'number', label = 'Jumlah ($)', min = 1, max = Config.maxAmount, required = true } }
  if withTarget then
    rows[2] = { type = 'number', label = 'ID pemain penerima', min = 1, required = true }
  end
  local input = lib.inputDialog(title, rows)
  if not input then
    return
  end
  submit(kind, {
    amount = math.tointeger(input[1]),
    targetId = withTarget and math.tointeger(input[2]) or nil,
    requestId = newRequestId(),
  })
end

lib.registerContext({
  id = 'rp_banking_menu',
  title = 'Bank',
  options = {
    { title = 'Setor tunai', icon = 'arrow-down', onSelect = function() prompt('deposit', 'Setor tunai') end },
    { title = 'Tarik tunai', icon = 'arrow-up', onSelect = function() prompt('withdraw', 'Tarik tunai') end },
    { title = 'Transfer', icon = 'right-left', onSelect = function() prompt('transfer', 'Transfer ke pemain', true) end },
  },
})

for _, loc in ipairs(Config.locations) do
  lib.points.new({
    coords = vec3(loc.x, loc.y, loc.z),
    distance = Config.radius,
    onEnter = function()
      lib.showTextUI('[E] ' .. loc.label)
    end,
    onExit = function()
      lib.hideTextUI()
    end,
    nearby = function()
      if IsControlJustReleased(0, 38) then
        lib.showContext('rp_banking_menu')
      end
    end,
  })
end
