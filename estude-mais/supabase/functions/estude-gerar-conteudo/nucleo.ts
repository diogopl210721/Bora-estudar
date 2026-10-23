// Núcleo do Estude+: valida o JSON da IA e grava tudo no banco.
// Sem imports — recebe o cliente Supabase (service role) pronto, para poder ser testado fora do Deno.

export type Pergunta = {
  pergunta: string;
  opcoes: Record<string, string>;
  resposta_correta: string;
  explicacao?: string;
  topico?: string;
};

export type Gerado = {
  titulo: string;
  texto_bruto: string;
  resumo: string;
  topicos: string[];
  mapa_mental: { tema_central: string; ramos: { titulo: string; pontos: string[] }[] };
  curiosidades: string[];
  quiz: Pergunta[];
  prova: Pergunta[];
  flashcards: { frente: string; verso: string; topico?: string }[];
};

const LETRAS = ["A", "B", "C", "D"];

function texto(v: unknown, max = 2000): string {
  return typeof v === "string" ? v.trim().slice(0, max) : "";
}

// Lê a resposta da IA mesmo se vier com cercas de código ou texto em volta.
export function extrairJson(bruto: string): unknown {
  const semCerca = bruto.replace(/```json|```/g, "").trim();
  const ini = semCerca.indexOf("{");
  const fim = semCerca.lastIndexOf("}");
  if (ini < 0 || fim <= ini) throw new Error("a IA não devolveu JSON");
  return JSON.parse(semCerca.slice(ini, fim + 1));
}

function normalizarPergunta(p: any): Pergunta | null {
  if (!p || typeof p !== "object") return null;
  const pergunta = texto(p.pergunta, 1200);
  const opcoes: Record<string, string> = {};
  for (const l of LETRAS) {
    const t = texto(p.opcoes?.[l], 500);
    if (!t) return null;
    opcoes[l] = t;
  }
  const correta = texto(p.resposta_correta, 1).toUpperCase();
  if (!pergunta || !LETRAS.includes(correta)) return null;
  return { pergunta, opcoes, resposta_correta: correta, explicacao: texto(p.explicacao, 800), topico: texto(p.topico, 80) };
}

export function normalizarGerado(bruto: any): Gerado {
  if (!bruto || typeof bruto !== "object") throw new Error("resposta da IA vazia");
  const topicos = Array.from(new Set(
    (Array.isArray(bruto.topicos) ? bruto.topicos : []).map((t: unknown) => texto(t, 80)).filter(Boolean),
  )).slice(0, 8) as string[];

  const ramos = (Array.isArray(bruto.mapa_mental?.ramos) ? bruto.mapa_mental.ramos : [])
    .map((r: any) => ({
      titulo: texto(r?.titulo, 120),
      pontos: (Array.isArray(r?.pontos) ? r.pontos : []).map((x: unknown) => texto(x, 240)).filter(Boolean).slice(0, 6),
    }))
    .filter((r: { titulo: string }) => r.titulo)
    .slice(0, 8);

  const g: Gerado = {
    titulo: texto(bruto.titulo, 120) || "Matéria",
    texto_bruto: texto(bruto.texto_bruto, 8000),
    resumo: texto(bruto.resumo, 6000),
    topicos,
    mapa_mental: { tema_central: texto(bruto.mapa_mental?.tema_central, 120), ramos },
    curiosidades: (Array.isArray(bruto.curiosidades) ? bruto.curiosidades : []).map((c: unknown) => texto(c, 400)).filter(Boolean).slice(0, 6),
    quiz: (Array.isArray(bruto.quiz) ? bruto.quiz : []).map(normalizarPergunta).filter(Boolean).slice(0, 10) as Pergunta[],
    prova: (Array.isArray(bruto.prova) ? bruto.prova : []).map(normalizarPergunta).filter(Boolean).slice(0, 15) as Pergunta[],
    flashcards: (Array.isArray(bruto.flashcards) ? bruto.flashcards : [])
      .map((c: any) => ({ frente: texto(c?.frente, 300), verso: texto(c?.verso, 600), topico: texto(c?.topico, 80) }))
      .filter((c: { frente: string; verso: string }) => c.frente && c.verso)
      .slice(0, 25),
  };
  if (!g.resumo || g.quiz.length < 3) throw new Error("a IA devolveu um conteúdo incompleto, tenta de novo");
  return g;
}

async function ok<T>(p: PromiseLike<{ data: T; error: any }>, onde: string): Promise<T> {
  const { data, error } = await p;
  if (error) throw new Error(`${onde}: ${error.message || error}`);
  return data;
}

// Grava material, tópicos, conteúdo, perguntas e flashcards de uma matéria.
export async function persistirConteudo(
  admin: any,
  args: { usuarioId: string; materiaId: string; tipoFonte: string; url: string | null; gerado: Gerado },
) {
  const { usuarioId, materiaId, tipoFonte, url, gerado } = args;

  await ok(admin.from("be_materiais").insert({
    materia_id: materiaId, tipo: tipoFonte, url_externa: url,
    texto_extraido: gerado.texto_bruto || null, importado_por: usuarioId,
  }), "salvar material");

  // tópicos: reaproveita os que já existem (sem diferenciar maiúsculas)
  const existentes: { id: string; nome: string; ordem: number }[] =
    await ok(admin.from("be_topicos").select("id, nome, ordem").eq("materia_id", materiaId), "ler tópicos") || [];
  const porNome = new Map<string, string>();
  let proxOrdem = 0;
  for (const t of existentes) {
    porNome.set(t.nome.toLowerCase(), t.id);
    proxOrdem = Math.max(proxOrdem, (t.ordem ?? 0) + 1);
  }
  const citados = [
    ...gerado.topicos,
    ...gerado.quiz.map((p) => p.topico || ""),
    ...gerado.prova.map((p) => p.topico || ""),
    ...gerado.flashcards.map((c) => c.topico || ""),
  ].filter(Boolean);
  for (const nome of citados) {
    if (porNome.has(nome.toLowerCase()) || porNome.size >= 12) continue;
    const novo = await ok(admin.from("be_topicos").insert({ materia_id: materiaId, nome, ordem: proxOrdem++ }).select("id").single(), "criar tópico");
    porNome.set(nome.toLowerCase(), novo.id);
  }
  const topicoId = (nome?: string) => (nome ? porNome.get(nome.toLowerCase()) ?? null : null);

  // conteúdo gerado: substitui a versão anterior da matéria
  await ok(admin.from("be_conteudo_gerado").delete().eq("materia_id", materiaId), "limpar conteúdo antigo");
  await ok(admin.from("be_conteudo_gerado").insert([
    { materia_id: materiaId, tipo: "resumo", conteudo: { texto: gerado.resumo, titulo: gerado.titulo } },
    { materia_id: materiaId, tipo: "mapa_mental", conteudo: gerado.mapa_mental },
    { materia_id: materiaId, tipo: "curiosidades", conteudo: { lista: gerado.curiosidades } },
  ]), "salvar resumo");

  const salvarPerguntas = async (tipo: "quiz" | "prova", lista: Pergunta[]) => {
    if (!lista.length) return [];
    const conteudo = await ok(admin.from("be_conteudo_gerado")
      .insert({ materia_id: materiaId, tipo, conteudo: { titulo: gerado.titulo } }).select("id").single(), `salvar ${tipo}`);
    const linhas = lista.map((p, i) => ({
      conteudo_gerado_id: conteudo.id, pergunta: p.pergunta, opcoes: p.opcoes, resposta_correta: p.resposta_correta,
      explicacao: p.explicacao || null, ordem: i, topico_id: topicoId(p.topico),
    }));
    return await ok(admin.from("be_quiz_perguntas").insert(linhas).select("id, pergunta, opcoes, topico_id, ordem"), `salvar perguntas de ${tipo}`) || [];
  };
  const quiz = await salvarPerguntas("quiz", gerado.quiz);
  const prova = await salvarPerguntas("prova", gerado.prova);

  // flashcards novos (não duplica pela frente)
  const cardsExistentes: { frente: string }[] =
    await ok(admin.from("be_cards").select("frente").eq("materia_id", materiaId), "ler cards") || [];
  const frentes = new Set(cardsExistentes.map((c) => c.frente.toLowerCase()));
  const novosCards = gerado.flashcards
    .filter((c) => { const k = c.frente.toLowerCase(); if (frentes.has(k)) return false; frentes.add(k); return true; })
    .map((c) => ({ materia_id: materiaId, topico_id: topicoId(c.topico), frente: c.frente, verso: c.verso, origem: "ia", criado_por: usuarioId }));
  if (novosCards.length) await ok(admin.from("be_cards").insert(novosCards), "salvar flashcards");

  quiz.sort((a: any, b: any) => a.ordem - b.ordem);
  prova.sort((a: any, b: any) => a.ordem - b.ordem);
  return {
    titulo: gerado.titulo,
    resumo: gerado.resumo,
    mapa_mental: gerado.mapa_mental,
    curiosidades: gerado.curiosidades,
    topicos: Array.from(porNome.keys()).length,
    quiz,
    prova,
    cards_novos: novosCards.length,
  };
}
