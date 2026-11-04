/*
  Perguntas de negócio respondidas a partir dos marts.
  Compile com `dbt compile --select perguntas_negocio` e rode o SQL gerado
  em target/compiled/... no BigQuery (ou cole cada bloco no console).
*/


-- =============================================================================
-- Pergunta 1: Qual a % do gasto em impulsionamento que foi para a Meta, por cargo?
--
-- Denominador: todo gasto declarado na categoria "Despesa com Impulsionamento
-- de Conteúdos", inclusive o que foi classificado como Offline (ex.: gráfica
-- lançada como impulsionamento). Como fct_gasto_midia_digital só tem
-- plataformas digitais, a parcela Offline é calculada à parte.
-- =============================================================================
with impulsionamento_digital as (
    select ds_cargo, plataforma, sum(vr_gasto) as vr
    from {{ ref('fct_gasto_midia_digital') }}
    where eh_impulsionamento
    group by 1, 2
),

impulsionamento_total as (
    select d.ds_cargo, sum(d.vr_despesa_contratada) as vr
    from {{ ref('int_despesas_classificadas') }} d
    where d.eh_impulsionamento
    group by 1
)

select
    t.ds_cargo,
    round(t.vr / 1e6, 2)                                                    as impulsionamento_total_mi,
    round(sum(if(i.plataforma = 'Meta', i.vr, 0)) / 1e6, 2)                 as impulsionamento_meta_mi,
    round(100 * safe_divide(sum(if(i.plataforma = 'Meta', i.vr, 0)), t.vr), 1)          as pct_meta,
    round(100 * safe_divide(sum(if(i.plataforma = 'Kwai', i.vr, 0)), t.vr), 2)          as pct_kwai,
    round(100 * safe_divide(sum(if(i.plataforma in ('Google', 'TikTok'), i.vr, 0)), t.vr), 2) as pct_google_tiktok,
    round(100 * safe_divide(sum(if(i.plataforma = 'Outras digitais', i.vr, 0)), t.vr), 1) as pct_outras_digitais,
    round(100 * (1 - safe_divide(sum(i.vr), t.vr)), 1)                     as pct_offline
from impulsionamento_total t
left join impulsionamento_digital i using (ds_cargo)
group by t.ds_cargo, t.vr
order by pct_meta desc;


-- =============================================================================
-- Pergunta 2: Quais partidos mais investem em mídia digital (R$ e % do gasto total)?
-- Top 10 por gasto digital. Inclui quantos candidatos do partido usaram digital.
-- =============================================================================
select
    sg_partido,
    count(*)                                                                as candidatos,
    countif(vr_gasto_digital > 0)                                           as candidatos_com_digital,
    round(sum(vr_gasto_digital) / 1e6, 2)                                   as gasto_digital_mi,
    round(sum(vr_despesa_total) / 1e6, 2)                                   as gasto_total_mi,
    round(100 * safe_divide(sum(vr_gasto_digital), sum(vr_despesa_total)), 1) as pct_digital,
    round(100 * safe_divide(sum(vr_gasto_meta), sum(vr_gasto_digital)), 1)  as pct_meta_no_digital
from {{ ref('dim_candidato') }}
group by sg_partido
order by gasto_digital_mi desc
limit 10;


-- =============================================================================
-- Pergunta 3: Em qual UF o digital pesa mais na campanha, e quanto gasta
-- (mediana) um candidato que investe em digital?
-- =============================================================================
select
    sg_uf,
    count(*)                                                                as candidatos,
    round(100 * countif(vr_gasto_digital > 0) / count(*), 1)                as pct_candidatos_com_digital,
    round(sum(vr_gasto_digital) / 1e6, 2)                                   as gasto_digital_mi,
    round(100 * safe_divide(sum(vr_gasto_digital), sum(vr_despesa_total)), 1) as pct_digital_no_total,
    round(approx_quantiles(if(vr_gasto_digital > 0, vr_gasto_digital, null), 2)[offset(1)], 0)
                                                                            as mediana_digital_por_candidato
from {{ ref('dim_candidato') }}
group by sg_uf
order by pct_digital_no_total desc;
