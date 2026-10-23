import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "jsr:@supabase/supabase-js@2";
import { LIMITE_PUBLICACOES_DIA, PROMPT_MODERACAO, XP_PUBLICAR, lerModeracao, textoParaModerar, validarPublicacao } from "./nucleo.ts";

// Publica um resumo na biblioteca só depois de a IA moderar (o app é usado por menores de idade).
const ANTHROPIC_API_KEY = Deno.env.get("ANTHROPIC_API_KEY");
const MODELO_RAPIDO = Deno.env.get("ESTUDE_MODELO_RAPIDO") || "claude-haiku-5-5";
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

    let pub;
    try { pub = validarPublicacao(await req.json()); } catch (e) { return resposta({ error: String((e as Error).message || e) }, 400); }

    const admin = createClient(SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY);
    const { data: auth, error: authErr } = await admin.auth.getUser(jwt);
    if (authErr || !auth.user) return resposta({ error: "sessão inválida, faça login de novo" }, 401);
    const { data: usuario } = await admin.from("be_usuarios").select("id").eq("auth_user_id", auth.user.id).single();
    if (!usuario) return resposta({ error: "usuário não encontrado" }, 401);

    const desde = new Date(Date.now() - 24 * 3600 * 1000).toISOString();
    const { count: hoje } = await admin.from("be_resumos").select("id", { count: "exact", head: true })
      .eq("autor_id", usuario.id).gte("created_at", desde);
    if ((hoje ?? 0) >= LIMITE_PUBLICACOES_DIA) return resposta({ error: `Você já publicou ${LIMITE_PUBLICACOES_DIA} resumos nas últimas 24 horas. Amanhã tem mais!` }, 429);

    if (pub.materiaId) {
      const { data: acesso } = await admin.rpc("be_materia_acessivel_para", { p_usuario: usuario.id, p_materia: pub.materiaId });
      if (!acesso) pub.materiaId = null;
    }

    const ia = await fetch("https://api.anthropic.com/v1/messages", {
      method: "POST",
      headers: { "x-api-key": ANTHROPIC_API_KEY, "anthropic-version": "2023-06-01", "content-type": "application/json" },
      body: JSON.stringify({ model: MODELO_RAPIDO, max_tokens: 300, system: PROMPT_MODERACAO, messages: [{ role: "user", content: textoParaModerar(pub) }] }),
    });
    if (!ia.ok) return resposta({ error: "não consegui revisar o resumo agora, tenta de novo daqui a pouco" }, 502);
    const iaJson = await ia.json();
    let mod;
    try { mod = lerModeracao((iaJson.content || []).find((b: { type: string }) => b.type === "text")?.text || ""); }
    catch { return resposta({ error: "não consegui revisar o resumo agora, tenta de novo daqui a pouco" }, 502); }

    const { data: r, error } = await admin.from("be_resumos").insert({
      autor_id: usuario.id, titulo: pub.titulo, materia: pub.materia, serie: pub.serie, conteudo: pub.conteudo,
      cartoes: pub.cartoes, cor: pub.cor, origem_materia_id: pub.materiaId,
      status: mod.aprovado ? "publicado" : "recusado", motivo_moderacao: mod.aprovado ? null : (mod.motivo || "não passou na revisão"),
    }).select("id, status").single();
    if (error) return resposta({ error: "não consegui salvar: " + error.message }, 500);

    let xp = 0;
    if (mod.aprovado) {
      await admin.rpc("be_ganhar_xp", { p_usuario: usuario.id, p_tipo: "resumo_publicado", p_pontos: XP_PUBLICAR, p_ref: r.id });
      await admin.rpc("be_conceder_conquista", { p_usuario: usuario.id, p_codigo: "primeiro_resumo" });
      xp = XP_PUBLICAR;
    }
    return resposta({ ok: true, id: r.id, publicado: mod.aprovado, motivo: mod.aprovado ? null : mod.motivo, xp });
  } catch (err) {
    return resposta({ error: "erro inesperado", detalhe: String(err) }, 500);
  }
});
