{# Teste genérico: valores devem estar entre 0 e 1 (NULL é permitido). #}
{% test confianca_entre_0_e_1(model, column_name) %}

select {{ column_name }}
from {{ model }}
where {{ column_name }} < 0 or {{ column_name }} > 1

{% endtest %}
