#!/bin/bash
# carrega a escola de demonstração (Colégio Monte Aurora, fictícia) no banco local de teste
# e uma conta de criador (criador@teste.com / senha-de-teste). Os tópicos das matérias são de mentira:
# em produção eles vêm da função que gera o conteúdo.
set -e
cd "$(dirname "$0")"
P="psql -h /tmp -p 54329 -U postgres -d estude -X -q -v ON_ERROR_STOP=1"
$P -c "insert into auth.users (id, email) select gen_random_uuid(), e from unnest(array['coordenacao','helena','ricardo','camila','laura']) n, lateral (select n || '.monteaurora@example.com' as e) x where not exists (select 1 from auth.users u where u.email = x.e)"
$P -f ../supabase/demo/monte_aurora_1_escola.sql
$P -c "insert into be_topicos (materia_id, nome, ordem) select m.id, t.nome, t.ordem from be_materias m join be_grupos g on g.id = m.grupo_id join be_instituicoes i on i.id = g.instituicao_id and i.demo, lateral (values ('Introdução', 0), ('Conceitos principais', 1), ('Exercícios', 2), ('Revisão', 3)) t(nome, ordem) where not exists (select 1 from be_topicos x where x.materia_id = m.id)"
$P -f ../supabase/demo/monte_aurora_2_progresso.sql
$P -c "insert into auth.users (id, email) select gen_random_uuid(), 'criador@teste.com' where not exists (select 1 from auth.users where email = 'criador@teste.com')" \
   -c "insert into be_usuarios (auth_user_id, nome, papel) select id, 'Criador Teste', 'aluno' from auth.users a where email = 'criador@teste.com' and not exists (select 1 from be_usuarios u where u.auth_user_id = a.id)" \
   -c "insert into be_criadores (usuario_id) select u.id from be_usuarios u join auth.users a on a.id = u.auth_user_id where a.email = 'criador@teste.com' on conflict do nothing"
echo "escola de demonstração carregada"
