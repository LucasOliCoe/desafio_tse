"""Verifica se o .env, a credencial do GCP e a chave da Groq estão funcionando."""
import os

from dotenv import load_dotenv

load_dotenv()

project = os.getenv("GCP_PROJECT_ID")
key_path = os.getenv("GOOGLE_APPLICATION_CREDENTIALS")
print(f"GCP_PROJECT_ID = {project}")
print(f"credencial     = {key_path} (existe: {bool(key_path) and os.path.exists(key_path)})")

# --- BigQuery
from google.cloud import bigquery

client = bigquery.Client(project=project)
rows = list(client.query("SELECT 'BigQuery OK' AS status").result())
print(rows[0].status)

# --- Groq
if os.getenv("GROQ_API_KEY", "").startswith("gsk_") and len(os.getenv("GROQ_API_KEY")) > 10:
    from groq import Groq

    resp = Groq().chat.completions.create(
        model=os.getenv("GROQ_MODEL", "openai/gpt-oss-120b"),
        messages=[{"role": "user", "content": "Responda apenas: Groq OK"}],
        max_tokens=300,
    )
    print(resp.choices[0].message.content)
else:
    print("GROQ_API_KEY não configurada (só será necessária na Etapa 4)")
