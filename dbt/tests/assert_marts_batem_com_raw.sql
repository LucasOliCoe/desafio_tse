/*
  Teste singular de conciliação ponta a ponta:
    1. soma de dim_candidato.vr_despesa_total == soma da raw (todas as despesas)
    2. soma de fct_gasto_midia_digital.vr_gasto == soma de dim_candidato.vr_gasto_digital
  Detecta linhas perdidas ou duplicadas em qualquer JOIN do pipeline.
  Retorna linhas (= falha) quando alguma diferença passa de R$ 0,01.
*/

with raw_total as (
    select sum({{ tse_numeric('vr_despesa_contratada') }}) as vr
    from {{ source('tse', 'despesas_contratadas_candidatos') }}
),

dim_total as (
    select sum(vr_despesa_total) as vr, sum(vr_gasto_digital) as vr_digital
    from {{ ref('dim_candidato') }}
),

fct_total as (
    select sum(vr_gasto) as vr
    from {{ ref('fct_gasto_midia_digital') }}
)

select 'raw x dim_candidato' as checagem, r.vr as esperado, d.vr as obtido
from raw_total r cross join dim_total d
where abs(r.vr - d.vr) > 0.01

union all

select 'dim_candidato (digital) x fct', d.vr_digital, f.vr
from dim_total d cross join fct_total f
where abs(d.vr_digital - f.vr) > 0.01
