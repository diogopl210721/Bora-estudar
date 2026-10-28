-- EstudeUp — ao remontar o plano de prova, as tarefas antigas ficam marcadas como substituídas em vez de apagadas.
alter table public.be_plano_tarefas add column if not exists substituida boolean not null default false;
create index if not exists be_plano_tarefas_ativas_idx on public.be_plano_tarefas (usuario_id, dia) where not substituida;

-- o app nunca vê nem mexe numa tarefa substituída (política restritiva, soma com as que já existem)
do $$ begin
  if not exists (select 1 from pg_policies where tablename = 'be_plano_tarefas' and policyname = 'esconder substituidas') then
    create policy "esconder substituidas" on public.be_plano_tarefas as restrictive for select to authenticated using (not substituida);
  end if;
  if not exists (select 1 from pg_policies where tablename = 'be_plano_tarefas' and policyname = 'nao editar substituidas') then
    create policy "nao editar substituidas" on public.be_plano_tarefas as restrictive for update to authenticated using (not substituida);
  end if;
end $$;
