// Confere que o app (papel authenticated) não consegue chamar as funções internas, e que a service role consegue.
import { chamarRpc, executar, pool, poolAdmin } from './executor.mjs';
const { rows } = await poolAdmin.query("select u.id, u.auth_user_id from be_usuarios u order by created_at limit 1");
if (!rows.length) { console.log('sem usuário de teste'); process.exit(1); }
const { id, auth_user_id: sub } = rows[0];
const internas = [
  ['be_ganhar_xp', { p_usuario: id, p_tipo: 'hack', p_pontos: 99999 }],
  ['be_conceder_conquista', { p_usuario: id, p_codigo: 'streak_30_dias' }],
  ['be_incrementar_uso_ia', { p_usuario_id: id }],
  ['be_materia_acessivel_para', { p_usuario: id, p_materia: id }],
  ['be_entrar_liga_atual', { p_usuario: id }],
  ['be_atualizar_dominio', { p_usuario: id, p_topico: id, p_acertou: true }],
  ['be_fechar_ligas', {}],
  ['be_enem_upsert', { p_chave: 'x', p_linhas: [] }],
];
let falhas = 0;
for (const [nome, args] of internas) {
  const r = await chamarRpc(sub, nome, args);
  const bloqueou = r.error && /interna/.test(r.error.message);
  if (!bloqueou) falhas++;
  console.log((bloqueou ? 'ok  bloqueado ' : 'FALHA liberado ') + nome, r.error ? '' : JSON.stringify(r.data));
}
const ruim = await chamarRpc(sub, 'be_modo_interno', {});
const depois = await chamarRpc(sub, 'be_ganhar_xp', { p_usuario: id, p_tipo: 'hack', p_pontos: 5 });
console.log(depois.error ? 'ok  modo interno não vaza entre chamadas' : 'FALHA modo interno vazou');
if (!depois.error) falhas++;
const svc = await chamarRpc(null, 'be_ganhar_xp', { p_usuario: id, p_tipo: 'teste', p_pontos: 1 });
console.log(svc.error ? 'FALHA service role bloqueada: ' + svc.error.message : 'ok  service role liberada');
if (svc.error) falhas++;
const app = await chamarRpc(sub, 'be_resumo_hoje', {});
console.log(app.error ? 'FALHA rpc do app: ' + app.error.message : 'ok  rpc do app funciona');
if (app.error) falhas++;
// ---------- biblioteca, tutor e comunidade: o app não fura as regras escrevendo direto nas tabelas ----------
const pessoas = (await poolAdmin.query("select id, auth_user_id, nome from be_usuarios order by created_at")).rows;
const ana = pessoas.find((u) => u.nome.startsWith('Ana'));
const prof = pessoas.find((u) => u.nome.startsWith('Carlos'));
const confere = (ok, txt) => { console.log((ok ? 'ok  ' : 'FALHA ') + txt); if (!ok) falhas++; };
if (ana && prof) {
  const r1 = await executar(ana.auth_user_id, { table: 'be_resumos', op: 'insert', values: { autor_id: ana.id, titulo: 'sem moderação', materia: 'x', conteudo: 'x'.repeat(100), status: 'publicado' }, filters: [], order: [] });
  confere(!!r1.error, 'aluno não publica resumo sem passar pela moderação');
  const doProf = (await poolAdmin.query('select id, status from be_resumos where autor_id = $1 limit 1', [prof.id])).rows[0];
  if (doProf) {
    await executar(ana.auth_user_id, { table: 'be_resumos', op: 'update', values: { status: 'oculto', titulo: 'hackeado' }, filters: [{ op: 'eq', col: 'id', val: doProf.id }], order: [] });
    const depois = (await poolAdmin.query('select status, titulo from be_resumos where id = $1', [doProf.id])).rows[0];
    confere(depois.titulo !== 'hackeado', 'aluno não edita resumo de outra pessoa');
    await executar(ana.auth_user_id, { table: 'be_resumos', op: 'delete', filters: [{ op: 'eq', col: 'id', val: doProf.id }], order: [] });
    confere((await poolAdmin.query('select 1 from be_resumos where id = $1', [doProf.id])).rowCount === 1, 'aluno não apaga resumo de outra pessoa');
    const r2 = await executar(ana.auth_user_id, { table: 'be_resumo_curtidas', op: 'insert', values: { resumo_id: doProf.id, usuario_id: prof.id }, filters: [], order: [] });
    confere(!!r2.error, 'não dá pra curtir em nome de outra pessoa');
  }
  const sala = (await poolAdmin.query('select id from be_salas where grupo_id is not null limit 1')).rows[0];
  const r3 = await executar(ana.auth_user_id, { table: 'be_sala_mensagens', op: 'insert', values: { sala_id: sala.id, usuario_id: ana.id, texto: 'www.golpe.com' }, filters: [], order: [] });
  confere(!!r3.error, 'mensagem só entra pela função com filtro (não direto na tabela)');
  const r4 = await executar(ana.auth_user_id, { table: 'be_tutor_mensagens', op: 'select', columns: '*', filters: [], order: [] });
  const minhas = (await poolAdmin.query('select count(*)::int n from be_tutor_mensagens m join be_tutor_conversas c on c.id = m.conversa_id where c.usuario_id = $1', [ana.id])).rows[0].n;
  confere(!r4.error && r4.data.length === minhas, 'cada um só lê as próprias conversas com o tutor');
  const r5 = await executar(ana.auth_user_id, { table: 'be_uso_tutor', op: 'update', values: { quantidade: 0 }, filters: [], order: [] });
  const uso = (await poolAdmin.query('select coalesce(sum(quantidade), 0)::int n from be_uso_tutor where usuario_id = $1', [ana.id])).rows[0].n;
  confere(uso > 0, 'aluno não zera o próprio limite do tutor' + (r5.error ? '' : ''));
  // remontar o plano: as tarefas antigas somem do app sem ser apagadas, e nada fica duplicado
  const bio = (await poolAdmin.query("select id from be_materias where usuario_id = $1 and nome = 'Biologia'", [ana.id])).rows[0];
  if (bio) {
    const g = await chamarRpc(ana.auth_user_id, 'be_gerar_plano', { p_materia: bio.id });
    const vis = await executar(ana.auth_user_id, { table: 'be_plano_tarefas', op: 'select', columns: 'id, manual, feita_em, dia', filters: [{ op: 'eq', col: 'materia_id', val: bio.id }], order: [] });
    const hoje = new Date().toLocaleDateString('en-CA', { timeZone: 'America/Sao_Paulo' });
    const futurasAuto = (vis.data || []).filter((t) => !t.manual && !t.feita_em && String(t.dia instanceof Date ? t.dia.toISOString() : t.dia).slice(0, 10) >= hoje).length;
    const subst = (await poolAdmin.query('select count(*)::int n from be_plano_tarefas where usuario_id = $1 and materia_id = $2 and substituida', [ana.id, bio.id])).rows[0].n;
    confere(!g.error && futurasAuto === g.data, `remontar o plano não duplica tarefas (${futurasAuto} visíveis, ${g.data} novas)`);
    confere(subst > 0 && !(vis.data || []).some((t) => t.substituida), `tarefas antigas ficam guardadas como substituídas (${subst}) e não aparecem no app`);
    const hojeRpc = await chamarRpc(ana.auth_user_id, 'be_resumo_hoje', {});
    const ids = new Set((hojeRpc.data.tarefas || []).map((t) => t.id));
    const vazou = (await poolAdmin.query('select id from be_plano_tarefas where usuario_id = $1 and substituida', [ana.id])).rows.some((r) => ids.has(r.id));
    confere(!vazou, 'o Hoje não mostra tarefa substituída');
  }
  // grupos: na turma do professor só ele põe material; no grupo de amigos, qualquer membro
  const turma = (await poolAdmin.query("select g.id, (select id from be_materias where grupo_id = g.id limit 1) as materia from be_grupos g where g.tipo = 'turma_professor' limit 1")).rows[0];
  if (turma && turma.materia) {
    const m1 = await executar(ana.auth_user_id, { table: 'be_materias', op: 'insert', values: { grupo_id: turma.id, nome: 'matéria pirata' }, filters: [], order: [] });
    confere(!!m1.error, 'aluna não cria matéria na turma do professor');
    const m2 = await executar(ana.auth_user_id, { table: 'be_materiais', op: 'insert', values: { materia_id: turma.materia, tipo: 'link', importado_por: ana.id, texto_extraido: 'x' }, filters: [], order: [] });
    confere(!!m2.error, 'aluna não põe material na matéria da turma');
    const m3 = await executar(ana.auth_user_id, { table: 'be_cards', op: 'insert', values: { materia_id: turma.materia, frente: 'pirata?', verso: 'sim', origem: 'manual', criado_por: ana.id }, filters: [], order: [] });
    confere(!!m3.error, 'aluna não cria flashcard na matéria da turma');
    const antes = (await poolAdmin.query('select data_prova from be_materias where id = $1', [turma.materia])).rows[0].data_prova;
    await executar(ana.auth_user_id, { table: 'be_materias', op: 'update', values: { data_prova: '2099-01-01' }, filters: [{ op: 'eq', col: 'id', val: turma.materia }], order: [] });
    const depois = (await poolAdmin.query('select data_prova from be_materias where id = $1', [turma.materia])).rows[0].data_prova;
    confere(String(antes) === String(depois), 'aluna não muda a data da prova da turma');
    await executar(ana.auth_user_id, { table: 'be_materias', op: 'delete', filters: [{ op: 'eq', col: 'id', val: turma.materia }], order: [] });
    confere((await poolAdmin.query('select 1 from be_materias where id = $1', [turma.materia])).rowCount === 1, 'aluna não tira matéria da turma');
    const fn1 = await chamarRpc(null, 'be_pode_editar_materia_para', { p_usuario: ana.id, p_materia: turma.materia });
    const fn2 = await chamarRpc(null, 'be_pode_editar_materia_para', { p_usuario: prof.id, p_materia: turma.materia });
    confere(fn1.data === false && fn2.data === true, 'gerar conteúdo com IA na turma: aluna não, professor sim');
  } else { console.log('FALHA sem turma do e2e'); falhas++; }
  const amigos = (await poolAdmin.query("select id from be_grupos where tipo = 'grupo_amigos' limit 1")).rows[0];
  const bia = (await poolAdmin.query("select id, auth_user_id from be_usuarios where nome like 'Bia%'")).rows[0];
  if (amigos && bia) {
    const gen = (await poolAdmin.query("select count(*)::int n from be_materias where grupo_id = $1 and nome = 'Genética'", [amigos.id])).rows[0].n;
    confere(gen === 1, 'no grupo de amigos, quem não criou o grupo também coloca matéria');
    const anaVe = await executar(ana.auth_user_id, { table: 'be_materias', op: 'select', columns: 'id', filters: [{ op: 'eq', col: 'grupo_id', val: amigos.id }], order: [] });
    confere(!anaVe.error && anaVe.data.length === 1, 'a matéria do grupo de amigos aparece pra quem criou o grupo');
  } else { console.log('FALHA sem grupo de amigos do e2e'); falhas++; }
  // terceira pessoa, fora da turma: não vê a sala nem as mensagens da turma
  const fora = (await poolAdmin.query("insert into auth.users (id, email) values (gen_random_uuid(), 'fora@teste.com') returning id")).rows[0].id;
  await poolAdmin.query("insert into be_usuarios (auth_user_id, nome, papel) values ($1, 'Pessoa de Fora', 'aluno')", [fora]);
  const r6 = await chamarRpc(fora, 'be_mensagens_sala', { p_sala: sala.id });
  confere(!!r6.error, 'quem não é da turma não abre a sala da turma');
  const r7 = await executar(fora, { table: 'be_sala_mensagens', op: 'select', columns: 'texto', filters: [{ op: 'eq', col: 'sala_id', val: sala.id }], order: [] });
  confere(!r7.error && r7.data.length === 0, 'quem não é da turma não lê as mensagens da turma direto na tabela');
  const r8 = await chamarRpc(fora, 'be_enviar_mensagem', { p_sala: sala.id, p_texto: 'oi' });
  confere(!!r8.error, 'quem não é da turma não escreve na sala da turma');
  const lista = await chamarRpc(fora, 'be_salas_lista', {});
  confere(!lista.error && !lista.data.some((x) => x.turma), 'a lista de salas de quem é de fora não mostra a turma');
  // bloqueio: quem bloqueou não vê mais as mensagens da pessoa
  await chamarRpc(ana.auth_user_id, 'be_bloquear', { p_usuario: prof.id });
  const r9 = await chamarRpc(ana.auth_user_id, 'be_mensagens_sala', { p_sala: sala.id });
  confere(!r9.error && !r9.data.mensagens.some((m) => !m.eu), 'mensagens de quem foi bloqueado somem pra quem bloqueou');
  const r10 = await chamarRpc(ana.auth_user_id, 'be_feed_resumos', { p_ordem: 'recentes' });
  confere(!r10.error && !r10.data.some((x) => x.autor.id === prof.id), 'resumos de quem foi bloqueado somem da biblioteca');
} else {
  console.log('FALHA sem os usuários do e2e para os testes sociais'); falhas++;
}

// ---------- conta do criador: ninguém vira criador sozinho; XP, papel e liga não mudam direto pela tabela ----------
{
  const porEmail = async (e) => (await poolAdmin.query('select u.id, u.auth_user_id, u.xp, u.papel, u.divisao from be_usuarios u join auth.users a on a.id = u.auth_user_id where a.email = $1', [e])).rows[0];
  const ana2 = await porEmail('ana@teste.com');
  const dono = await porEmail('dono@teste.com');
  const carlos = await porEmail('prof@teste.com');
  if (ana2 && dono && carlos) {
    const c1 = await executar(ana2.auth_user_id, { table: 'be_criadores', op: 'insert', values: { usuario_id: ana2.id }, filters: [], order: [] });
    confere(!!c1.error, 'aluna não se coloca como criadora');
    const c2 = await executar(ana2.auth_user_id, { table: 'be_criadores', op: 'select', columns: '*', filters: [], order: [] });
    confere(!c2.error && c2.data.length === 0, 'ninguém lê a lista de criadores pela tabela');
    const c3 = await chamarRpc(ana2.auth_user_id, 'be_painel_criador', {});
    confere(!!c3.error, 'aluna não abre o painel do criador');
    const c4 = await chamarRpc(ana2.auth_user_id, 'be_moderar', { p_tipo: 'resumo', p_alvo: dono.id, p_acao: 'ocultar' });
    confere(!!c4.error && /criador/.test(c4.error.message), 'aluna não modera resumo nem mensagem');
    const c5 = await chamarRpc(ana2.auth_user_id, 'be_silenciar', { p_usuario: dono.id, p_dias: 30 });
    confere(!!c5.error, 'aluna não silencia ninguém');
    const c6 = await executar(ana2.auth_user_id, { table: 'be_silenciados', op: 'insert', values: { usuario_id: carlos.id, ate: '2099-01-01' }, filters: [], order: [] });
    confere(!!c6.error, 'aluna não silencia ninguém direto na tabela');
    await executar(ana2.auth_user_id, { table: 'be_usuarios', op: 'update', values: { xp: 999999, papel: 'professor', divisao: 'diamante', nivel: 99 }, filters: [{ op: 'eq', col: 'id', val: ana2.id }], order: [] });
    const depois = await porEmail('ana@teste.com');
    confere(depois.xp === ana2.xp && depois.papel === ana2.papel && depois.divisao === ana2.divisao, 'XP, papel e liga não mudam direto pela tabela');
    const c7 = await chamarRpc(ana2.auth_user_id, 'be_silenciado_ate', { p_usuario: carlos.id });
    const c8 = await chamarRpc(carlos.auth_user_id, 'be_silenciado_ate', { p_usuario: carlos.id });
    confere(!c7.error && c7.data === null && !c8.error && c8.data !== null, 'só a própria pessoa e o criador sabem de um silêncio');
    const c9 = await chamarRpc(dono.auth_user_id, 'be_painel_criador', {});
    confere(!c9.error && c9.data.numeros.contas >= 4 && c9.data.silenciados.length === 1, 'o criador abre o painel');
    const c10 = await chamarRpc(carlos.auth_user_id, 'be_enviar_mensagem', { p_sala: (await poolAdmin.query('select id from be_salas where oficial limit 1')).rows[0].id, p_texto: 'oi' });
    confere(!!c10.error && /sem mandar/.test(c10.error.message), 'quem está silenciado não manda mensagem');
  } else { console.log('FALHA sem a conta do criador do e2e'); falhas++; }
}

await pool.end(); await poolAdmin.end();
process.exit(falhas ? 1 : 0);
