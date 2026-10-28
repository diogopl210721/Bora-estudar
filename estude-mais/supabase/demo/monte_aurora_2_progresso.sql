-- =====================================================================================
-- EstudeUp · Colégio Monte Aurora (FICTÍCIO) — parte 2: progresso dos alunos e conversa nas salas das turmas
-- Rodar depois que as 3 matérias da demonstração tiverem conteúdo (tópicos) gerado pela função estude-gerar-conteudo.
-- Só mexe em alunos da escola de demonstração. Não apaga nada: o progresso só é criado uma vez (se já existe, pula)
-- e as mensagens só entram em sala vazia. Pode rodar de novo sem duplicar.
-- A Laura (conta de login) ganha domínio, XP e sequência; o plano dela o próprio app monta quando ela entrar.
-- =====================================================================================
do $$
declare
  v_inst uuid; v_hoje date := be_hoje(); r record; t record; v_hab numeric; v_dias int; v_xp int; v_streak int; v_n int; v_s uuid;
begin
  select id into v_inst from be_instituicoes where slug = 'colegio-monte-aurora' and demo;
  if v_inst is null then raise exception 'rode antes a parte 1 (escola de demonstração)'; end if;
  if exists (select 1 from be_materias m join be_grupos g on g.id = m.grupo_id
             where g.instituicao_id = v_inst and not exists (select 1 from be_topicos tp where tp.materia_id = m.id)) then
    raise exception 'ainda tem matéria da demonstração sem conteúdo gerado';
  end if;

  for r in select u.id, u.nome, u.auth_user_id from be_usuarios u where u.instituicao_id = v_inst and u.papel = 'aluno'
             and not exists (select 1 from be_dominio d where d.usuario_id = u.id)
             and not exists (select 1 from be_xp_eventos x where x.usuario_id = u.id) loop
    -- "jeito" de cada aluno, fixo pelo nome: quanto domina e há quantos dias estudou
    v_hab := 0.35 + (abs(hashtext(r.nome)) % 55) / 100.0;
    v_dias := case r.nome when 'Davi Pereira' then null when 'Enzo Martins' then 4 when 'Yasmin Moreira' then 5
                          when 'Laura Mendes' then 1 else (abs(hashtext(r.nome || 'd')) % 3) end;
    if v_dias is null then
      update be_usuarios set xp = 0, nivel = 1, streak_atual = 0, streak_maior = 0, ultima_atividade = null, divisao = 'bronze' where id = r.id;
      continue;
    end if;
    v_streak := case when v_dias <= 1 then 2 + abs(hashtext(r.nome || 's')) % 14 else 0 end;
    if r.nome = 'Laura Mendes' then v_streak := 6; end if;
    v_xp := 300 + abs(hashtext(r.nome || 'x')) % 2100;
    update be_usuarios set xp = v_xp, nivel = v_xp / 200 + 1, streak_atual = v_streak,
      streak_maior = greatest(v_streak, 3 + abs(hashtext(r.nome || 'm')) % 18), ultima_atividade = v_hoje - v_dias,
      divisao = case when v_xp > 1800 then 'ouro' when v_xp > 900 then 'prata' else 'bronze' end
    where id = r.id;

    -- domínio por tópico nas matérias das turmas do aluno
    for t in select tp.id, tp.ordem, m.id as materia_id, tp.nome
             from be_grupo_membros gm join be_materias m on m.grupo_id = gm.grupo_id join be_topicos tp on tp.materia_id = m.id
             where gm.usuario_id = r.id and gm.papel_no_grupo = 'membro' loop
      v_n := 4 + abs(hashtext(r.nome || t.nome)) % 9;
      insert into be_dominio (usuario_id, topico_id, acertos, erros, score, atualizado_em)
      values (r.id, t.id,
              round(v_n * least(0.97, greatest(0.15, v_hab + ((abs(hashtext(t.nome || r.nome)) % 41) - 25) / 100.0 - t.ordem * 0.03))),
              v_n - round(v_n * least(0.97, greatest(0.15, v_hab + ((abs(hashtext(t.nome || r.nome)) % 41) - 25) / 100.0 - t.ordem * 0.03))),
              round(least(0.97, greatest(0.15, v_hab + ((abs(hashtext(t.nome || r.nome)) % 41) - 25) / 100.0 - t.ordem * 0.03)), 3),
              now() - make_interval(days => v_dias + abs(hashtext(t.nome || r.nome || 'q')) % 3));
    end loop;

    -- XP dos últimos 7 dias (quem estudou nos últimos dias)
    insert into be_xp_eventos (usuario_id, tipo, pontos, created_at)
    select r.id, (array['quiz', 'tarefa', 'cards', 'tarefa'])[1 + (d + abs(hashtext(r.nome))) % 4], 10 + abs(hashtext(r.nome || d::text)) % 35,
           (v_hoje - d)::timestamp + time '19:00' + make_interval(mins => abs(hashtext(r.nome || d::text || 'h')) % 180)
    from generate_series(v_dias, 6) d
    where abs(hashtext(r.nome || d::text || 'p')) % 10 < 7;

    -- tarefas feitas nos últimos 7 dias (só dos alunos sem login; a Laura monta o plano dela no app)
    if r.auth_user_id is null then
      insert into be_plano_tarefas (usuario_id, materia_id, dia, tipo, topico_id, titulo, minutos, ordem, feita_em)
      select r.id, x.materia_id, v_hoje - x.d, x.tipo, x.topico_id, x.titulo, 15 + 5 * (x.d % 3), 0,
             (v_hoje - x.d)::timestamp + time '18:30' + make_interval(mins => x.d * 7)
      from (
        select tp.materia_id, tp.id as topico_id, d,
               (array['estudar', 'quiz', 'cards'])[1 + (d + tp.ordem) % 3] as tipo,
               (array['Estudar: ', 'Quiz: ', 'Flashcards: '])[1 + (d + tp.ordem) % 3] || tp.nome as titulo
        from be_grupo_membros gm join be_materias m on m.grupo_id = gm.grupo_id join be_topicos tp on tp.materia_id = m.id,
             generate_series(v_dias, 6) d
        where gm.usuario_id = r.id and gm.papel_no_grupo = 'membro' and (d + tp.ordem + abs(hashtext(r.nome))) % 4 = 0
      ) x;
    end if;
  end loop;

  -- conversa nas salas das turmas (só se a sala ainda estiver vazia)
  for r in select g.id, g.nome, s.id as sala from be_grupos g join be_salas s on s.grupo_id = g.id where g.instituicao_id = v_inst loop
    if exists (select 1 from be_sala_mensagens where sala_id = r.sala) then continue; end if;
    insert into be_sala_mensagens (sala_id, usuario_id, texto, created_at)
    select r.sala, u.id, x.texto, now() - make_interval(hours => x.h)
    from (values
      ('3º A · Matemática', 'Helena Duarte', 'Pessoal, o resumo de funções e o plano até a prova do dia 17 já estão no app. Façam o quiz até sexta!', 70),
      ('3º A · Matemática', 'Pedro Henrique Lima', 'prof, no exercício do lucro o máximo é sempre no vértice?', 52),
      ('3º A · Matemática', 'Helena Duarte', 'Isso, Pedro! Quando o "a" é negativo a parábola abre pra baixo e o vértice é o ponto mais alto.', 51),
      ('3º A · Matemática', 'Beatriz Santos', 'errei a de delta negativo no quiz 😅 vou revisar nos flashcards', 30),
      ('3º A · Matemática', 'Sofia Carvalho', 'alguém quer revisar junto na biblioteca amanhã depois da aula?', 20),
      ('3º A · Matemática', 'Lucas Ferreira', 'bora! levo a lista de exercícios', 19),
      ('2º B · Biologia', 'Ricardo Almeida', 'Turma, a foto do caderno virou resumo, mapa mental e flashcards. Prova dia 12!', 60),
      ('2º B · Biologia', 'Valentina Gomes', 'prof, a fase escura só acontece à noite?', 40),
      ('2º B · Biologia', 'Ricardo Almeida', 'Boa pergunta! Não: ela não usa luz diretamente, mas acontece de dia também, com o ATP e o NADPH da fase clara.', 39),
      ('2º B · Biologia', 'Alice Barbosa', 'aaah agora entendi', 38),
      ('2º B · Biologia', 'Rafael Teixeira', 'o flashcard do ponto de compensação me salvou', 12),
      ('3º A · Redação ENEM', 'Camila Rocha', 'Pessoal, a apostila das 5 competências está no app. Simulado de redação dia 06/11.', 80),
      ('3º A · Redação ENEM', 'Isabela Costa', 'prof, repertório pode ser filme?', 44),
      ('3º A · Redação ENEM', 'Camila Rocha', 'Pode, desde que tenha a ver com o tema e você explique a relação com o seu argumento.', 43),
      ('3º A · Redação ENEM', 'Matheus Ribeiro', 'vou treinar a proposta de intervenção com os 5 elementos', 25),
      ('3º A · Redação ENEM', 'Manuela Araújo', 'agente, ação, modo, finalidade e detalhamento ✍️', 24)
    ) x(turma, autor, texto, h)
    join be_usuarios u on u.nome = x.autor and u.instituicao_id = v_inst
    where x.turma = r.nome;
  end loop;
end $$;
