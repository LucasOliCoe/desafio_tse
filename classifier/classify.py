"""
Classificador de fornecedores por plataforma de mídia digital usando LLM (Groq).

Lê os fornecedores PJ candidatos de intermediate.int_fornecedores_perfil
(gerado pelo dbt), envia em lotes para o LLM e grava o resultado no seed
dbt/seeds/fornecedores_classificados_llm.csv.

- Incremental: fornecedores já presentes no CSV não são reenviados, então dá
  para rodar várias vezes (ex.: um dia após o outro) até cobrir todos, sem
  gastar cota à toa. A ordem é por valor total (os mais relevantes primeiro).
- Respeita o limite gratuito da Groq: controla tokens por minuto e encerra
  de forma limpa quando a cota diária acaba.
- Pessoas físicas (CPF) NÃO são enviadas ao LLM (privacidade); são
  classificadas por regra no dbt.

Uso:
    .venv\\Scripts\\python classifier\\classify.py               # todos pendentes
    .venv\\Scripts\\python classifier\\classify.py --limit 100   # só os 100 maiores
"""
from __future__ import annotations

import argparse
import csv
import json
import os
import re
import time
from datetime import datetime, timezone
from pathlib import Path

from dotenv import load_dotenv
from google.cloud import bigquery
from groq import APIConnectionError, APIStatusError, Groq, RateLimitError

ROOT = Path(__file__).resolve().parents[1]
load_dotenv(ROOT / ".env")

SEED_PATH = ROOT / "dbt" / "seeds" / "fornecedores_classificados_llm.csv"
MODEL = os.getenv("GROQ_MODEL", "openai/gpt-oss-120b")
PLATAFORMAS = ["Meta", "Google", "TikTok", "Kwai", "Outras digitais", "Offline"]
CSV_FIELDS = [
    "cpf_cnpj_fornecedor", "nm_fornecedor", "plataforma", "confianca",
    "eh_intermediario", "justificativa", "modelo", "classificado_em",
]
BATCH_SIZE = 30
TOKENS_PER_MINUTE = 7500  # margem abaixo do limite de 8000 da conta gratuita

SYSTEM_PROMPT = """Você classifica fornecedores de campanhas eleitorais brasileiras (dados do TSE) pela plataforma de mídia.

Categorias (use exatamente um destes valores em "plataforma"):
- "Meta": o fornecedor É a Meta (Facebook Serviços Online do Brasil, Instagram, WhatsApp) ou um intermediário de pagamento cujas despesas são para anúncios na Meta.
- "Google": o fornecedor É o Google (Google Brasil Internet, YouTube) ou intermediário pagando anúncios no Google.
- "TikTok": o fornecedor É o TikTok/ByteDance ou intermediário pagando anúncios no TikTok.
- "Kwai": o fornecedor É o Kwai (razão social JOYO TECNOLOGIA BRASIL) ou intermediário pagando anúncios no Kwai.
- "Outras digitais": agências e produtoras de marketing digital, gestão de redes sociais/tráfego pago, criação de sites, produção de vídeo para internet, outras plataformas online (X, LinkedIn, Spotify, Telegram, portais), ou intermediário de pagamento de anúncios sem plataforma identificável.
- "Offline": todo o resto (gráficas, adesivos, rádio/TV tradicional, carro de som, eventos, combustível, aluguel, pessoal, consultoria não digital etc.).

Regras:
- Agência que GERENCIA anúncios na Meta/Google (ex.: "gestão de Meta Ads") é "Outras digitais", não a plataforma.
- Intermediários de pagamento (ex.: DLOCAL, EBANX, PagSeguro, Mercado Pago) recebem eh_intermediario=true; a plataforma é a predominante nas descrições, ou "Outras digitais" se não der para saber.
- A categoria de despesa declarada pelo candidato às vezes está errada. Gráficas, editoras e empresas de impressão (inclusive "impressão digital") são "Offline" mesmo que alguma despesa esteja lançada como impulsionamento. Priorize nome, CNAE e descrições.
- Produtoras de rádio/TV/vídeo: "Offline" se o foco é horário eleitoral em TV/rádio; "Outras digitais" só se as descrições indicarem conteúdo para internet/redes sociais.
- confianca: número de 0 a 1 (1 = certeza).
- justificativa: no máximo 10 palavras.

Responda SOMENTE com JSON no formato:
{"resultados": [{"id": 1, "plataforma": "...", "confianca": 0.9, "eh_intermediario": false, "justificativa": "..."}]}
Inclua um item para CADA id recebido."""


def fetch_candidates(already_done: set[str], limit: int | None) -> list[dict]:
    client = bigquery.Client(project=os.environ["GCP_PROJECT_ID"])
    rows = client.query("""
        select cpf_cnpj_fornecedor, nm_fornecedor, ds_cnae_fornecedor, vr_total,
               qtd_candidatos, principais_categorias, amostra_descricoes
        from intermediate.int_fornecedores_perfil
        where candidato_llm and tipo_documento_fornecedor = 'CNPJ'
        order by vr_total desc
    """).result()
    pending = [dict(r) for r in rows if r["cpf_cnpj_fornecedor"] not in already_done]
    return pending[:limit] if limit else pending


def format_supplier(i: int, s: dict) -> str:
    descs = "; ".join((d or "")[:100] for d in (s["amostra_descricoes"] or [])[:3])
    cats = "; ".join(s["principais_categorias"] or [])
    return (
        f"id={i} | nome={s['nm_fornecedor']} | cnae={s['ds_cnae_fornecedor'] or '-'} | "
        f"categorias={cats} | descricoes={descs} | valor_total=R${float(s['vr_total']):,.0f} | "
        f"candidatos={s['qtd_candidatos']}"
    )


def call_llm(client: Groq, batch: list[dict]) -> tuple[list[dict], int]:
    user_msg = "Classifique os fornecedores:\n" + "\n".join(
        format_supplier(i, s) for i, s in enumerate(batch, start=1)
    )
    resp = client.chat.completions.create(
        model=MODEL,
        messages=[{"role": "system", "content": SYSTEM_PROMPT},
                  {"role": "user", "content": user_msg}],
        response_format={"type": "json_object"},
        temperature=0,
        max_completion_tokens=4000,
        extra_body={"reasoning_effort": "low"},
    )
    data = json.loads(resp.choices[0].message.content)
    return data.get("resultados", []), resp.usage.total_tokens


def strip_cpf(name: str | None) -> str | None:
    """Remove CPF embutido na razão social de MEIs (ex.: 'FULANO 00703709232'), pois o CSV é público."""
    return re.sub(r"\s*\b\d{3}\.?\d{3}\.?\d{3}-?\d{2}\b", "", name).strip() if name else name


def validate(results: list[dict], batch: list[dict]) -> list[dict]:
    """Mantém só respostas válidas; ids faltantes ficam para a próxima execução."""
    now = datetime.now(timezone.utc).isoformat(timespec="seconds")
    out = []
    for r in results:
        try:
            idx = int(r["id"]) - 1
            plataforma = r["plataforma"]
            confianca = float(r["confianca"])
        except (KeyError, TypeError, ValueError):
            continue
        if not (0 <= idx < len(batch)) or plataforma not in PLATAFORMAS or not 0 <= confianca <= 1:
            continue
        s = batch[idx]
        out.append({
            "cpf_cnpj_fornecedor": s["cpf_cnpj_fornecedor"],
            "nm_fornecedor": strip_cpf(s["nm_fornecedor"]),
            "plataforma": plataforma,
            "confianca": round(confianca, 2),
            "eh_intermediario": bool(r.get("eh_intermediario", False)),
            "justificativa": str(r.get("justificativa", ""))[:120],
            "modelo": MODEL,
            "classificado_em": now,
        })
    # evita duplicar o mesmo fornecedor se o LLM repetir um id
    return list({o["cpf_cnpj_fornecedor"]: o for o in out}.values())


def load_done() -> set[str]:
    if not SEED_PATH.exists():
        return set()
    with open(SEED_PATH, encoding="utf-8", newline="") as fh:
        return {row["cpf_cnpj_fornecedor"] for row in csv.DictReader(fh)}


def append_rows(rows: list[dict]) -> None:
    new_file = not SEED_PATH.exists()
    SEED_PATH.parent.mkdir(parents=True, exist_ok=True)
    with open(SEED_PATH, "a", encoding="utf-8", newline="") as fh:
        w = csv.DictWriter(fh, fieldnames=CSV_FIELDS)
        if new_file:
            w.writeheader()
        w.writerows(rows)


def retry_seconds(err: RateLimitError) -> float:
    header = err.response.headers.get("retry-after")
    if header:
        return float(header) + 1
    m = re.search(r"try again in (?:(\d+)m)?([\d.]+)s", str(err))
    return (int(m.group(1) or 0) * 60 + float(m.group(2)) + 1) if m else 30


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--limit", type=int, default=None, help="máximo de fornecedores nesta execução")
    args = parser.parse_args()

    done = load_done()
    pending = fetch_candidates(done, args.limit)
    print(f"Já classificados: {len(done)} | pendentes nesta execução: {len(pending)} | modelo: {MODEL}")
    if not pending:
        return

    client = Groq(max_retries=0)
    total_ok = 0

    for start in range(0, len(pending), BATCH_SIZE):
        batch = pending[start:start + BATCH_SIZE]
        t0 = time.time()
        network_failures = 0
        while True:
            try:
                results, used = call_llm(client, batch)
                break
            # a ordem importa: RateLimitError é subclasse de APIStatusError
            except RateLimitError as err:
                msg = str(err).lower()
                if "per day" in msg or "(tpd)" in msg or "(rpd)" in msg:
                    print(f"\nCota diária esgotada. Classificados nesta execução: {total_ok}. "
                          "Rode de novo amanhã para continuar de onde parou.")
                    return
                wait = retry_seconds(err)
                print(f"  limite por minuto, aguardando {wait:.0f}s...")
                time.sleep(wait)
            except (APIConnectionError, APIStatusError) as err:
                status = getattr(err, "status_code", None)
                if status is not None and status < 500:
                    # 4xx (ex.: JSON inválido gerado pelo modelo): pula o lote, tenta na próxima execução
                    print(f"  erro {status} no lote; será tentado na próxima execução")
                    results, used = [], 0
                    break
                # falha de rede/timeout ou 5xx: tenta de novo com backoff exponencial
                network_failures += 1
                if network_failures > 6:
                    print("  falhas de rede repetidas; encerrando (rode de novo para continuar)")
                    return
                wait = min(300, 10 * 2 ** (network_failures - 1))
                print(f"  erro de conexão/servidor ({type(err).__name__}); nova tentativa em {wait}s")
                time.sleep(wait)
            except json.JSONDecodeError:
                print("  resposta não era JSON válido; lote será tentado na próxima execução")
                results, used = [], 0
                break

        rows = validate(results, batch)
        append_rows(rows)
        total_ok += len(rows)
        print(f"  lote {start // BATCH_SIZE + 1}: {len(rows)}/{len(batch)} ok "
              f"({used} tokens) | total {total_ok}/{len(pending)}")

        # controle proativo: espaça as chamadas para ficar abaixo de TOKENS_PER_MINUTE
        min_interval = used / TOKENS_PER_MINUTE * 60
        time.sleep(max(0.0, min_interval - (time.time() - t0)))

    print(f"\nConcluído: {total_ok} fornecedores classificados -> {SEED_PATH.relative_to(ROOT)}")


if __name__ == "__main__":
    main()
