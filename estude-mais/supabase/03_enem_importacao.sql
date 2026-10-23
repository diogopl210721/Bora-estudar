-- Estude+ — apoio à importação única das questões do ENEM (usado pela função estude-importar-enem)

create table if not exists public.be_import_chave (
  chave text primary key,
  criada_em timestamptz not null default now()
);
alter table public.be_import_chave enable row level security;  -- sem políticas: só service role

create or replace function public.be_enem_upsert(p_chave text, p_linhas jsonb) returns int
language plpgsql security definer set search_path = public as $$
declare v_n int;
begin
  perform be_exigir_interno();
  if not exists (select 1 from be_import_chave where chave = p_chave and criada_em > now() - interval '2 hours') then
    raise exception 'chave inválida';
  end if;
  insert into be_enem_questoes (ano, numero, idioma, area, contexto, introducao, alternativas, gabarito)
  select x.ano, x.numero, x.idioma, x.area, x.contexto, x.introducao, x.alternativas, x.gabarito
  from jsonb_to_recordset(p_linhas) as x(ano smallint, numero smallint, idioma text, area text,
                                         contexto text, introducao text, alternativas jsonb, gabarito text)
  on conflict (ano, numero, coalesce(idioma, '')) do update set
    area = excluded.area, contexto = excluded.contexto, introducao = excluded.introducao,
    alternativas = excluded.alternativas, gabarito = excluded.gabarito;
  get diagnostics v_n = row_count;
  return v_n;
end $$;
