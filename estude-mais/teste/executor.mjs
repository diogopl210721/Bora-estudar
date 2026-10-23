// Executa as consultas do "supabase de mentira" num Postgres local, com RLS de verdade.
import pg from 'pg';

// como a API do Supabase: conecta como "authenticator" e troca para o papel do token
export const pool = new pg.Pool({ host: '/tmp', port: 54329, user: 'authenticator', database: 'estude', max: 8 });
export const poolAdmin = new pg.Pool({ host: '/tmp', port: 54329, user: 'postgres', database: 'estude', max: 2 });

const ID = /^[a-z_][a-z0-9_]*$/;
function ident(x) {
  if (!ID.test(x)) throw new Error('identificador inválido: ' + x);
  return '"' + x + '"';
}
function colunas(sel) {
  const s = (sel || '*').trim();
  if (s === '*') return '*';
  return s.split(',').map((c) => c.trim()).filter(Boolean).map(ident).join(', ');
}

async function comPapel(sub, fn) {
  const c = await pool.connect();
  try {
    await c.query('begin');
    if (sub) {
      await c.query('set local role authenticated');
      await c.query("select set_config('request.jwt.claim.sub', $1, true), set_config('request.jwt.claims', $2, true)", [sub, JSON.stringify({ sub, role: 'authenticated' })]);
    } else {
      await c.query('set local role service_role');
      await c.query("select set_config('request.jwt.claims', $1, true)", [JSON.stringify({ role: 'service_role' })]);
    }
    const r = await fn(c);
    await c.query('commit');
    return r;
  } catch (e) {
    await c.query('rollback').catch(() => {});
    throw e;
  } finally {
    c.release();
  }
}

function onde(filtros, params) {
  const partes = [];
  for (const f of filtros || []) {
    const col = ident(f.col);
    if (f.op === 'eq') { params.push(f.val); partes.push(`${col} = $${params.length}`); }
    else if (f.op === 'neq') { params.push(f.val); partes.push(`${col} <> $${params.length}`); }
    else if (f.op === 'ilike') { params.push(f.val); partes.push(`${col} ilike $${params.length}`); }
    else if (f.op === 'in') { params.push(f.val); partes.push(`${col} = any($${params.length})`); }
    else if (f.op === 'is') { partes.push(`${col} is ${f.val === null ? 'null' : f.val ? 'true' : 'false'}`); }
    else if (f.op === 'not_is') { partes.push(`${col} is not ${f.val === null ? 'null' : f.val ? 'true' : 'false'}`); }
    else if (f.op === 'gte') { params.push(f.val); partes.push(`${col} >= $${params.length}`); }
    else if (f.op === 'lte') { params.push(f.val); partes.push(`${col} <= $${params.length}`); }
    else if (f.op === 'gt') { params.push(f.val); partes.push(`${col} > $${params.length}`); }
    else throw new Error('filtro não suportado no teste: ' + f.op);
  }
  return partes.length ? ' where ' + partes.join(' and ') : '';
}

function valor(v) {
  if (v !== null && typeof v === 'object' && !Array.isArray(v)) return JSON.stringify(v);
  if (Array.isArray(v) && v.some((x) => x !== null && typeof x === 'object')) return JSON.stringify(v);
  return v;
}

export async function executar(sub, q) {
  const tabela = 'public.' + ident(q.table);
  try {
    const data = await comPapel(sub, async (c) => {
      const params = [];
      if (q.op === 'select') {
        if (q.head) {
          const r = await c.query(`select count(*)::int n from ${tabela}${onde(q.filters, params)}`, params);
          return { data: null, count: r.rows[0].n };
        }
        let sql = `select ${colunas(q.columns)} from ${tabela}${onde(q.filters, params)}`;
        if (q.order && q.order.length) sql += ' order by ' + q.order.map((o) => `${ident(o.col)} ${o.asc === false ? 'desc' : 'asc'}`).join(', ');
        if (q.limit) sql += ' limit ' + Number(q.limit);
        const r = await c.query(sql, params);
        return { data: r.rows };
      }
      if (q.op === 'insert') {
        const linhas = Array.isArray(q.values) ? q.values : [q.values];
        const cols = Array.from(new Set(linhas.flatMap((l) => Object.keys(l))));
        const vals = linhas.map((l) => '(' + cols.map((k) => { if (!(k in l)) return 'default'; params.push(valor(l[k])); return `$${params.length}`; }).join(', ') + ')');
        const ret = q.returning ? ' returning ' + colunas(q.returning) : '';
        const r = await c.query(`insert into ${tabela} (${cols.map(ident).join(', ')}) values ${vals.join(', ')}${ret}`, params);
        return { data: q.returning ? r.rows : null };
      }
      if (q.op === 'upsert') {
        // como o PostgREST: conflito na chave primária atualiza a linha
        const pk = await c.query(`select a.attname from pg_index i join pg_attribute a on a.attrelid = i.indrelid and a.attnum = any(i.indkey)
                                  where i.indrelid = $1::regclass and i.indisprimary`, [tabela]);
        const chave = pk.rows.map((r) => r.attname);
        const linhas = Array.isArray(q.values) ? q.values : [q.values];
        const cols = Array.from(new Set(linhas.flatMap((l) => Object.keys(l))));
        const vals = linhas.map((l) => '(' + cols.map((k) => { if (!(k in l)) return 'default'; params.push(valor(l[k])); return `$${params.length}`; }).join(', ') + ')');
        const resto = cols.filter((k) => !chave.includes(k));
        const conflito = resto.length ? `do update set ${resto.map((k) => `${ident(k)} = excluded.${ident(k)}`).join(', ')}` : 'do nothing';
        await c.query(`insert into ${tabela} (${cols.map(ident).join(', ')}) values ${vals.join(', ')} on conflict (${chave.map(ident).join(', ')}) ${conflito}`, params);
        return { data: null };
      }
      if (q.op === 'update') {
        const sets = Object.entries(q.values).map(([k, v]) => { params.push(valor(v)); return `${ident(k)} = $${params.length}`; });
        const ret = q.returning ? ' returning ' + colunas(q.returning) : '';
        const r = await c.query(`update ${tabela} set ${sets.join(', ')}${onde(q.filters, params)}${ret}`, params);
        return { data: q.returning ? r.rows : null };
      }
      if (q.op === 'delete') {
        await c.query(`delete from ${tabela}${onde(q.filters, params)}`, params);
        return { data: null };
      }
      throw new Error('operação não suportada: ' + q.op);
    });
    if (q.single || q.maybeSingle) {
      const rows = data.data || [];
      if (rows.length > 1 || (q.single && rows.length === 0)) {
        return { data: null, error: { message: 'JSON object requested, multiple (or no) rows returned', code: 'PGRST116' } };
      }
      return { data: rows[0] ?? null, error: null };
    }
    return { ...data, error: null };
  } catch (e) {
    return { data: null, error: { message: e.message, code: e.code } };
  }
}

export async function chamarRpc(sub, nome, args) {
  if (!ID.test(nome)) return { data: null, error: { message: 'rpc inválida' } };
  try {
    return await comPapel(sub, async (c) => {
      const info = await c.query("select proretset from pg_proc p join pg_namespace n on n.oid = p.pronamespace where n.nspname = 'public' and p.proname = $1", [nome]);
      if (!info.rows.length) throw new Error('função não existe: ' + nome);
      const params = [];
      const nomeados = Object.entries(args || {}).map(([k, v]) => { params.push(valor(v)); return `${ident(k)} => $${params.length}`; });
      if (info.rows[0].proretset) {
        const r = await c.query(`select * from public.${ident(nome)}(${nomeados.join(', ')})`, params);
        return { data: r.rows, error: null };
      }
      const r = await c.query(`select public.${ident(nome)}(${nomeados.join(', ')}) as r`, params);
      return { data: r.rows[0].r, error: null };
    });
  } catch (e) {
    return { data: null, error: { message: e.message, code: e.code } };
  }
}

// Cliente "service role" para o núcleo das Edge Functions (sem RLS), com a mesma API encadeável.
export function clienteAdmin() {
  return {
    from(table) { return construtor(null, table); },
    rpc(nome, args) { return chamarRpc(null, nome, args); },
  };
}

export function construtor(sub, table) {
  const q = { table, op: 'select', columns: '*', filters: [], order: [] };
  const b = {
    select(cols = '*', opts = {}) {
      if (q.op === 'select') { q.columns = cols; if (opts.head) q.head = true; } else q.returning = cols;
      return b;
    },
    insert(values) { q.op = 'insert'; q.values = values; return b; },
    upsert(values) { q.op = 'upsert'; q.values = values; return b; },
    gte(col, val) { q.filters.push({ op: 'gte', col, val }); return b; },
    lte(col, val) { q.filters.push({ op: 'lte', col, val }); return b; },
    gt(col, val) { q.filters.push({ op: 'gt', col, val }); return b; },
    update(values) { q.op = 'update'; q.values = values; return b; },
    delete() { q.op = 'delete'; return b; },
    eq(col, val) { q.filters.push({ op: 'eq', col, val }); return b; },
    neq(col, val) { q.filters.push({ op: 'neq', col, val }); return b; },
    ilike(col, val) { q.filters.push({ op: 'ilike', col, val }); return b; },
    in(col, val) { q.filters.push({ op: 'in', col, val }); return b; },
    is(col, val) { q.filters.push({ op: 'is', col, val }); return b; },
    not(col, op, val) { if (op !== 'is') throw new Error('not só com is'); q.filters.push({ op: 'not_is', col, val }); return b; },
    order(col, opts = {}) { q.order.push({ col, asc: opts.ascending !== false }); return b; },
    limit(n) { q.limit = n; return b; },
    single() { q.single = true; return b; },
    maybeSingle() { q.maybeSingle = true; return b; },
    then(ok, falha) { return executar(sub, q).then(ok, falha); },
    _q: q,
  };
  return b;
}
