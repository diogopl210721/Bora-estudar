// Servidor de teste do Estude+: site estático + supabase de mentira + Edge Functions com IA simulada.
import http from 'node:http';
import fs from 'node:fs';
import path from 'node:path';
import { randomUUID } from 'node:crypto';
import { poolAdmin as pool, executar, chamarRpc, clienteAdmin } from './executor.mjs';
import { extrairJson, normalizarGerado, persistirConteudo } from '../supabase/functions/estude-gerar-conteudo/nucleo.ts';
import { normalizarCorrecao } from '../supabase/functions/estude-corrigir-redacao/nucleo.ts';
import { LIMITE_TUTOR_DIA, XP_TUTOR, XP_TUTOR_MAX_DIA, limparResposta, montarMensagens, tituloDaConversa, validarPedido } from '../supabase/functions/estude-tutor/nucleo.ts';
import { LIMITE_PUBLICACOES_DIA, XP_PUBLICAR, lerModeracao, textoParaModerar, validarPublicacao } from '../supabase/functions/estude-publicar-resumo/nucleo.ts';
import { lerConferencia, validarConferencia } from '../supabase/functions/estude-conferir-resposta/nucleo.ts';
import { LIMITE_CADASTROS_HORA_IP, hashIp, validarCadastro } from '../supabase/functions/estude-cadastro/nucleo.ts';

const SITE = path.resolve(import.meta.dirname, '../site');
const TIPOS = { '.html': 'text/html; charset=utf-8', '.js': 'text/javascript', '.css': 'text/css', '.svg': 'image/svg+xml', '.png': 'image/png', '.webmanifest': 'application/manifest+json', '.woff2': 'font/woff2', '.txt': 'text/plain; charset=utf-8' };
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
  const { data: podeEditar } = await admin.rpc('be_pode_editar_materia_para', { p_usuario: uid, p_materia: corpo.materia_id });
  if (!podeEditar) return json(res, { error: 'Nessa turma só o professor adiciona material.' }, 403);
  const hoje = new Date().toISOString().slice(0, 10);
  const { data: uso } = await admin.from('be_uso_ia').select('quantidade').eq('usuario_id', uid).eq('data', hoje).maybeSingle();
  const usado = uso ? uso.quantidade : 0;
  if (usado >= 7) return json(res, { error: 'Sua energia de hoje acabou (7 gerações por dia). Ela recarrega amanhã!' }, 429);
  await new Promise((ok) => setTimeout(ok, 4600)); // a IA de verdade leva uns 30 s; aqui só o bastante pra ver as etapas da geração
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

// ---------- tutor, publicação e conferência por voz (mesma lógica das Edge Functions, IA simulada) ----------
const iaTutor = (msgs) => {
  const ultima = msgs[msgs.length - 1].content;
  const temFoto = ultima.some((b) => b.type === 'image');
  const pergunta = ultima.find((b) => b.type === 'text').text;
  if (temFoto) return 'Li o exercício da foto: **resolver 2x + 6 = 14**.\n\n1. Tira o 6 dos dois lados: 2x = 14 − 6 = 8.\n2. Divide os dois lados por 2: x = 8 ÷ 2.\n3. Confere: 2·4 + 6 = 14. Certo!\n\n**Resposta: x = 4**\n\nAgora tenta você: quanto dá x em 3x + 3 = 12?';
  return `Boa pergunta! Vamos por partes sobre "${pergunta.replace(/^\[matéria: [^\]]+\] /, '').slice(0, 60)}".\n\n1. Primeiro, a ideia principal: a mitose gera **duas células iguais**.\n2. Depois, a meiose gera **quatro células** com metade dos cromossomos.\n\nPra fixar: qual das duas forma os gametas?`;
};

async function tutor(req, res) {
  const sub = tokenDe(req);
  const uid = sub && await usuarioDe(sub);
  if (!uid) return json(res, { error: 'não autenticado' }, 401);
  let pedido;
  try { pedido = validarPedido(await lerCorpo(req)); } catch (e) { return json(res, { error: e.message }, 400); }
  const admin = clienteAdmin();
  const hoje = new Date().toISOString().slice(0, 10);
  const { data: uso } = await admin.from('be_uso_tutor').select('quantidade').eq('usuario_id', uid).eq('data', hoje).maybeSingle();
  const usado = uso ? uso.quantidade : 0;
  if (usado >= LIMITE_TUTOR_DIA) return json(res, { error: `Você já fez ${LIMITE_TUTOR_DIA} perguntas hoje. O tutor volta amanhã!` }, 429);
  let conversaId = pedido.conversaId;
  let historico = [];
  if (conversaId) {
    const { data: c } = await admin.from('be_tutor_conversas').select('id, usuario_id').eq('id', conversaId).maybeSingle();
    if (!c || c.usuario_id !== uid) return json(res, { error: 'conversa não encontrada' }, 404);
    const { data: msgs } = await admin.from('be_tutor_mensagens').select('papel, texto, tinha_foto, created_at').eq('conversa_id', conversaId).order('created_at', { ascending: true });
    historico = msgs || [];
  } else {
    const { data: nova, error } = await admin.from('be_tutor_conversas').insert({ usuario_id: uid, materia: pedido.materia, titulo: tituloDaConversa(pedido.texto, !!pedido.imagem) }).select('id').single();
    if (error) return json(res, { error: 'não consegui abrir a conversa' }, 500);
    conversaId = nova.id;
  }
  await new Promise((ok) => setTimeout(ok, 900));
  const texto = limparResposta(iaTutor(montarMensagens(historico, pedido)));
  const agora = Date.now();
  await admin.from('be_tutor_mensagens').insert([
    { conversa_id: conversaId, papel: 'aluno', texto: pedido.texto || 'Resolve esse exercício da foto, passo a passo.', tinha_foto: !!pedido.imagem, created_at: new Date(agora - 5).toISOString() },
    { conversa_id: conversaId, papel: 'tutor', texto, created_at: new Date(agora).toISOString() },
  ]);
  await admin.from('be_tutor_conversas').update({ updated_at: new Date().toISOString() }).eq('id', conversaId);
  await admin.from('be_uso_tutor').upsert({ usuario_id: uid, data: hoje, quantidade: usado + 1 });
  let xp = 0;
  const inicioDia = new Date(); inicioDia.setUTCHours(3, 0, 0, 0);
  if (inicioDia.getTime() > Date.now()) inicioDia.setUTCDate(inicioDia.getUTCDate() - 1);
  const { count: xpHoje } = await admin.from('be_xp_eventos').select('id', { count: 'exact', head: true }).eq('usuario_id', uid).eq('tipo', 'tutor').gte('created_at', inicioDia.toISOString());
  if ((xpHoje ?? 0) < XP_TUTOR_MAX_DIA) { await admin.rpc('be_ganhar_xp', { p_usuario: uid, p_tipo: 'tutor', p_pontos: XP_TUTOR, p_ref: conversaId }); xp = XP_TUTOR; }
  json(res, { ok: true, conversa_id: conversaId, resposta: texto, xp, restantes: LIMITE_TUTOR_DIA - (usado + 1) });
}

async function publicarResumo(req, res) {
  const sub = tokenDe(req);
  const uid = sub && await usuarioDe(sub);
  if (!uid) return json(res, { error: 'não autenticado' }, 401);
  let pub;
  try { pub = validarPublicacao(await lerCorpo(req)); } catch (e) { return json(res, { error: e.message }, 400); }
  const admin = clienteAdmin();
  const desde = new Date(Date.now() - 24 * 3600 * 1000).toISOString();
  const { count: hoje } = await admin.from('be_resumos').select('id', { count: 'exact', head: true }).eq('autor_id', uid).gte('created_at', desde);
  if ((hoje ?? 0) >= LIMITE_PUBLICACOES_DIA) return json(res, { error: `Você já publicou ${LIMITE_PUBLICACOES_DIA} resumos nas últimas 24 horas. Amanhã tem mais!` }, 429);
  if (pub.materiaId) {
    const { data: acesso } = await admin.rpc('be_materia_acessivel_para', { p_usuario: uid, p_materia: pub.materiaId });
    if (!acesso) pub.materiaId = null;
  }
  await new Promise((ok) => setTimeout(ok, 500));
  // moderação simulada: recusa quando o texto tem contato pessoal ou a palavra-teste PROIBIDO
  const texto = textoParaModerar(pub);
  const recusa = /PROIBIDO|whats|instagram/i.test(texto);
  const mod = lerModeracao(JSON.stringify(recusa ? { aprovado: false, motivo: 'O resumo tem conteúdo que não combina com a biblioteca (contato pessoal ou ofensa).' } : { aprovado: true, motivo: '' }));
  const { data: r, error } = await admin.from('be_resumos').insert({
    autor_id: uid, titulo: pub.titulo, materia: pub.materia, serie: pub.serie, conteudo: pub.conteudo,
    cartoes: pub.cartoes, cor: pub.cor, origem_materia_id: pub.materiaId,
    status: mod.aprovado ? 'publicado' : 'recusado', motivo_moderacao: mod.aprovado ? null : mod.motivo,
  }).select('id, status').single();
  if (error) return json(res, { error: 'não consegui salvar: ' + error.message }, 500);
  let xp = 0;
  if (mod.aprovado) {
    await admin.rpc('be_ganhar_xp', { p_usuario: uid, p_tipo: 'resumo_publicado', p_pontos: XP_PUBLICAR, p_ref: r.id });
    await admin.rpc('be_conceder_conquista', { p_usuario: uid, p_codigo: 'primeiro_resumo' });
    xp = XP_PUBLICAR;
  }
  json(res, { ok: true, id: r.id, publicado: mod.aprovado, motivo: mod.aprovado ? null : mod.motivo, xp });
}

async function conferirResposta(req, res) {
  const sub = tokenDe(req);
  const uid = sub && await usuarioDe(sub);
  if (!uid) return json(res, { error: 'não autenticado' }, 401);
  let c;
  try { c = validarConferencia(await lerCorpo(req)); } catch (e) { return json(res, { error: e.message }, 400); }
  const norm = (t) => t.toLowerCase().normalize('NFD').replace(/[\u0300-\u036f]/g, '');
  const chave = norm(c.esperado).split(/[^a-z0-9]+/).filter((w) => w.length > 3);
  const acertos = chave.filter((w) => norm(c.resposta).includes(w)).length;
  const resultado = acertos >= Math.max(1, Math.ceil(chave.length / 3)) ? 'certo' : acertos > 0 ? 'quase' : 'errado';
  const r = lerConferencia(JSON.stringify({ resultado, comentario: resultado === 'certo' ? 'Isso mesmo, você lembrou do essencial.' : `A resposta era: ${c.esperado}`, nota: resultado === 'certo' ? 3 : resultado === 'quase' ? 2 : 1 }));
  const admin = clienteAdmin();
  const hoje = new Date().toISOString().slice(0, 10);
  const { data: uso } = await admin.from('be_uso_tutor').select('quantidade').eq('usuario_id', uid).eq('data', hoje).maybeSingle();
  await admin.from('be_uso_tutor').upsert({ usuario_id: uid, data: hoje, quantidade: (uso ? uso.quantidade : 0) + 1 });
  json(res, { ok: true, ...r });
}

// cadastro sem e-mail de confirmação: mesma validação e limite da Edge Function
async function cadastro(req, res) {
  let dados;
  try { dados = validarCadastro(await lerCorpo(req)); } catch (e) { return json(res, { error: e.message }, 400); }
  const ipHash = await hashIp(req.socket.remoteAddress || 'local');
  const { rows } = await pool.query("select count(*)::int n from public.be_cadastro_tentativas where ip_hash = $1 and created_at > now() - interval '1 hour'", [ipHash]);
  if (rows[0].n >= LIMITE_CADASTROS_HORA_IP) return json(res, { error: 'Muitas contas criadas daqui agora. Espera um pouco e tenta de novo.' }, 429);
  await pool.query('insert into public.be_cadastro_tentativas (ip_hash) values ($1)', [ipHash]);
  if (senhas.has(dados.email)) return json(res, { error: 'Já existe uma conta com esse e-mail. Entra com sua senha ou toca em "esqueci minha senha".' }, 409);
  const id = randomUUID();
  await pool.query('insert into auth.users (id, email) values ($1, $2)', [id, dados.email]);
  senhas.set(dados.email, { id, password: dados.senha });
  json(res, { ok: true });
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
      const { email: bruto, password } = await lerCorpo(req);
      const email = String(bruto || '').trim().toLowerCase();
      const u = senhas.get(email);
      if (!u || u.password !== password) return json(res, { error: { message: 'Invalid login credentials' } });
      return json(res, { session: { access_token: u.id, user: { id: u.id, email, user_metadata: {} } } });
    }
    if (req.method === 'POST' && url.pathname === '/__db') return json(res, await executar(tokenDe(req), await lerCorpo(req)));
    if (req.method === 'POST' && url.pathname.startsWith('/__rpc/')) return json(res, await chamarRpc(tokenDe(req), url.pathname.slice(7), await lerCorpo(req)));
    if (req.method === 'POST' && url.pathname === '/functions/v1/estude-gerar-conteudo') return await gerarConteudo(req, res);
    if (req.method === 'POST' && url.pathname === '/functions/v1/estude-corrigir-redacao') return await corrigirRedacao(req, res);
    if (req.method === 'POST' && url.pathname === '/functions/v1/estude-tutor') return await tutor(req, res);
    if (req.method === 'POST' && url.pathname === '/functions/v1/estude-cadastro') return await cadastro(req, res);
    if (req.method === 'POST' && url.pathname === '/functions/v1/estude-publicar-resumo') return await publicarResumo(req, res);
    if (req.method === 'POST' && url.pathname === '/functions/v1/estude-conferir-resposta') return await conferirResposta(req, res);
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
