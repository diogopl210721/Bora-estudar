# EstudeUp

**Seu próximo nível começa aqui.** Antes Estude+ e, antes ainda, **Bora Estudar**: o aluno manda o material (foto, PDF, texto, YouTube ou site) e o app devolve resumo, mapa mental, quiz, prova e flashcards — e monta um **plano de estudo dia a dia até a data da prova**. Tem revisão espaçada, liga semanal, simulado do ENEM com questões oficiais, correção de redação nas 5 competências e painel do professor.

Por cima disso, o que um app de estudo social tem: **biblioteca de resumos** feita pelos alunos (busca, curtidas, salvos, seguir), **tutor de IA** que resolve exercício pela foto, **voz** (responder flashcard falando, ditar pro tutor, ouvir resumos) e **comunidade** com salas por matéria e a sala de cada turma.

- Site: `site/` (HTML + JS puro, no GitHub Pages; hoje em `ddsinovacao.com.br/estudemais`, indo para `www.estudeup.com.br`)
- Escolas parceiras: página de cada escola, mural de oportunidades, painel da escola e área comercial (veja **Escolas parceiras**)
- Banco: Supabase do projeto compartilhado (`arffptuclrrzuzdrcmuc`), tabelas com prefixo `be_` — as mesmas contas do Bora Estudar continuam valendo
- IA: Edge Functions com a mesma `ANTHROPIC_API_KEY` que o Bora Estudar já usa

## O que tem

| Recurso | Onde mora a regra |
| --- | --- |
| Plano de prova (distribui os tópicos até a véspera, mais fracos primeiro, prova simulada no fim; ao remontar, as tarefas antigas ficam marcadas como substituídas, nada é apagado) | `be_gerar_plano` |
| Tarefas do dia, marcar feita, mover de dia, tarefa manual | `be_resumo_hoje`, `be_marcar_tarefa`, tabela `be_plano_tarefas` |
| Flashcards com repetição espaçada FSRS-4.5 (retenção alvo 90%) | `be_revisar_card`, `be_cards_para_revisar` |
| Domínio por tópico (sobe a cada acerto) | `be_responder_pergunta` → `be_dominio` |
| XP, nível, sequência e liga semanal (30 pessoas, sobem 5, caem 5) | `be_ganhar_xp`, `be_minha_liga`, `be_fechar_ligas` (pg_cron toda segunda 00:05) |
| Simulado ENEM 2009–2023 (2.750 questões oficiais) | `be_iniciar_simulado`, `be_finalizar_simulado` |
| Correção de redação nas 5 competências | Edge Function `estude-corrigir-redacao` |
| Gerar material a partir do upload (tópicos, cards, quiz, prova, plano) | Edge Function `estude-gerar-conteudo` |
| Painel da turma (onde a turma está fraca, quem sumiu) | `be_painel_turma` |
| Turma do professor × grupo de amigos: na turma só o professor põe material (matéria, material, flashcard, data da prova); no grupo de amigos qualquer membro põe | `be_pode_editar_grupo` nas regras de acesso + checagem na `estude-gerar-conteudo` |
| Biblioteca: feed (em alta, novos, seguindo, salvos, meus), busca em português, perfil público | `be_feed_resumos`, `be_resumo_abrir`, `be_perfil_publico` |
| Publicar resumo (filtro de contato + moderação por IA antes de aparecer; 25 XP, +2 XP por curtida) | Edge Function `estude-publicar-resumo`, gatilho `be_curtida_xp` |
| Tutor de IA com foto, uma conversa por dúvida (60 perguntas/dia, 3 XP até 5 vezes por dia) | Edge Function `estude-tutor` |
| Responder flashcard falando (a IA confere pelo sentido e sugere a nota) | Edge Function `estude-conferir-resposta` + `site/voz.js` |
| Salas da comunidade e da turma, não lidas, denúncia e bloqueio | `be_salas_lista`, `be_mensagens_sala`, `be_enviar_mensagem`, `be_denunciar`, `be_bloquear` |
| Conta do criador (master): sem limite de IA, tutor, publicação e ritmo de mensagem; escolhe turma ou grupo ao criar; painel com números do app e fila de denúncias; liberar, esconder e silenciar por uns dias; selo "equipe EstudeUp" | tabela `be_criadores`, `be_painel_criador`, `be_moderar`, `be_silenciar`, `site/criador.js` |

Toda regra que dá XP ou confere resposta roda no banco (`security definer` + checagem de dono). O navegador nunca recebe o gabarito antes de responder.
As funções internas (dar XP, conquista, liga, domínio, uso de IA, importação) chamam `be_exigir_interno()`: pelo app (papel `authenticator`) só funcionam dentro de uma rpc do próprio EstudeUp ou com a service role. O teste `teste/seguranca.mjs` confere isso.
XP, nível, sequência, liga e papel (aluno/professor) não mudam direto pela tabela `be_usuarios`: o gatilho `be_usuarios_protege` desfaz qualquer mudança nesses campos que venha do app.

## Conta do criador

Quem está na tabela `be_criadores` é a conta master. A tabela não tem acesso pelo app (nem pra ler), então ninguém se promove sozinho. Pra dar ou conferir no SQL Editor:
```sql
insert into be_criadores (usuario_id)
select u.id from be_usuarios u join auth.users a on a.id = u.auth_user_id where lower(a.email) = 'email@da.conta'
on conflict do nothing;
select u.nome from be_criadores c join be_usuarios u on u.id = c.usuario_id;
```
Pra tirar, apague a linha dessa conta em `be_criadores`.
No app, a conta master vê o **Painel do criador** (Perfil ou barra lateral): pessoas, uso do dia e conteúdo; a fila do que foi denunciado (abrir, liberar, manter escondido, silenciar o autor por 7 dias); a busca de contas pelo nome ou e-mail, com **senha provisória** pra quem esqueceu (Edge Function `estude-criador-senha`; a senha antiga para na hora e a pessoa troca depois em Perfil); e quem está silenciado. Nas salas, tocar numa mensagem dá "esconder pra todo mundo" e "silenciar"; num resumo, aparece a barra de moderação. Nada é apagado: esconder só tira de vista.
Mesmo pra conta master, as conversas com o tutor e as matérias de cada aluno continuam privadas.

## Escolas parceiras

| O quê | Onde |
| --- | --- |
| Página pública da escola (`escola.html?e=<endereço>`), mural (`oportunidades.html`), "Para escolas" com formulário (`escolas.html`), aviso de privacidade (`privacidade.html`). Abrem sem login | `site/publico.js`, `site/vitrine.js`, geradas por `scripts/paginas_publicas.py` |
| No app: cartão no Hoje, tela Oportunidades, página da escola, **Minha escola** (visão geral com números, página, oportunidades, turmas, professores, plano) | `site/escolas.js` |
| Cadastro da escola (fica esperando aprovação), professor entra com o código da escola, turma criada já ligada à escola | `be_escola_solicitar`, `be_escola_entrar_professor`, regra restritiva em `be_grupos` |
| Oportunidade: rascunho → esperando aprovação → no ar → pausada/encerrada; mexeu numa publicada, volta pra fila; bolsa e desconto exigem regras; limite por plano | `be_oportunidade_salvar`, `be_oportunidade_acao` |
| Números da vitrine: cada pessoa conta 1 vez por dia por item, a equipe da própria escola não conta, sem dado pessoal | `be_registrar_evento`, `be_escola_metricas_json` |
| Área comercial (conta do criador): resumo, escolas (aprovar, recusar, suspender, desativar, contrato, gestor, endereço, demonstração, observação, histórico), mural (publicar, recusar e suspender com motivo), contatos, planos editáveis, histórico e configuração | `be_admin_*`, tela no Painel do criador |
| Planos de referência (Presença, Destaque, Premium) e contrato registrado à mão: interessado, em negociação, ativo, pendente, cancelado; pagamento só como anotação, sem cobrança pelo app | `be_planos`, `be_assinaturas` |
| Imagens da escola (logo, capa, oportunidades) na pasta pública `estude-escolas`, só o gestor envia e só na pasta da própria escola | `be_pode_enviar_imagem_escola` + regra da pasta |

Todas as tabelas novas ficam fechadas pro app (sem regra de leitura); tudo passa pelas funções, que conferem quem pede. Os ajudantes internos (por exemplo, `be_escola_metricas_json`) não podem ser chamados pelo app.
A escola de demonstração (Colégio Monte Aurora, fictícia, `demo = true`) fica marcada em todo lugar, aparece por último no mural e não entra nos números do criador nem da área comercial. Contas de demonstração (domínio reservado `example.com`): `coordenacao`, `helena`, `ricardo`, `camila` e `laura` `.monteaurora@example.com`. Scripts: `supabase/demo/` (parte 1: escola, pessoas, turmas e mural; parte 2: progresso e conversa nas salas, depois de gerar o conteúdo das matérias) e as imagens em `site/demo/monte-aurora/` (`scripts/demo_monte_aurora.py`).
Pra tirar a demonstração do ar sem apagar nada: Área comercial → Escolas → desativar.

## Proteção dos alunos (muitos são menores de idade)

- Em público só aparece primeiro nome + inicial do sobrenome ("Ana S.") e as iniciais, nunca a foto.
- Não existe mensagem privada entre alunos; as salas de turma só são vistas por quem é da turma.
- Mensagens e resumos não aceitam link, e-mail, @ de rede social nem telefone (datas e contas passam). Envio de mensagem limitado (3 s entre mensagens, 12 por minuto).
- Resumo só aparece depois da moderação por IA; 3 denúncias de pessoas diferentes escondem o resumo ou a mensagem até a conta do criador revisar.
- A conta do criador pode silenciar alguém por uns dias: a pessoa continua estudando, mas não manda mensagem nem publica resumo.
- Bloquear alguém esconde as mensagens e os resumos dessa pessoa pra quem bloqueou.
- O tutor tem instrução de não pedir dados pessoais e de acolher e indicar o CVV (188) se o aluno contar que está sofrendo.
- Nada de propaganda dentro do tutor nem anúncio direcionado pelo comportamento do aluno. As oportunidades das escolas ficam num espaço próprio, marcadas como de instituição parceira, e só entram depois da aprovação.
- A escola não recebe dado de quem vê a página: o botão de contato só abre o WhatsApp, o site ou o e-mail da escola. No painel da escola só aparecem números da turma inteira.

## Visual

Marca **EstudeUp**: símbolo do S de livros (degradê ciano → azul → roxo → magenta), em `site/marca/`, nos ícones do app (`icon-192.png`, `icon-512.png`, `apple-touch-icon.png`, `favicon.png`) e no cabeçalho; "Up" no degradê do símbolo. O recorte do símbolo sai do arquivo original com `scripts/marca_extrair_simbolo.py`.
Visual "estojo": azul de caneta (#1F4BFF), marca-texto amarelo (#FFE34D), post-it rosa (#FF5C9D) e verde de acerto, sobre fundo frio quase branco; modo escuro em azul-noite (Perfil → Aparência, ou igual ao aparelho).
O que marca o app são as figurinhas 3D com contorno branco (atalhos, fontes do material, vazios, geração, conquistas), que "descolam" quando tocadas.
Fontes no próprio site (`site/fontes/`, licença OFL): Unbounded nos títulos e números, Atkinson Hyperlegible Next no texto.
Ícones: Phosphor Icons (MIT); figurinhas: Fluent Emoji 3D da Microsoft (MIT), já com contorno, em `site/adesivos/` (licenças junto).
Movimento que responde ao toque: troca de tela com direção (entrar desliza da direita, voltar da esquerda), gota que desliza na barra de baixo, botões que afundam, visto que pula ao marcar tarefa, esqueleto com brilho enquanto carrega.
Upload: a foto vira polaroide com visto; na geração a foto é escaneada pela faixa de marca-texto, com porcentagem e as 5 etapas ganhando visto.
Com "reduzir movimento" ligado no aparelho saem deslocamentos, giros e confete, e ficam fades, cores e barras de progresso.

## Como subir (ordem)

1. **Banco** — rodar no SQL Editor, nessa ordem: `supabase/01_estude_schema.sql`, `supabase/02_estude_funcoes.sql`, `supabase/03_enem_importacao.sql`, `supabase/04_estude_social.sql`, `supabase/05_estude_social_funcoes.sql`, `supabase/06_estude_cadastro.sql`, `supabase/07_estude_plano_substituidas.sql`, `supabase/08_estude_grupos_permissoes.sql`, `supabase/09_estude_criador.sql`, `supabase/10_estude_criador_contas.sql`, `supabase/11_estude_escolas.sql`, `supabase/12_estude_escolas_imagens.sql`, `supabase/13_estude_vitrine_demo_por_ultimo.sql`, `supabase/14_estude_marca_estudeup.sql`. Tudo é aditivo (só cria ou substitui) e pode rodar de novo sem quebrar.
   A 11 só acrescenta; as duas funções que ela substitui têm a versão anterior em `supabase/reverter/11_reverter.sql` (que só deve rodar com aprovação, depois de exportar os dados novos).
   O texto colado fica em `be_materiais` como `tipo = 'link'` sem `url_externa` (a tabela original não aceita `texto`).
2. **Funções** — publicar `supabase/functions/estude-gerar-conteudo`, `estude-corrigir-redacao`, `estude-tutor`, `estude-publicar-resumo`, `estude-conferir-resposta`, `estude-criador-senha` (todas com verificação de JWT), `estude-cadastro` (sem verificação de JWT: é ela que cria a conta) e `estude-importar-enem` (sem verificação de JWT; ela exige a chave descartável).
   Opcional: secret `GEMINI_API_KEY` (e `GEMINI_MODELO`, padrão `gemini-2.5-flash`) pra ler vídeo do YouTube pelo link: o YouTube bloqueia os servidores do Supabase, então sem essa chave o aluno cola a transcrição do vídeo (YouTube → descrição → "Mostrar transcrição").
   Opcional: secrets `ESTUDE_MODELO` (padrão `claude-sonnet-5-5`, usado no material e no tutor) e `ESTUDE_MODELO_RAPIDO` (padrão `claude-haiku-5-5`, usado na moderação e na conferência por voz).
3. **Questões do ENEM** — no SQL Editor:
   ```sql
   insert into be_import_chave (chave) values (gen_random_uuid()::text) returning chave;
   -- para cada ano de 2009 a 2023:
   select net.http_post(
     url := 'https://arffptuclrrzuzdrcmuc.supabase.co/functions/v1/estude-importar-enem',
     body := jsonb_build_object('ano', 2023, 'chave', '<chave>'),
     headers := '{"Content-Type":"application/json"}'::jsonb,
     timeout_milliseconds := 120000);
   -- conferir: select ano, count(*) from be_enem_questoes group by ano order by ano;  (≈ 180 por ano, 2.750 no total)
   -- a chave só vale por 2 horas; depois disso a função recusa sozinha.
   ```
   Alternativa offline: `python3 scripts/montar_enem.py <clone do enem-api> <commit> <saida>` gera lotes SQL.
4. **Site** — copiar `site/` para a pasta `estudemais/` do repositório do domínio (ou para a raiz do repositório do `www.estudeup.com.br`, com o arquivo `CNAME`).
5. **Login** — só e-mail e senha. O cadastro pede o e-mail e a senha 2 vezes e a função `estude-cadastro` cria a conta já confirmada, sem e-mail de confirmação (no máximo 5 contas novas por hora do mesmo endereço). Não precisa mexer na configuração de Auth do projeto, que é compartilhado com outros apps. Esqueceu a senha: as contas antigas, que têm pergunta de segurança, trocam sozinhas (função `resetar-senha-segura` do Bora Estudar); as contas novas pedem pra equipe, e a conta do criador gera uma senha provisória no painel.

## Testes

`teste/rodar.sh` sobe um Postgres local com o espelho das tabelas do Bora Estudar + as migrações, um servidor que imita o Supabase (com RLS de verdade) e IA simulada, e passa o app inteiro no Chromium: cadastro, matéria com IA, quiz, plano, flashcards (com resposta conferida pela IA), simulado, redação, liga, turma do professor, publicar e moderar resumo, biblioteca (busca, curtir, salvar, seguir, perfil), tutor com texto e foto, salas (filtro de telefone, denúncia), desktop e modo escuro.
`teste/seguranca.mjs` confere as funções internas e as regras da parte social (não publicar sem moderação, não mexer no resumo dos outros, não escrever direto na sala, quem é de fora não vê a turma, bloqueio) e da conta do criador (ninguém se promove, só o criador modera e silencia, XP e papel não mudam pela tabela).
`teste/permissoes_escolas.sql` confere as regras das escolas no banco (anônimo, gestor, professor, quem é de fora, criador) e `teste/escolas_e2e.py` passa pelas telas com a escola de demonstração (`teste/carregar_demo.sh`): páginas públicas e formulário, aluna, professor, gestor (oportunidade com regra obrigatória, logo, outra escola bloqueada) e criador (aprovar, contatos).
O e2e também passa pela conta do criador: sem limite com o uso do dia estourado, painel, liberar resumo, silenciar, esconder mensagem, link na sala, turma criada e senha provisória (a aluna entra com ela e troca em Perfil).

Questões do ENEM: provas oficiais do INEP organizadas pelo projeto aberto [enem.dev](https://enem.dev) (yunger7/enem-api).
