-- Estude+ (evolução do Bora Estudar) — schema aditivo, prefixo be_
-- Datas do app sempre no fuso de Brasília.

create or replace function public.be_hoje() returns date
language sql stable set search_path = public as $$
  select (now() at time zone 'America/Sao_Paulo')::date
$$;

create or replace function public.be_semana_atual() returns date
language sql stable set search_path = public as $$
  select date_trunc('week', (now() at time zone 'America/Sao_Paulo'))::date
$$;

-- ---------- usuários: preferências de estudo e divisão da liga ----------
alter table public.be_usuarios
  add column if not exists dias_estudo smallint[] not null default '{1,2,3,4,5,6}',
  add column if not exists minutos_por_dia smallint not null default 40,
  add column if not exists divisao text not null default 'bronze';

do $$ begin
  alter table public.be_usuarios add constraint be_usuarios_divisao_check
    check (divisao in ('bronze','prata','ouro','diamante'));
exception when duplicate_object then null; end $$;

-- material colado como texto passa a ser aceito
alter table public.be_materiais drop constraint if exists be_materiais_tipo_check;
alter table public.be_materiais add constraint be_materiais_tipo_check
  check (tipo in ('foto','pdf','youtube','link','texto'));

-- ---------- acesso a uma matéria (dono ou membro do grupo dela) ----------
create or replace function public.be_materia_acessivel(p_materia uuid) returns boolean
language sql stable security definer set search_path = public as $$
  select exists (
    select 1 from public.be_materias m
    where m.id = p_materia
      and (m.usuario_id = public.be_usuario_atual_id()
           or m.grupo_id in (select public.be_meus_grupos_ids()))
  )
$$;

create or replace function public.be_materia_acessivel_para(p_usuario uuid, p_materia uuid) returns boolean
language sql stable security definer set search_path = public as $$
  select exists (
    select 1 from public.be_materias m
    where m.id = p_materia
      and (m.usuario_id = p_usuario
           or m.grupo_id in (select grupo_id from public.be_grupo_membros where usuario_id = p_usuario))
  )
$$;

-- ---------- tópicos ----------
create table if not exists public.be_topicos (
  id uuid primary key default gen_random_uuid(),
  materia_id uuid not null references public.be_materias(id) on delete cascade,
  nome text not null,
  ordem int not null default 0,
  created_at timestamptz not null default now()
);
create unique index if not exists be_topicos_materia_nome_key on public.be_topicos (materia_id, lower(nome));

alter table public.be_quiz_perguntas
  add column if not exists topico_id uuid references public.be_topicos(id) on delete set null;

-- ---------- domínio por tópico ----------
create table if not exists public.be_dominio (
  usuario_id uuid not null references public.be_usuarios(id) on delete cascade,
  topico_id uuid not null references public.be_topicos(id) on delete cascade,
  acertos int not null default 0,
  erros int not null default 0,
  score numeric(4,3) not null default 0,
  atualizado_em timestamptz not null default now(),
  primary key (usuario_id, topico_id)
);
create index if not exists be_dominio_topico_idx on public.be_dominio (topico_id);

-- ---------- flashcards + repetição espaçada (FSRS) ----------
create table if not exists public.be_cards (
  id uuid primary key default gen_random_uuid(),
  materia_id uuid not null references public.be_materias(id) on delete cascade,
  topico_id uuid references public.be_topicos(id) on delete set null,
  frente text not null,
  verso text not null,
  origem text not null default 'ia' check (origem in ('ia','manual')),
  criado_por uuid references public.be_usuarios(id) on delete set null,
  created_at timestamptz not null default now()
);
create unique index if not exists be_cards_materia_frente_key on public.be_cards (materia_id, lower(frente));
create index if not exists be_cards_topico_idx on public.be_cards (topico_id);

create table if not exists public.be_card_revisoes (
  usuario_id uuid not null references public.be_usuarios(id) on delete cascade,
  card_id uuid not null references public.be_cards(id) on delete cascade,
  estado smallint not null default 0,          -- 0 novo · 1 aprendendo · 2 revisão · 3 reaprendendo
  estabilidade real not null default 0,
  dificuldade real not null default 0,
  repeticoes int not null default 0,
  lapsos int not null default 0,
  ultima_revisao timestamptz,
  proxima date not null default current_date,
  primary key (usuario_id, card_id)
);
create index if not exists be_card_revisoes_proxima_idx on public.be_card_revisoes (usuario_id, proxima);
create index if not exists be_card_revisoes_card_idx on public.be_card_revisoes (card_id);

-- ---------- plano de prova ----------
create table if not exists public.be_plano_tarefas (
  id uuid primary key default gen_random_uuid(),
  usuario_id uuid not null references public.be_usuarios(id) on delete cascade,
  materia_id uuid not null references public.be_materias(id) on delete cascade,
  dia date not null,
  tipo text not null check (tipo in ('estudar','quiz','cards','prova','revisao_geral')),
  topico_id uuid references public.be_topicos(id) on delete set null,
  titulo text not null,
  minutos smallint not null default 15,
  ordem smallint not null default 0,
  feita_em timestamptz,
  manual boolean not null default false,
  created_at timestamptz not null default now()
);
create index if not exists be_plano_tarefas_usuario_dia_idx on public.be_plano_tarefas (usuario_id, dia);
create index if not exists be_plano_tarefas_materia_idx on public.be_plano_tarefas (materia_id);

-- ---------- XP, liga semanal ----------
create table if not exists public.be_xp_eventos (
  id bigint generated always as identity primary key,
  usuario_id uuid not null references public.be_usuarios(id) on delete cascade,
  tipo text not null,
  pontos int not null,
  ref_id uuid,
  created_at timestamptz not null default now()
);
create index if not exists be_xp_eventos_usuario_idx on public.be_xp_eventos (usuario_id, created_at);

create table if not exists public.be_ligas (
  id uuid primary key default gen_random_uuid(),
  semana date not null,
  divisao text not null check (divisao in ('bronze','prata','ouro','diamante')),
  fechada boolean not null default false,
  created_at timestamptz not null default now()
);
create index if not exists be_ligas_semana_idx on public.be_ligas (semana, divisao);

create table if not exists public.be_liga_membros (
  liga_id uuid not null references public.be_ligas(id) on delete cascade,
  usuario_id uuid not null references public.be_usuarios(id) on delete cascade,
  xp_semana int not null default 0,
  posicao int,
  resultado text check (resultado in ('subiu','ficou','caiu')),
  entrou_em timestamptz not null default now(),
  primary key (liga_id, usuario_id)
);
create index if not exists be_liga_membros_usuario_idx on public.be_liga_membros (usuario_id);

-- ---------- ENEM ----------
create table if not exists public.be_enem_questoes (
  id uuid primary key default gen_random_uuid(),
  ano smallint not null,
  numero smallint not null,
  idioma text,
  area text not null check (area in ('linguagens','ciencias-humanas','ciencias-natureza','matematica')),
  contexto text,
  introducao text,
  alternativas jsonb not null,
  gabarito text not null check (gabarito in ('A','B','C','D','E'))
);
create unique index if not exists be_enem_questoes_key on public.be_enem_questoes (ano, numero, coalesce(idioma, ''));
create index if not exists be_enem_questoes_area_idx on public.be_enem_questoes (area, ano);

create table if not exists public.be_simulados (
  id uuid primary key default gen_random_uuid(),
  usuario_id uuid not null references public.be_usuarios(id) on delete cascade,
  area text,
  modo text not null default 'rapido',
  questoes uuid[] not null,
  respostas jsonb not null default '{}'::jsonb,
  acertos int,
  total int not null,
  duracao_seg int,
  iniciado_em timestamptz not null default now(),
  finalizado_em timestamptz
);
create index if not exists be_simulados_usuario_idx on public.be_simulados (usuario_id, iniciado_em desc);

create table if not exists public.be_redacoes (
  id uuid primary key default gen_random_uuid(),
  usuario_id uuid not null references public.be_usuarios(id) on delete cascade,
  tema text not null,
  texto text not null,
  notas jsonb,
  total int,
  feedback jsonb,
  created_at timestamptz not null default now()
);
create index if not exists be_redacoes_usuario_idx on public.be_redacoes (usuario_id, created_at desc);

-- ---------- conquistas novas ----------
insert into public.be_conquistas (codigo, nome, descricao, icone)
select v.codigo, v.nome, v.descricao, v.icone from (values
  ('primeiro_simulado_enem', 'Primeiro simulado ENEM', 'Termine um simulado do ENEM', '🎯'),
  ('redacao_800', 'Redação 800+', 'Tire 800 ou mais numa redação corrigida', '✍️'),
  ('cem_cards', '100 cards revisados', 'Revise 100 flashcards', '🗂️'),
  ('subiu_de_liga', 'Subiu de liga', 'Termine a semana na zona de promoção', '⬆️'),
  ('plano_em_dia', 'Plano em dia', 'Conclua todas as tarefas do plano num dia', '✅')
) as v(codigo, nome, descricao, icone)
where not exists (select 1 from public.be_conquistas c where c.codigo = v.codigo);

-- ---------- RLS ----------
alter table public.be_topicos enable row level security;
alter table public.be_dominio enable row level security;
alter table public.be_cards enable row level security;
alter table public.be_card_revisoes enable row level security;
alter table public.be_plano_tarefas enable row level security;
alter table public.be_xp_eventos enable row level security;
alter table public.be_ligas enable row level security;
alter table public.be_liga_membros enable row level security;
alter table public.be_enem_questoes enable row level security;
alter table public.be_simulados enable row level security;
alter table public.be_redacoes enable row level security;

drop policy if exists "ver topicos" on public.be_topicos;
create policy "ver topicos" on public.be_topicos for select to authenticated
  using (public.be_materia_acessivel(materia_id));
drop policy if exists "criar topico" on public.be_topicos;
create policy "criar topico" on public.be_topicos for insert to authenticated
  with check (public.be_materia_acessivel(materia_id));

drop policy if exists "ver meu dominio" on public.be_dominio;
create policy "ver meu dominio" on public.be_dominio for select to authenticated
  using (usuario_id = public.be_usuario_atual_id());

drop policy if exists "ver cards" on public.be_cards;
create policy "ver cards" on public.be_cards for select to authenticated
  using (public.be_materia_acessivel(materia_id));
drop policy if exists "criar card" on public.be_cards;
create policy "criar card" on public.be_cards for insert to authenticated
  with check (public.be_materia_acessivel(materia_id) and criado_por = public.be_usuario_atual_id() and origem = 'manual');
drop policy if exists "editar meu card" on public.be_cards;
create policy "editar meu card" on public.be_cards for update to authenticated
  using (criado_por = public.be_usuario_atual_id());
drop policy if exists "excluir card" on public.be_cards;
create policy "excluir card" on public.be_cards for delete to authenticated
  using (criado_por = public.be_usuario_atual_id()
         or materia_id in (select id from public.be_materias where usuario_id = public.be_usuario_atual_id()));

drop policy if exists "ver minhas revisoes" on public.be_card_revisoes;
create policy "ver minhas revisoes" on public.be_card_revisoes for select to authenticated
  using (usuario_id = public.be_usuario_atual_id());

drop policy if exists "ver meu plano" on public.be_plano_tarefas;
create policy "ver meu plano" on public.be_plano_tarefas for select to authenticated
  using (usuario_id = public.be_usuario_atual_id());
drop policy if exists "criar tarefa" on public.be_plano_tarefas;
create policy "criar tarefa" on public.be_plano_tarefas for insert to authenticated
  with check (usuario_id = public.be_usuario_atual_id() and public.be_materia_acessivel(materia_id));
drop policy if exists "editar tarefa" on public.be_plano_tarefas;
create policy "editar tarefa" on public.be_plano_tarefas for update to authenticated
  using (usuario_id = public.be_usuario_atual_id())
  with check (usuario_id = public.be_usuario_atual_id());
drop policy if exists "excluir tarefa" on public.be_plano_tarefas;
create policy "excluir tarefa" on public.be_plano_tarefas for delete to authenticated
  using (usuario_id = public.be_usuario_atual_id());

drop policy if exists "ver meu xp" on public.be_xp_eventos;
create policy "ver meu xp" on public.be_xp_eventos for select to authenticated
  using (usuario_id = public.be_usuario_atual_id());

drop policy if exists "ver meus simulados" on public.be_simulados;
create policy "ver meus simulados" on public.be_simulados for select to authenticated
  using (usuario_id = public.be_usuario_atual_id());

drop policy if exists "ver minhas redacoes" on public.be_redacoes;
create policy "ver minhas redacoes" on public.be_redacoes for select to authenticated
  using (usuario_id = public.be_usuario_atual_id());
-- be_ligas, be_liga_membros e be_enem_questoes: sem políticas — só via funções.

-- energia de IA: só a função do servidor incrementa
revoke execute on function public.be_incrementar_uso_ia(uuid) from public, anon, authenticated;
grant execute on function public.be_incrementar_uso_ia(uuid) to service_role;
revoke execute on function public.be_materia_acessivel_para(uuid, uuid) from public, anon, authenticated;
grant execute on function public.be_materia_acessivel_para(uuid, uuid) to service_role;
