-- EstudeUp — o app passou a se chamar EstudeUp (antes Estude+).
-- Troca o nome nas mensagens que as funções do banco mostram e nos textos de planos e configurações.
-- Não muda regra nenhuma: cada função é recriada igual, só com o nome novo no texto (permissões ficam como estão).
do $$
declare f record;
begin
  for f in select p.oid from pg_proc p
           where p.pronamespace = 'public'::regnamespace and p.proname like 'be\_%' and p.prosrc like '%Estude+%' loop
    execute replace(pg_get_functiondef(f.oid), 'Estude+', 'EstudeUp');
  end loop;
end $$;

update public.be_planos set descricao = replace(descricao, 'Estude+', 'EstudeUp'),
  recursos = replace(recursos::text, 'Estude+', 'EstudeUp')::jsonb, updated_at = now()
where descricao like '%Estude+%' or recursos::text like '%Estude+%';

update public.be_config_comercial set valor = replace(valor, 'Estude+', 'EstudeUp'), updated_at = now()
where valor like '%Estude+%';

update public.be_instituicoes set descricao = replace(descricao, 'Estude+', 'EstudeUp'), updated_at = now()
where demo and descricao like '%Estude+%';
