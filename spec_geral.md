# Desafio #1: Raio-X do gasto com mídia digital nas Eleições 2026
Nível: médio, de 8 a 10h (dá para fazer em 4 noites de ~2h e mais um bloco no fim de semana)

# Contexto de negócio
Uma agência de mídia quer entender quanto as campanhas de 2026 gastaram em mídia digital e em quais plataformas: impulsionamento na Meta, Google, TikTok, Kwai e produtoras. O problema é que, na prestação de contas do TSE, o fornecedor aparece como texto livre (“FACEBOOK SERVICOS ONLINE DO BRASIL LTDA”, “GOOGLE BRASIL INTERNET”, “FB PGTO IMPULSIONAMENTO”...). Hoje ninguém consegue somar esse gasto por plataforma de forma confiável. Sua missão é criar uma camada analítica limpa, testada e documentada para responder isso. É o mesmo problema que você enfrenta no trabalho, só que com dados públicos.

# Objetivo
Ao final, você vai ter um repositório com:

ingestão em Python dos dados do TSE para o BigQuery;
um projeto dbt com camadas staging → intermediate → marts;
um classificador de fornecedores/despesas por plataforma de mídia feito com LLM;
testes de qualidade de dados e documentação gerada pelo dbt.

# Stack

Python (ingestão)
BigQuery (sandbox)
dbt-core + dbt-bigquery ← NOVA da semana
Claude API, só para a etapa de classificação
Git/GitHub

# Dados

Principal: Prestação de Contas Eleitorais 2026 (candidatos), no Portal de Dados Abertos do TSE. Procure “Prestação de Contas Eleitorais 2026” e use o arquivo de despesas contratadas. O TSE confirmou a publicação dos dados parciais em setembro.
Atenção: os CSVs vêm em latin-1, separados por ; e são grandes. Comece filtrando 2 ou 3 UFs, por exemplo DF e mais duas.
Opcional, para comparar: a mesma base de 2022 (eleição geral anterior) no mesmo portal.

# Requisitos obrigatórios

 Script de ingestão idempotente que baixa, filtra as UFs, padroniza o encoding e carrega uma tabela raw no BigQuery. Rodar duas vezes não pode duplicar dados.
 Projeto dbt com sources.yml apontando para a camada raw.
 stg_despesas: tipagem, nomes em snake_case e CNPJ/CPF do fornecedor normalizado.
 int_fornecedores_classificados: cada fornecedor distinto recebe plataforma (Meta, Google, TikTok, Kwai, Outras digitais, Offline) e confianca.
 Marts:
fct_gasto_midia_digital (gasto por candidato, cargo, partido, UF e plataforma);
dim_candidato.
 Pelo menos 8 testes no dbt: unique, not_null, accepted_values para plataforma, e 1 teste singular (ex.: nenhum valor de despesa negativo, ou a soma do mart bate com a raw).
 dbt docs generate funcionando, com descrição em todas as colunas dos marts.
 Um .sql com 3 perguntas de negócio respondidas a partir dos marts. Exemplo: “qual a % do gasto em impulsionamento que foi para a Meta, por cargo?”

# Extras

Modelo incremental no dbt.
Snapshot do classificador para versionar mudanças de categoria.
Pacote dbt_expectations.
Comparativo 2022 × 2026: o TikTok cresceu?
