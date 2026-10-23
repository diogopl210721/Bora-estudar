-- Estude+ — conta do criador: achar uma conta pelo nome ou e-mail (pra trocar a senha ou silenciar).
-- A troca de senha em si é feita pela Edge Function estude-criador-senha, que confere de novo se quem pediu é o criador.
-- Só cria ou substitui (pode rodar de novo).

create or replace function public.be_buscar_contas(p_busca text) returns json
language plpgsql stable security definer set search_path = public as $$
declare v_b text := btrim(coalesce(p_busca, ''));
begin
  perform be_exigir_criador();
  if char_length(v_b) < 2 then return '[]'::json; end if;
  v_b := replace(replace(replace(v_b, '\', '\\'), '%', '\%'), '_', '\_');
  return coalesce((
    select json_agg(x.j order by x.criada desc) from (
      select u.created_at as criada,
             json_build_object('id', u.id, 'nome', u.nome, 'email', a.email, 'papel', u.papel, 'serie', u.serie, 'escola', u.escola,
                               'nivel', u.nivel, 'ultima_atividade', u.ultima_atividade, 'criada', u.created_at,
                               'equipe', be_eh_criador(u.id), 'silenciado_ate', be_silenciado_ate(u.id)) as j
      from be_usuarios u left join auth.users a on a.id = u.auth_user_id
      where u.nome ilike '%' || v_b || '%' or a.email ilike '%' || v_b || '%'
      order by u.created_at desc
      limit 20) x), '[]'::json);
end $$;
