// Substitui o supabase-js no navegador durante o teste: manda tudo pro servidor local.
(function () {
  const CHAVE = 'mock_session';
  const ler = () => { try { return JSON.parse(localStorage.getItem(CHAVE)); } catch (_) { return null; } };
  const gravar = (s) => { if (s) localStorage.setItem(CHAVE, JSON.stringify(s)); else localStorage.removeItem(CHAVE); };
  async function post(caminho, corpo) {
    const s = ler();
    const r = await fetch(caminho, { method: 'POST', headers: { 'Content-Type': 'application/json', Authorization: s ? 'Bearer ' + s.access_token : '' }, body: JSON.stringify(corpo || {}) });
    return r.json();
  }
  function construtor(table) {
    const q = { table, op: 'select', columns: '*', filters: [], order: [] };
    const b = {
      select(cols = '*', opts = {}) { if (q.op === 'select') { q.columns = cols; if (opts.head) q.head = true; } else q.returning = cols; return b; },
      insert(v) { q.op = 'insert'; q.values = v; return b; },
      upsert(v) { q.op = 'upsert'; q.values = v; return b; },
      gte(col, val) { q.filters.push({ op: 'gte', col, val }); return b; },
      lte(col, val) { q.filters.push({ op: 'lte', col, val }); return b; },
      update(v) { q.op = 'update'; q.values = v; return b; },
      delete() { q.op = 'delete'; return b; },
      eq(col, val) { q.filters.push({ op: 'eq', col, val }); return b; },
      neq(col, val) { q.filters.push({ op: 'neq', col, val }); return b; },
      ilike(col, val) { q.filters.push({ op: 'ilike', col, val }); return b; },
      in(col, val) { q.filters.push({ op: 'in', col, val }); return b; },
      is(col, val) { q.filters.push({ op: 'is', col, val }); return b; },
      not(col, op, val) { q.filters.push({ op: 'not_is', col, val }); return b; },
      order(col, o = {}) { q.order.push({ col, asc: o.ascending !== false }); return b; },
      limit(n) { q.limit = n; return b; },
      single() { q.single = true; return b; },
      maybeSingle() { q.maybeSingle = true; return b; },
      then(ok, falha) { return post('/__db', q).then(ok, falha); },
    };
    return b;
  }
  const ouvintes = [];
  window.supabase = {
    createClient() {
      return {
        from: construtor,
        rpc: (nome, args) => post('/__rpc/' + nome, args),
        // sem tempo real no teste: o app cai na busca periódica
        channel() { const c = { on() { return c; }, subscribe(cb) { if (cb) setTimeout(() => cb('CHANNEL_ERROR'), 0); return c; } }; window.__canais = (window.__canais || 0) + 1; return c; },
        removeChannel() { window.__canais = (window.__canais || 1) - 1; return Promise.resolve('ok'); },
        auth: {
          async getSession() { return { data: { session: ler() } }; },
          async signUp({ email, password }) {
            const r = await post('/__auth/signup', { email, password });
            if (r.error) return { data: {}, error: r.error };
            gravar(r.session); return { data: { user: r.session.user, session: r.session }, error: null };
          },
          async signInWithPassword({ email, password }) {
            const r = await post('/__auth/login', { email, password });
            if (r.error) return { data: {}, error: r.error };
            gravar(r.session); return { data: { user: r.session.user, session: r.session }, error: null };
          },
          async signOut() { gravar(null); return { error: null }; },
          onAuthStateChange(cb) { ouvintes.push(cb); return { data: { subscription: { unsubscribe() {} } } }; },
          async updateUser() { return { data: {}, error: null }; },
          async signInWithOAuth() { return { error: { message: 'sem Google no teste' } }; },
          async resetPasswordForEmail() { return { error: null }; },
        },
      };
    },
  };
})();
