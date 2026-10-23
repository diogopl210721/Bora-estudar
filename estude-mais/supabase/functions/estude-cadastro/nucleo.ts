// Núcleo do cadastro do Estude+: só e-mail e senha (digitada 2 vezes no app), sem e-mail de confirmação. Sem imports.

export const LIMITE_CADASTROS_HORA_IP = 5;     // contas criadas por hora a partir do mesmo endereço
export const LIMITE_CADASTROS_HORA_TOTAL = 200; // trava geral contra robô

const EMAIL = /^[^\s@]+@[^\s@]+\.[^\s@]{2,}$/;

export function validarCadastro(corpo: any): { email: string; senha: string; nome: string } {
  const email = typeof corpo?.email === "string" ? corpo.email.trim().toLowerCase() : "";
  const senha = typeof corpo?.senha === "string" ? corpo.senha : "";
  const nome = typeof corpo?.nome === "string" ? corpo.nome.replace(/\s+/g, " ").trim() : "";
  if (nome.length < 2) throw new Error("digite seu nome pra continuar");
  if (nome.length > 80) throw new Error("o nome ficou grande demais");
  if (!EMAIL.test(email) || email.length > 160) throw new Error("esse e-mail não parece certo, confere de novo");
  if (senha.length < 6) throw new Error("a senha precisa ter pelo menos 6 caracteres");
  if (senha.length > 72) throw new Error("a senha pode ter no máximo 72 caracteres");
  return { email, senha, nome };
}

// o erro do Supabase quando o e-mail já tem conta
export function jaExiste(err: { code?: string; message?: string; status?: number } | null): boolean {
  if (!err) return false;
  return err.code === "email_exists" || /already (been )?registered|already exists/i.test(err.message || "");
}

export async function hashIp(ip: string): Promise<string> {
  const dados = new TextEncoder().encode("estude+:" + ip);
  const h = await crypto.subtle.digest("SHA-256", dados);
  return Array.from(new Uint8Array(h)).map((b) => b.toString(16).padStart(2, "0")).join("");
}
