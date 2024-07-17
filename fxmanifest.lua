fx_version 'adamant'
rdr3_warning 'I acknowledge that this is a prerelease build of RedM, and I am aware my resources *will* become incompatible once RedM ships.'
game "rdr3"
lua54 'yes'

author 'RISKYSHOT'
description 'A Minigame Resource. Thanks MaximilianAdF for code.'
version '1.0'

client_scripts {
    'data/*.lua',
    'client/class.lua',
    '@vorp_core/client/dataview.lua',
    'client/main.lua',
    'client/ragdoll.lua',
}

shared_scripts {
    '@ox_lib/init.lua',
    'config/*.lua'
}

