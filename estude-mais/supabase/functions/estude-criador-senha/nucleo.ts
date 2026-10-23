// Núcleo da troca de senha feita pela conta do criador. Sem imports, para ser testado fora do Deno.

export function validarTroca(corpo: any): { usuarioId: string; senha: string } {
  const usuarioId = typeof corpo?.usuario_id === "string" && /^[0-9a-f-]{36}$/i.test(corpo.usuario_id) ? corpo.usuario_id : "";
  const senha = typeof corpo?.senha === "string" ? corpo.senha : "";
  if (!usuarioId) throw new Error("conta não informada");
  if (senha.length < 6) throw new Error("a senha precisa ter pelo menos 6 caracteres");
  if (senha.length > 72) throw new Error("a senha ficou grande demais");
  return { usuarioId, senha };
}
