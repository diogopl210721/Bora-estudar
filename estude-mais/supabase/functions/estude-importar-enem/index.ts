import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "jsr:@supabase/supabase-js@2";
import { caminhosDoAno, montarQuestao, semRepetidas } from "./nucleo.ts";

// Importação única das questões oficiais do ENEM (repositório aberto yunger7/enem-api, fixado num commit).
// Chamada pelo próprio banco (pg_net), um ano por vez, com uma chave descartável guardada em be_import_chave.
const SHA = "938c56fbd3b391e03d93316c920a90c3e54842e5";
const RAW = `https://raw.githubusercontent.com/yunger7/enem-api/${SHA}/`;
const admin = createClient(Deno.env.get("SUPABASE_URL")!, Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!);

const resposta = (body: unknown, status = 200) =>
  new Response(JSON.stringify(body), { status, headers: { "Content-Type": "application/json" } });

async function buscarJson(caminho: string) {
  const r = await fetch(RAW + caminho);
  if (!r.ok) throw new Error(`${caminho}: ${r.status}`);
  return r.json();
}

Deno.serve(async (req) => {
  try {
    const { ano, chave } = await req.json();
    if (!Number.isInteger(ano) || ano < 2009 || ano > 2030 || typeof chave !== "string") {
      return resposta({ error: "parâmetros inválidos" }, 400);
    }
    const { data: ok } = await admin.from("be_import_chave").select("chave").eq("chave", chave).maybeSingle();
    if (!ok) return resposta({ error: "chave inválida" }, 403);

    const caminhos = caminhosDoAno(await buscarJson(`public/${ano}/details.json`));
    const linhas: ReturnType<typeof montarQuestao>[] = [];
    let puladas = 0;
    for (let i = 0; i < caminhos.length; i += 12) {
      const lote = await Promise.all(caminhos.slice(i, i + 12).map((c) => buscarJson(c).catch(() => null)));
      for (const q of lote) {
        const linha = q ? montarQuestao(q) : null;
        if (linha) linhas.push(linha); else puladas++;
      }
    }
    const { data: n, error } = await admin.rpc("be_enem_upsert", { p_chave: chave, p_linhas: semRepetidas(linhas as any) });
    if (error) return resposta({ error: error.message }, 500);
    return resposta({ ano, importadas: n, puladas, repetidas: linhas.length - semRepetidas(linhas as any).length });
  } catch (err) {
    return resposta({ error: String(err) }, 500);
  }
});
