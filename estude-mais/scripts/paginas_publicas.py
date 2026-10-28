"""Gera as páginas públicas do EstudeUp (Para escolas, oportunidades, escola, privacidade) com o mesmo topo e rodapé.
Uso: python3 scripts/paginas_publicas.py  (escreve em site/)"""
import os
SITE = os.path.join(os.path.dirname(__file__), '..', 'site')
V = '12'

def cabeca(titulo, descricao):
    return f'''<!DOCTYPE html>
<html lang="pt-BR">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width, initial-scale=1.0, viewport-fit=cover">
<title>{titulo}</title>
<meta name="description" content="{descricao}">
<meta property="og:title" content="{titulo}">
<meta property="og:description" content="{descricao}">
<meta name="theme-color" content="#F4F6FB" media="(prefers-color-scheme: light)">
<meta name="theme-color" content="#0E1230" media="(prefers-color-scheme: dark)">
<link rel="icon" type="image/png" href="favicon.png">
<link rel="apple-touch-icon" href="apple-touch-icon.png">
<link rel="preload" href="fontes/unbounded.woff2" as="font" type="font/woff2" crossorigin>
<link rel="preload" href="fontes/atkinson-next.woff2" as="font" type="font/woff2" crossorigin>
<script>
  try {{
    var t = localStorage.getItem('estude-tema');
    if (t === 'caderno') t = 'claro'; if (t === 'lousa') t = 'escuro';
    if (t === 'claro' || t === 'escuro') document.documentElement.dataset.tema = t;
  }} catch (e) {{}}
</script>
<link rel="stylesheet" href="styles.css?v={V}">
<script src="https://cdn.jsdelivr.net/npm/@supabase/supabase-js@2"></script>
</head>'''

def topo(ativo):
    def a(href, txt, chave, extra=''):
        return f'<a href="{href}" class="{"ativo " if chave == ativo else ""}{extra}">{txt}</a>'
    return f'''<header class="pub-topo">
  <a class="brand" href="escolas.html" aria-label="EstudeUp para escolas"><img class="marca-s" src="marca/simbolo-256.webp" alt="" width="40" height="34">Estude<span class="up">Up</span></a>
  <nav aria-label="páginas">
    {a("oportunidades.html", "Oportunidades", "mural")}
    {a("escolas.html", "Para escolas", "escolas", "so-largo")}
    {a("./", "Entrar no app", "app")}
  </nav>
</header>'''

RODAPE = '''<footer class="pub-rodape">
  <p><b>EstudeUp</b> · Seu próximo nível começa aqui.</p>
  <p><a href="oportunidades.html">Oportunidades</a> · <a href="escolas.html">Para escolas</a> · <a href="privacidade.html">Aviso de privacidade</a> · <a href="./">Entrar no app</a></p>
  <p>© 2026 Diogo Soares · DDS Inovação</p>
</footer>'''

CAMADAS = '''<canvas id="fx-canvas" aria-hidden="true"></canvas>
<div class="dlg" id="dlg" hidden>
  <div class="bilhete" role="alertdialog" aria-modal="true" aria-describedby="dlg-texto">
    <p id="dlg-texto"></p>
    <div class="field" id="dlg-campo-wrap" hidden><textarea id="dlg-campo" rows="3" style="min-height:90px"></textarea></div>
    <div class="dlg-botoes"><button class="btn ghost" id="dlg-nao">Cancelar</button><button class="btn coral" id="dlg-ok">OK</button></div>
  </div>
</div>
<div class="toast" id="toast" role="status" aria-live="polite"></div>'''

def scripts():
    return f'''<script src="config.js?v={V}"></script>
<script src="efeitos.js?v={V}"></script>
<script src="vitrine.js?v={V}"></script>
<script src="publico.js?v={V}"></script>'''

def pagina(nome, titulo, descricao, ativo, corpo, pagina_id):
    html = f'''{cabeca(titulo, descricao)}
<body class="pub" data-pagina="{pagina_id}">
{topo(ativo)}
<main class="pub-conteudo">
{corpo}
</main>
{RODAPE}
{CAMADAS}
{scripts()}
</body>
</html>
'''
    open(os.path.join(SITE, nome), 'w', encoding='utf-8').write(html)

def ad(nome, cls=''):
    return f'<img class="adesivo {cls}" src="adesivos/{nome}.webp" alt="">'

def ic(nome, t=18):
    return f'<svg class="ico" style="width:{t}px;height:{t}px" aria-hidden="true"><use href="icones.svg#{nome}"/></svg>'

# ---------------------------------------------------------------- Para escolas
item = lambda adesivo, titulo, texto: f'<div class="pub-item">{ad(adesivo)}<h3>{titulo}</h3><p>{texto}</p></div>'
escolas = f'''
<section class="pub-hero">
  <div>
    <span class="tag-hero">{ic("i-escola", 16)}EstudeUp para escolas</span>
    <h1>Sua instituição pode estar <mark>mais perto de quem quer aprender</mark>.</h1>
    <p class="lead">Seus alunos estudando com plano até a prova e sua escola sendo encontrada. O EstudeUp transforma o material do professor em resumo, quiz, flashcards e um plano de estudo dia a dia até a prova. E dá à sua escola uma página e um mural pra divulgar matrículas, bolsas e aulas experimentais.</p>
    <div class="pub-ctas">
      <a class="btn coral" href="#contato">{ic("i-megafone")}Quero apresentar minha escola</a>
      <a class="ghost-btn forte" style="width:auto" href="#" data-demo-link hidden>{ic("i-olho")}Ver uma escola de demonstração</a>
    </div>
  </div>
  <div class="pub-vitrine-hero" aria-label="ilustração do app">
    {ad("calendario", "a1")}{ad("trofeu", "a2")}
    <div class="cartao-flutua c1">
      <span class="rot">plano do aluno</span>
      <h4>Biologia · prova em 12 dias</h4>
      <div class="linha-tarefa"><span class="bolinha feita"></span>Revisar mitose · 20 min</div>
      <div class="linha-tarefa"><span class="bolinha feita"></span>Quiz de meiose</div>
      <div class="linha-tarefa"><span class="bolinha"></span>Flashcards de genética</div>
    </div>
    <div class="cartao-flutua c2">
      <span class="rot">painel da turma</span>
      <h4>3º A · Biologia</h4>
      <span class="small muted">onde a turma está fraca</span>
      <div class="small"><b>Meiose</b></div><div class="barra"><i style="width:42%;background:var(--erro)"></i></div>
      <div class="small"><b>Mitose</b></div><div class="barra"><i style="width:78%;background:var(--certo)"></i></div>
      <span class="small muted">ilustração do painel</span>
    </div>
  </div>
</section>

<section class="pub-secao">
  <span class="rotulo">Dentro da sala</span>
  <h2>O professor manda o material. O aluno recebe o plano.</h2>
  <p class="sub">A escola usa o EstudeUp com os próprios alunos, turma por turma.</p>
  <div class="pub-grade">
    {item("turma", "Turma do professor", "O professor cria a turma e passa o código. Só ele coloca material; cada aluno ganha o seu plano.")}
    {item("calendario", "Plano até a prova", "Um plano dia a dia até a data da prova, começando pelos tópicos em que o aluno está mais fraco.")}
    {item("cerebro", "Resumo, quiz e flashcards", "Gerados a partir da foto do caderno, do PDF ou do texto que o professor mandar.")}
    {item("alvo", "Simulado ENEM e redação", "Questões oficiais do ENEM e correção de redação nas 5 competências.")}
    {item("grafico", "Painel da turma", "Onde a turma está fraca, quem sumiu e quem está em dia, sem planilha.")}
    {item("robo", "Tutor com foto", "O aluno manda a foto do exercício e recebe a explicação passo a passo.")}
  </div>
</section>

<section class="pub-secao">
  <span class="rotulo">Fora da sala</span>
  <h2>Uma vitrine pra quem está decidindo onde estudar.</h2>
  <p class="sub">Página da escola e mural de oportunidades, abertos na internet e dentro do app.</p>
  <div class="pub-grade">
    {item("escola", "Página da escola", "Cursos, modalidades, endereço e contato, com um link pra divulgar onde quiser.")}
    {item("megafone", "Mural de oportunidades", "Matrículas abertas, bolsas, descontos, aulas experimentais e eventos, sempre com prazo.")}
    {item("balao", "Contato direto", "O botão abre o WhatsApp ou o site da escola, com uma mensagem pronta.")}
    {item("prancheta", "Números de interesse", "Visualizações da página e das oportunidades e cliques no contato, por período.")}
  </div>
</section>

<section class="pub-secao">
  <span class="rotulo">Parceria</span>
  <h2>Como funciona</h2>
  <ol class="pub-passos">
    <li><b>Você manda o contato</b><span>Pelo formulário aqui embaixo.</span></li>
    <li><b>A gente apresenta</b><span>Uma conversa curta mostrando o EstudeUp na realidade da sua escola.</span></li>
    <li><b>Cadastro e aprovação</b><span>A escola recebe o painel e os professores, um código pra criar as turmas.</span></li>
    <li><b>No ar</b><span>Turmas estudando e a página da escola publicada, com as oportunidades aprovadas.</span></li>
  </ol>
</section>

<section class="pub-secao">
  <span class="rotulo">Planos</span>
  <h2>Pra cada tamanho de escola</h2>
  <p class="sub">Todos incluem as turmas no EstudeUp e a página da escola.</p>
  <div class="pub-planos" id="planos"><div class="loading">carregando...</div></div>
</section>

<section class="pub-secao">
  <span class="rotulo">Cuidado com os alunos</span>
  <h2>Feito pra quem tem aluno menor de idade</h2>
  <div class="pub-cuidados">
    <div>{ic("i-selo", 22)}<span>A escola não recebe dados de quem vê a página ou as oportunidades. O contato parte do aluno ou da família.</span></div>
    <div>{ic("i-selo", 22)}<span>Toda oportunidade passa por aprovação e aparece marcada como de instituição parceira.</span></div>
    <div>{ic("i-selo", 22)}<span>Nada de propaganda no tutor de IA e nada de anúncio direcionado pelo comportamento do aluno.</span></div>
    <div>{ic("i-selo", 22)}<span>Em público, o aluno aparece só com o primeiro nome e a inicial. Não existe mensagem privada entre alunos.</span></div>
    <div>{ic("i-selo", 22)}<span>Bolsa e desconto só entram com as regras e condições informadas pela escola.</span></div>
  </div>
</section>

<section class="pub-secao" id="contato">
  <div class="pub-form-wrap">
    <div>
      <span class="rotulo" style="font-size:13px;font-weight:800;letter-spacing:.06em;text-transform:uppercase;color:var(--marca)">Contato</span>
      <h2 style="margin:6px 0 10px;font-size:clamp(24px,5vw,34px)">Quero apresentar minha escola</h2>
      <p class="muted" style="font-size:16.5px">Conta um pouco da sua instituição. A gente responde pelo WhatsApp ou pelo e-mail que você informar pra marcar a apresentação.</p>
      <p class="muted small">O cadastro da escola só acontece depois dessa conversa e da aprovação.</p>
      <a class="ghost-btn forte" style="width:auto;margin-top:6px" href="#" data-demo-link hidden>{ic("i-olho")}Ver uma escola de demonstração</a>
    </div>
    <div>
      <form class="pub-form" id="form-interesse" novalidate>
        <div class="row">
          <div class="field"><label for="f-inst">nome da instituição</label><input id="f-inst" name="instituicao" maxlength="120" autocomplete="organization" required></div>
          <div class="field"><label for="f-resp">seu nome</label><input id="f-resp" name="responsavel" maxlength="80" autocomplete="name" required></div>
          <div class="field"><label for="f-email">e-mail profissional</label><input id="f-email" name="email" type="email" maxlength="160" autocomplete="email" required></div>
          <div class="field"><label for="f-tel">telefone ou WhatsApp</label><input id="f-tel" name="telefone" type="tel" maxlength="20" autocomplete="tel" placeholder="(41) 99999-9999" required></div>
          <div class="field"><label for="f-cidade">cidade</label><input id="f-cidade" name="cidade" maxlength="80" autocomplete="address-level2" required></div>
          <div class="field"><label for="f-tipo">tipo de instituição</label>
            <select id="f-tipo" name="tipo" required><option value="">escolhe</option><option value="escola">Escola</option><option value="cursinho">Cursinho / pré-vestibular</option>
            <option value="idiomas">Escola de idiomas</option><option value="profissionalizante">Curso profissionalizante</option><option value="faculdade">Faculdade</option>
            <option value="reforco">Reforço escolar</option><option value="outro">Outro</option></select></div>
        </div>
        <div class="field"><label for="f-msg">mensagem <span class="opt">(opcional)</span></label><textarea id="f-msg" name="mensagem" maxlength="1000" style="min-height:96px" placeholder="quantos alunos, quais séries, o que mais interessa"></textarea></div>
        <div class="escondido" aria-hidden="true"><label for="f-site">site</label><input id="f-site" name="site_url" tabindex="-1" autocomplete="off"></div>
        <label class="consent"><input type="checkbox" name="consentimento" id="f-consent"><span id="texto-consentimento">Autorizo o EstudeUp a usar estes dados só para responder a esta solicitação e apresentar a parceria.</span></label>
        <p class="small" style="margin:-8px 0 14px"><a href="privacidade.html" style="color:var(--marca);font-weight:800">Aviso de privacidade</a></p>
        <p class="aviso-moderacao" id="form-erro" role="alert" hidden></p>
        <button class="btn coral" id="btn-interesse" type="submit" style="width:100%">{ic("i-enviar")}Quero ser escola parceira</button>
      </form>
      <div class="pub-ok" id="form-ok" hidden role="status">
        {ad("festa")}
        <h3>Recebemos seu contato!</h3>
        <p class="muted">A gente vai falar com você pelo WhatsApp ou pelo e-mail informado pra marcar a apresentação.</p>
      </div>
    </div>
  </div>
</section>
<a class="pub-zap" id="pub-zap" href="#" target="_blank" rel="noopener" hidden>{ic("i-whatsapp", 22)}Falar no WhatsApp</a>
'''
pagina('escolas.html', 'EstudeUp para escolas', 'Sua instituição mais perto de quem quer aprender: turmas no EstudeUp, página da escola e mural de oportunidades.', 'escolas', escolas, 'escolas')

# ---------------------------------------------------------------- mural
mural = f'''
<section>
  <h1 style="font-size:clamp(26px,6vw,40px);margin:6px 0 8px">Oportunidades das escolas parceiras</h1>
  <p class="muted" style="font-size:16.5px;max-width:640px;margin:0 0 18px">Matrículas, bolsas, aulas experimentais e eventos de escolas que estão no EstudeUp, com prazo e condições informadas pela escola.</p>
  <div class="filtros-vitrine">
    <div class="busca" style="margin:0">{ic("i-busca")}<input type="search" id="mural-busca" placeholder="buscar escola, curso ou oportunidade" aria-label="buscar oportunidade"></div>
    <div class="linha"><select id="mural-cidade" aria-label="cidade"><option value="">todas as cidades</option></select></div>
    <div class="chips-rolam" id="mural-cats"></div>
  </div>
  <div id="mural-lista"><div class="loading">carregando...</div></div>
  <p class="small muted" style="margin-top:16px">{ic("i-info", 14)} As publicações são de instituições parceiras. O EstudeUp não passa seus dados pra escola: quem decide entrar em contato é você. Menor de 18 anos? Combina com seus responsáveis.</p>
</section>
<section class="pub-secao">
  <h2 style="margin-bottom:12px">Escolas parceiras</h2>
  <div class="escola-lista" id="mural-escolas"></div>
</section>
<section class="pub-secao">
  <div class="pub-item" style="display:flex;gap:14px;align-items:center;flex-wrap:wrap">
    {ad("escola")}
    <div style="flex:1;min-width:220px"><h3>É de uma escola?</h3><p>Coloque a sua escola no EstudeUp: turmas estudando com plano até a prova e uma vitrine pra quem está escolhendo onde estudar.</p></div>
    <a class="btn coral" href="escolas.html">Quero apresentar minha escola</a>
  </div>
</section>
'''
pagina('oportunidades.html', 'Oportunidades das escolas · EstudeUp', 'Matrículas, bolsas, aulas experimentais e eventos de escolas parceiras do EstudeUp.', 'mural', mural, 'mural')

# ---------------------------------------------------------------- escola
escola = f'''
<a class="pub-voltar" href="oportunidades.html">{ic("i-voltar")}oportunidades</a>
<div id="escola"><div class="loading">carregando...</div></div>
<section class="pub-secao">
  <div class="pub-item" style="display:flex;gap:14px;align-items:center;flex-wrap:wrap">
    {ad("caderno")}
    <div style="flex:1;min-width:220px"><h3>Estuda com plano até a prova</h3><p>Manda a foto do caderno e o EstudeUp monta resumo, quiz, flashcards e um plano dia a dia até a data da prova.</p></div>
    <a class="ghost-btn forte" style="width:auto" href="./">Entrar no EstudeUp</a>
  </div>
</section>
'''
pagina('escola.html', 'Escola · EstudeUp', 'Página da escola parceira no EstudeUp.', '', escola, 'escola')

# ---------------------------------------------------------------- privacidade
priv = '''
<article class="texto-legal" style="max-width:760px">
  <h1 style="font-size:clamp(26px,6vw,36px)">Aviso de privacidade</h1>
  <p class="muted">Como o EstudeUp usa os dados de quem estuda, de quem ensina e das escolas parceiras. Atualizado em outubro de 2026.</p>
  <h2>Quem cuida dos dados</h2>
  <p>O EstudeUp é um app de estudo mantido pela DDS Inovação. Fale com a gente <span id="contato-dados">pelos canais de atendimento</span>.</p>
  <h2>O que usamos e pra quê</h2>
  <ul>
    <li><b>Conta:</b> nome, e-mail e senha (a senha fica com o serviço de login, não com a gente em texto). Escola, cidade e série são opcionais. Servem pra criar a sua conta e montar o seu plano de estudo.</li>
    <li><b>Estudo:</b> o material que você manda (foto, PDF, texto, link), suas respostas, flashcards, plano e XP. Servem pra o app funcionar. O material é processado por um serviço de inteligência artificial pra gerar resumo, quiz e flashcards.</li>
    <li><b>Biblioteca e comunidade:</b> o que você publica aparece pra outros alunos só com o seu primeiro nome e a inicial do sobrenome. Passa por filtro (sem link, telefone ou rede social) e por moderação.</li>
    <li><b>Turmas:</b> o professor vê o progresso dos alunos da turma dele (o aluno entra na turma pelo código que o professor passa). A escola vê só números da turma, sem lista de nomes.</li>
    <li><b>Vitrine das escolas:</b> contamos visualizações e cliques com um número aleatório guardado no seu navegador, sem nome. A escola vê só quantas vezes a página e as oportunidades foram vistas.</li>
    <li><b>Formulário "Para escolas":</b> os dados de quem representa a instituição, usados só pra responder a solicitação.</li>
  </ul>
  <h2>Crianças e adolescentes</h2>
  <p>Muitos alunos são menores de idade. Por isso: não existe mensagem privada entre alunos; não fazemos anúncio direcionado pelo comportamento de ninguém; as oportunidades das escolas aparecem marcadas como de instituição parceira e nunca dentro do tutor; e o contato com uma escola só acontece se o aluno ou a família decidir. Recomendamos que menores combinem com os responsáveis antes de falar com uma escola.</p>
  <h2>Com quem os dados são compartilhados</h2>
  <p>Só com os serviços necessários pra o app funcionar: o banco de dados e o login (Supabase), a inteligência artificial que gera o conteúdo de estudo (Anthropic) e a hospedagem do site (GitHub Pages). Não vendemos dados.</p>
  <h2>Seus direitos</h2>
  <p>Você pode pedir pra ver, corrigir ou apagar seus dados, e tirar uma autorização que deu. É só falar com a gente pelos canais acima.</p>
</article>
'''
pagina('privacidade.html', 'Aviso de privacidade · EstudeUp', 'Como o EstudeUp usa os dados de alunos, professores e escolas parceiras.', '', priv, 'privacidade')
print('ok')
