-- Estude+ — cadastro só com e-mail e senha, sem e-mail de confirmação.
-- A Edge Function estude-cadastro cria a conta já confirmada; esta tabela só guarda o limite de contas novas por hora.
create table if not exists public.be_cadastro_tentativas (
  id bigint generated always as identity primary key,
  ip_hash text not null,
  created_at timestamptz not null default now()
);
create index if not exists be_cadastro_tentativas_idx on public.be_cadastro_tentativas (ip_hash, created_at desc);
create index if not exists be_cadastro_tentativas_data_idx on public.be_cadastro_tentativas (created_at desc);
-- só a função (service role) lê e grava
alter table public.be_cadastro_tentativas enable row level security;
