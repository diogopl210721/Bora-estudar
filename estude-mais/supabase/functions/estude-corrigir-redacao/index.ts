import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "jsr:@supabase/supabase-js@2";
import { normalizarCorrecao } from "./nucleo.ts";

const ANTHROPIC_API_KEY = Deno.env.get("ANTHROPIC_API_KEY");
const MODELO = Deno.env.get("ESTUDE_MODELO") || "claude-sonnet-5-5";
const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!;
const SUPABASE_SERVICE_ROLE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
const LIMITE_DIARIO = 7;

const CORS = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
};
const resposta = (body: unknown, status = 200) =>
  new Response(JSON.stringify(body), { status, headers: { ...CORS, "Content-Type": "application/json" } });

const PROMPT = `Você é um corretor experiente de redações do ENEM e avalia textos dissertativo-argumentativos de estudantes brasileiros.
Avalie a redação pelas 5 competências da matriz do ENEM, cada uma com nota em 0, 40, 80, 120, 160 ou 200:
C1 domínio da modalidade escrita formal da língua portuguesa;
C2 compreensão da proposta, tipo textual dissertativo-argumentativo e repertório sociocultural produtivo;
C3 seleção, relação, organização e interpretação de informações, fatos, opiniões e argumentos em defesa de um ponto de vista;
C4 conhecimento dos mecanismos linguísticos necessários para a construção da argumentação (coesão);
C5 proposta de intervenção para o problema, detalhada (agente, ação, meio/modo, efeito, detalhamento) e que respeite os direitos humanos.
Seja rigoroso e justo como a banca. Texto que foge totalmente do tema ou não é dissertativo-argumentativo recebe nota baixa em C2 e C3 e isso deve ser explicado.
Responda SOMENTE com JSON válido, sem texto antes ou depois:
{
  "notas": {"c1": 0, "c2": 0, "c3": 0, "c4": 0, "c5": 0},
  "comentarios": {"c1": "o que motivou a nota, com 1 exemplo do texto", "c2": "...", "c3": "...", "c4": "...", "c5": "..."},
  "pontos_fortes": ["até 3 itens"],
  "melhorias": ["até 4 ações concretas para subir a nota"],
  "paragrafo_reescrito": "um parágrafo do aluno reescrito como exemplo de melhoria"
}`;

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: CORS });
  try {
    const jwt = (req.headers.get("Authorization") || "").replace("Bearer ", "");
    if (!jwt) return resposta({ error: "não autenticado" }, 401);
    if (!ANTHROPIC_API_KEY) return resposta({ error: "ANTHROPIC_API_KEY não configurada nas secrets da função" }, 500);

    const { tema, texto } = await req.json();
    const temaLimpo = typeof tema === "string" ? tema.trim().slice(0, 300) : "";
    const textoLimpo = typeof texto === "string" ? texto.trim() : "";
    if (!temaLimpo) return resposta({ error: "escolhe ou escreve o tema da redação" }, 400);
    if (textoLimpo.length < 400) return resposta({ error: "a redação está curta demais pra corrigir (mínimo de umas 8 linhas)" }, 400);
    if (textoLimpo.length > 6000) return resposta({ error: "a redação passou do tamanho de uma folha do ENEM (30 linhas)" }, 400);

    const admin = createClient(SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY);
    const { data: auth, error: authErr } = await admin.auth.getUser(jwt);
    if (authErr || !auth.user) return resposta({ error: "sessão inválida, faça login de novo" }, 401);
    const { data: usuario } = await admin.from("be_usuarios").select("id").eq("auth_user_id", auth.user.id).single();
    if (!usuario) return resposta({ error: "usuário não encontrado" }, 401);

    // a conta do criador (be_criadores) não tem limite diário
    const { data: criador } = await admin.rpc("be_eh_criador", { p_usuario: usuario.id });
    const hoje = new Date().toISOString().slice(0, 10);
    const { data: uso } = await admin.from("be_uso_ia").select("quantidade").eq("usuario_id", usuario.id).eq("data", hoje).maybeSingle();
    const usado = uso?.quantidade ?? 0;
    if (!criador && usado >= LIMITE_DIARIO) {
      return resposta({ error: `Sua energia de hoje acabou (${LIMITE_DIARIO} usos de IA por dia). Ela recarrega amanhã!` }, 429);
    }

    const ia = await fetch("https://api.anthropic.com/v1/messages", {
      method: "POST",
      headers: { "x-api-key": ANTHROPIC_API_KEY, "anthropic-version": "2023-06-01", "content-type": "application/json" },
      body: JSON.stringify({
        model: MODELO, max_tokens: 4000, system: PROMPT,
        messages: [{ role: "user", content: `Tema: ${temaLimpo}\n\nRedação do aluno:\n\n${textoLimpo}` }],
      }),
    });
    if (!ia.ok) return resposta({ error: "erro ao corrigir com IA", detalhe: await ia.text() }, 502);
    const iaJson = await ia.json();
    const bloco = (iaJson.content || []).find((b: { type: string }) => b.type === "text");
    if (!bloco) return resposta({ error: "a IA não retornou texto" }, 502);

    let correcao;
    try {
      correcao = normalizarCorrecao(bloco.text);
    } catch (e) {
      return resposta({ error: String((e as Error).message || e) }, 502);
    }

    const { data: salva, error: erroSalvar } = await admin.from("be_redacoes").insert({
      usuario_id: usuario.id, tema: temaLimpo, texto: textoLimpo,
      notas: correcao.notas, total: correcao.total,
      feedback: { comentarios: correcao.comentarios, pontos_fortes: correcao.pontos_fortes, melhorias: correcao.melhorias, paragrafo_reescrito: correcao.paragrafo_reescrito },
    }).select("id, created_at").single();
    if (erroSalvar) return resposta({ error: "não consegui salvar a correção", detalhe: erroSalvar.message }, 500);

    await admin.rpc("be_incrementar_uso_ia", { p_usuario_id: usuario.id });
    await admin.rpc("be_ganhar_xp", { p_usuario: usuario.id, p_tipo: "redacao", p_pontos: 30, p_ref: salva.id });
    if (correcao.total >= 800) await admin.rpc("be_conceder_conquista", { p_usuario: usuario.id, p_codigo: "redacao_800" });

    return resposta({ ok: true, id: salva.id, ...correcao, xp: 30, energia_restante: criador ? null : LIMITE_DIARIO - (usado + 1) });
  } catch (err) {
    return resposta({ error: "erro inesperado", detalhe: String(err) }, 500);
  }
});
