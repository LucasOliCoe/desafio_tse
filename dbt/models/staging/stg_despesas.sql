{{ config(materialized='view') }}

/*
  Uma linha por lançamento de despesa contratada.

  - SQ_DESPESA não é único (uma despesa pode ser rateada em várias linhas e há
    lançamentos idênticos). Não deduplicamos para não subestimar o gasto
    declarado; criamos despesa_linha_id = sq_despesa + sequencial.
  - Linhas "sem despesa" (SQ_DESPESA = -1, valor 0, tudo #NULO) representam
    prestações de contas zeradas e são removidas.
  - CPF/CNPJ do fornecedor: só dígitos, com zeros à esquerda; o tipo
    (CPF/CNPJ) é inferido pelo tamanho, pois CD_TIPO_FORNECEDOR do TSE marca
    ~50 mil pessoas físicas como "PESSOA JURÍDICA".
*/

with source as (

    select * from {{ source('tse', 'despesas_contratadas_candidatos') }}
    where sq_despesa != '-1'

),

typed as (

    select
        -- eleição / prestação de contas
        safe_cast(aa_eleicao as int64)                         as ano_eleicao,
        safe_cast(cd_eleicao as int64)                         as cd_eleicao,
        {{ tse_null('ds_eleicao') }}                           as ds_eleicao,
        safe_cast(st_turno as int64)                           as turno,
        {{ tse_null('tp_prestacao_contas') }}                  as tipo_prestacao_contas,
        {{ tse_date('dt_prestacao_contas') }}                  as dt_prestacao_contas,
        {{ tse_null('sq_prestador_contas') }}                  as sq_prestador_contas,

        -- candidato
        {{ tse_null('sq_candidato') }}                         as sq_candidato,
        safe_cast({{ tse_null('nr_candidato') }} as int64)     as nr_candidato,
        {{ tse_null('nm_candidato') }}                         as nm_candidato,
        safe_cast(cd_cargo as int64)                           as cd_cargo,
        {{ tse_null('ds_cargo') }}                             as ds_cargo,
        {{ tse_null('sg_uf') }}                                as sg_uf,
        {{ tse_null('sg_ue') }}                                as sg_ue,
        {{ tse_null('nm_ue') }}                                as nm_ue,
        safe_cast({{ tse_null('nr_partido') }} as int64)       as nr_partido,
        {{ tse_null('sg_partido') }}                           as sg_partido,
        {{ tse_null('nm_partido') }}                           as nm_partido,

        -- fornecedor
        {{ tse_null('ds_tipo_fornecedor') }}                   as tipo_fornecedor_declarado,
        regexp_replace({{ tse_null('nr_cpf_cnpj_fornecedor') }}, r'[^0-9]', '')
                                                               as _cpf_cnpj_digitos,
        {{ clean_upper('nm_fornecedor') }}                     as nm_fornecedor,
        {{ clean_upper('nm_fornecedor_rfb') }}                 as nm_fornecedor_rfb,
        {{ tse_null('cd_cnae_fornecedor') }}                   as cd_cnae_fornecedor,
        {{ tse_null('ds_cnae_fornecedor') }}                   as ds_cnae_fornecedor,
        {{ tse_null('sg_uf_fornecedor') }}                     as sg_uf_fornecedor,
        {{ tse_null('nm_municipio_fornecedor') }}              as nm_municipio_fornecedor,

        -- despesa
        {{ tse_null('sq_despesa') }}                           as sq_despesa,
        {{ tse_date('dt_despesa') }}                           as dt_despesa,
        safe_cast({{ tse_null('cd_origem_despesa') }} as int64) as cd_origem_despesa,
        {{ tse_null('ds_origem_despesa') }}                    as ds_origem_despesa,
        {{ tse_null('ds_despesa') }}                           as ds_despesa,
        {{ tse_null('ds_tipo_documento') }}                    as ds_tipo_documento,
        {{ tse_null('nr_documento') }}                         as nr_documento,
        {{ tse_numeric('vr_despesa_contratada') }}             as vr_despesa_contratada,

        -- metadados da ingestão
        _arquivo_origem                                        as arquivo_origem,
        _carregado_em                                          as carregado_em

    from source

),

final as (

    select
        concat(
            cast(ano_eleicao as string), '-', sq_despesa, '-',
            cast(row_number() over (
                partition by ano_eleicao, sq_despesa
                order by vr_despesa_contratada, nr_documento, dt_despesa, ds_despesa
            ) as string)
        )                                                      as despesa_linha_id,

        * except (_cpf_cnpj_digitos),

        case
            when length(_cpf_cnpj_digitos) between 1 and 11 then lpad(_cpf_cnpj_digitos, 11, '0')
            when length(_cpf_cnpj_digitos) between 12 and 14 then lpad(_cpf_cnpj_digitos, 14, '0')
        end                                                    as cpf_cnpj_fornecedor,

        case
            when length(_cpf_cnpj_digitos) between 1 and 11 then 'CPF'
            when length(_cpf_cnpj_digitos) between 12 and 14 then 'CNPJ'
        end                                                    as tipo_documento_fornecedor

    from typed

)

select * from final
