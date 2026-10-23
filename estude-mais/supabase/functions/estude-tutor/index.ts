import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "jsr:@supabase/supabase-js@2";
import { LIMITE_TUTOR_DIA, PROMPT_TUTOR, XP_TUTOR, XP_TUTOR_MAX_DIA, limparResposta, montarMensagens, tituloDaConversa, validarPedido } from "./nucleo.ts";

const ANTHROPIC_API_KEY = Deno.env.get("ANTHROPIC_API_KEY");
const MODELO = Deno.env.get("ESTUDE_MODELO") || "claude-sonnet-5-5";
const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!;
const SUPABASE_SERVICE_ROLE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;

const CORS = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
};
const resposta = (body: unknown, status = 200) =>
  new Response(JSON.stringify(body), { status, headers: { ...CORS, "Content-Type": "application/json" } });

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: CORS });
  try {
    const jwt = (req.headers.get("Authorization") || "").replace("Bearer ", "");
    if (!jwt) return resposta({ error: "não autenticado" }, 401);
    if (!ANTHROPIC_API_KEY) return resposta({ error: "ANTHROPIC_API_KEY não configurada nas secrets da função" }, 500);

    let pedido;
    try { pedido = validarPedido(await req.json()); } catch (e) { return resposta({ error: String((e as Error).message || e) }, 400); }

    const admin = createClient(SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY);
    const { data: auth, error: authErr } = await admin.auth.getUser(jwt);
    if (authErr || !auth.user) return resposta({ error: "sessão inválida, faça login de novo" }, 401);
    const { data: usuario } = await admin.from("be_usuarios").select("id").eq("auth_user_id", auth.user.id).single();
    if (!usuario) return resposta({ error: "usuário não encontrado" }, 401);

    // a conta do criador (be_criadores) não tem limite diário
    const { data: criador } = await admin.rpc("be_eh_criador", { p_usuario: usuario.id });
    const hoje = new Date().toISOString().slice(0, 10);
    const { data: uso } = await admin.from("be_uso_tutor").select("quantidade").eq("usuario_id", usuario.id).eq("data", hoje).maybeSingle();
    const usado = uso?.quantidade ?? 0;
    if (!criador && usado >= LIMITE_TUTOR_DIA) return resposta({ error: `Você já fez ${LIMITE_TUTOR_DIA} perguntas hoje. O tutor volta amanhã!` }, 429);

    // conversa: continua a do aluno ou abre uma nova
    let conversaId = pedido.conversaId;
    let historico: { papel: "aluno" | "tutor"; texto: string; tinha_foto: boolean }[] = [];
    if (conversaId) {
      const { data: c } = await admin.from("be_tutor_conversas").select("id, usuario_id").eq("id", conversaId).maybeSingle();
      if (!c || c.usuario_id !== usuario.id) return resposta({ error: "conversa não encontrada" }, 404);
      const { data: msgs } = await admin.from("be_tutor_mensagens").select("papel, texto, tinha_foto, created_at")
        .eq("conversa_id", conversaId).order("created_at", { ascending: true });
      historico = msgs || [];
    } else {
      const { data: nova, error } = await admin.from("be_tutor_conversas")
        .insert({ usuario_id: usuario.id, materia: pedido.materia, titulo: tituloDaConversa(pedido.texto, !!pedido.imagem) })
        .select("id").single();
      if (error) return resposta({ error: "não consegui abrir a conversa" }, 500);
      conversaId = nova.id;
    }

    const ia = await fetch("https://api.anthropic.com/v1/messages", {
      method: "POST",
      headers: { "x-api-key": ANTHROPIC_API_KEY, "anthropic-version": "2023-06-01", "content-type": "application/json" },
      body: JSON.stringify({ model: MODELO, max_tokens: 2500, system: PROMPT_TUTOR, messages: montarMensagens(historico, pedido) }),
    });
    if (!ia.ok) return resposta({ error: "o tutor não respondeu agora, tenta de novo", detalhe: await ia.text() }, 502);
    const iaJson = await ia.json();
    const bloco = (iaJson.content || []).find((b: { type: string }) => b.type === "text");
    const texto = limparResposta(bloco?.text || "");

    const textoAluno = pedido.texto || "Resolve esse exercício da foto, passo a passo.";
    const agora = Date.now();
    await admin.from("be_tutor_mensagens").insert([
      { conversa_id: conversaId, papel: "aluno", texto: textoAluno, tinha_foto: !!pedido.imagem, created_at: new Date(agora - 5).toISOString() },
      { conversa_id: conversaId, papel: "tutor", texto, created_at: new Date(agora).toISOString() },
    ]);
    await admin.from("be_tutor_conversas").update({ updated_at: new Date().toISOString() }).eq("id", conversaId);
    await admin.from("be_uso_tutor").upsert({ usuario_id: usuario.id, data: hoje, quantidade: usado + 1 });

    let xp = 0;
    const inicioDia = new Date(); inicioDia.setUTCHours(3, 0, 0, 0); // meia-noite em Brasília
    if (inicioDia.getTime() > Date.now()) inicioDia.setUTCDate(inicioDia.getUTCDate() - 1);
    const { count: xpHoje } = await admin.from("be_xp_eventos").select("id", { count: "exact", head: true })
      .eq("usuario_id", usuario.id).eq("tipo", "tutor").gte("created_at", inicioDia.toISOString());
    if ((xpHoje ?? 0) < XP_TUTOR_MAX_DIA) {
      await admin.rpc("be_ganhar_xp", { p_usuario: usuario.id, p_tipo: "tutor", p_pontos: XP_TUTOR, p_ref: conversaId });
      xp = XP_TUTOR;
    }
    const { data: minhasConversas } = await admin.from("be_tutor_conversas").select("id").eq("usuario_id", usuario.id);
    const ids = (minhasConversas || []).map((c: { id: string }) => c.id);
    if (ids.length) {
      const { count: perguntas } = await admin.from("be_tutor_mensagens").select("id", { count: "exact", head: true })
        .in("conversa_id", ids).eq("papel", "aluno");
      if ((perguntas ?? 0) >= 10) await admin.rpc("be_conceder_conquista", { p_usuario: usuario.id, p_codigo: "tutor_curioso" });
    }

    return resposta({ ok: true, conversa_id: conversaId, resposta: texto, xp, restantes: criador ? null : LIMITE_TUTOR_DIA - (usado + 1) });
  } catch (err) {
    return resposta({ error: "erro inesperado", detalhe: String(err) }, 500);
  }
});
