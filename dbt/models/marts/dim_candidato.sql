/*
  Um registro por candidato que prestou contas (inclusive sem despesas),
  com atributos cadastrais e totais de gasto para facilitar análises de
  participação (% digital, plataforma principal).
*/

with candidatos as (

    select * from {{ ref('stg_candidatos') }}

),

despesas as (

    select * from {{ ref('int_despesas_classificadas') }}

),

por_plataforma as (

    select sq_candidato, plataforma, sum(vr_despesa_contratada) as vr
    from despesas
    group by 1, 2

),

totais as (

    select
        sq_candidato,
        sum(vr)                                                     as vr_despesa_total,
        sum(if(plataforma != 'Offline', vr, 0))                     as vr_gasto_digital,
        sum(if(plataforma = 'Meta', vr, 0))                         as vr_gasto_meta,
        sum(if(plataforma = 'Google', vr, 0))                       as vr_gasto_google,
        sum(if(plataforma = 'TikTok', vr, 0))                       as vr_gasto_tiktok,
        sum(if(plataforma = 'Kwai', vr, 0))                         as vr_gasto_kwai,
        sum(if(plataforma = 'Outras digitais', vr, 0))              as vr_gasto_outras_digitais,
        array_agg(if(plataforma != 'Offline' and vr > 0, plataforma, null) ignore nulls
                  order by vr desc limit 1)[safe_offset(0)]         as plataforma_digital_principal
    from por_plataforma
    group by 1

)

select
    c.sq_candidato,
    c.ano_eleicao,
    c.nr_candidato,
    c.nm_candidato,
    c.cd_cargo,
    c.ds_cargo,
    c.sg_uf,
    c.nr_partido,
    c.sg_partido,
    c.nm_partido,
    c.turno_maximo,
    c.tipo_prestacao_contas,
    c.dt_prestacao_contas,
    c.declarou_despesas,
    coalesce(t.vr_despesa_total, 0)                                 as vr_despesa_total,
    coalesce(t.vr_gasto_digital, 0)                                 as vr_gasto_digital,
    coalesce(t.vr_gasto_meta, 0)                                    as vr_gasto_meta,
    coalesce(t.vr_gasto_google, 0)                                  as vr_gasto_google,
    coalesce(t.vr_gasto_tiktok, 0)                                  as vr_gasto_tiktok,
    coalesce(t.vr_gasto_kwai, 0)                                    as vr_gasto_kwai,
    coalesce(t.vr_gasto_outras_digitais, 0)                         as vr_gasto_outras_digitais,
    round(safe_divide(t.vr_gasto_digital, t.vr_despesa_total), 4)   as pct_gasto_digital,
    t.plataforma_digital_principal
from candidatos c
left join totais t using (sq_candidato)
