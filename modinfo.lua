-- Ficha do mod para o Don't Starve Together (campos lidos por modindex.lua).
-- Este arquivo roda num ambiente próprio, sem acesso ao jogo: só variáveis.

name = "DST Card Game"
description = "Card game 1 contra 1 jogado dentro de uma arena do Don't Starve Together. Projeto de fã, sem fins lucrativos."
author = "herli-son"
version = "0.1.0"

-- MOD_API_VERSION em mods.lua.
api_version = 10

dst_compatible = true
dont_starve_compatible = false
reign_of_giants_compatible = false

-- Todo cliente precisa do mod: o id dos tiles, as RPCs e as variáveis de rede
-- são gerados por ordem de registro e têm de bater entre servidor e clientes
-- (docs/investigacao-scripts-dst.md).
all_clients_require_mod = true
client_only_mod = false

-- Nenhum ícone por enquanto: icon_atlas e icon só podem apontar para arquivos
-- que existem na pasta do mod (modindex.lua avisa e descarta se não existirem).

server_filter_tags = { "card game", "duelo", "pvp" }

configuration_options = {}
