{# Converte os marcadores de nulo do TSE (#NULO, #NULO#, -1, -4, vazio) em NULL e faz TRIM. #}
{% macro tse_null(col) -%}
    case
        when trim({{ col }}) in ('#NULO', '#NULO#', '-1', '-3', '-4', '') then null
        else trim({{ col }})
    end
{%- endmacro %}

{# Data no formato dd/mm/aaaa -> DATE (NULL se inválida). #}
{% macro tse_date(col) -%}
    safe.parse_date('%d/%m/%Y', {{ tse_null(col) }})
{%- endmacro %}

{# Valor no formato brasileiro "1.234,56" -> NUMERIC. #}
{% macro tse_numeric(col) -%}
    safe_cast(replace(replace({{ tse_null(col) }}, '.', ''), ',', '.') as numeric)
{%- endmacro %}

{# Texto em caixa alta, sem espaços duplicados (para nomes de fornecedor). #}
{% macro clean_upper(col) -%}
    nullif(regexp_replace(upper({{ tse_null(col) }}), r'\s+', ' '), '')
{%- endmacro %}
