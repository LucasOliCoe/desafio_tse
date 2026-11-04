/*
  Uma linha por fornecedor distinto (cpf_cnpj_fornecedor), com os atributos
  que o classificador de plataforma usa: nome mais frequente, CNAE,
  categorias de despesa, amostra de descrições e valor total.

  candidato_llm = TRUE quando há algum sinal de mídia digital; só esses
  fornecedores vão para o LLM. Os demais são classificados como "Offline"
  por regra em int_fornecedores_classificados.
*/

{% set categorias_digitais = [
    'Despesa com Impulsionamento de Conteúdos',
    'Criação e inclusão de páginas na internet',
    'Produção de programas de rádio, televisão ou vídeo',
] %}

{% set regex_digital = '(?i)(impulsion|tr[aá]fego pago|an[uú]ncio|ads\\b|marketing digital|m[ií]dia digital|redes sociais|social ?media|internet|digital|online|facebook|instagram|\\bmeta\\b|google|youtube|tiktok|tik tok|bytedance|kwai|joyo|twitter|linkedin|spotify|whatsapp|telegram|dlocal|ebanx|site\\b|website|influenciador)' %}

with despesas as (

    select * from {{ ref('stg_despesas') }}
    where cpf_cnpj_fornecedor is not null

),

descricoes as (
    -- até 5 descrições distintas mais caras por fornecedor (amostra para o LLM)
    select cpf_cnpj_fornecedor, array_agg(ds_despesa order by valor desc limit 5) as amostra_descricoes
    from (
        select cpf_cnpj_fornecedor, left(ds_despesa, 150) as ds_despesa, sum(vr_despesa_contratada) as valor
        from despesas
        where ds_despesa is not null
        group by 1, 2
    )
    group by 1
),

categorias as (
    select cpf_cnpj_fornecedor, array_agg(ds_origem_despesa order by valor desc limit 3) as principais_categorias
    from (
        select cpf_cnpj_fornecedor, ds_origem_despesa, sum(vr_despesa_contratada) as valor
        from despesas
        group by 1, 2
    )
    group by 1
),

agregado as (
    select
        cpf_cnpj_fornecedor,
        any_value(tipo_documento_fornecedor)                                  as tipo_documento_fornecedor,
        approx_top_count(coalesce(nm_fornecedor_rfb, nm_fornecedor), 1)[safe_offset(0)].value
                                                                              as nm_fornecedor,
        approx_top_count(ds_cnae_fornecedor, 1)[safe_offset(0)].value         as ds_cnae_fornecedor,
        count(*)                                                              as qtd_despesas,
        count(distinct sq_candidato)                                          as qtd_candidatos,
        sum(vr_despesa_contratada)                                            as vr_total,
        logical_or(ds_origem_despesa in (
            {%- for c in categorias_digitais %}'{{ c }}'{{ ',' if not loop.last }}{% endfor -%}
        ))                                                                    as tem_categoria_digital,
        logical_or(regexp_contains(
            concat(coalesce(ds_despesa, ''), ' ', coalesce(nm_fornecedor, ''), ' ',
                   coalesce(nm_fornecedor_rfb, ''), ' ', coalesce(ds_cnae_fornecedor, '')),
            r'{{ regex_digital }}'
        ))                                                                    as tem_termo_digital
    from despesas
    group by 1
)

select
    a.*,
    c.principais_categorias,
    d.amostra_descricoes,
    (a.tem_categoria_digital or a.tem_termo_digital)                          as candidato_llm
from agregado a
left join categorias c using (cpf_cnpj_fornecedor)
left join descricoes d using (cpf_cnpj_fornecedor)
