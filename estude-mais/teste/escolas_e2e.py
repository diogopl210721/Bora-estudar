"""Teste de ponta a ponta das escolas parceiras do EstudeUp (banco local com a escola de demonstração carregada).
Aluna: cartão no Hoje, mural, página da escola. Gestor: painel, oportunidade com regra obrigatória, logo.
Professor: não edita a página. Criador: aprova oportunidade e escola, contatos do formulário público. Páginas públicas sem login."""
import os, re, sys, json, subprocess
from playwright.sync_api import sync_playwright

BASE = 'http://localhost:8787'
AQUI = os.path.dirname(os.path.abspath(__file__))
SHOTS = os.path.join(AQUI, 'shots')
os.makedirs(SHOTS, exist_ok=True)
MOCK = open(os.path.join(AQUI, 'mock-supabase.js'), encoding='utf-8').read()
LOGO = os.path.join(AQUI, '..', 'site', 'adesivos', 'escola.webp')
SENHA_DEMO = 'MonteAurora2026'
erros, falhas = [], []

AUTO = '''
window.addEventListener('DOMContentLoaded', () => {
  new MutationObserver(() => {
    const d = document.getElementById('dlg');
    if (d && !d.hidden && !d.dataset.lido) {
      d.dataset.lido = '1';
      (window.__dialogos = window.__dialogos || []).push(document.getElementById('dlg-texto').textContent);
      if (!document.getElementById('dlg-campo-wrap').hidden) document.getElementById('dlg-campo').value = window.__respostaDlg || '';
      setTimeout(() => { document.getElementById('dlg-ok').click(); delete d.dataset.lido; }, 120);
    }
  }).observe(document.body, { subtree: true, attributes: true, attributeFilter: ['hidden'] });
});'''


def sql(q):
    return subprocess.run(['psql', '-h', '/tmp', '-p', '54329', '-U', 'postgres', '-d', 'estude', '-X', '-At', '-c', q], capture_output=True, text=True).stdout.strip()


def confere(cond, msg):
    print(('ok   ' if cond else 'FALHA ') + msg)
    if not cond:
        falhas.append(msg)


def contexto(nav, largura=390):
    ctx = nav.new_context(viewport={'width': largura, 'height': 900}, locale='pt-BR')
    ctx.add_init_script(AUTO)
    ctx.route(re.compile(r'https://cdn\.jsdelivr\.net/npm/@supabase.*'), lambda r: r.fulfill(status=200, content_type='text/javascript', body=MOCK))
    ctx.route(re.compile(r'https://fonts\.(googleapis|gstatic)\.com/.*'), lambda r: r.abort())
    ctx.route(re.compile(r'https://www\.ddsinovacao\.com\.br/estudemais/(.*)'),
              lambda r: r.fulfill(response=r.fetch(url=BASE + '/' + re.sub(r'^https://www\.ddsinovacao\.com\.br/estudemais/', '', r.request.url))))
    ctx.route(re.compile(r'https://arquivos\.exemplo-teste\.com/(.*)'),
              lambda r: r.fulfill(response=r.fetch(url=BASE + '/__arquivos/' + re.sub(r'^https://arquivos\.exemplo-teste\.com/', '', r.request.url))))
    p = ctx.new_page()
    p.on('console', lambda m: erros.append(f'console: {m.text}') if m.type == 'error' else None)
    p.on('pageerror', lambda e: erros.append(f'pageerror: {e}'))
    return ctx, p


def entrar(p, email, senha=SENHA_DEMO):
    p.goto(BASE + '/')
    p.evaluate('localStorage.clear()')
    p.goto(BASE + '/')
    p.fill('#input-email-login', email)
    p.fill('#input-senha-login', senha)
    p.click('#btn-login')
    p.wait_for_selector('#screen-home.active', timeout=15000)
    p.wait_for_timeout(900)


def dialogos(p):
    return p.evaluate('window.__dialogos || []')


with sync_playwright() as pw:
    nav = pw.chromium.launch()

    # ---------- páginas públicas, sem login ----------
    ctx, p = contexto(nav, 1280)
    p.goto(BASE + '/oportunidades.html')
    p.wait_for_selector('#mural-lista .op-card')
    confere(p.locator('#mural-lista .op-card').count() >= 5, 'mural público lista as oportunidades no ar')
    confere(p.locator('#mural-lista >> text=Olimpíada interna').count() == 0, 'oportunidade vencida não aparece')
    confere(p.locator('#mural-lista >> text=Inglês nas férias').count() == 0, 'oportunidade esperando aprovação não aparece')
    p.goto(BASE + '/escola.html?e=colegio-monte-aurora')
    p.wait_for_selector('#escola .escola-pagina')
    confere('Escola de demonstração' in p.inner_text('#escola'), 'página pública avisa que a escola é de demonstração')
    p.click('#escola .escola-cta')
    p.wait_for_timeout(500)
    confere(any('demonstração' in d for d in dialogos(p)), 'contato da escola demo explica em vez de abrir o WhatsApp')
    vistos_antes = int(sql("select count(*) from be_vitrine_eventos where tipo = 'ver_escola' and dia = be_hoje()"))
    p.reload(); p.wait_for_selector('#escola .escola-pagina'); p.wait_for_timeout(600)
    vistos_depois = int(sql("select count(*) from be_vitrine_eventos where tipo = 'ver_escola' and dia = be_hoje()"))
    confere(vistos_depois == vistos_antes, 'recarregar a página no mesmo dia não conta visita de novo')
    p.goto(BASE + '/escolas.html')
    p.wait_for_selector('#form-interesse')
    p.fill('#f-inst', 'Colégio Teste do Formulário'); p.fill('#f-resp', 'Marta Lima'); p.fill('#f-email', 'marta@colegioteste.com.br')
    p.fill('#f-tel', '(41) 98888-1234'); p.fill('#f-cidade', 'Curitiba'); p.select_option('#f-tipo', 'escola')
    p.click('#btn-interesse'); p.wait_for_timeout(500)
    confere(not p.is_hidden('#form-erro') and 'autorização' in p.inner_text('#form-erro'), 'formulário pede a autorização de contato')
    p.check('#f-consent'); p.click('#btn-interesse'); p.wait_for_selector('#form-ok:not([hidden])')
    confere(sql("select count(*) from be_leads where email = 'marta@colegioteste.com.br' and consentimento") == '1', 'contato da escola gravado com o consentimento')
    p.screenshot(path=os.path.join(SHOTS, 'escolas-publica.png'))
    ctx.close()

    # ---------- aluna ----------
    ctx, p = contexto(nav)
    entrar(p, 'laura.monteaurora@example.com')
    p.wait_for_selector('#home-oportunidades .op-mini')
    confere(p.locator('#home-oportunidades .op-mini').count() >= 1, 'Hoje mostra o cartão de oportunidades')
    p.evaluate('verOportunidades()'); p.wait_for_selector('#op-lista .op-card')
    confere('nunca mostram propaganda' in p.inner_text('#screen-oportunidades'), 'mural do app diz que o tutor não tem propaganda')
    p.evaluate("abrirEscolaApp('colegio-monte-aurora')"); p.wait_for_selector('#escola-conteudo .escola-pagina')
    confere(p.locator('#escola-conteudo .op-card').count() >= 5, 'página da escola no app mostra as oportunidades')
    p.evaluate('verPerfil()'); p.wait_for_timeout(900)
    confere(p.locator('#perfil-escola .convite-escola').count() == 0, 'aluna não vê o convite de cadastrar escola')
    r = p.evaluate("rpc('be_escola_painel', { p_inst: (Vitrine.cache.escolas['colegio-monte-aurora'] || {}).id }).then(() => 'abriu', (e) => e.message)")
    confere(r != 'abriu', 'aluna não abre o painel da escola')
    ctx.close()

    # ---------- professor ----------
    ctx, p = contexto(nav)
    entrar(p, 'helena.monteaurora@example.com')
    p.evaluate('verMinhaEscola()'); p.wait_for_selector('#me-abas .chip')
    abas = p.locator('#me-abas .chip').all_inner_texts()
    confere(abas == ['Minhas turmas', 'A escola'], f'professor vê só as abas dele ({abas})')
    inst = sql("select id from be_instituicoes where slug = 'colegio-monte-aurora'")
    r = p.evaluate(f"rpc('be_escola_salvar', {{ p_inst: '{inst}', p_dados: {{ nome: 'Hackeado' }} }}).then(() => 'salvou', (e) => e.message)")
    confere(r != 'salvou' and sql(f"select nome from be_instituicoes where id = '{inst}'") == 'Colégio Monte Aurora', 'professor não edita a página da escola')
    ctx.close()

    # ---------- gestor ----------
    ctx, p = contexto(nav)
    entrar(p, 'coordenacao.monteaurora@example.com')
    p.evaluate('verMinhaEscola()'); p.wait_for_selector('#me-conteudo .nums-grupo')
    confere(p.locator('#me-abas .chip').count() == 6, 'gestor vê as 6 abas do painel')
    confere('Escola de demonstração' in p.inner_text('#me-conteudo'), 'painel avisa que a escola é de demonstração')
    p.evaluate("abaEscola('professores')"); p.wait_for_timeout(300)
    codigo = sql(f"select codigo_professor from be_instituicoes where id = '{inst}'")
    confere(codigo in p.inner_text('#me-conteudo'), 'gestor vê o código de professor')
    p.evaluate("abaEscola('oportunidades')"); p.click('.limite-ops .btn'); p.wait_for_selector('#op-form')
    p.select_option('#of-categoria', 'desconto'); p.fill('#of-titulo', 'Desconto para irmãos'); p.fill('#of-descricao', 'Irmãos estudando na escola ganham desconto na mensalidade.')
    p.click('#btn-of-enviar'); p.wait_for_timeout(500)
    confere(any('regras' in d for d in dialogos(p)), 'desconto sem regras não vai pra aprovação')
    p.fill('#of-regras', '10% para o segundo irmão e 15% a partir do terceiro, válido para 2027.'); p.click('#btn-of-enviar'); p.wait_for_timeout(1500)
    confere(sql("select status from be_oportunidades where titulo = 'Desconto para irmãos'") == 'pendente', 'oportunidade com regras vai pra aprovação')
    p.evaluate("abaEscola('pagina')"); p.wait_for_selector('#pg-logo-arq', state='attached')
    p.set_input_files('#pg-logo-arq', LOGO); p.wait_for_timeout(2500)
    confere(sql(f"select logo_url like 'https://arquivos.exemplo-teste.com/estude-escolas/{inst}/logo-%' from be_instituicoes where id = '{inst}'") == 't', 'gestor troca a logo (arquivo na pasta da escola)')
    outra = sql("insert into be_instituicoes (nome, slug, status) values ('Outra Escola', 'outra-escola', 'aprovada') returning id").splitlines()[0]
    r = p.evaluate(f"sb.storage.from('estude-escolas').upload('{outra}/logo-x.webp', new Blob(['x'], {{ type: 'image/webp' }}), {{ contentType: 'image/webp' }}).then((r) => r.error ? 'negou' : 'enviou')")
    confere(r == 'negou', 'gestor não envia imagem na pasta de outra escola')
    r = p.evaluate(f"rpc('be_escola_salvar', {{ p_inst: '{outra}', p_dados: {{ nome: 'Invadida' }} }}).then(() => 'salvou', (e) => e.message)")
    confere(r != 'salvou', 'gestor não edita outra escola')
    r = p.evaluate("rpc('be_admin_escolas', {}).then(() => 'abriu', (e) => e.message)")
    confere(r != 'abriu', 'gestor não abre a área comercial')
    p.screenshot(path=os.path.join(SHOTS, 'escola-painel.png'))
    ctx.close()

    # ---------- criador ----------
    ctx, p = contexto(nav)
    entrar(p, 'criador@teste.com', 'senha-de-teste')
    p.evaluate('verCriador()'); p.wait_for_selector('#criador-comercial .criador-atalho')
    confere('pra aprovar' in p.inner_text('#criador-comercial'), 'painel do criador avisa oportunidade esperando')
    p.evaluate("verComercial('oportunidades')"); p.wait_for_selector('#com-conteudo .op-adm')
    op = sql("select id from be_oportunidades where titulo = 'Desconto para irmãos'")
    p.evaluate("window.__respostaDlg = ''")
    p.evaluate(f"statusOportunidadeAdm('{op}', 'recusada')"); p.wait_for_timeout(700)
    confere(sql(f"select status from be_oportunidades where id = '{op}'") == 'pendente', 'recusar sem motivo não muda nada')
    p.evaluate(f"statusOportunidadeAdm('{op}', 'publicada')"); p.wait_for_timeout(1200)
    confere(sql(f"select status from be_oportunidades where id = '{op}'") == 'publicada', 'criador publica a oportunidade')
    p.evaluate("verComercial('contatos')"); p.wait_for_selector('#com-conteudo .lead')
    confere('Colégio Teste do Formulário' in p.inner_text('#com-conteudo'), 'contato do formulário aparece pro criador')
    p.evaluate("verComercial('escolas')"); p.wait_for_timeout(800)
    p.evaluate("ESC.com.escolas = ''; verComercial('escolas')"); p.wait_for_selector('#com-conteudo .escola-adm')
    confere(p.locator('#com-conteudo .escola-adm').count() >= 2, 'criador vê as escolas')
    p.evaluate("verComercial('resumo')"); p.wait_for_selector('#com-conteudo .nums-grupo')
    p.screenshot(path=os.path.join(SHOTS, 'comercial.png'))
    ctx.close()
    nav.close()

sql("delete from be_instituicoes where slug = 'outra-escola'")
# o 403 do envio na pasta de outra escola é esperado (é o próprio teste de bloqueio)
erros = [e for e in erros if 'status of 403' not in e]
print('\nerros de página:', json.dumps(erros, ensure_ascii=False) if erros else 'nenhum')
print(f'\n{len(falhas)} falha(s)' if falhas else '\ntudo certo nas escolas')
sys.exit(1 if falhas or erros else 0)
