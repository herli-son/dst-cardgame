-- Pilha de resolução e os três tipos de efeito. Lua 5.1 puro.
-- Instala os métodos no Game: require("duelo/core/pilha")(Game)
--
-- Tipos (campo speed dos feitiços e de activation nos efeitos ativados):
--   "instantaneo"  resolve na hora; não gasta a vez; pode ser usado com a pilha aberta
--   "rapido"       abre a pilha ou entra nela; pode ser usado com a pilha aberta
--   "lento"        só abre a pilha (no máximo 1 por pilha, sempre o primeiro)
--
-- Regras da pilha:
--   * Quem põe algo na pilha continua com a vez para pôr mais (Rápidos e Instantâneos).
--   * "pass" com a pilha aberta: se o jogador pôs algo nesta janela, é "pronto" e a
--     vez vai para o outro; se não pôs nada, a pilha resolve, do último ao primeiro.
--   * Ao resolver, a vez é de quem não abriu a pilha. A vez de quem abriu conta uma
--     vez só para o período, quando a pilha fecha; as respostas não contam.
--   * Passar com a pilha aberta não conta para encerrar a rodada.

return function(Game)
  Game.SPEEDS = { instantaneo = true, rapido = true, lento = true }

  function Game:stack_open()
    return self.stack ~= nil and #self.stack > 0
  end

  -- Diz se um efeito desse tipo pode ser usado agora.
  function Game:can_use_speed(speed)
    if not Game.SPEEDS[speed] then return false, "tipo de efeito inválido: " .. tostring(speed) end
    if speed == "lento" and self:stack_open() then
      return false, "Lento só pode abrir a pilha"
    end
    return true
  end

  -- entry = { owner, label, resolve = function(g) }
  function Game:push_stack(p, entry)
    self.stack = self.stack or {}
    if #self.stack == 0 then self.stack_opener = p end
    entry.owner = p
    self.stack[#self.stack + 1] = entry
    self.stack_added = true
    self:emit{ t = "stack_push", p = p, label = entry.label, size = #self.stack }
  end

  -- Usa um efeito de acordo com o tipo. Retorna o terceiro valor das ações
  -- (passes_turn): sempre false, porque nenhum tipo passa a vez na hora.
  function Game:use_speed(p, speed, label, resolve)
    if speed == "instantaneo" then
      self:emit{ t = "instant", p = p, label = label }
      resolve(self)
    else
      self:push_stack(p, { label = label, resolve = resolve })
    end
    return false
  end

  -- "Pronto": a vez vai para o outro sem contar para o período.
  function Game:hand_over()
    -- Conta as passagens de vez dentro da pilha (o combate usa para saber qual é a
    -- primeira resposta do defensor).
    self.handover_count = (self.handover_count or 0) + 1
    self.stack_added = false
    self.active = Game.other(self.active)
    self:emit{ t = "ready", active = self.active, size = #self.stack }
  end

  -- Resolve do topo para baixo. Para se um efeito abrir uma escolha; a ação
  -- "choose" retoma a resolução.
  function Game:resolve_stack()
    self.resolving = true
    while #self.stack > 0 do
      if self.winner ~= nil then break end
      local entry = table.remove(self.stack)
      self:emit{ t = "stack_resolve", p = entry.owner, label = entry.label }
      entry.resolve(self)
      self:settle()
      if self:choices_waiting() then return end
    end
    self:close_stack()
  end

  function Game:close_stack()
    local opener = self.stack_opener
    self.stack = {}
    self.stack_opener = nil
    self.stack_added = false
    self.resolving = false
    self.passes = 0
    -- Um combate que não chegou a resolver (partida vencida no meio da pilha) acaba aqui.
    self.combat = nil
    self:emit{ t = "stack_closed" }
    if self.winner ~= nil then return end
    -- A vez de quem abriu conta agora e passa para quem não abriu.
    if opener == nil then return end
    self.active = opener
    self:advance_vez()
  end

  -- Chamado pelo act() quando o jogador passa com a pilha aberta.
  function Game:stack_pass(p)
    self:emit{ t = "pass", p = p, stack = true }
    if self.stack_added then
      self:hand_over()
    else
      self:resolve_stack()
    end
  end
end
