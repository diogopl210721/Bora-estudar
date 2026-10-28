-- EstudeUp — imagens das escolas (logo, capa e imagens das oportunidades).
-- Pasta pública "estude-escolas": qualquer pessoa vê (a página da escola é aberta), só o gestor da escola
-- (ou a conta do criador) envia, e só na pasta da própria escola: <id da escola>/<arquivo>.(jpg|jpeg|png|webp), até 3 MB.
-- Só cria (pode rodar de novo). Não mexe nas outras pastas do projeto.

insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('estude-escolas', 'estude-escolas', true, 3145728, array['image/jpeg', 'image/png', 'image/webp'])
on conflict (id) do nothing;

do $$ begin
  if not exists (select 1 from pg_policies where schemaname = 'storage' and tablename = 'objects' and policyname = 'estude-escolas: gestor envia') then
    create policy "estude-escolas: gestor envia" on storage.objects for insert to authenticated
      with check (bucket_id = 'estude-escolas' and public.be_pode_enviar_imagem_escola(name));
  end if;
  -- trocar a imagem com o mesmo nome (upsert) precisa de update
  if not exists (select 1 from pg_policies where schemaname = 'storage' and tablename = 'objects' and policyname = 'estude-escolas: gestor troca') then
    create policy "estude-escolas: gestor troca" on storage.objects for update to authenticated
      using (bucket_id = 'estude-escolas' and public.be_pode_enviar_imagem_escola(name))
      with check (bucket_id = 'estude-escolas' and public.be_pode_enviar_imagem_escola(name));
  end if;
end $$;
