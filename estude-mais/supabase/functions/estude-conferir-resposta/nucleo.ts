// Núcleo da resposta falada: o aluno fala a resposta do flashcard e a IA compara pelo sentido. Sem imports.

export const PROMPT_CONFERIR = `Você confere respostas de flashcards de alunos brasileiros. A resposta do aluno veio de reconhecimento de voz,
então ignore erros de digitação, pontuação e palavras trocadas por som parecido.
Compare pelo SENTIDO com a resposta esperada. Responda SOMENTE com JSON:
{"resultado": "certo" | "quase" | "errado", "comentario": "uma frase curta, em português, dizendo o que faltou ou confirmando", "nota": 1 a 4}
Regras da nota: 4 = certo e completo; 3 = certo com detalhe faltando; 2 = quase, ideia principal incompleta; 1 = errado ou "não sei".`;

function texto(v: unknown, max: number): string {
  return typeof v === "string" ? v.trim().slice(0, max) : "";
}

export function validarConferencia(corpo: any) {
  const pergunta = texto(corpo?.pergunta, 600);
  const esperado = texto(corpo?.esperado, 1200);
  const resposta = texto(corpo?.resposta, 1200);
  if (!pergunta || !esperado) throw new Error("faltou o flashcard");
  if (!resposta) throw new Error("não ouvi nada, tenta falar de novo");
  return { pergunta, esperado, resposta };
}

export function lerConferencia(bruto: string): { resultado: "certo" | "quase" | "errado"; comentario: string; nota: number } {
  const limpo = String(bruto || "").replace(/```json|```/g, "");
  const ini = limpo.indexOf("{");
  const fim = limpo.lastIndexOf("}");
  if (ini < 0 || fim <= ini) throw new Error("sem resposta");
  const j = JSON.parse(limpo.slice(ini, fim + 1));
  const resultado = ["certo", "quase", "errado"].includes(j.resultado) ? j.resultado : "quase";
  const padrao = resultado === "certo" ? 3 : resultado === "quase" ? 2 : 1;
  const nota = Number.isInteger(j.nota) && j.nota >= 1 && j.nota <= 4 ? j.nota : padrao;
  return { resultado, comentario: typeof j.comentario === "string" ? j.comentario.slice(0, 240) : "", nota };
}
