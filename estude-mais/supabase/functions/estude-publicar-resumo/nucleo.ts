// Núcleo da publicação na biblioteca: validação, filtro de contato e leitura da moderação. Sem imports.

export const CORES = ["azul", "verde", "rosa", "laranja", "roxo", "amarelo"];
export const SERIES = ["6º ano", "7º ano", "8º ano", "9º ano", "1º EM", "2º EM", "3º EM", "Cursinho", "Faculdade"];
export const LIMITE_PUBLICACOES_DIA = 10;
export const XP_PUBLICAR = 25;

// mesmo filtro das salas: nada de link, e-mail, @ de rede social ou telefone
// telefone no formato brasileiro, sem pegar datas e contas ("1914-1918", "1500, 1822 e 1889")
const CONTATO = /(https?:\/\/|www\.|\b[a-z0-9-]+\.(com|net|org|br|io|me|ly|gg|app|xyz)\b|[a-z0-9._%+-]+@[a-z0-9.-]+\.[a-z]{2,}|(^|\s)@[a-z0-9_.]{3,}|(?<![\d.,])\(?\d{2}\)?[\s.-]?9?[\s.]?\d{4}[\s.-]?\d{4}\b|\b9\d{4}[\s.-]?\d{4}\b|(?<![\d.,])\d{10,11}(?!\d))/i;

export const PROMPT_MODERACAO = `Você modera a biblioteca de resumos do EstudeUp, usada por alunos brasileiros a partir de 12 anos.
Leia o resumo e decida se ele pode ser publicado. Responda SOMENTE com JSON: {"aprovado": true ou false, "motivo": "frase curta para o aluno, em português"}.
Reprove quando houver: conteúdo sexual; violência explícita ou incentivo a se machucar; discurso de ódio ou preconceito;
ofensa, bullying ou exposição de uma pessoa real (colega, professor) pelo nome; dados pessoais ou de contato; propaganda, spam ou venda;
texto sem relação com estudo; texto vazio, só repetido ou sem sentido.
Aprove resumos escolares normais, mesmo curtos, informais ou com pequenos erros de conteúdo. Temas históricos ou científicos sensíveis (guerras, escravidão, sexualidade na biologia) são permitidos quando tratados como matéria escolar.`;

function texto(v: unknown, max: number): string {
  return typeof v === "string" ? v.replace(/\r/g, "").trim().slice(0, max) : "";
}

export type Publicacao = { titulo: string; materia: string; serie: string | null; conteudo: string; cartoes: { frente: string; verso: string }[]; cor: string; materiaId: string | null };

export function validarPublicacao(corpo: any): Publicacao {
  const titulo = texto(corpo?.titulo, 120);
  const materia = texto(corpo?.materia, 60);
  const conteudo = texto(corpo?.conteudo, 20000);
  const serie = SERIES.includes(corpo?.serie) ? corpo.serie : null;
  const cor = CORES.includes(corpo?.cor) ? corpo.cor : CORES[Math.floor(Math.random() * CORES.length)];
  const cartoes = (Array.isArray(corpo?.cartoes) ? corpo.cartoes : [])
    .map((c: any) => ({ frente: texto(c?.frente, 300), verso: texto(c?.verso, 600) }))
    .filter((c: { frente: string; verso: string }) => c.frente && c.verso)
    .slice(0, 40);
  if (titulo.length < 3) throw new Error("dá um título pro seu resumo");
  if (materia.length < 2) throw new Error("diz de qual matéria é o resumo");
  if (conteudo.length < 80) throw new Error("o resumo está curto demais (escreve pelo menos umas 2 linhas)");
  const tudo = [titulo, materia, conteudo, ...cartoes.flatMap((c: { frente: string; verso: string }) => [c.frente, c.verso])].join("\n");
  if (CONTATO.test(tudo)) throw new Error("pra proteger todo mundo, resumo não pode ter link, e-mail, @ de rede social ou telefone");
  const materiaId = typeof corpo?.materia_id === "string" && /^[0-9a-f-]{36}$/i.test(corpo.materia_id) ? corpo.materia_id : null;
  return { titulo, materia, serie, conteudo, cartoes, cor, materiaId };
}

export function textoParaModerar(p: Publicacao): string {
  const cards = p.cartoes.map((c) => `- ${c.frente} → ${c.verso}`).join("\n");
  return `Título: ${p.titulo}\nMatéria: ${p.materia}\nSérie: ${p.serie || "não informada"}\n\n${p.conteudo.slice(0, 12000)}${cards ? "\n\nFlashcards:\n" + cards.slice(0, 4000) : ""}`;
}

export function lerModeracao(bruto: string): { aprovado: boolean; motivo: string } {
  const limpo = String(bruto || "").replace(/```json|```/g, "");
  const ini = limpo.indexOf("{");
  const fim = limpo.lastIndexOf("}");
  if (ini < 0 || fim <= ini) throw new Error("moderação sem resposta");
  const j = JSON.parse(limpo.slice(ini, fim + 1));
  return { aprovado: j.aprovado === true, motivo: typeof j.motivo === "string" ? j.motivo.slice(0, 300) : "" };
}

// "25/10 às 14:30" no horário de Brasília (mensagem pra quem está silenciado)
export function dataHora(iso: string): string {
  const d = new Date(iso);
  const dia = d.toLocaleDateString("pt-BR", { timeZone: "America/Sao_Paulo", day: "2-digit", month: "2-digit" });
  const hora = d.toLocaleTimeString("pt-BR", { timeZone: "America/Sao_Paulo", hour: "2-digit", minute: "2-digit" });
  return `${dia} às ${hora}`;
}
