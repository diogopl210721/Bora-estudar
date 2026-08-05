# Bora Estudar

App de estudo gamificado com IA — aluno individual, turmas de professor e grupos entre amigos.

## Como publicar (GitHub Pages, gratuito)

1. Suba o arquivo `index.html` pra raiz do repositório
2. Vá em **Settings > Pages**
3. Em "Source", escolha a branch `main` e a pasta `/ (root)`
4. Salve — em alguns minutos o site fica no ar em `https://SEU-USUARIO.github.io/Bora-estudar/`

## Backend

Banco de dados: Supabase (projeto compartilhado "Acompanhamento Clientes", schema `public`, tabelas prefixadas com `be_`).
Autenticação: anônima (sem senha), vinculada ao aparelho — cada pessoa que se cadastra vira uma linha em `be_usuarios`.
