fx_version 'cerulean'
game 'gta5'
lua54 'yes'

name 'sentinel_admission'
description 'CGNAT-safe, fail-open admission queue; observe mode by default (draft, unverified on FXServer)'
version '0.1.0'

server_scripts {
  'shared/admission.lua',
  'server/main.lua',
}
