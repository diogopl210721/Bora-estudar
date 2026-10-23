// Confere que o app (papel authenticated) não consegue chamar as funções internas, e que a service role consegue.
import { chamarRpc, pool, poolAdmin } from './executor.mjs';
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
await pool.end(); await poolAdmin.end();
process.exit(falhas ? 1 : 0);
