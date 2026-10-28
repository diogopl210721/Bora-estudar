-- =====================================================================================
-- EstudeUp · Colégio Monte Aurora — escola FICTÍCIA de demonstração (parte 1: escola, pessoas, turmas, mural)
-- Nome, logo, pessoas, ofertas e números são inventados para mostrar o EstudeUp funcionando.
-- Tudo fica marcado: be_instituicoes.demo = true e as contas ligadas a ela (be_usuarios.instituicao_id).
-- O painel do criador e a área comercial não contam nada disso nos números reais.
-- Pode rodar de novo (não duplica). Antes, as 5 contas de login precisam existir (cadastro normal do app):
--   coordenacao / helena / ricardo / camila / laura  .monteaurora@example.com  (example.com é domínio reservado)
-- Depois desta parte: gerar o conteúdo das 3 matérias pela função estude-gerar-conteudo (Texto, Foto e PDF)
-- e rodar a parte 2 (progresso dos alunos e conversa nas salas).
-- =====================================================================================
do $$
declare
  v_base text := 'https://www.ddsinovacao.com.br/estudemais/demo/monte-aurora/';
  v_inst uuid; v_coord uuid; v_helena uuid; v_ricardo uuid; v_camila uuid; v_laura uuid;
  v_g uuid; v_m uuid; v_s uuid; v_plano uuid; r record;
begin
  -- ---------- contas de login (perfil no EstudeUp) ----------
  insert into be_usuarios (auth_user_id, nome, papel, escola, cidade, serie)
  select a.id, x.nome, x.papel, 'Colégio Monte Aurora', 'Curitiba', x.serie
  from (values ('coordenacao.monteaurora@example.com', 'Coordenação Monte Aurora', 'professor', null),
               ('helena.monteaurora@example.com', 'Helena Duarte', 'professor', null),
               ('ricardo.monteaurora@example.com', 'Ricardo Almeida', 'professor', null),
               ('camila.monteaurora@example.com', 'Camila Rocha', 'professor', null),
               ('laura.monteaurora@example.com', 'Laura Mendes', 'aluno', '3º EM')) x(email, nome, papel, serie)
  join auth.users a on lower(a.email) = x.email
  where not exists (select 1 from be_usuarios u where u.auth_user_id = a.id);

  select u.id into v_coord from be_usuarios u join auth.users a on a.id = u.auth_user_id where lower(a.email) = 'coordenacao.monteaurora@example.com';
  select u.id into v_helena from be_usuarios u join auth.users a on a.id = u.auth_user_id where lower(a.email) = 'helena.monteaurora@example.com';
  select u.id into v_ricardo from be_usuarios u join auth.users a on a.id = u.auth_user_id where lower(a.email) = 'ricardo.monteaurora@example.com';
  select u.id into v_camila from be_usuarios u join auth.users a on a.id = u.auth_user_id where lower(a.email) = 'camila.monteaurora@example.com';
  select u.id into v_laura from be_usuarios u join auth.users a on a.id = u.auth_user_id where lower(a.email) = 'laura.monteaurora@example.com';
  if v_coord is null or v_helena is null or v_ricardo is null or v_camila is null or v_laura is null then
    raise exception 'faltam contas de login da demonstração (crie pelo cadastro do app antes)';
  end if;

  -- ---------- a escola ----------
  select id into v_inst from be_instituicoes where slug = 'colegio-monte-aurora';
  if v_inst is null then
    insert into be_instituicoes (nome, slug, tipo, status, demo, aprovada_em, dono_id, codigo_professor)
    values ('Colégio Monte Aurora', 'colegio-monte-aurora', 'escola', 'aprovada', true, now(), v_coord, be_codigo_aleatorio(6))
    returning id into v_inst;
  end if;
  update be_instituicoes set
    demo = true, status = 'aprovada', tipo = 'escola', cidade = 'Curitiba', uf = 'PR',
    cor_primaria = '#24306E', cor_secundaria = '#FF8A3D',
    descricao = 'No Monte Aurora ninguém estuda sozinho. Cada turma tem plano de estudo até a prova no EstudeUp, com quiz, flashcards e simulados, '
             || 'e os professores enxergam quem está travado antes da nota sair. Do 6º ano ao pré-vestibular, com laboratório maker, robótica, '
             || 'inglês todos os dias e plantão de dúvidas no contraturno. A gente quer aluno que entende a matéria, não só aluno que decora pra prova.',
    publico = 'Ensino Fundamental II (6º ao 9º ano), Ensino Médio e pré-vestibular',
    regiao = 'Curitiba e região metropolitana',
    endereco = 'Rua das Araucárias, 1200 · Bairro Alto (endereço fictício)',
    modalidades = '{presencial,hibrido}',
    cursos = '[{"nome":"Ensino Fundamental II","descricao":"6º ao 9º ano, de manhã, com robótica e inglês todos os dias."},
               {"nome":"Ensino Médio","descricao":"1º ao 3º ano, com trilhas de exatas, humanas e biológicas."},
               {"nome":"Pré-vestibular ENEM","descricao":"Revisão com simulado toda semana e redação corrigida."},
               {"nome":"Robótica e programação","descricao":"Contraturno, do 6º ao 9º ano, no laboratório maker."},
               {"nome":"Inglês intensivo","descricao":"Turmas por nível, de 11 a 17 anos."}]'::jsonb,
    site = 'https://monteaurora.example.com', instagram = null, facebook = null,
    whatsapp = '41999990000', telefone = '(41) 3000-0000', email_contato = 'contato@monteaurora.example.com',
    logo_url = v_base || 'logo.svg', capa_url = v_base || 'capa.webp', updated_at = now()
  where id = v_inst;

  -- coordenação = gestor; professores
  insert into be_instituicao_membros (instituicao_id, usuario_id, papel) values
    (v_inst, v_coord, 'gestor'), (v_inst, v_helena, 'professor'), (v_inst, v_ricardo, 'professor'), (v_inst, v_camila, 'professor')
  on conflict (instituicao_id, usuario_id) do update set papel = excluded.papel, ativo = true;

  update be_usuarios set instituicao_id = v_inst, escola = 'Colégio Monte Aurora', cidade = 'Curitiba'
  where id in (v_coord, v_helena, v_ricardo, v_camila, v_laura);
  update be_usuarios set serie = '3º EM' where id = v_laura;

  -- ---------- alunos sem login (só aparecem dentro das turmas da demonstração) ----------
  insert into be_usuarios (nome, papel, escola, cidade, serie, instituicao_id)
  select x.nome, 'aluno', 'Colégio Monte Aurora', 'Curitiba', x.serie, v_inst
  from (values ('Pedro Henrique Lima', '3º EM'), ('Beatriz Santos', '3º EM'), ('Gabriel Oliveira', '3º EM'), ('Sofia Carvalho', '3º EM'),
               ('Lucas Ferreira', '3º EM'), ('Isabela Costa', '3º EM'), ('Matheus Ribeiro', '3º EM'), ('Manuela Araújo', '3º EM'),
               ('Enzo Martins', '3º EM'),
               ('Valentina Gomes', '2º EM'), ('Davi Pereira', '2º EM'), ('Alice Barbosa', '2º EM'), ('Rafael Teixeira', '2º EM'),
               ('Yasmin Moreira', '2º EM')) x(nome, serie)
  where not exists (select 1 from be_usuarios u where u.instituicao_id = v_inst and u.nome = x.nome);

  -- ---------- turmas, salas e matérias ----------
  for r in select * from (values
      ('3º A · Matemática', 'Matemática', v_helena, '3º EM', 'Funções do 1º e do 2º grau', date '2026-11-17'),
      ('2º B · Biologia', 'Biologia', v_ricardo, '2º EM', 'Fotossíntese e respiração celular', date '2026-11-12'),
      ('3º A · Redação ENEM', 'Redação', v_camila, '3º EM', 'Redação ENEM: competências e estrutura', date '2026-11-06')
    ) t(nome, materia, dono, serie, materia_nome, prova)
  loop
    select id into v_g from be_grupos where instituicao_id = v_inst and nome = r.nome;
    if v_g is null then
      insert into be_grupos (nome, tipo, materia, dono_id, codigo, permite_upload_aluno, instituicao_id)
      values (r.nome, 'turma_professor', r.materia, r.dono,
              (select c from (select 'MA' || be_codigo_aleatorio(4) c from generate_series(1, 20)) z
               where not exists (select 1 from be_grupos g where g.codigo = z.c) limit 1),
              false, v_inst)
      returning id into v_g;
    end if;
    insert into be_grupo_membros (grupo_id, usuario_id, papel_no_grupo) values (v_g, r.dono, 'admin') on conflict (grupo_id, usuario_id) do nothing;
    insert into be_grupo_membros (grupo_id, usuario_id, papel_no_grupo)
    select v_g, u.id, 'membro' from be_usuarios u where u.instituicao_id = v_inst and u.papel = 'aluno' and u.serie = r.serie
    on conflict (grupo_id, usuario_id) do nothing;

    select id into v_s from be_salas where grupo_id = v_g;
    if v_s is null then
      insert into be_salas (nome, descricao, materia, icone, grupo_id, ordem) values (r.nome, 'Sala da turma', r.materia, '🏫', v_g, 0) returning id into v_s;
    end if;
    insert into be_sala_membros (sala_id, usuario_id) select v_s, gm.usuario_id from be_grupo_membros gm where gm.grupo_id = v_g on conflict do nothing;

    if not exists (select 1 from be_materias where grupo_id = v_g and nome = r.materia_nome) then
      insert into be_materias (grupo_id, nome, data_prova) values (v_g, r.materia_nome, r.prova);
    end if;
  end loop;

  -- ---------- plano (contrato de demonstração, sem cobrança) ----------
  select id into v_plano from be_planos where codigo = 'premium';
  insert into be_assinaturas (instituicao_id, plano_id, status, pagamento, valor_mensal, vigencia_inicio, vigencia_fim, observacao)
  values (v_inst, v_plano, 'ativo', 'isento', null, date '2026-10-01', date '2027-09-30', 'Escola de demonstração (fictícia): sem cobrança.')
  on conflict (instituicao_id) do update set plano_id = excluded.plano_id, status = 'ativo', pagamento = 'isento',
    vigencia_inicio = excluded.vigencia_inicio, vigencia_fim = excluded.vigencia_fim, observacao = excluded.observacao, updated_at = now();

  -- ---------- mural (com as condições escritas; tudo fictício) ----------
  insert into be_oportunidades (instituicao_id, titulo, descricao, categoria, imagem_url, local, online, inicio, fim, regras, status, aprovada_em, criado_por, created_at)
  select v_inst, x.titulo, x.descricao, x.categoria, v_base || x.img, x.local, x.online, x.inicio, x.fim, x.regras, x.status,
         case when x.status = 'publicada' then x.inicio::timestamptz + interval '10 hours' end, v_coord, x.inicio::timestamptz + interval '9 hours'
  from (values
    ('Prova de bolsas 2027: até 50% na mensalidade',
     'Vai cursar o Ensino Médio no ano que vem? Faça a prova de bolsas do Monte Aurora: 40 questões de português e matemática, numa manhã de sábado, com café da manhã pra quem vier.',
     'bolsa', 'bolsas.webp', 'Sede do colégio · Bairro Alto', false, date '2026-10-15', date '2026-11-28',
     'Para quem vai cursar o 1º, 2º ou 3º ano do Ensino Médio em 2027. Prova no sábado, 21/11, às 9h. Bolsa de 20% a 50% na mensalidade conforme a nota, válida para o ano letivo de 2027 (não vale para material e atividades extras). Inscrição gratuita até 19/11 pelo WhatsApp da escola.',
     'publicada'),
    ('Aula experimental de robótica',
     'Seu filho monta e programa um robô de verdade em 90 minutos, no laboratório maker, com os professores de robótica do contraturno. Não precisa saber programar.',
     'aula_experimental', 'robotica.webp', 'Laboratório maker', false, date '2026-10-20', date '2026-11-29',
     'Para estudantes do 6º ao 9º ano (de qualquer escola). Sábados de novembro, às 10h. Gratuita, 12 vagas por turma, com inscrição pelo WhatsApp.',
     'publicada'),
    ('Matrículas 2027 abertas',
     'Visite a escola, conheça os professores e saia com a proposta pronta. Fundamental II e Ensino Médio, de manhã, com contraturno opcional.',
     'matricula', 'matriculas.webp', 'Secretaria · seg. a sex., 8h às 18h', false, date '2026-10-01', date '2027-01-31',
     'Visitas com hora marcada pelo WhatsApp. Documentos e valores são apresentados na visita.',
     'publicada'),
    ('Intensivão ENEM: 4 aulões de véspera',
     'Revisão do que mais cai, com os professores do 3º ano: natureza, humanas, matemática e redação. Presencial no auditório ou ao vivo pelo link da turma.',
     'preparatorio', 'enem.webp', 'Auditório · e ao vivo online', true, date '2026-10-10', date '2026-11-07',
     'Aberto a estudantes do 3º ano e egressos. Gratuito para alunos do colégio; para quem é de fora, inscrição pelo WhatsApp.',
     'publicada'),
    ('Feira de profissões',
     'Uma tarde pra conversar com ex-alunos que hoje estudam engenharia, medicina, direito, design e cursos técnicos, e com equipes de universidades da região.',
     'evento', 'profissoes.webp', 'Quadra coberta', false, date '2026-10-25', date '2026-11-21',
     'Sábado, 21/11, das 14h às 18h. Entrada gratuita, aberta a estudantes e famílias.',
     'publicada'),
    ('Inglês nas férias: curso intensivo de janeiro',
     'Três semanas de inglês por nível, de manhã, com conversação, música e projeto final em grupo.',
     'curso_novo', 'ingles.webp', 'Sede do colégio', false, date '2026-11-01', date '2027-01-10',
     'De 11 a 17 anos, de qualquer escola. De 05/01 a 23/01, de segunda a sexta, 8h às 11h. Teste de nível na primeira aula.',
     'pendente'),
    ('Olimpíada interna de matemática',
     'Prova em duas fases pra todas as séries, com medalhas e menção honrosa.',
     'evento', 'bolsas.webp', 'Salas de aula', false, date '2026-09-01', date '2026-10-10',
     'Para alunos do colégio, do 6º ano ao 3º ano.',
     'publicada')
  ) x(titulo, descricao, categoria, img, local, online, inicio, fim, regras, status)
  where not exists (select 1 from be_oportunidades o where o.instituicao_id = v_inst and o.titulo = x.titulo);

  -- ---------- números da vitrine (visitas e cliques inventados dos últimos 30 dias) ----------
  if not exists (select 1 from be_vitrine_eventos where instituicao_id = v_inst) then
    insert into be_vitrine_eventos (tipo, instituicao_id, oportunidade_id, visitante, logado, dia)
    select 'ver_escola', v_inst, null, gen_random_uuid(), random() < 0.3, d
    from generate_series(be_hoje() - 29, be_hoje(), interval '1 day') d, lateral generate_series(1, 6 + (random() * 14)::int + (extract(dow from d) in (1, 2))::int * 6) n;
    insert into be_vitrine_eventos (tipo, instituicao_id, oportunidade_id, visitante, logado, dia)
    select 'ver_oportunidade', v_inst, o.id, gen_random_uuid(), random() < 0.3, d
    from be_oportunidades o, generate_series(greatest(o.inicio, be_hoje() - 29), least(o.fim, be_hoje()), interval '1 day') d,
         lateral generate_series(1, 2 + abs(hashtext(o.id::text || d::text || 'v')) % (case o.categoria when 'bolsa' then 15 when 'matricula' then 9 else 7 end)) n
    where o.instituicao_id = v_inst and o.status = 'publicada';
    insert into be_vitrine_eventos (tipo, instituicao_id, oportunidade_id, visitante, logado, dia)
    select 'clique_contato', v_inst, o.id, gen_random_uuid(), random() < 0.3, d
    from be_oportunidades o, generate_series(greatest(o.inicio, be_hoje() - 29), least(o.fim, be_hoje()), interval '1 day') d,
         lateral generate_series(1, abs(hashtext(o.id::text || d::text || 'c')) % (case o.categoria when 'bolsa' then 5 else 3 end)) n
    where o.instituicao_id = v_inst and o.status = 'publicada';
  end if;
end $$;
