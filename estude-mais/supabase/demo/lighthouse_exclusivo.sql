-- =====================================================================================
-- EstudeUp · demonstração do APP EXCLUSIVO para apresentar ao Colégio Lighthouse
-- Marca e logo do colégio só para a apresentação. Fica marcada como demonstração (demo = true)
-- e em modo 'exclusiva': NÃO aparece na vitrine pública nem para alunos de fora.
-- Contas fictícias (example.com): aluno.lighthouse / coordenacao.lighthouse, senha Lighthouse2026.
-- As turmas são cópias das turmas do Colégio Monte Aurora (fictício), para o aluno já ter conteúdo.
-- Avisos e oportunidades são EXEMPLOS (o título começa com "Exemplo:"), não ofertas reais do colégio.
-- Pode rodar de novo: não duplica.
-- =====================================================================================
do $$
declare
  v_base text := 'https://www.ddsinovacao.com.br/estudemais/demo/lighthouse/';
  v_inst uuid; v_aluno uuid; v_coord uuid; v_ma uuid; r record; v_g uuid; v_m uuid; v_t uuid; v_c uuid;
begin
  -- perfis das duas contas
  insert into be_usuarios (auth_user_id, nome, papel, escola, cidade, serie)
  select a.id, x.nome, x.papel, 'Colégio Lighthouse', 'Curitiba', x.serie
  from (values ('aluno.lighthouse@example.com', 'Pedro Lima', 'aluno', '9º ano'),
               ('coordenacao.lighthouse@example.com', 'Coordenação Lighthouse', 'professor', null)) x(email, nome, papel, serie)
  join auth.users a on lower(a.email) = x.email
  where not exists (select 1 from be_usuarios u where u.auth_user_id = a.id);
  select u.id into v_aluno from be_usuarios u join auth.users a on a.id = u.auth_user_id where lower(a.email) = 'aluno.lighthouse@example.com';
  select u.id into v_coord from be_usuarios u join auth.users a on a.id = u.auth_user_id where lower(a.email) = 'coordenacao.lighthouse@example.com';
  if v_aluno is null or v_coord is null then raise exception 'crie antes as duas contas pelo cadastro do app'; end if;

  -- a escola
  select id into v_inst from be_instituicoes where slug = 'colegio-lighthouse';
  if v_inst is null then
    insert into be_instituicoes (nome, slug, tipo, status, demo, modo, logo_url, capa_url, cor_primaria, cor_secundaria,
      descricao, cidade, uf, publico, dono_id, aprovada_em, codigo_professor)
    values ('Colégio Lighthouse', 'colegio-lighthouse', 'escola', 'aprovada', true, 'exclusiva', v_base || 'logo.webp', v_base || 'capa.webp',
      '#1B3A8C', '#E4002B', 'Ensino bilíngue. Este é o app do colégio para os alunos estudarem com plano até a prova, quiz, flashcards e inglês todo dia.',
      'Curitiba', 'PR', 'Ensino Fundamental e Médio', v_coord, now(), 'LHDEMO')
    returning id into v_inst;
  else
    update be_instituicoes set demo = true, modo = 'exclusiva', status = 'aprovada', logo_url = v_base || 'logo.webp', capa_url = v_base || 'capa.webp' where id = v_inst;
  end if;
  update be_usuarios set instituicao_id = v_inst where id in (v_aluno, v_coord);
  insert into be_instituicao_membros (instituicao_id, usuario_id, papel) values (v_inst, v_coord, 'gestor') on conflict do nothing;

  -- turmas copiadas do Monte Aurora (com matérias, tópicos, resumo, quiz, prova e flashcards)
  select id into v_ma from be_instituicoes where slug = 'colegio-monte-aurora';
  for r in select g.*, x.novo from be_grupos g
           join (values ('3º A · Matemática', '9º ano · Matemática', 'LHMAT9'), ('2º B · Biologia', '9º ano · Ciências', 'LHCIE9')) x(velho, novo, cod) on x.velho = g.nome
           where g.instituicao_id = v_ma loop
    if exists (select 1 from be_grupos where instituicao_id = v_inst and nome = r.novo) then continue; end if;
    insert into be_grupos (nome, tipo, materia, dono_id, codigo, permite_upload_aluno, instituicao_id)
    values (r.novo, r.tipo, r.materia, v_coord, case when r.novo like '%Mat%' then 'LHMAT9' else 'LHCIE9' end, r.permite_upload_aluno, v_inst)
    returning id into v_g;
    insert into be_grupo_membros (grupo_id, usuario_id, papel_no_grupo) values (v_g, v_coord, 'admin'), (v_g, v_aluno, 'membro');
    insert into be_salas (nome, descricao, materia, icone, grupo_id, oficial, ordem)
    select r.novo, s.descricao, s.materia, s.icone, v_g, s.oficial, s.ordem from be_salas s where s.grupo_id = r.id;
    for v_m in select id from be_materias where grupo_id = r.id loop
      declare v_nm uuid; mapa jsonb := '{}'; t record; c record; begin
        insert into be_materias (usuario_id, grupo_id, nome, data_prova, status)
        select m.usuario_id, v_g, m.nome, be_hoje() + 12, m.status from be_materias m where m.id = v_m returning id into v_nm;
        for t in select * from be_topicos where materia_id = v_m loop
          insert into be_topicos (materia_id, nome, ordem) values (v_nm, t.nome, t.ordem) returning id into v_t;
          mapa := mapa || jsonb_build_object(t.id::text, v_t);
        end loop;
        insert into be_materiais (materia_id, tipo, url_externa, texto_extraido, importado_por)
        select v_nm, tipo, url_externa, texto_extraido, v_coord from be_materiais where materia_id = v_m;
        for c in select * from be_conteudo_gerado where materia_id = v_m and tipo <> 'quiz_topico' loop
          insert into be_conteudo_gerado (materia_id, tipo, conteudo) values (v_nm, c.tipo, c.conteudo) returning id into v_c;
          insert into be_quiz_perguntas (conteudo_gerado_id, pergunta, opcoes, resposta_correta, explicacao, ordem, topico_id)
          select v_c, q.pergunta, q.opcoes, q.resposta_correta, q.explicacao, q.ordem, (mapa ->> q.topico_id::text)::uuid
          from be_quiz_perguntas q where q.conteudo_gerado_id = c.id;
        end loop;
        insert into be_cards (materia_id, topico_id, frente, verso, origem, criado_por)
        select v_nm, (mapa ->> k.topico_id::text)::uuid, k.frente, k.verso, k.origem, v_coord from be_cards k where k.materia_id = v_m;
      end;
    end loop;
  end loop;

  -- avisos de exemplo da escola (só o aluno dela vê)
  if not exists (select 1 from be_oportunidades where instituicao_id = v_inst) then
    insert into be_oportunidades (instituicao_id, titulo, descricao, categoria, inicio, fim, status, aprovada_em, criado_por, imagem_url)
    values
      (v_inst, 'Exemplo: Semana bilíngue', 'Aviso de exemplo para mostrar como a escola fala com os alunos pelo app: programação, horários e o que levar.', 'evento', be_hoje() - 1, be_hoje() + 30, 'publicada', now(), v_coord, v_base || 'capa.webp'),
      (v_inst, 'Exemplo: Simulado do 9º ano', 'Aviso de exemplo: data do simulado e as matérias que caem. O plano de estudos no app já leva a data em conta.', 'evento', be_hoje() - 1, be_hoje() + 30, 'publicada', now(), v_coord, null),
      (v_inst, 'Exemplo: Reforço de matemática', 'Aviso de exemplo de atividade no contraturno, com inscrição pela secretaria.', 'curso_novo', be_hoje() - 1, be_hoje() + 30, 'publicada', now(), v_coord, null);
  end if;
end $$;
