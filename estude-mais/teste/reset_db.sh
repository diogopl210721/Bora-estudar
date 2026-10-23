#!/bin/bash
# recria o banco local de teste: espelho do que existe + migrações do Estude+ + questões do ENEM
set -e
P="psql -h /tmp -p 54329 -U postgres -v ON_ERROR_STOP=1 -q -X"
$P -c "drop database if exists estude" -c "create database estude" >/dev/null
$P -d estude -f 00_espelho_bora_estudar.sql >/dev/null
$P -d estude -f ../supabase/01_estude_schema.sql 2>&1 | grep -v NOTICE || true
$P -d estude -f ../supabase/02_estude_funcoes.sql 2>&1 | grep -v NOTICE || true
$P -d estude -f ../supabase/03_enem_importacao.sql 2>&1 | grep -v NOTICE || true
$P -d estude -f ../supabase/04_estude_social.sql 2>&1 | grep -v NOTICE || true
$P -d estude -f ../supabase/05_estude_social_funcoes.sql 2>&1 | grep -v NOTICE || true
$P -d estude -f ../supabase/06_estude_cadastro.sql 2>&1 | grep -v NOTICE || true
$P -d estude -f ../supabase/07_estude_plano_substituidas.sql 2>&1 | grep -v NOTICE || true
$P -d estude -f ../supabase/08_estude_grupos_permissoes.sql 2>&1 | grep -v NOTICE || true
for f in ../supabase/enem/enem_*.sql; do $P -d estude -f $f >/dev/null; done
$P -d estude -c "select count(*) as questoes_enem from be_enem_questoes"
