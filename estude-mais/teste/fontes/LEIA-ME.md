# Materiais de teste das fontes Foto e PDF

Usados para testar em produção a geração de conteúdo (`estude-gerar-conteudo`) com as turmas da escola de demonstração (Colégio Monte Aurora, fictícia).

- `caderno_bio.jpg`: "foto de caderno" com anotações de Biologia (fotossíntese e respiração). Gerada por `caderno.py` com a fonte Caveat (OFL, Google Fonts).
- `caderno_bio.jpg.b64`: a mesma foto em base64 (o banco busca esse texto para mandar à função, sem passar o arquivo pelo app).
- `redacao_enem.pdf`: apostila curta de Redação ENEM. Gerada por `redacao_pdf.py` (reportlab). `redacao_enem.pdf.b64` é a mesma em base64.
