-- Estude+ — regras do jogo no servidor (XP, streak, liga, revisão espaçada, plano, simulado ENEM)
-- Tudo security definer com checagem de dono; o front só chama rpc().


-- Funções internas não podem ser chamadas direto pelo app (API). Em vez de revogar permissões,
-- cada uma exige: chamada vinda do próprio banco (cron/SQL), da service role, ou de uma rpc do app
-- que liga a marca be.interno só durante a própria transação.
create or replace function public.be_exigir_interno() returns void
language plpgsql stable set search_path = public as $$
begin
  if session_user = 'authenticator'
     and coalesce(current_setting('be.interno', true), '') <> '1'
     and coalesce(nullif(current_setting('request.jwt.claims', true), '')::jsonb ->> 'role', '') <> 'service_role' then
    raise exception 'função interna do Estude+';
  end if;
end $$;

create or replace function public.be_modo_interno() returns void
language plpgsql volatile set search_path = public as $$
begin
  perform set_config('be.interno', '1', true);
end $$;

-- reforça as duas funções que já existiam e recebem um usuário qualquer como parâmetro
create or replace function public.be_incrementar_uso_ia(p_usuario_id uuid) returns void
language plpgsql security definer set search_path = public as $$
begin
  perform be_exigir_interno();
  insert into be_uso_ia (usuario_id, data, quantidade) values (p_usuario_id, current_date, 1)
  on conflict (usuario_id, data) do update set quantidade = be_uso_ia.quantidade + 1;
end $$;

create or replace function public.be_materia_acessivel_para(p_usuario uuid, p_materia uuid) returns boolean
language plpgsql stable security definer set search_path = public as $$
begin
  perform be_exigir_interno();
  return exists (
    select 1 from be_materias m
    where m.id = p_materia
      and (m.usuario_id = p_usuario
           or m.grupo_id in (select grupo_id from be_grupo_membros where usuario_id = p_usuario)));
end $$;

-- =========================================================
-- INTERNAS (não expostas ao app)
-- =========================================================

create or replace function public.be_conceder_conquista(p_usuario uuid, p_codigo text) returns boolean
language plpgsql security definer set search_path = public as $$
declare v_id uuid; v_n int;
begin
  perform be_exigir_interno();
  select id into v_id from be_conquistas where codigo = p_codigo;
  if v_id is null then return false; end if;
  insert into be_usuario_conquistas (usuario_id, conquista_id) values (p_usuario, v_id)
  on conflict (usuario_id, conquista_id) do nothing;
  get diagnostics v_n = row_count;
  return v_n > 0;
end $$;

create or replace function public.be_entrar_liga_atual(p_usuario uuid) returns uuid
language plpgsql security definer set search_path = public as $$
declare v_semana date := be_semana_atual(); v_div text; v_liga uuid;
begin
  perform be_exigir_interno();
  select lm.liga_id into v_liga
  from be_liga_membros lm join be_ligas l on l.id = lm.liga_id
  where lm.usuario_id = p_usuario and l.semana = v_semana limit 1;
  if v_liga is not null then return v_liga; end if;

  select divisao into v_div from be_usuarios where id = p_usuario;
  if v_div is null then return null; end if;

  perform pg_advisory_xact_lock(hashtext('be_liga_' || v_semana::text || v_div));

  select l.id into v_liga from be_ligas l
  where l.semana = v_semana and l.divisao = v_div and not l.fechada
    and (select count(*) from be_liga_membros m where m.liga_id = l.id) < 30
  order by l.created_at limit 1;

  if v_liga is null then
    insert into be_ligas (semana, divisao) values (v_semana, v_div) returning id into v_liga;
  end if;

  insert into be_liga_membros (liga_id, usuario_id) values (v_liga, p_usuario)
  on conflict do nothing;
  return v_liga;
end $$;

create or replace function public.be_ganhar_xp(p_usuario uuid, p_tipo text, p_pontos int, p_ref uuid default null)
returns int language plpgsql security definer set search_path = public as $$
declare
  v_hoje date := be_hoje();
  v_ult date; v_streak int; v_xp int; v_liga uuid;
begin
  perform be_exigir_interno();
  if p_pontos is null or p_pontos <= 0 then
    select xp into v_xp from be_usuarios where id = p_usuario;
    return coalesce(v_xp, 0);
  end if;

  insert into be_xp_eventos (usuario_id, tipo, pontos, ref_id) values (p_usuario, p_tipo, p_pontos, p_ref);

  select ultima_atividade, streak_atual into v_ult, v_streak from be_usuarios where id = p_usuario for update;
  if v_ult is distinct from v_hoje then
    if v_ult = v_hoje - 1 then v_streak := coalesce(v_streak, 0) + 1; else v_streak := 1; end if;
  end if;

  update be_usuarios set
    xp = xp + p_pontos,
    nivel = ((xp + p_pontos) / 200) + 1,
    streak_atual = v_streak,
    streak_maior = greatest(streak_maior, v_streak),
    ultima_atividade = v_hoje
  where id = p_usuario
  returning xp into v_xp;

  insert into be_streak_log (usuario_id, data) values (p_usuario, v_hoje) on conflict do nothing;

  if v_streak >= 7 then perform be_conceder_conquista(p_usuario, 'streak_7_dias'); end if;
  if v_streak >= 30 then perform be_conceder_conquista(p_usuario, 'streak_30_dias'); end if;
  if extract(hour from (now() at time zone 'America/Sao_Paulo')) < 5 then
    perform be_conceder_conquista(p_usuario, 'coruja_madrugada');
  end if;

  v_liga := be_entrar_liga_atual(p_usuario);
  update be_liga_membros set xp_semana = xp_semana + p_pontos
  where liga_id = v_liga and usuario_id = p_usuario;

  return v_xp;
end $$;

-- domínio: média móvel por tópico (0 = não sabe, 1 = domina)
create or replace function public.be_atualizar_dominio(p_usuario uuid, p_topico uuid, p_acertou boolean)
returns numeric language plpgsql security definer set search_path = public as $$
declare v_score numeric;
begin
  perform be_exigir_interno();
  if p_topico is null then return null; end if;
  insert into be_dominio (usuario_id, topico_id, acertos, erros, score, atualizado_em)
  values (p_usuario, p_topico, case when p_acertou then 1 else 0 end, case when p_acertou then 0 else 1 end,
          case when p_acertou then 0.55 else 0.15 end, now())
  on conflict (usuario_id, topico_id) do update set
    acertos = be_dominio.acertos + case when p_acertou then 1 else 0 end,
    erros = be_dominio.erros + case when p_acertou then 0 else 1 end,
    score = round(be_dominio.score + 0.35 * ((case when p_acertou then 1 else 0 end) - be_dominio.score), 3),
    atualizado_em = now()
  returning score into v_score;
  return v_score;
end $$;

-- =========================================================
-- QUIZ / PROVA da matéria
-- =========================================================

create or replace function public.be_responder_pergunta(p_pergunta uuid, p_resposta text, p_tempo_ms int default null)
returns json language plpgsql security definer set search_path = public as $$
declare
  v_u uuid := be_usuario_atual_id();
  v_q record; v_acertou boolean; v_xp int := 0; v_ja boolean; v_score numeric;
begin
  if v_u is null then raise exception 'faça login de novo'; end if;
  perform be_modo_interno();

  select q.id, q.resposta_correta, q.explicacao, q.topico_id, c.materia_id
    into v_q
  from be_quiz_perguntas q join be_conteudo_gerado c on c.id = q.conteudo_gerado_id
  where q.id = p_pergunta;
  if v_q.id is null or not be_materia_acessivel_para(v_u, v_q.materia_id) then
    raise exception 'pergunta não encontrada';
  end if;

  v_acertou := upper(trim(coalesce(p_resposta, ''))) = upper(trim(v_q.resposta_correta));

  select exists (select 1 from be_tentativas t where t.usuario_id = v_u and t.quiz_pergunta_id = p_pergunta
                 and (t.created_at at time zone 'America/Sao_Paulo')::date = be_hoje()) into v_ja;

  if not v_ja then v_xp := case when v_acertou then 10 else 3 end; end if;

  insert into be_tentativas (usuario_id, quiz_pergunta_id, acertou, tempo_resposta_ms, pontos_ganhos)
  values (v_u, p_pergunta, v_acertou, p_tempo_ms, v_xp);

  v_score := be_atualizar_dominio(v_u, v_q.topico_id, v_acertou);
  perform be_ganhar_xp(v_u, 'quiz', v_xp, p_pergunta);

  return json_build_object('acertou', v_acertou, 'correta', v_q.resposta_correta,
                           'explicacao', v_q.explicacao, 'xp', v_xp, 'dominio', v_score);
end $$;

-- =========================================================
-- FLASHCARDS — repetição espaçada FSRS-4.5 (retenção alvo 90%)
-- =========================================================

create or replace function public.be_revisar_card(p_card uuid, p_nota int)
returns json language plpgsql security definer set search_path = public as $$
declare
  w constant float8[] := array[0.4872,1.4003,3.7145,13.8206,5.1618,1.2298,0.8975,0.031,1.6474,0.1367,1.0461,2.1072,0.0793,0.3246,1.587,0.2272,2.8755];
  v_u uuid := be_usuario_atual_id();
  v_hoje date := be_hoje();
  v_card record; r record;
  s float8; d float8; v_r float8; t float8; v_int int; v_estado smallint; v_xp int := 0; v_ja boolean;
begin
  if v_u is null then raise exception 'faça login de novo'; end if;
  perform be_modo_interno();
  if p_nota not between 1 and 4 then raise exception 'nota inválida'; end if;

  select id, materia_id into v_card from be_cards where id = p_card;
  if v_card.id is null or not be_materia_acessivel_para(v_u, v_card.materia_id) then
    raise exception 'card não encontrado';
  end if;

  insert into be_card_revisoes (usuario_id, card_id, proxima) values (v_u, p_card, v_hoje)
  on conflict do nothing;
  select * into r from be_card_revisoes where usuario_id = v_u and card_id = p_card for update;

  v_ja := r.ultima_revisao is not null and (r.ultima_revisao at time zone 'America/Sao_Paulo')::date = v_hoje;

  if r.repeticoes = 0 or r.estabilidade <= 0 then
    s := w[p_nota];
    d := least(10, greatest(1, w[5] - (p_nota - 3) * w[6]));
  else
    t := greatest(0, v_hoje - (r.ultima_revisao at time zone 'America/Sao_Paulo')::date);
    v_r := power(1 + (19.0/81.0) * t / r.estabilidade, -0.5);
    d := r.dificuldade - w[7] * (p_nota - 3);
    d := w[8] * (w[5] - (4 - 3) * w[6]) + (1 - w[8]) * d;
    d := least(10, greatest(1, d));
    if p_nota = 1 then
      s := w[12] * power(d, -w[13]) * (power(r.estabilidade + 1, w[14]) - 1) * exp(w[15] * (1 - v_r));
      s := least(s, r.estabilidade);
    else
      s := r.estabilidade * (exp(w[9]) * (11 - d) * power(r.estabilidade, -w[10]) * (exp(w[11] * (1 - v_r)) - 1)
             * (case when p_nota = 2 then w[16] else 1 end)
             * (case when p_nota = 4 then w[17] else 1 end) + 1);
    end if;
  end if;
  s := greatest(s, 0.1);

  if p_nota = 1 then
    v_int := 0;
    v_estado := case when r.repeticoes = 0 then 1 else 3 end;
  else
    v_int := least(365, greatest(1, round(s)::int));
    v_estado := 2;
  end if;

  update be_card_revisoes set
    estado = v_estado,
    estabilidade = s,
    dificuldade = d,
    repeticoes = repeticoes + 1,
    lapsos = lapsos + case when p_nota = 1 and r.repeticoes > 0 then 1 else 0 end,
    ultima_revisao = now(),
    proxima = v_hoje + v_int
  where usuario_id = v_u and card_id = p_card;

  if not v_ja then
    v_xp := 2;
    perform be_ganhar_xp(v_u, 'card', v_xp, p_card);
  end if;

  if (select count(*) from be_card_revisoes where usuario_id = v_u and repeticoes > 0) >= 100 then
    perform be_conceder_conquista(v_u, 'cem_cards');
  end if;

  return json_build_object('intervalo_dias', v_int, 'proxima', v_hoje + v_int, 'xp', v_xp,
                           'estabilidade', round(s::numeric, 2));
end $$;

create or replace function public.be_cards_para_revisar(p_materia uuid default null, p_limite int default 30)
returns table (card_id uuid, frente text, verso text, materia_id uuid, materia_nome text, topico text, novo boolean)
language plpgsql security definer set search_path = public as $$
#variable_conflict use_column
declare v_u uuid := be_usuario_atual_id(); v_hoje date := be_hoje(); v_novos_hoje int; v_cota int;
begin
  if v_u is null then raise exception 'faça login de novo'; end if;
  perform be_modo_interno();

  select count(*) into v_novos_hoje from be_card_revisoes cr
  where cr.usuario_id = v_u and cr.repeticoes > 0
    and cr.repeticoes = 1 and (cr.ultima_revisao at time zone 'America/Sao_Paulo')::date = v_hoje;
  v_cota := greatest(0, 20 - v_novos_hoje);

  return query
  with materias as (
    select m.id, m.nome from be_materias m
    where m.status = 'ativa' and (p_materia is null or m.id = p_materia)
      and (m.usuario_id = v_u or m.grupo_id in (select gm.grupo_id from be_grupo_membros gm where gm.usuario_id = v_u))
  ), vencidos as (
    select c.id, c.frente, c.verso, c.materia_id, ma.nome, t.nome as tnome, false as novo, cr.proxima as ord
    from be_card_revisoes cr
    join be_cards c on c.id = cr.card_id
    join materias ma on ma.id = c.materia_id
    left join be_topicos t on t.id = c.topico_id
    where cr.usuario_id = v_u and cr.proxima <= v_hoje
  ), novos as (
    select c.id, c.frente, c.verso, c.materia_id, ma.nome, t.nome as tnome, true as novo, v_hoje as ord
    from be_cards c
    join materias ma on ma.id = c.materia_id
    left join be_topicos t on t.id = c.topico_id
    where not exists (select 1 from be_card_revisoes cr where cr.usuario_id = v_u and cr.card_id = c.id)
    order by c.created_at
    limit v_cota
  )
  select x.id, x.frente, x.verso, x.materia_id, x.nome, x.tnome, x.novo
  from (select * from vencidos union all select * from novos) x
  order by x.novo, x.ord
  limit greatest(1, least(p_limite, 200));
end $$;

-- =========================================================
-- PLANO DE PROVA
-- =========================================================

create or replace function public.be_gerar_plano(p_materia uuid) returns int
language plpgsql security definer set search_path = public as $$
declare
  v_u uuid := be_usuario_atual_id();
  v_hoje date := be_hoje();
  v_m record; v_dias date[]; v_dias_estudo smallint[];
  v_topicos uuid[]; v_nomes text[]; v_scores numeric[];
  v_n_dias int; v_n_top int; v_ultimo date; v_estudo date[];
  v_seq int[]; i int; j int; k int; v_por_dia int; v_count int := 0; v_ord smallint;
  v_tid uuid; v_tnome text; v_primeira boolean;
begin
  if v_u is null then raise exception 'faça login de novo'; end if;
  perform be_modo_interno();
  select id, nome, data_prova into v_m from be_materias where id = p_materia;
  if v_m.id is null or not be_materia_acessivel_para(v_u, p_materia) then raise exception 'matéria não encontrada'; end if;
  if v_m.data_prova is null then raise exception 'defina a data da prova para montar o plano'; end if;
  if v_m.data_prova < v_hoje then raise exception 'a data da prova já passou'; end if;

  -- as tarefas automáticas futuras ainda não feitas saem do plano (ficam guardadas como substituídas, nada é apagado)
  update be_plano_tarefas set substituida = true
  where usuario_id = v_u and materia_id = p_materia and not manual and feita_em is null and dia >= v_hoje and not substituida;

  select coalesce(dias_estudo, '{1,2,3,4,5,6}') into v_dias_estudo from be_usuarios where id = v_u;

  select coalesce(array_agg(g::date order by g), '{}') into v_dias
  from generate_series(v_hoje, v_m.data_prova - 1, interval '1 day') g
  where extract(isodow from g)::smallint = any (v_dias_estudo);
  if coalesce(array_length(v_dias, 1), 0) = 0 then v_dias := array[v_hoje]; end if;
  v_n_dias := array_length(v_dias, 1);
  v_ultimo := v_dias[v_n_dias];

  select coalesce(array_agg(t.id order by t.ordem, t.created_at), '{}'),
         coalesce(array_agg(t.nome order by t.ordem, t.created_at), '{}'),
         coalesce(array_agg(coalesce(d.score, 0) order by t.ordem, t.created_at), '{}')
    into v_topicos, v_nomes, v_scores
  from be_topicos t left join be_dominio d on d.topico_id = t.id and d.usuario_id = v_u
  where t.materia_id = p_materia;
  v_n_top := coalesce(array_length(v_topicos, 1), 0);
  if v_n_top = 0 then
    v_topicos := array[null::uuid]; v_nomes := array[v_m.nome]; v_scores := array[0::numeric]; v_n_top := 1;
  end if;

  -- dias de estudo de tópicos = todos menos o último (véspera), se houver mais de um
  if v_n_dias > 1 then v_estudo := v_dias[1:v_n_dias - 1]; else v_estudo := '{}'; end if;

  -- sequência: 1ª passada por todos os tópicos; depois os mais fracos primeiro, em rodízio
  v_seq := '{}';
  for i in 1..v_n_top loop v_seq := v_seq || i; end loop;
  if coalesce(array_length(v_estudo, 1), 0) > v_n_top then
    declare v_ordem int[];
    begin
      select array_agg(idx order by sc, idx) into v_ordem
      from unnest(v_scores) with ordinality as u(sc, idx);
      k := 1;
      while array_length(v_seq, 1) < array_length(v_estudo, 1) loop
        v_seq := v_seq || v_ordem[k];
        k := k % v_n_top + 1;
      end loop;
    end;
  end if;

  if coalesce(array_length(v_estudo, 1), 0) > 0 then
    v_por_dia := ceil(array_length(v_seq, 1)::numeric / array_length(v_estudo, 1));
    k := 1;
    for i in 1..array_length(v_estudo, 1) loop
      v_ord := 0;
      for j in 1..v_por_dia loop
        exit when k > array_length(v_seq, 1);
        v_tid := v_topicos[v_seq[k]]; v_tnome := v_nomes[v_seq[k]];
        v_primeira := k <= v_n_top;
        if v_primeira then
          insert into be_plano_tarefas (usuario_id, materia_id, dia, tipo, topico_id, titulo, minutos, ordem)
          values (v_u, p_materia, v_estudo[i], 'estudar', v_tid, 'Estudar: ' || v_tnome, 15, v_ord);
          v_ord := v_ord + 1; v_count := v_count + 1;
        end if;
        insert into be_plano_tarefas (usuario_id, materia_id, dia, tipo, topico_id, titulo, minutos, ordem)
        values (v_u, p_materia, v_estudo[i], 'quiz', v_tid,
                case when v_primeira then 'Quiz: ' else 'Revisar com quiz: ' end || v_tnome, 10, v_ord);
        v_ord := v_ord + 1; v_count := v_count + 1;
        k := k + 1;
      end loop;
      insert into be_plano_tarefas (usuario_id, materia_id, dia, tipo, titulo, minutos, ordem)
      values (v_u, p_materia, v_estudo[i], 'cards', 'Flashcards do dia', 10, v_ord);
      v_count := v_count + 1;
    end loop;
  end if;

  -- véspera: revisão geral + prova simulada
  insert into be_plano_tarefas (usuario_id, materia_id, dia, tipo, titulo, minutos, ordem) values
    (v_u, p_materia, v_ultimo, 'revisao_geral', 'Revisão geral: resumo e mapa mental', 15, 0),
    (v_u, p_materia, v_ultimo, 'cards', 'Flashcards do dia', 10, 1),
    (v_u, p_materia, v_ultimo, 'prova', 'Prova simulada de ' || v_m.nome, 20, 2);
  v_count := v_count + 3;

  return v_count;
end $$;

create or replace function public.be_marcar_tarefa(p_tarefa uuid, p_feita boolean default true)
returns json language plpgsql security definer set search_path = public as $$
declare
  v_u uuid := be_usuario_atual_id(); v_hoje date := be_hoje();
  v_t record; v_xp int := 0; v_completo boolean := false; v_bonus int := 0;
begin
  if v_u is null then raise exception 'faça login de novo'; end if;
  perform be_modo_interno();
  select * into v_t from be_plano_tarefas where id = p_tarefa and usuario_id = v_u and not substituida;
  if v_t.id is null then raise exception 'tarefa não encontrada'; end if;

  update be_plano_tarefas set feita_em = case when p_feita then coalesce(feita_em, now()) else null end
  where id = p_tarefa;

  if p_feita and not exists (select 1 from be_xp_eventos where usuario_id = v_u and tipo = 'tarefa' and ref_id = p_tarefa) then
    v_xp := 15;
    perform be_ganhar_xp(v_u, 'tarefa', v_xp, p_tarefa);
  end if;

  if p_feita and v_t.dia = v_hoje and not exists (
       select 1 from be_plano_tarefas where usuario_id = v_u and dia = v_hoje and feita_em is null and not substituida) then
    v_completo := true;
    perform be_conceder_conquista(v_u, 'plano_em_dia');
    if not exists (select 1 from be_xp_eventos where usuario_id = v_u and tipo = 'dia_completo'
                   and (created_at at time zone 'America/Sao_Paulo')::date = v_hoje) then
      v_bonus := 20;
      perform be_ganhar_xp(v_u, 'dia_completo', v_bonus, null);
    end if;
  end if;

  return json_build_object('xp', v_xp + v_bonus, 'dia_completo', v_completo);
end $$;

-- =========================================================
-- ENEM — simulado com questões oficiais
-- =========================================================

create or replace function public.be_iniciar_simulado(p_area text default null, p_qtd int default 10, p_idioma text default 'ingles')
returns json language plpgsql security definer set search_path = public as $$
declare v_u uuid := be_usuario_atual_id(); v_ids uuid[]; v_sim uuid; v_qtd int := least(45, greatest(5, coalesce(p_qtd, 10)));
begin
  if v_u is null then raise exception 'faça login de novo'; end if;
  perform be_modo_interno();
  if p_area is not null and p_area not in ('linguagens','ciencias-humanas','ciencias-natureza','matematica') then
    raise exception 'área inválida';
  end if;

  with vistas as (
    select unnest(questoes) as id from be_simulados where usuario_id = v_u
  )
  select array_agg(id) into v_ids from (
    select q.id from be_enem_questoes q
    where (p_area is null or q.area = p_area)
      and (q.idioma is null or q.idioma = coalesce(p_idioma, 'ingles'))
    order by (q.id in (select id from vistas)), random()
    limit v_qtd
  ) s;

  if v_ids is null then raise exception 'o banco de questões do ENEM ainda está vazio'; end if;

  insert into be_simulados (usuario_id, area, modo, questoes, total)
  values (v_u, p_area, case when v_qtd >= 45 then 'completo' else 'rapido' end, v_ids, array_length(v_ids, 1))
  returning id into v_sim;

  return json_build_object(
    'simulado_id', v_sim,
    'questoes', (
      select json_agg(json_build_object('id', q.id, 'ano', q.ano, 'numero', q.numero, 'area', q.area,
                                        'contexto', q.contexto, 'introducao', q.introducao, 'alternativas', q.alternativas)
                      order by o.ord)
      from unnest(v_ids) with ordinality as o(id, ord) join be_enem_questoes q on q.id = o.id
    )
  );
end $$;

create or replace function public.be_finalizar_simulado(p_simulado uuid, p_respostas jsonb, p_duracao_seg int default null)
returns json language plpgsql security definer set search_path = public as $$
declare v_u uuid := be_usuario_atual_id(); v_s record; v_acertos int; v_xp int; v_res json;
begin
  if v_u is null then raise exception 'faça login de novo'; end if;
  perform be_modo_interno();
  select * into v_s from be_simulados where id = p_simulado and usuario_id = v_u for update;
  if v_s.id is null then raise exception 'simulado não encontrado'; end if;
  if v_s.finalizado_em is not null then raise exception 'esse simulado já foi entregue'; end if;

  select count(*) filter (where upper(coalesce(p_respostas ->> q.id::text, '')) = q.gabarito)
    into v_acertos
  from be_enem_questoes q where q.id = any (v_s.questoes);

  update be_simulados set respostas = coalesce(p_respostas, '{}'::jsonb), acertos = v_acertos,
         duracao_seg = p_duracao_seg, finalizado_em = now()
  where id = p_simulado;

  v_xp := v_acertos * 5 + 10;
  perform be_ganhar_xp(v_u, 'simulado', v_xp, p_simulado);
  perform be_conceder_conquista(v_u, 'primeiro_simulado_enem');
  if v_acertos = v_s.total and v_s.total >= 10 then perform be_conceder_conquista(v_u, 'simulado_sem_erros'); end if;

  select json_build_object(
    'acertos', v_acertos, 'total', v_s.total, 'xp', v_xp,
    'gabarito', (select json_object_agg(q.id, q.gabarito) from be_enem_questoes q where q.id = any (v_s.questoes)),
    'por_area', (select json_object_agg(area, json_build_object('acertos', a, 'total', t)) from (
        select q.area, count(*) t,
               count(*) filter (where upper(coalesce(p_respostas ->> q.id::text, '')) = q.gabarito) a
        from be_enem_questoes q where q.id = any (v_s.questoes) group by q.area) x)
  ) into v_res;
  return v_res;
end $$;

-- =========================================================
-- LIGA SEMANAL
-- =========================================================

create or replace function public.be_minha_liga() returns json
language plpgsql security definer set search_path = public as $$
declare v_u uuid := be_usuario_atual_id(); v_liga uuid; v_l record;
begin
  if v_u is null then raise exception 'faça login de novo'; end if;
  perform be_modo_interno();
  v_liga := be_entrar_liga_atual(v_u);
  select * into v_l from be_ligas where id = v_liga;
  return json_build_object(
    'semana', v_l.semana,
    'termina_em', (v_l.semana + 7),
    'divisao', v_l.divisao,
    'sobem', case when v_l.divisao = 'diamante' then 0 else 5 end,
    'caem', case when v_l.divisao = 'bronze' then 0 else 5 end,
    'membros', (
      select json_agg(json_build_object(
               'nome', split_part(u.nome, ' ', 1) || coalesce(' ' || left(nullif(split_part(u.nome, ' ', 2), ''), 1) || '.', ''),
               'iniciais', upper(left(u.nome, 1) || coalesce(left(nullif(split_part(u.nome, ' ', 2), ''), 1), '')),
               'xp', m.xp_semana,
               'eu', m.usuario_id = v_u,
               'posicao', m.pos)
             order by m.pos)
      from (select lm.*, row_number() over (order by lm.xp_semana desc, lm.entrou_em) as pos
            from be_liga_membros lm where lm.liga_id = v_liga) m
      join be_usuarios u on u.id = m.usuario_id
    )
  );
end $$;

create or replace function public.be_fechar_ligas() returns int
language plpgsql security definer set search_path = public as $$
declare v_l record; v_n int; v_fechadas int := 0;
  ordem constant text[] := array['bronze','prata','ouro','diamante'];
begin
  perform be_exigir_interno();
  for v_l in select * from be_ligas where not fechada and semana < be_semana_atual() loop
    select count(*) into v_n from be_liga_membros where liga_id = v_l.id;

    with r as (
      select usuario_id, xp_semana, row_number() over (order by xp_semana desc, entrou_em) pos
      from be_liga_membros where liga_id = v_l.id
    )
    update be_liga_membros lm set
      posicao = r.pos,
      resultado = case
        when v_l.divisao <> 'diamante' and r.pos <= 5 and r.xp_semana > 0 and v_n >= 2 then 'subiu'
        when v_l.divisao <> 'bronze' and v_n >= 10 and r.pos > v_n - 5 then 'caiu'
        when v_l.divisao <> 'bronze' and r.xp_semana = 0 then 'caiu'
        else 'ficou' end
    from r where lm.liga_id = v_l.id and lm.usuario_id = r.usuario_id;

    update be_usuarios u set divisao = ordem[array_position(ordem, v_l.divisao) + 1]
    from be_liga_membros lm where lm.liga_id = v_l.id and lm.usuario_id = u.id and lm.resultado = 'subiu';
    update be_usuarios u set divisao = ordem[array_position(ordem, v_l.divisao) - 1]
    from be_liga_membros lm where lm.liga_id = v_l.id and lm.usuario_id = u.id and lm.resultado = 'caiu';

    perform be_conceder_conquista(lm.usuario_id, 'subiu_de_liga')
    from be_liga_membros lm where lm.liga_id = v_l.id and lm.resultado = 'subiu';

    update be_ligas set fechada = true where id = v_l.id;
    v_fechadas := v_fechadas + 1;
  end loop;
  return v_fechadas;
end $$;

-- =========================================================
-- HOME e TURMA
-- =========================================================

create or replace function public.be_resumo_hoje() returns json
language plpgsql security definer set search_path = public as $$
declare v_u uuid := be_usuario_atual_id(); v_hoje date := be_hoje(); v_usr record; v_streak int; v_liga json;
begin
  if v_u is null then raise exception 'faça login de novo'; end if;
  perform be_modo_interno();

  -- quem entrou numa turma (ou ainda não tinha plano) ganha o plano das matérias com prova marcada
  perform be_gerar_plano(m.id)
  from be_materias m
  where m.status = 'ativa' and m.data_prova >= v_hoje
    and (m.usuario_id = v_u or m.grupo_id in (select grupo_id from be_grupo_membros where usuario_id = v_u))
    and exists (select 1 from be_topicos t where t.materia_id = m.id)
    and not exists (select 1 from be_plano_tarefas pt where pt.materia_id = m.id and pt.usuario_id = v_u and not pt.substituida);

  select * into v_usr from be_usuarios where id = v_u;
  v_streak := case when v_usr.ultima_atividade >= v_hoje - 1 then v_usr.streak_atual else 0 end;

  select json_build_object('divisao', l.divisao, 'xp_semana', m.xp_semana,
           'posicao', (select count(*) + 1 from be_liga_membros o where o.liga_id = m.liga_id and o.xp_semana > m.xp_semana),
           'total', (select count(*) from be_liga_membros o where o.liga_id = m.liga_id))
    into v_liga
  from be_liga_membros m join be_ligas l on l.id = m.liga_id
  where m.usuario_id = v_u and l.semana = be_semana_atual() limit 1;

  return json_build_object(
    'hoje', v_hoje,
    'nome', v_usr.nome, 'papel', v_usr.papel, 'xp', v_usr.xp, 'nivel', v_usr.nivel,
    'streak', v_streak, 'estudou_hoje', v_usr.ultima_atividade = v_hoje,
    'divisao', v_usr.divisao,
    'energia', greatest(0, 7 - coalesce((select quantidade from be_uso_ia where usuario_id = v_u and data = current_date), 0)),
    'liga', v_liga,
    'cards_pendentes', (select count(*) from be_card_revisoes cr join be_cards c on c.id = cr.card_id
                          join be_materias m on m.id = c.materia_id
                        where cr.usuario_id = v_u and cr.proxima <= v_hoje and m.status = 'ativa'),
    'cards_novos', (select count(*) from be_cards c join be_materias m on m.id = c.materia_id
                    where m.status = 'ativa'
                      and (m.usuario_id = v_u or m.grupo_id in (select grupo_id from be_grupo_membros where usuario_id = v_u))
                      and not exists (select 1 from be_card_revisoes cr where cr.usuario_id = v_u and cr.card_id = c.id)),
    'tarefas', coalesce((
      select json_agg(json_build_object('id', t.id, 'tipo', t.tipo, 'titulo', t.titulo, 'minutos', t.minutos,
                                        'feita', t.feita_em is not null, 'materia_id', t.materia_id, 'materia', m.nome,
                                        'topico_id', t.topico_id, 'dia', t.dia, 'atrasada', t.dia < v_hoje)
                      order by t.dia, m.nome, t.ordem)
      from be_plano_tarefas t join be_materias m on m.id = t.materia_id
      where t.usuario_id = v_u and m.status = 'ativa' and not t.substituida
        and (t.dia = v_hoje or (t.dia < v_hoje and t.feita_em is null and t.dia >= v_hoje - 3))
    ), '[]'::json),
    'provas', coalesce((
      select json_agg(json_build_object('id', m.id, 'nome', m.nome, 'data_prova', m.data_prova,
                                        'dias', m.data_prova - v_hoje) order by m.data_prova)
      from be_materias m
      where m.status = 'ativa' and m.data_prova >= v_hoje
        and (m.usuario_id = v_u or m.grupo_id in (select grupo_id from be_grupo_membros where usuario_id = v_u))
    ), '[]'::json)
  );
end $$;

create or replace function public.be_painel_turma(p_grupo uuid) returns json
language plpgsql security definer set search_path = public as $$
declare v_u uuid := be_usuario_atual_id(); v_hoje date := be_hoje(); v_g record;
begin
  if v_u is null then raise exception 'faça login de novo'; end if;
  perform be_modo_interno();
  if not exists (select 1 from be_grupo_membros where grupo_id = p_grupo and usuario_id = v_u and papel_no_grupo = 'admin') then
    raise exception 'só o admin da turma vê esse painel';
  end if;
  select id, nome, codigo, tipo into v_g from be_grupos where id = p_grupo;

  return json_build_object(
    'grupo', json_build_object('id', v_g.id, 'nome', v_g.nome, 'codigo', v_g.codigo, 'tipo', v_g.tipo),
    'materias', coalesce((
      select json_agg(json_build_object('id', m.id, 'nome', m.nome, 'data_prova', m.data_prova, 'status', m.status,
               'materiais', (select count(*) from be_materiais mt where mt.materia_id = m.id))
             order by m.status, m.data_prova nulls last, m.nome)
      from be_materias m where m.grupo_id = p_grupo
    ), '[]'::json),
    'topicos', coalesce((
      select json_agg(json_build_object('id', t.id, 'nome', t.nome, 'materia', m.nome,
               'media', (select round(avg(d.score), 2) from be_dominio d
                         join be_grupo_membros gm on gm.usuario_id = d.usuario_id and gm.grupo_id = p_grupo
                         where d.topico_id = t.id and gm.papel_no_grupo = 'membro'),
               'alunos', (select count(*) from be_dominio d
                         join be_grupo_membros gm on gm.usuario_id = d.usuario_id and gm.grupo_id = p_grupo
                         where d.topico_id = t.id and gm.papel_no_grupo = 'membro'))
             order by m.nome, t.ordem)
      from be_topicos t join be_materias m on m.id = t.materia_id
      where m.grupo_id = p_grupo and m.status = 'ativa'
    ), '[]'::json),
    'membros', coalesce((
      select json_agg(json_build_object('nome', u.nome, 'papel', gm.papel_no_grupo, 'nivel', u.nivel,
               'ultima_atividade', u.ultima_atividade,
               'dias_sem_estudar', case when u.ultima_atividade is null then null else v_hoje - u.ultima_atividade end,
               'streak', case when u.ultima_atividade >= v_hoje - 1 then u.streak_atual else 0 end,
               'xp_7d', (select coalesce(sum(pontos), 0) from be_xp_eventos x where x.usuario_id = u.id and x.created_at > now() - interval '7 days'),
               'tarefas_7d', (select count(*) from be_plano_tarefas pt join be_materias m on m.id = pt.materia_id
                              where pt.usuario_id = u.id and m.grupo_id = p_grupo and pt.feita_em > now() - interval '7 days'),
               'dominio', (select round(avg(d.score), 2) from be_dominio d join be_topicos t on t.id = d.topico_id
                           join be_materias m on m.id = t.materia_id where d.usuario_id = u.id and m.grupo_id = p_grupo))
             order by gm.papel_no_grupo, u.nome)
      from be_grupo_membros gm join be_usuarios u on u.id = gm.usuario_id
      where gm.grupo_id = p_grupo
    ), '[]'::json)
  );
end $$;

create or replace function public.be_meus_grupos() returns json
language plpgsql security definer set search_path = public as $$
declare v_u uuid := be_usuario_atual_id();
begin
  if v_u is null then raise exception 'faça login de novo'; end if;
  perform be_modo_interno();
  return coalesce((
    select json_agg(json_build_object('id', g.id, 'nome', g.nome, 'materia', g.materia, 'tipo', g.tipo,
             'codigo', g.codigo, 'papel', gm.papel_no_grupo,
             'membros', (select count(*) from be_grupo_membros o where o.grupo_id = g.id))
           order by gm.joined_at desc)
    from be_grupo_membros gm join be_grupos g on g.id = gm.grupo_id
    where gm.usuario_id = v_u
  ), '[]'::json);
end $$;

create or replace function public.be_materia_detalhe(p_materia uuid) returns json
language plpgsql security definer set search_path = public as $$
declare v_u uuid := be_usuario_atual_id(); v_hoje date := be_hoje(); v_m record; v_res json;
begin
  if v_u is null then raise exception 'faça login de novo'; end if;
  perform be_modo_interno();
  select * into v_m from be_materias where id = p_materia;
  if v_m.id is null or not be_materia_acessivel_para(v_u, p_materia) then raise exception 'matéria não encontrada'; end if;

  select json_build_object(
    'materia', json_build_object('id', v_m.id, 'nome', v_m.nome, 'data_prova', v_m.data_prova, 'status', v_m.status,
                                 'nota_real', v_m.nota_real, 'grupo_id', v_m.grupo_id, 'dono', v_m.usuario_id = v_u,
                                 'dias', v_m.data_prova - v_hoje,
                                 'grupo_nome', (select nome from be_grupos where id = v_m.grupo_id)),
    'materiais', coalesce((select json_agg(json_build_object('id', mt.id, 'tipo', mt.tipo, 'created_at', mt.created_at, 'tem_url', mt.url_externa is not null,
                                   'meu', mt.importado_por = v_u) order by mt.created_at desc)
                           from be_materiais mt where mt.materia_id = p_materia), '[]'::json),
    'resumo', (select conteudo from be_conteudo_gerado where materia_id = p_materia and tipo = 'resumo' order by created_at desc limit 1),
    'mapa_mental', (select conteudo from be_conteudo_gerado where materia_id = p_materia and tipo = 'mapa_mental' order by created_at desc limit 1),
    'curiosidades', (select conteudo from be_conteudo_gerado where materia_id = p_materia and tipo = 'curiosidades' order by created_at desc limit 1),
    'quiz', coalesce((select json_agg(json_build_object('id', q.id, 'pergunta', q.pergunta, 'opcoes', q.opcoes,
                                'topico_id', q.topico_id, 'topico', t.nome) order by q.ordem)
                      from be_quiz_perguntas q join be_conteudo_gerado c on c.id = q.conteudo_gerado_id
                      left join be_topicos t on t.id = q.topico_id
                      where c.materia_id = p_materia and c.tipo = 'quiz'), '[]'::json),
    'prova', coalesce((select json_agg(json_build_object('id', q.id, 'pergunta', q.pergunta, 'opcoes', q.opcoes,
                                'topico_id', q.topico_id, 'topico', t.nome) order by q.ordem)
                      from be_quiz_perguntas q join be_conteudo_gerado c on c.id = q.conteudo_gerado_id
                      left join be_topicos t on t.id = q.topico_id
                      where c.materia_id = p_materia and c.tipo = 'prova'), '[]'::json),
    'topicos', coalesce((select json_agg(json_build_object('id', t.id, 'nome', t.nome,
                                'score', coalesce(d.score, 0), 'respondidas', coalesce(d.acertos + d.erros, 0)) order by t.ordem, t.created_at)
                         from be_topicos t left join be_dominio d on d.topico_id = t.id and d.usuario_id = v_u
                         where t.materia_id = p_materia), '[]'::json),
    'cards_total', (select count(*) from be_cards where materia_id = p_materia),
    'cards_pendentes', (select count(*) from be_cards c
                        left join be_card_revisoes cr on cr.card_id = c.id and cr.usuario_id = v_u
                        where c.materia_id = p_materia and (cr.card_id is null or cr.proxima <= v_hoje)),
    'tarefas', coalesce((select json_agg(json_build_object('id', t.id, 'dia', t.dia, 'tipo', t.tipo, 'titulo', t.titulo,
                                 'minutos', t.minutos, 'feita', t.feita_em is not null, 'manual', t.manual, 'topico_id', t.topico_id)
                               order by t.dia, t.ordem)
                         from be_plano_tarefas t where t.materia_id = p_materia and t.usuario_id = v_u and not t.substituida
                           and (t.dia >= v_hoje - 3 or t.feita_em is null)), '[]'::json),
    'resultado', case when v_m.status = 'arquivada' then (
        select json_build_object('respondidas', count(*), 'acertos', count(*) filter (where te.acertou))
        from be_tentativas te join be_quiz_perguntas q on q.id = te.quiz_pergunta_id
        join be_conteudo_gerado c on c.id = q.conteudo_gerado_id
        where te.usuario_id = v_u and c.materia_id = p_materia) else null end
  ) into v_res;
  return v_res;
end $$;

-- fecha as ligas toda segunda 00:05 (horário de Brasília = 03:05 UTC); cron.schedule com nome atualiza se já existir
do $$ begin
  if exists (select 1 from pg_namespace where nspname = 'cron') then
    perform cron.schedule('be-fechar-ligas', '5 3 * * 1', 'select public.be_fechar_ligas();');
  end if;
end $$;
