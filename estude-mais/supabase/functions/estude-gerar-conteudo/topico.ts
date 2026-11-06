// Aula de UM tópico: explicação, exemplo, macete, quiz e flashcards só daquele assunto.
// Gerada uma vez e reaproveitada por todos que estudam a matéria. Sem imports, pra ser testada fora do Deno.

export const PROMPT_TOPICO = `Você é o professor do app EstudeUp, para estudantes brasileiros do fundamental ao ENEM e à faculdade.
Vai preparar a aula de UM tópico de uma matéria, usando o material do aluno como base.
Fale SÓ do tópico pedido. Não repita o resumo geral da matéria e não entre nos outros tópicos (eles têm aula própria).
Responda SOMENTE com um JSON válido, sem texto antes ou depois, sem markdown, exatamente neste formato:
{
  "introducao": "1 parágrafo curto dizendo o que é o tópico e por que importa",
  "partes": [ { "titulo": "string", "texto": "explicação clara em 1 ou 2 parágrafos curtos" } ],
  "exemplo": "um exemplo resolvido ou do dia a dia, passo a passo",
  "macete": "um macete ou pegadinha comum de prova",
  "para_lembrar": ["frase curta", "frase curta", "frase curta"],
  "quiz": [ { "pergunta": "string", "opcoes": {"A": "string", "B": "string", "C": "string", "D": "string"}, "resposta_correta": "A", "explicacao": "por que está certa" } ],
  "flashcards": [ { "frente": "pergunta ou termo curto", "verso": "resposta direta em até 2 frases" } ]
}
Regras:
- "partes": de 2 a 4, cobrindo o tópico com mais profundidade do que o resumo geral.
- "quiz": EXATAMENTE 5 perguntas SÓ sobre este tópico, da mais fácil para a mais difícil, todas diferentes entre si e diferentes das perguntas já existentes que forem informadas.
- "flashcards": de 4 a 6, só sobre este tópico.
- Distribua a resposta correta entre A, B, C e D.
- Use o material como base; pode completar com conhecimento escolar correto do assunto, sem inventar dados.
- Português do Brasil, frases curtas, tom de professor gente boa.`;

const LETRAS = ["A", "B", "C", "D"];
const txt = (v: unknown, max = 2000) => (typeof v === "string" ? v.trim().slice(0, max) : "");

export type AulaTopico = {
  introducao: string;
  partes: { titulo: string; texto: string }[];
  exemplo: string;
  macete: string;
  para_lembrar: string[];
};

export function normalizarTopico(bruto: any) {
  if (!bruto || typeof bruto !== "object") throw new Error("a IA devolveu uma aula vazia, tenta de novo");
  const aula: AulaTopico = {
    introducao: txt(bruto.introducao, 1500),
    partes: (Array.isArray(bruto.partes) ? bruto.partes : [])
      .map((p: any) => ({ titulo: txt(p?.titulo, 120), texto: txt(p?.texto, 2500) }))
      .filter((p: { titulo: string; texto: string }) => p.titulo && p.texto).slice(0, 5),
    exemplo: txt(bruto.exemplo, 2000),
    macete: txt(bruto.macete, 800),
    para_lembrar: (Array.isArray(bruto.para_lembrar) ? bruto.para_lembrar : []).map((x: unknown) => txt(x, 300)).filter(Boolean).slice(0, 6),
  };
  const quiz = (Array.isArray(bruto.quiz) ? bruto.quiz : []).map((p: any) => {
    const opcoes: Record<string, string> = {};
    for (const l of LETRAS) { const t = txt(p?.opcoes?.[l], 500); if (!t) return null; opcoes[l] = t; }
    const correta = txt(p?.resposta_correta, 1).toUpperCase();
    const pergunta = txt(p?.pergunta, 1200);
    if (!pergunta || !LETRAS.includes(correta)) return null;
    return { pergunta, opcoes, resposta_correta: correta, explicacao: txt(p?.explicacao, 800) };
  }).filter(Boolean).slice(0, 8) as { pergunta: string; opcoes: Record<string, string>; resposta_correta: string; explicacao: string }[];
  const flashcards = (Array.isArray(bruto.flashcards) ? bruto.flashcards : [])
    .map((c: any) => ({ frente: txt(c?.frente, 300), verso: txt(c?.verso, 600) }))
    .filter((c: { frente: string; verso: string }) => c.frente && c.verso).slice(0, 8);
  if (!aula.introducao || !aula.partes.length || quiz.length < 3) throw new Error("a IA devolveu uma aula incompleta, tenta de novo");
  return { aula, quiz, flashcards };
}

async function ok<T>(p: PromiseLike<{ data: T; error: any }>, onde: string): Promise<T> {
  const { data, error } = await p;
  if (error) throw new Error(`${onde}: ${error.message || error}`);
  return data;
}

// monta o pedido pra IA: material da matéria + o tópico + o que já existe (pra não repetir)
export async function contextoTopico(admin: any, topicoId: string) {
  const t = await ok(admin.from("be_topicos").select("id, nome, materia_id").eq("id", topicoId).maybeSingle(), "ler tópico");
  if (!t) return null;
  const m = await ok(admin.from("be_materias").select("nome").eq("id", t.materia_id).single(), "ler matéria");
  const materiais = await ok(admin.from("be_materiais").select("texto_extraido, tipo").eq("materia_id", t.materia_id)
    .not("texto_extraido", "is", null), "ler materiais") || [];
  const outros = await ok(admin.from("be_topicos").select("nome").eq("materia_id", t.materia_id).neq("id", topicoId).order("ordem"), "ler tópicos") || [];
  const conteudos = await ok(admin.from("be_conteudo_gerado").select("id").eq("materia_id", t.materia_id), "ler conteúdo") || [];
  const geral = conteudos.length
    ? await ok(admin.from("be_quiz_perguntas").select("pergunta").in("conteudo_gerado_id", conteudos.map((c: any) => c.id)), "ler perguntas") || []
    : [];
  const texto = materiais.map((x: any) => `[${x.tipo}]\n${x.texto_extraido}`).join("\n\n").slice(0, 40000);
  const pedido = [
    `Matéria: ${m.nome}`,
    `TÓPICO DESTA AULA: ${t.nome}`,
    outros.length ? `Outros tópicos da matéria (NÃO explique estes aqui): ${outros.map((o: any) => o.nome).join("; ")}` : "",
    geral.length ? `Perguntas que já existem na matéria (não repita):\n- ${geral.map((g: any) => g.pergunta).slice(0, 30).join("\n- ")}` : "",
    texto ? `Material do aluno:\n\n${texto}` : "O aluno ainda não tem material escrito: use o conhecimento escolar do tópico.",
    `Agora prepare a aula do tópico "${t.nome}".`,
  ].filter(Boolean).join("\n\n");
  return { topico: t, pedido };
}

// grava aula, quiz e flashcards do tópico (se outra pessoa gerou ao mesmo tempo, fica a primeira)
export async function persistirTopico(admin: any, args: { topico: { id: string; materia_id: string }; usuarioId: string; gerado: ReturnType<typeof normalizarTopico> }) {
  const { topico, usuarioId, gerado } = args;
  const { data: ja } = await admin.from("be_topico_estudo").select("topico_id").eq("topico_id", topico.id).maybeSingle();
  if (ja) return false;
  const { error } = await admin.from("be_topico_estudo").insert({ topico_id: topico.id, materia_id: topico.materia_id, aula: gerado.aula });
  if (error) { if (String(error.code) === "23505") return false; throw new Error(`salvar aula: ${error.message}`); }
  const c = await ok(admin.from("be_conteudo_gerado").insert({ materia_id: topico.materia_id, topico_id: topico.id, tipo: "quiz_topico", conteudo: {} })
    .select("id").single(), "salvar quiz do tópico");
  await ok(admin.from("be_quiz_perguntas").insert(gerado.quiz.map((p, i) => ({
    conteudo_gerado_id: c.id, pergunta: p.pergunta, opcoes: p.opcoes, resposta_correta: p.resposta_correta,
    explicacao: p.explicacao || null, ordem: i, topico_id: topico.id,
  }))), "salvar perguntas do tópico");
  const existentes = await ok(admin.from("be_cards").select("frente").eq("materia_id", topico.materia_id), "ler cards") || [];
  const frentes = new Set(existentes.map((x: any) => x.frente.toLowerCase()));
  const novos = gerado.flashcards.filter((x) => { const k = x.frente.toLowerCase(); if (frentes.has(k)) return false; frentes.add(k); return true; })
    .map((x) => ({ materia_id: topico.materia_id, topico_id: topico.id, frente: x.frente, verso: x.verso, origem: "ia", criado_por: usuarioId }));
  if (novos.length) await ok(admin.from("be_cards").insert(novos), "salvar flashcards do tópico");
  return true;
}
