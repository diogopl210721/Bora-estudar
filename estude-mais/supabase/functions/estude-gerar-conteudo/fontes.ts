// Leitura das fontes externas do EstudeUp: transcrição de vídeo do YouTube e texto de site.
// Sem imports — usa só fetch, pra poder ser testado fora do Deno.

export type Resultado = { texto: string | null; motivo: string; detalhe?: string };

// ---------------- YouTube ----------------
export function idDoYoutube(url: string): string | null {
  const bruto = String(url || "").trim();
  const valido = (v: string | null) => (v && /^[a-zA-Z0-9_-]{11}$/.test(v) ? v : null);
  try {
    const u = new URL(/^https?:\/\//i.test(bruto) ? bruto : "https://" + bruto);
    const host = u.hostname.toLowerCase().replace(/^(www|m|music)\./, "");
    if (host === "youtu.be") return valido(u.pathname.split("/")[1] || null);
    if (host === "youtube.com" || host === "youtube-nocookie.com") {
      const v = valido(u.searchParams.get("v"));
      if (v) return v;
      const m = u.pathname.match(/^\/(?:shorts|embed|live|v|e)\/([a-zA-Z0-9_-]{11})/);
      if (m) return m[1];
    }
  } catch { /* cai na busca solta */ }
  const m = bruto.match(/(?:[?&]v=|youtu\.be\/|\/(?:shorts|embed|live)\/)([a-zA-Z0-9_-]{11})/);
  return m ? m[1] : null;
}

// clientes do player do YouTube; o primeiro que devolver legenda vale
const CLIENTES = [
  {
    nome: "ANDROID", versao: "20.10.38", numero: "3",
    ua: "com.google.android.youtube/20.10.38 (Linux; U; Android 14) gzip",
    extra: { androidSdkVersion: 34, osName: "Android", osVersion: "14" },
  },
  {
    nome: "IOS", versao: "20.10.4", numero: "5",
    ua: "com.google.ios.youtube/20.10.4 (iPhone16,2; U; CPU iOS 18_3_2 like Mac OS X;)",
    extra: { deviceMake: "Apple", deviceModel: "iPhone16,2", osName: "iPhone", osVersion: "18.3.2.22D82" },
  },
  {
    nome: "WEB_EMBEDDED_PLAYER", versao: "1.20250310.01.00", numero: "56",
    ua: "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/134.0 Safari/537.36",
    extra: {}, embed: true,
  },
  {
    nome: "WEB", versao: "2.20250312.04.00", numero: "1",
    ua: "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/134.0 Safari/537.36",
    extra: {},
  },
];

type Trilha = { baseUrl?: string; languageCode?: string; kind?: string };

function escolherTrilha(trilhas: Trilha[]): Trilha | null {
  if (!trilhas?.length) return null;
  const manual = (l: string) => trilhas.find((t) => (t.languageCode || "").startsWith(l) && t.kind !== "asr");
  const auto = (l: string) => trilhas.find((t) => (t.languageCode || "").startsWith(l));
  return manual("pt") || auto("pt") || manual("en") || auto("en") || manual("es") || trilhas[0];
}

export function textoDaLegenda(bruto: string): string {
  const s = String(bruto || "").trim();
  let partes: string[] = [];
  if (s.startsWith("{")) {
    try {
      const j = JSON.parse(s);
      partes = (j.events || []).map((e: any) => (e.segs || []).map((g: any) => g.utf8 || "").join(""));
    } catch { partes = []; }
  } else {
    partes = Array.from(s.matchAll(/<(?:text|p)\b[^>]*>([\s\S]*?)<\/(?:text|p)>/g)).map((m) => m[1].replace(/<[^>]+>/g, ""));
  }
  return decodificar(decodificar(partes.join(" "))).replace(/\[(música|music|aplausos|applause|risos)\]/gi, " ").replace(/\s+/g, " ").trim();
}

const ENTIDADES: Record<string, string> = {
  aacute: "á", eacute: "é", iacute: "í", oacute: "ó", uacute: "ú", Aacute: "Á", Eacute: "É", Iacute: "Í", Oacute: "Ó", Uacute: "Ú",
  atilde: "ã", otilde: "õ", Atilde: "Ã", Otilde: "Õ", acirc: "â", ecirc: "ê", ocirc: "ô", Acirc: "Â", Ecirc: "Ê", Ocirc: "Ô",
  agrave: "à", Agrave: "À", ccedil: "ç", Ccedil: "Ç", uuml: "ü", ordm: "º", ordf: "ª", deg: "°", sup2: "²", sup3: "³",
  laquo: "«", raquo: "»", ndash: "–", mdash: "—", hellip: "…", ldquo: "“", rdquo: "”", lsquo: "‘", rsquo: "’", middot: "·", times: "×", divide: "÷",
  rsaquo: "›", lsaquo: "‹", bull: "•", copy: "©", reg: "®", trade: "™", euro: "€", sect: "§", para: "¶", shy: "", frac12: "½", frac14: "¼", plusmn: "±",
};

function decodificar(t: string): string {
  return t.replace(/&([A-Za-z]+[0-9]?);/g, (m, nome) => ENTIDADES[nome] ?? m).replace(/&#(\d+);/g, (_, n) => String.fromCodePoint(Number(n)))
    .replace(/&#x([0-9a-f]+);/gi, (_, n) => String.fromCodePoint(parseInt(n, 16)))
    .replace(/&quot;/g, '"').replace(/&apos;|&#39;/g, "'").replace(/&lt;/g, "<").replace(/&gt;/g, ">").replace(/&nbsp;/g, " ").replace(/&amp;/g, "&");
}

async function baixarLegenda(baseUrl: string, ua: string): Promise<string> {
  const limpa = baseUrl.replace(/&fmt=[^&]*/g, "");
  for (const formato of ["&fmt=json3", ""]) {
    try {
      const r = await fetch(limpa + formato, { headers: { "User-Agent": ua, "Accept-Language": "pt-BR,pt;q=0.9,en;q=0.8" } });
      if (!r.ok) continue;
      const t = textoDaLegenda(await r.text());
      if (t.length > 40) return t;
    } catch { /* tenta o próximo formato */ }
  }
  return "";
}

// Com a chave do Gemini (secret GEMINI_API_KEY), o próprio Google assiste o vídeo e devolve o que foi ensinado.
// É o caminho que funciona de servidor: o YouTube bloqueia os servidores do Supabase (HTTP 403).
export async function transcricaoGemini(id: string, chave: string, modelo = "gemini-2.5-flash"): Promise<Resultado> {
  try {
    const r = await fetch(`https://generativelanguage.googleapis.com/v1beta/models/${modelo}:generateContent`, {
      method: "POST",
      headers: { "Content-Type": "application/json", "x-goog-api-key": chave },
      body: JSON.stringify({
        contents: [{ parts: [
          { file_data: { file_uri: `https://www.youtube.com/watch?v=${id}` } },
          { text: "Este é um vídeo de aula. Transcreva em português do Brasil o que é ensinado, na ordem, com as definições, exemplos, fórmulas e datas que aparecem na fala e na tela. Se o vídeo for longo, faça um resumo bem detalhado em vez da transcrição palavra por palavra. Não invente nada que não esteja no vídeo. No máximo 12 mil caracteres, em texto simples." },
        ] }],
        generationConfig: { temperature: 0.2, maxOutputTokens: 6000 },
      }),
    });
    if (!r.ok) return { texto: null, motivo: "gemini_erro", detalhe: `http ${r.status}: ${(await r.text()).slice(0, 160)}` };
    const j = await r.json();
    const texto = (j?.candidates?.[0]?.content?.parts || []).map((p: any) => p.text || "").join("").trim();
    if (texto.length < 80) return { texto: null, motivo: "gemini_vazio", detalhe: j?.candidates?.[0]?.finishReason || "" };
    return { texto: texto.slice(0, 14000), motivo: "ok", detalhe: "gemini" };
  } catch (e) {
    return { texto: null, motivo: "gemini_erro", detalhe: String((e as Error).message || e).slice(0, 120) };
  }
}

export async function transcricaoYoutube(url: string, gemini?: { chave?: string; modelo?: string }): Promise<Resultado> {
  const id = idDoYoutube(url);
  if (!id) return { texto: null, motivo: "link_invalido" };
  const motivos: string[] = [];
  if (gemini?.chave) {
    const g = await transcricaoGemini(id, gemini.chave, gemini.modelo || undefined);
    if (g.texto) return g;
    motivos.push(`gemini:${g.motivo}:${g.detalhe || ""}`);
  }
  let titulo = "";
  for (const c of CLIENTES) {
    try {
      const corpo: Record<string, unknown> = {
        context: { client: { clientName: c.nome, clientVersion: c.versao, hl: "pt", gl: "BR", ...c.extra } },
        videoId: id, contentCheckOk: true, racyCheckOk: true,
      };
      if (c.embed) (corpo.context as any).thirdParty = { embedUrl: "https://www.ddsinovacao.com.br/estudemais/" };
      const r = await fetch("https://www.youtube.com/youtubei/v1/player?prettyPrint=false", {
        method: "POST",
        headers: {
          "Content-Type": "application/json", "User-Agent": c.ua,
          "X-YouTube-Client-Name": c.numero, "X-YouTube-Client-Version": c.versao,
          "Origin": "https://www.youtube.com", "Accept-Language": "pt-BR,pt;q=0.9,en;q=0.8",
        },
        body: JSON.stringify(corpo),
      });
      if (!r.ok) { motivos.push(`${c.nome}:http${r.status}`); continue; }
      const j = await r.json();
      titulo = titulo || j?.videoDetails?.title || "";
      const estado = j?.playabilityStatus?.status || "?";
      const trilha = escolherTrilha(j?.captions?.playerCaptionsTracklistRenderer?.captionTracks || []);
      if (!trilha?.baseUrl) { motivos.push(`${c.nome}:${estado}:sem_legenda`); continue; }
      const texto = await baixarLegenda(trilha.baseUrl, c.ua);
      if (texto) return { texto: (titulo ? `Título do vídeo: ${titulo}\n\n` : "") + texto.slice(0, 14000), motivo: "ok", detalhe: `${c.nome}:${trilha.languageCode}` };
      motivos.push(`${c.nome}:${estado}:legenda_vazia`);
    } catch (e) {
      motivos.push(`${c.nome}:erro:${String((e as Error).message || e).slice(0, 60)}`);
    }
  }
  // última tentativa: a página do vídeo
  try {
    const html = await (await fetch(`https://www.youtube.com/watch?v=${id}&hl=pt`, {
      headers: { "Accept-Language": "pt-BR,pt;q=0.9", "User-Agent": CLIENTES[3].ua },
    })).text();
    const m = html.match(/"captionTracks":(\[.*?\])/);
    if (m) {
      const trilha = escolherTrilha(JSON.parse(m[1].replace(/\\u0026/g, "&")));
      if (trilha?.baseUrl) {
        const texto = await baixarLegenda(trilha.baseUrl, CLIENTES[3].ua);
        if (texto) return { texto: texto.slice(0, 14000), motivo: "ok", detalhe: "pagina" };
      }
      motivos.push("pagina:legenda_vazia");
    } else motivos.push(/consent|confirm you|não é um robô|not a bot/i.test(html) ? "pagina:bloqueada" : "pagina:sem_legenda");
  } catch (e) {
    motivos.push("pagina:erro");
  }
  const bloqueado = motivos.some((m) => /LOGIN_REQUIRED|bloqueada|UNPLAYABLE|http4/.test(m));
  return { texto: null, motivo: bloqueado ? "bloqueado" : "sem_legenda", detalhe: motivos.join(" | ") };
}

// ---------------- Site ----------------
export function textoDoHtml(html: string): string {
  let h = String(html || "");
  h = h.replace(/<(script|style|noscript|svg|nav|footer|header|aside|form|iframe)\b[\s\S]*?<\/\1>/gi, " ");
  const principal = h.match(/<article\b[\s\S]*?<\/article>/i)?.[0] || h.match(/<main\b[\s\S]*?<\/main>/i)?.[0] || h;
  const titulo = h.match(/<title[^>]*>([\s\S]*?)<\/title>/i)?.[1] || "";
  const corpo = principal
    .replace(/<\/(p|div|li|h[1-6]|tr|br|section)>/gi, "\n")
    .replace(/<br\s*\/?>/gi, "\n")
    .replace(/<[^>]+>/g, " ");
  const texto = decodificar(corpo).split("\n").map((l) => l.replace(/\s+/g, " ").trim()).filter((l) => l.length > 2).join("\n");
  return ((titulo ? decodificar(titulo).trim() + "\n\n" : "") + texto).trim();
}

export async function textoDoSite(url: string): Promise<Resultado> {
  let alvo = String(url || "").trim();
  if (!/^https?:\/\//i.test(alvo)) alvo = "https://" + alvo;
  let u: URL;
  try { u = new URL(alvo); } catch { return { texto: null, motivo: "link_invalido" }; }
  if (!/^https?:$/.test(u.protocol) || /^(localhost|127\.|10\.|192\.168\.|169\.254\.|0\.)/.test(u.hostname) || u.hostname.endsWith(".internal")) {
    return { texto: null, motivo: "link_invalido" };
  }
  if (/(^|\.)youtube\.com$|(^|\.)youtu\.be$/.test(u.hostname)) return { texto: null, motivo: "e_youtube" };
  try {
    const r = await fetch(u.toString(), {
      redirect: "follow",
      headers: {
        "User-Agent": "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/134.0 Safari/537.36",
        "Accept": "text/html,application/xhtml+xml,text/plain;q=0.9,*/*;q=0.5",
        "Accept-Language": "pt-BR,pt;q=0.9,en;q=0.8",
      },
    });
    if (!r.ok) return { texto: null, motivo: "site_recusou", detalhe: `http ${r.status}` };
    const tipo = r.headers.get("content-type") || "";
    if (/pdf/i.test(tipo)) return { texto: null, motivo: "e_pdf" };
    const buf = new Uint8Array(await r.arrayBuffer());
    let charset = (tipo.match(/charset=([\w-]+)/i)?.[1] || "").toLowerCase();
    let html = new TextDecoder(charset === "iso-8859-1" || charset === "windows-1252" ? "windows-1252" : "utf-8").decode(buf);
    if (!charset) {
      const meta = html.slice(0, 3000).match(/<meta[^>]+charset=["']?([\w-]+)/i)?.[1]?.toLowerCase();
      if (meta && meta !== "utf-8" && meta !== "utf8") html = new TextDecoder("windows-1252").decode(buf);
    }
    const texto = /text\/plain/i.test(tipo) ? html : textoDoHtml(html);
    if (texto.length < 200) return { texto: null, motivo: "pouco_texto", detalhe: `${texto.length} caracteres` };
    return { texto: texto.slice(0, 15000), motivo: "ok" };
  } catch (e) {
    return { texto: null, motivo: "site_fora", detalhe: String((e as Error).message || e).slice(0, 120) };
  }
}

// mensagem pro aluno quando a fonte não deu certo
export function mensagemFonte(tipo: "youtube" | "link", r: Resultado): string {
  if (tipo === "youtube") {
    if (r.motivo === "link_invalido") return "Esse link não é de um vídeo do YouTube. Abre o vídeo, toca em Compartilhar → Copiar link e cola aqui.";
    return "O YouTube não deixou a gente puxar a transcrição desse vídeo. Faz assim: no YouTube, abre a descrição do vídeo → \"Mostrar transcrição\", copia o texto e cola no campo da transcrição, logo abaixo do link.";
  }
  if (r.motivo === "link_invalido") return "Esse link não parece certo. Copia o endereço completo da página (começando com https://).";
  if (r.motivo === "e_youtube") return "Esse link é do YouTube: usa a aba YouTube.";
  if (r.motivo === "e_pdf") return "Esse link é de um PDF: baixa o arquivo e manda pela aba PDF.";
  if (r.motivo === "pouco_texto") return "Essa página quase não tem texto pra ler (pode ser só vídeo ou precisar de login). Copia o texto da página e cola na aba Texto.";
  return "Não consegui ler esse site (ele pode bloquear leitura automática). Copia o texto da página e cola na aba Texto.";
}
