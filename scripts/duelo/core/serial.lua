-- Serialização de valores simples em texto, sem executar código. Lua 5.1 puro.
--
-- Este módulo não depende do motor (não dá require em nada): é o único
-- arquivo de duelo/core que os clientes do mod carregam (US #41), para
-- escrever as ações que mandam ao servidor e ler os eventos que recebem. O
-- registro de partidas (duelo/core/replay, US #82) usa as mesmas funções.
--
-- Interface:
--   local Serial = require("duelo/core/serial")
--   Serial.serialize(v) -> texto      números, strings, booleans e tabelas sem
--                                     ciclo, com chaves inteiras ou strings. As
--                                     chaves saem ordenadas: o mesmo valor dá
--                                     sempre o mesmo texto. Erro com o caminho
--                                     se houver outra coisa (função, NaN...).
--   Serial.deserialize(texto) -> v    o caminho de volta. Só aceita a sintaxe
--                                     que o serializador produz (literais e
--                                     tabelas com chaves entre colchetes); o
--                                     texto é lido caractere a caractere e
--                                     NENHUM código é executado (não usa
--                                     loadstring). Erro se o texto não for um
--                                     valor serializado por este módulo.
--   Serial.sort_keys(a, b)            a ordem das chaves (números antes de
--                                     strings, cada tipo na sua ordem).

local Serial = {}


local function sort_keys(a, b)
  local ta, tb = type(a), type(b)
  if ta ~= tb then return ta < tb end
  return a < b
end

local function write(v, out, seen, path)
  local tv = type(v)
  if tv == "number" then
    if v ~= v or v == math.huge or v == -math.huge then
      error("valor não serializável em " .. path .. ": " .. tostring(v))
    end
    if v % 1 == 0 and math.abs(v) < 2 ^ 53 then
      out[#out + 1] = string.format("%.0f", v)
    else
      out[#out + 1] = string.format("%.17g", v)
    end
  elseif tv == "string" then
    out[#out + 1] = string.format("%q", v)
  elseif tv == "boolean" then
    out[#out + 1] = tostring(v)
  elseif tv == "table" then
    if seen[v] then error("referência cíclica em " .. path) end
    seen[v] = true
    local keys = {}
    for k in pairs(v) do
      local tk = type(k)
      if tk ~= "number" and tk ~= "string" then error("chave não serializável em " .. path .. ": " .. tostring(k)) end
      if tk == "number" and (k ~= k or k % 1 ~= 0) then error("chave não serializável em " .. path .. ": " .. tostring(k)) end
      keys[#keys + 1] = k
    end
    table.sort(keys, sort_keys)
    out[#out + 1] = "{"
    for i, k in ipairs(keys) do
      if i > 1 then out[#out + 1] = "," end
      local key
      if type(k) == "number" then key = string.format("[%.0f]", k) else key = string.format("[%q]", k) end
      out[#out + 1] = key .. "="
      write(v[k], out, seen, path .. key)
    end
    out[#out + 1] = "}"
    seen[v] = nil
  else
    error("valor não serializável em " .. path .. ": " .. tv)
  end
end

function Serial.serialize(v)
  local out = {}
  write(v, out, {}, "log")
  return table.concat(out)
end

-- Lê um valor serializado por Serial.serialize. Só aceita a sintaxe que o
-- serializador produz: literais e construtores de tabela com chaves entre
-- colchetes. Nenhum código é executado.
local function reader(s)
  local pos = 1
  local function fail(msg) error("texto de registro inválido na posição " .. pos .. ": " .. msg, 0) end
  local function peek() return s:sub(pos, pos) end
  local value
  local function read_string()
    -- O formato %q: aspas, escapes com barra e quebras de linha escapadas.
    local out = {}
    pos = pos + 1
    while true do
      local c = s:sub(pos, pos)
      if c == "" then fail("string sem fim") end
      if c == '"' then pos = pos + 1; break end
      if c == "\\" then
        local n = s:sub(pos + 1, pos + 1)
        if n == "\n" then out[#out + 1] = "\n"; pos = pos + 2
        elseif n == "n" then out[#out + 1] = "\n"; pos = pos + 2
        elseif n == "r" then out[#out + 1] = "\r"; pos = pos + 2
        elseif n == "t" then out[#out + 1] = "\t"; pos = pos + 2
        elseif n:match("%d") then
          local digits = s:match("^%d%d?%d?", pos + 1)
          out[#out + 1] = string.char(tonumber(digits))
          pos = pos + 1 + #digits
        else out[#out + 1] = n; pos = pos + 2 end
      else
        out[#out + 1] = c
        pos = pos + 1
      end
    end
    return table.concat(out)
  end
  local function read_key()
    if peek() ~= "[" then fail("esperava chave") end
    pos = pos + 1
    local k
    if peek() == '"' then k = read_string() else
      local num = s:match("^-?%d+", pos)
      if not num then fail("chave inválida") end
      pos = pos + #num
      k = tonumber(num)
    end
    if peek() ~= "]" then fail("esperava ]") end
    pos = pos + 1
    return k
  end
  function value()
    local c = peek()
    if c == "{" then
      pos = pos + 1
      local t = {}
      if peek() == "}" then pos = pos + 1; return t end
      while true do
        local k = read_key()
        if peek() ~= "=" then fail("esperava =") end
        pos = pos + 1
        t[k] = value()
        local d = peek()
        if d == "}" then pos = pos + 1; return t end
        if d ~= "," then fail("esperava , ou }") end
        pos = pos + 1
      end
    elseif c == '"' then
      return read_string()
    elseif s:sub(pos, pos + 3) == "true" then
      pos = pos + 4; return true
    elseif s:sub(pos, pos + 4) == "false" then
      pos = pos + 5; return false
    else
      local num = s:match("^-?%d+%.?%d*[eE]?[-+]?%d*", pos)
      if not num or num == "" then fail("valor inesperado") end
      local n = tonumber(num)
      if n == nil then fail("número inválido") end
      pos = pos + #num
      return n
    end
  end
  return function()
    local v = value()
    if pos <= #s then fail("sobra depois do valor") end
    return v
  end
end

function Serial.deserialize(s)
  assert(type(s) == "string", "esperava um texto")
  return reader(s)()
end

Serial.sort_keys = sort_keys

return Serial
