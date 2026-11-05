# Raio-X do gasto com mídia digital nas Eleições 2026

Quanto as campanhas de 2026 gastaram em **Meta, Google, TikTok, Kwai** e outras mídias digitais? E o que mudou desde 2022?

Na prestação de contas do TSE, o fornecedor aparece como texto livre ("FACEBOOK SERVICOS ONLINE DO BRASIL LTDA", "DLOCAL BRASIL INSTITUICAO DE PAGAMENTO", "JOYO TECNOLOGIA BRASIL"...). Este projeto cria uma camada analítica limpa, testada e documentada que classifica cada fornecedor por plataforma, usando LLM e regras, e responde a essas perguntas.

**Escopo:** despesas contratadas por candidatos nas eleições gerais de **2022 e 2026**, UFs **DF, SP, MG, BA, RS e AM** (1,65 milhão de lançamentos, R$ 4,8 bi). Presidente fica de fora nos dois anos.

## Principais resultados de 2026

| Plataforma | Gasto contratado | % do digital |
|---|---|---|
| Meta (Facebook/Instagram) | R$ 291,0 mi | 71,4% |
| Outras digitais (agências, produtoras, sites) | R$ 115,5 mi | 28,4% |
| Kwai | R$ 0,7 mi | 0,2% |
| Google | R$ 0,1 mi | ~0% |
| TikTok | ~R$ 0 | ~0% |

- **98% a 99% do impulsionamento foi para a Meta**, em todos os cargos.
- **Google e TikTok praticamente não aparecem**, o que é coerente com as políticas das plataformas: o Google veta anúncios políticos no Brasil desde 2024 e manteve o veto em 2026 ([Poder360](https://www.poder360.com.br/poder-eleicoes/google-veta-impulsionamento-eleitoral-nas-eleicoes-de-2026/)), e o TikTok proíbe anúncios políticos ([O Povo](https://www.opovo.com.br/noticias/politica/eleicoes/2026/08/03/tiktok-apresenta-plano-contra-a-desinformacao-nas-eleicoes.html)). Os resíduos encontrados são do tipo já apontado pela [Aos Fatos](https://www.aosfatos.org/noticias/anuncios-google-tiktok-campanha-eleitoral/).
- **NOVO é o partido mais "digital"**: 34,0% do gasto total, o dobro da média geral (16,7%). O PL lidera em valor absoluto (R$ 76,5 mi).
- **SP é a UF onde o digital pesa mais** (23,0% do gasto) e **BA a que menos pesa** (9,5%).

## Comparativo 2022 × 2026: o TikTok cresceu?

**Não.** O TikTok é praticamente zero nos dois anos. A grande mudança foi outra: **o Google saiu e a Meta ocupou o espaço.**

| Plataforma | 2022 | 2026 | Variação | Candidatos que usaram (2022 → 2026) |
|---|---|---|---|---|
| Meta | R$ 105,7 mi (44%) | R$ 291,0 mi (71%) | **+175%** | 3.989 → 3.826 |
| Outras digitais | R$ 106,3 mi (44%) | R$ 115,5 mi (28%) | +9% | 3.681 → 2.646 |
| Google | R$ 28,3 mi (12%) | R$ 0,1 mi | **−99,7%** | **765 → 21** |
| Kwai | R$ 0,4 mi | R$ 0,7 mi | +108% | 4 → 18 |
| TikTok | R$ 0,05 mi | R$ 0,01 mi | resíduo | 26 → 12 |

- **O gasto total das campanhas ficou estável** (R$ 2,37 bi em 2022 e R$ 2,44 bi em 2026), **mas o digital cresceu 69%** (de R$ 241 mi para R$ 407 mi) e passou de **10,2% para 16,7%** do gasto total.
- **765 candidatos anunciaram no Google em 2022.** Em 2026 foram 21, depois do veto do Google a anúncios políticos a partir de 2024. A Meta passou de 44% para 71% do gasto digital.
- O **Kwai** dobrou de tamanho, mas segue marginal.

Consultas completas, incluindo este comparativo, em [`dbt/analyses/perguntas_negocio.sql`](dbt/analyses/perguntas_negocio.sql).

## Arquitetura

```mermaid
flowchart LR
    TSE[(CSVs TSE<br/>latin-1, ;)] -->|ingestion/load_raw.py| RAW[raw.despesas_contratadas_candidatos]
    RAW --> STG[staging<br/>stg_despesas<br/>stg_candidatos]
    STG --> PERFIL[int_fornecedores_perfil]
    PERFIL -->|classifier/classify.py<br/>Groq LLM| SEED[(seed<br/>fornecedores_classificados_llm.csv)]
    PERFIL --> CLASS[int_fornecedores_classificados]
    SEED --> CLASS
    CLASS --> DESP[int_despesas_classificadas]
    STG --> DESP
    DESP --> FCT[marts.fct_gasto_midia_digital]
    DESP --> DIM[marts.dim_candidato]
```

| Camada | O que faz |
|---|---|
| **Ingestão** ([load_raw.py](ingestion/load_raw.py)) | Usa os CSVs locais ou baixa os zips do TSE, filtra anos e UFs, converte latin-1 em Parquet UTF-8 e carrega a raw com **um único load job `WRITE_TRUNCATE`** para os dois anos. É idempotente: rodar N vezes dá o mesmo resultado. |
| **Staging** | Tipagem, snake_case e marcadores de nulo do TSE (`#NULO`, `-1`, `-4`) convertidos em NULL. O CPF/CNPJ é normalizado (só dígitos, zeros à esquerda) e o tipo é inferido pelo tamanho, porque o TSE marca cerca de 50 mil pessoas físicas como PJ. |
| **Intermediate** | Perfil de cada fornecedor, classificação por plataforma (LLM + regras) e resolução de intermediários de pagamento pela descrição da despesa. |
| **Marts** | `fct_gasto_midia_digital` (candidato × plataforma × categoria, com o ano da eleição) e `dim_candidato`. |

## Classificador de fornecedores

O desafio original sugere a Claude API. **Usei a Groq (`openai/gpt-oss-120b`) para manter o projeto com custo zero.**

Mandar os 841 mil fornecedores ao LLM seria inviável e desnecessário. A estratégia é híbrida:

| Grupo | Como é classificado | Por quê |
|---|---|---|
| PJ com sinal digital (categoria ou termo digital) | **LLM**, em lotes de 30, do maior valor para o menor | Casos ambíguos: agência ou gráfica? Plataforma ou intermediário? |
| Pessoa física | Regra: "Outras digitais" se atua em categoria digital, senão "Offline" | PF não é plataforma de anúncio, e **nenhum CPF é enviado ao LLM nem publicado** |
| Sem sinal digital | Regra: "Offline" | Militância, combustível, aluguel etc. |
| PJ ainda não processada pelo LLM | Regra de reserva por palavra-chave (confiança 0,4) | O pipeline fica completo mesmo com o LLM parcial |

**Intermediários de pagamento** (DLOCAL, EBANX) atendem várias plataformas. Para essas despesas, a plataforma vem da **descrição** quando ela cita uma ("...Facebook/Instagram (Meta) via dLocal"). Quando a descrição é genérica, vale a plataforma predominante do intermediário, identificada pelo método `fornecedor_predominante`.

O resultado do LLM fica num **seed versionado no git**. O `dbt build` não chama o LLM, então é rápido, grátis e reprodutível, e as mudanças de classificação aparecem no diff. O script é **incremental**: só classifica o que ainda não está no CSV e respeita os limites do plano gratuito, parando sem perder nada quando a cota diária acaba.

## Qualidade de dados

- **56 testes dbt**: `unique`, `not_null`, `relationships`, `accepted_values` (plataforma, cargo, UF, método), testes do pacote **[dbt_expectations](https://hub.getdbt.com/metaplane/dbt_expectations/latest/)** e dois testes singulares.
  - `dbt_expectations`: volume mínimo da raw (pega ingestão parcial), regex de CPF/CNPJ, datas dentro do ano da eleição, confiança e % digital entre 0 e 1, e presença das plataformas principais no fato.
  - O teste de datas **encontrou 39 lançamentos com ano digitado errado** pelos candidatos (2024, 2025 e 2028, somando R$ 61 mil). As datas não foram corrigidas, para não inventar dado. O teste emite *warn* para casos pontuais e só dá *error* acima de 500 linhas, o que indicaria um erro sistêmico de conversão.
  - Testes singulares:
    - [`assert_marts_batem_com_raw`](dbt/tests/assert_marts_batem_com_raw.sql): conciliação ponta a ponta (raw = dim_candidato, e gasto digital da dim = fct). Foi validado com um erro proposital: falha quando há duplicação.
    - [`assert_nenhum_gasto_negativo`](dbt/tests/assert_nenhum_gasto_negativo.sql).
- **Freshness** na source.
- **Documentação** em todas as colunas dos marts (`dbt docs generate`).

## Decisões e limitações

- **`SQ_DESPESA` não é único**: uma despesa pode ser rateada em várias linhas, e há cerca de 9 mil lançamentos idênticos. **Não dedupliquei**, para não subestimar o gasto declarado. A chave é `despesa_linha_id`.
- **Valor contratado, não pago**: usei o arquivo de despesas *contratadas*, como pede o desafio.
- **Uma plataforma por fornecedor**: fornecedores mistos ("impulsionamento + material gráfico") recebem uma única plataforma. Os casos encontrados são de baixo valor (R$ 15 a 20 mil cada).
- **A categoria declarada pelo candidato tem erros**: há gráficas lançadas como "impulsionamento". O LLM prioriza nome, CNAE e descrição.
- **A confiança do LLM é autodeclarada** e otimista (média de 0,93, mínima de 0,6). O fato expõe `vr_gasto_classificado_llm` para separar o que veio do LLM do que veio de regra.
- **Cobertura do LLM**: na data deste README, 2.250 fornecedores, ou **96% do valor** dos fornecedores PJ com sinal digital. Do gasto digital, **92% (2022) e 97% (2026)** tiveram a plataforma definida pelo LLM. O restante usa a regra de reserva até o script terminar, já que a cota gratuita classifica cerca de 1.100 fornecedores por dia.
- **A classificação é por fornecedor, considerando os dois anos**: uma empresa que fez impulsionamento em 2022 tem "sinal digital" também em 2026. É a mesma empresa, mas incluir 2022 mudou levemente alguns números de 2026.
- **Um só classificador para os dois anos**: todo o LLM usa o mesmo modelo (`gpt-oss-120b`). Trocar de modelo no meio do caminho enviesaria justamente a comparação entre os anos.
- **BigQuery Sandbox**: as tabelas expiram em 60 dias e o DML é bloqueado (testado: `MERGE` retorna *"DML queries are not allowed in the free tier"*). Por isso a ingestão usa load job, e não `DELETE`/`MERGE`, e os extras de **snapshot** e **modelo incremental** não foram implementados. O versionamento das classificações fica no histórico do git do seed.

## Como rodar

**Pré-requisitos:** Python 3.11+, um projeto no Google Cloud com BigQuery Sandbox, uma service account (BigQuery Data Editor + Job User) com chave JSON e uma chave gratuita da [Groq](https://console.groq.com).

```bash
# 1. Ambiente
python -m venv .venv
.venv\Scripts\activate            # Linux/Mac: source .venv/bin/activate
pip install -r requirements.txt

# 2. Configuração
cp .env.example .env              # preencha GCP_PROJECT_ID e GROQ_API_KEY
# salve a chave da service account em credentials/gcp-key.json
python ingestion/check_setup.py   # deve imprimir "BigQuery OK" e "Groq OK"

# 3. Ingestão (baixa ~900 MB do TSE, 2022 + 2026, se os CSVs não estiverem em data/)
python ingestion/load_raw.py                  # ou --anos 2026 --ufs DF,SP

# 4. Transformações + testes
cd dbt
dbt deps                          # instala dbt_expectations
dbt build                         # seed + modelos + 56 testes

# 5. (Opcional) Reclassificar / continuar a classificação com LLM
cd ..
python classifier/classify.py     # incremental, respeita a cota gratuita
cd dbt && dbt build

# 6. Documentação
dbt docs generate && dbt docs serve
```

## Estrutura

```
├── ingestion/
│   ├── check_setup.py          # valida credenciais
│   └── load_raw.py             # TSE -> BigQuery raw (idempotente)
├── classifier/
│   └── classify.py             # classificação de fornecedores com LLM (Groq)
├── dbt/
│   ├── models/
│   │   ├── staging/            # sources, stg_despesas, stg_candidatos
│   │   ├── intermediate/       # perfil e classificação de fornecedores/despesas
│   │   └── marts/              # fct_gasto_midia_digital, dim_candidato
│   ├── seeds/                  # fornecedores_classificados_llm.csv
│   ├── macros/                 # tratamento de nulos/formatos do TSE, regex de plataforma
│   ├── tests/                  # testes singulares
│   ├── packages.yml            # dbt_expectations
│   └── analyses/               # perguntas_negocio.sql
└── requirements.txt
```

## Stack

Python · BigQuery (Sandbox) · dbt-core + dbt-bigquery · Groq (gpt-oss-120b) · Git/GitHub

**Fonte dos dados:** [Portal de Dados Abertos do TSE](https://dadosabertos.tse.jus.br/), Prestação de Contas Eleitorais 2022 e 2026.
