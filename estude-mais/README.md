# Estude+

Evolução do **Bora Estudar**: o aluno manda o material (foto, PDF, texto, YouTube ou site) e o app devolve resumo, mapa mental, quiz, prova e flashcards — e monta um **plano de estudo dia a dia até a data da prova**. Tem revisão espaçada, liga semanal, simulado do ENEM com questões oficiais, correção de redação nas 5 competências e painel do professor.

Por cima disso, o que um app de estudo social tem: **biblioteca de resumos** feita pelos alunos (busca, curtidas, salvos, seguir), **tutor de IA** que resolve exercício pela foto, **voz** (responder flashcard falando, ditar pro tutor, ouvir resumos) e **comunidade** com salas por matéria e a sala de cada turma.

- Site: `site/` (HTML + JS puro, publicado no GitHub Pages em `ddsinovacao.com.br/estudemais`)
- Banco: Supabase do projeto compartilhado (`arffptuclrrzuzdrcmuc`), tabelas com prefixo `be_` — as mesmas contas do Bora Estudar continuam valendo
- IA: Edge Functions com a mesma `ANTHROPIC_API_KEY` que o Bora Estudar já usa

## O que tem

| Recurso | Onde mora a regra |
| --- | --- |
| Plano de prova (distribui os tópicos até a véspera, mais fracos primeiro, prova simulada no fim) | `be_gerar_plano` |
| Tarefas do dia, marcar feita, mover de dia, tarefa manual | `be_resumo_hoje`, `be_marcar_tarefa`, tabela `be_plano_tarefas` |
| Flashcards com repetição espaçada FSRS-4.5 (retenção alvo 90%) | `be_revisar_card`, `be_cards_para_revisar` |
| Domínio por tópico (sobe a cada acerto) | `be_responder_pergunta` → `be_dominio` |
| XP, nível, sequência e liga semanal (30 pessoas, sobem 5, caem 5) | `be_ganhar_xp`, `be_minha_liga`, `be_fechar_ligas` (pg_cron toda segunda 00:05) |
| Simulado ENEM 2009–2023 (2.750 questões oficiais) | `be_iniciar_simulado`, `be_finalizar_simulado` |
| Correção de redação nas 5 competências | Edge Function `estude-corrigir-redacao` |
| Gerar material a partir do upload (tópicos, cards, quiz, prova, plano) | Edge Function `estude-gerar-conteudo` |
| Painel da turma (onde a turma está fraca, quem sumiu) | `be_painel_turma` |
| Biblioteca: feed (em alta, novos, seguindo, salvos, meus), busca em português, perfil público | `be_feed_resumos`, `be_resumo_abrir`, `be_perfil_publico` |
| Publicar resumo (filtro de contato + moderação por IA antes de aparecer; 25 XP, +2 XP por curtida) | Edge Function `estude-publicar-resumo`, gatilho `be_curtida_xp` |
| Tutor de IA com foto, uma conversa por dúvida (60 perguntas/dia, 3 XP até 5 vezes por dia) | Edge Function `estude-tutor` |
| Responder flashcard falando (a IA confere pelo sentido e sugere a nota) | Edge Function `estude-conferir-resposta` + `site/voz.js` |
| Salas da comunidade e da turma, não lidas, denúncia e bloqueio | `be_salas_lista`, `be_mensagens_sala`, `be_enviar_mensagem`, `be_denunciar`, `be_bloquear` |

Toda regra que dá XP ou confere resposta roda no banco (`security definer` + checagem de dono). O navegador nunca recebe o gabarito antes de responder.
As funções internas (dar XP, conquista, liga, domínio, uso de IA, importação) chamam `be_exigir_interno()`: pelo app (papel `authenticator`) só funcionam dentro de uma rpc do próprio Estude+ ou com a service role. O teste `teste/seguranca.mjs` confere isso.

## Proteção dos alunos (muitos são menores de idade)

- Em público só aparece primeiro nome + inicial do sobrenome ("Ana S.") e as iniciais, nunca a foto.
- Não existe mensagem privada entre alunos; as salas de turma só são vistas por quem é da turma.
- Mensagens e resumos não aceitam link, e-mail, @ de rede social nem telefone (datas e contas passam). Envio de mensagem limitado (3 s entre mensagens, 12 por minuto).
- Resumo só aparece depois da moderação por IA; 3 denúncias de pessoas diferentes escondem o resumo ou a mensagem.
- Bloquear alguém esconde as mensagens e os resumos dessa pessoa pra quem bloqueou.
- O tutor tem instrução de não pedir dados pessoais e de acolher e indicar o CVV (188) se o aluno contar que está sofrendo.

## Visual

Visual limpo de app: fundo claro, cartões arredondados, azul como cor principal e capas coloridas na biblioteca; modo escuro pelo Perfil → Aparência (ou igual ao aparelho).
Navegação de baixo com Hoje, Matérias, Tutor (no centro), Biblioteca e Comunidade; no computador vira barra lateral.
Fontes no próprio site (`site/fontes/`, licença OFL): Shantell Sans nos destaques e Atkinson Hyperlegible Next no texto.
Efeitos em `site/efeitos.js` (confete, XP voando, subir de nível, carimbo de dia completo, flashcard que vira). Quem ativa "reduzir movimento" no aparelho vê tudo sem animação.

## Como subir (ordem)

1. **Banco** — rodar no SQL Editor, nessa ordem: `supabase/01_estude_schema.sql`, `supabase/02_estude_funcoes.sql`, `supabase/03_enem_importacao.sql`, `supabase/04_estude_social.sql`, `supabase/05_estude_social_funcoes.sql`, `supabase/06_estude_cadastro.sql`. Tudo é aditivo (só cria ou substitui) e pode rodar de novo sem quebrar.
   O texto colado fica em `be_materiais` como `tipo = 'link'` sem `url_externa` (a tabela original não aceita `texto`).
2. **Funções** — publicar `supabase/functions/estude-gerar-conteudo`, `estude-corrigir-redacao`, `estude-tutor`, `estude-publicar-resumo`, `estude-conferir-resposta` (todas com verificação de JWT), `estude-cadastro` (sem verificação de JWT: é ela que cria a conta) e `estude-importar-enem` (sem verificação de JWT; ela exige a chave descartável).
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
4. **Site** — copiar `site/` para a pasta `estudemais/` do repositório do domínio.
5. **Login** — só e-mail e senha. O cadastro pede a senha 2 vezes e a função `estude-cadastro` cria a conta já confirmada, sem e-mail de confirmação (no máximo 5 contas novas por hora do mesmo endereço). Não precisa mexer na configuração de Auth do projeto, que é compartilhado com outros apps. Esqueceu a senha: pergunta de segurança, pela função `resetar-senha-segura` do Bora Estudar.

## Testes

`teste/rodar.sh` sobe um Postgres local com o espelho das tabelas do Bora Estudar + as migrações, um servidor que imita o Supabase (com RLS de verdade) e IA simulada, e passa o app inteiro no Chromium: cadastro, matéria com IA, quiz, plano, flashcards (com resposta conferida pela IA), simulado, redação, liga, turma do professor, publicar e moderar resumo, biblioteca (busca, curtir, salvar, seguir, perfil), tutor com texto e foto, salas (filtro de telefone, denúncia), desktop e modo escuro.
`teste/seguranca.mjs` confere as funções internas e as regras da parte social (não publicar sem moderação, não mexer no resumo dos outros, não escrever direto na sala, quem é de fora não vê a turma, bloqueio).

Questões do ENEM: provas oficiais do INEP organizadas pelo projeto aberto [enem.dev](https://enem.dev) (yunger7/enem-api).
