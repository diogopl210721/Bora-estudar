import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "jsr:@supabase/supabase-js@2";
import { extrairJson, normalizarGerado, persistirConteudo } from "./nucleo.ts";
import { mensagemFonte, textoDoSite, transcricaoYoutube } from "./fontes.ts";

const ANTHROPIC_API_KEY = Deno.env.get("ANTHROPIC_API_KEY");
const MODELO = Deno.env.get("ESTUDE_MODELO") || "claude-sonnet-5-5";
const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!;
const SUPABASE_SERVICE_ROLE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
const SUPABASE_ANON_KEY = Deno.env.get("SUPABASE_ANON_KEY")!;
const LIMITE_DIARIO = 7;
const GEMINI = { chave: Deno.env.get("GEMINI_API_KEY") || "", modelo: Deno.env.get("GEMINI_MODELO") || "" };

const CORS = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
};
const resposta = (body: unknown, status = 200) =>
  new Response(JSON.stringify(body), { status, headers: { ...CORS, "Content-Type": "application/json" } });

const PROMPT = `Você é o motor de estudo do app EstudeUp, para estudantes brasileiros do fundamental ao ENEM e à faculdade.
Transforme o material enviado em conteúdo de estudo em português do Brasil.
Responda SOMENTE com um JSON válido, sem texto antes ou depois, sem markdown, exatamente neste formato:
{
  "titulo": "título curto do assunto",
  "texto_bruto": "transcrição fiel do material enviado AGORA (não invente)",
  "topicos": ["tópico 1", "tópico 2"],
  "resumo": "resumo de TODO o conteúdo da matéria (materiais anteriores + o novo) em 3 a 5 parágrafos curtos",
  "mapa_mental": { "tema_central": "string", "ramos": [ { "titulo": "string", "pontos": ["string"] } ] },
  "curiosidades": ["string", "string", "string"],
  "flashcards": [ { "frente": "pergunta ou termo curto", "verso": "resposta direta em até 2 frases", "topico": "um dos tópicos" } ],
  "quiz": [ { "pergunta": "string", "opcoes": {"A": "string", "B": "string", "C": "string", "D": "string"}, "resposta_correta": "A", "explicacao": "por que está certa", "topico": "um dos tópicos" } ],
  "prova": [ { "pergunta": "string", "opcoes": {"A": "string", "B": "string", "C": "string", "D": "string"}, "resposta_correta": "A", "explicacao": "por que está certa", "topico": "um dos tópicos" } ]
}
Regras:
- "topicos": de 3 a 6 tópicos que dividem a matéria em partes estudáveis em um dia cada. Se a lista de tópicos já existentes for informada, REUSE exatamente os mesmos nomes quando o assunto for o mesmo.
- Todo item de quiz, prova e flashcards deve ter "topico" igual a um nome da lista "topicos".
- "quiz": EXATAMENTE 6 perguntas rápidas, dificuldade crescente, cobrindo os tópicos.
- "prova": EXATAMENTE 10 perguntas mais completas, simulando uma prova real sobre todo o conteúdo.
- "flashcards": de 10 a 15 cartões de memorização ativa (definições, fórmulas, datas, causas e consequências). A frente pede para lembrar, não para reconhecer.
- Distribua a resposta correta entre A, B, C e D.
- mapa_mental com 3 a 6 ramos refletindo todo o conteúdo.
- Nunca invente conteúdo sem relação com o material.`;

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: CORS });
  try {
    const jwt = (req.headers.get("Authorization") || "").replace("Bearer ", "");
    if (!jwt) return resposta({ error: "não autenticado" }, 401);
    if (!ANTHROPIC_API_KEY) return resposta({ error: "ANTHROPIC_API_KEY não configurada nas secrets da função" }, 500);

    const { materia_id, tipo_fonte, imagem_base64, pdf_base64, url, texto, apenas_testar_fonte } = await req.json();
    if (!tipo_fonte || (!materia_id && !apenas_testar_fonte)) return resposta({ error: "materia_id e tipo_fonte são obrigatórios" }, 400);

    const admin = createClient(SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY);
    const comoUsuario = createClient(SUPABASE_URL, SUPABASE_ANON_KEY, { global: { headers: { Authorization: `Bearer ${jwt}` } } });

    const { data: auth, error: authErr } = await admin.auth.getUser(jwt);
    if (authErr || !auth.user) return resposta({ error: "sessão inválida, faça login de novo" }, 401);
    const { data: usuario } = await admin.from("be_usuarios").select("id").eq("auth_user_id", auth.user.id).single();
    if (!usuario) return resposta({ error: "usuário não encontrado" }, 401);

    // só confere se o vídeo ou o site dá pra ler (sem IA e sem gastar energia)
    if (apenas_testar_fonte) {
      if (tipo_fonte !== "youtube" && tipo_fonte !== "link") return resposta({ error: "só dá pra testar YouTube e site" }, 400);
      const r = tipo_fonte === "youtube" ? await transcricaoYoutube(url, GEMINI) : await textoDoSite(url);
      return resposta({
        ok: !!r.texto, motivo: r.motivo, detalhe: r.detalhe || null, caracteres: r.texto?.length || 0,
        inicio: r.texto ? r.texto.slice(0, 160) : null, mensagem: r.texto ? null : mensagemFonte(tipo_fonte, r),
      });
    }

    const { data: acesso } = await admin.rpc("be_materia_acessivel_para", { p_usuario: usuario.id, p_materia: materia_id });
    if (!acesso) return resposta({ error: "matéria não encontrada" }, 404);
    // na turma do professor só ele adiciona material; no grupo de amigos, qualquer membro
    const { data: podeEditar } = await admin.rpc("be_pode_editar_materia_para", { p_usuario: usuario.id, p_materia: materia_id });
    if (!podeEditar) return resposta({ error: "Nessa turma só o professor adiciona material." }, 403);

    // a conta do criador (be_criadores) não tem limite diário
    const { data: criador } = await admin.rpc("be_eh_criador", { p_usuario: usuario.id });
    const hoje = new Date().toISOString().slice(0, 10);
    const { data: uso } = await admin.from("be_uso_ia").select("quantidade").eq("usuario_id", usuario.id).eq("data", hoje).maybeSingle();
    const usado = uso?.quantidade ?? 0;
    if (!criador && usado >= LIMITE_DIARIO) {
      return resposta({ error: `Sua energia de hoje acabou (${LIMITE_DIARIO} gerações por dia). Ela recarrega amanhã!` }, 429);
    }

    const blocos: Record<string, unknown>[] = [];
    const { data: anteriores } = await admin.from("be_materiais").select("texto_extraido, tipo")
      .eq("materia_id", materia_id).not("texto_extraido", "is", null);
    if (anteriores?.length) {
      const contexto = anteriores.map((m: any) => `[material anterior - ${m.tipo}]\n${m.texto_extraido}`).join("\n\n").slice(0, 30000);
      blocos.push({ type: "text", text: `Materiais já estudados nessa matéria (considere no resumo, mapa, quiz e prova):\n\n${contexto}` });
    }
    const { data: topicosAtuais } = await admin.from("be_topicos").select("nome").eq("materia_id", materia_id).order("ordem");
    if (topicosAtuais?.length) {
      blocos.push({ type: "text", text: `Tópicos já existentes nessa matéria: ${topicosAtuais.map((t: any) => t.nome).join("; ")}` });
    }

    if (tipo_fonte === "foto") {
      if (!imagem_base64) return resposta({ error: "faltou a imagem" }, 400);
      blocos.push({ type: "image", source: { type: "base64", media_type: "image/jpeg", data: imagem_base64 } });
      blocos.push({ type: "text", text: "Foto de caderno ou material de estudo. Leia tudo, inclusive letra à mão, e gere o conteúdo pedido." });
    } else if (tipo_fonte === "pdf") {
      if (!pdf_base64) return resposta({ error: "faltou o PDF" }, 400);
      blocos.push({ type: "document", source: { type: "base64", media_type: "application/pdf", data: pdf_base64 } });
      blocos.push({ type: "text", text: "PDF de material de estudo. Leia e gere o conteúdo pedido." });
    } else if (tipo_fonte === "youtube") {
      const colada = typeof texto === "string" ? texto.trim() : "";
      if (colada.length >= 80) {
        // o aluno colou a transcrição do vídeo (Mostrar transcrição no YouTube)
        blocos.push({ type: "text", text: `Transcrição de uma aula do YouTube, colada pelo aluno${url ? ` (${String(url).slice(0, 200)})` : ""}:\n\n${colada.slice(0, 20000)}\n\nGere o conteúdo pedido.` });
      } else {
        if (!url) return resposta({ error: "faltou o link do vídeo" }, 400);
        const r = await transcricaoYoutube(url, GEMINI);
        if (!r.texto) return resposta({ error: mensagemFonte("youtube", r), motivo: r.motivo, detalhe: r.detalhe }, 422);
        blocos.push({ type: "text", text: `Transcrição de uma aula do YouTube:\n\n${r.texto}\n\nGere o conteúdo pedido.` });
      }
    } else if (tipo_fonte === "link") {
      if (!url) return resposta({ error: "faltou o link" }, 400);
      const r = await textoDoSite(url);
      if (!r.texto) return resposta({ error: mensagemFonte("link", r), motivo: r.motivo, detalhe: r.detalhe }, 422);
      blocos.push({ type: "text", text: `Conteúdo de uma página de estudo:\n\n${r.texto}\n\nGere o conteúdo pedido.` });
    } else if (tipo_fonte === "texto") {
      const t = typeof texto === "string" ? texto.trim() : "";
      if (t.length < 80) return resposta({ error: "cola um texto um pouco maior (pelo menos 80 caracteres)" }, 400);
      blocos.push({ type: "text", text: `Anotações coladas pelo aluno:\n\n${t.slice(0, 20000)}\n\nGere o conteúdo pedido.` });
    } else {
      return resposta({ error: "tipo_fonte inválido" }, 400);
    }

    const ia = await fetch("https://api.anthropic.com/v1/messages", {
      method: "POST",
      headers: { "x-api-key": ANTHROPIC_API_KEY, "anthropic-version": "2023-06-01", "content-type": "application/json" },
      body: JSON.stringify({ model: MODELO, max_tokens: 16000, system: PROMPT, messages: [{ role: "user", content: blocos }] }),
    });
    if (!ia.ok) return resposta({ error: "erro ao gerar conteúdo com IA", detalhe: await ia.text() }, 502);
    const iaJson = await ia.json();
    const bloco = (iaJson.content || []).find((b: { type: string }) => b.type === "text");
    if (!bloco) return resposta({ error: "a IA não retornou texto" }, 502);

    let gerado;
    try {
      gerado = normalizarGerado(extrairJson(bloco.text));
    } catch (e) {
      return resposta({ error: String((e as Error).message || e) }, 502);
    }

    const salvo = await persistirConteudo(admin, {
      usuarioId: usuario.id, materiaId: materia_id, tipoFonte: tipo_fonte,
      url: tipo_fonte === "youtube" || tipo_fonte === "link" ? url : null, gerado,
    });

    await admin.rpc("be_incrementar_uso_ia", { p_usuario_id: usuario.id });
    await admin.rpc("be_ganhar_xp", { p_usuario: usuario.id, p_tipo: "material", p_pontos: 20, p_ref: materia_id });

    const { count: nMateriais } = await admin.from("be_materiais").select("id", { count: "exact", head: true }).eq("importado_por", usuario.id);
    if ((nMateriais ?? 0) >= 5) await admin.rpc("be_conceder_conquista", { p_usuario: usuario.id, p_codigo: "cinco_mapas_mentais" });
    const { count: nMaterias } = await admin.from("be_materias").select("id", { count: "exact", head: true }).eq("usuario_id", usuario.id);
    if ((nMaterias ?? 0) >= 10) await admin.rpc("be_conceder_conquista", { p_usuario: usuario.id, p_codigo: "dez_materias" });

    // plano de prova: monta (ou refaz) se a matéria tem data de prova futura
    let plano: number | null = null;
    const { data: materia } = await admin.from("be_materias").select("data_prova").eq("id", materia_id).single();
    if (materia?.data_prova && materia.data_prova >= hoje) {
      const { data: n } = await comoUsuario.rpc("be_gerar_plano", { p_materia: materia_id });
      plano = typeof n === "number" ? n : null;
    }

    return resposta({ ok: true, ...salvo, plano_tarefas: plano, energia_restante: criador ? null : LIMITE_DIARIO - (usado + 1) });
  } catch (err) {
    return resposta({ error: "erro inesperado", detalhe: String(err) }, 500);
  }
});
