# DeepMap — AGENTS.md

Este ficheiro contém regras permanentes de desenvolvimento do projeto DeepMap. Estas regras devem ser respeitadas em qualquer tarefa futura, salvo instrução explícita em contrário.

---

# PARTE A — REGRAS TÉCNICAS

## 1. Princípios gerais

- O DeepMap é uma plataforma multi-jogo de mapas, exploração, conteúdo e comunidade.
- Não tratar o projeto como um site específico de Elden Ring.
- Priorizar arquitetura escalável, modular e reutilizável.
- Evitar soluções rápidas que criem dívida técnica ou obriguem a refazer a estrutura mais tarde.
- Antes de alterações estruturais grandes, analisar dependências e impacto real no repositório.
- Não alterar funcionalidades, design ou comportamento fora do âmbito pedido.
- Não “melhorar” coisas por iniciativa própria se isso alterar comportamento, UX, textos, cores, layout ou arquitetura sem necessidade.
- Sempre que possível, preferir evolução incremental e compatível em vez de substituições destrutivas.

## 2. Arquitetura multi-jogo

- `Game` é a entidade principal da plataforma.
- Cada jogo deve poder ser criado e configurado pelo Admin sem ser necessário criar páginas Svelte específicas para esse jogo.
- Evitar qualquer hardcode específico de Elden Ring ou de outro jogo, salvo dados de seed/migração claramente identificados.
- A aplicação deve usar rotas genéricas e dados/configuração por jogo.

Estrutura conceptual:

```text
Game
├── Hub
├── Map
├── Content
├── Playtime
├── Community
└── Settings
```

Notas:
- `Overview` e `Settings` são áreas administrativas, não módulos públicos.
- `Hub`, `Map`, `Content`, `Playtime` e `Community` são módulos independentes e opcionais por jogo.
- Um jogo deve funcionar mesmo com alguns módulos desligados.
- O Hub agrega informação dos outros módulos, mas não é dono técnico desses dados.

## 3. Identidade interna e URLs

- Usar UUID como identidade interna de entidades novas importantes.
- Usar `slug` para URLs e identificação legível.
- Não usar slug como chave primária ou identidade interna definitiva.
- O `slug` pode mudar no futuro sem obrigar a alterar foreign keys.
- Sempre que fizer sentido, separar:
  - `id` = UUID interno e estável;
  - `slug` = URL / identificador legível;
  - `name` = nome de apresentação.

Exemplo:

```text
games
id      UUID
slug    TEXT UNIQUE
name    TEXT
```

## 4. Sistema de módulos por jogo

- Evitar dezenas de colunas booleanas em `games` como `has_forum`, `has_playtime`, `has_map`, etc.
- Preferir um sistema extensível do tipo:

```text
game_modules
game_id
module_key
enabled
position
settings
```

- O sistema deve permitir adicionar novos módulos futuros sem refazer a tabela principal `games`.
- Módulos previstos:
  - `hub`
  - `map`
  - `content`
  - `playtime`
  - `community`
- Outros módulos futuros devem poder ser adicionados de forma compatível.

## 5. Mapas e layers

Estrutura preferida:

```text
Game
└── Game Map
    └── Map Layers
```

- Um jogo pode ter um ou mais `game_maps`.
- Só criar vários `game_maps` quando existirem mapas conceptualmente diferentes.
- Elden Ring deve ter uma única página pública de mapa com layers como:
  - Surface
  - Underground
  - Shadow Realm / DLC
- A troca de layer deve acontecer dentro da mesma página pública do mapa.
- Cada layer deve poder configurar:
  - imagem/tiles;
  - dimensões;
  - bounds/coordenadas;
  - zoom mínimo/máximo;
  - ordem;
  - nome;
  - estado ativo;
  - outras opções específicas da layer.
- Preservar coordenadas canónicas existentes quando se migrar de imagem única para tilemap.
- Não alterar coordenadas de marcadores existentes apenas por mudança de tecnologia de renderização.

## 6. Conteúdo e marcadores

- Entidade de conteúdo e marcador de mapa são conceitos diferentes.
- Um item/localização/conteúdo pode existir sem marcador.
- Uma entidade de conteúdo pode estar associada a um ou vários marcadores.
- URLs de conteúdo devem ser estáveis e não depender da categoria atual.
- Categorias devem ser específicas por jogo quando aplicável.
- Não criar herança global de categorias de mapa entre jogos.
- Manter a separação entre Locations, Collectibles, Items e outras famílias futuras.

## 7. Community

- `Community` é um módulo-pai opcional por jogo.
- O jogo não pode depender da Community para funcionar.
- Submódulos futuros podem incluir:
  - Discussions / Forum;
  - Guides;
  - Posts / Discoveries;
  - Q&A / Help;
  - Community activity.
- Estes submódulos devem depender do jogo, normalmente por `game_id`.
- Não prender comentários tecnicamente ao fórum.
- Comentários/reactions devem ser infraestrutura transversal reutilizável em markers, items, locations, guides, posts, vídeos e outras entidades futuras.
- Perfis, following, notificações, moderação e audit são sistemas globais/transversais, não pertencem a um jogo específico.

## 8. Playtime / Completion Time

- `Playtime` é um módulo opcional por jogo.
- O Hub pode mostrar um resumo, mas os dados pertencem ao módulo Playtime.
- Prever rota futura do tipo `/games/[game]/playtime`.
- Não implementar o sistema de tempos sem pedido explícito.
- A futura lógica deverá suportar categorias como Main Story, Main + Extras e Completionist.
- O sistema deve ser baseado em submissões reais de utilizadores e não apenas em votos.
- Preferir mediana a média simples para agregação.
- Prever mecanismos anti-abuso/outliers.
- Quando não houver dados suficientes, não apresentar estatísticas enganadoras.

## 9. Rotas

- Preferir rotas genéricas baseadas em slug:

```text
/games/[game]
/games/[game]/map
/games/[game]/locations
/games/[game]/collectibles
/games/[game]/items/[slug]
/games/[game]/playtime
/games/[game]/community
```

- Não criar uma nova árvore Svelte específica para cada jogo.
- O código deve resolver o jogo a partir do slug e trabalhar internamente com UUID.
- Páginas públicas devem ser montadas por templates genéricos + dados/configuração.

## 10. Admin, Moderation e Editor

Manter separação clara de responsabilidades.

### Admin global
Responsável por:
- Games;
- Moderation global;
- Users;
- Audit Log;
- configurações globais;
- Reports no futuro.

### Moderation global
Responsável por:
- revisão de submissões;
- aprovação/rejeição;
- histórico;
- navegação entre jogos/mapas;
- ferramentas próprias de moderador.

### Editor por mapa
Responsável apenas por conteúdo/configuração específica daquele mapa:
- markers;
- map labels / zone titles;
- categories;
- icons;
- layers;
- configuração específica do mapa.

Regras:
- Não colocar gestão global de utilizadores no Editor.
- Não colocar moderação global dentro do Editor.
- Não colocar funcionalidades globais num mapa específico.
- Administradores e moderadores devem ter permissões diferentes e explícitas.

## 11. Supabase e migrations

- Toda alteração de schema SQL deve existir também em `supabase/migrations`.
- Não alterar apenas o Supabase remoto sem refletir a mudança no repositório.
- Não apagar migrations antigas apenas por estarem desatualizadas.
- Tratar migrations existentes como histórico do estado real da base de dados.
- Antes de remover ou substituir uma migration, avaliar impacto no Supabase real.
- Alterações destrutivas devem ser evitadas numa primeira fase.
- Em migrações estruturais:
  1. criar estrutura nova;
  2. fazer backfill;
  3. adaptar código;
  4. validar;
  5. só depois remover dependências antigas.
- Manter compatibilidade temporária quando necessário para evitar downtime.
- Não executar migrations de produção automaticamente sem aprovação explícita.
- Não fazer `DROP TABLE`, `DROP COLUMN`, deletes em massa ou alterações irreversíveis sem instrução explícita.
- Não assumir que uma migration pode ser refeita do zero em produção.

## 12. Segurança e RLS

- Toda nova tabela exposta via Supabase deve ter a estratégia de RLS analisada.
- Aplicar princípio de menor privilégio.
- Não confiar apenas no frontend para permissões.
- Validar roles e permissões no servidor/DB quando a ação for sensível.
- Manter distinção entre `user`, `moderator` e `admin`.
- Utilizadores suspensos devem continuar a poder aceder a páginas públicas quando aplicável, mas não podem realizar interações bloqueadas.
- Reutilizar lógica central de autorização quando existente em vez de duplicar regras.
- Rever cuidadosamente funções `SECURITY DEFINER`.
- Evitar policies excessivamente permissivas.
- Nunca colocar secrets em código cliente, commits, logs ou documentação.
- Não expor emails privados publicamente.

## 13. Compatibilidade e migrações de IDs

- Ao migrar identificadores textuais para UUID, não fazer uma troca destrutiva imediata.
- Criar novas referências UUID, fazer backfill, adaptar queries e só depois retirar dependências antigas.
- Validar foreign keys e dados antes de remover a estrutura anterior.
- Não mudar slugs para resolver problemas de identidade interna.
- Não usar nomes visíveis como foreign keys.

## 14. Cloudflare R2 e tilemaps

- A arquitetura atual deve ficar preparada para R2 e tilemaps futuros.
- Não implementar R2 ou tilemaps sem pedido explícito.
- Supabase continua a ser usado para Auth + dados/referências.
- R2 será usado para ficheiros/imagens/tiles quando essa fase chegar.
- Evitar acoplar componentes a URLs físicas permanentes de storage.
- Preferir uma camada/resolver central para URLs de ficheiros.
- Tilemaps futuros devem respeitar as coordenadas atuais dos marcadores.
- Não colocar milhares de tiles em `static/` como solução definitiva.
- O suporte de layers deve ser preparado antes do tilemap.

## 15. Uploads e imagens

Quando a fase de uploads/R2 chegar:
- validar no servidor;
- redimensionar;
- comprimir;
- converter para WebP quando adequado;
- aplicar limites de tamanho;
- evitar ficheiros órfãos;
- usar referências na BD em vez de lógica espalhada por componentes.

Limites de referência atuais:
- avatar: ~500 KB;
- screenshot: ~2 MB;
- imagem de marcador: ~1 MB;
- capa: ~500 KB;
- até 4 imagens por publicação;
- aplicar limite diário de uploads quando existir conteúdo comunitário.

## 16. Código e organização

- Evitar duplicação de lógica entre jogos.
- Extrair lógica genérica para componentes/lib/features quando fizer sentido.
- Não criar abstrações desnecessárias sem benefício real.
- Não criar diretórios vazios apenas para antecipar funcionalidades futuras.
- Não criar ficheiros placeholders sem necessidade.
- Reutilizar componentes existentes quando são adequados.
- Manter responsabilidades claras entre server/client.
- Não mover ficheiros só por preferência estética.
- Não renomear APIs, stores, rotas ou componentes sem necessidade funcional.
- Preservar compatibilidade durante refactors grandes.
- Evitar imports mortos e código duplicado.
- Não adicionar dependências npm sem justificar.

## 17. Remoção e substituição de ficheiros

- Se um ficheiro for removido, indicar sempre o caminho completo.
- Se um ficheiro for substituído, indicar sempre o caminho completo.
- Não apagar ficheiros silenciosamente.
- Não remover assets aparentemente antigos sem confirmar se ainda são referenciados.
- Não remover migrations antigas sem análise explícita.
- Quando uma tarefa alterar muitos ficheiros, apresentar um resumo final dos ficheiros criados, modificados e removidos.

## 18. Testes e validação

Antes de concluir uma alteração relevante:
- executar checks/lint/tests existentes quando disponíveis;
- executar build quando aplicável;
- verificar erros de TypeScript/Svelte;
- confirmar que rotas alteradas compilam;
- verificar imports quebrados;
- testar queries alteradas;
- rever regressões em mobile e desktop;
- não fazer commit automático sem instrução explícita.
- Se um teste não puder ser executado, dizer claramente qual e porquê.

Para alterações de base de dados:
- fornecer queries de verificação quando útil;
- validar contagens e relações após backfill;
- não assumir sucesso apenas porque a migration terminou sem erro.

---

# PARTE B — REGRAS DE DESIGN E UX

## 19. Identidade visual

- Preservar a identidade visual existente do DeepMap.
- Não alterar paleta de cores sem pedido explícito.
- Não alterar tipografia global sem pedido explícito.
- Não alterar estilo de botões, cards, inputs ou headers apenas por preferência pessoal.
- Não fazer redesign geral numa tarefa funcional.
- Não “modernizar” componentes que não fazem parte do pedido.
- Reutilizar padrões visuais existentes para manter consistência.
- O visual deve continuar coerente entre homepage, hubs, mapas, Admin, Moderation e perfis.

## 20. Desktop e mobile

- Toda alteração deve funcionar em desktop e mobile.
- Mobile não é uma versão secundária.
- Não concluir uma alteração de UI sem considerar ecrãs pequenos.
- Evitar larguras fixas que causem overflow.
- Inputs e ações importantes devem ser utilizáveis por toque.
- Scroll deve acontecer no painel correto e de forma natural.
- Evitar barras de scroll estreitas/inutilizáveis em mobile.
- Não bloquear pinch-zoom fora do mapa sem necessidade.
- No mapa, preservar o comportamento de zoom/pinch previsto.
- Não permitir que alterações de sidebar/header quebrem o mapa em mobile.

## 21. Mapa e Editor

- A cor do marcador temporário de escolha de posição deve permanecer azul (`#2f8fff`) salvo pedido explícito.
- O fluxo de escolha de posição deve ser consistente em desktop e mobile.
- Fluxo esperado:
  1. escolher posição;
  2. posicionar;
  3. confirmar ou cancelar;
  4. regressar ao formulário/painel.
- Não mostrar marcador temporário antes de o utilizador iniciar explicitamente a escolha de posição.
- Em mobile, ao escolher posição, minimizar distrações e mostrar apenas o necessário para confirmar/cancelar.
- O avatar/header não deve deixar painéis sobrepostos de edição abertos.
- Com editor aberto em mobile, evitar conflitos com side menu.
- Não introduzir regressões em drag, zoom, pinch ou seleção de markers.

## 22. Popups e galerias

- Popups do mapa nunca devem ficar cortados no topo do ecrã.
- O mapa deve fazer auto-pan quando necessário para manter o popup visível.
- A navegação da galeria deve continuar funcional.
- Não remover setas/controles de galeria sem pedido explícito.
- Popups devem funcionar em mobile e desktop.
- Manter legibilidade de textos e ações dentro dos popups.

## 23. Forms e campos

- Campos obrigatórios devem ter `*`.
- Campos opcionais devem indicar `(opcional)` quando adequado.
- Mostrar erros específicos por campo.
- Evitar mensagens genéricas como `invalid` quando se pode explicar o erro.
- Preservar consistência visual entre forms de user/admin/mod.
- Coordenadas devem usar controlos claros e consistentes.
- Não reintroduzir native spin buttons se o design atual usa controlos personalizados.
- Colocar ações de Confirmar/Cancelar perto do contexto a que pertencem.

## 24. Botões Refresh / Atualizar

Todos os botões de refresh/update devem seguir comportamento consistente:
- mostrar loading;
- ficar temporariamente disabled;
- usar texto equivalente a `A atualizar…`;
- após sucesso, mostrar feedback equivalente a `Atualizado agora ✓`.
- Não criar variações arbitrárias deste padrão entre páginas.

## 25. Paginação e listas

Listas que podem crescer devem usar paginação server-side quando apropriado.

Padrão:
- opções: 10 / 20 / 50;
- default: 10;
- sem persistência em localStorage/profile/DB;
- refresh/navigation volta ao default quando essa é a regra da página;
- evitar carregar listas potencialmente enormes de uma vez.

Exceção conhecida:
- bell de notificações mantém apenas as 20 mais recentes.

## 26. Notificações e Audit

- Notificações são alertas recentes, não histórico permanente.
- Audit Log é histórico permanente.
- Não duplicar conceitos entre ambos sem necessidade.
- Bell deve abrir/fechar de forma previsível.
- Clicar fora deve fechar overlays quando aplicável.
- Estados unread/read devem ser claros.
- Não carregar quantidades ilimitadas de notificações no header.

## 27. Consistência de ações

- Ações destrutivas devem pedir confirmação quando apropriado.
- Botões importantes não devem mudar de posição sem necessidade.
- Em formulários longos, ações devem aparecer no fim natural do conteúdo quando essa é a UX definida.
- Evitar ações sticky se isso conflitar com a experiência existente.
- Labels e termos devem ser consistentes entre páginas.

## 28. Acessibilidade básica

- Garantir contraste suficiente.
- Não depender apenas da cor para comunicar estado.
- Controlos clicáveis devem ter áreas de toque adequadas.
- Manter navegação por teclado quando possível.
- Inputs devem ter labels claros.
- Botões devem indicar estado disabled/loading.
- Não esconder ações essenciais apenas em hover.

## 29. Texto e localização

- Não alterar textos de produto sem pedido explícito.
- Não misturar PT-PT e inglês de forma inconsistente.
- Rótulos técnicos internos podem continuar em inglês quando fizer sentido.
- Textos de UI devem respeitar a linguagem definida para a área.
- Evitar regressões como `Until` em páginas localizadas para PT.
- Quando PT não existir para conteúdo de jogo, usar fallback definido sem quebrar a UI.

## 30. Performance de UI

- Não carregar Leaflet em páginas que não precisam de mapa.
- Não carregar dados pesados antecipadamente sem necessidade.
- Evitar imagens excessivamente grandes.
- Não fazer requests duplicados desnecessários.
- Paginar datasets grandes.
- Preservar boa experiência em mobile e ligações mais lentas.

---

# PARTE C — DISCIPLINA DE ALTERAÇÕES

## 31. Antes de alterar

Antes de uma refatoração estrutural:
- identificar dependências;
- listar tabelas/rotas/componentes afetados;
- identificar hardcodes;
- avaliar impacto em produção;
- propor sequência segura;
- só depois implementar.

## 32. Durante a alteração

- Fazer mudanças por fases pequenas e verificáveis.
- Evitar misturar refactor estrutural com redesign.
- Evitar misturar limpeza de código não relacionada com a feature atual.
- Não aproveitar uma tarefa para mudar áreas não pedidas.
- Se aparecer um problema fora do scope, documentar primeiro.

## 33. Depois da alteração

Apresentar:
- resumo do que mudou;
- ficheiros criados;
- ficheiros modificados;
- ficheiros removidos;
- migrations criadas;
- comandos/testes executados;
- problemas ou limitações encontrados;
- passos manuais ainda necessários.

## 34. Regra de segurança para produção

- Não executar alterações destrutivas em produção sem aprovação explícita.
- Não aplicar migrations remotas automaticamente sem aprovação.
- Não fazer push para `main` sem instrução explícita.
- Não fazer deploy de produção sem instrução explícita.
- Não alterar secrets/env vars sem instrução explícita.
- Não apagar dados reais para “limpar” testes sem autorização.

## 35. Filosofia final

Quando houver dúvida entre:
- uma solução rápida específica de um jogo; e
- uma solução ligeiramente mais estruturada que funciona para vários jogos,

preferir a segunda, desde que não crie complexidade artificial.

O objetivo é permitir que o DeepMap cresça para novos jogos, novos módulos, R2, tilemaps, conteúdos, comunidade e funcionalidades futuras sem obrigar a reconstruir a fundação de cada vez.

---

## 36. Codex handoff / relatório para revisão

- Em tarefas relevantes de análise, refatoração, implementação, migrations ou infraestrutura, manter um ficheiro temporário de handoff na raiz do repositório:

```text
codex-handoff.md
```

- Este ficheiro serve apenas para comunicação e revisão entre Codex, utilizador e ChatGPT.
- `codex-handoff.md` não faz parte do produto DeepMap e não deve ser commitado.
- Garantir que `codex-handoff.md` está incluído no `.gitignore`.
- Substituir o conteúdo anterior do ficheiro em cada nova tarefa relevante, em vez de acumular relatórios antigos.
- No fim de cada tarefa relevante, o handoff deve incluir, quando aplicável:
  - objetivo da tarefa;
  - o que foi analisado;
  - o que foi alterado;
  - ficheiros criados;
  - ficheiros modificados;
  - ficheiros removidos;
  - migrations/SQL criados ou alterados;
  - comandos/testes executados;
  - resultados dos testes/build/checks;
  - riscos ou problemas encontrados;
  - decisões ainda pendentes;
  - passos manuais necessários;
  - próximos passos recomendados.
- O handoff não substitui `git diff`, testes nem revisão humana.
- Não colocar secrets, tokens, passwords, connection strings privadas ou outros dados sensíveis no handoff.
- Não fazer commit, push, deploy ou aplicar migrations remotas apenas por ter concluído o handoff.
- Para tarefas pequenas e triviais, o handoff pode ser omitido se não trouxer valor.
- Ficheiros temporários anteriores, como `codex-audit.md`, podem ser apagados depois de o conteúdo ser revisto/copied, desde que não sejam necessários como registo.

