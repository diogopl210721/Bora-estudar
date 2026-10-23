-- Estude+ — quem põe material num grupo: na turma do professor só ele (dono ou admin); no grupo de amigos, qualquer membro.
-- Vale pra matéria nova do grupo, material novo, flashcard criado à mão, data da prova e nota real.

-- usuário logado (usada nas regras de acesso)
create or replace function public.be_pode_editar_grupo(p_grupo uuid) returns boolean
language sql stable security definer set search_path = public as $$
  select exists (
    select 1 from be_grupos g
    where g.id = p_grupo
      and (g.dono_id = be_usuario_atual_id()
           or exists (select 1 from be_grupo_membros gm
                      where gm.grupo_id = g.id and gm.usuario_id = be_usuario_atual_id()
                        and (gm.papel_no_grupo = 'admin' or g.tipo = 'grupo_amigos'))))
$$;

create or replace function public.be_pode_editar_materia(p_materia uuid) returns boolean
language sql stable security definer set search_path = public as $$
  select exists (
    select 1 from be_materias m
    where m.id = p_materia
      and (m.usuario_id = be_usuario_atual_id() or (m.grupo_id is not null and be_pode_editar_grupo(m.grupo_id))))
$$;

-- pra Edge Function (service role): mesma regra, com o usuário informado
create or replace function public.be_pode_editar_materia_para(p_usuario uuid, p_materia uuid) returns boolean
language plpgsql stable security definer set search_path = public as $$
begin
  perform be_exigir_interno();
  return exists (
    select 1 from be_materias m left join be_grupos g on g.id = m.grupo_id
    where m.id = p_materia
      and (m.usuario_id = p_usuario
           or g.dono_id = p_usuario
           or exists (select 1 from be_grupo_membros gm
                      where gm.grupo_id = m.grupo_id and gm.usuario_id = p_usuario
                        and (gm.papel_no_grupo = 'admin' or g.tipo = 'grupo_amigos'))));
end $$;

-- regras restritivas: somam com as que já existem (quem não pode editar o grupo não cria, muda nem tira matéria dele)
do $$ begin
  if not exists (select 1 from pg_policies where tablename = 'be_materias' and policyname = 'grupo: criar so quem pode') then
    create policy "grupo: criar so quem pode" on public.be_materias as restrictive for insert to authenticated
      with check (grupo_id is null or public.be_pode_editar_grupo(grupo_id));
  end if;
  if not exists (select 1 from pg_policies where tablename = 'be_materias' and policyname = 'grupo: editar so quem pode') then
    create policy "grupo: editar so quem pode" on public.be_materias as restrictive for update to authenticated
      using (grupo_id is null or public.be_pode_editar_grupo(grupo_id));
  end if;
  if not exists (select 1 from pg_policies where tablename = 'be_materias' and policyname = 'grupo: tirar so quem pode') then
    create policy "grupo: tirar so quem pode" on public.be_materias as restrictive for delete to authenticated
      using (grupo_id is null or public.be_pode_editar_grupo(grupo_id));
  end if;
  if not exists (select 1 from pg_policies where tablename = 'be_materiais' and policyname = 'grupo: material so quem pode') then
    create policy "grupo: material so quem pode" on public.be_materiais as restrictive for insert to authenticated
      with check (public.be_pode_editar_materia(materia_id));
  end if;
  if not exists (select 1 from pg_policies where tablename = 'be_cards' and policyname = 'grupo: card so quem pode') then
    create policy "grupo: card so quem pode" on public.be_cards as restrictive for insert to authenticated
      with check (public.be_pode_editar_materia(materia_id));
  end if;
end $$;
