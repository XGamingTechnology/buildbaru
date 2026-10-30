fx_version 'cerulean'
game 'gta5'
lua54 'yes'

name 'rp_banking'
description 'Bank deposit/withdraw/transfer through the econ ledger (replaces legacy pri_banking; draft, unverified on FXServer)'
version '0.1.0'

dependencies {
  'ox_lib',
  'qbx_core',
  'rp_economy',
  'rp_qbx_bridge',
}

shared_scripts {
  '@ox_lib/init.lua',
  'shared/config.lua',
  'shared/logic.lua',
}

client_scripts {
  'client/main.lua',
}

server_scripts {
  'server/main.lua',
}
