/*
  Uma linha por lançamento de despesa (mesmo grão do stg_despesas) com a
  plataforma final.

  Regra de plataforma da despesa:
    - sem fornecedor (tarifas bancárias, impostos)  -> Offline
    - fornecedor intermediário de pagamento (DLOCAL, EBANX...):
        * descrição cita uma plataforma             -> essa plataforma
        * descrição genérica                        -> plataforma predominante do fornecedor
    - demais                                        -> plataforma do fornecedor
*/

with despesas as (

    select * from {{ ref('stg_despesas') }}

),

fornecedores as (

    select * from {{ ref('int_fornecedores_classificados') }}

),

joined as (

    select
        d.*,
        f.plataforma           as plataforma_fornecedor,
        f.confianca            as confianca_fornecedor,
        f.metodo_classificacao as metodo_fornecedor,
        coalesce(f.eh_intermediario, false) as eh_intermediario,
        {{ plataforma_por_texto('d.ds_despesa') }} as plataforma_descricao
    from despesas d
    left join fornecedores f using (cpf_cnpj_fornecedor)

)

select
    * except (plataforma_descricao),

    case
        when cpf_cnpj_fornecedor is null then 'Offline'
        when eh_intermediario and plataforma_descricao is not null then plataforma_descricao
        else plataforma_fornecedor
    end as plataforma,

    case
        when cpf_cnpj_fornecedor is null then 1.0
        when eh_intermediario and plataforma_descricao is not null then 0.9
        when eh_intermediario then round(confianca_fornecedor * 0.7, 2)
        else confianca_fornecedor
    end as confianca,

    case
        when cpf_cnpj_fornecedor is null then 'sem_fornecedor'
        when eh_intermediario and plataforma_descricao is not null then 'descricao_intermediario'
        when eh_intermediario then 'fornecedor_predominante'
        else metodo_fornecedor
    end as metodo_classificacao,

    ds_origem_despesa = 'Despesa com Impulsionamento de Conteúdos' as eh_impulsionamento

from joined
