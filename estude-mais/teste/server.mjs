// Servidor de teste do Estude+: site estático + supabase de mentira + Edge Functions com IA simulada.
import http from 'node:http';
import fs from 'node:fs';
import path from 'node:path';
import { randomUUID } from 'node:crypto';
import { pool, executar, chamarRpc, clienteAdmin } from './executor.mjs';
import { extrairJson, normalizarGerado, persistirConteudo } from '../supabase/functions/estude-gerar-conteudo/nucleo.ts';
import { normalizarCorrecao } from '../supabase/functions/estude-corrigir-redacao/nucleo.ts';

const SITE = path.resolve(import.meta.dirname, '../site');
const TIPOS = { '.html': 'text/html; charset=utf-8', '.js': 'text/javascript', '.css': 'text/css', '.svg': 'image/svg+xml', '.png': 'image/png', '.webmanifest': 'application/manifest+json' };
const senhas = new Map();

const IA_CONTEUDO = '```json\n' + JSON.stringify({
  titulo: 'Divisão celular',
  texto_bruto: 'Anotações sobre células, mitose e meiose.',
  topicos: ['Células', 'Mitose', 'Meiose'],
  resumo: 'A célula é a unidade básica da vida.\n\nNa mitose uma célula gera duas células-filhas idênticas.\n\nNa meiose surgem quatro células com metade dos cromossomos, base da reprodução sexuada.',
  mapa_mental: { tema_central: 'Divisão celular', ramos: [
    { titulo: 'Células', pontos: ['membrana', 'citoplasma', 'núcleo'] },
    { titulo: 'Mitose', pontos: ['prófase', 'metáfase', 'anáfase', 'telófase'] },
    { titulo: 'Meiose', pontos: ['crossing-over', 'redução cromossômica'] } ] },
  curiosidades: ['Uma célula da pele se divide a cada poucas semanas.', 'Os neurônios quase não se dividem.'],
  flashcards: [
    { frente: 'O que é a célula?', verso: 'A unidade básica estrutural e funcional dos seres vivos.', topico: 'Células' },
    { frente: 'Quantas células-filhas a mitose produz?', verso: 'Duas, geneticamente idênticas à mãe.', topico: 'Mitose' },
    { frente: 'Ordem das fases da mitose', verso: 'Prófase, metáfase, anáfase e telófase (PMAT).', topico: 'Mitose' },
    { frente: 'Para que serve a meiose?', verso: 'Formar gametas com metade dos cromossomos.', topico: 'Meiose' },
    { frente: 'O que é crossing-over?', verso: 'Troca de pedaços entre cromossomos homólogos na prófase I.', topico: 'Meiose' },
  ],
  quiz: [
    { pergunta: 'Qual é a unidade básica da vida?', opcoes: { A: 'Átomo', B: 'Célula', C: 'Tecido', D: 'Órgão' }, resposta_correta: 'B', explicacao: 'Todo ser vivo é formado por células.', topico: 'Células' },
    { pergunta: 'Onde fica o material genético nos eucariontes?', opcoes: { A: 'Núcleo', B: 'Ribossomo', C: 'Membrana', D: 'Vacúolo' }, resposta_correta: 'A', explicacao: 'O DNA fica protegido no núcleo.', topico: 'Células' },
    { pergunta: 'Quantas células a mitose produz?', opcoes: { A: '1', B: '4', C: '2', D: '8' }, resposta_correta: 'C', explicacao: 'Duas células idênticas.', topico: 'Mitose' },
    { pergunta: 'Em que fase os cromossomos se alinham no centro?', opcoes: { A: 'Prófase', B: 'Metáfase', C: 'Anáfase', D: 'Telófase' }, resposta_correta: 'B', explicacao: 'Na metáfase ficam na placa equatorial.', topico: 'Mitose' },
    { pergunta: 'A meiose produz células:', opcoes: { A: 'diploides', B: 'idênticas', C: 'com o dobro de cromossomos', D: 'haploides' }, resposta_correta: 'D', explicacao: 'Metade dos cromossomos.', topico: 'Meiose' },
    { pergunta: 'O crossing-over acontece na:', opcoes: { A: 'prófase I', B: 'anáfase II', C: 'interfase', D: 'telófase I' }, resposta_correta: 'A', explicacao: 'Na prófase I da meiose.', topico: 'Meiose' },
  ],
  prova: [
    { pergunta: 'Qual processo garante variabilidade genética?', opcoes: { A: 'Mitose', B: 'Meiose', C: 'Osmose', D: 'Difusão' }, resposta_correta: 'B', explicacao: 'O crossing-over e a segregação independente.', topico: 'Meiose' },
    { pergunta: 'A regeneração de tecidos depende principalmente de:', opcoes: { A: 'meiose', B: 'fecundação', C: 'mitose', D: 'fotossíntese' }, resposta_correta: 'C', explicacao: 'Mitose repõe células.', topico: 'Mitose' },
    { pergunta: 'Qual estrutura delimita a célula?', opcoes: { A: 'Membrana plasmática', B: 'Núcleo', C: 'Centríolo', D: 'Lisossomo' }, resposta_correta: 'A', explicacao: 'A membrana separa o meio interno do externo.', topico: 'Células' },
  ],
}) + '\n```';

const IA_REDACAO = 'Aqui está: {"notas":{"c1":150,"c2":160,"c3":120,"c4":200,"c5":95},"comentarios":{"c1":"Poucos desvios.","c2":"Repertório pertinente.","c3":"Argumento 2 pouco desenvolvido.","c4":"Boa coesão.","c5":"Faltou detalhar o meio."},"pontos_fortes":["Tese clara"],"melhorias":["Detalhar o agente","Aprofundar o segundo argumento"],"paragrafo_reescrito":"Portanto, cabe ao Ministério da Educação..."}';

function lerCorpo(req) {
  return new Promise((ok) => { let d = ''; req.on('data', (c) => { d += c; }); req.on('end', () => { try { ok(d ? JSON.parse(d) : {}); } catch (_) { ok({}); } }); });
}
function json(res, corpo, status = 200) {
  res.writeHead(status, { 'Content-Type': 'application/json', 'Access-Control-Allow-Origin': '*', 'Access-Control-Allow-Headers': '*' });
  res.end(JSON.stringify(corpo));
}
const tokenDe = (req) => (req.headers.authorization || '').replace('Bearer ', '') || null;

async function usuarioDe(sub) {
  const r = await pool.query('select id from public.be_usuarios where auth_user_id = $1', [sub]);
  return r.rows[0] ? r.rows[0].id : null;
}

async function gerarConteudo(req, res) {
  const sub = tokenDe(req);
  const corpo = await lerCorpo(req);
  const uid = sub && await usuarioDe(sub);
  if (!uid) return json(res, { error: 'não autenticado' }, 401);
  const admin = clienteAdmin();
  const { data: acesso } = await admin.rpc('be_materia_acessivel_para', { p_usuario: uid, p_materia: corpo.materia_id });
  if (!acesso) return json(res, { error: 'matéria não encontrada' }, 404);
  const hoje = new Date().toISOString().slice(0, 10);
  const { data: uso } = await admin.from('be_uso_ia').select('quantidade').eq('usuario_id', uid).eq('data', hoje).maybeSingle();
  const usado = uso ? uso.quantidade : 0;
  if (usado >= 7) return json(res, { error: 'Sua energia de hoje acabou (7 gerações por dia). Ela recarrega amanhã!' }, 429);
  const gerado = normalizarGerado(extrairJson(IA_CONTEUDO));
  const salvo = await persistirConteudo(admin, { usuarioId: uid, materiaId: corpo.materia_id, tipoFonte: corpo.tipo_fonte, url: null, gerado });
  await admin.rpc('be_incrementar_uso_ia', { p_usuario_id: uid });
  await admin.rpc('be_ganhar_xp', { p_usuario: uid, p_tipo: 'material', p_pontos: 20, p_ref: corpo.materia_id });
  let plano = null;
  const { data: m } = await admin.from('be_materias').select('data_prova').eq('id', corpo.materia_id).single();
  if (m && m.data_prova) {
    const r = await chamarRpc(sub, 'be_gerar_plano', { p_materia: corpo.materia_id });
    if (r.error) return json(res, { error: r.error.message }, 500);
    plano = r.data;
  }
  json(res, { ok: true, ...salvo, plano_tarefas: plano, energia_restante: 7 - (usado + 1) });
}

async function corrigirRedacao(req, res) {
  const sub = tokenDe(req);
  const corpo = await lerCorpo(req);
  const uid = sub && await usuarioDe(sub);
  if (!uid) return json(res, { error: 'não autenticado' }, 401);
  if ((corpo.texto || '').length < 400) return json(res, { error: 'curta demais' }, 400);
  const c = normalizarCorrecao(IA_REDACAO);
  const admin = clienteAdmin();
  const { data, error } = await admin.from('be_redacoes').insert({
    usuario_id: uid, tema: corpo.tema, texto: corpo.texto, notas: c.notas, total: c.total,
    feedback: { comentarios: c.comentarios, pontos_fortes: c.pontos_fortes, melhorias: c.melhorias, paragrafo_reescrito: c.paragrafo_reescrito },
  }).select('id').single();
  if (error) return json(res, { error: error.message }, 500);
  await admin.rpc('be_incrementar_uso_ia', { p_usuario_id: uid });
  await admin.rpc('be_ganhar_xp', { p_usuario: uid, p_tipo: 'redacao', p_pontos: 30, p_ref: data.id });
  json(res, { ok: true, id: data.id, ...c, xp: 30, energia_restante: 5 });
}

http.createServer(async (req, res) => {
  try {
    const url = new URL(req.url, 'http://x');
    if (req.method === 'OPTIONS') return json(res, {});
    if (req.method === 'POST' && url.pathname === '/__auth/signup') {
      const { email, password } = await lerCorpo(req);
      if (senhas.has(email)) return json(res, { error: { message: 'User already registered' } });
      const id = randomUUID();
      await pool.query('insert into auth.users (id, email) values ($1, $2)', [id, email]);
      senhas.set(email, { id, password });
      return json(res, { session: { access_token: id, user: { id, email, user_metadata: {} } } });
    }
    if (req.method === 'POST' && url.pathname === '/__auth/login') {
      const { email, password } = await lerCorpo(req);
      const u = senhas.get(email);
      if (!u || u.password !== password) return json(res, { error: { message: 'Invalid login credentials' } });
      return json(res, { session: { access_token: u.id, user: { id: u.id, email, user_metadata: {} } } });
    }
    if (req.method === 'POST' && url.pathname === '/__db') return json(res, await executar(tokenDe(req), await lerCorpo(req)));
    if (req.method === 'POST' && url.pathname.startsWith('/__rpc/')) return json(res, await chamarRpc(tokenDe(req), url.pathname.slice(7), await lerCorpo(req)));
    if (req.method === 'POST' && url.pathname === '/functions/v1/estude-gerar-conteudo') return await gerarConteudo(req, res);
    if (req.method === 'POST' && url.pathname === '/functions/v1/estude-corrigir-redacao') return await corrigirRedacao(req, res);
    if (url.pathname === '/mock-supabase.js') {
      res.writeHead(200, { 'Content-Type': 'text/javascript' });
      return res.end(fs.readFileSync(path.join(import.meta.dirname, 'mock-supabase.js')));
    }
    const arq = path.join(SITE, url.pathname === '/' ? 'index.html' : url.pathname);
    if (!arq.startsWith(SITE) || !fs.existsSync(arq)) { res.writeHead(404); return res.end('404'); }
    res.writeHead(200, { 'Content-Type': TIPOS[path.extname(arq)] || 'application/octet-stream' });
    res.end(fs.readFileSync(arq));
  } catch (e) {
    console.error(e);
    json(res, { error: String(e.message || e) }, 500);
  }
}).listen(8787, () => console.log('teste em http://localhost:8787'));
