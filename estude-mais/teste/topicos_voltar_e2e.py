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



# ---------- tarefas por tópico e botão de voltar ----------
with sync_playwright() as pw:
    nav = pw.chromium.launch()
    ctx, p = contexto(nav, 390)
    entrar(p, 'laura.monteaurora@example.com')

    # a tarefa "Estudar: tópico" abre a aula daquele tópico, e o voltar volta pro Hoje
    sql("update be_plano_tarefas set feita_em = null where usuario_id = (select id from be_usuarios where nome = 'Laura Mendes')")
    p.evaluate("carregarHoje()"); p.wait_for_timeout(1200)
    tarefa = p.evaluate("""Object.values(estado.tarefas).find((t) => t.tipo === 'estudar' && t.topico_id) || null""")
    confere(tarefa is not None, 'a aluna tem tarefa de estudar um tópico')
    p.evaluate(f"fazerTarefa('{tarefa['id']}')")
    p.wait_for_selector('#screen-estudo.active')
    p.wait_for_function("document.querySelector('#estudo-conteudo .aula')", timeout=15000)
    titulo = p.inner_text('#estudo-titulo')
    confere(titulo in tarefa['titulo'] and titulo in p.inner_text('#estudo-conteudo'), f'a tarefa abre a aula do tópico "{titulo}"')
    p.click('#screen-estudo .back-btn'); p.wait_for_timeout(600)
    confere(p.evaluate('telaAtual()') == 'home', 'voltar da aula leva de volta pro Hoje (de onde veio)')

    # dois tópicos da mesma matéria: aulas diferentes
    tops = sql(f"select string_agg(id::text, ',' order by ordem) from be_topicos where materia_id = (select materia_id from be_topicos where id = '{tarefa['topico_id']}')").split(',')
    estudar = [{'topico': t} for t in tops[:2]]
    aulas = []
    for t in estudar:
        p.evaluate(f"abrirEstudoTopico('{t['topico']}')")
        p.wait_for_function("document.querySelector('#estudo-conteudo .aula') && document.getElementById('estudo-titulo').textContent !== 'carregando...'", timeout=15000)
        aulas.append(p.inner_text('#estudo-conteudo'))
    confere(len(aulas) == 2 and aulas[0] != aulas[1], 'tópicos diferentes têm aulas diferentes')

    # quiz de cada tópico tem perguntas próprias, não o quiz geral da matéria
    quizes = []
    for t in estudar[:2]:
        p.evaluate(f"iniciarQuizTopico('{t['topico']}')")
        p.wait_for_selector('#screen-quiz.active'); p.wait_for_timeout(300)
        quizes.append(p.evaluate("estado.quiz.perguntas.map((q) => q.pergunta).join('|')"))
        confere(p.evaluate("estado.quiz.perguntas.every((q) => q.topico_id === estado.quiz.topicoId)"), 'quiz só com perguntas do tópico')
        p.click('#screen-quiz .back-btn'); p.wait_for_timeout(500)
    confere(quizes[0] != quizes[1], 'quizzes de tópicos diferentes têm perguntas diferentes')
    confere(sql(f"select count(*) from be_topico_estudo where topico_id = '{estudar[0]['topico']}'") == '1', 'a aula fica guardada (não gera de novo)')

    # voltar um passo: Matérias > matéria > quiz > voltar = matéria; voltar = Matérias (não o Hoje)
    p.evaluate("verMaterias()"); p.wait_for_timeout(800)
    mid = sql(f"select materia_id from be_topicos where id = '{tarefa['topico_id']}'")
    p.click(f"#lista-materias .group-card[onclick*='{mid}']"); p.wait_for_selector('#screen-materia.active'); p.wait_for_timeout(1200)
    p.evaluate(f"iniciarQuizTopico('{tarefa['topico_id']}')"); p.wait_for_selector('#screen-quiz.active')
    p.click('#screen-quiz .back-btn'); p.wait_for_timeout(900)
    confere(p.evaluate('telaAtual()') == 'materia' and p.evaluate('estado.materiaId') == mid, 'quiz > voltar = a mesma matéria')
    p.click('#screen-materia .back-btn'); p.wait_for_timeout(600)
    confere(p.evaluate('telaAtual()') == 'materias', 'matéria > voltar = lista de Matérias, não o Hoje')

    # Hoje > Turmas > voltar = Hoje; Perfil > Minha escola não existe pra aluna: Hoje > Oportunidades > escola > voltar = Oportunidades
    p.evaluate("verHoje()"); p.wait_for_timeout(600)
    p.evaluate("verOportunidades()"); p.wait_for_timeout(1200)
    p.evaluate("abrirEscolaApp('colegio-monte-aurora')"); p.wait_for_selector('#screen-escola.active'); p.wait_for_timeout(800)
    p.click('#screen-escola .back-btn'); p.wait_for_timeout(600)
    confere(p.evaluate('telaAtual()') == 'oportunidades', 'escola > voltar = Oportunidades')
    p.click('#screen-oportunidades .back-btn'); p.wait_for_timeout(600)
    confere(p.evaluate('telaAtual()') == 'home', 'Oportunidades > voltar = Hoje')
    p.screenshot(path=os.path.join(os.path.dirname(__file__), 'shots', 'topico-aula.png'))
    # print da aula
    p.evaluate(f"abrirEstudoTopico('{estudar[0]['topico']}')"); p.wait_for_function("document.querySelector('#estudo-conteudo .aula')")
    p.screenshot(path=os.path.join(os.path.dirname(__file__), 'shots', 'topico-aula.png'), full_page=True)
    ctx.close(); nav.close()

ruins = [e for e in erros if 'status of 403' not in e]
print('erros de página:', ruins or 'nenhum')
if falhas or ruins:
    sys.exit(1)
print('tudo certo nos tópicos e no voltar')
