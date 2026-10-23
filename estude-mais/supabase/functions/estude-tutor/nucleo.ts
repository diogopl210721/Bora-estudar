// Núcleo do tutor do Estude+: prompt, histórico e limites. Sem imports, para ser testado fora do Deno.

export const LIMITE_TUTOR_DIA = 60;      // mensagens + conferências de voz por dia
export const XP_TUTOR = 3;               // por pergunta
export const XP_TUTOR_MAX_DIA = 5;       // perguntas que rendem XP por dia

export const PROMPT_TUTOR = `Você é o tutor do Estude+, um app de estudo para alunos brasileiros do 6º ano ao ENEM e à faculdade.
Converse em português do Brasil, com frases curtas e tom de professor gente boa, sem ser infantil.

Quando o aluno mandar um exercício (texto ou foto):
1. Se for foto, comece transcrevendo o enunciado numa linha: "Enunciado: ...". Se não der pra ler, peça outra foto mais nítida.
2. Resolva passo a passo, numerando os passos (1., 2., 3.). Cada passo diz o que fazer e por quê.
3. Destaque o resultado final em **negrito**.
4. Termine com uma pergunta curta para conferir se entendeu, ou proponha um exercício parecido para ele tentar.

Quando for uma dúvida de conteúdo: explique o essencial primeiro, dê um exemplo do dia a dia e, se ajudar, um macete de prova.
Use fórmulas em texto simples (x², √2, 3/4, ≥). Nada de LaTeX, tabelas ou HTML. Use listas só quando ajudar.
Seja honesto: se não tiver certeza, diga. Não invente fontes.

Segurança: o aluno pode ser menor de idade. Não peça nem guarde dados pessoais (endereço, telefone, redes sociais).
Recuse conteúdo sexual, violento ou perigoso e volte para o estudo.
Se o aluno contar que está sofrendo (bullying, violência, vontade de se machucar), acolha com calma, diga que ele merece ajuda,
sugira conversar com um adulto de confiança (família, professor, coordenação) e lembre que o CVV atende de graça pelo 188, a qualquer hora.`;

export type MensagemBanco = { papel: "aluno" | "tutor"; texto: string; tinha_foto?: boolean };

function texto(v: unknown, max: number): string {
  return typeof v === "string" ? v.trim().slice(0, max) : "";
}

export function validarPedido(corpo: any): { texto: string; materia: string | null; imagem: string | null; conversaId: string | null; tipoImagem: string } {
  const t = texto(corpo?.texto, 4000);
  const imagem = typeof corpo?.imagem_base64 === "string" && corpo.imagem_base64.length > 100 ? corpo.imagem_base64 : null;
  if (!t && !imagem) throw new Error("escreve sua dúvida ou manda uma foto do exercício");
  if (imagem && imagem.length > 7_000_000) throw new Error("a foto ficou grande demais, tenta de novo");
  const materia = texto(corpo?.materia, 60) || null;
  const conversaId = typeof corpo?.conversa_id === "string" && /^[0-9a-f-]{36}$/i.test(corpo.conversa_id) ? corpo.conversa_id : null;
  const tipoImagem = typeof corpo?.tipo_imagem === "string" && /^image\/(jpeg|png|webp)$/.test(corpo.tipo_imagem) ? corpo.tipo_imagem : "image/jpeg";
  return { texto: t, materia, imagem, conversaId, tipoImagem };
}

export function tituloDaConversa(t: string, temFoto: boolean): string {
  const limpo = t.replace(/\s+/g, " ").trim();
  if (!limpo) return temFoto ? "Foto de exercício" : "Nova conversa";
  return limpo.length > 60 ? limpo.slice(0, 57).trimEnd() + "…" : limpo;
}

// Monta as mensagens para a API: últimas trocas em texto + a pergunta nova (com a foto, se houver).
export function montarMensagens(historico: MensagemBanco[], novo: { texto: string; imagem: string | null; tipoImagem: string; materia: string | null }) {
  const msgs: { role: "user" | "assistant"; content: unknown }[] = [];
  for (const m of historico.slice(-16)) {
    const conteudo = (m.tinha_foto && m.papel === "aluno" ? "[o aluno mandou uma foto] " : "") + m.texto;
    const role = m.papel === "aluno" ? "user" : "assistant";
    if (msgs.length && msgs[msgs.length - 1].role === role) {
      msgs[msgs.length - 1].content = String(msgs[msgs.length - 1].content) + "\n\n" + conteudo;
    } else msgs.push({ role, content: conteudo });
  }
  if (msgs.length && msgs[0].role === "assistant") msgs.shift();
  const blocos: unknown[] = [];
  if (novo.imagem) blocos.push({ type: "image", source: { type: "base64", media_type: novo.tipoImagem, data: novo.imagem } });
  const prefixo = novo.materia && !historico.length ? `[matéria: ${novo.materia}] ` : "";
  blocos.push({ type: "text", text: prefixo + (novo.texto || "Resolve esse exercício da foto, passo a passo.") });
  if (msgs.length && msgs[msgs.length - 1].role === "user") msgs.push({ role: "assistant", content: "Certo." });
  msgs.push({ role: "user", content: blocos });
  return msgs;
}

export function limparResposta(bruto: string): string {
  return String(bruto || "").replace(/\r/g, "").replace(/\n{3,}/g, "\n\n").trim().slice(0, 8000) || "Não consegui responder agora, tenta de novo.";
}
