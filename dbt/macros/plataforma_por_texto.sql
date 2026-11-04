{#
  Identifica a plataforma citada explicitamente em um texto (nome do
  fornecedor ou descrição da despesa). Retorna NULL se nenhuma for citada.
  Usado como fallback do LLM e para refinar despesas de intermediários.
#}
{% macro plataforma_por_texto(texto) -%}
    case
        when regexp_contains({{ texto }}, r'(?i)(facebook|instagram|\bmeta\b|\bfb\b|whatsapp)') then 'Meta'
        when regexp_contains({{ texto }}, r'(?i)(google|youtube|you tube)') then 'Google'
        when regexp_contains({{ texto }}, r'(?i)(tiktok|tik tok|bytedance)') then 'TikTok'
        when regexp_contains({{ texto }}, r'(?i)(kwai|joyo)') then 'Kwai'
    end
{%- endmacro %}
