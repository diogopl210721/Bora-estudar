"""Teste de ponta a ponta do Estude+ contra o banco local (RLS e funções de verdade, IA simulada)."""
import os, re, sys, json, datetime, subprocess
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
      // pergunta com campo de texto: responde com o que o teste deixou em __respostaDlg
      if (!document.getElementById('dlg-campo-wrap').hidden) document.getElementById('dlg-campo').value = window.__respostaDlg || '';
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


def esperar_dialogo(p, trecho, ms=8000):
    for _ in range(ms // 100):
        if any(trecho in d for d in dialogos):
            return
        p.wait_for_timeout(100)
    raise AssertionError('diálogo não apareceu: ' + trecho)


def esperar_toast(p, trecho):
    p.wait_for_function("(t) => document.getElementById('toast').textContent.includes(t)", arg=trecho, timeout=6000)


def sql(comando):
    subprocess.run(['psql', '-h', '/tmp', '-p', '54329', '-U', 'postgres', '-d', 'estude', '-X', '-q', '-v', 'ON_ERROR_STOP=1', '-c', comando], check=True, capture_output=True)


def cadastrar(p, nome, email, papel='aluno'):
    p.goto(BASE)
    tela(p, 'login')
    p.click('text=criar minha conta')
    tela(p, 'cadastro')
    if papel == 'professor':
        p.click('#role-professor')
    p.fill('#input-nome', nome)
    p.fill('#input-email-cadastro', email)
    p.fill('#input-email-cadastro-confirma', email)
    p.fill('#input-senha-cadastro', 'segredo123')
    p.fill('#input-senha-cadastro-confirma', 'segredo123')
    p.fill('#input-escola', 'Colégio Teste')
    p.fill('#input-cidade', 'Curitiba - PR')
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
    if nome == 'Biologia':
        # foto escolhida vira polaroide com visto
        p.set_input_files('#input-galeria', os.path.join(os.path.dirname(__file__), 'exercicio.png'))
        p.wait_for_selector('#foto-moldura.com-foto')
        shot(p, '02a-upload-foto', 900)
    else:
        p.click('.src-tab[data-fonte=texto]')
        p.fill('#input-texto', TEXTO)
    p.click('#btn-criar-jornada')
    if nome == 'Biologia':
        p.wait_for_selector('#fx-gerando:not([hidden])')
        p.wait_for_timeout(3700)
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
    # senha digitada diferente nas duas vezes
    p.click('text=criar minha conta')
    tela(p, 'cadastro')
    p.fill('#input-nome', 'Ana Souza')
    p.fill('#input-email-cadastro', 'ana@teste.com')
    p.fill('#input-email-cadastro-confirma', 'ana@teste.co')
    p.fill('#input-senha-cadastro', 'segredo123')
    p.fill('#input-senha-cadastro-confirma', 'segredo123')
    p.click('#btn-cadastro')
    esperar_dialogo(p, 'os dois e-mails não são iguais')
    p.fill('#input-email-cadastro-confirma', 'ana@teste.com')
    p.fill('#input-senha-cadastro-confirma', 'segredo124')
    p.click('#btn-cadastro')
    esperar_dialogo(p, 'as duas senhas não são iguais')
    assert p.locator('#input-pergunta-seguranca').count() == 0, 'pergunta de segurança saiu do cadastro'
    assert p.locator('.google-btn').count() == 0, 'não era pra ter login com Google'
    cadastrar(p, 'Ana Souza', 'ana@teste.com')
    p.click('text=não tenho código')
    tela(p, 'home')
    sem_carregando(p, '#home-tarefas')
    shot(p, '02-hoje-vazio')

    # ---------- matéria com IA ----------
    p.click('#home-lado .upload-cta')
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
    # responder sem virar: a IA confere a resposta (voz no celular, digitando aqui)
    p.evaluate("window.__respostaDlg = document.getElementById('flash-verso').textContent")
    p.click('#cards-digitar')
    p.wait_for_selector('#cards-voz-res.certo')
    p.wait_for_selector('#cards-notas:not([hidden]) .grade.g3.sugerida')
    shot(p, '10-card-verso', 900)
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
    p.evaluate('verEnem()')
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
    p.evaluate('verEnem()')
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
    p.evaluate('verLiga()')
    tela(p, 'liga')
    sem_carregando(p, '#liga-conteudo')
    shot(p, '17-liga')
    p.evaluate('verPerfil()')
    tela(p, 'perfil')
    p.wait_for_selector('#perfil-dias .chip')
    p.click('#perfil-dias .chip[data-d="6"]')
    p.click('#btn-salvar-rotina')
    p.wait_for_timeout(400)
    shot(p, '18-perfil')

    # ---------- e-mail que já tem conta ----------
    p.evaluate("localStorage.clear()")
    p.goto(BASE)
    tela(p, 'login')
    p.click('text=criar minha conta')
    tela(p, 'cadastro')
    p.fill('#input-nome', 'Ana de Novo')
    p.fill('#input-email-cadastro', 'ANA@teste.com')
    p.fill('#input-email-cadastro-confirma', 'ana@teste.com')
    p.fill('#input-senha-cadastro', 'outrasenha')
    p.fill('#input-senha-cadastro-confirma', 'outrasenha')
    p.click('#btn-cadastro')
    esperar_dialogo(p, 'Já existe uma conta')
    tela(p, 'login')
    assert p.input_value('#input-email-login') == 'ANA@teste.com'

    # ---------- professor + turma ----------
    p.evaluate("localStorage.clear()")
    cadastrar(p, 'Carlos Lima', 'prof@teste.com', 'professor')
    p.click('text=não tenho código')
    tela(p, 'home')
    p.click('.sidebar-nav [data-s=grupos]') if p.locator('#sidebar:not(.sidebar-hidden)').is_visible() else p.evaluate('verGrupos()')
    tela(p, 'grupos')
    p.click('text=criar grupo')
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
    # na turma do professor a aluna estuda, mas não coloca material nem cria card
    # espera a matéria carregar (a tela abre antes de chegar a resposta)
    p.wait_for_function("() => document.getElementById('mat-titulo').textContent.includes('Química')")
    p.wait_for_selector('#mat-add-row', state='hidden', timeout=5000)
    p.click('#mat-menu [data-tipo=cards]')
    assert p.locator('#mat-cards:has-text("Criar card")').count() == 0
    p.click('#mat-menu [data-tipo=quiz]')
    p.click('#mat-quiz .btn.coral')
    responder_quiz(p, escolher='second')
    tela(p, 'quiz-fim')

    # aluna cria um grupo de amigos; outra aluna entra pelo código e coloca matéria pro grupo
    p.evaluate('verGrupos()')
    tela(p, 'grupos')
    p.wait_for_selector('.group-card')
    assert p.locator('.group-card:has-text("Química 3ºB") button:has-text("matéria nova")').count() == 0
    p.click('text=criar grupo')
    p.fill('#input-nome-grupo', 'Bio com as amigas')
    p.fill('#input-materia-grupo', 'Biologia')
    p.click('#btn-criar-grupo')
    p.wait_for_selector('.group-card:has-text("Bio com as amigas")')
    p.wait_for_function("() => document.getElementById('dlg').hidden")
    assert 'grupo de amigos' in p.inner_text('.group-card:has-text("Bio com as amigas")')
    codigo_amigos = re.search(r'Código: (\w+)', [d for d in dialogos if 'Código' in d][-1]).group(1)
    p.evaluate("localStorage.clear()")
    cadastrar(p, 'Bia Lima', 'bia@teste.com')
    p.fill('#input-codigo', codigo_amigos)
    p.click('#btn-codigo')
    tela(p, 'home')
    p.evaluate('verGrupos()')
    tela(p, 'grupos')
    p.wait_for_selector('.group-card:has-text("Bio com as amigas") button:has-text("matéria nova pro grupo")')
    shot(p, '19b-grupo-de-amigos')
    p.click('.group-card:has-text("Bio com as amigas") button:has-text("matéria nova pro grupo")')
    gerar_materia(p, 'Genética', 15)

    # professor vê o painel
    entrar(p, 'prof@teste.com')
    p.evaluate('verGrupos()')
    tela(p, 'grupos')
    p.click('text=abrir painel')
    tela(p, 'painel')
    p.wait_for_selector('#painel-membros .engage-row')
    shot(p, '20-painel-turma')

    # ---------- biblioteca: o professor publica um resumo a partir da matéria da turma ----------
    p.evaluate('novoResumo()')
    tela(p, 'publicar')
    p.wait_for_function("() => document.querySelectorAll('#pub-origem option').length > 1")
    p.select_option('#pub-origem', label='Química orgânica')
    p.wait_for_function("() => document.getElementById('pub-conteudo').value.length > 80")
    p.select_option('#pub-serie', '3º EM')
    p.click('#pub-cores [data-c=verde]')
    shot(p, '27-publicar')
    p.click('#btn-publicar')
    tela(p, 'resumo', 10000)
    p.wait_for_selector('#res-autor .avatar')
    assert p.locator('#res-cards .mini-card').count() == 5, 'flashcards da matéria não foram junto'
    shot(p, '28-resumo-publicado')
    # a moderação recusa conteúdo com contato pessoal
    p.evaluate('novoResumo()')
    tela(p, 'publicar')
    p.fill('#pub-titulo', 'Resumo de teste')
    p.fill('#pub-materia', 'Química')
    p.fill('#pub-conteudo', 'Me chama no instagram pra trocar resumo. ' + TEXTO)
    p.click('#btn-publicar')
    esperar_dialogo(p, 'não foi publicado')
    # sala da turma: aviso do professor e filtro de contato
    p.evaluate('verComunidade()')
    tela(p, 'comunidade')
    p.wait_for_selector('.sala-item.turma')
    p.click('.sala-item.turma:has-text("Química 3ºB")')
    tela(p, 'sala')
    sem_carregando(p, '#sala-mensagens')
    p.fill('#sala-texto', 'Pessoal, amanhã tem revisão de orgânica. Tragam as dúvidas!')
    p.click('#sala-enviar')
    p.wait_for_selector('#sala-mensagens .bolha-linha.minha')
    p.fill('#sala-texto', 'me chama no zap 41 99999-8888')
    p.click('#sala-enviar')
    esperar_toast(p, 'pra proteger')
    assert p.locator('#sala-mensagens .bolha-linha.minha').count() == 1

    # ---------- aluna: biblioteca, tutor e comunidade ----------
    entrar(p, 'ana@teste.com')
    sem_carregando(p, '#home-tarefas')
    p.wait_for_selector('#home-biblio .capa-resumo')
    p.wait_for_function("() => !document.getElementById('nav-nao-lidas').hidden")
    p.click('.navbar [data-s=biblioteca]')
    tela(p, 'biblioteca')
    p.wait_for_selector('#bib-lista .capa-resumo')
    shot(p, '29-biblioteca')
    p.fill('#bib-busca', 'orgânica')
    p.wait_for_timeout(900)
    assert p.locator('#bib-lista .capa-resumo').count() == 1, 'busca não achou o resumo'
    p.fill('#bib-busca', 'fotossíntese')
    p.wait_for_selector('#bib-lista .empty')
    p.fill('#bib-busca', '')
    p.wait_for_selector('#bib-lista .capa-resumo')
    p.locator('#bib-lista .capa-resumo').first.click()
    tela(p, 'resumo')
    p.wait_for_selector('#res-seguir')
    p.click('#res-curtir')
    p.wait_for_function("() => document.getElementById('res-curtidas').textContent === '1'")
    p.click('#res-salvar')
    esperar_toast(p, 'Salvo')
    p.click('#res-seguir')
    p.wait_for_function("() => document.getElementById('res-seguir').textContent === 'Seguindo'")
    p.locator('#res-cards .mini-card').first.click()
    shot(p, '30-resumo')
    p.click('#res-autor .quem')
    tela(p, 'autor')
    p.wait_for_selector('.perfil-publico')
    assert 'Carlos L.' in p.inner_text('.perfil-publico h1'), 'nome público deveria ser abreviado'
    shot(p, '31-perfil-publico')
    p.locator('#autor-conteudo .capa-resumo').first.click()
    tela(p, 'resumo')
    p.click('#screen-resumo .back-btn')
    tela(p, 'autor')
    p.click('#screen-autor .back-btn')
    tela(p, 'resumo')
    p.click('#screen-resumo .back-btn')
    tela(p, 'biblioteca')
    p.click('#bib-ordem [data-o=salvos]')
    p.wait_for_selector('#bib-lista .capa-resumo')
    p.click('#bib-ordem [data-o=seguindo]')
    p.wait_for_selector('#bib-lista .capa-resumo')
    # aluna publica a partir da própria matéria
    p.evaluate('novoResumo()')
    tela(p, 'publicar')
    p.wait_for_function("() => document.querySelectorAll('#pub-origem option').length > 1")
    p.select_option('#pub-origem', label='Biologia')
    p.wait_for_function("() => document.getElementById('pub-conteudo').value.length > 80")
    p.click('#btn-publicar')
    tela(p, 'resumo', 10000)
    p.wait_for_selector('#res-apagar:not([hidden])')
    p.click('#screen-resumo .back-btn')
    tela(p, 'biblioteca')
    p.click('#bib-ordem [data-o=meus]')
    p.wait_for_function("() => document.querySelectorAll('#bib-lista .capa-resumo').length === 1")

    # tutor: pergunta escrita, continuação e foto do exercício
    p.click('.navbar [data-s=tutor]')
    tela(p, 'tutor')
    sem_carregando(p, '#tutor-lista')
    p.click('#tutor-materias .chip:has-text("Biologia")')
    shot(p, '32-tutor')
    p.fill('#tutor-pergunta-rapida', 'Qual a diferença entre mitose e meiose?')
    p.click('#screen-tutor .ou button')
    tela(p, 'tutor-chat')
    p.wait_for_selector('#tchat-mensagens .bolha .ferramentas')
    p.fill('#tchat-texto', 'E qual das duas forma os gametas?')
    p.click('#tchat-enviar')
    p.wait_for_function("() => document.querySelectorAll('#tchat-mensagens .bolha .ferramentas').length === 2")
    shot(p, '33-tutor-chat')
    p.click('#screen-tutor-chat .back-btn')
    tela(p, 'tutor')
    p.set_input_files('#tutor-foto-input', os.path.join(os.path.dirname(__file__), 'exercicio.png'))
    tela(p, 'tutor-chat')
    p.wait_for_selector('#tchat-mensagens img.foto-mini')
    p.wait_for_function("() => document.getElementById('tchat-mensagens').innerText.includes('x = 4')")
    shot(p, '34-tutor-foto')
    p.click('#screen-tutor-chat .back-btn')
    tela(p, 'tutor')
    p.wait_for_function("() => document.querySelectorAll('#tutor-lista .conversa-item').length === 2")
    p.locator('#tutor-lista .conversa-item').last.click()
    tela(p, 'tutor-chat')
    p.wait_for_function("() => document.querySelectorAll('#tchat-mensagens .bolha .ferramentas').length === 2")

    # comunidade: sala da turma com o aviso do professor
    p.evaluate('verComunidade()')
    tela(p, 'comunidade')
    p.wait_for_selector('.sala-item.turma:has-text("Química 3ºB") .nao-lidas')
    shot(p, '35-comunidade')
    p.click('.sala-item.turma:has-text("Química 3ºB")')
    tela(p, 'sala')
    p.wait_for_selector('#sala-mensagens .bolha-linha:not(.minha)')
    assert 'Carlos L.' in p.inner_text('#sala-mensagens')
    p.fill('#sala-texto', 'Professor, vai cair nomenclatura?')
    p.click('#sala-enviar')
    p.wait_for_selector('#sala-mensagens .bolha-linha.minha')
    shot(p, '36-sala')
    p.locator('#sala-mensagens .bolha-linha:not(.minha) .bolha').first.click()
    p.wait_for_selector('#menu-msg')
    p.wait_for_timeout(300)
    p.screenshot(path=os.path.join(SHOTS, '37-sala-menu.png'))
    p.click('#menu-msg button:has-text("Denunciar")')
    esperar_toast(p, 'Obrigado')
    p.click('#screen-sala .back-btn')
    tela(p, 'comunidade')
    p.wait_for_function("() => ![...document.querySelectorAll('.sala-item.turma')].some((e) => e.textContent.includes('Química 3ºB') && e.querySelector('.nao-lidas'))")
    p.locator('.sala-item:not(.turma)').first.click()
    tela(p, 'sala')
    p.wait_for_selector('#sala-mensagens .empty')
    p.click('#screen-sala .back-btn')
    tela(p, 'comunidade')

    # ---------- conta do criador (master) ----------
    p.evaluate("localStorage.clear()")
    cadastrar(p, 'Diogo Soares', 'dono@teste.com')
    p.click('text=não tenho código')
    tela(p, 'home')
    assert p.inner_text('#home-energia') != '∞', 'conta comum não tem energia infinita'
    sql("""insert into be_criadores (usuario_id) select u.id from be_usuarios u join auth.users a on a.id = u.auth_user_id where a.email = 'dono@teste.com'""")
    # 3 denúncias escondem o resumo da Ana; o uso de IA e do tutor do criador já estourou o limite do dia
    sql("""insert into be_denuncias (usuario_id, alvo_tipo, alvo_id, motivo)
           select u.id, 'resumo', r.id, v.m from be_resumos r join auth.users aa on aa.email = 'ana@teste.com' join be_usuarios ua on ua.auth_user_id = aa.id and r.autor_id = ua.id,
             (values ('prof@teste.com', 'parece cópia'), ('bia@teste.com', null), ('dono@teste.com', null)) v(e, m)
             join auth.users a on a.email = v.e join be_usuarios u on u.auth_user_id = a.id""")
    sql("""insert into be_uso_tutor (usuario_id, data, quantidade) select u.id, current_date, 60 from be_usuarios u join auth.users a on a.id = u.auth_user_id where a.email = 'dono@teste.com'
           on conflict (usuario_id, data) do update set quantidade = 60;
           insert into be_uso_ia (usuario_id, data, quantidade) select u.id, current_date, 7 from be_usuarios u join auth.users a on a.id = u.auth_user_id where a.email = 'dono@teste.com'
           on conflict (usuario_id, data) do update set quantidade = 7""")
    entrar(p, 'dono@teste.com')
    sem_carregando(p, '#home-tarefas')
    p.wait_for_function("() => document.getElementById('home-energia').textContent === '∞'")
    r = p.evaluate("(t) => chamarFuncao('estude-corrigir-redacao', { tema: 'Tema livre', texto: t })", REDACAO)
    assert r['ok'] and r['energia_restante'] is None, 'criador deveria corrigir redação sem limite'
    r = p.evaluate("() => chamarFuncao('estude-tutor', { texto: 'Quanto é 2 + 2?' })")
    assert r['ok'] and r['restantes'] is None, 'criador deveria usar o tutor sem limite'
    p.evaluate('verTutor()')
    tela(p, 'tutor')
    p.wait_for_function("() => document.getElementById('tutor-restantes').textContent.includes('sem limite')")
    p.evaluate('verPerfil()')
    tela(p, 'perfil')
    p.wait_for_selector('#perfil-criador:not([hidden])')
    assert 'criador do Estude+' in p.inner_text('#perfil-meta')
    shot(p, '38a-criador-perfil')
    p.click('#perfil-criador')
    tela(p, 'criador')
    sem_carregando(p, '#criador-numeros')
    p.wait_for_selector('#criador-fila .fila-item')
    abas = p.inner_text('#criador-abas')
    assert 'resumos (1)' in abas and 'mensagens (1)' in abas, 'fila deveria ter 1 resumo e 1 mensagem: ' + abas
    shot(p, '38-criador-painel')
    # resumo escondido pelas denúncias: abre, confere e libera
    p.click('#criador-fila .fila-acoes button:has-text("abrir")')
    tela(p, 'resumo')
    p.wait_for_selector('#res-mod:not([hidden]) .liberar')
    assert p.locator('#res-denunciar').is_hidden(), 'criador não precisa denunciar'
    assert '3 denúncias' in p.inner_text('#res-mod')
    shot(p, '39-criador-resumo')
    p.click('#res-mod .liberar')
    esperar_toast(p, 'Resumo no ar')
    p.wait_for_function("() => !document.querySelector('#res-aviso .aviso-moderacao') && !document.querySelector('#res-mod .liberar')")
    p.click('#screen-resumo .back-btn')
    tela(p, 'criador')
    p.wait_for_function("() => document.getElementById('criador-abas').innerText.includes('resumos (0)')")
    # mensagem denunciada: silencia o autor por 7 dias e esconde a mensagem
    p.click('#criador-abas [data-a=mensagens]')
    p.wait_for_selector('#criador-fila .fila-item')
    p.click('#criador-fila .fila-acoes button:has-text("silenciar")')
    esperar_dialogo(p, 'Silenciar Carlos L.')
    p.wait_for_selector('#criador-silenciados .hist-row')
    p.wait_for_selector('#criador-fila .fila-item .ocultar')
    p.click('#criador-fila .fila-item .ocultar')
    esperar_toast(p, 'Mensagem escondida')
    p.wait_for_selector('#criador-fila .empty')
    shot(p, '40-criador-moderado')
    # aviso numa sala aberta, com link (só a conta do criador pode)
    p.evaluate('verComunidade()')
    tela(p, 'comunidade')
    p.locator('.sala-item:not(.turma)').first.click()
    tela(p, 'sala')
    sem_carregando(p, '#sala-mensagens')
    p.fill('#sala-texto', 'Bem-vindos ao Estude+! Novidades em ddsinovacao.com.br/estudemais')
    p.click('#sala-enviar')
    p.wait_for_selector('#sala-mensagens .bolha-linha.minha')
    p.fill('#sala-texto', 'Qualquer dúvida, chama aqui.')
    p.click('#sala-enviar')
    p.wait_for_function("() => document.querySelectorAll('#sala-mensagens .bolha-linha.minha').length === 2")
    # turma criada pela conta do criador
    p.evaluate('verGrupos()')
    tela(p, 'grupos')
    p.click('text=criar grupo')
    p.wait_for_selector('#criar-tipo:not([hidden])')
    p.fill('#input-nome-grupo', 'Monitoria Estude+')
    p.fill('#input-materia-grupo', 'Matemática')
    p.click('#btn-criar-grupo')
    esperar_dialogo(p, 'Grupo criado')
    p.wait_for_selector('.group-card:has-text("Monitoria Estude+")')
    assert ', turma,' in p.inner_text('.group-card:has-text("Monitoria Estude+")'), 'deveria ser turma'
    # senha provisória pra quem esqueceu (conta nova não tem pergunta de segurança)
    p.evaluate('verCriador()')
    tela(p, 'criador')
    sem_carregando(p, '#criador-numeros')
    p.fill('#criador-busca', 'ana@')
    p.wait_for_selector('#criador-contas .fila-item:has-text("Ana Souza")')
    assert 'ana@teste.com' in p.inner_text('#criador-contas')
    shot(p, '40b-criador-contas')
    p.click('#criador-contas .fila-item:has-text("Ana Souza") button:has-text("senha provisória")')
    esperar_dialogo(p, 'Senha provisória de Ana')
    provisoria = re.search(r'\n\n([A-Z0-9]{4}-[A-Z0-9]{4})\n\n', [d for d in dialogos if 'Senha provisória de' in d][-1]).group(1)
    p.fill('#criador-busca', 'dono@')
    p.wait_for_selector('#criador-contas .fila-item:has-text("Diogo Soares")')
    assert p.locator('#criador-contas button:has-text("senha provisória")').count() == 0, 'a conta do criador não troca a própria senha pelo painel'
    # quem foi silenciado não manda mensagem
    entrar(p, 'prof@teste.com')
    p.evaluate('verComunidade()')
    tela(p, 'comunidade')
    p.click('.sala-item.turma:has-text("Química 3ºB")')
    tela(p, 'sala')
    sem_carregando(p, '#sala-mensagens')
    p.fill('#sala-texto', 'Alguém aí?')
    p.click('#sala-enviar')
    esperar_toast(p, 'sem mandar mensagens')
    # aluna: a senha antiga parou de funcionar; entra com a provisória e troca em Perfil
    p.evaluate("localStorage.clear()")
    p.goto(BASE)
    tela(p, 'login')
    p.fill('#input-email-login', 'ana@teste.com')
    p.fill('#input-senha-login', 'segredo123')
    p.click('#btn-login')
    esperar_dialogo(p, 'e-mail ou senha errados')
    p.fill('#input-senha-login', provisoria)
    p.click('#btn-login')
    tela(p, 'home')
    p.evaluate('verPerfil()')
    tela(p, 'perfil')
    p.click('#screen-perfil .ghost-btn:has-text("trocar senha")')
    p.fill('#input-senha-atual', provisoria)
    p.fill('#input-senha-nova', 'segredo123')
    p.fill('#input-senha-nova-confirma', 'segredo123')
    p.click('#btn-trocar-senha')
    esperar_toast(p, 'Senha trocada')
    # aluna vê o aviso com o selo da equipe e não vê o menu de moderação
    entrar(p, 'ana@teste.com')
    p.evaluate('verComunidade()')
    tela(p, 'comunidade')
    p.locator('.sala-item:not(.turma)').first.click()
    tela(p, 'sala')
    p.wait_for_selector('#sala-mensagens .selo-equipe')
    shot(p, '41-sala-selo-equipe')
    p.locator('#sala-mensagens .bolha-linha:not(.minha) .bolha').first.click()
    p.wait_for_selector('#menu-msg')
    assert p.locator('#menu-msg button:has-text("Silenciar")').count() == 0, 'aluna não pode silenciar'
    p.evaluate('fecharMenuMensagem()')

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
    p.evaluate('verBiblioteca()')
    p.wait_for_selector('#bib-lista .capa-resumo')
    p.wait_for_timeout(600)
    p.screenshot(path=os.path.join(SHOTS, '21c-desktop-biblioteca.png'))
    p.evaluate('verComunidade()')
    p.wait_for_selector('.sala-item.turma')
    p.click('.sala-item.turma:has-text("Química 3ºB")')
    p.wait_for_selector('#sala-mensagens .bolha-linha')
    p.wait_for_timeout(500)
    p.screenshot(path=os.path.join(SHOTS, '21d-desktop-sala.png'))

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
    p.evaluate('verBiblioteca()')
    p.wait_for_selector('#bib-lista .capa-resumo')
    shot(p, '24b-escuro-biblioteca')
    p.evaluate('verTutor()')
    p.wait_for_selector('#tutor-lista .conversa-item')
    p.locator('#tutor-lista .conversa-item').first.click()
    p.wait_for_selector('#tchat-mensagens .ferramentas')
    shot(p, '24c-escuro-tutor')
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
# 409 é o aviso esperado de e-mail que já tem conta
reais = [e for e in erros if 'favicon' not in e and 'net::ERR_FAILED' not in e and '409 (Conflict)' not in e]
print('erros:', json.dumps(reais, ensure_ascii=False, indent=1))
sys.exit(1 if reais else 0)
