fx_version 'cerulean'
game 'gta5'
lua54 'yes'

name 'rp_economy'
description 'Server-authoritative, idempotent ledger transfers (draft, unverified on FXServer)'
version '0.1.0'

-- oxmysql is NOT vendored here; its license and version are pending review (D-09).
dependencies {
  'oxmysql',
}

server_scripts {
  '@oxmysql/lib/MySQL.lua',
  'shared/validate.lua',
  'server/main.lua',
}
