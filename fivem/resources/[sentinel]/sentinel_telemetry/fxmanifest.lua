fx_version 'cerulean'
game 'gta5'
lua54 'yes'

name 'sentinel_telemetry'
description 'Non-blocking, bounded, privacy-guarded telemetry emitter (draft, unverified on FXServer)'
version '0.1.0'

server_scripts {
  'shared/queue.lua',
  'shared/envelope.lua',
  'server/main.lua',
}
