-- =====================================================================================
-- EstudeUp · 18: visão geral da escola para a coordenação (só números, nenhum dado pessoal de aluno)
-- Alunos por série, ativos na semana e totais. Só o gestor da escola (ou a equipe EstudeUp) vê.
-- =====================================================================================
create or replace function public.be_escola_visao(p_inst uuid) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare v_u uuid := be_usuario_atual_id();
begin
  if v_u is null then raise exception 'faça login de novo'; end if;
  if not (be_sou_criador() or exists (select 1 from be_instituicao_membros m where m.instituicao_id = p_inst and m.usuario_id = v_u and m.papel = 'gestor')) then
    raise exception 'só a coordenação da escola vê isso';
  end if;
  return (
    with alunos as (
      select distinct u.id, coalesce(nullif(btrim(u.serie), ''), 'sem série') as serie, u.ultima_atividade
      from be_grupos g join be_grupo_membros gm on gm.grupo_id = g.id and gm.papel_no_grupo = 'membro'
      join be_usuarios u on u.id = gm.usuario_id
      where g.instituicao_id = p_inst)
    select jsonb_build_object(
      'alunos', (select count(*) from alunos),
      'ativos_7d', (select count(*) from alunos where ultima_atividade >= be_hoje() - 6),
      'ativos_hoje', (select count(*) from alunos where ultima_atividade >= be_hoje()),
      'professores', (select count(*) from be_instituicao_membros m where m.instituicao_id = p_inst and m.papel = 'professor'),
      'turmas', (select count(*) from be_grupos g where g.instituicao_id = p_inst),
      'series', coalesce((select jsonb_agg(jsonb_build_object('serie', serie, 'alunos', n, 'ativos_7d', a) order by serie)
                          from (select serie, count(*) n, count(*) filter (where ultima_atividade >= be_hoje() - 6) a from alunos group by serie) s), '[]'::jsonb)));
end $$;
revoke execute on function public.be_escola_visao(uuid) from public, anon;
grant execute on function public.be_escola_visao(uuid) to authenticated;
