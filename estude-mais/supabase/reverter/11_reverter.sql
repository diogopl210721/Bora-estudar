-- ============================================================================
-- Estude+ · REVERSÃO da migração 11 (escolas, vitrine e área comercial)
-- NÃO roda sozinho. Só use com aprovação, depois de exportar os dados das tabelas novas
-- (be_oportunidades, be_leads, be_assinaturas, be_vitrine_eventos, be_registro_acoes...).
-- A migração 11 só ACRESCENTA coisas; as únicas funções que ela substitui são
-- be_usuarios_protege e be_painel_criador. As versões anteriores estão no fim deste arquivo
-- (conferidas por md5 com a produção antes de aplicar: ce184a03... e 80cd9f97...).
-- ============================================================================
begin;

-- 1) políticas novas
drop policy if exists "escolas: so pelas funcoes" on public.be_instituicoes;
drop policy if exists "escola: turma so de quem e da escola" on public.be_grupos;
drop policy if exists "escola: mudar turma so quem e da escola" on public.be_grupos;

-- 2) funções novas
drop function if exists public.be_admin_comercial(p_dias integer) cascade;
drop function if exists public.be_admin_config_salvar(p_dados jsonb) cascade;
drop function if exists public.be_admin_contrato_salvar(p_inst uuid, p_dados jsonb) cascade;
drop function if exists public.be_admin_escola_criar(p_dados jsonb, p_email_gestor text) cascade;
drop function if exists public.be_admin_escola_editar(p_inst uuid, p_dados jsonb) cascade;
drop function if exists public.be_admin_escola_gestor(p_inst uuid, p_email text) cascade;
drop function if exists public.be_admin_escola_status(p_inst uuid, p_status text, p_motivo text) cascade;
drop function if exists public.be_admin_escolas(p_status text) cascade;
drop function if exists public.be_admin_lead_status(p_id uuid, p_status text, p_nota text) cascade;
drop function if exists public.be_admin_leads(p_status text) cascade;
drop function if exists public.be_admin_nota(p_inst uuid, p_texto text) cascade;
drop function if exists public.be_admin_oportunidade_status(p_id uuid, p_status text, p_motivo text) cascade;
drop function if exists public.be_admin_oportunidades(p_status text) cascade;
drop function if exists public.be_admin_plano_salvar(p_id uuid, p_dados jsonb) cascade;
drop function if exists public.be_admin_planos() cascade;
drop function if exists public.be_admin_registro(p_inst uuid, p_limite integer) cascade;
drop function if exists public.be_codigo_aleatorio(p_tam integer) cascade;
drop function if exists public.be_eh_demo(p_usuario uuid) cascade;
drop function if exists public.be_escola_codigo_novo(p_inst uuid) cascade;
drop function if exists public.be_escola_entrar_professor(p_codigo text) cascade;
drop function if exists public.be_escola_json(i be_instituicoes) cascade;
drop function if exists public.be_escola_metricas_json(p_inst uuid, p_dias integer) cascade;
drop function if exists public.be_escola_painel(p_inst uuid, p_dias integer) cascade;
drop function if exists public.be_escola_salvar(p_inst uuid, p_dados jsonb) cascade;
drop function if exists public.be_escola_solicitar(p_dados jsonb) cascade;
drop function if exists public.be_escola_tirar_professor(p_inst uuid, p_usuario uuid) cascade;
drop function if exists public.be_limite_oportunidades(p_inst uuid) cascade;
drop function if exists public.be_minhas_escolas() cascade;
drop function if exists public.be_oportunidade_acao(p_id uuid, p_acao text) cascade;
drop function if exists public.be_oportunidade_json(o be_oportunidades, i be_instituicoes) cascade;
drop function if exists public.be_oportunidade_salvar(p_id uuid, p_inst uuid, p_dados jsonb, p_enviar boolean) cascade;
drop function if exists public.be_oportunidades_em_uso(p_inst uuid, p_menos uuid) cascade;
drop function if exists public.be_plano_da_escola(p_inst uuid) cascade;
drop function if exists public.be_pode_enviar_imagem_escola(p_caminho text) cascade;
drop function if exists public.be_registrar_acao(p_papel text, p_acao text, p_alvo_tipo text, p_alvo_id uuid, p_inst uuid, p_detalhe jsonb) cascade;
drop function if exists public.be_registrar_evento(p_tipo text, p_instituicao uuid, p_oportunidade uuid, p_visitante uuid) cascade;
drop function if exists public.be_registrar_interesse(p_dados jsonb) cascade;
drop function if exists public.be_slug(p_texto text) cascade;
drop function if exists public.be_slug_livre(p_base text, p_inst uuid) cascade;
drop function if exists public.be_slug_livre_plano(p_nome text) cascade;
drop function if exists public.be_so_digitos(p text) cascade;
drop function if exists public.be_sou_da_escola(p_inst uuid, p_papel text) cascade;
drop function if exists public.be_txt(p jsonb, p_chave text, p_max integer) cascade;
drop function if exists public.be_url_ok(p text) cascade;
drop function if exists public.be_vitrine_config() cascade;
drop function if exists public.be_vitrine_escola(p_slug text) cascade;
drop function if exists public.be_vitrine_escolas(p_busca text, p_cidade text, p_tipo text) cascade;
drop function if exists public.be_vitrine_filtros() cascade;
drop function if exists public.be_vitrine_oportunidades(p_categoria text, p_cidade text, p_busca text, p_limite integer, p_offset integer) cascade;
drop function if exists public.be_vitrine_planos() cascade;

-- 3) tabelas novas
drop table if exists public.be_vitrine_eventos, public.be_leads, public.be_registro_acoes, public.be_assinaturas,
  public.be_oportunidades, public.be_instituicao_membros, public.be_planos, public.be_config_comercial cascade;

-- 4) colunas novas em be_instituicoes (as originais id, nome, logo_url, cores, plano, limite_ia_diario, dono_id e created_at ficam)
alter table public.be_instituicoes
  drop column if exists slug, drop column if exists tipo, drop column if exists status, drop column if exists demo,
  drop column if exists descricao, drop column if exists cidade, drop column if exists uf, drop column if exists regiao,
  drop column if exists endereco, drop column if exists modalidades, drop column if exists publico, drop column if exists cursos,
  drop column if exists site, drop column if exists instagram, drop column if exists facebook, drop column if exists whatsapp,
  drop column if exists telefone, drop column if exists email_contato, drop column if exists capa_url,
  drop column if exists codigo_professor, drop column if exists aprovada_em, drop column if exists updated_at;

-- 5) versões anteriores das duas funções substituídas
CREATE OR REPLACE FUNCTION public.be_painel_criador()
 RETURNS json
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare v_hoje date := be_hoje(); v_ini timestamptz := (be_hoje()::timestamp at time zone 'America/Sao_Paulo');
begin
  perform be_exigir_criador();
  return json_build_object(
    'numeros', json_build_object(
      'contas', (select count(*) from be_usuarios),
      'professores', (select count(*) from be_usuarios where papel = 'professor'),
      'novos_7d', (select count(*) from be_usuarios where created_at > now() - interval '7 days'),
      'ativos_hoje', (select count(*) from be_usuarios where ultima_atividade = v_hoje),
      'ativos_7d', (select count(*) from be_usuarios where ultima_atividade >= v_hoje - 6),
      'materias', (select count(*) from be_materias),
      'materias_7d', (select count(*) from be_materias where created_at > now() - interval '7 days'),
      'turmas', (select count(*) from be_grupos where tipo = 'turma_professor'),
      'grupos_amigos', (select count(*) from be_grupos where tipo = 'grupo_amigos'),
      'ia_hoje', (select coalesce(sum(quantidade), 0) from be_uso_ia where data = current_date),
      'tutor_hoje', (select coalesce(sum(quantidade), 0) from be_uso_tutor where data = current_date),
      'resumos', (select count(*) from be_resumos where status = 'publicado'),
      'mensagens_hoje', (select count(*) from be_sala_mensagens where created_at >= v_ini),
      'simulados_7d', (select count(*) from be_simulados where iniciado_em > now() - interval '7 days'),
      'redacoes_7d', (select count(*) from be_redacoes where created_at > now() - interval '7 days')),
    'fila_resumos', coalesce((
      select json_agg(x.j order by x.n desc, x.ultima desc) from (
        select count(*) n, max(d.created_at) ultima,
               json_build_object('id', r.id, 'titulo', r.titulo, 'materia', r.materia, 'status', r.status,
                                 'trecho', left(regexp_replace(r.conteudo, '\s+', ' ', 'g'), 160),
                                 'denuncias', count(*), 'motivos', coalesce(json_agg(d.motivo) filter (where d.motivo is not null and d.motivo <> ''), '[]'::json),
                                 'ultima', max(d.created_at), 'autor', be_autor_json(r.autor_id),
                                 'silenciado_ate', be_silenciado_ate(r.autor_id)) j
        from be_denuncias d join be_resumos r on r.id = d.alvo_id
        where d.alvo_tipo = 'resumo' and d.resolvida_em is null
        group by r.id limit 40) x), '[]'::json),
    'fila_mensagens', coalesce((
      select json_agg(x.j order by x.n desc, x.ultima desc) from (
        select count(*) n, max(d.created_at) ultima,
               json_build_object('id', m.id, 'texto', m.texto, 'oculta', m.oculta, 'sala', s.nome, 'created_at', m.created_at,
                                 'denuncias', count(*), 'ultima', max(d.created_at), 'autor', be_autor_json(m.usuario_id),
                                 'silenciado_ate', be_silenciado_ate(m.usuario_id)) j
        from be_denuncias d join be_sala_mensagens m on m.id = d.alvo_id join be_salas s on s.id = m.sala_id
        where d.alvo_tipo = 'mensagem' and d.resolvida_em is null
        group by m.id, s.nome limit 40) x), '[]'::json),
    'silenciados', coalesce((
      select json_agg(json_build_object('autor', be_autor_json(z.usuario_id), 'ate', z.ate, 'motivo', z.motivo) order by z.ate)
      from be_silenciados z where z.ate > now()), '[]'::json));
end $function$
;

CREATE OR REPLACE FUNCTION public.be_usuarios_protege()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO 'public'
AS $function$
begin
  if current_user not in ('authenticated', 'anon') then return new; end if;
  if tg_op = 'INSERT' then
    new.xp := 0; new.nivel := 1; new.streak_atual := 0; new.streak_maior := 0; new.ultima_atividade := null; new.divisao := 'bronze';
    if new.papel not in ('aluno', 'professor') then new.papel := 'aluno'; end if;
  else
    new.id := old.id; new.auth_user_id := old.auth_user_id; new.papel := old.papel;
    new.xp := old.xp; new.nivel := old.nivel; new.streak_atual := old.streak_atual; new.streak_maior := old.streak_maior;
    new.ultima_atividade := old.ultima_atividade; new.divisao := old.divisao; new.energia := old.energia;
    new.instituicao_id := old.instituicao_id;
  end if;
  return new;
end $function$
;

commit;
