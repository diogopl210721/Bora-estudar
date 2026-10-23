// Converte uma questão do repositório aberto enem-api (yunger7/enem-api) numa linha de be_enem_questoes.
// Mesmas regras do scripts/montar_enem.py: só entra questão com 5 alternativas, gabarito e área conhecida.

export const AREAS = ["linguagens", "ciencias-humanas", "ciencias-natureza", "matematica"];

export type LinhaEnem = {
  ano: number;
  numero: number;
  idioma: string | null;
  area: string;
  contexto: string;
  introducao: string;
  alternativas: { letter: string; text: string; file: string | null }[];
  gabarito: string;
};

export function montarQuestao(q: any): LinhaEnem | null {
  const alts = Array.isArray(q?.alternatives) ? q.alternatives : [];
  const gab = q?.correctAlternative;
  if (alts.length !== 5 || typeof gab !== "string" || !"ABCDE".includes(gab) || !gab) return null;
  if (!AREAS.includes(q.discipline)) return null;
  return {
    ano: q.year,
    numero: q.index,
    idioma: q.language ?? null,
    area: q.discipline,
    contexto: q.context || "",
    introducao: q.alternativesIntroduction || "",
    alternativas: alts.map((a: any) => ({ letter: a.letter, text: a.text || "", file: a.file ?? null })),
    gabarito: gab,
  };
}

// Caminho de cada questão dentro do repositório: public/{ano}/questions/{indice}[-{idioma}]/details.json
export function caminhosDoAno(detalhesAno: any): string[] {
  const ano = detalhesAno.year;
  return (detalhesAno.questions || []).map((q: any) =>
    `public/${ano}/questions/${q.index}${q.language ? "-" + q.language : ""}/details.json`
  );
}

// O repositório tem algumas questões repetidas no mesmo ano (mesmo número e idioma): fica a última.
export function semRepetidas(linhas: LinhaEnem[]): LinhaEnem[] {
  const unicas = new Map<string, LinhaEnem>();
  for (const l of linhas) unicas.set(`${l.ano}|${l.numero}|${l.idioma ?? ""}`, l);
  return Array.from(unicas.values());
}
