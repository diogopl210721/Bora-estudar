import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "jsr:@supabase/supabase-js@2";
import { PROMPT_CONFERIR, lerConferencia, validarConferencia } from "./nucleo.ts";

const ANTHROPIC_API_KEY = Deno.env.get("ANTHROPIC_API_KEY");
const MODELO_RAPIDO = Deno.env.get("ESTUDE_MODELO_RAPIDO") || "claude-haiku-5-5";
const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!;
const SUPABASE_SERVICE_ROLE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
const LIMITE_TUTOR_DIA = 60; // mesmo limite diário do tutor (as duas usam be_uso_tutor)

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

    let c;
    try { c = validarConferencia(await req.json()); } catch (e) { return resposta({ error: String((e as Error).message || e) }, 400); }

    const admin = createClient(SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY);
    const { data: auth, error: authErr } = await admin.auth.getUser(jwt);
    if (authErr || !auth.user) return resposta({ error: "sessão inválida, faça login de novo" }, 401);
    const { data: usuario } = await admin.from("be_usuarios").select("id").eq("auth_user_id", auth.user.id).single();
    if (!usuario) return resposta({ error: "usuário não encontrado" }, 401);

    const hoje = new Date().toISOString().slice(0, 10);
    const { data: uso } = await admin.from("be_uso_tutor").select("quantidade").eq("usuario_id", usuario.id).eq("data", hoje).maybeSingle();
    const usado = uso?.quantidade ?? 0;
    if (usado >= LIMITE_TUTOR_DIA) return resposta({ error: "Limite de conferências por voz de hoje atingido. Avalie o card nos botões." }, 429);

    const ia = await fetch("https://api.anthropic.com/v1/messages", {
      method: "POST",
      headers: { "x-api-key": ANTHROPIC_API_KEY, "anthropic-version": "2023-06-01", "content-type": "application/json" },
      body: JSON.stringify({
        model: MODELO_RAPIDO, max_tokens: 200, system: PROMPT_CONFERIR,
        messages: [{ role: "user", content: `Pergunta: ${c.pergunta}\nResposta esperada: ${c.esperado}\nResposta do aluno: ${c.resposta}` }],
      }),
    });
    if (!ia.ok) return resposta({ error: "não consegui conferir agora, avalie nos botões" }, 502);
    const iaJson = await ia.json();
    let r;
    try { r = lerConferencia((iaJson.content || []).find((b: { type: string }) => b.type === "text")?.text || ""); }
    catch { return resposta({ error: "não consegui conferir agora, avalie nos botões" }, 502); }
    await admin.from("be_uso_tutor").upsert({ usuario_id: usuario.id, data: hoje, quantidade: usado + 1 });
    return resposta({ ok: true, ...r });
  } catch (err) {
    return resposta({ error: "erro inesperado", detalhe: String(err) }, 500);
  }
});
