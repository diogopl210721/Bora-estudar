-- EstudeUp — biblioteca de resumos, tutor de IA e comunidade.
-- Só cria ou substitui (pode rodar de novo). Nomes públicos aparecem como "Ana S." e sem foto, por causa dos alunos menores.

alter table public.be_usuarios add column if not exists serie text;

create or replace function public.be_nome_publico(p_nome text) returns text
language sql immutable set search_path = '' as $$
  -- em público só o primeiro nome e a inicial do sobrenome: "Ana Paula Souza" vira "Ana S."
  with p as (select regexp_split_to_array(btrim(coalesce(p_nome, '')), '\s+') a)
  select case when a[1] = '' then 'Estudante'
              when array_length(a, 1) > 1 then a[1] || ' ' || upper(left(a[array_length(a, 1)], 1)) || '.'
              else a[1] end from p
$$;
create or replace function public.be_iniciais(p_nome text) returns text
language sql immutable set search_path = '' as $$
  with p as (select regexp_split_to_array(btrim(coalesce(p_nome, '')), '\s+') a)
  select case when a[1] = '' then '?'
              else upper(left(a[1], 1) || case when array_length(a, 1) > 1 then left(a[array_length(a, 1)], 1) else '' end) end from p
$$;

-- =========================================================
-- BIBLIOTECA DE RESUMOS
-- =========================================================
create table if not exists public.be_resumos (
  id uuid primary key default gen_random_uuid(),
  autor_id uuid not null references public.be_usuarios(id) on delete cascade,
  titulo text not null check (char_length(titulo) between 3 and 120),
  materia text not null check (char_length(materia) between 2 and 60),
  serie text,
  conteudo text not null check (char_length(conteudo) between 80 and 20000),
  cartoes jsonb not null default '[]'::jsonb,
  cor text not null default 'azul' check (cor in ('azul', 'verde', 'rosa', 'laranja', 'roxo', 'amarelo')),
  origem_materia_id uuid references public.be_materias(id) on delete set null,
  status text not null default 'publicado' check (status in ('publicado', 'oculto', 'recusado')),
  motivo_moderacao text,
  visualizacoes int not null default 0,
  created_at timestamptz not null default now(),
  busca tsvector generated always as (
    to_tsvector('portuguese', coalesce(titulo, '') || ' ' || coalesce(materia, '') || ' ' || coalesce(conteudo, ''))
  ) stored
);
create index if not exists be_resumos_busca_idx on public.be_resumos using gin (busca);
create index if not exists be_resumos_status_idx on public.be_resumos (status, created_at desc);
create index if not exists be_resumos_autor_idx on public.be_resumos (autor_id);

create table if not exists public.be_resumo_curtidas (
  resumo_id uuid not null references public.be_resumos(id) on delete cascade,
  usuario_id uuid not null references public.be_usuarios(id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (resumo_id, usuario_id)
);
-- quem já deu XP ao autor por curtir (curtir, descurtir e curtir de novo não rende XP de novo)
create table if not exists public.be_resumo_curtidas_xp (
  resumo_id uuid not null references public.be_resumos(id) on delete cascade,
  usuario_id uuid not null references public.be_usuarios(id) on delete cascade,
  primary key (resumo_id, usuario_id)
);
create table if not exists public.be_resumo_salvos (
  resumo_id uuid not null references public.be_resumos(id) on delete cascade,
  usuario_id uuid not null references public.be_usuarios(id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (resumo_id, usuario_id)
);
create table if not exists public.be_seguidores (
  seguidor_id uuid not null references public.be_usuarios(id) on delete cascade,
  seguido_id uuid not null references public.be_usuarios(id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (seguidor_id, seguido_id),
  check (seguidor_id <> seguido_id)
);
create table if not exists public.be_bloqueios (
  usuario_id uuid not null references public.be_usuarios(id) on delete cascade,
  bloqueado_id uuid not null references public.be_usuarios(id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (usuario_id, bloqueado_id),
  check (usuario_id <> bloqueado_id)
);
create table if not exists public.be_denuncias (
  id uuid primary key default gen_random_uuid(),
  usuario_id uuid not null references public.be_usuarios(id) on delete cascade,
  alvo_tipo text not null check (alvo_tipo in ('resumo', 'mensagem')),
  alvo_id uuid not null,
  motivo text,
  created_at timestamptz not null default now(),
  unique (usuario_id, alvo_tipo, alvo_id)
);

-- =========================================================
-- TUTOR DE IA
-- =========================================================
create table if not exists public.be_tutor_conversas (
  id uuid primary key default gen_random_uuid(),
  usuario_id uuid not null references public.be_usuarios(id) on delete cascade,
  materia text,
  titulo text not null default 'Nova conversa',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create index if not exists be_tutor_conversas_usuario_idx on public.be_tutor_conversas (usuario_id, updated_at desc);
create table if not exists public.be_tutor_mensagens (
  id uuid primary key default gen_random_uuid(),
  conversa_id uuid not null references public.be_tutor_conversas(id) on delete cascade,
  papel text not null check (papel in ('aluno', 'tutor')),
  texto text not null,
  tinha_foto boolean not null default false,
  created_at timestamptz not null default now()
);
create index if not exists be_tutor_mensagens_conversa_idx on public.be_tutor_mensagens (conversa_id, created_at);
create table if not exists public.be_uso_tutor (
  usuario_id uuid not null references public.be_usuarios(id) on delete cascade,
  data date not null default current_date,
  quantidade int not null default 0,
  primary key (usuario_id, data)
);

-- =========================================================
-- COMUNIDADE
-- =========================================================
create table if not exists public.be_salas (
  id uuid primary key default gen_random_uuid(),
  nome text not null,
  descricao text,
  materia text,
  icone text not null default '💬',
  grupo_id uuid references public.be_grupos(id) on delete cascade,
  oficial boolean not null default false,
  ordem int not null default 100,
  created_at timestamptz not null default now()
);
create unique index if not exists be_salas_grupo_uidx on public.be_salas (grupo_id) where grupo_id is not null;
create unique index if not exists be_salas_oficial_uidx on public.be_salas (nome) where oficial;
create table if not exists public.be_sala_membros (
  sala_id uuid not null references public.be_salas(id) on delete cascade,
  usuario_id uuid not null references public.be_usuarios(id) on delete cascade,
  entrou_em timestamptz not null default now(),
  ultima_leitura timestamptz not null default now(),
  primary key (sala_id, usuario_id)
);
create table if not exists public.be_sala_mensagens (
  id uuid primary key default gen_random_uuid(),
  sala_id uuid not null references public.be_salas(id) on delete cascade,
  usuario_id uuid not null references public.be_usuarios(id) on delete cascade,
  texto text not null check (char_length(texto) between 1 and 500),
  oculta boolean not null default false,
  created_at timestamptz not null default now()
);
create index if not exists be_sala_mensagens_sala_idx on public.be_sala_mensagens (sala_id, created_at desc);
create index if not exists be_sala_mensagens_usuario_idx on public.be_sala_mensagens (usuario_id, created_at desc);

insert into public.be_salas (nome, descricao, materia, icone, oficial, ordem)
select v.nome, v.descricao, v.materia, v.icone, true, v.ordem from (values
  ('ENEM 2026', 'Contagem regressiva, dicas e dúvidas da prova', null, '🎯', 1),
  ('Redação', 'Temas, repertório e estrutura do texto', 'Redação', '✍️', 2),
  ('Matemática', 'Exercícios, fórmulas e macetes', 'Matemática', '📐', 3),
  ('Português e Literatura', 'Gramática, interpretação e obras', 'Português', '📚', 4),
  ('Biologia', 'Células, genética, ecologia e corpo humano', 'Biologia', '🧬', 5),
  ('Química', 'Orgânica, estequiometria e tabela periódica', 'Química', '⚗️', 6),
  ('Física', 'Cinemática, energia, elétrica e ondas', 'Física', '🧲', 7),
  ('História', 'Brasil, geral e atualidades', 'História', '🏛️', 8),
  ('Geografia', 'Mapas, clima, população e geopolítica', 'Geografia', '🌎', 9),
  ('Inglês e Espanhol', 'Vocabulário, textos e dicas de prova', 'Inglês', '🗣️', 10),
  ('Vestibulares', 'Fuvest, Unicamp, UFPR e outros', null, '🎓', 11),
  ('Dúvidas rápidas', 'Travou num exercício? Pergunta aqui', null, '❓', 12)
) as v(nome, descricao, materia, icone, ordem)
where not exists (select 1 from public.be_salas s where s.oficial and s.nome = v.nome);

insert into public.be_conquistas (codigo, nome, descricao, icone)
select v.codigo, v.nome, v.descricao, v.icone from (values
  ('primeiro_resumo', 'Autor(a)', 'Publique seu primeiro resumo na biblioteca', '📝'),
  ('dez_curtidas', '10 curtidas', 'Receba 10 curtidas nos seus resumos', '❤️'),
  ('tutor_curioso', 'Curioso(a)', 'Faça 10 perguntas ao tutor', '🤖')
) as v(codigo, nome, descricao, icone)
where not exists (select 1 from public.be_conquistas c where c.codigo = v.codigo);

-- =========================================================
-- RLS
-- =========================================================
alter table public.be_resumos enable row level security;
alter table public.be_resumo_curtidas enable row level security;
alter table public.be_resumo_curtidas_xp enable row level security;
alter table public.be_resumo_salvos enable row level security;
alter table public.be_seguidores enable row level security;
alter table public.be_bloqueios enable row level security;
alter table public.be_denuncias enable row level security;
alter table public.be_tutor_conversas enable row level security;
alter table public.be_tutor_mensagens enable row level security;
alter table public.be_uso_tutor enable row level security;
alter table public.be_salas enable row level security;
alter table public.be_sala_membros enable row level security;
alter table public.be_sala_mensagens enable row level security;

do $$ begin
  -- resumos: lê os publicados e os próprios; publicar passa pela moderação (função de IA); o autor pode apagar o seu
  if not exists (select 1 from pg_policies where tablename = 'be_resumos' and policyname = 'ver resumos publicados') then
    create policy "ver resumos publicados" on public.be_resumos for select to authenticated
      using (status = 'publicado' or autor_id = public.be_usuario_atual_id());
  end if;
  if not exists (select 1 from pg_policies where tablename = 'be_resumos' and policyname = 'apagar meu resumo') then
    create policy "apagar meu resumo" on public.be_resumos for delete to authenticated
      using (autor_id = public.be_usuario_atual_id());
  end if;
  -- curtidas e salvos: cada um mexe só nos seus
  if not exists (select 1 from pg_policies where tablename = 'be_resumo_curtidas' and policyname = 'minhas curtidas') then
    create policy "minhas curtidas" on public.be_resumo_curtidas for select to authenticated using (usuario_id = public.be_usuario_atual_id());
    create policy "curtir" on public.be_resumo_curtidas for insert to authenticated
      with check (usuario_id = public.be_usuario_atual_id() and exists (select 1 from public.be_resumos r where r.id = resumo_id and r.status = 'publicado'));
    create policy "descurtir" on public.be_resumo_curtidas for delete to authenticated using (usuario_id = public.be_usuario_atual_id());
  end if;
  if not exists (select 1 from pg_policies where tablename = 'be_resumo_salvos' and policyname = 'meus salvos') then
    create policy "meus salvos" on public.be_resumo_salvos for select to authenticated using (usuario_id = public.be_usuario_atual_id());
    create policy "salvar" on public.be_resumo_salvos for insert to authenticated
      with check (usuario_id = public.be_usuario_atual_id() and exists (select 1 from public.be_resumos r where r.id = resumo_id and (r.status = 'publicado' or r.autor_id = usuario_id)));
    create policy "tirar dos salvos" on public.be_resumo_salvos for delete to authenticated using (usuario_id = public.be_usuario_atual_id());
  end if;
  if not exists (select 1 from pg_policies where tablename = 'be_seguidores' and policyname = 'ver quem sigo') then
    create policy "ver quem sigo" on public.be_seguidores for select to authenticated
      using (seguidor_id = public.be_usuario_atual_id() or seguido_id = public.be_usuario_atual_id());
    create policy "seguir" on public.be_seguidores for insert to authenticated with check (seguidor_id = public.be_usuario_atual_id());
    create policy "deixar de seguir" on public.be_seguidores for delete to authenticated using (seguidor_id = public.be_usuario_atual_id());
  end if;
  if not exists (select 1 from pg_policies where tablename = 'be_bloqueios' and policyname = 'meus bloqueios') then
    create policy "meus bloqueios" on public.be_bloqueios for select to authenticated using (usuario_id = public.be_usuario_atual_id());
    create policy "bloquear" on public.be_bloqueios for insert to authenticated with check (usuario_id = public.be_usuario_atual_id());
    create policy "desbloquear" on public.be_bloqueios for delete to authenticated using (usuario_id = public.be_usuario_atual_id());
  end if;
  -- tutor: só o dono lê e apaga; quem grava é a função de IA
  if not exists (select 1 from pg_policies where tablename = 'be_tutor_conversas' and policyname = 'minhas conversas') then
    create policy "minhas conversas" on public.be_tutor_conversas for select to authenticated using (usuario_id = public.be_usuario_atual_id());
    create policy "apagar minha conversa" on public.be_tutor_conversas for delete to authenticated using (usuario_id = public.be_usuario_atual_id());
  end if;
  if not exists (select 1 from pg_policies where tablename = 'be_tutor_mensagens' and policyname = 'mensagens das minhas conversas') then
    create policy "mensagens das minhas conversas" on public.be_tutor_mensagens for select to authenticated
      using (conversa_id in (select id from public.be_tutor_conversas where usuario_id = public.be_usuario_atual_id()));
  end if;
  if not exists (select 1 from pg_policies where tablename = 'be_uso_tutor' and policyname = 'meu uso do tutor') then
    create policy "meu uso do tutor" on public.be_uso_tutor for select to authenticated using (usuario_id = public.be_usuario_atual_id());
  end if;
  -- salas: as oficiais pra todo mundo logado, as de turma só pra quem é da turma
  if not exists (select 1 from pg_policies where tablename = 'be_salas' and policyname = 'ver salas') then
    create policy "ver salas" on public.be_salas for select to authenticated
      using (grupo_id is null or grupo_id in (select public.be_meus_grupos_ids()));
  end if;
  if not exists (select 1 from pg_policies where tablename = 'be_sala_membros' and policyname = 'minhas salas') then
    create policy "minhas salas" on public.be_sala_membros for select to authenticated using (usuario_id = public.be_usuario_atual_id());
    create policy "sair da sala" on public.be_sala_membros for delete to authenticated using (usuario_id = public.be_usuario_atual_id());
  end if;
  -- mensagens: leitura direta (para o tempo real); envio só pela rpc, que filtra link e telefone
  if not exists (select 1 from pg_policies where tablename = 'be_sala_mensagens' and policyname = 'ler mensagens das salas') then
    create policy "ler mensagens das salas" on public.be_sala_mensagens for select to authenticated
      using (not oculta and sala_id in (select s.id from public.be_salas s where s.grupo_id is null or s.grupo_id in (select public.be_meus_grupos_ids())));
  end if;
end $$;

-- =========================================================
-- GATILHOS
-- =========================================================
-- curtida nova dá 2 XP pro autor (uma vez por pessoa por resumo, nunca pra si mesmo)
create or replace function public.be_curtida_xp() returns trigger
language plpgsql security definer set search_path = public as $$
declare v_autor uuid; v_n int; v_total int;
begin
  select autor_id into v_autor from be_resumos where id = new.resumo_id;
  if v_autor is null or v_autor = new.usuario_id then return new; end if;
  insert into be_resumo_curtidas_xp (resumo_id, usuario_id) values (new.resumo_id, new.usuario_id) on conflict do nothing;
  get diagnostics v_n = row_count;
  if v_n > 0 then
    perform be_modo_interno();
    perform be_ganhar_xp(v_autor, 'curtida', 2, new.resumo_id);
    select count(*) into v_total from be_resumo_curtidas c join be_resumos r on r.id = c.resumo_id where r.autor_id = v_autor;
    if v_total >= 10 then perform be_conceder_conquista(v_autor, 'dez_curtidas'); end if;
    perform set_config('be.interno', '', true);
  end if;
  return new;
end $$;
do $$ begin
  if not exists (select 1 from pg_trigger where tgname = 'be_curtida_xp_trg') then
    create trigger be_curtida_xp_trg after insert on public.be_resumo_curtidas for each row execute function public.be_curtida_xp();
  end if;
end $$;

-- 3 denúncias de pessoas diferentes escondem o resumo ou a mensagem até alguém revisar
create or replace function public.be_denuncia_esconde() returns trigger
language plpgsql security definer set search_path = public as $$
declare v_n int;
begin
  select count(*) into v_n from be_denuncias where alvo_tipo = new.alvo_tipo and alvo_id = new.alvo_id;
  if v_n >= 3 then
    if new.alvo_tipo = 'resumo' then update be_resumos set status = 'oculto', motivo_moderacao = 'denúncias' where id = new.alvo_id and status = 'publicado';
    else update be_sala_mensagens set oculta = true where id = new.alvo_id; end if;
  end if;
  return new;
end $$;
do $$ begin
  if not exists (select 1 from pg_trigger where tgname = 'be_denuncia_esconde_trg') then
    create trigger be_denuncia_esconde_trg after insert on public.be_denuncias for each row execute function public.be_denuncia_esconde();
  end if;
end $$;
