"""Converte as questões do repositório público enem-api (yunger7) em SQL para be_enem_questoes.
As imagens continuam apontando para enem.dev; o app troca para o GitHub se alguma não carregar."""
import json, glob, os, re, sys

RAIZ = sys.argv[1]
SHA = sys.argv[2]
SAIDA = sys.argv[3]
CDN = f"https://cdn.jsdelivr.net/gh/yunger7/enem-api@{SHA}/public"

def cdn(texto):
    return texto

linhas, pulos, anos = [], 0, {}
for arq in sorted(glob.glob(os.path.join(RAIZ, "public/*/questions/*/details.json"))):
    q = json.load(open(arq, encoding="utf-8"))
    alts = q.get("alternatives") or []
    gab = q.get("correctAlternative")
    if len(alts) != 5 or gab not in "ABCDE" or not gab:
        pulos += 1
        continue
    if q.get("discipline") not in ("linguagens", "ciencias-humanas", "ciencias-natureza", "matematica"):
        pulos += 1
        continue
    alternativas = [{"letter": a["letter"], "text": cdn(a.get("text") or ""), "file": cdn(a.get("file"))} for a in alts]
    linhas.append({
        "ano": q["year"], "numero": q["index"], "idioma": q.get("language"), "area": q["discipline"],
        "contexto": cdn(q.get("context") or ""), "introducao": q.get("alternativesIntroduction") or "",
        "alternativas": alternativas, "gabarito": gab,
    })
    anos[q["year"]] = anos.get(q["year"], 0) + 1

def lit(v):
    if v is None:
        return "null"
    return "'" + str(v).replace("'", "''") + "'"

os.makedirs(SAIDA, exist_ok=True)
lote, n_arq = 400, 0
for i in range(0, len(linhas), lote):
    parte = linhas[i:i + lote]
    vals = ",\n".join(
        f"({r['ano']},{r['numero']},{lit(r['idioma'])},{lit(r['area'])},{lit(r['contexto'])},{lit(r['introducao'])},"
        f"{lit(json.dumps(r['alternativas'], ensure_ascii=False))}::jsonb,{lit(r['gabarito'])})" for r in parte)
    sql = ("insert into public.be_enem_questoes (ano, numero, idioma, area, contexto, introducao, alternativas, gabarito) values\n"
           + vals + "\non conflict (ano, numero, coalesce(idioma, '')) do update set contexto = excluded.contexto, "
           "introducao = excluded.introducao, alternativas = excluded.alternativas, gabarito = excluded.gabarito, area = excluded.area;\n")
    n_arq += 1
    open(os.path.join(SAIDA, f"enem_{n_arq:02d}.sql"), "w", encoding="utf-8").write(sql)

print("questões:", len(linhas), "puladas:", pulos, "arquivos:", n_arq)
print("por ano:", dict(sorted(anos.items())))
