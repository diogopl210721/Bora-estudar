"""Teste de ponta a ponta do Estude+ contra o banco local (RLS e funções de verdade, IA simulada)."""
import os, re, sys, json, datetime
from playwright.sync_api import sync_playwright

BASE = 'http://localhost:8787'
SHOTS = os.path.join(os.path.dirname(__file__), 'shots')
os.makedirs(SHOTS, exist_ok=True)
MOCK = open(os.path.join(os.path.dirname(__file__), 'mock-supabase.js'), encoding='utf-8').read()
PNG = bytes.fromhex('89504e470d0a1a0a0000000d4948445200000001000000010806000000'
                    '1f15c4890000000d49444154789c63f8cfc0f01f0005000201ff0a3a5b5f0000000049454e44ae426082')
HOJE = datetime.date.today()
erros, dialogos = [], []
PAG = []

TEXTO = ('A célula é a unidade básica da vida. Na mitose, uma célula se divide em duas células-filhas idênticas, '
         'passando por prófase, metáfase, anáfase e telófase. Na meiose, formam-se quatro células com metade dos cromossomos.')
REDACAO = ('A desinformação nas redes sociais é um desafio crescente no Brasil. ' * 6 + '\n\n') * 3


AUTO = '''
window.addEventListener('DOMContentLoaded', () => {
  new MutationObserver(() => {
    const d = document.getElementById('dlg');
    if (d && !d.hidden && !d.dataset.lido) {
      d.dataset.lido = '1';
      window.__registrarDialogo(document.getElementById('dlg-texto').textContent);
      setTimeout(() => { document.getElementById('dlg-ok').click(); delete d.dataset.lido; }, 150);
    }
    const n = document.getElementById('fx-nivel');
    if (n && !n.hidden && !n.dataset.lido && !window.__manterNivel) {
      n.dataset.lido = '1';
      window.__registrarDialogo('nível ' + document.getElementById('nivel-n').textContent);
      setTimeout(() => { Fx.fecharNivel(); delete n.dataset.lido; }, 700);
    }
  }).observe(document.body, { subtree: true, attributes: true, attributeFilter: ['hidden'] });
});
'''


def preparar(ctx):
    ctx.expose_binding('__registrarDialogo', lambda fonte, msg: dialogos.append(msg))
    ctx.add_init_script(AUTO)
    ctx.route(re.compile(r'https://cdn\.jsdelivr\.net/npm/@supabase.*'), lambda r: r.fulfill(status=200, content_type='text/javascript', body=MOCK))
    ctx.route(re.compile(r'https://fonts\.(googleapis|gstatic)\.com/.*'), lambda r: r.abort())
    ctx.route(re.compile(r'https://(enem\.dev|raw\.githubusercontent\.com)/.*'), lambda r: r.fulfill(status=200, content_type='image/png', body=PNG))

    def para_local(route):
        req = route.request
        caminho = re.sub(r'^https://[^/]+', '', req.url)
        resp = route.fetch(url=BASE + caminho)
        route.fulfill(response=resp)
    ctx.route(re.compile(r'https://arffptuclrrzuzdrcmuc\.supabase\.co/.*'), para_local)


def nova_pagina(ctx):
    p = ctx.new_page()
    p.on('console', lambda m: erros.append(f'console: {m.text}') if m.type == 'error' else None)
    p.on('pageerror', lambda e: erros.append(f'pageerror: {e}'))
    def dlg(d):
        dialogos.append(d.message)
        d.accept()
    p.on('dialog', dlg)
    return p


def shot(p, nome, espera=1100):
    p.wait_for_timeout(espera)
    p.evaluate("""() => { const s = document.createElement('style'); s.id='shotcss';
      s.textContent = '.phone{height:auto!important;overflow:visible!important} .screen.active{position:relative!important;overflow:visible!important} .sheet{min-height:0!important} .toast,.xp-voa,#fx-canvas,.fx-visto{display:none!important}';
      document.head.appendChild(s); }""")
    p.screenshot(path=os.path.join(SHOTS, nome + '.png'), full_page=True)
    p.evaluate("() => document.getElementById('shotcss').remove()")


def tela(p, nome, timeout=8000):
    p.wait_for_selector(f'#screen-{nome}.active', timeout=timeout)


def sem_carregando(p, sel):
    p.wait_for_function(f"() => !document.querySelector('{sel} .loading')", timeout=8000)


def cadastrar(p, nome, email, papel='aluno'):
    p.goto(BASE)
    tela(p, 'login')
    p.click('text=criar minha conta')
    tela(p, 'cadastro')
    if papel == 'professor':
        p.click('#role-professor')
    p.fill('#input-nome', nome)
    p.fill('#input-email-cadastro', email)
    p.fill('#input-senha-cadastro', 'segredo123')
    p.fill('#input-senha-cadastro-confirma', 'segredo123')
    p.fill('#input-escola', 'Colégio Teste')
    p.fill('#input-cidade', 'Curitiba - PR')
    p.fill('#input-pergunta-seguranca', 'pet')
    p.fill('#input-resposta-seguranca', 'rex')
    p.click('#btn-cadastro')
    tela(p, 'codigo')


def entrar(p, email):
    p.evaluate("localStorage.clear()")
    p.goto(BASE)
    tela(p, 'login')
    p.fill('#input-email-login', email)
    p.fill('#input-senha-login', 'segredo123')
    p.click('#btn-login')
    tela(p, 'home')


def gerar_materia(p, nome, dias):
    tela(p, 'upload')
    p.fill('#input-materia', nome)
    p.fill('#input-data-prova', (HOJE + datetime.timedelta(days=dias)).isoformat())
    p.click('.src-tab[data-fonte=texto]')
    p.fill('#input-texto', TEXTO)
    p.click('#btn-criar-jornada')
    if nome == 'Biologia':
        p.wait_for_selector('#fx-gerando:not([hidden])')
        p.wait_for_timeout(1300)
        p.screenshot(path=os.path.join(SHOTS, '02b-gerando.png'))
    tela(p, 'pronto', 15000)


def responder_quiz(p, quantas=None, escolher='first', foto=None):
    tela(p, 'quiz')
    n = 0
    while True:
        p.wait_for_selector('#quiz-opcoes .option')
        opcoes = p.locator('#quiz-opcoes .option')
        (opcoes.first if escolher == 'first' else opcoes.nth(1)).click()
        p.wait_for_selector('#quiz-feedback:not([hidden])')
        n += 1
        if foto and n <= 2:
            p.wait_for_timeout(900)
            p.screenshot(path=os.path.join(SHOTS, f'{foto}-{n}.png'))
        texto = p.inner_text('#quiz-next-btn')
        p.click('#quiz-next-btn')
        if 'resultado' in texto.lower():
            break
        if quantas and n >= quantas:
            break
    return n


def principal(pw):
    nav = pw.chromium.launch()
    ctx = nav.new_context(viewport={'width': 390, 'height': 844}, device_scale_factor=2, locale='pt-BR', timezone_id='America/Sao_Paulo',
                          reduced_motion=os.environ.get('MOVIMENTO', 'no-preference'))
    preparar(ctx)
    p = nova_pagina(ctx)
    PAG.append(p)

    # ---------- conta nova ----------
    p.goto(BASE)
    tela(p, 'login')
    shot(p, '01-login')
    cadastrar(p, 'Ana Souza', 'ana@teste.com')
    p.click('text=não tenho código')
    tela(p, 'home')
    sem_carregando(p, '#home-tarefas')
    shot(p, '02-hoje-vazio')

    # ---------- matéria com IA ----------
    p.click('.upload-cta')
    gerar_materia(p, 'Biologia', 12)
    shot(p, '03-pronto')
    p.wait_for_function("() => document.getElementById('pronto-cards').textContent === '5'", timeout=4000)
    p.click('text=Começar pelo quiz')
    responder_quiz(p, foto='03b-quiz-resposta')
    tela(p, 'quiz-fim')
    shot(p, '04-quiz-fim')
    p.click('text=Voltar pra matéria')
    tela(p, 'materia')
    p.wait_for_selector('#mat-plano .task')
    shot(p, '05-materia-plano')
    p.locator('#mat-plano .icon-btn.edit').first.click()
    shot(p, '05b-materia-plano-editando')
    p.locator('#mat-plano .icon-btn.edit').first.click()
    p.click('#mat-menu [data-tipo=mapa]')
    shot(p, '06-materia-mapa')
    p.click('#mat-menu [data-tipo=cards]')
    shot(p, '07-materia-cards')

    # mover uma tarefa futura de dia e adicionar uma minha
    p.click('#mat-menu [data-tipo=plano]')
    p.click('#btn-plano-resto')
    edits = p.locator('#mat-plano .icon-btn.edit')
    assert edits.count() > 0
    edits.nth(edits.count() - 1).click()
    datas = p.locator('#mat-plano .task.editando .task-tools input[type=date]')
    datas.first.fill((HOJE + datetime.timedelta(days=9)).isoformat())
    datas.first.dispatch_event('change')
    p.wait_for_timeout(600)
    p.click('text=+ tarefa minha')
    p.fill('#nt-titulo', 'Refazer exercícios do livro')
    p.click('text=Adicionar ao plano')
    p.wait_for_selector('text=Refazer exercícios do livro')

    # ---------- Hoje com plano ----------
    p.click('.navbar [data-s=home]')
    tela(p, 'home')
    sem_carregando(p, '#home-tarefas')
    p.wait_for_selector('#home-tarefas .task')
    shot(p, '08-hoje-plano')
    # tarefa "estudar" → resumo → marcar
    p.locator('#home-tarefas .task').first.locator('.go-small').click()
    tela(p, 'materia')
    p.click('text=Estudei, marcar tarefa como feita')
    p.wait_for_timeout(700)
    # flashcards
    p.click('.navbar [data-s=home]')
    tela(p, 'home')
    p.wait_for_function("() => Number(document.getElementById('home-cards-n').textContent) > 0")
    p.click('#home-revisao')
    tela(p, 'cards')
    shot(p, '09-card-frente', 600)
    p.click('#cards-virar')
    p.wait_for_selector('#cards-notas:not([hidden])')
    shot(p, '10-card-verso', 800)
    pronto_ou_proximo = "() => document.querySelector('#screen-cards-fim.active') || !document.getElementById('cards-virar').hidden"
    p.click('.grade.g1')
    p.wait_for_function(pronto_ou_proximo)
    for _ in range(12):
        if p.locator('#screen-cards-fim.active').count():
            break
        p.click('#cards-virar')
        p.click('.grade.g3')
        p.wait_for_function(pronto_ou_proximo)
    tela(p, 'cards-fim')
    shot(p, '11-cards-fim')

    # ---------- ENEM ----------
    p.click('.navbar [data-s=enem]')
    tela(p, 'enem')
    shot(p, '12-enem')
    p.click('.area-btn[data-area=matematica]')
    p.click('#btn-iniciar-simulado')
    tela(p, 'simulado')
    p.wait_for_selector('#sim-opcoes .option')
    p.locator('#sim-opcoes .option').nth(2).click()
    shot(p, '13-simulado', 700)
    for i in range(10):
        p.locator('#sim-opcoes .option').nth(i % 5).click()
        if i < 9:
            p.click('#sim-proxima')
    p.click('#btn-entregar')
    tela(p, 'simulado-fim')
    shot(p, '14-simulado-resultado')
    p.locator('#simfim-grid .qdot').first.click()
    tela(p, 'simulado')
    shot(p, '15-simulado-revisao')

    # redação
    p.click('.navbar [data-s=enem]')
    tela(p, 'enem')
    p.click('text=Corrigir uma redação')
    tela(p, 'redacao')
    p.fill('#redacao-texto', REDACAO)
    p.dispatch_event('#redacao-texto', 'input')
    p.click('#btn-corrigir')
    p.wait_for_selector('#redacao-resultado:not([hidden]) .score-big')
    p.wait_for_function("() => document.querySelector('#redacao-resultado .score-big').textContent.trim() === '720'", timeout=5000)
    shot(p, '16-redacao', 1000)

    # liga e perfil
    p.click('.navbar [data-s=liga]')
    tela(p, 'liga')
    sem_carregando(p, '#liga-conteudo')
    shot(p, '17-liga')
    p.click('.navbar [data-s=perfil]')
    tela(p, 'perfil')
    p.wait_for_selector('#perfil-dias .chip')
    p.click('#perfil-dias .chip[data-d="6"]')
    p.click('#btn-salvar-rotina')
    p.wait_for_timeout(400)
    shot(p, '18-perfil')

    # ---------- professor + turma ----------
    p.evaluate("localStorage.clear()")
    cadastrar(p, 'Carlos Lima', 'prof@teste.com', 'professor')
    p.click('text=não tenho código')
    tela(p, 'home')
    p.click('.sidebar-nav [data-s=grupos]') if p.locator('#sidebar:not(.sidebar-hidden)').is_visible() else p.evaluate('verGrupos()')
    tela(p, 'grupos')
    p.click('text=+ criar grupo')
    p.fill('#input-nome-grupo', 'Química 3ºB')
    p.fill('#input-materia-grupo', 'Química')
    p.click('#btn-criar-grupo')
    p.wait_for_selector('.group-card')
    p.wait_for_function("() => document.getElementById('dlg').hidden")
    codigo = re.search(r'Código: (\w+)', [d for d in dialogos if 'Código' in d][-1]).group(1)
    p.click('text=abrir painel')
    tela(p, 'painel')
    p.click('#screen-painel .link-btn')
    gerar_materia(p, 'Química orgânica', 10)

    # aluna entra na turma e estuda
    entrar(p, 'ana@teste.com')
    p.evaluate('verGrupos()')
    tela(p, 'grupos')
    p.click('text=entrar com código')
    p.fill('#input-codigo-grupo', codigo)
    p.click('#btn-entrar-grupo')
    p.wait_for_selector('text=Química 3ºB')
    p.click('.navbar [data-s=home]')
    tela(p, 'home')
    p.wait_for_function("() => document.getElementById('home-tarefas').innerText.includes('Química')")
    shot(p, '19-hoje-com-turma')
    p.click('.exam-chip:has-text("Química")')
    tela(p, 'materia')
    p.click('#mat-menu [data-tipo=quiz]')
    p.click('#mat-quiz .btn.coral')
    responder_quiz(p, escolher='second')
    tela(p, 'quiz-fim')

    # professor vê o painel
    entrar(p, 'prof@teste.com')
    p.evaluate('verGrupos()')
    tela(p, 'grupos')
    p.click('text=abrir painel')
    tela(p, 'painel')
    p.wait_for_selector('#painel-membros .engage-row')
    shot(p, '20-painel-turma')

    # desktop
    entrar(p, 'ana@teste.com')
    p.set_viewport_size({'width': 1366, 'height': 900})
    p.evaluate('verHoje()')
    sem_carregando(p, '#home-tarefas')
    p.wait_for_timeout(500)
    p.screenshot(path=os.path.join(SHOTS, '21-desktop-hoje.png'))
    p.evaluate('verEnem()')
    p.wait_for_timeout(900)
    p.screenshot(path=os.path.join(SHOTS, '21b-desktop-enem.png'))

    # modo lousa (escuro)
    p.set_viewport_size({'width': 390, 'height': 844})
    p.evaluate("escolherTema('lousa')")
    p.evaluate('verHoje()')
    sem_carregando(p, '#home-tarefas')
    shot(p, '22-lousa-hoje')
    p.click('.exam-chip:has-text("Química")')
    tela(p, 'materia')
    p.click('#mat-menu [data-tipo=mapa]')
    shot(p, '23-lousa-mapa')
    p.click('#mat-menu [data-tipo=quiz]')
    p.click('#mat-quiz .btn.coral')
    tela(p, 'quiz')
    p.locator('#quiz-opcoes .option').first.click()
    p.wait_for_selector('#quiz-feedback:not([hidden])')
    p.wait_for_timeout(900)
    p.screenshot(path=os.path.join(SHOTS, '24-lousa-quiz.png'))
    p.evaluate("escolherTema('caderno')")

    # efeitos em destaque
    p.evaluate("window.__manterNivel = true; Fx.nivel(4)")
    p.wait_for_timeout(1300)
    p.screenshot(path=os.path.join(SHOTS, '25-nivel.png'))
    p.evaluate("Fx.fecharNivel(); window.__manterNivel = false; verHoje()")
    sem_carregando(p, '#home-tarefas')
    p.wait_for_timeout(800)
    p.evaluate("Fx.visto('dia completo')")
    p.wait_for_timeout(700)
    p.screenshot(path=os.path.join(SHOTS, '26-visto.png'))
    nav.close()


with sync_playwright() as pw:
    try:
        principal(pw)
    except Exception as e:
        import traceback
        linhas = [l for l in traceback.format_exc().splitlines() if 'e2e.py' in l]
        print('FALHOU:', str(e).split('Call log')[0][:400], linhas[-2:])
        if PAG:
            PAG[-1].screenshot(path=os.path.join(SHOTS, 'falha.png'))
            print('tela ativa:', PAG[-1].evaluate("document.querySelector('.screen.active').id"))
        erros.append('falha do teste: ' + str(e)[:200])

print('diálogos:', json.dumps(dialogos, ensure_ascii=False, indent=1))
reais = [e for e in erros if 'favicon' not in e and 'net::ERR_FAILED' not in e]
print('erros:', json.dumps(reais, ensure_ascii=False, indent=1))
sys.exit(1 if reais else 0)
