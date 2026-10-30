fx_version 'cerulean'
game 'gta5'
lua54 'yes'

name 'rp_qbx_bridge'
description 'Makes the econ ledger authoritative for Qbox cash/bank (replaces legacy pri_base; draft, unverified on FXServer)'
version '0.1.0'

dependencies {
  'oxmysql',
  'qbx_core',
  'rp_economy',
}

server_scripts {
  '@oxmysql/lib/MySQL.lua',
  'shared/logic.lua',
  'server/main.lua',
}
