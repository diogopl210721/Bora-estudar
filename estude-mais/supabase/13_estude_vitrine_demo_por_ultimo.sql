-- EstudeUp — no mural e na lista de escolas, a escola de demonstração aparece sempre depois das escolas de verdade
-- (mesmo com plano de destaque). Só troca a ordem; o resto das duas funções é igual ao da migração 11.

create or replace function public.be_vitrine_escolas(p_busca text default null, p_cidade text default null, p_tipo text default null) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare v_b text := nullif(btrim(coalesce(p_busca, '')), '');
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
declare v_b text := nullif(btrim(coalesce(p_busca, '')), '');
begin
  return coalesce((
    select jsonb_agg(x.j order by x.demo, x.destaque desc, x.publicada desc)
    from (
      select be_oportunidade_json(o, i) as j, i.demo, coalesce((be_plano_da_escola(i.id)).destaque, 0) as destaque,
             coalesce(o.aprovada_em, o.created_at) as publicada
      from be_oportunidades o join be_instituicoes i on i.id = o.instituicao_id
      where o.status = 'publicada' and be_hoje() between o.inicio and o.fim and i.status = 'aprovada'
        and (p_categoria is null or o.categoria = p_categoria)
        and (p_cidade is null or lower(i.cidade) = lower(p_cidade) or o.online)
        and (v_b is null or o.titulo ilike '%' || v_b || '%' or o.descricao ilike '%' || v_b || '%' or i.nome ilike '%' || v_b || '%')
      order by i.demo, destaque desc, publicada desc
      limit least(greatest(coalesce(p_limite, 30), 1), 60) offset greatest(coalesce(p_offset, 0), 0)) x), '[]'::jsonb);
end $$;
