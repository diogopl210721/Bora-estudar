import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "jsr:@supabase/supabase-js@2";
import { validarTroca } from "./nucleo.ts";

// Só a conta do criador (tabela be_criadores) troca a senha de uma conta do Estude+ — pra quem esqueceu e não tem pergunta de segurança.
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

    let pedido;
    try { pedido = validarTroca(await req.json()); } catch (e) { return resposta({ error: String((e as Error).message || e) }, 400); }

    const admin = createClient(SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY);
    const { data: auth, error: authErr } = await admin.auth.getUser(jwt);
    if (authErr || !auth.user) return resposta({ error: "sessão inválida, faça login de novo" }, 401);
    const { data: eu } = await admin.from("be_usuarios").select("id").eq("auth_user_id", auth.user.id).single();
    if (!eu) return resposta({ error: "usuário não encontrado" }, 401);
    const { data: souCriador } = await admin.rpc("be_eh_criador", { p_usuario: eu.id });
    if (souCriador !== true) return resposta({ error: "só a conta do criador pode trocar a senha de outra pessoa" }, 403);

    const { data: alvo } = await admin.from("be_usuarios").select("id, auth_user_id").eq("id", pedido.usuarioId).maybeSingle();
    if (!alvo || !alvo.auth_user_id) return resposta({ error: "conta não encontrada" }, 404);
    const { data: alvoCriador } = await admin.rpc("be_eh_criador", { p_usuario: alvo.id });
    if (alvoCriador === true) return resposta({ error: "a senha da conta do criador só muda em Perfil → trocar senha" }, 403);

    const { error } = await admin.auth.admin.updateUserById(alvo.auth_user_id, { password: pedido.senha });
    if (error) return resposta({ error: "não consegui trocar a senha: " + error.message }, 500);
    return resposta({ ok: true });
  } catch (err) {
    return resposta({ error: "erro inesperado", detalhe: String(err) }, 500);
  }
});
