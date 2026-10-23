-- Estude+ — conta do criador (master).
-- Quem está em be_criadores não tem limite de IA, tutor, publicação nem ritmo de mensagem, pode criar turma ou grupo,
-- vê os números gerais e modera a biblioteca e as salas (liberar, ocultar, silenciar por uns dias).
-- A marca fica numa tabela separada, sem acesso pelo app: ninguém consegue se promover sozinho.
-- Só cria ou substitui (pode rodar de novo). Nada é apagado: moderar é esconder ou liberar.

create table if not exists public.be_criadores (
  usuario_id uuid primary key references public.be_usuarios(id) on delete cascade,
  created_at timestamptz not null default now()
);
alter table public.be_criadores enable row level security;   -- sem políticas: só funções do banco e o service role

create or replace function public.be_eh_criador(p_usuario uuid) returns boolean
language sql stable security definer set search_path = public as $$
  select p_usuario is not null and exists (select 1 from be_criadores where usuario_id = p_usuario)
$$;

create or replace function public.be_sou_criador() returns boolean
language sql stable security definer set search_path = public as $$
  select be_eh_criador(be_usuario_atual_id())
$$;

create or replace function public.be_exigir_criador() returns uuid
language plpgsql stable security definer set search_path = public as $$
declare v_u uuid := be_usuario_atual_id();
begin
  if v_u is null or not be_eh_criador(v_u) then raise exception 'só a conta do criador pode fazer isso' using errcode = '42501'; end if;
  return v_u;
end $$;

-- quem foi silenciado não manda mensagem nem publica resumo até a data
create table if not exists public.be_silenciados (
  usuario_id uuid primary key references public.be_usuarios(id) on delete cascade,
  ate timestamptz not null,
  motivo text,
  por uuid references public.be_usuarios(id) on delete set null,
  created_at timestamptz not null default now()
);
alter table public.be_silenciados enable row level security;  -- sem políticas

create or replace function public.be_silenciado_ate(p_usuario uuid) returns timestamptz
language sql stable security definer set search_path = public as $$
  -- só a própria pessoa e o criador ficam sabendo
  select ate from be_silenciados
  where usuario_id = p_usuario and ate > now()
    and (p_usuario = be_usuario_atual_id() or be_eh_criador(be_usuario_atual_id()))
$$;

-- denúncia revisada sai da fila e para de contar pra esconder
alter table public.be_denuncias add column if not exists resolvida_em timestamptz;
alter table public.be_denuncias add column if not exists decisao text;
create index if not exists be_denuncias_abertas_idx on public.be_denuncias (alvo_tipo, alvo_id) where resolvida_em is null;

-- 3 denúncias ainda abertas, de pessoas diferentes, escondem o resumo ou a mensagem até o criador revisar
create or replace function public.be_denuncia_esconde() returns trigger
language plpgsql security definer set search_path = public as $$
declare v_n int;
begin
  select count(*) into v_n from be_denuncias where alvo_tipo = new.alvo_tipo and alvo_id = new.alvo_id and resolvida_em is null;
  if v_n >= 3 then
    if new.alvo_tipo = 'resumo' then update be_resumos set status = 'oculto', motivo_moderacao = 'denúncias' where id = new.alvo_id and status = 'publicado';
    else update be_sala_mensagens set oculta = true where id = new.alvo_id; end if;
  end if;
  return new;
end $$;

-- XP, nível, sequência, liga e papel só mudam pelas funções do banco, nunca direto pelo app
create or replace function public.be_usuarios_protege() returns trigger
language plpgsql set search_path = public as $$
begin
  if current_user not in ('authenticated', 'anon') then return new; end if;
  if tg_op = 'INSERT' then
    new.xp := 0; new.nivel := 1; new.streak_atual := 0; new.streak_maior := 0; new.ultima_atividade := null; new.divisao := 'bronze';
    if new.papel not in ('aluno', 'professor') then new.papel := 'aluno'; end if;
  else
    new.id := old.id; new.auth_user_id := old.auth_user_id; new.papel := old.papel;
    new.xp := old.xp; new.nivel := old.nivel; new.streak_atual := old.streak_atual; new.streak_maior := old.streak_maior;
    new.ultima_atividade := old.ultima_atividade; new.divisao := old.divisao; new.energia := old.energia;
    new.instituicao_id := old.instituicao_id;
  end if;
  return new;
end $$;
do $$ begin
  if not exists (select 1 from pg_trigger where tgname = 'be_usuarios_protege_trg') then
    create trigger be_usuarios_protege_trg before insert or update on public.be_usuarios for each row execute function public.be_usuarios_protege();
  end if;
end $$;

-- autor em público: o criador aparece com o selo "equipe Estude+"
create or replace function public.be_autor_json(p_usuario uuid) returns json
language sql stable security definer set search_path = public as $$
  select json_build_object('id', u.id, 'nome', be_nome_publico(u.nome), 'iniciais', be_iniciais(u.nome),
                           'nivel', u.nivel, 'professor', u.papel = 'professor', 'equipe', be_eh_criador(u.id))
  from be_usuarios u where u.id = p_usuario and auth.uid() is not null
$$;

-- perfil público: selo da equipe; o criador também vê se a pessoa está silenciada
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
    'equipe', be_eh_criador(v_p.id),
    'silenciado_ate', case when be_eh_criador(v_u) then be_silenciado_ate(v_p.id) end,
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

-- o criador abre qualquer resumo (inclusive escondido) pra revisar, e vê as denúncias abertas dele
create or replace function public.be_resumo_abrir(p_resumo uuid) returns json
language plpgsql security definer set search_path = public as $$
declare v_u uuid := be_usuario_atual_id(); v_r record; v_cri boolean := be_eh_criador(be_usuario_atual_id()); v_conta boolean;
begin
  if v_u is null then raise exception 'faça login de novo'; end if;
  select * into v_r from be_resumos where id = p_resumo;
  if v_r.id is null or (v_r.status <> 'publicado' and v_r.autor_id <> v_u and not v_cri) then raise exception 'esse resumo não está disponível'; end if;
  v_conta := v_r.autor_id <> v_u and v_r.status = 'publicado';
  if v_conta then update be_resumos set visualizacoes = visualizacoes + 1 where id = p_resumo; end if;
  return json_build_object(
    'id', v_r.id, 'titulo', v_r.titulo, 'materia', v_r.materia, 'serie', v_r.serie, 'cor', v_r.cor, 'status', v_r.status,
    'conteudo', v_r.conteudo, 'cartoes', v_r.cartoes, 'created_at', v_r.created_at, 'motivo', v_r.motivo_moderacao,
    'visualizacoes', v_r.visualizacoes + case when v_conta then 1 else 0 end,
    'curtidas', (select count(*) from be_resumo_curtidas where resumo_id = p_resumo),
    'eu_curti', exists (select 1 from be_resumo_curtidas where resumo_id = p_resumo and usuario_id = v_u),
    'salvo', exists (select 1 from be_resumo_salvos where resumo_id = p_resumo and usuario_id = v_u),
    'meu', v_r.autor_id = v_u,
    'eu_sigo', exists (select 1 from be_seguidores where seguidor_id = v_u and seguido_id = v_r.autor_id),
    'autor', be_autor_json(v_r.autor_id),
    'denuncias', case when v_cri then (select count(*) from be_denuncias d where d.alvo_tipo = 'resumo' and d.alvo_id = p_resumo and d.resolvida_em is null) end);
end $$;

-- mensagem: o criador manda link e não tem ritmo; quem está silenciado não manda
create or replace function public.be_enviar_mensagem(p_sala uuid, p_texto text) returns json
language plpgsql security definer set search_path = public as $$
declare
  v_u uuid := be_usuario_atual_id();
  v_t text := btrim(regexp_replace(coalesce(p_texto, ''), '[\r\n]{3,}', E'\n\n', 'g'));
  v_m record;
  v_cri boolean := be_eh_criador(be_usuario_atual_id());
  v_sil timestamptz;
begin
  if v_u is null then raise exception 'faça login de novo'; end if;
  if not be_sala_visivel(p_sala) then raise exception 'sala não encontrada'; end if;
  if char_length(v_t) = 0 then raise exception 'escreve alguma coisa'; end if;
  if char_length(v_t) > 500 then raise exception 'mensagem grande demais (máximo 500 letras)'; end if;
  v_sil := be_silenciado_ate(v_u);
  if v_sil is not null then
    raise exception 'você está sem mandar mensagens até % por causa das regras da comunidade', to_char(v_sil at time zone 'America/Sao_Paulo', 'DD/MM "às" HH24:MI');
  end if;
  if not v_cri then
    -- proteção: sem links, e-mail, @ de rede social ou telefone nas salas (datas e contas passam)
    if v_t ~* '(https?://|www\.|\m[a-z0-9-]+\.(com|net|org|br|io|me|ly|gg|app|xyz)\M|[a-z0-9._%+-]+@[a-z0-9.-]+\.[a-z]{2,}|(^|\s)@[a-z0-9_.]{3,}|(?<![\d.,])\(?\d{2}\)?[\s.-]?9?[\s.]?\d{4}[\s.-]?\d{4}\y|\y9\d{4}[\s.-]?\d{4}\y|(?<![\d.,])\d{10,11}(?!\d))' then
      raise exception 'pra proteger todo mundo, não dá pra mandar link, e-mail, @ de rede social ou telefone aqui';
    end if;
    if exists (select 1 from be_sala_mensagens where usuario_id = v_u and created_at > now() - interval '3 seconds') then
      raise exception 'calma, espera uns segundinhos pra mandar outra';
    end if;
    if (select count(*) from be_sala_mensagens where usuario_id = v_u and created_at > now() - interval '1 minute') >= 12 then
      raise exception 'muitas mensagens seguidas, espera um minuto';
    end if;
  end if;
  insert into be_sala_membros (sala_id, usuario_id) values (p_sala, v_u)
  on conflict (sala_id, usuario_id) do update set ultima_leitura = now();
  insert into be_sala_mensagens (sala_id, usuario_id, texto) values (p_sala, v_u, v_t) returning * into v_m;
  return json_build_object('id', v_m.id, 'texto', v_m.texto, 'created_at', v_m.created_at, 'eu', true, 'autor', be_autor_json(v_u));
end $$;

-- ---------------- PAINEL DO CRIADOR ----------------
create or replace function public.be_painel_criador() returns json
language plpgsql stable security definer set search_path = public as $$
declare v_hoje date := be_hoje(); v_ini timestamptz := (be_hoje()::timestamp at time zone 'America/Sao_Paulo');
begin
  perform be_exigir_criador();
  return json_build_object(
    'numeros', json_build_object(
      'contas', (select count(*) from be_usuarios),
      'professores', (select count(*) from be_usuarios where papel = 'professor'),
      'novos_7d', (select count(*) from be_usuarios where created_at > now() - interval '7 days'),
      'ativos_hoje', (select count(*) from be_usuarios where ultima_atividade = v_hoje),
      'ativos_7d', (select count(*) from be_usuarios where ultima_atividade >= v_hoje - 6),
      'materias', (select count(*) from be_materias),
      'materias_7d', (select count(*) from be_materias where created_at > now() - interval '7 days'),
      'turmas', (select count(*) from be_grupos where tipo = 'turma_professor'),
      'grupos_amigos', (select count(*) from be_grupos where tipo = 'grupo_amigos'),
      'ia_hoje', (select coalesce(sum(quantidade), 0) from be_uso_ia where data = current_date),
      'tutor_hoje', (select coalesce(sum(quantidade), 0) from be_uso_tutor where data = current_date),
      'resumos', (select count(*) from be_resumos where status = 'publicado'),
      'mensagens_hoje', (select count(*) from be_sala_mensagens where created_at >= v_ini),
      'simulados_7d', (select count(*) from be_simulados where iniciado_em > now() - interval '7 days'),
      'redacoes_7d', (select count(*) from be_redacoes where created_at > now() - interval '7 days')),
    'fila_resumos', coalesce((
      select json_agg(x.j order by x.n desc, x.ultima desc) from (
        select count(*) n, max(d.created_at) ultima,
               json_build_object('id', r.id, 'titulo', r.titulo, 'materia', r.materia, 'status', r.status,
                                 'trecho', left(regexp_replace(r.conteudo, '\s+', ' ', 'g'), 160),
                                 'denuncias', count(*), 'motivos', coalesce(json_agg(d.motivo) filter (where d.motivo is not null and d.motivo <> ''), '[]'::json),
                                 'ultima', max(d.created_at), 'autor', be_autor_json(r.autor_id),
                                 'silenciado_ate', be_silenciado_ate(r.autor_id)) j
        from be_denuncias d join be_resumos r on r.id = d.alvo_id
        where d.alvo_tipo = 'resumo' and d.resolvida_em is null
        group by r.id limit 40) x), '[]'::json),
    'fila_mensagens', coalesce((
      select json_agg(x.j order by x.n desc, x.ultima desc) from (
        select count(*) n, max(d.created_at) ultima,
               json_build_object('id', m.id, 'texto', m.texto, 'oculta', m.oculta, 'sala', s.nome, 'created_at', m.created_at,
                                 'denuncias', count(*), 'ultima', max(d.created_at), 'autor', be_autor_json(m.usuario_id),
                                 'silenciado_ate', be_silenciado_ate(m.usuario_id)) j
        from be_denuncias d join be_sala_mensagens m on m.id = d.alvo_id join be_salas s on s.id = m.sala_id
        where d.alvo_tipo = 'mensagem' and d.resolvida_em is null
        group by m.id, s.nome limit 40) x), '[]'::json),
    'silenciados', coalesce((
      select json_agg(json_build_object('autor', be_autor_json(z.usuario_id), 'ate', z.ate, 'motivo', z.motivo) order by z.ate)
      from be_silenciados z where z.ate > now()), '[]'::json));
end $$;

-- liberar (volta a aparecer) ou ocultar (some pra todo mundo); as denúncias abertas daquilo ficam resolvidas
create or replace function public.be_moderar(p_tipo text, p_alvo uuid, p_acao text) returns json
language plpgsql security definer set search_path = public as $$
declare v_u uuid := be_exigir_criador(); v_n int;
begin
  if p_tipo not in ('resumo', 'mensagem') then raise exception 'tipo inválido'; end if;
  if p_acao not in ('liberar', 'ocultar') then raise exception 'ação inválida'; end if;
  if p_tipo = 'resumo' then
    update be_resumos set status = case when p_acao = 'liberar' then 'publicado' else 'oculto' end,
                          motivo_moderacao = case when p_acao = 'liberar' then null else 'revisado pela equipe do Estude+' end
    where id = p_alvo;
  else
    update be_sala_mensagens set oculta = (p_acao = 'ocultar') where id = p_alvo;
  end if;
  get diagnostics v_n = row_count;
  if v_n = 0 then raise exception 'não achei isso, pode já ter sido apagado'; end if;
  update be_denuncias set resolvida_em = now(), decisao = p_acao where alvo_tipo = p_tipo and alvo_id = p_alvo and resolvida_em is null;
  return json_build_object('ok', true, 'acao', p_acao);
end $$;

-- silencia por alguns dias (0 dias = tira o silêncio). O criador não silencia a si mesmo.
create or replace function public.be_silenciar(p_usuario uuid, p_dias int, p_motivo text default null) returns json
language plpgsql security definer set search_path = public as $$
declare v_u uuid := be_exigir_criador(); v_ate timestamptz;
begin
  if p_usuario is null or not exists (select 1 from be_usuarios where id = p_usuario) then raise exception 'pessoa não encontrada'; end if;
  if be_eh_criador(p_usuario) then raise exception 'a conta do criador não pode ser silenciada'; end if;
  if p_dias is null or p_dias < 0 or p_dias > 365 then raise exception 'escolhe de 0 a 365 dias'; end if;
  v_ate := case when p_dias = 0 then now() else now() + make_interval(days => p_dias) end;
  insert into be_silenciados (usuario_id, ate, motivo, por) values (p_usuario, v_ate, left(p_motivo, 200), v_u)
  on conflict (usuario_id) do update set ate = excluded.ate, motivo = excluded.motivo, por = excluded.por, created_at = now();
  return json_build_object('ok', true, 'ate', case when p_dias = 0 then null else v_ate end);
end $$;
