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

await pool.end(); await poolAdmin.end();
process.exit(falhas ? 1 : 0);
