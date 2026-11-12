"""(cabeçalho copiado do teste das escolas) Teste de ponta a ponta das escolas parceiras do EstudeUp (banco local com a escola de demonstração carregada).
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
    ctx.route(re.compile(r'https://arffptuclrrzuzdrcmuc\.supabase\.co/.*'),
              lambda r: r.fulfill(response=r.fetch(url=BASE + re.sub(r'^https://[^/]+', '', r.request.url))))
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




# ---------- propaganda visível, app exclusivo e Aprenda Inglês ----------
SH = os.path.join(os.path.dirname(__file__), 'shots')
sql("update be_instituicoes set modo = 'parceira' where slug = 'colegio-monte-aurora'")
sql("delete from be_ingles_licoes; delete from be_ingles_erros")
with sync_playwright() as pw:
    nav = pw.chromium.launch()
    ctx, p = contexto(nav, 390)
    entrar(p, 'laura.monteaurora@example.com')
    p.wait_for_selector('#home-parceiras .parceira-slide', timeout=10000)
    caixa = p.locator('#home-parceiras').bounding_box()
    confere(caixa and caixa['y'] < 400, f"carrossel de escolas no topo do Hoje (y={caixa and int(caixa['y'])})")
    confere('patrocinado' in p.inner_text('#home-parceiras'), 'carrossel marcado como patrocinado')
    p.screenshot(path=os.path.join(SH, 'pat-home.png'))
    confere(p.locator('.atalho', has_text='Inglês').count() == 1, 'atalho Inglês na tela Hoje')

    # trilha e uma lição inteira, respondendo certo (e errando uma de propósito)
    p.click('.atalho:has-text("Inglês")'); p.wait_for_selector('#screen-ingles.active'); p.wait_for_selector('.ing-no.atual')
    p.screenshot(path=os.path.join(SH, 'ing-trilha.png'), full_page=True)
    p.click('.ing-no.atual button'); p.wait_for_selector('#screen-ingles-licao.active')
    errei = False; tipos = set(); passos = 0
    while p.evaluate("telaAtual()") == 'ingles-licao' and passos < 40:
        passos += 1
        e = p.evaluate("(() => { const s = ING.sessao, e = s.exercicios[s.i]; return { tipo: e.tipo, opcoes: e.opcoes, banco: e.banco, aceitas: e.aceitas, pares: e.pares }; })()")
        tipos.add(e['tipo'])
        if passos == 2: p.screenshot(path=os.path.join(SH, f'ing-ex-{e["tipo"]}.png'))
        if e['tipo'] in ('escolha', 'completar'):
            k = next(i for i, o in enumerate(e['opcoes']) if o['certa'])
            if not errei: k = (k + 1) % len(e['opcoes']); errei = True
            p.click(f'.ing-op[data-k="{k}"]'); p.click('#ing-conferir')
        elif e['tipo'] == 'montar':
            alvo = p.evaluate("princ(ING.sessao.exercicios[ING.sessao.i].aceitas)")
            usados = set()
            for t in p.evaluate("tokens(princ(ING.sessao.exercicios[ING.sessao.i].aceitas))"):
                k = next(i for i, b in enumerate(e['banco']) if b == t and i not in usados); usados.add(k)
                p.click(f'#ing-banco .ing-ficha[data-k="{k}"]')
            if passos == 5: p.screenshot(path=os.path.join(SH, 'ing-montar.png'))
            p.click('#ing-conferir')
        elif e['tipo'] == 'escrever':
            p.fill('#ing-texto', p.evaluate("princ(ING.sessao.exercicios[ING.sessao.i].aceitas)")); p.click('#ing-conferir')
        elif e['tipo'] == 'pares':
            for par in e['pares']:
                p.click(f'.ing-par[data-lado="e"]:has-text("{par[0]}")'); p.click(f'.ing-par[data-lado="d"]:has-text("{par[1]}")')
        elif e['tipo'] == 'falar':
            p.click('text=não posso falar agora'); continue
        p.wait_for_selector('.ing-rodape.certo, .ing-rodape.errado')
        p.click('.ing-rodape .btn')
    confere(p.evaluate("telaAtual()") == 'ingles-fim', f'lição terminou ({passos} passos, tipos: {sorted(tipos)})')
    confere({'escolha', 'montar', 'pares', 'escrever'} <= tipos, 'a lição tem exercícios variados')
    p.wait_for_function("document.getElementById('ingfim-xp').textContent.startsWith('+')", timeout=10000)
    p.wait_for_selector('#inglesfim-patrocinio .pat-fim', timeout=10000)
    confere(True, 'cartão patrocinado no fim da lição')
    p.screenshot(path=os.path.join(SH, 'ing-fim.png'), full_page=True)
    confere(sql("select count(*) from be_ingles_licoes where licao = 'u1l1'") == '1', 'lição gravada no banco')
    confere(int(sql("select count(*) from be_ingles_erros")) >= 1, 'o que errou foi pra revisão')
    p.click('text=Voltar pra trilha'); p.wait_for_selector('.ing-no.feita')
    confere(p.locator('text=Revisar o que eu errei').count() == 1, 'botão de revisão aparece')

    # app exclusivo: a escola vira dona do app pra Laura
    sql("update be_instituicoes set modo = 'exclusiva' where slug = 'colegio-monte-aurora'")
    p.evaluate("aplicarMarca().then(() => verHoje())"); p.wait_for_timeout(1500)
    confere('Monte Aurora' in p.inner_text('#screen-home .brand'), 'marca da escola no topo do app')
    confere('Sua escola' in p.inner_text('#home-parceiras'), 'carrossel vira "Sua escola"')
    p.screenshot(path=os.path.join(SH, 'exclusivo-home.png'))
    ctx.close()

    # login pelo link da escola
    ctx, p = contexto(nav, 390)
    p.goto(BASE + '/?escola=colegio-monte-aurora'); p.wait_for_timeout(1500)
    confere('Monte Aurora' in p.inner_text('#screen-login .brand'), 'tela de login com a marca da escola pelo link')
    p.screenshot(path=os.path.join(SH, 'exclusivo-login.png'))
    ctx.close(); nav.close()
sql("update be_instituicoes set modo = 'parceira' where slug = 'colegio-monte-aurora'")

ruins = [e for e in erros if 'status of 403' not in e]
print('erros de página:', ruins or 'nenhum')
if falhas or ruins:
    sys.exit(1)
print('tudo certo no inglês e nas escolas')
