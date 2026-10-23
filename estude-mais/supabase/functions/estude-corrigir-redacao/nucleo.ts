// Valida a correção devolvida pela IA: notas só nos degraus do ENEM (0 a 200, de 40 em 40).

const COMPETENCIAS = ["c1", "c2", "c3", "c4", "c5"] as const;

export type Correcao = {
  notas: Record<string, number>;
  total: number;
  comentarios: Record<string, string>;
  pontos_fortes: string[];
  melhorias: string[];
  paragrafo_reescrito: string;
};

function texto(v: unknown, max = 1500): string {
  return typeof v === "string" ? v.trim().slice(0, max) : "";
}

export function degrau(v: unknown): number {
  const n = Number(v);
  if (!Number.isFinite(n)) return 0;
  return Math.min(200, Math.max(0, Math.round(n / 40) * 40));
}

export function normalizarCorrecao(bruto: string): Correcao {
  const semCerca = bruto.replace(/```json|```/g, "").trim();
  const ini = semCerca.indexOf("{");
  const fim = semCerca.lastIndexOf("}");
  if (ini < 0 || fim <= ini) throw new Error("a IA não devolveu a correção em JSON");
  const j = JSON.parse(semCerca.slice(ini, fim + 1));
  if (!j?.notas) throw new Error("a correção veio sem notas, tenta de novo");

  const notas: Record<string, number> = {};
  const comentarios: Record<string, string> = {};
  for (const c of COMPETENCIAS) {
    notas[c] = degrau(j.notas[c]);
    comentarios[c] = texto(j.comentarios?.[c]);
  }
  const lista = (v: unknown, n: number) =>
    (Array.isArray(v) ? v : []).map((x) => texto(x, 400)).filter(Boolean).slice(0, n);

  return {
    notas,
    total: COMPETENCIAS.reduce((s, c) => s + notas[c], 0),
    comentarios,
    pontos_fortes: lista(j.pontos_fortes, 3),
    melhorias: lista(j.melhorias, 4),
    paragrafo_reescrito: texto(j.paragrafo_reescrito, 2000),
  };
}
