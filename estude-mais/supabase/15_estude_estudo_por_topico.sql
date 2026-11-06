-- =====================================================================================
-- EstudeUp · 15: conteúdo próprio de cada tópico (aula, quiz e flashcards do tópico)
-- Antes, "Estudar: tópico X" abria o resumo da matéria inteira e o quiz do tópico caía no quiz geral
-- (o quiz geral tem ~1 pergunta por tópico). Agora cada tópico ganha a sua aula e o seu quiz,
-- gerados uma vez pela função estude-gerar-conteudo (acao = 'estudar_topico') e reaproveitados
-- por todo mundo que estuda a matéria. Só acrescenta: nada existente é apagado.
-- =====================================================================================

-- quiz de um tópico fica em be_conteudo_gerado com tipo próprio (o quiz e a prova gerais não mudam)
alter table public.be_conteudo_gerado drop constraint if exists be_conteudo_gerado_tipo_check;
alter table public.be_conteudo_gerado add constraint be_conteudo_gerado_tipo_check
  check (tipo = any (array['quiz', 'prova', 'mapa_mental', 'resumo', 'curiosidades', 'quiz_topico']));
alter table public.be_conteudo_gerado add column if not exists topico_id uuid references public.be_topicos(id) on delete cascade;
create index if not exists be_conteudo_gerado_topico_idx on public.be_conteudo_gerado (topico_id) where topico_id is not null;

-- a aula do tópico (explicação, exemplo, macete); só a função (service role) grava
create table if not exists public.be_topico_estudo (
  topico_id uuid primary key references public.be_topicos(id) on delete cascade,
  materia_id uuid not null references public.be_materias(id) on delete cascade,
  aula jsonb not null,
  created_at timestamptz not null default now()
);
alter table public.be_topico_estudo enable row level security;
revoke all on public.be_topico_estudo from anon, authenticated;

-- o que o app lê: a aula e as perguntas do tópico (sem a resposta certa), se já foram geradas
create or replace function public.be_topico_estudo(p_topico uuid)
returns json language plpgsql security definer set search_path = public as $$
declare
  v_u uuid := be_usuario_atual_id();
  v_t record; v_aula jsonb;
begin
  if v_u is null then raise exception 'faça login de novo'; end if;
  perform be_modo_interno();
  select t.id, t.nome, t.materia_id, m.nome as materia_nome into v_t
  from be_topicos t join be_materias m on m.id = t.materia_id where t.id = p_topico;
  if v_t.id is null or not be_materia_acessivel_para(v_u, v_t.materia_id) then raise exception 'tópico não encontrado'; end if;
  select aula into v_aula from be_topico_estudo where topico_id = p_topico;
  return json_build_object(
    'topico', json_build_object('id', v_t.id, 'nome', v_t.nome, 'materia_id', v_t.materia_id, 'materia_nome', v_t.materia_nome),
    'pronto', v_aula is not null,
    'aula', v_aula,
    'quiz', coalesce((select json_agg(json_build_object('id', q.id, 'pergunta', q.pergunta, 'opcoes', q.opcoes,
                              'topico_id', q.topico_id, 'topico', v_t.nome) order by q.ordem)
                      from be_quiz_perguntas q join be_conteudo_gerado c on c.id = q.conteudo_gerado_id
                      where c.topico_id = p_topico and c.tipo = 'quiz_topico'), '[]'::json));
end $$;
revoke execute on function public.be_topico_estudo(uuid) from public, anon;
grant execute on function public.be_topico_estudo(uuid) to authenticated;
