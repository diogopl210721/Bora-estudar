import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "jsr:@supabase/supabase-js@2";
import { LIMITE_CADASTROS_HORA_IP, LIMITE_CADASTROS_HORA_TOTAL, hashIp, jaExiste, validarCadastro } from "./nucleo.ts";

// Cria a conta já confirmada (sem e-mail de confirmação). O app entra logo depois com e-mail e senha.
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
  if (req.method !== "POST") return resposta({ error: "use POST" }, 405);
  try {
    let dados;
    try { dados = validarCadastro(await req.json()); } catch (e) { return resposta({ error: String((e as Error).message || e) }, 400); }

    const admin = createClient(SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY);

    // limite de contas novas por endereço e no total, pra robô não encher o banco
    const ip = (req.headers.get("x-forwarded-for") || "").split(",")[0].trim() || "sem-ip";
    const ipHash = await hashIp(ip);
    const umaHora = new Date(Date.now() - 3600 * 1000).toISOString();
    const { count: doIp } = await admin.from("be_cadastro_tentativas").select("id", { count: "exact", head: true })
      .eq("ip_hash", ipHash).gte("created_at", umaHora);
    const { count: total } = await admin.from("be_cadastro_tentativas").select("id", { count: "exact", head: true })
      .gte("created_at", umaHora);
    if ((doIp ?? 0) >= LIMITE_CADASTROS_HORA_IP || (total ?? 0) >= LIMITE_CADASTROS_HORA_TOTAL) {
      return resposta({ error: "Muitas contas criadas daqui agora. Espera um pouco e tenta de novo." }, 429);
    }
    await admin.from("be_cadastro_tentativas").insert({ ip_hash: ipHash });

    const { error } = await admin.auth.admin.createUser({
      email: dados.email,
      password: dados.senha,
      email_confirm: true,
      user_metadata: { nome: dados.nome, origem: "estude+" },
    });
    if (jaExiste(error)) return resposta({ error: "Já existe uma conta com esse e-mail. Entra com sua senha ou toca em \"esqueci minha senha\"." }, 409);
    if (error) return resposta({ error: "não consegui criar a conta: " + error.message }, 500);

    return resposta({ ok: true });
  } catch (err) {
    return resposta({ error: "erro inesperado", detalhe: String(err) }, 500);
  }
});
