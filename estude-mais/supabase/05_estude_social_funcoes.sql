-- Estude+ — funções da biblioteca, do tutor e da comunidade. Só cria ou substitui.

-- ---------------- BIBLIOTECA ----------------
create or replace function public.be_autor_json(p_usuario uuid) returns json
language sql stable security definer set search_path = public as $$
  select json_build_object('id', u.id, 'nome', be_nome_publico(u.nome), 'iniciais', be_iniciais(u.nome),
                           'nivel', u.nivel, 'professor', u.papel = 'professor')
  from be_usuarios u where u.id = p_usuario and auth.uid() is not null
$$;

create or replace function public.be_feed_resumos(
  p_busca text default null, p_materia text default null, p_serie text default null,
  p_ordem text default 'populares', p_limite int default 20, p_offset int default 0
) returns json
language plpgsql stable security definer set search_path = public as $$
declare
  v_u uuid := be_usuario_atual_id();
  v_q tsquery;
  v_busca text := nullif(trim(coalesce(p_busca, '')), '');
  v_res json;
begin
  if v_u is null then raise exception 'faça login de novo'; end if;
  if p_ordem not in ('populares', 'recentes', 'seguindo', 'salvos', 'meus') then raise exception 'ordem inválida'; end if;
  if v_busca is not null then v_q := websearch_to_tsquery('portuguese', v_busca); end if;

  with base as (
    select r.id, r.titulo, r.materia, r.serie, r.cor, r.status, r.autor_id, r.created_at, r.visualizacoes,
           left(regexp_replace(r.conteudo, '\s+', ' ', 'g'), 190) as trecho,
           jsonb_array_length(r.cartoes) as n_cartoes,
           (select count(*) from be_resumo_curtidas c where c.resumo_id = r.id) as curtidas,
           exists (select 1 from be_resumo_curtidas c where c.resumo_id = r.id and c.usuario_id = v_u) as eu_curti,
           exists (select 1 from be_resumo_salvos s where s.resumo_id = r.id and s.usuario_id = v_u) as salvo,
           case when v_q is not null then ts_rank(r.busca, v_q) else 0 end as relevancia
    from be_resumos r
    where (r.status = 'publicado' or (p_ordem = 'meus' and r.autor_id = v_u))
      and (p_ordem <> 'meus' or r.autor_id = v_u)
      and (p_ordem <> 'seguindo' or r.autor_id in (select seguido_id from be_seguidores where seguidor_id = v_u))
      and (p_ordem <> 'salvos' or exists (select 1 from be_resumo_salvos s where s.resumo_id = r.id and s.usuario_id = v_u))
      and (p_materia is null or lower(r.materia) = lower(p_materia))
      and (p_serie is null or r.serie = p_serie)
      and (v_busca is null or r.busca @@ v_q or r.titulo ilike '%' || v_busca || '%' or r.materia ilike '%' || v_busca || '%')
      and r.autor_id not in (select bloqueado_id from be_bloqueios where usuario_id = v_u)
  ), ordenado as (
    select b.*
    from base b
    order by
      case when v_busca is not null then b.relevancia end desc nulls last,
      case when p_ordem = 'populares' then (b.curtidas * 3 + b.visualizacoes * 0.25 + 1) / power(extract(epoch from (now() - b.created_at)) / 3600 + 4, 0.55) end desc nulls last,
      b.created_at desc
    limit least(greatest(coalesce(p_limite, 20), 1), 50) offset greatest(coalesce(p_offset, 0), 0)
  )
  select coalesce(json_agg(json_build_object(
           'id', o.id, 'titulo', o.titulo, 'materia', o.materia, 'serie', o.serie, 'cor', o.cor, 'status', o.status,
           'trecho', o.trecho, 'n_cartoes', o.n_cartoes, 'curtidas', o.curtidas, 'eu_curti', o.eu_curti, 'salvo', o.salvo,
           'visualizacoes', o.visualizacoes, 'created_at', o.created_at, 'meu', o.autor_id = v_u,
           'autor', be_autor_json(o.autor_id))), '[]'::json)
    into v_res
  from ordenado o;
  return v_res;
end $$;

create or replace function public.be_resumo_abrir(p_resumo uuid) returns json
language plpgsql security definer set search_path = public as $$
declare v_u uuid := be_usuario_atual_id(); v_r record;
begin
  if v_u is null then raise exception 'faça login de novo'; end if;
  select * into v_r from be_resumos where id = p_resumo;
  if v_r.id is null or (v_r.status <> 'publicado' and v_r.autor_id <> v_u) then raise exception 'esse resumo não está disponível'; end if;
  if v_r.autor_id <> v_u then update be_resumos set visualizacoes = visualizacoes + 1 where id = p_resumo; end if;
  return json_build_object(
    'id', v_r.id, 'titulo', v_r.titulo, 'materia', v_r.materia, 'serie', v_r.serie, 'cor', v_r.cor, 'status', v_r.status,
    'conteudo', v_r.conteudo, 'cartoes', v_r.cartoes, 'created_at', v_r.created_at, 'motivo', v_r.motivo_moderacao,
    'visualizacoes', v_r.visualizacoes + case when v_r.autor_id <> v_u then 1 else 0 end,
    'curtidas', (select count(*) from be_resumo_curtidas where resumo_id = p_resumo),
    'eu_curti', exists (select 1 from be_resumo_curtidas where resumo_id = p_resumo and usuario_id = v_u),
    'salvo', exists (select 1 from be_resumo_salvos where resumo_id = p_resumo and usuario_id = v_u),
    'meu', v_r.autor_id = v_u,
    'eu_sigo', exists (select 1 from be_seguidores where seguidor_id = v_u and seguido_id = v_r.autor_id),
    'autor', be_autor_json(v_r.autor_id));
end $$;

create or replace function public.be_perfil_publico(p_usuario uuid) returns json
language plpgsql stable security definer set search_path = public as $$
declare v_u uuid := be_usuario_atual_id(); v_p record;
begin
  if v_u is null then raise exception 'faça login de novo'; end if;
  select id, nome, nivel, xp, divisao, papel, serie into v_p from be_usuarios where id = p_usuario;
  if v_p.id is null then raise exception 'perfil não encontrado'; end if;
  return json_build_object(
    'id', v_p.id, 'nome', be_nome_publico(v_p.nome), 'iniciais', be_iniciais(v_p.nome), 'nivel', v_p.nivel, 'xp', v_p.xp,
    'divisao', v_p.divisao, 'professor', v_p.papel = 'professor', 'serie', v_p.serie, 'eh_eu', v_p.id = v_u,
    'seguidores', (select count(*) from be_seguidores where seguido_id = p_usuario),
    'seguindo', (select count(*) from be_seguidores where seguidor_id = p_usuario),
    'eu_sigo', exists (select 1 from be_seguidores where seguidor_id = v_u and seguido_id = p_usuario),
    'bloqueado', exists (select 1 from be_bloqueios where usuario_id = v_u and bloqueado_id = p_usuario),
    'curtidas_recebidas', (select count(*) from be_resumo_curtidas c join be_resumos r on r.id = c.resumo_id where r.autor_id = p_usuario),
    'resumos', coalesce((select json_agg(json_build_object('id', r.id, 'titulo', r.titulo, 'materia', r.materia, 'cor', r.cor,
                          'serie', r.serie, 'curtidas', (select count(*) from be_resumo_curtidas c where c.resumo_id = r.id),
                          'visualizacoes', r.visualizacoes, 'created_at', r.created_at) order by r.created_at desc)
                        from be_resumos r where r.autor_id = p_usuario and r.status = 'publicado'), '[]'::json));
end $$;

create or replace function public.be_materias_biblioteca() returns json
language sql stable security definer set search_path = public as $$
  select coalesce(json_agg(json_build_object('materia', materia, 'n', n) order by n desc, materia), '[]'::json)
  from (select initcap(lower(materia)) as materia, count(*) n from be_resumos where status = 'publicado' and auth.uid() is not null group by 1 order by 2 desc limit 30) x
$$;

create or replace function public.be_denunciar(p_tipo text, p_alvo uuid, p_motivo text default null) returns boolean
language plpgsql security definer set search_path = public as $$
declare v_u uuid := be_usuario_atual_id(); v_n int;
begin
  if v_u is null then raise exception 'faça login de novo'; end if;
  if p_tipo not in ('resumo', 'mensagem') then raise exception 'tipo inválido'; end if;
  if p_tipo = 'resumo' and not exists (select 1 from be_resumos where id = p_alvo) then raise exception 'resumo não encontrado'; end if;
  if p_tipo = 'mensagem' and not exists (select 1 from be_sala_mensagens where id = p_alvo) then raise exception 'mensagem não encontrada'; end if;
  insert into be_denuncias (usuario_id, alvo_tipo, alvo_id, motivo) values (v_u, p_tipo, p_alvo, left(p_motivo, 300))
  on conflict do nothing;
  get diagnostics v_n = row_count;
  return v_n > 0;
end $$;

-- ---------------- TUTOR ----------------
create or replace function public.be_tutor_conversas_lista() returns json
language plpgsql stable security definer set search_path = public as $$
declare v_u uuid := be_usuario_atual_id();
begin
  if v_u is null then raise exception 'faça login de novo'; end if;
  return coalesce((
    select json_agg(json_build_object('id', c.id, 'titulo', c.titulo, 'materia', c.materia, 'updated_at', c.updated_at,
             'ultima', (select left(m.texto, 120) from be_tutor_mensagens m where m.conversa_id = c.id order by m.created_at desc limit 1),
             'mensagens', (select count(*) from be_tutor_mensagens m where m.conversa_id = c.id))
           order by c.updated_at desc)
    from be_tutor_conversas c where c.usuario_id = v_u), '[]'::json);
end $$;

-- ---------------- COMUNIDADE ----------------
create or replace function public.be_sala_visivel(p_sala uuid) returns boolean
language sql stable security definer set search_path = public as $$
  select exists (select 1 from be_salas s where s.id = p_sala
                 and (s.grupo_id is null or s.grupo_id in (select grupo_id from be_grupo_membros where usuario_id = be_usuario_atual_id())))
$$;

create or replace function public.be_salas_lista() returns json
language plpgsql security definer set search_path = public as $$
declare v_u uuid := be_usuario_atual_id();
begin
  if v_u is null then raise exception 'faça login de novo'; end if;
  -- toda turma ou grupo de que a pessoa participa ganha uma sala própria
  insert into be_salas (nome, descricao, materia, icone, grupo_id, ordem)
  select g.nome, case when g.tipo = 'turma_professor' then 'Sala da turma' else 'Sala do grupo' end, g.materia,
         case when g.tipo = 'turma_professor' then '🏫' else '👥' end, g.id, 0
  from be_grupos g join be_grupo_membros gm on gm.grupo_id = g.id and gm.usuario_id = v_u
  where not exists (select 1 from be_salas s where s.grupo_id = g.id)
  on conflict do nothing;

  return coalesce((
    select json_agg(x.j order by x.turma desc, x.entrei desc, x.ordem, x.nome)
    from (
      select s.nome, s.ordem, s.grupo_id is not null as turma,
             exists (select 1 from be_sala_membros m where m.sala_id = s.id and m.usuario_id = v_u) as entrei,
             json_build_object(
               'id', s.id, 'nome', s.nome, 'descricao', s.descricao, 'icone', s.icone, 'materia', s.materia,
               'turma', s.grupo_id is not null, 'oficial', s.oficial,
               'membros', (select count(*) from be_sala_membros m where m.sala_id = s.id),
               'entrei', exists (select 1 from be_sala_membros m where m.sala_id = s.id and m.usuario_id = v_u),
               -- não lidas: desde a última leitura; na sala da turma conta tudo até a pessoa abrir a primeira vez
               'nao_lidas', (select count(*) from be_sala_mensagens msg
                             where msg.sala_id = s.id and not msg.oculta and msg.usuario_id <> v_u
                               and msg.usuario_id not in (select bloqueado_id from be_bloqueios where usuario_id = v_u)
                               and msg.created_at > coalesce((select m.ultima_leitura from be_sala_membros m where m.sala_id = s.id and m.usuario_id = v_u),
                                                             case when s.grupo_id is not null then '-infinity'::timestamptz else 'infinity'::timestamptz end)),
               'ultima', (select json_build_object('texto', left(msg.texto, 90), 'autor', be_nome_publico(u.nome), 'created_at', msg.created_at)
                          from be_sala_mensagens msg join be_usuarios u on u.id = msg.usuario_id
                          where msg.sala_id = s.id and not msg.oculta
                            and msg.usuario_id not in (select bloqueado_id from be_bloqueios where usuario_id = v_u)
                          order by msg.created_at desc limit 1)
             ) as j
      from be_salas s
      where s.grupo_id is null or s.grupo_id in (select grupo_id from be_grupo_membros where usuario_id = v_u)
    ) x), '[]'::json);
end $$;

create or replace function public.be_mensagens_sala(p_sala uuid, p_depois timestamptz default null, p_limite int default 60) returns json
language plpgsql security definer set search_path = public as $$
declare v_u uuid := be_usuario_atual_id(); v_s record;
begin
  if v_u is null then raise exception 'faça login de novo'; end if;
  if not be_sala_visivel(p_sala) then raise exception 'sala não encontrada'; end if;
  select id, nome, descricao, icone, grupo_id into v_s from be_salas where id = p_sala;
  insert into be_sala_membros (sala_id, usuario_id) values (p_sala, v_u)
  on conflict (sala_id, usuario_id) do update set ultima_leitura = now();
  return json_build_object(
    'sala', json_build_object('id', v_s.id, 'nome', v_s.nome, 'descricao', v_s.descricao, 'icone', v_s.icone, 'turma', v_s.grupo_id is not null,
                              'membros', (select count(*) from be_sala_membros where sala_id = p_sala)),
    'mensagens', coalesce((
      select json_agg(json_build_object('id', x.id, 'texto', x.texto, 'created_at', x.created_at, 'eu', x.usuario_id = v_u,
                                        'autor', be_autor_json(x.usuario_id)) order by x.created_at)
      from (select m.* from be_sala_mensagens m
            where m.sala_id = p_sala and not m.oculta and (p_depois is null or m.created_at > p_depois)
              and m.usuario_id not in (select bloqueado_id from be_bloqueios where usuario_id = v_u)
            order by m.created_at desc limit least(greatest(coalesce(p_limite, 60), 1), 100)) x), '[]'::json));
end $$;

create or replace function public.be_enviar_mensagem(p_sala uuid, p_texto text) returns json
language plpgsql security definer set search_path = public as $$
declare
  v_u uuid := be_usuario_atual_id();
  v_t text := btrim(regexp_replace(coalesce(p_texto, ''), '[\r\n]{3,}', E'\n\n', 'g'));
  v_m record;
begin
  if v_u is null then raise exception 'faça login de novo'; end if;
  if not be_sala_visivel(p_sala) then raise exception 'sala não encontrada'; end if;
  if char_length(v_t) = 0 then raise exception 'escreve alguma coisa'; end if;
  if char_length(v_t) > 500 then raise exception 'mensagem grande demais (máximo 500 letras)'; end if;
  -- proteção: sem links, e-mail, @ de rede social ou telefone nas salas abertas
  if v_t ~* '(https?://|www\.|\m[a-z0-9-]+\.(com|net|org|br|io|me|ly|gg|app|xyz)\M|[a-z0-9._%+-]+@[a-z0-9.-]+\.[a-z]{2,}|(^|\s)@[a-z0-9_.]{3,}|(?<![\d.,])\(?\d{2}\)?[\s.-]?9?[\s.]?\d{4}[\s.-]?\d{4}\y|\y9\d{4}[\s.-]?\d{4}\y|(?<![\d.,])\d{10,11}(?!\d))' then
    raise exception 'pra proteger todo mundo, não dá pra mandar link, e-mail, @ de rede social ou telefone aqui';
  end if;
  if exists (select 1 from be_sala_mensagens where usuario_id = v_u and created_at > now() - interval '3 seconds') then
    raise exception 'calma, espera uns segundinhos pra mandar outra';
  end if;
  if (select count(*) from be_sala_mensagens where usuario_id = v_u and created_at > now() - interval '1 minute') >= 12 then
    raise exception 'muitas mensagens seguidas, espera um minuto';
  end if;
  insert into be_sala_membros (sala_id, usuario_id) values (p_sala, v_u)
  on conflict (sala_id, usuario_id) do update set ultima_leitura = now();
  insert into be_sala_mensagens (sala_id, usuario_id, texto) values (p_sala, v_u, v_t) returning * into v_m;
  return json_build_object('id', v_m.id, 'texto', v_m.texto, 'created_at', v_m.created_at, 'eu', true, 'autor', be_autor_json(v_u));
end $$;

create or replace function public.be_bloquear(p_usuario uuid) returns boolean
language plpgsql security definer set search_path = public as $$
declare v_u uuid := be_usuario_atual_id();
begin
  if v_u is null then raise exception 'faça login de novo'; end if;
  if p_usuario = v_u then raise exception 'não dá pra bloquear você mesmo'; end if;
  insert into be_bloqueios (usuario_id, bloqueado_id) values (v_u, p_usuario) on conflict do nothing;
  return true;
end $$;

-- tempo real nas salas (o app também busca a cada poucos segundos, então isso é só um acelerador)
do $$ begin
  if exists (select 1 from pg_publication where pubname = 'supabase_realtime')
     and not exists (select 1 from pg_publication_tables where pubname = 'supabase_realtime' and tablename = 'be_sala_mensagens') then
    alter publication supabase_realtime add table public.be_sala_mensagens;
  end if;
end $$;
