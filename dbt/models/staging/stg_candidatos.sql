{{ config(materialized='view') }}

/*
  Uma linha por candidato que prestou contas (inclusive quem declarou zero
  despesas, que é removido do stg_despesas). Lido direto da raw para não
  perder esses candidatos. Nome, cargo e partido são constantes por
  SQ_CANDIDATO (validado na exploração); o turno pode variar (2º turno de
  governador), então guardamos o maior.
*/

with source as (

    select * from {{ source('tse', 'despesas_contratadas_candidatos') }}

)

select
    {{ tse_null('sq_candidato') }}                         as sq_candidato,
    any_value(safe_cast(aa_eleicao as int64))              as ano_eleicao,
    any_value(safe_cast({{ tse_null('nr_candidato') }} as int64)) as nr_candidato,
    any_value({{ tse_null('nm_candidato') }})              as nm_candidato,
    any_value(safe_cast(cd_cargo as int64))                as cd_cargo,
    any_value({{ tse_null('ds_cargo') }})                  as ds_cargo,
    any_value({{ tse_null('sg_uf') }})                     as sg_uf,
    any_value(safe_cast({{ tse_null('nr_partido') }} as int64)) as nr_partido,
    any_value({{ tse_null('sg_partido') }})                as sg_partido,
    any_value({{ tse_null('nm_partido') }})                as nm_partido,
    max(safe_cast(st_turno as int64))                      as turno_maximo,
    any_value({{ tse_null('tp_prestacao_contas') }})       as tipo_prestacao_contas,
    max({{ tse_date('dt_prestacao_contas') }})             as dt_prestacao_contas,
    countif(sq_despesa != '-1') > 0                        as declarou_despesas

from source
group by 1
