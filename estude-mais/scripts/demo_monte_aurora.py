"""Gera as imagens do Colégio Monte Aurora (escola FICTÍCIA de demonstração do Estude+):
logo (SVG), capa e banners das oportunidades (WebP), em site/demo/monte-aurora/.
Uso: python3 scripts/demo_monte_aurora.py <pasta com unbounded.ttf e atkinson-next.ttf>"""
import math, os, sys, random
from PIL import Image, ImageDraw, ImageFilter, ImageFont

RAIZ = os.path.join(os.path.dirname(__file__), '..', 'site')
SAIDA = os.path.join(RAIZ, 'demo', 'monte-aurora')
os.makedirs(SAIDA, exist_ok=True)
FONTES = sys.argv[1]
random.seed(7)


def fonte(nome, tam, peso):
    f = ImageFont.truetype(os.path.join(FONTES, nome + '.ttf'), tam)
    try:
        f.set_variation_by_axes([peso])
    except Exception:
        pass
    return f


def hexrgb(h):
    h = h.lstrip('#')
    return tuple(int(h[i:i + 2], 16) for i in (0, 2, 4))


def gradiente(w, h, c1, c2, vertical=True):
    a, b = hexrgb(c1), hexrgb(c2)
    im = Image.new('RGB', (w, h))
    px = im.load()
    for y in range(h):
        for x in range(w):
            t = y / (h - 1) if vertical else (x / (w - 1) * 0.7 + y / (h - 1) * 0.3)
            px[x, y] = tuple(int(a[i] + (b[i] - a[i]) * t) for i in range(3))
    return im


# ---------------- logo (vetor) ----------------
LOGO = '''<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 512 512">
  <!-- Colégio Monte Aurora: escola FICTÍCIA, criada para demonstrar o Estude+ -->
  <defs>
    <linearGradient id="ceu" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="#1E2A6E"/><stop offset="1" stop-color="#2F3FA8"/></linearGradient>
    <linearGradient id="sol" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="#FFD34D"/><stop offset="1" stop-color="#FF7A3D"/></linearGradient>
    <clipPath id="borda"><rect width="512" height="512" rx="120"/></clipPath>
  </defs>
  <g clip-path="url(#borda)">
  <rect width="512" height="512" fill="url(#ceu)"/>
  <g stroke="#FFD34D" stroke-width="16" stroke-linecap="round" opacity=".9">
    <line x1="256" y1="70" x2="256" y2="112"/><line x1="140" y1="118" x2="168" y2="148"/><line x1="372" y1="118" x2="344" y2="148"/>
    <line x1="88" y1="222" x2="128" y2="226"/><line x1="424" y1="222" x2="384" y2="226"/>
  </g>
  <circle cx="256" cy="262" r="104" fill="url(#sol)"/>
  <path d="M40 420 L184 236 L250 318 L318 212 L472 420 Z" fill="#5B6BD6"/>
  <path d="M318 212 L360 268 L338 262 L318 282 L300 258 L282 266 Z" fill="#F4F6FB"/>
  <path d="M184 236 L214 274 L196 270 L184 284 L170 268 Z" fill="#F4F6FB" opacity=".9"/>
  <path d="M0 400 C120 360 220 380 300 404 C380 428 450 410 512 392 L512 440 L0 440 Z" fill="#12B981"/>
  <rect y="430" width="512" height="82" fill="#0E1A4F"/>
  <path d="M196 466 h120" stroke="#FFD34D" stroke-width="14" stroke-linecap="round"/>
  </g>
</svg>
'''
open(os.path.join(SAIDA, 'logo.svg'), 'w', encoding='utf-8').write(LOGO)

# ---------------- capa ----------------
def capa():
    W, H = 1600, 600
    im = gradiente(W, H, '#1E2A6E', '#FF9A5A')
    d = ImageDraw.Draw(im, 'RGBA')
    for _ in range(90):  # estrelinhas no alto
        x, y = random.randint(0, W), random.randint(0, 220)
        r = random.choice((1, 1, 2, 2, 3))
        d.ellipse((x - r, y - r, x + r, y + r), fill=(255, 255, 255, random.randint(60, 170)))
    brilho = Image.new('RGBA', (W, H), (0, 0, 0, 0))
    db = ImageDraw.Draw(brilho)
    for i in range(14, 0, -1):
        rr = 150 + i * 26
        db.ellipse((1060 - rr, 360 - rr, 1060 + rr, 360 + rr), fill=(255, 196, 90, 9))
    im.paste(brilho, (0, 0), brilho)
    d = ImageDraw.Draw(im, 'RGBA')
    d.ellipse((1060 - 150, 360 - 150, 1060 + 150, 360 + 150), fill=(255, 205, 80, 255))
    camadas = [
        ([(0, 600), (0, 380), (180, 250), (360, 360), (560, 210), (800, 380), (1000, 260), (1240, 390), (1420, 280), (1600, 360), (1600, 600)], (91, 107, 214, 235)),
        ([(0, 600), (0, 440), (240, 330), (470, 450), (720, 320), (980, 460), (1200, 360), (1600, 470), (1600, 600)], (55, 66, 168, 255)),
        ([(0, 600), (0, 500), (300, 450), (640, 520), (960, 470), (1300, 530), (1600, 490), (1600, 600)], (18, 185, 129, 255)),
    ]
    for pts, cor in camadas:
        d.polygon(pts, fill=cor)
    # prédio da escola no morro
    bx, by = 260, 400
    d.rectangle((bx, by, bx + 260, by + 110), fill=(244, 246, 251, 255))
    d.polygon([(bx - 16, by), (bx + 130, by - 70), (bx + 276, by)], fill=(255, 92, 157, 255))
    d.rectangle((bx + 110, by + 50, bx + 150, by + 110), fill=(30, 42, 110, 255))
    for i in range(4):
        x = bx + 18 + i * 62 if i < 2 else bx + 168 + (i - 2) * 50
        d.rectangle((x, by + 22, x + 30, by + 50), fill=(255, 211, 77, 255))
    d.line((bx + 130, by - 70, bx + 130, by - 130), fill=(244, 246, 251, 255), width=5)
    d.polygon([(bx + 132, by - 130), (bx + 182, by - 116), (bx + 132, by - 102)], fill=(255, 211, 77, 255))
    d.rectangle((0, 560, W, 600), fill=(14, 26, 79, 255))
    im.save(os.path.join(SAIDA, 'capa.webp'), 'WEBP', quality=86)


# ---------------- banners das oportunidades ----------------
def quebrar(d, texto, f, largura):
    linhas, atual = [], ''
    for p in texto.split():
        teste = (atual + ' ' + p).strip()
        if d.textlength(teste, font=f) <= largura:
            atual = teste
        else:
            linhas.append(atual); atual = p
    if atual:
        linhas.append(atual)
    return linhas


def banner(nome, c1, c2, titulo, sub, adesivos, destaque=None):
    W, H = 1200, 525
    im = gradiente(W, H, c1, c2, vertical=False).convert('RGBA')
    camada = Image.new('RGBA', (W, H), (0, 0, 0, 0))  # desenha transparências numa camada e depois mistura
    dc = ImageDraw.Draw(camada)
    for i in range(-H, W, 46):  # listras diagonais
        dc.polygon([(i, H), (i + 22, H), (i + 22 + H, 0), (i + H, 0)], fill=(255, 255, 255, 12))
    im.alpha_composite(camada)
    camada = Image.new('RGBA', (W, H), (0, 0, 0, 0))
    ImageDraw.Draw(camada).ellipse((W - 520, -180, W + 120, 460), fill=(255, 255, 255, 34))
    im.alpha_composite(camada)
    camada = Image.new('RGBA', (W, H), (0, 0, 0, 0))
    d = ImageDraw.Draw(camada)
    ft, fs, fp = fonte('unbounded', 74, 800), fonte('atkinson-next', 34, 700), fonte('atkinson-next', 22, 800)
    y = 70
    for linha in quebrar(d, titulo, ft, 700):
        x = 64
        if destaque and destaque in linha:
            antes, depois = linha.split(destaque, 1)
            d.text((x, y), antes, font=ft, fill='white')
            x += d.textlength(antes, font=ft)
            caixa = d.textbbox((x, y), destaque, font=ft)
            d.rounded_rectangle((caixa[0] - 10, caixa[1] - 6, caixa[2] + 10, caixa[3] + 10), 14, fill=(255, 211, 77, 255))
            d.text((x, y), destaque, font=ft, fill=(14, 26, 79))
            x += d.textlength(destaque, font=ft)
            d.text((x, y), depois, font=ft, fill='white')
        else:
            d.text((x, y), linha, font=ft, fill='white')
        y += 88
    d.text((66, y + 12), sub, font=fs, fill=(255, 255, 255, 240))
    # selo da escola
    d.rounded_rectangle((64, H - 82, 64 + 300, H - 34), 24, fill=(14, 26, 79, 210))
    d.text((90, H - 71), 'Colégio Monte Aurora', font=fp, fill=(255, 211, 77, 255))
    d.text((W - 262, H - 58), 'escola de demonstração', font=fonte('atkinson-next', 20, 700), fill=(255, 255, 255, 190))
    im.alpha_composite(camada)
    for i, a in enumerate(adesivos):
        st = Image.open(os.path.join(RAIZ, 'adesivos', a + '.webp')).convert('RGBA')
        tam = 250 if i == 0 else 170
        st = st.resize((tam, tam), Image.LANCZOS).rotate(-8 if i == 0 else 12, expand=True, resample=Image.BICUBIC)
        sombra = Image.new('RGBA', st.size, (0, 0, 0, 0))
        sombra.paste((10, 15, 50, 90), (0, 0), st.split()[3])
        sombra = sombra.filter(ImageFilter.GaussianBlur(10))
        pos = (W - 330, 120) if i == 0 else (W - 470, 300)
        im.alpha_composite(sombra, (pos[0] + 8, pos[1] + 14))
        im.alpha_composite(st, pos)
    im.convert('RGB').save(os.path.join(SAIDA, nome + '.webp'), 'WEBP', quality=86)


capa()
banner('bolsas', '#1E2A6E', '#3D4FD1', 'Bolsas de até 50%', 'Prova de bolsas · Ensino Médio 2027', ['trofeu', 'medalha1'], destaque='50%')
banner('robotica', '#0B8F63', '#12B981', 'Aula experimental de robótica', '6º ao 9º ano · sábados de novembro', ['robo', 'foguete'])
banner('matriculas', '#E23A7E', '#FF5C9D', 'Matrículas 2027 abertas', 'Fundamental II e Ensino Médio', ['escola', 'calendario'])
banner('enem', '#5B32C9', '#8457F0', 'Intensivão ENEM', '4 aulões de revisão de véspera', ['alvo', 'capelo'])
banner('profissoes', '#E8590C', '#FF7F32', 'Feira de profissões', 'Conversa com ex-alunos e universidades', ['megafone', 'lampada'])
banner('ingles', '#1F4BFF', '#3D7BFF', 'Inglês nas férias', 'Curso intensivo de janeiro · 11 a 17 anos', ['globo', 'balao'])
print('ok', sorted(os.listdir(SAIDA)))
