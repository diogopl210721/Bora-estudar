# foto "de caderno" das anotações de Biologia do prof. Ricardo (conteúdo de demonstração)
from PIL import Image, ImageDraw, ImageFont, ImageFilter
import random
random.seed(3)
W, H = 760, 980
im = Image.new('RGB', (W, H), (250, 248, 240))
d = ImageDraw.Draw(im)
for y in range(110, H, 34):
    d.line((0, y, W, y), fill=(190, 212, 232), width=1)
d.line((70, 0, 70, H), fill=(232, 150, 150), width=2)
f = ImageFont.truetype('../fontes_dl/caveat.ttf', 30)
try: f.set_variation_by_axes([520])
except Exception: pass
ft = ImageFont.truetype('../fontes_dl/caveat.ttf', 40)
try: ft.set_variation_by_axes([700])
except Exception: pass
linhas = [
 ('t', 'Fotossíntese x Respiração celular'),
 ('', '• Fotossíntese: acontece no CLOROPLASTO'),
 ('', '  6 CO2 + 6 H2O + luz -> C6H12O6 + 6 O2'),
 ('', '• Fase clara (tilacoides): luz quebra a água'),
 ('', '  (fotólise) -> libera O2, forma ATP e NADPH'),
 ('', '• Fase escura / ciclo de Calvin (estroma):'),
 ('', '  usa ATP + NADPH pra fixar CO2 -> glicose'),
 ('', '• Respiração: na MITOCÔNDRIA'),
 ('', '  C6H12O6 + 6 O2 -> 6 CO2 + 6 H2O + ATP'),
 ('', '  glicólise (citoplasma) -> Krebs -> cadeia resp.'),
 ('', '  saldo ~ 30 a 32 ATP por glicose'),
 ('', '• Fermentação: sem O2, só 2 ATP'),
 ('', '  (alcoólica: levedura / lática: músculo)'),
 ('', '* Planta faz as DUAS! Respira dia e noite.'),
 ('', '  Ponto de compensação: fotossíntese = respiração'),
]
y = 64
for tipo, t in linhas:
    fonte = ft if tipo == 't' else f
    x = 86 + random.randint(-3, 3)
    d.text((x, y + random.randint(-2, 2)), t, font=fonte, fill=(28, 52, 140) if tipo != 't' else (170, 30, 60))
    y += 52 if tipo == 't' else 34 * 1.62
im = im.rotate(-1.6, resample=Image.BICUBIC, expand=True, fillcolor=(120, 110, 95))
im = im.filter(ImageFilter.GaussianBlur(0.5)).resize((560, int(560 * im.height / im.width)), Image.LANCZOS)
# sombra/luz de foto
luz = Image.new('L', im.size, 0)
dl = ImageDraw.Draw(luz)
for i in range(20):
    dl.ellipse((-200 + i * 10, -200 + i * 10, im.width + 200 - i * 10, im.height + 200 - i * 10), fill=8 * i)
im = Image.composite(im, Image.new('RGB', im.size, (200, 196, 186)), luz.filter(ImageFilter.GaussianBlur(40)).point(lambda v: min(255, 120 + v)))
im.save('caderno_bio.jpg', 'JPEG', quality=40, optimize=True, progressive=True)
print(im.size)
