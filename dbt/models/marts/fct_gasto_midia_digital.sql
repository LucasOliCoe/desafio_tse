/*
  Gasto com mídia digital.
  Grão: candidato x plataforma digital x categoria de despesa declarada.
  Só plataformas digitais (Meta, Google, TikTok, Kwai, Outras digitais);
  o gasto Offline fica em dim_candidato.vr_despesa_total.
*/

with despesas as (

    select * from {{ ref('int_despesas_classificadas') }}
    where plataforma != 'Offline'

),

candidatos as (

    select * from {{ ref('stg_candidatos') }}

),

agregado as (

    select
        sq_candidato,
        plataforma,
        ds_origem_despesa                                              as categoria_despesa,
        logical_or(eh_impulsionamento)                                 as eh_impulsionamento,
        sum(vr_despesa_contratada)                                     as vr_gasto,
        count(*)                                                       as qtd_despesas,
        count(distinct cpf_cnpj_fornecedor)                            as qtd_fornecedores,
        safe_divide(sum(vr_despesa_contratada * confianca),
                    sum(vr_despesa_contratada))                        as confianca_media,
        sum(if(metodo_classificacao in ('llm', 'descricao_intermediario', 'fornecedor_predominante'),
               vr_despesa_contratada, 0))                              as vr_gasto_classificado_llm,
        min(dt_despesa)                                                as dt_primeira_despesa,
        max(dt_despesa)                                                as dt_ultima_despesa
    from despesas
    group by 1, 2, 3

)

select
    to_hex(md5(concat(a.sq_candidato, '|', a.plataforma, '|', a.categoria_despesa))) as gasto_id,
    a.sq_candidato,
    c.nm_candidato,
    c.ds_cargo,
    c.sg_partido,
    c.sg_uf,
    a.plataforma,
    a.categoria_despesa,
    a.eh_impulsionamento,
    a.vr_gasto,
    a.qtd_despesas,
    a.qtd_fornecedores,
    round(a.confianca_media, 3)                                        as confianca_media,
    a.vr_gasto_classificado_llm,
    a.dt_primeira_despesa,
    a.dt_ultima_despesa
from agregado a
left join candidatos c using (sq_candidato)
