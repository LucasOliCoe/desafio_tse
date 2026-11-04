"""
Ingestão das despesas contratadas por candidatos (TSE, Eleições 2022 e 2026) no BigQuery.

Fluxo:
  1. Garante que os CSVs dos anos e UFs escolhidos existem em data/ (se faltar algum,
     baixa o zip do Portal de Dados Abertos do TSE e extrai só o necessário).
  2. Lê cada CSV (latin-1, separador ';') em blocos, mantém todas as colunas
     como texto (a tipagem é responsabilidade do dbt/staging) e grava um único
     Parquet UTF-8 local com colunas de metadados.
  3. Carrega o Parquet em `<projeto>.raw.despesas_contratadas_candidatos`
     com WRITE_TRUNCATE num único load job.

Idempotência: o load job substitui a tabela inteira de forma atômica, então
rodar o script N vezes produz sempre o mesmo resultado (sem duplicar linhas).
Não usamos DML (DELETE/MERGE), que tem restrições no BigQuery Sandbox.

Uso:
    .venv\\Scripts\\python ingestion\\load_raw.py                       # ANOS e UFS do .env
    .venv\\Scripts\\python ingestion\\load_raw.py --anos 2026 --ufs DF,SP
"""
from __future__ import annotations

import argparse
import os
import shutil
import tempfile
import zipfile
from datetime import datetime, timezone
from pathlib import Path

import pandas as pd
import pyarrow as pa
import pyarrow.parquet as pq
import requests
from dotenv import load_dotenv
from google.cloud import bigquery

load_dotenv()

ROOT = Path(__file__).resolve().parents[1]
DATASET_NAME = "prestacao_de_contas_eleitorais_candidatos_{ano}"
ZIP_URL = "https://cdn.tse.jus.br/estatistica/sead/odsele/prestacao_contas/" + DATASET_NAME + ".zip"
FILE_PATTERN = "despesas_contratadas_candidatos_{ano}_{uf}.csv"
TABLE_NAME = "despesas_contratadas_candidatos"
CHUNK_SIZE = 200_000


def ensure_files(ano: int, ufs: list[str]) -> list[Path]:
    """Retorna os caminhos dos CSVs do ano; baixa o zip do TSE se algum estiver faltando."""
    data_dir = ROOT / "data" / DATASET_NAME.format(ano=ano)
    zip_url = ZIP_URL.format(ano=ano)
    paths = [data_dir / FILE_PATTERN.format(ano=ano, uf=uf) for uf in ufs]
    missing = [p for p in paths if not p.exists()]
    if not missing:
        print(f"[1/3] {ano}: usando CSVs locais em {data_dir.relative_to(ROOT)}")
        return paths

    print(f"[1/3] {ano}: faltam {len(missing)} arquivo(s); baixando {zip_url}")
    data_dir.mkdir(parents=True, exist_ok=True)
    zip_path = data_dir.parent / f"{DATASET_NAME.format(ano=ano)}.zip"
    with requests.get(zip_url, stream=True, timeout=60) as r:
        r.raise_for_status()
        with open(zip_path, "wb") as fh:
            shutil.copyfileobj(r.raw, fh, length=1024 * 1024)

    wanted = {p.name for p in missing}
    with zipfile.ZipFile(zip_path) as zf:
        for member in zf.namelist():
            if Path(member).name in wanted:
                with zf.open(member) as src, open(data_dir / Path(member).name, "wb") as dst:
                    shutil.copyfileobj(src, dst)
    zip_path.unlink()

    still_missing = [p.name for p in paths if not p.exists()]
    if still_missing:
        raise FileNotFoundError(f"Não encontrados no zip do TSE: {still_missing}")
    return paths


def build_parquet(files: list[tuple[Path, str]], out_path: Path) -> int:
    """Converte os CSVs (latin-1) em um único Parquet UTF-8, tudo como STRING.

    files: lista de (caminho do CSV, UF esperada).
    """
    print("[2/3] Convertendo CSVs para Parquet (UTF-8)")
    loaded_at = datetime.now(timezone.utc)
    writer: pq.ParquetWriter | None = None
    schema: pa.Schema | None = None
    total = 0

    for path, uf in files:
        n_file = 0
        reader = pd.read_csv(
            path,
            sep=";",
            encoding="latin-1",
            dtype=str,
            keep_default_na=False,  # "#NULO", "" etc. ficam como texto; staging trata
            chunksize=CHUNK_SIZE,
        )
        for chunk in reader:
            # filtro defensivo: garante que só entram linhas da UF do arquivo
            chunk = chunk[chunk["SG_UF"] == uf]
            chunk["_arquivo_origem"] = path.name
            chunk["_carregado_em"] = loaded_at
            table = pa.Table.from_pandas(chunk, preserve_index=False)
            if writer is None:
                schema = table.schema
                writer = pq.ParquetWriter(out_path, schema)
            writer.write_table(table.cast(schema))
            n_file += len(chunk)
        print(f"      {path.name}: {n_file:>9,} linhas")
        total += n_file

    if writer is not None:
        writer.close()
    print(f"      total: {total:,} linhas")
    return total


def load_to_bigquery(parquet_path: Path, expected_rows: int) -> None:
    project = os.environ["GCP_PROJECT_ID"]
    dataset = os.getenv("BQ_DATASET_RAW", "raw")
    client = bigquery.Client(project=project)

    ds = bigquery.Dataset(f"{project}.{dataset}")
    ds.location = "US"
    client.create_dataset(ds, exists_ok=True)

    table_id = f"{project}.{dataset}.{TABLE_NAME}"
    print(f"[3/3] Carregando em {table_id} (WRITE_TRUNCATE)")
    job_config = bigquery.LoadJobConfig(
        source_format=bigquery.SourceFormat.PARQUET,
        write_disposition=bigquery.WriteDisposition.WRITE_TRUNCATE,
        clustering_fields=["SG_UF"],
    )
    with open(parquet_path, "rb") as fh:
        job = client.load_table_from_file(fh, table_id, job_config=job_config)
    job.result()

    table = client.get_table(table_id)
    print(f"      {table.num_rows:,} linhas na tabela")
    if table.num_rows != expected_rows:
        raise RuntimeError(f"Esperado {expected_rows:,}, carregado {table.num_rows:,}")


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__.split("\n")[1])
    parser.add_argument("--ufs", default=os.getenv("UFS", "DF,SP,MG,BA,RS,AM"))
    parser.add_argument("--anos", default=os.getenv("ANOS", "2022,2026"))
    args = parser.parse_args()
    ufs = [u.strip().upper() for u in args.ufs.split(",") if u.strip()]
    anos = [int(a) for a in args.anos.split(",") if a.strip()]

    # todos os anos vão num único Parquet + único WRITE_TRUNCATE (atômico e idempotente)
    files = [(p, uf) for ano in anos for p, uf in zip(ensure_files(ano, ufs), ufs)]
    with tempfile.TemporaryDirectory() as tmp:
        parquet_path = Path(tmp) / "despesas.parquet"
        total = build_parquet(files, parquet_path)
        load_to_bigquery(parquet_path, total)
    print("OK")


if __name__ == "__main__":
    main()
