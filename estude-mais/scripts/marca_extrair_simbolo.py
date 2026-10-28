# EstudeUp: recorta o símbolo (S de livros) do arquivo original da logo e gera os ícones do app.
# Uso: rodar dentro de uma pasta com o original copiado como logo_original.png (o original fica em marca/estudeup-logo-original.png).
# O recorte (x0, x1, y0, y1) é o retângulo das cores no original de 6250x3516; o fundo branco e o preto viram transparência.
# Saída: simbolo-*.png/.webp, icon-192.png, icon-512.png, apple-touch-icon.png, favicon-48.png e previa.png -> copiar pra site/ e site/marca/.
import numpy as np
from PIL import Image, ImageDraw
from scipy import ndimage
im = Image.open('logo_original.png').convert('RGB')
a = np.asarray(im).astype(np.float32)
x0, x1, y0, y1 = 1158, 5114, 231, 3382
m = 14
a = a[y0 - m:y1 + m, x0 - m:x1 + m]
H, W, _ = a.shape
mn, mx = a.min(2), a.max(2)
claro = (mx >= 251) & (mn >= 236)
escuro = mx < 40
fundo_cand = claro | escuro
rot, n = ndimage.label(fundo_cand)
borda = set(np.unique(np.concatenate([rot[0], rot[-1], rot[:, 0], rot[:, -1]]))) - {0}
fundo = np.isin(rot, list(borda))
# faixa da borda: até 6 px do fundo -> "cor para transparência" a partir do branco
dist = ndimage.distance_transform_edt(~fundo)
faixa = (dist > 0) & (dist <= 3)
alfa = np.ones((H, W), np.float32)
alfa[fundo] = 0
rgb = a.copy()
c = a[faixa]
al = np.clip((255 - c.min(1)) / 22, 0, 1)  # perto do branco puro vira transparente; páginas (cinza) ficam opacas
al = al
safe = np.maximum(al, 1e-3)[:, None]
rgb[faixa] = np.clip((c - (1 - al)[:, None] * 255) / safe, 0, 255)
alfa[faixa] = al
# tira pedacinhos soltos (cantos arredondados do fundo original), fica só o símbolo
lab, n = ndimage.label(alfa > 0.05)
if n > 1:
    tam = ndimage.sum(np.ones_like(alfa), lab, index=np.arange(1, n + 1))
    manter = np.isin(lab, (np.where(tam > tam.max() * 0.01)[0] + 1))
    alfa[~manter] = 0
out = np.dstack([rgb, alfa * 255]).astype(np.uint8)
s = Image.fromarray(out, 'RGBA')
bb = s.getbbox(); s = s.crop(bb)
print('símbolo', s.size)
s.save('simbolo_full.png')
# quadrado com respiro
lado = int(max(s.size) * 1.0)
q = Image.new('RGBA', (lado, lado), (0, 0, 0, 0)); q.paste(s, ((lado - s.width) // 2, (lado - s.height) // 2), s)
for t in (64, 128, 256, 512):
    q.resize((t, t), Image.LANCZOS).save(f'simbolo-{t}.png', optimize=True)
q.resize((256, 256), Image.LANCZOS).save('simbolo-256.webp', quality=90, method=6)
# ícone do app: fundo branco cheio, símbolo com respiro (cabe no recorte redondo dos celulares)
for t in (192, 512):
    ic = Image.new('RGBA', (t, t), (255, 255, 255, 255))
    r = int(t * 0.70)
    sm = q.resize((r, r), Image.LANCZOS)
    ic.paste(sm, ((t - r) // 2, (t - r) // 2), sm)
    ic.convert('RGB').save(f'icon-{t}.png', optimize=True)
# apple touch e favicon 32
ic = Image.new('RGBA', (180, 180), (255, 255, 255, 255)); r = 132; sm = q.resize((r, r), Image.LANCZOS); ic.paste(sm, (24, 24), sm); ic.convert('RGB').save('apple-touch-icon.png', optimize=True)
q.resize((48, 48), Image.LANCZOS).save('favicon-48.png', optimize=True)
# prévia em fundo claro e escuro
pv = Image.new('RGB', (1100, 520), (244, 246, 251)); d = ImageDraw.Draw(pv); d.rectangle((550, 0, 1100, 520), fill=(14, 18, 48))
s2 = q.resize((420, 420), Image.LANCZOS); pv.paste(s2, (65, 50), s2)
t = Image.new('RGBA', (440, 440), (0, 0, 0, 0)); ImageDraw.Draw(t).rounded_rectangle((0, 0, 439, 439), 96, fill=(255, 255, 255, 255)); s3 = q.resize((340, 340), Image.LANCZOS); t.paste(s3, (50, 50), s3); pv.paste(t, (605, 40), t)
pv.save('previa.png')
# cores do símbolo (pra paleta)
arr = np.asarray(q.resize((200, 200))).reshape(-1, 4)
arr = arr[(arr[:, 3] > 250)]
sat = arr[:, :3].max(1).astype(int) - arr[:, :3].min(1)
cores = arr[sat > 80][:, :3]
from collections import Counter
cnt = Counter([tuple((c // 24 * 24).tolist()) for c in cores])
print([('#%02X%02X%02X' % k, v) for k, v in cnt.most_common(12)])
