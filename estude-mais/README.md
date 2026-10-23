# Estude+

Evolução do **Bora Estudar**: o aluno manda o material (foto, PDF, texto, YouTube ou site) e o app devolve resumo, mapa mental, quiz, prova e flashcards — e monta um **plano de estudo dia a dia até a data da prova**. Tem revisão espaçada, liga semanal, simulado do ENEM com questões oficiais, correção de redação nas 5 competências e painel do professor.

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

Toda regra que dá XP ou confere resposta roda no banco (`security definer` + checagem de dono). O navegador nunca recebe o gabarito antes de responder.

## Como subir (ordem)

1. **Banco** — rodar no SQL Editor, nessa ordem: `supabase/01_estude_schema.sql`, `supabase/02_estude_funcoes.sql`, `supabase/03_enem_importacao.sql`. Tudo é aditivo e pode rodar de novo sem quebrar.
2. **Funções** — publicar `supabase/functions/estude-gerar-conteudo`, `estude-corrigir-redacao` (com verificação de JWT) e `estude-importar-enem` (sem verificação de JWT; ela exige a chave descartável).
   Opcional: secret `ESTUDE_MODELO` para trocar o modelo (padrão `claude-sonnet-5-5`).
3. **Questões do ENEM** — no SQL Editor:
   ```sql
   insert into be_import_chave (chave) values (gen_random_uuid()::text) returning chave;
   -- para cada ano de 2009 a 2023:
   select net.http_post(
     url := 'https://arffptuclrrzuzdrcmuc.supabase.co/functions/v1/estude-importar-enem',
     body := jsonb_build_object('ano', 2023, 'chave', '<chave>'),
     headers := '{"Content-Type":"application/json"}'::jsonb,
     timeout_milliseconds := 120000);
   -- conferir: select ano, count(*) from be_enem_questoes group by ano order by ano;  (≈ 180 por ano)
   delete from be_import_chave;
   ```
   Alternativa offline: `python3 scripts/montar_enem.py <clone do enem-api> <commit> <saida>` gera lotes SQL.
4. **Site** — copiar `site/` para a pasta `estudemais/` do repositório do domínio.
5. **Login com Google e link de senha** — em Authentication → URL Configuration, incluir `https://www.ddsinovacao.com.br/estudemais/` nas Redirect URLs.

## Testes

`teste/rodar.sh` sobe um Postgres local com o espelho das tabelas do Bora Estudar + as migrações, um servidor que imita o Supabase (com RLS de verdade) e IA simulada, e passa o app inteiro no Chromium: cadastro, matéria com IA, quiz, plano, flashcards, simulado, redação, liga, turma do professor e desktop.

Questões do ENEM: provas oficiais do INEP organizadas pelo projeto aberto [enem.dev](https://enem.dev) (yunger7/enem-api).
