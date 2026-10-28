# apostila curta de Redação ENEM da prof.ª Camila (material de demonstração)
from reportlab.lib.pagesizes import A4
from reportlab.platypus import SimpleDocTemplate, Paragraph, Spacer, Table, TableStyle
from reportlab.lib.styles import getSampleStyleSheet, ParagraphStyle
from reportlab.lib import colors
from reportlab.lib.units import cm
st = getSampleStyleSheet()
h1 = ParagraphStyle('h1', parent=st['Heading1'], fontSize=17, textColor=colors.HexColor('#24306E'), spaceAfter=4)
h2 = ParagraphStyle('h2', parent=st['Heading2'], fontSize=12.5, textColor=colors.HexColor('#E8590C'), spaceBefore=8, spaceAfter=3)
p = ParagraphStyle('p', parent=st['BodyText'], fontSize=10, leading=13.5)
peq = ParagraphStyle('peq', parent=p, fontSize=8, textColor=colors.grey)
doc = SimpleDocTemplate('redacao_enem.pdf', pagesize=A4, leftMargin=2*cm, rightMargin=2*cm, topMargin=1.6*cm, bottomMargin=1.6*cm,
                        title='Redação ENEM - competências e estrutura', author='Material de demonstração')
c = []
c.append(Paragraph('Redação ENEM: as 5 competências e a estrutura do texto', h1))
c.append(Paragraph('3º ano A · Apostila de revisão · material de demonstração do Estude+', peq))
c.append(Spacer(1, 6))
c.append(Paragraph('O ENEM pede um <b>texto dissertativo-argumentativo</b> em prosa, de até 30 linhas, sobre um tema de ordem social, científica, cultural ou política. A nota vai de 0 a 1000 e soma cinco competências de 0 a 200 pontos cada.', p))
c.append(Paragraph('As 5 competências', h2))
t = Table([
  ['C1', 'Domínio da norma padrão da língua portuguesa (gramática, ortografia, concordância).'],
  ['C2', 'Compreender a proposta e aplicar conceitos de várias áreas, sem fugir do tema, no tipo dissertativo-argumentativo.'],
  ['C3', 'Selecionar, relacionar, organizar e interpretar informações e argumentos em defesa de um ponto de vista (projeto de texto).'],
  ['C4', 'Conhecer os mecanismos linguísticos de argumentação: coesão (conectivos, retomadas, sem repetição).'],
  ['C5', 'Elaborar proposta de intervenção para o problema, respeitando os direitos humanos.'],
], colWidths=[1.2*cm, 15.3*cm])
t.setStyle(TableStyle([('FONTSIZE', (0,0), (-1,-1), 9.5), ('VALIGN', (0,0), (-1,-1), 'TOP'), ('TEXTCOLOR', (0,0), (0,-1), colors.HexColor('#24306E')),
  ('FONTNAME', (0,0), (0,-1), 'Helvetica-Bold'), ('ROWBACKGROUNDS', (0,0), (-1,-1), [colors.HexColor('#F4F6FB'), colors.white]),
  ('BOTTOMPADDING', (0,0), (-1,-1), 5), ('TOPPADDING', (0,0), (-1,-1), 5)]))
c.append(t)
c.append(Paragraph('Estrutura em 4 parágrafos', h2))
for s in [
  '<b>Introdução:</b> contextualize o tema (repertório: dado, lei, autor, fato histórico) e apresente a tese com os dois argumentos que serão desenvolvidos.',
  '<b>Desenvolvimento 1:</b> tópico frasal com o 1º argumento, repertório legitimado e pertinente, explicação e fechamento ligando ao tema.',
  '<b>Desenvolvimento 2:</b> o 2º argumento com a mesma lógica; use conectivos de abertura ("Além disso", "Outrossim", "Em segundo plano").',
  '<b>Conclusão:</b> retome a tese e faça a proposta de intervenção completa com os 5 elementos: <b>agente</b> (quem), <b>ação</b> (o quê), <b>modo/meio</b> (como), <b>finalidade</b> (para quê) e <b>detalhamento</b> de um dos elementos.',
]:
  c.append(Paragraph('• ' + s, p))
c.append(Paragraph('O que zera a redação', h2))
c.append(Paragraph('Fuga total ao tema; não obedecer ao tipo dissertativo-argumentativo; texto com até 7 linhas; parte desconectada do tema de propósito; desrespeito aos direitos humanos; folha em branco; identificação do candidato no texto.', p))
c.append(Paragraph('Repertório e coesão: dicas rápidas', h2))
for s in ['Repertório bom é <b>legitimado</b> (fonte reconhecida), <b>pertinente</b> (tem a ver com o tema) e <b>produtivo</b> (você explica e usa no argumento).',
          'Varie conectivos: adição (além disso, ademais), oposição (entretanto, todavia), causa (visto que, uma vez que), conclusão (portanto, dessa forma).',
          'Evite repetir palavras: use sinônimos, pronomes e expressões que retomam ("tal cenário", "essa problemática").']:
  c.append(Paragraph('• ' + s, p))
doc.build(c)
