-- Espelho local do que já existe no Supabase (só para testar as migrações)
create extension if not exists pgcrypto;
do $$ begin
  create role anon nologin; exception when duplicate_object then null; end $$;
do $$ begin
  create role authenticated nologin; exception when duplicate_object then null; end $$;
do $$ begin
  create role service_role nologin bypassrls; exception when duplicate_object then null; end $$;
grant usage on schema public to anon, authenticated, service_role;
alter default privileges in schema public grant all on tables to anon, authenticated, service_role;
alter default privileges in schema public grant all on sequences to anon, authenticated, service_role;
alter default privileges in schema public grant execute on functions to anon, authenticated, service_role;

create schema if not exists auth;
grant usage on schema auth to anon, authenticated, service_role;
create table if not exists auth.users (id uuid primary key default gen_random_uuid(), email text);
create or replace function auth.uid() returns uuid language sql stable as $$
  select nullif(current_setting('request.jwt.claim.sub', true), '')::uuid
$$;
grant execute on function auth.uid() to anon, authenticated, service_role;

create table public.be_instituicoes (id uuid primary key default gen_random_uuid(), nome text not null, logo_url text, cor_primaria text default '#2C4870', cor_secundaria text default '#F5C93D', plano text not null default 'free' check (plano in ('free','basico','premium')), limite_ia_diario int, dono_id uuid, created_at timestamptz not null default now());
create table public.be_usuarios (id uuid primary key default gen_random_uuid(), device_id uuid unique, nome text not null, papel text not null check (papel in ('aluno','professor')), escola text, cidade text, nivel int not null default 1, xp int not null default 0, energia int not null default 7, streak_atual int not null default 0, streak_maior int not null default 0, ultima_atividade date, instituicao_id uuid references public.be_instituicoes(id), created_at timestamptz not null default now(), avatar_base64 text, auth_user_id uuid unique references auth.users(id) on delete cascade, pergunta_seguranca text, resposta_seguranca_hash text);
alter table public.be_instituicoes add foreign key (dono_id) references public.be_usuarios(id);
create table public.be_conquistas (id uuid primary key default gen_random_uuid(), codigo text not null unique, nome text not null, descricao text not null, icone text not null default '🏅');
create table public.be_grupos (id uuid primary key default gen_random_uuid(), nome text not null, tipo text not null check (tipo in ('turma_professor','grupo_amigos')), materia text, dono_id uuid not null references public.be_usuarios(id) on delete cascade, codigo text not null unique, permite_upload_aluno boolean not null default true, instituicao_id uuid references public.be_instituicoes(id), created_at timestamptz not null default now());
create table public.be_grupo_membros (id uuid primary key default gen_random_uuid(), grupo_id uuid not null references public.be_grupos(id) on delete cascade, usuario_id uuid not null references public.be_usuarios(id) on delete cascade, papel_no_grupo text not null default 'membro' check (papel_no_grupo in ('admin','membro')), joined_at timestamptz not null default now(), unique (grupo_id, usuario_id));
create table public.be_materias (id uuid primary key default gen_random_uuid(), usuario_id uuid references public.be_usuarios(id) on delete cascade, grupo_id uuid references public.be_grupos(id) on delete cascade, nome text not null, data_prova date, fase_atual int not null default 1, total_fases int not null default 5, created_at timestamptz not null default now(), status text not null default 'ativa' check (status in ('ativa','arquivada')), nota_real numeric, check ((usuario_id is not null and grupo_id is null) or (usuario_id is null and grupo_id is not null)));
create table public.be_materiais (id uuid primary key default gen_random_uuid(), materia_id uuid not null references public.be_materias(id) on delete cascade, tipo text not null check (tipo in ('foto','pdf','youtube','link')), storage_path text, url_externa text, texto_extraido text, importado_por uuid not null references public.be_usuarios(id), created_at timestamptz not null default now());
create table public.be_conteudo_gerado (id uuid primary key default gen_random_uuid(), materia_id uuid not null references public.be_materias(id) on delete cascade, tipo text not null check (tipo in ('quiz','prova','mapa_mental','resumo','curiosidades')), conteudo jsonb not null, created_at timestamptz not null default now());
create table public.be_quiz_perguntas (id uuid primary key default gen_random_uuid(), conteudo_gerado_id uuid not null references public.be_conteudo_gerado(id) on delete cascade, pergunta text not null, opcoes jsonb not null, resposta_correta text not null, explicacao text, ordem int not null default 0);
create table public.be_streak_log (id uuid primary key default gen_random_uuid(), usuario_id uuid not null references public.be_usuarios(id) on delete cascade, data date not null, created_at timestamptz not null default now(), unique (usuario_id, data));
create table public.be_tentativas (id uuid primary key default gen_random_uuid(), usuario_id uuid not null references public.be_usuarios(id) on delete cascade, quiz_pergunta_id uuid not null references public.be_quiz_perguntas(id) on delete cascade, acertou boolean not null, tempo_resposta_ms int, pontos_ganhos int not null default 0, created_at timestamptz not null default now());
create table public.be_uso_ia (id uuid primary key default gen_random_uuid(), usuario_id uuid not null references public.be_usuarios(id) on delete cascade, data date not null default current_date, quantidade int not null default 0, unique (usuario_id, data));
create table public.be_usuario_conquistas (id uuid primary key default gen_random_uuid(), usuario_id uuid not null references public.be_usuarios(id) on delete cascade, conquista_id uuid not null references public.be_conquistas(id) on delete cascade, desbloqueada_em timestamptz not null default now(), unique (usuario_id, conquista_id));

create or replace function public.be_usuario_atual_id() returns uuid language sql stable security definer set search_path to 'public' as $$
  select id from public.be_usuarios where auth_user_id = auth.uid()
$$;
create or replace function public.be_meus_grupos_ids() returns setof uuid language sql stable security definer set search_path to 'public' as $$
  select grupo_id from public.be_grupo_membros where usuario_id = public.be_usuario_atual_id()
$$;
create or replace function public.be_incrementar_uso_ia(p_usuario_id uuid) returns void language sql security definer set search_path to 'public' as $$
  insert into public.be_uso_ia (usuario_id, data, quantidade) values (p_usuario_id, current_date, 1)
  on conflict (usuario_id, data) do update set quantidade = public.be_uso_ia.quantidade + 1;
$$;

alter table public.be_usuarios enable row level security;
alter table public.be_materias enable row level security;
alter table public.be_grupos enable row level security;
alter table public.be_grupo_membros enable row level security;
alter table public.be_quiz_perguntas enable row level security;
alter table public.be_conteudo_gerado enable row level security;
alter table public.be_tentativas enable row level security;
create policy "ver proprio perfil" on public.be_usuarios for select using (auth_user_id = auth.uid());
create policy "ver colegas de grupo" on public.be_usuarios for select using (id in (select gm.usuario_id from public.be_grupo_membros gm where gm.grupo_id in (select public.be_meus_grupos_ids())));
create policy "editar proprio perfil" on public.be_usuarios for update using (auth_user_id = auth.uid());
create policy "ver minhas materias" on public.be_materias for select using ((usuario_id = public.be_usuario_atual_id()) or (grupo_id in (select public.be_meus_grupos_ids())));
create policy "criar materia" on public.be_materias for insert with check ((usuario_id = public.be_usuario_atual_id()) or (grupo_id in (select public.be_meus_grupos_ids())));
create policy "editar minha materia" on public.be_materias for update using ((usuario_id = public.be_usuario_atual_id()) or (grupo_id in (select public.be_meus_grupos_ids())));
create policy "ver grupo pelo codigo" on public.be_grupos for select using (true);
create policy "ver membros dos meus grupos" on public.be_grupo_membros for select using (grupo_id in (select public.be_meus_grupos_ids()));
create policy "ver conteudo gerado" on public.be_conteudo_gerado for select using (materia_id in (select id from public.be_materias where usuario_id = public.be_usuario_atual_id() or grupo_id in (select public.be_meus_grupos_ids())));
create policy "ver perguntas" on public.be_quiz_perguntas for select using (conteudo_gerado_id in (select id from public.be_conteudo_gerado));
create policy "minhas tentativas" on public.be_tentativas for select using (usuario_id = public.be_usuario_atual_id());
create policy "registrar tentativa" on public.be_tentativas for insert with check (usuario_id = public.be_usuario_atual_id());

insert into public.be_conquistas (codigo, nome, descricao, icone) values
 ('dez_materias','10 matérias criadas','Crie 10 matérias de estudo','📚'),
 ('primeiro_lugar_dia','1º lugar no quiz do dia','Termine em primeiro no quiz do dia','🏅'),
 ('streak_30_dias','30 dias seguidos','Estude 30 dias seguidos','🚀'),
 ('cinco_mapas_mentais','5 mapas mentais','Gere 5 mapas mentais','🧠'),
 ('streak_7_dias','7 dias seguidos','Estude 7 dias seguidos','🔥'),
 ('convidou_3_amigos','Convidou 3 amigos','Convide 3 amigos pro grupo','👥'),
 ('coruja_madrugada','Coruja','Estudou depois da meia-noite','🌙'),
 ('simulado_sem_erros','Simulado sem erros','Complete um simulado com 100% de acerto','💯');

-- demais políticas que existem no Supabase
alter table public.be_conquistas enable row level security;
alter table public.be_instituicoes enable row level security;
alter table public.be_materiais enable row level security;
alter table public.be_streak_log enable row level security;
alter table public.be_uso_ia enable row level security;
alter table public.be_usuario_conquistas enable row level security;
create policy "criar proprio perfil" on public.be_usuarios for insert with check (auth_user_id = auth.uid());
create policy "catalogo de conquistas publico" on public.be_conquistas for select using (true);
create policy "entrar em grupo" on public.be_grupo_membros for insert with check (usuario_id = public.be_usuario_atual_id());
create policy "criar grupo" on public.be_grupos for insert with check (dono_id = public.be_usuario_atual_id());
create policy "dono edita grupo" on public.be_grupos for update using (dono_id = public.be_usuario_atual_id());
create policy "ver grupos que participo" on public.be_grupos for select using (id in (select public.be_meus_grupos_ids()));
create policy "ver instituicoes" on public.be_instituicoes for select using (true);
create policy "excluir material que importei" on public.be_materiais for delete using (importado_por = public.be_usuario_atual_id());
create policy "importar material" on public.be_materiais for insert with check (importado_por = public.be_usuario_atual_id());
create policy "ver materiais da materia" on public.be_materiais for select using (materia_id in (select id from public.be_materias where usuario_id = public.be_usuario_atual_id() or grupo_id in (select public.be_meus_grupos_ids())));
create policy "excluir minha materia" on public.be_materias for delete using ((usuario_id = public.be_usuario_atual_id()) or (grupo_id in (select public.be_meus_grupos_ids())));
create policy "registrar streak" on public.be_streak_log for insert with check (usuario_id = public.be_usuario_atual_id());
create policy "ver meu streak" on public.be_streak_log for select using (usuario_id = public.be_usuario_atual_id());
create policy "colegas veem tentativas pro ranking" on public.be_tentativas for select using (usuario_id in (select gm.usuario_id from public.be_grupo_membros gm where gm.grupo_id in (select public.be_meus_grupos_ids())));
create policy "ver meu uso de ia" on public.be_uso_ia for select using (usuario_id = public.be_usuario_atual_id());
create policy "desbloquear conquista" on public.be_usuario_conquistas for insert with check (usuario_id = public.be_usuario_atual_id());
create policy "ver minhas conquistas" on public.be_usuario_conquistas for select using (usuario_id = public.be_usuario_atual_id());
