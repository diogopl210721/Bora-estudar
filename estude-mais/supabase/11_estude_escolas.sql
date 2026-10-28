-- EstudeUp — escolas parceiras.
-- Página pública da escola, mural de oportunidades, painel da escola (dados, oportunidades, turmas, números, plano),
-- planos e contratos configuráveis, contatos comerciais, métricas de visualização e clique, histórico de ações.
-- Só cria ou acrescenta (pode rodar de novo). Nada é apagado: escola e oportunidade mudam de status.
-- Todo acesso passa por funções que conferem quem é quem; as tabelas novas não têm acesso direto pelo app.

-- =========================================================
-- INSTITUIÇÕES (a tabela be_instituicoes já existia, vazia, do Bora Estudar)
-- =========================================================
alter table public.be_instituicoes
  add column if not exists slug text,
  add column if not exists tipo text not null default 'escola',
  add column if not exists status text not null default 'pendente',
  add column if not exists demo boolean not null default false,
  add column if not exists descricao text,
  add column if not exists cidade text,
  add column if not exists uf text,
  add column if not exists regiao text,
  add column if not exists endereco text,
  add column if not exists modalidades text[] not null default '{}',
  add column if not exists publico text,
  add column if not exists cursos jsonb not null default '[]'::jsonb,
  add column if not exists site text,
  add column if not exists instagram text,
  add column if not exists facebook text,
  add column if not exists whatsapp text,
  add column if not exists telefone text,
  add column if not exists email_contato text,
  add column if not exists capa_url text,
  add column if not exists codigo_professor text,
  add column if not exists aprovada_em timestamptz,
  add column if not exists updated_at timestamptz not null default now();

do $$ begin
  alter table public.be_instituicoes add constraint be_instituicoes_tipo_check
    check (tipo in ('escola', 'cursinho', 'idiomas', 'profissionalizante', 'faculdade', 'reforco', 'outro'));
exception when duplicate_object then null; end $$;
do $$ begin
  alter table public.be_instituicoes add constraint be_instituicoes_status_check
    check (status in ('pendente', 'aprovada', 'recusada', 'suspensa', 'desativada'));
exception when duplicate_object then null; end $$;
do $$ begin
  alter table public.be_instituicoes add constraint be_instituicoes_slug_check check (slug ~ '^[a-z0-9]+(-[a-z0-9]+)*$');
exception when duplicate_object then null; end $$;
create unique index if not exists be_instituicoes_slug_uidx on public.be_instituicoes (slug);
create unique index if not exists be_instituicoes_codigo_prof_uidx on public.be_instituicoes (codigo_professor) where codigo_professor is not null;
create index if not exists be_instituicoes_status_idx on public.be_instituicoes (status, cidade);
alter table public.be_instituicoes enable row level security;
-- as regras antigas do Bora Estudar deixavam qualquer conta ler, criar e editar a própria instituição direto na tabela
-- (inclusive se aprovar sozinha e ler o código dos professores). Esta regra restritiva fecha a tabela pro app;
-- tudo passa pelas funções abaixo. As regras antigas ficam lá, sem efeito.
do $$ begin
  if not exists (select 1 from pg_policies where tablename = 'be_instituicoes' and policyname = 'escolas: so pelas funcoes') then
    create policy "escolas: so pelas funcoes" on public.be_instituicoes as restrictive for all to anon, authenticated using (false) with check (false);
  end if;
end $$;

-- quem é da escola: gestor (cuida da página, oportunidades e números) e professor (cria turmas da escola)
create table if not exists public.be_instituicao_membros (
  instituicao_id uuid not null references public.be_instituicoes(id) on delete cascade,
  usuario_id uuid not null references public.be_usuarios(id) on delete cascade,
  papel text not null check (papel in ('gestor', 'professor')),
  ativo boolean not null default true,
  created_at timestamptz not null default now(),
  primary key (instituicao_id, usuario_id)
);
create index if not exists be_instituicao_membros_usuario_idx on public.be_instituicao_membros (usuario_id) where ativo;
alter table public.be_instituicao_membros enable row level security;

-- =========================================================
-- OPORTUNIDADES (mural)
-- =========================================================
create table if not exists public.be_oportunidades (
  id uuid primary key default gen_random_uuid(),
  instituicao_id uuid not null references public.be_instituicoes(id) on delete cascade,
  titulo text not null check (char_length(titulo) between 4 and 120),
  descricao text not null check (char_length(descricao) between 10 and 2000),
  categoria text not null check (categoria in ('bolsa', 'desconto', 'matricula', 'curso_novo', 'preparatorio', 'profissionalizante',
                                               'aula_experimental', 'evento', 'campanha', 'outro')),
  imagem_url text,
  local text,
  online boolean not null default false,
  inicio date not null,
  fim date not null,
  regras text,
  link text,
  contato text,
  status text not null default 'rascunho' check (status in ('rascunho', 'pendente', 'publicada', 'pausada', 'encerrada', 'recusada', 'suspensa')),
  motivo_status text,
  aprovada_em timestamptz,
  criado_por uuid references public.be_usuarios(id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  check (fim >= inicio)
);
create index if not exists be_oportunidades_ativas_idx on public.be_oportunidades (status, fim, inicio);
create index if not exists be_oportunidades_inst_idx on public.be_oportunidades (instituicao_id, created_at desc);
alter table public.be_oportunidades enable row level security;

-- =========================================================
-- PLANOS E CONTRATOS (cobrança manual por enquanto)
-- =========================================================
create table if not exists public.be_planos (
  id uuid primary key default gen_random_uuid(),
  codigo text not null unique check (codigo ~ '^[a-z0-9_]+$'),
  nome text not null,
  descricao text,
  preco_mensal numeric(10, 2),
  recursos jsonb not null default '[]'::jsonb,
  limite_oportunidades int not null default 1 check (limite_oportunidades >= 0),
  limite_alunos int check (limite_alunos is null or limite_alunos >= 0),
  destaque int not null default 0 check (destaque between 0 and 3),
  relatorios text not null default 'basico' check (relatorios in ('basico', 'ampliado', 'completo')),
  ativo boolean not null default true,
  ordem int not null default 0,
  updated_at timestamptz not null default now()
);
alter table public.be_planos enable row level security;

insert into public.be_planos (codigo, nome, descricao, preco_mensal, recursos, limite_oportunidades, limite_alunos, destaque, relatorios, ordem)
select v.codigo, v.nome, v.descricao, v.preco, v.recursos::jsonb, v.lim_op, v.lim_al, v.destaque, v.rel, v.ordem from (values
  ('presenca', 'Presença', 'Página da escola no EstudeUp e as turmas dos seus alunos estudando com plano até a prova.', 99.00,
   '["Página da escola com contato","Turmas da escola no EstudeUp (plano de estudo, quiz, flashcards, simulado ENEM)","Até 2 oportunidades ativas no mural","Visualizações e cliques"]',
   2, 150, 0, 'basico', 1),
  ('destaque', 'Destaque', 'Tudo do Presença, com mais alunos, mais oportunidades e destaque no mural.', 199.00,
   '["Tudo do Presença","Até 5 oportunidades ativas","Destaque visual no mural","Números por oportunidade e por período"]',
   5, 400, 1, 'ampliado', 2),
  ('premium', 'Premium', 'Tudo do Destaque, sem limite de alunos e com o maior destaque do mural.', 399.00,
   '["Tudo do Destaque","Até 15 oportunidades ativas","Alunos sem limite","Destaque máximo no mural e na página inicial","Relatório completo"]',
   15, null, 2, 'completo', 3)
) as v(codigo, nome, descricao, preco, recursos, lim_op, lim_al, destaque, rel, ordem)
where not exists (select 1 from public.be_planos p where p.codigo = v.codigo);

create table if not exists public.be_assinaturas (
  instituicao_id uuid primary key references public.be_instituicoes(id) on delete cascade,
  plano_id uuid references public.be_planos(id),
  status text not null default 'interessado' check (status in ('interessado', 'negociacao', 'ativo', 'pendente', 'cancelado')),
  pagamento text not null default 'nao_se_aplica' check (pagamento in ('nao_se_aplica', 'em_dia', 'pendente', 'atrasado', 'isento')),
  valor_mensal numeric(10, 2),
  vigencia_inicio date,
  vigencia_fim date,
  observacao text,
  updated_at timestamptz not null default now(),
  check (vigencia_fim is null or vigencia_inicio is null or vigencia_fim >= vigencia_inicio)
);
alter table public.be_assinaturas enable row level security;

-- =========================================================
-- CONTATOS COMERCIAIS (formulário "Quero ser escola parceira")
-- =========================================================
create table if not exists public.be_leads (
  id uuid primary key default gen_random_uuid(),
  instituicao text not null,
  responsavel text not null,
  email text not null,
  telefone text not null,
  cidade text not null,
  tipo text not null,
  mensagem text,
  consentimento boolean not null check (consentimento),
  consentimento_texto text not null,
  status text not null default 'novo' check (status in ('novo', 'em_contato', 'convertido', 'descartado')),
  nota text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create index if not exists be_leads_status_idx on public.be_leads (status, created_at desc);
create index if not exists be_leads_email_idx on public.be_leads (lower(email), created_at desc);
alter table public.be_leads enable row level security;

-- =========================================================
-- MÉTRICAS (no máximo 1 por pessoa, por dia, por item)
-- =========================================================
create table if not exists public.be_vitrine_eventos (
  id bigint generated always as identity primary key,
  tipo text not null check (tipo in ('ver_escola', 'ver_oportunidade', 'clique_contato')),
  instituicao_id uuid not null references public.be_instituicoes(id) on delete cascade,
  oportunidade_id uuid references public.be_oportunidades(id) on delete cascade,
  visitante uuid not null,
  logado boolean not null default false,
  dia date not null,
  created_at timestamptz not null default now()
);
create unique index if not exists be_vitrine_eventos_uidx on public.be_vitrine_eventos
  (tipo, instituicao_id, coalesce(oportunidade_id, '00000000-0000-0000-0000-000000000000'::uuid), visitante, dia);
create index if not exists be_vitrine_eventos_inst_idx on public.be_vitrine_eventos (instituicao_id, dia);
create index if not exists be_vitrine_eventos_visitante_idx on public.be_vitrine_eventos (visitante, dia);
alter table public.be_vitrine_eventos enable row level security;

-- =========================================================
-- HISTÓRICO E CONFIGURAÇÕES
-- =========================================================
create table if not exists public.be_registro_acoes (
  id bigint generated always as identity primary key,
  usuario_id uuid references public.be_usuarios(id) on delete set null,
  papel text not null,
  acao text not null,
  alvo_tipo text,
  alvo_id uuid,
  instituicao_id uuid references public.be_instituicoes(id) on delete set null,
  detalhe jsonb,
  created_at timestamptz not null default now()
);
create index if not exists be_registro_acoes_idx on public.be_registro_acoes (created_at desc);
create index if not exists be_registro_acoes_inst_idx on public.be_registro_acoes (instituicao_id, created_at desc);
alter table public.be_registro_acoes enable row level security;

create table if not exists public.be_config_comercial (
  chave text primary key check (chave in ('whatsapp_comercial', 'email_comercial', 'limite_sem_plano', 'mensagem_whatsapp', 'mostrar_precos')),
  valor text,
  updated_at timestamptz not null default now()
);
alter table public.be_config_comercial enable row level security;
insert into public.be_config_comercial (chave, valor) values
  ('limite_sem_plano', '1'),
  ('mostrar_precos', 'nao'),
  ('mensagem_whatsapp', 'Olá! Vi o EstudeUp e quero apresentar minha escola.')
on conflict (chave) do nothing;

-- turma da escola: só quem é professor ou gestor ativo da escola liga uma turma a ela
create or replace function public.be_sou_da_escola(p_inst uuid, p_papel text default null) returns boolean
language sql stable security definer set search_path = public as $$
  select p_inst is not null and exists (
    select 1 from be_instituicao_membros m join be_instituicoes i on i.id = m.instituicao_id
    where m.instituicao_id = p_inst and m.usuario_id = be_usuario_atual_id() and m.ativo
      and (p_papel is null or m.papel = p_papel))
$$;

do $$ begin
  if not exists (select 1 from pg_policies where tablename = 'be_grupos' and policyname = 'escola: turma so de quem e da escola') then
    create policy "escola: turma so de quem e da escola" on public.be_grupos as restrictive for insert to authenticated
      with check (instituicao_id is null or public.be_sou_da_escola(instituicao_id));
  end if;
  if not exists (select 1 from pg_policies where tablename = 'be_grupos' and policyname = 'escola: mudar turma so quem e da escola') then
    create policy "escola: mudar turma so quem e da escola" on public.be_grupos as restrictive for update to authenticated
      with check (instituicao_id is null or public.be_sou_da_escola(instituicao_id));
  end if;
end $$;

-- =========================================================
-- AJUDANTES
-- =========================================================
-- grava no histórico (só funciona de dentro das funções do banco: a tabela não tem acesso pelo app)
create or replace function public.be_registrar_acao(p_papel text, p_acao text, p_alvo_tipo text, p_alvo_id uuid, p_inst uuid, p_detalhe jsonb default null)
returns void language sql set search_path = public as $$
  insert into be_registro_acoes (usuario_id, papel, acao, alvo_tipo, alvo_id, instituicao_id, detalhe)
  values (be_usuario_atual_id(), p_papel, p_acao, p_alvo_tipo, p_alvo_id, p_inst, p_detalhe)
$$;

create or replace function public.be_slug(p_texto text) returns text
language sql immutable set search_path = public as $$
  select trim(both '-' from regexp_replace(lower(translate(coalesce(p_texto, ''),
    'ÁÀÂÃÄáàâãäÉÈÊËéèêëÍÌÎÏíìîïÓÒÔÕÖóòôõöÚÙÛÜúùûüÇçÑñ', 'AAAAAaaaaaEEEEeeeeIIIIiiiiOOOOOoooooUUUUuuuuCcNn')), '[^a-z0-9]+', '-', 'g'))
$$;

create or replace function public.be_slug_livre(p_base text, p_inst uuid default null) returns text
language plpgsql stable security definer set search_path = public as $$
declare v_base text := left(nullif(be_slug(p_base), ''), 60); v_s text; v_n int := 1;
begin
  if v_base is null then v_base := 'escola'; end if;
  v_s := v_base;
  while exists (select 1 from be_instituicoes where slug = v_s and id is distinct from p_inst) loop
    v_n := v_n + 1; v_s := v_base || '-' || v_n;
  end loop;
  return v_s;
end $$;

create or replace function public.be_codigo_aleatorio(p_tam int default 6) returns text
language sql volatile set search_path = public as $$
  select string_agg(substr('ABCDEFGHJKLMNPQRSTUVWXYZ23456789', 1 + floor(random() * 32)::int, 1), '') from generate_series(1, p_tam)
$$;

-- texto limpo: tira espaços das pontas, junta espaços e corta no tamanho
create or replace function public.be_txt(p jsonb, p_chave text, p_max int) returns text
language sql immutable set search_path = public as $$
  select nullif(left(btrim(regexp_replace(coalesce(p ->> p_chave, ''), '[ \t]+', ' ', 'g')), p_max), '')
$$;

-- link externo: só https/http com domínio
create or replace function public.be_url_ok(p text) returns boolean
language sql immutable set search_path = public as $$
  select p is null or p ~* '^https?://[a-z0-9.-]+\.[a-z]{2,}(/[^\s]*)?$'
$$;

create or replace function public.be_so_digitos(p text) returns text
language sql immutable set search_path = public as $$
  select nullif(regexp_replace(coalesce(p, ''), '\D', '', 'g'), '')
$$;

-- plano que vale hoje pra escola (ativo e dentro da vigência)
create or replace function public.be_plano_da_escola(p_inst uuid) returns public.be_planos
language sql stable security definer set search_path = public as $$
  select p.* from be_assinaturas a join be_planos p on p.id = a.plano_id
  where a.instituicao_id = p_inst and a.status = 'ativo'
    and (a.vigencia_inicio is null or a.vigencia_inicio <= be_hoje())
    and (a.vigencia_fim is null or a.vigencia_fim >= be_hoje())
$$;

create or replace function public.be_limite_oportunidades(p_inst uuid) returns int
language sql stable security definer set search_path = public as $$
  select coalesce((be_plano_da_escola(p_inst)).limite_oportunidades,
                  (select nullif(valor, '')::int from be_config_comercial where chave = 'limite_sem_plano'), 1)
$$;

-- oportunidade que conta pro limite: mandada pra aprovação, publicada ou pausada, e ainda não venceu
create or replace function public.be_oportunidades_em_uso(p_inst uuid, p_menos uuid default null) returns int
language sql stable security definer set search_path = public as $$
  select count(*)::int from be_oportunidades
  where instituicao_id = p_inst and status in ('pendente', 'publicada', 'pausada') and fim >= be_hoje()
    and id is distinct from p_menos
$$;

-- json público da escola (o que aparece pra qualquer pessoa)
create or replace function public.be_escola_json(i public.be_instituicoes) returns jsonb
language sql stable security definer set search_path = public as $$
  select jsonb_build_object(
    'id', i.id, 'slug', i.slug, 'nome', i.nome, 'tipo', i.tipo, 'demo', i.demo, 'descricao', i.descricao,
    'cidade', i.cidade, 'uf', i.uf, 'regiao', i.regiao, 'endereco', i.endereco, 'modalidades', to_jsonb(i.modalidades),
    'publico', i.publico, 'cursos', i.cursos, 'site', i.site, 'instagram', i.instagram, 'facebook', i.facebook,
    'whatsapp', i.whatsapp, 'telefone', i.telefone, 'email', i.email_contato,
    'logo_url', i.logo_url, 'capa_url', i.capa_url, 'cor', i.cor_primaria,
    'destaque', coalesce((be_plano_da_escola(i.id)).destaque, 0))
$$;

create or replace function public.be_oportunidade_json(o public.be_oportunidades, i public.be_instituicoes) returns jsonb
language sql stable security definer set search_path = public as $$
  select jsonb_build_object(
    'id', o.id, 'titulo', o.titulo, 'descricao', o.descricao, 'categoria', o.categoria, 'imagem_url', o.imagem_url,
    'local', o.local, 'online', o.online, 'inicio', o.inicio, 'fim', o.fim, 'regras', o.regras, 'link', o.link,
    'contato', coalesce(o.contato, i.whatsapp), 'status', o.status,
    'escola', jsonb_build_object('id', i.id, 'slug', i.slug, 'nome', i.nome, 'logo_url', i.logo_url, 'cidade', i.cidade, 'uf', i.uf,
                                 'demo', i.demo, 'whatsapp', i.whatsapp, 'site', i.site, 'email', i.email_contato,
                                 'destaque', coalesce((be_plano_da_escola(i.id)).destaque, 0)))
$$;

-- =========================================================
-- PÚBLICO (abre sem login)
-- =========================================================
create or replace function public.be_vitrine_escolas(p_busca text default null, p_cidade text default null, p_tipo text default null) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare v_b text := nullif(btrim(coalesce(p_busca, '')), '');
begin
  return coalesce((
    select jsonb_agg(x.j order by x.destaque desc, x.ativas desc, x.nome)
    from (
      select i.nome, coalesce((be_plano_da_escola(i.id)).destaque, 0) as destaque,
             (select count(*) from be_oportunidades o where o.instituicao_id = i.id and o.status = 'publicada' and be_hoje() between o.inicio and o.fim) as ativas,
             be_escola_json(i) || jsonb_build_object('oportunidades_ativas',
               (select count(*) from be_oportunidades o where o.instituicao_id = i.id and o.status = 'publicada' and be_hoje() between o.inicio and o.fim)) as j
      from be_instituicoes i
      where i.status = 'aprovada'
        and (p_cidade is null or lower(i.cidade) = lower(p_cidade))
        and (p_tipo is null or i.tipo = p_tipo)
        and (v_b is null or i.nome ilike '%' || v_b || '%' or i.descricao ilike '%' || v_b || '%' or i.cursos::text ilike '%' || v_b || '%')
      limit 100) x), '[]'::jsonb);
end $$;

-- escola pela página pública; quem é da escola e o criador também veem a escola ainda não aprovada (prévia)
create or replace function public.be_vitrine_escola(p_slug text) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare v_i be_instituicoes; v_previa boolean;
begin
  select * into v_i from be_instituicoes where slug = lower(btrim(coalesce(p_slug, '')));
  if v_i.id is null then raise exception 'escola não encontrada'; end if;
  v_previa := v_i.status <> 'aprovada';
  if v_previa and not (be_sou_da_escola(v_i.id) or be_sou_criador()) then raise exception 'escola não encontrada'; end if;
  return be_escola_json(v_i) || jsonb_build_object(
    'previa', v_previa, 'status', case when v_previa then v_i.status end,
    'oportunidades', coalesce((
      select jsonb_agg(be_oportunidade_json(o, v_i) order by o.fim, o.created_at desc)
      from be_oportunidades o
      where o.instituicao_id = v_i.id and o.status = 'publicada' and be_hoje() between o.inicio and o.fim), '[]'::jsonb));
end $$;

create or replace function public.be_vitrine_oportunidades(
  p_categoria text default null, p_cidade text default null, p_busca text default null,
  p_limite int default 30, p_offset int default 0) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare v_b text := nullif(btrim(coalesce(p_busca, '')), '');
begin
  return coalesce((
    select jsonb_agg(x.j order by x.destaque desc, x.publicada desc)
    from (
      select be_oportunidade_json(o, i) as j, coalesce((be_plano_da_escola(i.id)).destaque, 0) as destaque,
             coalesce(o.aprovada_em, o.created_at) as publicada
      from be_oportunidades o join be_instituicoes i on i.id = o.instituicao_id
      where o.status = 'publicada' and be_hoje() between o.inicio and o.fim and i.status = 'aprovada'
        and (p_categoria is null or o.categoria = p_categoria)
        and (p_cidade is null or lower(i.cidade) = lower(p_cidade) or o.online)
        and (v_b is null or o.titulo ilike '%' || v_b || '%' or o.descricao ilike '%' || v_b || '%' or i.nome ilike '%' || v_b || '%')
      order by destaque desc, publicada desc
      limit least(greatest(coalesce(p_limite, 30), 1), 60) offset greatest(coalesce(p_offset, 0), 0)) x), '[]'::jsonb);
end $$;

create or replace function public.be_vitrine_filtros() returns jsonb
language sql stable security definer set search_path = public as $$
  select jsonb_build_object(
    'cidades', coalesce((select jsonb_agg(c order by c) from (select distinct i.cidade as c from be_instituicoes i
                          where i.status = 'aprovada' and i.cidade is not null) x), '[]'::jsonb),
    'categorias', coalesce((select jsonb_object_agg(categoria, n) from (
                     select o.categoria, count(*) n from be_oportunidades o join be_instituicoes i on i.id = o.instituicao_id
                     where o.status = 'publicada' and be_hoje() between o.inicio and o.fim and i.status = 'aprovada'
                     group by o.categoria) x), '{}'::jsonb),
    'escolas', (select count(*) from be_instituicoes where status = 'aprovada'))
$$;

create or replace function public.be_vitrine_config() returns jsonb
language sql stable security definer set search_path = public as $$
  select coalesce(jsonb_object_agg(chave, valor) filter (where chave in ('whatsapp_comercial', 'email_comercial', 'mensagem_whatsapp')), '{}'::jsonb)
  from be_config_comercial
$$;

-- planos pra página "Para escolas" (o preço só aparece se o criador ligar "mostrar preços")
create or replace function public.be_vitrine_planos() returns jsonb
language sql stable security definer set search_path = public as $$
  select coalesce(jsonb_agg(jsonb_build_object('nome', p.nome, 'descricao', p.descricao, 'recursos', p.recursos, 'destaque', p.destaque,
           'preco', case when (select valor from be_config_comercial where chave = 'mostrar_precos') = 'sim' then p.preco_mensal end) order by p.ordem), '[]'::jsonb)
  from be_planos p where p.ativo
$$;

-- conta visualização e clique; repetição do mesmo visitante no mesmo dia não conta de novo
create or replace function public.be_registrar_evento(p_tipo text, p_instituicao uuid, p_oportunidade uuid default null, p_visitante uuid default null)
returns boolean language plpgsql security definer set search_path = public as $$
declare v_u uuid := be_usuario_atual_id(); v_quem uuid; v_n int;
begin
  if p_tipo not in ('ver_escola', 'ver_oportunidade', 'clique_contato') then return false; end if;
  v_quem := coalesce(v_u, p_visitante);
  if v_quem is null then return false; end if;
  if not exists (select 1 from be_instituicoes where id = p_instituicao and status = 'aprovada') then return false; end if;
  if p_oportunidade is not null and not exists (select 1 from be_oportunidades where id = p_oportunidade and instituicao_id = p_instituicao) then return false; end if;
  -- quem é da própria escola não infla os números dela
  if v_u is not null and exists (select 1 from be_instituicao_membros where instituicao_id = p_instituicao and usuario_id = v_u) then return false; end if;
  if (select count(*) from be_vitrine_eventos where visitante = v_quem and dia = be_hoje()) >= 300 then return false; end if;
  insert into be_vitrine_eventos (tipo, instituicao_id, oportunidade_id, visitante, logado, dia)
  values (p_tipo, p_instituicao, p_oportunidade, v_quem, v_u is not null, be_hoje())
  on conflict do nothing;
  get diagnostics v_n = row_count;
  return v_n > 0;
end $$;

-- formulário "Quero ser escola parceira": valida, limita e guarda; não aprova nada sozinho
create or replace function public.be_registrar_interesse(p_dados jsonb) returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  v_inst text := be_txt(p_dados, 'instituicao', 120);
  v_resp text := be_txt(p_dados, 'responsavel', 80);
  v_email text := lower(be_txt(p_dados, 'email', 160));
  v_tel text := be_so_digitos(p_dados ->> 'telefone');
  v_cidade text := be_txt(p_dados, 'cidade', 80);
  v_tipo text := be_txt(p_dados, 'tipo', 30);
  v_msg text := be_txt(p_dados, 'mensagem', 1000);
begin
  if be_txt(p_dados, 'site_url', 200) is not null then return jsonb_build_object('ok', true); end if; -- campo escondido: robô
  if v_inst is null or char_length(v_inst) < 2 then raise exception 'escreve o nome da instituição'; end if;
  if v_resp is null or char_length(v_resp) < 2 then raise exception 'escreve o nome do responsável'; end if;
  if v_email is null or v_email !~ '^[^\s@]+@[^\s@]+\.[^\s@]{2,}$' then raise exception 'confere o e-mail'; end if;
  if v_tel is null or char_length(v_tel) not between 10 and 13 then raise exception 'confere o telefone com DDD'; end if;
  if v_cidade is null then raise exception 'escreve a cidade'; end if;
  if v_tipo is null or v_tipo not in ('escola', 'cursinho', 'idiomas', 'profissionalizante', 'faculdade', 'reforco', 'outro') then raise exception 'escolhe o tipo de instituição'; end if;
  if coalesce((p_dados ->> 'consentimento')::boolean, false) is not true then raise exception 'pra gente responder, precisa marcar a autorização de contato'; end if;
  if (select count(*) from be_leads where lower(email) = v_email and created_at > now() - interval '1 day') >= 3 then
    raise exception 'já recebemos seu contato, a gente responde em breve';
  end if;
  if (select count(*) from be_leads where created_at > now() - interval '1 hour') >= 60 then
    raise exception 'muitos contatos agora, tenta de novo daqui a pouco';
  end if;
  insert into be_leads (instituicao, responsavel, email, telefone, cidade, tipo, mensagem, consentimento, consentimento_texto)
  values (v_inst, v_resp, v_email, v_tel, v_cidade, v_tipo, v_msg, true,
          coalesce(be_txt(p_dados, 'consentimento_texto', 400), 'Autorizo o EstudeUp a usar estes dados para responder a esta solicitação.'));
  return jsonb_build_object('ok', true);
end $$;

-- =========================================================
-- ESCOLA (gestor e professores)
-- =========================================================
create or replace function public.be_minhas_escolas() returns jsonb
language sql stable security definer set search_path = public as $$
  select coalesce(jsonb_agg(jsonb_build_object('id', i.id, 'slug', i.slug, 'nome', i.nome, 'status', i.status, 'demo', i.demo,
                                               'papel', m.papel, 'logo_url', i.logo_url) order by i.nome), '[]'::jsonb)
  from be_instituicao_membros m join be_instituicoes i on i.id = m.instituicao_id
  where m.usuario_id = be_usuario_atual_id() and m.ativo and i.status in ('pendente', 'aprovada', 'suspensa')
$$;

-- qualquer conta pode pedir o cadastro da sua escola; fica pendente até o criador aprovar
create or replace function public.be_escola_solicitar(p_dados jsonb) returns jsonb
language plpgsql security definer set search_path = public as $$
declare v_u uuid := be_usuario_atual_id(); v_nome text := be_txt(p_dados, 'nome', 120); v_id uuid; v_tipo text := coalesce(be_txt(p_dados, 'tipo', 30), 'escola');
begin
  if v_u is null then raise exception 'faça login de novo'; end if;
  if v_nome is null or char_length(v_nome) < 3 then raise exception 'escreve o nome da escola'; end if;
  if v_tipo not in ('escola', 'cursinho', 'idiomas', 'profissionalizante', 'faculdade', 'reforco', 'outro') then raise exception 'tipo inválido'; end if;
  if exists (select 1 from be_instituicao_membros m join be_instituicoes i on i.id = m.instituicao_id
             where m.usuario_id = v_u and m.papel = 'gestor' and i.status = 'pendente') then
    raise exception 'você já tem um pedido esperando aprovação';
  end if;
  insert into be_instituicoes (nome, slug, tipo, status, cidade, uf, whatsapp, email_contato, dono_id, codigo_professor)
  values (v_nome, be_slug_livre(v_nome), v_tipo, 'pendente', be_txt(p_dados, 'cidade', 80), upper(be_txt(p_dados, 'uf', 2)),
          be_so_digitos(p_dados ->> 'whatsapp'), lower(be_txt(p_dados, 'email', 160)), v_u, be_codigo_aleatorio(6))
  returning id into v_id;
  insert into be_instituicao_membros (instituicao_id, usuario_id, papel) values (v_id, v_u, 'gestor');
  insert into be_assinaturas (instituicao_id, status) values (v_id, 'interessado') on conflict do nothing;
  perform be_registrar_acao('gestor', 'escola_solicitada', 'instituicao', v_id, v_id, jsonb_build_object('nome', v_nome));
  return jsonb_build_object('ok', true, 'id', v_id);
end $$;

-- professor entra na escola com o código que o gestor passa
create or replace function public.be_escola_entrar_professor(p_codigo text) returns jsonb
language plpgsql security definer set search_path = public as $$
declare v_u uuid := be_usuario_atual_id(); v_i be_instituicoes;
begin
  if v_u is null then raise exception 'faça login de novo'; end if;
  select * into v_i from be_instituicoes where codigo_professor = upper(btrim(coalesce(p_codigo, ''))) and status = 'aprovada';
  if v_i.id is null then raise exception 'código de escola não encontrado'; end if;
  insert into be_instituicao_membros (instituicao_id, usuario_id, papel) values (v_i.id, v_u, 'professor')
  on conflict (instituicao_id, usuario_id) do update set ativo = true;
  perform be_registrar_acao('professor', 'professor_entrou', 'usuario', v_u, v_i.id, null);
  return jsonb_build_object('ok', true, 'id', v_i.id, 'nome', v_i.nome);
end $$;

-- números da escola num período (sem dado pessoal de ninguém)
create or replace function public.be_escola_metricas_json(p_inst uuid, p_dias int) returns jsonb
language sql stable security definer set search_path = public as $$
  with periodo as (select be_hoje() - greatest(1, least(coalesce(p_dias, 30), 365)) + 1 as ini)
  select jsonb_build_object(
    'dias', greatest(1, least(coalesce(p_dias, 30), 365)),
    'ver_escola', (select count(*) from be_vitrine_eventos e, periodo p where e.instituicao_id = p_inst and e.tipo = 'ver_escola' and e.dia >= p.ini),
    'ver_oportunidade', (select count(*) from be_vitrine_eventos e, periodo p where e.instituicao_id = p_inst and e.tipo = 'ver_oportunidade' and e.dia >= p.ini),
    'cliques', (select count(*) from be_vitrine_eventos e, periodo p where e.instituicao_id = p_inst and e.tipo = 'clique_contato' and e.dia >= p.ini),
    'serie', coalesce((select jsonb_agg(jsonb_build_object('dia', d.dia,
                 'ver', (select count(*) from be_vitrine_eventos e where e.instituicao_id = p_inst and e.dia = d.dia and e.tipo in ('ver_escola', 'ver_oportunidade')),
                 'cliques', (select count(*) from be_vitrine_eventos e where e.instituicao_id = p_inst and e.dia = d.dia and e.tipo = 'clique_contato')) order by d.dia)
               from (select generate_series(p.ini, be_hoje(), interval '1 day')::date as dia from periodo p) d), '[]'::jsonb),
    'por_oportunidade', coalesce((select jsonb_agg(jsonb_build_object('id', o.id, 'titulo', o.titulo,
                 'ver', (select count(*) from be_vitrine_eventos e, periodo p where e.oportunidade_id = o.id and e.tipo = 'ver_oportunidade' and e.dia >= p.ini),
                 'cliques', (select count(*) from be_vitrine_eventos e, periodo p where e.oportunidade_id = o.id and e.tipo = 'clique_contato' and e.dia >= p.ini))
                 order by o.created_at desc)
               from be_oportunidades o where o.instituicao_id = p_inst and o.status in ('publicada', 'pausada', 'encerrada')), '[]'::jsonb))
$$;

create or replace function public.be_escola_painel(p_inst uuid, p_dias int default 30) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare v_i be_instituicoes; v_gestor boolean := be_sou_da_escola(p_inst, 'gestor'); v_plano be_planos; v_ass be_assinaturas;
begin
  if not (be_sou_da_escola(p_inst) or be_sou_criador()) then raise exception 'você não faz parte dessa escola'; end if;
  select * into v_i from be_instituicoes where id = p_inst;
  v_plano := be_plano_da_escola(p_inst);
  select * into v_ass from be_assinaturas where instituicao_id = p_inst;
  return be_escola_json(v_i) || jsonb_build_object(
    'status', v_i.status, 'gestor', v_gestor or be_sou_criador(), 'codigo_professor', case when v_gestor or be_sou_criador() then v_i.codigo_professor end,
    'plano', case when v_plano.id is not null then jsonb_build_object('nome', v_plano.nome, 'recursos', v_plano.recursos, 'limite_oportunidades', v_plano.limite_oportunidades,
                                                                       'limite_alunos', v_plano.limite_alunos, 'relatorios', v_plano.relatorios) end,
    'contrato', case when v_ass.instituicao_id is not null then jsonb_build_object('status', v_ass.status, 'pagamento', v_ass.pagamento,
                       'vigencia_inicio', v_ass.vigencia_inicio, 'vigencia_fim', v_ass.vigencia_fim) end,
    'limite_oportunidades', be_limite_oportunidades(p_inst), 'oportunidades_em_uso', be_oportunidades_em_uso(p_inst),
    'oportunidades', coalesce((select jsonb_agg(be_oportunidade_json(o, v_i) || jsonb_build_object('motivo_status', o.motivo_status,
                       'vencida', o.fim < be_hoje(), 'ja_aprovada', o.aprovada_em is not null, 'created_at', o.created_at) order by o.created_at desc)
                     from be_oportunidades o where o.instituicao_id = p_inst), '[]'::jsonb),
    'professores', case when v_gestor or be_sou_criador() then coalesce((
                     select jsonb_agg(jsonb_build_object('id', u.id, 'nome', u.nome, 'papel', m.papel) order by m.papel, u.nome)
                     from be_instituicao_membros m join be_usuarios u on u.id = m.usuario_id
                     where m.instituicao_id = p_inst and m.ativo), '[]'::jsonb) end,
    'turmas', coalesce((
      select jsonb_agg(jsonb_build_object('id', g.id, 'nome', g.nome, 'materia', g.materia, 'professor', be_nome_publico(pu.nome),
               'alunos', (select count(*) from be_grupo_membros gm where gm.grupo_id = g.id and gm.papel_no_grupo = 'membro'),
               'ativos_7d', (select count(*) from be_grupo_membros gm join be_usuarios u on u.id = gm.usuario_id
                             where gm.grupo_id = g.id and gm.papel_no_grupo = 'membro' and u.ultima_atividade >= be_hoje() - 6),
               'dominio', (select round(avg(d.score), 2) from be_dominio d join be_topicos t on t.id = d.topico_id join be_materias m on m.id = t.materia_id
                           join be_grupo_membros gm on gm.usuario_id = d.usuario_id and gm.grupo_id = g.id and gm.papel_no_grupo = 'membro'
                           where m.grupo_id = g.id),
               'minha', g.dono_id = be_usuario_atual_id()) order by g.nome)
      from be_grupos g join be_usuarios pu on pu.id = g.dono_id
      where g.instituicao_id = p_inst and (v_gestor or be_sou_criador() or g.dono_id = be_usuario_atual_id())), '[]'::jsonb),
    'alunos_total', (select count(distinct gm.usuario_id) from be_grupos g join be_grupo_membros gm on gm.grupo_id = g.id and gm.papel_no_grupo = 'membro'
                     where g.instituicao_id = p_inst),
    'metricas', case when v_gestor or be_sou_criador() then be_escola_metricas_json(p_inst, p_dias) end);
end $$;

create or replace function public.be_escola_salvar(p_inst uuid, p_dados jsonb) returns jsonb
language plpgsql security definer set search_path = public as $$
declare v_mod text[] := '{}'; v_cursos jsonb; v_x text;
begin
  if not (be_sou_da_escola(p_inst, 'gestor') or be_sou_criador()) then raise exception 'só o gestor da escola muda esses dados'; end if;
  if p_dados ? 'modalidades' then
    select coalesce(array_agg(distinct m), '{}') into v_mod from jsonb_array_elements_text(coalesce(p_dados -> 'modalidades', '[]')) m
    where m in ('presencial', 'online', 'hibrido');
  end if;
  if p_dados ? 'cursos' then
    if jsonb_typeof(p_dados -> 'cursos') <> 'array' or jsonb_array_length(p_dados -> 'cursos') > 40 then raise exception 'lista de cursos inválida (até 40)'; end if;
    select coalesce(jsonb_agg(jsonb_build_object('nome', left(btrim(c ->> 'nome'), 80), 'descricao', left(btrim(coalesce(c ->> 'descricao', '')), 300))), '[]')
      into v_cursos from jsonb_array_elements(p_dados -> 'cursos') c where char_length(btrim(coalesce(c ->> 'nome', ''))) >= 2;
  end if;
  foreach v_x in array array['site', 'instagram', 'facebook', 'logo_url', 'capa_url'] loop
    if not be_url_ok(be_txt(p_dados, v_x, 300)) then raise exception 'o link em "%" precisa começar com https://', v_x; end if;
  end loop;
  if be_txt(p_dados, 'email', 160) is not null and be_txt(p_dados, 'email', 160) !~ '^[^\s@]+@[^\s@]+\.[^\s@]{2,}$' then raise exception 'confere o e-mail de contato'; end if;
  if be_so_digitos(p_dados ->> 'whatsapp') is not null and char_length(be_so_digitos(p_dados ->> 'whatsapp')) not between 10 and 13 then raise exception 'confere o WhatsApp com DDD'; end if;
  if p_dados ? 'nome' and char_length(coalesce(be_txt(p_dados, 'nome', 120), '')) < 3 then raise exception 'o nome da escola ficou curto'; end if;
  if p_dados ? 'tipo' and be_txt(p_dados, 'tipo', 30) not in ('escola', 'cursinho', 'idiomas', 'profissionalizante', 'faculdade', 'reforco', 'outro') then raise exception 'tipo inválido'; end if;
  update be_instituicoes set
    nome = case when p_dados ? 'nome' then be_txt(p_dados, 'nome', 120) else nome end,
    tipo = case when p_dados ? 'tipo' then be_txt(p_dados, 'tipo', 30) else tipo end,
    descricao = case when p_dados ? 'descricao' then be_txt(p_dados, 'descricao', 3000) else descricao end,
    cidade = case when p_dados ? 'cidade' then be_txt(p_dados, 'cidade', 80) else cidade end,
    uf = case when p_dados ? 'uf' then upper(be_txt(p_dados, 'uf', 2)) else uf end,
    regiao = case when p_dados ? 'regiao' then be_txt(p_dados, 'regiao', 200) else regiao end,
    endereco = case when p_dados ? 'endereco' then be_txt(p_dados, 'endereco', 200) else endereco end,
    modalidades = case when p_dados ? 'modalidades' then v_mod else modalidades end,
    publico = case when p_dados ? 'publico' then be_txt(p_dados, 'publico', 300) else publico end,
    cursos = case when p_dados ? 'cursos' then v_cursos else cursos end,
    site = case when p_dados ? 'site' then be_txt(p_dados, 'site', 300) else site end,
    instagram = case when p_dados ? 'instagram' then be_txt(p_dados, 'instagram', 300) else instagram end,
    facebook = case when p_dados ? 'facebook' then be_txt(p_dados, 'facebook', 300) else facebook end,
    whatsapp = case when p_dados ? 'whatsapp' then be_so_digitos(p_dados ->> 'whatsapp') else whatsapp end,
    telefone = case when p_dados ? 'telefone' then be_txt(p_dados, 'telefone', 30) else telefone end,
    email_contato = case when p_dados ? 'email' then lower(be_txt(p_dados, 'email', 160)) else email_contato end,
    logo_url = case when p_dados ? 'logo_url' then be_txt(p_dados, 'logo_url', 300) else logo_url end,
    capa_url = case when p_dados ? 'capa_url' then be_txt(p_dados, 'capa_url', 300) else capa_url end,
    updated_at = now()
  where id = p_inst;
  perform be_registrar_acao(case when be_sou_criador() and not be_sou_da_escola(p_inst, 'gestor') then 'criador' else 'gestor' end,
                            'escola_editada', 'instituicao', p_inst, p_inst, jsonb_build_object('campos', (select jsonb_agg(k) from jsonb_object_keys(p_dados) k)));
  return jsonb_build_object('ok', true);
end $$;

create or replace function public.be_escola_codigo_novo(p_inst uuid) returns text
language plpgsql security definer set search_path = public as $$
declare v_c text;
begin
  if not (be_sou_da_escola(p_inst, 'gestor') or be_sou_criador()) then raise exception 'só o gestor da escola faz isso'; end if;
  loop
    v_c := be_codigo_aleatorio(6);
    exit when not exists (select 1 from be_instituicoes where codigo_professor = v_c);
  end loop;
  update be_instituicoes set codigo_professor = v_c, updated_at = now() where id = p_inst;
  perform be_registrar_acao('gestor', 'codigo_professor_novo', 'instituicao', p_inst, p_inst, null);
  return v_c;
end $$;

create or replace function public.be_escola_tirar_professor(p_inst uuid, p_usuario uuid) returns jsonb
language plpgsql security definer set search_path = public as $$
begin
  if not (be_sou_da_escola(p_inst, 'gestor') or be_sou_criador()) then raise exception 'só o gestor da escola faz isso'; end if;
  if p_usuario = be_usuario_atual_id() then raise exception 'você não pode tirar você mesmo'; end if;
  update be_instituicao_membros set ativo = false where instituicao_id = p_inst and usuario_id = p_usuario and papel = 'professor';
  perform be_registrar_acao('gestor', 'professor_removido', 'usuario', p_usuario, p_inst, null);
  return jsonb_build_object('ok', true);
end $$;

-- criar ou editar oportunidade. Mudou o conteúdo de uma publicada: volta pra aprovação.
create or replace function public.be_oportunidade_salvar(p_id uuid, p_inst uuid, p_dados jsonb, p_enviar boolean default false) returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  v_o be_oportunidades; v_i be_instituicoes; v_id uuid := p_id; v_status text;
  v_titulo text := be_txt(p_dados, 'titulo', 120); v_desc text := be_txt(p_dados, 'descricao', 2000);
  v_cat text := be_txt(p_dados, 'categoria', 30); v_ini date; v_fim date;
  v_link text := be_txt(p_dados, 'link', 300); v_img text := be_txt(p_dados, 'imagem_url', 300);
begin
  if p_id is not null then
    select * into v_o from be_oportunidades where id = p_id;
    if v_o.id is null then raise exception 'oportunidade não encontrada'; end if;
    p_inst := v_o.instituicao_id;
  end if;
  if not (be_sou_da_escola(p_inst, 'gestor') or be_sou_criador()) then raise exception 'só o gestor da escola cuida das oportunidades'; end if;
  select * into v_i from be_instituicoes where id = p_inst;
  if v_i.status not in ('aprovada', 'pendente') then raise exception 'a escola está %: fala com a equipe do EstudeUp', v_i.status; end if;
  if v_titulo is null or char_length(v_titulo) < 4 then raise exception 'dá um título pra oportunidade'; end if;
  if v_desc is null or char_length(v_desc) < 10 then raise exception 'descreve a oportunidade (pelo menos uma frase)'; end if;
  if v_cat is null or v_cat not in ('bolsa', 'desconto', 'matricula', 'curso_novo', 'preparatorio', 'profissionalizante', 'aula_experimental', 'evento', 'campanha', 'outro') then
    raise exception 'escolhe a categoria';
  end if;
  begin v_ini := (p_dados ->> 'inicio')::date; v_fim := (p_dados ->> 'fim')::date; exception when others then raise exception 'confere as datas'; end;
  if v_ini is null or v_fim is null then raise exception 'escolhe o início e o fim da oportunidade'; end if;
  if v_fim < v_ini then raise exception 'o fim precisa ser depois do início'; end if;
  if v_fim < be_hoje() then raise exception 'essa data de fim já passou'; end if;
  if v_fim > v_ini + 366 then raise exception 'a oportunidade pode durar no máximo 1 ano'; end if;
  if v_cat in ('bolsa', 'desconto') and char_length(coalesce(be_txt(p_dados, 'regras', 2000), '')) < 10 then
    raise exception 'bolsa e desconto precisam das regras e condições (quem pode, quanto, até quando)';
  end if;
  if not be_url_ok(v_link) or not be_url_ok(v_img) then raise exception 'os links precisam começar com https://'; end if;

  v_status := case when p_enviar then 'pendente' else 'rascunho' end;
  if v_id is not null and v_o.status in ('publicada', 'pausada') and not p_enviar then v_status := 'pendente'; end if;
  if v_status = 'pendente' and be_oportunidades_em_uso(p_inst, v_id) >= be_limite_oportunidades(p_inst) then
    raise exception 'o plano da escola permite % oportunidade(s) ativa(s) ao mesmo tempo. Encerra uma ou fala com a equipe do EstudeUp sobre o plano', be_limite_oportunidades(p_inst);
  end if;

  if v_id is null then
    insert into be_oportunidades (instituicao_id, titulo, descricao, categoria, imagem_url, local, online, inicio, fim, regras, link, contato, status, criado_por)
    values (p_inst, v_titulo, v_desc, v_cat, v_img, be_txt(p_dados, 'local', 120), coalesce((p_dados ->> 'online')::boolean, false),
            v_ini, v_fim, be_txt(p_dados, 'regras', 2000), v_link, be_so_digitos(p_dados ->> 'contato'), v_status, be_usuario_atual_id())
    returning id into v_id;
  else
    update be_oportunidades set titulo = v_titulo, descricao = v_desc, categoria = v_cat, imagem_url = v_img, local = be_txt(p_dados, 'local', 120),
      online = coalesce((p_dados ->> 'online')::boolean, false), inicio = v_ini, fim = v_fim, regras = be_txt(p_dados, 'regras', 2000),
      link = v_link, contato = be_so_digitos(p_dados ->> 'contato'), status = v_status, motivo_status = null, updated_at = now()
    where id = v_id;
  end if;
  perform be_registrar_acao('gestor', case when p_id is null then 'oportunidade_criada' else 'oportunidade_editada' end, 'oportunidade', v_id, p_inst,
                            jsonb_build_object('status', v_status, 'titulo', v_titulo));
  return jsonb_build_object('ok', true, 'id', v_id, 'status', v_status);
end $$;

-- pausar, retomar (se já tinha sido aprovada), encerrar ou mandar pra aprovação
create or replace function public.be_oportunidade_acao(p_id uuid, p_acao text) returns jsonb
language plpgsql security definer set search_path = public as $$
declare v_o be_oportunidades; v_novo text;
begin
  select * into v_o from be_oportunidades where id = p_id;
  if v_o.id is null then raise exception 'oportunidade não encontrada'; end if;
  if not (be_sou_da_escola(v_o.instituicao_id, 'gestor') or be_sou_criador()) then raise exception 'só o gestor da escola cuida das oportunidades'; end if;
  v_novo := case
    when p_acao = 'pausar' and v_o.status = 'publicada' then 'pausada'
    when p_acao = 'retomar' and v_o.status = 'pausada' and v_o.aprovada_em is not null and v_o.fim >= be_hoje() then 'publicada'
    when p_acao = 'encerrar' and v_o.status in ('rascunho', 'pendente', 'publicada', 'pausada', 'recusada') then 'encerrada'
    when p_acao = 'enviar' and v_o.status in ('rascunho', 'recusada') and v_o.fim >= be_hoje() then 'pendente'
  end;
  if v_novo is null then raise exception 'não dá pra % uma oportunidade que está %', p_acao, v_o.status; end if;
  if v_novo = 'pendente' and be_oportunidades_em_uso(v_o.instituicao_id, v_o.id) >= be_limite_oportunidades(v_o.instituicao_id) then
    raise exception 'o plano da escola permite % oportunidade(s) ativa(s) ao mesmo tempo', be_limite_oportunidades(v_o.instituicao_id);
  end if;
  update be_oportunidades set status = v_novo, updated_at = now() where id = p_id;
  perform be_registrar_acao('gestor', 'oportunidade_' || p_acao, 'oportunidade', p_id, v_o.instituicao_id, jsonb_build_object('de', v_o.status, 'para', v_novo));
  return jsonb_build_object('ok', true, 'status', v_novo);
end $$;

-- caminho da imagem no armazenamento: <id da escola>/<arquivo>; só o gestor da escola (ou o criador) envia
create or replace function public.be_pode_enviar_imagem_escola(p_caminho text) returns boolean
language plpgsql stable security definer set search_path = public as $$
declare v_pasta text := split_part(coalesce(p_caminho, ''), '/', 1); v_id uuid;
begin
  if v_pasta !~ '^[0-9a-f-]{36}$' or p_caminho !~ '^[0-9a-f-]{36}/[a-z0-9_-]{1,60}\.(jpg|jpeg|png|webp)$' then return false; end if;
  v_id := v_pasta::uuid;
  return be_sou_da_escola(v_id, 'gestor') or be_sou_criador();
end $$;

-- =========================================================
-- ADMINISTRAÇÃO (conta do criador)
-- =========================================================
create or replace function public.be_admin_comercial(p_dias int default 30) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare v_dias int := greatest(1, least(coalesce(p_dias, 30), 365)); v_ini date;
begin
  perform be_exigir_criador();
  v_ini := be_hoje() - v_dias + 1;
  return jsonb_build_object(
    'dias', v_dias,
    'escolas', jsonb_build_object(
      'total', (select count(*) from be_instituicoes where not demo),
      'pendentes', (select count(*) from be_instituicoes where status = 'pendente' and not demo),
      'aprovadas', (select count(*) from be_instituicoes where status = 'aprovada' and not demo),
      'ativas', (select count(*) from be_assinaturas a join be_instituicoes i on i.id = a.instituicao_id where a.status = 'ativo' and not i.demo
                 and (a.vigencia_fim is null or a.vigencia_fim >= be_hoje())),
      'demo', (select count(*) from be_instituicoes where demo)),
    'oportunidades', jsonb_build_object(
      'pendentes', (select count(*) from be_oportunidades where status = 'pendente'),
      'publicadas', (select count(*) from be_oportunidades where status = 'publicada'),
      'ativas', (select count(*) from be_oportunidades o join be_instituicoes i on i.id = o.instituicao_id
                 where o.status = 'publicada' and be_hoje() between o.inicio and o.fim and i.status = 'aprovada')),
    'leads', jsonb_build_object('novos', (select count(*) from be_leads where status = 'novo'),
                                'periodo', (select count(*) from be_leads where created_at::date >= v_ini)),
    'eventos', jsonb_build_object(
      'ver_escola', (select count(*) from be_vitrine_eventos e join be_instituicoes i on i.id = e.instituicao_id where e.tipo = 'ver_escola' and e.dia >= v_ini and not i.demo),
      'ver_oportunidade', (select count(*) from be_vitrine_eventos e join be_instituicoes i on i.id = e.instituicao_id where e.tipo = 'ver_oportunidade' and e.dia >= v_ini and not i.demo),
      'cliques', (select count(*) from be_vitrine_eventos e join be_instituicoes i on i.id = e.instituicao_id where e.tipo = 'clique_contato' and e.dia >= v_ini and not i.demo)),
    'serie', coalesce((select jsonb_agg(jsonb_build_object('dia', d.dia,
               'ver', (select count(*) from be_vitrine_eventos e join be_instituicoes i on i.id = e.instituicao_id where e.dia = d.dia and e.tipo <> 'clique_contato' and not i.demo),
               'cliques', (select count(*) from be_vitrine_eventos e join be_instituicoes i on i.id = e.instituicao_id where e.dia = d.dia and e.tipo = 'clique_contato' and not i.demo),
               'leads', (select count(*) from be_leads l where l.created_at::date = d.dia)) order by d.dia)
             from (select generate_series(v_ini, be_hoje(), interval '1 day')::date as dia) d), '[]'::jsonb),
    'config', (select coalesce(jsonb_object_agg(chave, valor), '{}'::jsonb) from be_config_comercial));
end $$;

create or replace function public.be_admin_escolas(p_status text default null) returns jsonb
language plpgsql stable security definer set search_path = public as $$
begin
  perform be_exigir_criador();
  return coalesce((
    select jsonb_agg(be_escola_json(i) || jsonb_build_object('status', i.status, 'created_at', i.created_at, 'aprovada_em', i.aprovada_em,
             'gestores', (select jsonb_agg(jsonb_build_object('nome', u.nome, 'email', a.email)) from be_instituicao_membros m join be_usuarios u on u.id = m.usuario_id
                          left join auth.users a on a.id = u.auth_user_id where m.instituicao_id = i.id and m.papel = 'gestor' and m.ativo),
             'contrato', (select jsonb_build_object('status', s.status, 'pagamento', s.pagamento, 'plano', p.nome, 'plano_id', s.plano_id, 'valor_mensal', s.valor_mensal,
                                                    'vigencia_inicio', s.vigencia_inicio, 'vigencia_fim', s.vigencia_fim, 'observacao', s.observacao)
                          from be_assinaturas s left join be_planos p on p.id = s.plano_id where s.instituicao_id = i.id),
             'oportunidades_ativas', (select count(*) from be_oportunidades o where o.instituicao_id = i.id and o.status = 'publicada' and be_hoje() between o.inicio and o.fim),
             'oportunidades_pendentes', (select count(*) from be_oportunidades o where o.instituicao_id = i.id and o.status = 'pendente'))
           order by case i.status when 'pendente' then 0 when 'aprovada' then 1 else 2 end, i.created_at desc)
    from be_instituicoes i where p_status is null or i.status = p_status), '[]'::jsonb);
end $$;

create or replace function public.be_admin_escola_status(p_inst uuid, p_status text, p_motivo text default null) returns jsonb
language plpgsql security definer set search_path = public as $$
declare v_antes text;
begin
  perform be_exigir_criador();
  if p_status not in ('pendente', 'aprovada', 'recusada', 'suspensa', 'desativada') then raise exception 'status inválido'; end if;
  select status into v_antes from be_instituicoes where id = p_inst;
  if v_antes is null then raise exception 'escola não encontrada'; end if;
  update be_instituicoes set status = p_status, updated_at = now(),
    aprovada_em = case when p_status = 'aprovada' then coalesce(aprovada_em, now()) else aprovada_em end,
    codigo_professor = coalesce(codigo_professor, be_codigo_aleatorio(6))
  where id = p_inst;
  perform be_registrar_acao('criador', 'escola_' || p_status, 'instituicao', p_inst, p_inst, jsonb_build_object('de', v_antes, 'motivo', left(p_motivo, 300)));
  return jsonb_build_object('ok', true);
end $$;

-- o criador cadastra a escola direto (depois do contato) e liga o gestor pelo e-mail da conta dele no EstudeUp
create or replace function public.be_admin_escola_criar(p_dados jsonb, p_email_gestor text default null) returns jsonb
language plpgsql security definer set search_path = public as $$
declare v_nome text := be_txt(p_dados, 'nome', 120); v_id uuid;
begin
  perform be_exigir_criador();
  if v_nome is null or char_length(v_nome) < 3 then raise exception 'escreve o nome da escola'; end if;
  insert into be_instituicoes (nome, slug, tipo, status, cidade, uf, dono_id, codigo_professor, aprovada_em, demo)
  values (v_nome, be_slug_livre(coalesce(be_txt(p_dados, 'slug', 60), v_nome)), coalesce(be_txt(p_dados, 'tipo', 30), 'escola'), 'aprovada',
          be_txt(p_dados, 'cidade', 80), upper(be_txt(p_dados, 'uf', 2)), be_usuario_atual_id(), be_codigo_aleatorio(6), now(),
          coalesce((p_dados ->> 'demo')::boolean, false))
  returning id into v_id;
  insert into be_assinaturas (instituicao_id, status) values (v_id, 'negociacao') on conflict do nothing;
  perform be_registrar_acao('criador', 'escola_criada', 'instituicao', v_id, v_id, jsonb_build_object('nome', v_nome));
  if nullif(btrim(coalesce(p_email_gestor, '')), '') is not null then perform be_admin_escola_gestor(v_id, p_email_gestor); end if;
  perform be_escola_salvar(v_id, p_dados - 'slug' - 'demo' - 'nome' - 'tipo' - 'cidade' - 'uf');
  return jsonb_build_object('ok', true, 'id', v_id);
end $$;

create or replace function public.be_admin_escola_gestor(p_inst uuid, p_email text) returns jsonb
language plpgsql security definer set search_path = public as $$
declare v_u uuid;
begin
  perform be_exigir_criador();
  select u.id into v_u from be_usuarios u join auth.users a on a.id = u.auth_user_id where lower(a.email) = lower(btrim(coalesce(p_email, '')));
  if v_u is null then raise exception 'não achei conta no EstudeUp com esse e-mail (a pessoa precisa criar a conta primeiro)'; end if;
  insert into be_instituicao_membros (instituicao_id, usuario_id, papel) values (p_inst, v_u, 'gestor')
  on conflict (instituicao_id, usuario_id) do update set papel = 'gestor', ativo = true;
  perform be_registrar_acao('criador', 'gestor_ligado', 'usuario', v_u, p_inst, null);
  return jsonb_build_object('ok', true);
end $$;

create or replace function public.be_admin_escola_editar(p_inst uuid, p_dados jsonb) returns jsonb
language plpgsql security definer set search_path = public as $$
declare v_slug text := be_txt(p_dados, 'slug', 60);
begin
  perform be_exigir_criador();
  if v_slug is not null then
    v_slug := be_slug(v_slug);
    if exists (select 1 from be_instituicoes where slug = v_slug and id <> p_inst) then raise exception 'esse endereço já é de outra escola'; end if;
    update be_instituicoes set slug = v_slug where id = p_inst;
  end if;
  if p_dados ? 'demo' then update be_instituicoes set demo = coalesce((p_dados ->> 'demo')::boolean, false) where id = p_inst; end if;
  perform be_escola_salvar(p_inst, p_dados - 'slug' - 'demo');
  return jsonb_build_object('ok', true);
end $$;

create or replace function public.be_admin_nota(p_inst uuid, p_texto text) returns jsonb
language plpgsql security definer set search_path = public as $$
begin
  perform be_exigir_criador();
  if char_length(btrim(coalesce(p_texto, ''))) < 2 then raise exception 'escreve a observação'; end if;
  perform be_registrar_acao('criador', 'observacao', 'instituicao', p_inst, p_inst, jsonb_build_object('texto', left(btrim(p_texto), 1000)));
  return jsonb_build_object('ok', true);
end $$;

create or replace function public.be_admin_oportunidades(p_status text default 'pendente') returns jsonb
language plpgsql stable security definer set search_path = public as $$
begin
  perform be_exigir_criador();
  return coalesce((
    select jsonb_agg(be_oportunidade_json(o, i) || jsonb_build_object('motivo_status', o.motivo_status, 'vencida', o.fim < be_hoje(),
                     'created_at', o.created_at, 'updated_at', o.updated_at, 'escola_status', i.status)
           order by o.updated_at desc)
    from be_oportunidades o join be_instituicoes i on i.id = o.instituicao_id
    where p_status is null or o.status = p_status
    limit 200), '[]'::jsonb);
end $$;

create or replace function public.be_admin_oportunidade_status(p_id uuid, p_status text, p_motivo text default null) returns jsonb
language plpgsql security definer set search_path = public as $$
declare v_o be_oportunidades;
begin
  perform be_exigir_criador();
  if p_status not in ('publicada', 'recusada', 'suspensa', 'encerrada', 'pendente') then raise exception 'status inválido'; end if;
  select * into v_o from be_oportunidades where id = p_id;
  if v_o.id is null then raise exception 'oportunidade não encontrada'; end if;
  if p_status = 'publicada' and v_o.fim < be_hoje() then raise exception 'essa oportunidade já venceu'; end if;
  if p_status in ('recusada', 'suspensa') and char_length(btrim(coalesce(p_motivo, ''))) < 3 then raise exception 'escreve o motivo (a escola vê)'; end if;
  update be_oportunidades set status = p_status, motivo_status = nullif(left(btrim(coalesce(p_motivo, '')), 300), ''), updated_at = now(),
    aprovada_em = case when p_status = 'publicada' then now() else aprovada_em end
  where id = p_id;
  perform be_registrar_acao('criador', 'oportunidade_' || p_status, 'oportunidade', p_id, v_o.instituicao_id,
                            jsonb_build_object('de', v_o.status, 'motivo', left(p_motivo, 300), 'titulo', v_o.titulo));
  return jsonb_build_object('ok', true);
end $$;

create or replace function public.be_admin_leads(p_status text default null) returns jsonb
language plpgsql stable security definer set search_path = public as $$
begin
  perform be_exigir_criador();
  return coalesce((select jsonb_agg(to_jsonb(l) order by l.created_at desc) from be_leads l where p_status is null or l.status = p_status), '[]'::jsonb);
end $$;

create or replace function public.be_admin_lead_status(p_id uuid, p_status text, p_nota text default null) returns jsonb
language plpgsql security definer set search_path = public as $$
begin
  perform be_exigir_criador();
  if p_status not in ('novo', 'em_contato', 'convertido', 'descartado') then raise exception 'status inválido'; end if;
  update be_leads set status = p_status, nota = coalesce(nullif(left(btrim(coalesce(p_nota, '')), 1000), ''), nota), updated_at = now() where id = p_id;
  if not found then raise exception 'contato não encontrado'; end if;
  perform be_registrar_acao('criador', 'lead_' || p_status, 'lead', p_id, null, null);
  return jsonb_build_object('ok', true);
end $$;

create or replace function public.be_admin_planos() returns jsonb
language plpgsql stable security definer set search_path = public as $$
begin
  perform be_exigir_criador();
  return coalesce((select jsonb_agg(to_jsonb(p) || jsonb_build_object('escolas', (select count(*) from be_assinaturas a where a.plano_id = p.id and a.status = 'ativo')) order by p.ordem)
                   from be_planos p), '[]'::jsonb);
end $$;

create or replace function public.be_admin_plano_salvar(p_id uuid, p_dados jsonb) returns jsonb
language plpgsql security definer set search_path = public as $$
declare v_rec jsonb := coalesce(p_dados -> 'recursos', '[]'::jsonb);
begin
  perform be_exigir_criador();
  if jsonb_typeof(v_rec) <> 'array' then raise exception 'recursos inválidos'; end if;
  if char_length(coalesce(be_txt(p_dados, 'nome', 60), '')) < 2 then raise exception 'dá um nome pro plano'; end if;
  if p_id is null then
    insert into be_planos (codigo, nome) values (be_slug_livre_plano(be_txt(p_dados, 'nome', 60)), be_txt(p_dados, 'nome', 60)) returning id into p_id;
  end if;
  update be_planos set
    nome = be_txt(p_dados, 'nome', 60),
    descricao = be_txt(p_dados, 'descricao', 500),
    preco_mensal = nullif(p_dados ->> 'preco_mensal', '')::numeric,
    recursos = (select coalesce(jsonb_agg(left(btrim(r), 120)), '[]') from jsonb_array_elements_text(v_rec) r where btrim(r) <> ''),
    limite_oportunidades = greatest(0, coalesce(nullif(p_dados ->> 'limite_oportunidades', '')::int, limite_oportunidades)),
    limite_alunos = nullif(p_dados ->> 'limite_alunos', '')::int,
    destaque = least(3, greatest(0, coalesce(nullif(p_dados ->> 'destaque', '')::int, destaque))),
    relatorios = coalesce(nullif(p_dados ->> 'relatorios', ''), relatorios),
    ativo = coalesce((p_dados ->> 'ativo')::boolean, ativo),
    updated_at = now()
  where id = p_id;
  perform be_registrar_acao('criador', 'plano_salvo', 'plano', p_id, null, p_dados);
  return jsonb_build_object('ok', true, 'id', p_id);
end $$;

create or replace function public.be_slug_livre_plano(p_nome text) returns text
language plpgsql stable security definer set search_path = public as $$
declare v_b text := coalesce(nullif(replace(be_slug(p_nome), '-', '_'), ''), 'plano'); v_s text := v_b; v_n int := 1;
begin
  while exists (select 1 from be_planos where codigo = v_s) loop v_n := v_n + 1; v_s := v_b || '_' || v_n; end loop;
  return v_s;
end $$;

create or replace function public.be_admin_contrato_salvar(p_inst uuid, p_dados jsonb) returns jsonb
language plpgsql security definer set search_path = public as $$
declare v_status text := coalesce(be_txt(p_dados, 'status', 20), 'interessado'); v_pag text := coalesce(be_txt(p_dados, 'pagamento', 20), 'nao_se_aplica');
begin
  perform be_exigir_criador();
  if v_status not in ('interessado', 'negociacao', 'ativo', 'pendente', 'cancelado') then raise exception 'situação inválida'; end if;
  if v_pag not in ('nao_se_aplica', 'em_dia', 'pendente', 'atrasado', 'isento') then raise exception 'pagamento inválido'; end if;
  if v_status = 'ativo' and nullif(p_dados ->> 'plano_id', '') is null then raise exception 'escolhe o plano do contrato ativo'; end if;
  insert into be_assinaturas (instituicao_id, plano_id, status, pagamento, valor_mensal, vigencia_inicio, vigencia_fim, observacao, updated_at)
  values (p_inst, nullif(p_dados ->> 'plano_id', '')::uuid, v_status, v_pag, nullif(p_dados ->> 'valor_mensal', '')::numeric,
          nullif(p_dados ->> 'vigencia_inicio', '')::date, nullif(p_dados ->> 'vigencia_fim', '')::date, be_txt(p_dados, 'observacao', 1000), now())
  on conflict (instituicao_id) do update set plano_id = excluded.plano_id, status = excluded.status, pagamento = excluded.pagamento,
    valor_mensal = excluded.valor_mensal, vigencia_inicio = excluded.vigencia_inicio, vigencia_fim = excluded.vigencia_fim,
    observacao = excluded.observacao, updated_at = now();
  perform be_registrar_acao('criador', 'contrato_salvo', 'instituicao', p_inst, p_inst, p_dados);
  return jsonb_build_object('ok', true);
end $$;

create or replace function public.be_admin_config_salvar(p_dados jsonb) returns jsonb
language plpgsql security definer set search_path = public as $$
declare v_k text;
begin
  perform be_exigir_criador();
  for v_k in select jsonb_object_keys(p_dados) loop
    if v_k not in ('whatsapp_comercial', 'email_comercial', 'limite_sem_plano', 'mensagem_whatsapp', 'mostrar_precos') then raise exception 'configuração desconhecida: %', v_k; end if;
  end loop;
  if p_dados ? 'whatsapp_comercial' and be_so_digitos(p_dados ->> 'whatsapp_comercial') is not null
     and char_length(be_so_digitos(p_dados ->> 'whatsapp_comercial')) not between 10 and 13 then raise exception 'confere o WhatsApp com DDD'; end if;
  if p_dados ? 'limite_sem_plano' and coalesce(p_dados ->> 'limite_sem_plano', '') !~ '^\d{1,2}$' then raise exception 'limite sem plano: número de 0 a 99'; end if;
  if p_dados ? 'mostrar_precos' and coalesce(p_dados ->> 'mostrar_precos', '') not in ('sim', 'nao') then raise exception 'mostrar preços: sim ou nao'; end if;
  insert into be_config_comercial (chave, valor, updated_at)
  select k, case when k = 'whatsapp_comercial' then be_so_digitos(p_dados ->> k) else be_txt(p_dados, k, 300) end, now() from jsonb_object_keys(p_dados) k
  on conflict (chave) do update set valor = excluded.valor, updated_at = now();
  perform be_registrar_acao('criador', 'config_salva', null, null, null, p_dados);
  return jsonb_build_object('ok', true);
end $$;

create or replace function public.be_admin_registro(p_inst uuid default null, p_limite int default 80) returns jsonb
language plpgsql stable security definer set search_path = public as $$
begin
  perform be_exigir_criador();
  return coalesce((
    select jsonb_agg(jsonb_build_object('acao', r.acao, 'papel', r.papel, 'quem', u.nome, 'alvo_tipo', r.alvo_tipo, 'escola', i.nome,
                                        'detalhe', r.detalhe, 'created_at', r.created_at) order by r.created_at desc)
    from (select * from be_registro_acoes where p_inst is null or instituicao_id = p_inst order by created_at desc
          limit least(greatest(coalesce(p_limite, 80), 1), 300)) r
    left join be_usuarios u on u.id = r.usuario_id left join be_instituicoes i on i.id = r.instituicao_id), '[]'::jsonb);
end $$;

-- painel do criador: escola de demonstração não entra nos números de pessoas
create or replace function public.be_eh_demo(p_usuario uuid) returns boolean
language sql stable security definer set search_path = public as $$
  select exists (select 1 from be_usuarios u join be_instituicoes i on i.id = u.instituicao_id where u.id = p_usuario and i.demo)
$$;

-- conta nova pelo app nunca nasce ligada a uma escola (quem liga é o banco)
create or replace function public.be_usuarios_protege() returns trigger
language plpgsql set search_path = public as $$
begin
  if current_user not in ('authenticated', 'anon') then return new; end if;
  if tg_op = 'INSERT' then
    new.xp := 0; new.nivel := 1; new.streak_atual := 0; new.streak_maior := 0; new.ultima_atividade := null; new.divisao := 'bronze';
    new.instituicao_id := null;
    if new.papel not in ('aluno', 'professor') then new.papel := 'aluno'; end if;
  else
    new.id := old.id; new.auth_user_id := old.auth_user_id; new.papel := old.papel;
    new.xp := old.xp; new.nivel := old.nivel; new.streak_atual := old.streak_atual; new.streak_maior := old.streak_maior;
    new.ultima_atividade := old.ultima_atividade; new.divisao := old.divisao; new.energia := old.energia;
    new.instituicao_id := old.instituicao_id;
  end if;
  return new;
end $$;

-- números do painel do criador sem as contas, turmas e matérias da escola de demonstração
create or replace function public.be_painel_criador() returns json
language plpgsql stable security definer set search_path = public as $$
declare v_hoje date := be_hoje(); v_ini timestamptz := (be_hoje()::timestamp at time zone 'America/Sao_Paulo');
begin
  perform be_exigir_criador();
  return json_build_object(
    'numeros', json_build_object(
      'contas', (select count(*) from be_usuarios u where not be_eh_demo(u.id)),
      'professores', (select count(*) from be_usuarios u where papel = 'professor' and not be_eh_demo(u.id)),
      'novos_7d', (select count(*) from be_usuarios u where created_at > now() - interval '7 days' and not be_eh_demo(u.id)),
      'ativos_hoje', (select count(*) from be_usuarios u where ultima_atividade = v_hoje and not be_eh_demo(u.id)),
      'ativos_7d', (select count(*) from be_usuarios u where ultima_atividade >= v_hoje - 6 and not be_eh_demo(u.id)),
      'materias', (select count(*) from be_materias m left join be_grupos g on g.id = m.grupo_id left join be_instituicoes i on i.id = g.instituicao_id
                   where not coalesce(i.demo, false) and (m.usuario_id is null or not be_eh_demo(m.usuario_id))),
      'materias_7d', (select count(*) from be_materias m left join be_grupos g on g.id = m.grupo_id left join be_instituicoes i on i.id = g.instituicao_id
                      where m.created_at > now() - interval '7 days' and not coalesce(i.demo, false) and (m.usuario_id is null or not be_eh_demo(m.usuario_id))),
      'turmas', (select count(*) from be_grupos g left join be_instituicoes i on i.id = g.instituicao_id where g.tipo = 'turma_professor' and not coalesce(i.demo, false)),
      'grupos_amigos', (select count(*) from be_grupos g left join be_instituicoes i on i.id = g.instituicao_id where g.tipo = 'grupo_amigos' and not coalesce(i.demo, false)),
      'ia_hoje', (select coalesce(sum(quantidade), 0) from be_uso_ia where data = current_date and not be_eh_demo(usuario_id)),
      'tutor_hoje', (select coalesce(sum(quantidade), 0) from be_uso_tutor where data = current_date and not be_eh_demo(usuario_id)),
      'resumos', (select count(*) from be_resumos where status = 'publicado' and not be_eh_demo(autor_id)),
      'mensagens_hoje', (select count(*) from be_sala_mensagens where created_at >= v_ini and not be_eh_demo(usuario_id)),
      'simulados_7d', (select count(*) from be_simulados where iniciado_em > now() - interval '7 days' and not be_eh_demo(usuario_id)),
      'redacoes_7d', (select count(*) from be_redacoes where created_at > now() - interval '7 days' and not be_eh_demo(usuario_id)),
      'demo', (select count(*) from be_usuarios u where be_eh_demo(u.id))),
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
      from be_silenciados z where z.ate > now()), '[]'::json),
    'comercial', json_build_object(
      'escolas_pendentes', (select count(*) from be_instituicoes where status = 'pendente'),
      'oportunidades_pendentes', (select count(*) from be_oportunidades where status = 'pendente'),
      'leads_novos', (select count(*) from be_leads where status = 'novo')));
end $$;

-- =========================================================
-- AJUDANTES INTERNOS: só as funções do banco chamam (o app não chama direto)
-- be_escola_metricas_json, por exemplo, devolveria os números de qualquer escola sem conferir quem pede.
-- Ficam abertas só as que as regras de acesso usam (be_sou_da_escola e be_pode_enviar_imagem_escola).
-- =========================================================
revoke execute on function public.be_registrar_acao(text, text, text, uuid, uuid, jsonb) from public, anon, authenticated;
revoke execute on function public.be_plano_da_escola(uuid) from public, anon, authenticated;
revoke execute on function public.be_limite_oportunidades(uuid) from public, anon, authenticated;
revoke execute on function public.be_oportunidades_em_uso(uuid, uuid) from public, anon, authenticated;
revoke execute on function public.be_escola_json(public.be_instituicoes) from public, anon, authenticated;
revoke execute on function public.be_oportunidade_json(public.be_oportunidades, public.be_instituicoes) from public, anon, authenticated;
revoke execute on function public.be_escola_metricas_json(uuid, int) from public, anon, authenticated;
revoke execute on function public.be_slug_livre(text, uuid) from public, anon, authenticated;
revoke execute on function public.be_slug_livre_plano(text) from public, anon, authenticated;
revoke execute on function public.be_codigo_aleatorio(int) from public, anon, authenticated;
revoke execute on function public.be_eh_demo(uuid) from public, anon, authenticated;
