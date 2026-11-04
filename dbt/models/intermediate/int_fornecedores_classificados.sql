/*
  Uma linha por fornecedor distinto com plataforma e confiança.

  Ordem de decisão (coluna metodo_classificacao):
    1. llm            -> resultado do classificador Groq (seed fornecedores_classificados_llm)
    2. regra_pf       -> pessoa física: não pode ser plataforma de anúncio;
                         "Outras digitais" se atua em categoria digital, senão "Offline"
    3. regra_fallback -> PJ candidata ao LLM ainda não classificada: plataforma citada
                         no nome/descrições; senão "Outras digitais" se tem categoria
                         digital declarada; senão "Offline"
    4. regra_offline  -> sem nenhum sinal digital: "Offline"
*/

with perfil as (

    select * from {{ ref('int_fornecedores_perfil') }}

),

llm as (

    select * from {{ ref('fornecedores_classificados_llm') }}

),

classificado as (

    select
        p.cpf_cnpj_fornecedor,
        p.tipo_documento_fornecedor,
        p.nm_fornecedor,
        p.ds_cnae_fornecedor,
        p.vr_total,
        p.candidato_llm,

        case
            when l.cpf_cnpj_fornecedor is not null then 'llm'
            when p.tipo_documento_fornecedor = 'CPF' then 'regra_pf'
            when p.candidato_llm then 'regra_fallback'
            else 'regra_offline'
        end as metodo_classificacao,

        case
            when l.cpf_cnpj_fornecedor is not null then l.plataforma
            when p.tipo_documento_fornecedor = 'CPF'
                then if(p.tem_categoria_digital, 'Outras digitais', 'Offline')
            when p.candidato_llm then coalesce(
                {{ plataforma_por_texto("concat(coalesce(p.nm_fornecedor, ''), ' ', array_to_string(p.amostra_descricoes, ' '))") }},
                if(p.tem_categoria_digital, 'Outras digitais', 'Offline')
            )
            else 'Offline'
        end as plataforma,

        case
            when l.cpf_cnpj_fornecedor is not null then l.confianca
            when p.tipo_documento_fornecedor = 'CPF' then 0.5
            when p.candidato_llm then 0.4
            else 0.9
        end as confianca,

        coalesce(l.eh_intermediario, false) as eh_intermediario,
        l.justificativa                     as justificativa_llm,
        l.modelo                            as modelo_llm,
        l.classificado_em

    from perfil p
    left join llm l using (cpf_cnpj_fornecedor)

)

select * from classificado
