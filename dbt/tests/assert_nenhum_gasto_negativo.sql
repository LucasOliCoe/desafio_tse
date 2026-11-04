-- Teste singular: nenhum gasto de mídia digital pode ser negativo.
select gasto_id, vr_gasto
from {{ ref('fct_gasto_midia_digital') }}
where vr_gasto < 0
