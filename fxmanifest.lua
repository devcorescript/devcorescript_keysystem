fx_version 'cerulean'
game 'gta5'

author 'DevCoreScripts'
description 'esx_keysystem — Vehicle Keys (ESX + ox_inventory + oxmysql)'
version '1.0.0'

shared_script 'config.lua'

client_scripts {
  'client/client.lua',
  'client/locksmith.lua'
}

server_scripts {
  'server/shared.lua',
  'server/server.lua',
  'server/locksmith.lua'
}

ui_page 'html/locksmith/index.html'

files {
  'html/locksmith/index.html',
  'html/locksmith/style.css',
  'html/locksmith/script.js'
}

dependencies {
  'es_extended',
  'ox_inventory',
  'oxmysql'
}