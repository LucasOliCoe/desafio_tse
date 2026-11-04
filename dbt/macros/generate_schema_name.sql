{#
  Usa o +schema configurado diretamente como nome do dataset
  (staging, intermediate, marts), em vez do padrão do dbt "<target>_<schema>".
#}
{% macro generate_schema_name(custom_schema_name, node) -%}
    {%- if custom_schema_name is none -%}
        {{ target.schema }}
    {%- else -%}
        {{ custom_schema_name | trim }}
    {%- endif -%}
{%- endmacro %}
