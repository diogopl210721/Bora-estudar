-- Regras de acesso das escolas (rodar num banco recém-criado, depois do e2e): cada "ok ..." é uma checagem que passou; "FALHA" para o teste.
\set ON_ERROR_STOP 1
insert into auth.users (id, email) values
 ('11111111-1111-1111-1111-111111111111','ana@x.com'),('22222222-2222-2222-2222-222222222222','gil@escola.com'),
 ('33333333-3333-3333-3333-333333333333','pedro@escola.com'),('44444444-4444-4444-4444-444444444444','dono@x.com'),
 ('55555555-5555-5555-5555-555555555555','fora@x.com');
insert into be_usuarios (id, auth_user_id, nome, papel) values
 ('a1111111-1111-1111-1111-111111111111','11111111-1111-1111-1111-111111111111','Ana Souza','aluno'),
 ('b2222222-2222-2222-2222-222222222222','22222222-2222-2222-2222-222222222222','Gil Gestor','professor'),
 ('c3333333-3333-3333-3333-333333333333','33333333-3333-3333-3333-333333333333','Pedro Prof','professor'),
 ('d4444444-4444-4444-4444-444444444444','44444444-4444-4444-4444-444444444444','Diogo Soares','aluno'),
 ('e5555555-5555-5555-5555-555555555555','55555555-5555-5555-5555-555555555555','Fora Silva','professor');
insert into be_criadores values ('d4444444-4444-4444-4444-444444444444');

\echo '--- anônimo: formulário e vitrine'
set role anon;
select be_registrar_interesse('{"instituicao":"Colégio Teste","responsavel":"Gil","email":"gil@escola.com","telefone":"(41) 99999-0000","cidade":"Curitiba","tipo":"escola","consentimento":true}');
do $$ begin perform be_registrar_interesse('{"instituicao":"X","responsavel":"Gil","email":"gil@escola.com","telefone":"41999990000","cidade":"Curitiba","tipo":"escola","consentimento":true}'); raise exception 'FALHA'; exception when others then if sqlerrm like 'FALHA%' then raise; end if; raise notice 'ok recusou: %', sqlerrm; end $$;
do $$ begin perform be_registrar_interesse('{"instituicao":"Colégio","responsavel":"Gil","email":"gil@escola.com","telefone":"41999990000","cidade":"Curitiba","tipo":"escola","consentimento":false}'); raise exception 'FALHA'; exception when others then if sqlerrm like 'FALHA%' then raise; end if; raise notice 'ok recusou: %', sqlerrm; end $$;
select be_vitrine_escolas() as escolas_publicas;
select be_vitrine_config();
do $$ begin perform be_admin_leads(); raise exception 'FALHA'; exception when others then if sqlerrm like 'FALHA%' then raise; end if; raise notice 'ok anon nao le leads'; end $$;

set role authenticated;
\echo '--- gestor pede o cadastro'
select set_config('request.jwt.claim.sub', '22222222-2222-2222-2222-222222222222', false);
select (be_escola_solicitar('{"nome":"Colégio São João","tipo":"escola","cidade":"Curitiba","uf":"pr","whatsapp":"(41) 98888-7777"}')) ->> 'ok' as pedido;
select id as inst from be_instituicoes limit 0;
reset role; select id as inst, slug from be_instituicoes \gset
select set_config('t.inst', :'inst', false), set_config('t.slug', :'slug', false);
set role authenticated;
select be_minhas_escolas() -> 0 ->> 'status' as status_escola;
select (be_vitrine_escola(:'slug')) ->> 'previa' as previa_gestor;
select be_escola_salvar(:'inst', '{"descricao":"Escola de teste","cursos":[{"nome":"Ensino Médio","descricao":"1º ao 3º ano"},{"nome":"x"}],"modalidades":["presencial","voar"],"site":"https://colegio.com.br"}') ->> 'ok';
do $$ begin perform be_escola_salvar(current_setting('t.inst')::uuid, '{"site":"javascript:alert(1)"}'); raise exception 'FALHA'; exception when others then if sqlerrm like 'FALHA%' then raise; end if; raise notice 'ok link ruim: %', sqlerrm; end $$;
select be_oportunidade_salvar(null, :'inst', jsonb_build_object('titulo','Matrículas abertas 2027','descricao','Venha conhecer a escola','categoria','matricula','inicio',be_hoje(),'fim',be_hoje()+30), true) ->> 'status' as op1;
do $$ begin perform be_oportunidade_salvar(null, current_setting('t.inst')::uuid, jsonb_build_object('titulo','Bolsa 50%','descricao','Bolsa de estudo','categoria','bolsa','inicio',be_hoje(),'fim',be_hoje()+30,'regras','Prova de bolsas dia 10'), true); raise exception 'FALHA'; exception when others then if sqlerrm like 'FALHA%' then raise; end if; raise notice 'ok limite: %', sqlerrm; end $$;
do $$ begin perform be_oportunidade_salvar(null, current_setting('t.inst')::uuid, jsonb_build_object('titulo','Bolsa 50%','descricao','Bolsa de estudo','categoria','bolsa','inicio',be_hoje(),'fim',be_hoje()+30), false); raise exception 'FALHA'; exception when others then if sqlerrm like 'FALHA%' then raise; end if; raise notice 'ok bolsa sem regra: %', sqlerrm; end $$;

\echo '--- de fora não vê nem mexe'
select set_config('request.jwt.claim.sub', '55555555-5555-5555-5555-555555555555', false);
do $$ begin perform be_vitrine_escola(current_setting('t.slug')); raise exception 'FALHA'; exception when others then if sqlerrm like 'FALHA%' then raise; end if; raise notice 'ok pendente invisivel: %', sqlerrm; end $$;
do $$ begin perform be_escola_salvar(current_setting('t.inst')::uuid, '{"descricao":"hack"}'); raise exception 'FALHA'; exception when others then if sqlerrm like 'FALHA%' then raise; end if; raise notice 'ok nao edita: %', sqlerrm; end $$;
do $$ begin perform be_escola_painel(current_setting('t.inst')::uuid); raise exception 'FALHA'; exception when others then if sqlerrm like 'FALHA%' then raise; end if; raise notice 'ok sem painel: %', sqlerrm; end $$;
do $$ begin perform be_admin_escola_status(current_setting('t.inst')::uuid, 'aprovada'); raise exception 'FALHA'; exception when others then if sqlerrm like 'FALHA%' then raise; end if; raise notice 'ok nao aprova: %', sqlerrm; end $$;
do $$ begin insert into be_oportunidades (instituicao_id, titulo, descricao, categoria, inicio, fim, status) values (current_setting('t.inst')::uuid, 'Hack hack', 'direto na tabela', 'outro', current_date, current_date+1, 'publicada'); raise exception 'FALHA'; exception when others then if sqlerrm like 'FALHA%' then raise; end if; raise notice 'ok sem insert direto: %', sqlerrm; end $$;
select count(*) as le_tabela_direto from be_instituicoes;
do $$ begin insert into be_grupos (nome, tipo, dono_id, codigo, instituicao_id) values ('Turma pirata', 'turma_professor', 'e5555555-5555-5555-5555-555555555555', 'PIRATA', current_setting('t.inst')::uuid); raise exception 'FALHA'; exception when others then if sqlerrm like 'FALHA%' then raise; end if; raise notice 'ok turma pirata: %', sqlerrm; end $$;

\echo '--- criador aprova escola e oportunidade, dá plano'
select set_config('request.jwt.claim.sub', '44444444-4444-4444-4444-444444444444', false);
select be_admin_escola_status(:'inst', 'aprovada') ->> 'ok';
select jsonb_array_length(be_admin_oportunidades('pendente')) as pendentes;
reset role; select id as op1 from be_oportunidades limit 1 \gset
set role authenticated;
select be_admin_oportunidade_status(:'op1', 'publicada') ->> 'ok';
reset role; select id as plano_destaque from be_planos where codigo='destaque' \gset
set role authenticated;
select be_admin_contrato_salvar(:'inst', jsonb_build_object('plano_id', :'plano_destaque', 'status','ativo','pagamento','em_dia','valor_mensal','199','vigencia_inicio', be_hoje())) ->> 'ok';
select jsonb_array_length(be_admin_leads()) as leads, be_admin_comercial(7) -> 'escolas' as escolas;
select be_admin_nota(:'inst', 'Primeira reunião feita') ->> 'ok';

\echo '--- público'
set role anon;
select jsonb_array_length(be_vitrine_escolas()) as escolas, jsonb_array_length(be_vitrine_oportunidades()) as ops, be_vitrine_filtros();
select be_vitrine_escola(:'slug') -> 'cursos' as cursos, be_vitrine_escola(:'slug') -> 'modalidades' as modalidades;
select be_registrar_evento('ver_escola', :'inst', null, 'f0000000-0000-0000-0000-000000000001') as conta1, be_registrar_evento('ver_escola', :'inst', null, 'f0000000-0000-0000-0000-000000000001') as repete;
select be_registrar_evento('clique_contato', :'inst', :'op1', 'f0000000-0000-0000-0000-000000000001') as clique;
set role authenticated;
select set_config('request.jwt.claim.sub', '22222222-2222-2222-2222-222222222222', false);
select be_registrar_evento('ver_escola', :'inst', null, null) as gestor_nao_conta;
\echo '--- gestor: segunda oportunidade agora cabe (plano Destaque), painel e números'
select be_oportunidade_salvar(null, :'inst', jsonb_build_object('titulo','Bolsa de até 50%','descricao','Bolsa de estudo','categoria','bolsa','inicio',be_hoje(),'fim',be_hoje()+30,'regras','Prova de bolsas dia 10'), true) ->> 'status' as op2;
select be_oportunidade_acao(:'op1', 'pausar') ->> 'status' as pausa;
select be_oportunidade_acao(:'op1', 'retomar') ->> 'status' as retoma;
select p -> 'metricas' -> 'ver_escola' as ver, p -> 'metricas' -> 'cliques' as cliques, p ->> 'limite_oportunidades' as limite, p -> 'plano' ->> 'nome' as plano, p ->> 'codigo_professor' is not null as tem_codigo
from (select be_escola_painel(:'inst') p) x;
\echo '--- professor entra pelo código e cria turma da escola'
select set_config('request.jwt.claim.sub', '33333333-3333-3333-3333-333333333333', false);
reset role; select codigo_professor as cod from be_instituicoes \gset
set role authenticated;
select be_escola_entrar_professor(:'cod') ->> 'nome';
insert into be_grupos (nome, tipo, dono_id, codigo, instituicao_id) values ('Física 2º A', 'turma_professor', 'c3333333-3333-3333-3333-333333333333', 'FIS2AA', :'inst');
select jsonb_array_length(be_escola_painel(:'inst') -> 'turmas') as turmas_do_prof, be_escola_painel(:'inst') -> 'metricas' as prof_sem_metricas;
do $$ begin perform be_oportunidade_salvar(null, current_setting('t.inst')::uuid, jsonb_build_object('titulo','Do professor','descricao','não pode','categoria','evento','inicio',be_hoje(),'fim',be_hoje()+3), false); raise exception 'FALHA'; exception when others then if sqlerrm like 'FALHA%' then raise; end if; raise notice 'ok professor nao publica: %', sqlerrm; end $$;
\echo '--- vencida some'
reset role;
update be_oportunidades set inicio = be_hoje() - 10, fim = be_hoje() - 1 where categoria = 'matricula';
set role anon;
select jsonb_array_length(be_vitrine_oportunidades()) as ativas_depois;
reset role;
select acao, papel from be_registro_acoes order by id;
select be_pode_enviar_imagem_escola(id::text || '/logo-1.jpg') as anon_pode from be_instituicoes;

\echo '--- ajudantes internos fechados pro app'
set role anon;
do $$ begin perform be_escola_metricas_json(current_setting('t.inst')::uuid, 30); raise exception 'FALHA'; exception when others then if sqlerrm like 'FALHA%' then raise; end if; raise notice 'ok anon nao chama metricas direto: %', sqlerrm; end $$;
set role authenticated;
select set_config('request.jwt.claim.sub', '55555555-5555-5555-5555-555555555555', false);
do $$ begin perform be_plano_da_escola(current_setting('t.inst')::uuid); raise exception 'FALHA'; exception when others then if sqlerrm like 'FALHA%' then raise; end if; raise notice 'ok logado nao chama plano direto: %', sqlerrm; end $$;
reset role;
