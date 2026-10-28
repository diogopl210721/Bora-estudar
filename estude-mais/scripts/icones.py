"""Acrescenta ícones Phosphor (bold, MIT) ao sprite do index.html e gera site/icones.svg para as páginas públicas.
Uso: python3 scripts/icones.py <pasta assets/bold do @phosphor-icons/core>"""
import re, sys, os

BASE = os.path.join(os.path.dirname(__file__), '..', 'site')
NOVOS = {
    'i-whatsapp': 'whatsapp-logo', 'i-instagram': 'instagram-logo', 'i-pin': 'map-pin', 'i-telefone': 'phone',
    'i-email': 'envelope-simple', 'i-capelo': 'graduation-cap', 'i-megafone': 'megaphone', 'i-grafico': 'chart-bar',
    'i-vitrine': 'storefront', 'i-imagem': 'image', 'i-tag': 'tag', 'i-calendario': 'calendar-blank', 'i-turmas': 'users-three',
    'i-professor': 'chalkboard-teacher', 'i-escola': 'buildings', 'i-cursor': 'cursor-click', 'i-compartilhar': 'share-network',
    'i-filtro': 'funnel', 'i-abrir': 'arrow-square-out', 'i-selo': 'seal-check', 'i-pausa': 'pause', 'i-play': 'play',
    'i-arquivo': 'archive', 'i-nota': 'note-pencil', 'i-site': 'globe-simple', 'i-facebook': 'facebook-logo', 'i-info': 'info',
    'i-alerta': 'warning', 'i-aluno': 'student', 'i-ficha': 'identification-card', 'i-brilho': 'sparkle',
}
pasta = sys.argv[1]
idx = os.path.join(BASE, 'index.html')
html = open(idx, encoding='utf-8').read()
existentes = set(re.findall(r'<symbol id="([^"]+)"', html))
novos = []
for sid, nome in NOVOS.items():
    if sid in existentes:
        continue
    svg = open(os.path.join(pasta, f'{nome}-bold.svg'), encoding='utf-8').read()
    miolo = re.search(r'<svg[^>]*>(.*)</svg>', svg, re.S).group(1).strip()
    novos.append(f'<symbol id="{sid}" viewBox="0 0 256 256">{miolo}</symbol>')
if novos:
    fim = html.index('</svg>', html.index('<symbol id="i-hoje"'))
    html = html[:fim] + '\n'.join(novos) + '\n' + html[fim:]
    open(idx, 'w', encoding='utf-8').write(html)
ini = html.index('<symbol id="i-hoje"')
fim = html.index('</svg>', ini)
simbolos = html[ini:fim].strip()
open(os.path.join(BASE, 'icones.svg'), 'w', encoding='utf-8').write(
    '<svg xmlns="http://www.w3.org/2000/svg">\n<!-- Phosphor Icons (MIT) -->\n' + simbolos + '\n</svg>\n')
print('novos:', len(novos), 'total:', simbolos.count('<symbol'))
