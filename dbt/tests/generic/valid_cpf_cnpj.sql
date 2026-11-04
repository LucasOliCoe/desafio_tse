{#
  Teste genérico: o documento deve ser NULL ou ter só dígitos com
  11 (CPF) ou 14 (CNPJ) caracteres. Retorna as linhas inválidas.
#}
{% test valid_cpf_cnpj(model, column_name) %}

select {{ column_name }}
from {{ model }}
where {{ column_name }} is not null
  and not regexp_contains({{ column_name }}, r'^([0-9]{11}|[0-9]{14})$')

{% endtest %}
