fx_version 'cerulean'
game 'gta5'
lua54 'yes'

name 'sentinel_selftest'
description 'Staging-only smoke checks for rp_economy, sentinel_telemetry and DB grants. Never ensure in production.'
version '0.1.0'

dependencies {
  'oxmysql',
  'rp_economy',
  'sentinel_telemetry',
}

server_scripts {
  '@oxmysql/lib/MySQL.lua',
  'server/main.lua',
}
