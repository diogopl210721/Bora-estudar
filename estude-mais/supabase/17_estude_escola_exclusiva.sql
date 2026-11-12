-- =====================================================================================
-- EstudeUp · 17: escola com app exclusivo
-- modo 'parceira'  = aparece pra todos os alunos do EstudeUp (vitrine, carrossel de patrocinadoras)
-- modo 'exclusiva' = o app vira "da escola" pros alunos dela: marca dela no topo e no login, e eles
--                    não veem propaganda de outras escolas; a escola exclusiva não aparece pra quem é de fora.
-- Só acrescenta uma coluna (padrão 'parceira', igual a hoje) e funções; ninguém muda de comportamento sozinho.
-- =====================================================================================

alter table public.be_instituicoes add column if not exists modo text not null default 'parceira';
alter table public.be_instituicoes drop constraint if exists be_instituicoes_modo_check;
alter table public.be_instituicoes add constraint be_instituicoes_modo_check check (modo in ('parceira', 'exclusiva'));
alter table public.be_instituicoes add column if not exists nome_app text check (nome_app is null or length(nome_app) between 2 and 40);

-- a escola exclusiva do usuário (pelo cadastro dele ou pelas turmas da escola em que ele está)
create or replace function public.be_escola_exclusiva_de(p_usuario uuid) returns uuid
language sql stable security definer set search_path = public as $$
  select i.id from be_instituicoes i
  where i.modo = 'exclusiva' and i.status = 'aprovada'
    and (i.id = (select u.instituicao_id from be_usuarios u where u.id = p_usuario)
         or exists (select 1 from be_grupo_membros gm join be_grupos g on g.id = gm.grupo_id
                    where gm.usuario_id = p_usuario and g.instituicao_id = i.id)
         or exists (select 1 from be_instituicao_membros m where m.usuario_id = p_usuario and m.instituicao_id = i.id))
  order by i.created_at limit 1
$$;
revoke execute on function public.be_escola_exclusiva_de(uuid) from public, anon, authenticated;

-- marca do app pro usuário logado (null = EstudeUp normal)
create or replace function public.be_minha_marca() returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare v_u uuid := be_usuario_atual_id(); v_i be_instituicoes;
begin
  if v_u is null then return null; end if;
  select * into v_i from be_instituicoes where id = be_escola_exclusiva_de(v_u);
  if v_i.id is null then return null; end if;
  return jsonb_build_object('id', v_i.id, 'slug', v_i.slug, 'nome', v_i.nome, 'nome_app', coalesce(v_i.nome_app, v_i.nome),
    'logo_url', v_i.logo_url, 'cor', v_i.cor_primaria, 'demo', v_i.demo);
end $$;

-- marca pela URL (?escola=slug), antes do login: só nome, logo e cor de escola aprovada e exclusiva
create or replace function public.be_marca_por_slug(p_slug text) returns jsonb
language sql stable security definer set search_path = public as $$
  select jsonb_build_object('slug', i.slug, 'nome', i.nome, 'nome_app', coalesce(i.nome_app, i.nome),
    'logo_url', i.logo_url, 'cor', i.cor_primaria, 'demo', i.demo)
  from be_instituicoes i
  where i.slug = lower(btrim(coalesce(p_slug, ''))) and i.status = 'aprovada' and i.modo = 'exclusiva'
$$;

revoke execute on function public.be_minha_marca() from public, anon;
grant execute on function public.be_minha_marca() to authenticated;
revoke execute on function public.be_marca_por_slug(text) from public;
grant execute on function public.be_marca_por_slug(text) to anon, authenticated;

-- vitrine: aluno de escola exclusiva só vê a própria escola; escola exclusiva não aparece pra quem é de fora
create or replace function public.be_vitrine_escolas(p_busca text default null, p_cidade text default null, p_tipo text default null) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare
  v_b text := nullif(btrim(coalesce(p_busca, '')), '');
  v_excl uuid := case when be_usuario_atual_id() is null then null else be_escola_exclusiva_de(be_usuario_atual_id()) end;
begin
  return coalesce((
    select jsonb_agg(x.j order by x.demo, x.destaque desc, x.ativas desc, x.nome)
    from (
      select i.nome, i.demo, coalesce((be_plano_da_escola(i.id)).destaque, 0) as destaque,
             (select count(*) from be_oportunidades o where o.instituicao_id = i.id and o.status = 'publicada' and be_hoje() between o.inicio and o.fim) as ativas,
             be_escola_json(i) || jsonb_build_object('oportunidades_ativas',
               (select count(*) from be_oportunidades o where o.instituicao_id = i.id and o.status = 'publicada' and be_hoje() between o.inicio and o.fim)) as j
      from be_instituicoes i
      where i.status = 'aprovada'
        and (case when v_excl is not null then i.id = v_excl else i.modo = 'parceira' end)
        and (p_cidade is null or lower(i.cidade) = lower(p_cidade))
        and (p_tipo is null or i.tipo = p_tipo)
        and (v_b is null or i.nome ilike '%' || v_b || '%' or i.descricao ilike '%' || v_b || '%' or i.cursos::text ilike '%' || v_b || '%')
      order by i.demo, i.nome
      limit 100) x), '[]'::jsonb);
end $$;

create or replace function public.be_vitrine_oportunidades(
  p_categoria text default null, p_cidade text default null, p_busca text default null,
  p_limite int default 30, p_offset int default 0) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare
  v_b text := nullif(btrim(coalesce(p_busca, '')), '');
  v_excl uuid := case when be_usuario_atual_id() is null then null else be_escola_exclusiva_de(be_usuario_atual_id()) end;
begin
  return coalesce((
    select jsonb_agg(x.j order by x.demo, x.destaque desc, x.publicada desc)
    from (
      select be_oportunidade_json(o, i) as j, i.demo, coalesce((be_plano_da_escola(i.id)).destaque, 0) as destaque,
             coalesce(o.aprovada_em, o.created_at) as publicada
      from be_oportunidades o join be_instituicoes i on i.id = o.instituicao_id
      where o.status = 'publicada' and be_hoje() between o.inicio and o.fim and i.status = 'aprovada'
        and (case when v_excl is not null then i.id = v_excl else i.modo = 'parceira' end)
        and (p_categoria is null or o.categoria = p_categoria)
        and (p_cidade is null or lower(i.cidade) = lower(p_cidade) or o.online)
        and (v_b is null or o.titulo ilike '%' || v_b || '%' or o.descricao ilike '%' || v_b || '%' or i.nome ilike '%' || v_b || '%')
      order by i.demo, destaque desc, publicada desc
      limit least(greatest(coalesce(p_limite, 30), 1), 60) offset greatest(coalesce(p_offset, 0), 0)) x), '[]'::jsonb);
end $$;

-- área comercial: o criador troca o modo da escola (e o nome que aparece no app exclusivo)
create or replace function public.be_comercial_modo_escola(p_inst uuid, p_modo text, p_nome_app text default null) returns jsonb
language plpgsql security definer set search_path = public as $$
declare v_u uuid := be_usuario_atual_id();
begin
  if v_u is null or not be_sou_criador() then raise exception 'só a equipe do EstudeUp muda isso'; end if;
  if p_modo not in ('parceira', 'exclusiva') then raise exception 'modo inválido'; end if;
  update be_instituicoes set modo = p_modo, nome_app = nullif(btrim(coalesce(p_nome_app, '')), ''), updated_at = now() where id = p_inst;
  if not found then raise exception 'escola não encontrada'; end if;
  perform be_registrar_acao('criador', 'modo_' || p_modo, 'instituicao', p_inst, p_inst, jsonb_build_object('nome_app', p_nome_app));
  return jsonb_build_object('ok', true, 'modo', p_modo);
end $$;
revoke execute on function public.be_comercial_modo_escola(uuid, text, text) from public, anon;
grant execute on function public.be_comercial_modo_escola(uuid, text, text) to authenticated;

-- o JSON da escola passa a dizer o modo (a área comercial mostra e troca)
create or replace function public.be_escola_json(i public.be_instituicoes) returns jsonb
language sql stable security definer set search_path = public as $$
  select jsonb_build_object(
    'id', i.id, 'slug', i.slug, 'nome', i.nome, 'tipo', i.tipo, 'demo', i.demo, 'descricao', i.descricao,
    'cidade', i.cidade, 'uf', i.uf, 'regiao', i.regiao, 'endereco', i.endereco, 'modalidades', to_jsonb(i.modalidades),
    'publico', i.publico, 'cursos', i.cursos, 'site', i.site, 'instagram', i.instagram, 'facebook', i.facebook,
    'whatsapp', i.whatsapp, 'telefone', i.telefone, 'email', i.email_contato,
    'logo_url', i.logo_url, 'capa_url', i.capa_url, 'cor', i.cor_primaria,
    'destaque', coalesce((be_plano_da_escola(i.id)).destaque, 0),
    'modo', i.modo, 'nome_app', i.nome_app)
$$;
revoke execute on function public.be_escola_json(public.be_instituicoes) from public, anon, authenticated;
