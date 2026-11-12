-- =====================================================================================
-- EstudeUp · 16: Aprenda Inglês (trilha de lições, revisão do que errou e XP)
-- O conteúdo das lições fica no app (site/ingles-conteudo.js); aqui só o progresso de cada pessoa.
-- Só acrescenta tabelas e funções novas.
-- =====================================================================================

create table if not exists public.be_ingles_licoes (
  usuario_id uuid not null references public.be_usuarios(id) on delete cascade,
  licao text not null check (licao ~ '^u[0-9]{1,2}l[0-9]{1,2}$'),
  vezes int not null default 1,
  melhor int not null default 0,          -- melhor % de acerto
  pulada boolean not null default false,  -- liberada pelo teste de nível
  primeira_em timestamptz not null default now(),
  ultima_em timestamptz not null default now(),
  primary key (usuario_id, licao)
);

-- palavras e frases que a pessoa errou: voltam na revisão até ela acertar 2 vezes seguidas
create table if not exists public.be_ingles_erros (
  usuario_id uuid not null references public.be_usuarios(id) on delete cascade,
  item text not null check (length(item) between 1 and 200),
  erros int not null default 1,
  acertos_seguidos int not null default 0,
  atualizado_em timestamptz not null default now(),
  primary key (usuario_id, item)
);

alter table public.be_ingles_licoes enable row level security;
alter table public.be_ingles_erros enable row level security;
revoke all on public.be_ingles_licoes, public.be_ingles_erros from anon, authenticated;

-- o que o app lê: lições feitas e o que está para revisar
create or replace function public.be_ingles_progresso()
returns json language plpgsql security definer set search_path = public as $$
declare v_u uuid := be_usuario_atual_id();
begin
  if v_u is null then raise exception 'faça login de novo'; end if;
  return json_build_object(
    'licoes', coalesce((select json_object_agg(licao, json_build_object('vezes', vezes, 'melhor', melhor, 'pulada', pulada))
                        from be_ingles_licoes where usuario_id = v_u), '{}'::json),
    'revisar', coalesce((select json_agg(item order by erros desc, atualizado_em desc)
                         from (select item, erros, atualizado_em from be_ingles_erros
                               where usuario_id = v_u and acertos_seguidos < 2 order by erros desc, atualizado_em desc limit 30) e), '[]'::json),
    'xp_hoje', coalesce((select sum(pontos) from be_xp_eventos where usuario_id = v_u and tipo = 'ingles'
                         and created_at >= (be_hoje()::timestamp at time zone 'America/Sao_Paulo')), 0));
end $$;

-- fim de uma lição (ou da revisão, ou do teste de nível)
-- p_tipo: 'licao' | 'revisao' | 'nivel'; p_errados e p_acertados: itens em inglês para a revisão
create or replace function public.be_ingles_concluir(p_tipo text, p_licao text, p_acertos int, p_total int,
  p_errados text[] default '{}', p_acertados text[] default '{}', p_liberar text[] default '{}')
returns json language plpgsql security definer set search_path = public as $$
declare
  v_u uuid := be_usuario_atual_id();
  v_pct int; v_xp int := 0; v_hoje_xp int; v_item text;
begin
  if v_u is null then raise exception 'faça login de novo'; end if;
  if p_tipo not in ('licao', 'revisao', 'nivel') then raise exception 'tipo inválido'; end if;
  if p_total is null or p_total < 1 or p_total > 60 or p_acertos is null or p_acertos < 0 or p_acertos > p_total then
    raise exception 'resultado inválido';
  end if;
  v_pct := round(100.0 * p_acertos / p_total);

  if p_tipo = 'licao' and p_licao is null then
    v_xp := 0; -- lição não terminada (acabaram as vidas): só guarda o que errou pra revisão
  elsif p_tipo = 'licao' then
    if p_licao !~ '^u[0-9]{1,2}l[0-9]{1,2}$' then raise exception 'lição inválida'; end if;
    insert into be_ingles_licoes (usuario_id, licao, melhor) values (v_u, p_licao, v_pct)
    on conflict (usuario_id, licao) do update set vezes = be_ingles_licoes.vezes + 1,
      melhor = greatest(be_ingles_licoes.melhor, v_pct), ultima_em = now();
    v_xp := 10 + least(p_acertos, 10);
  elsif p_tipo = 'revisao' then
    v_xp := 5 + least(p_acertos, 10);
  elsif p_tipo = 'nivel' and v_pct >= 80 and p_total >= 8 then
    -- passou no teste: libera as lições pedidas (só ids válidos, marcadas como puladas)
    insert into be_ingles_licoes (usuario_id, licao, melhor, pulada)
    select v_u, l, 0, true from unnest(p_liberar) l where l ~ '^u[0-9]{1,2}l[0-9]{1,2}$'
    on conflict (usuario_id, licao) do nothing;
  end if;

  -- revisão: errou volta pra lista; acertou conta seguidas
  foreach v_item in array coalesce(p_errados, '{}') loop
    continue when v_item is null or length(v_item) not between 1 and 200;
    insert into be_ingles_erros (usuario_id, item) values (v_u, v_item)
    on conflict (usuario_id, item) do update set erros = be_ingles_erros.erros + 1, acertos_seguidos = 0, atualizado_em = now();
  end loop;
  update be_ingles_erros set acertos_seguidos = acertos_seguidos + 1, atualizado_em = now()
  where usuario_id = v_u and item = any(coalesce(p_acertados, '{}'));

  -- XP do inglês: no máximo 150 por dia (conta na sequência e na liga como o resto do app)
  select coalesce(sum(pontos), 0) into v_hoje_xp from be_xp_eventos
  where usuario_id = v_u and tipo = 'ingles' and created_at >= (be_hoje()::timestamp at time zone 'America/Sao_Paulo');
  v_xp := greatest(0, least(v_xp, 150 - v_hoje_xp));
  if v_xp > 0 then
    perform be_modo_interno();
    perform be_ganhar_xp(v_u, 'ingles', v_xp, null);
  end if;
  return json_build_object('xp', v_xp, 'pct', v_pct, 'passou', p_tipo <> 'nivel' or (v_pct >= 80 and p_total >= 8));
end $$;

revoke execute on function public.be_ingles_progresso() from public, anon;
revoke execute on function public.be_ingles_concluir(text, text, int, int, text[], text[], text[]) from public, anon;
grant execute on function public.be_ingles_progresso() to authenticated;
grant execute on function public.be_ingles_concluir(text, text, int, int, text[], text[], text[]) to authenticated;
