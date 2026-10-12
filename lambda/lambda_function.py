"""Embeds company names with Titan Text Embeddings V2 and indexes / queries them in S3 Vectors.

Invoked either directly (event = {"mode": "index"|"query", "records": [...]})
or by an SQS FIFO trigger (each message body is the same JSON as one record,
MessageGroupId = country + first token of the normalised name).
"""
import json
import os
import re

import boto3

REGION = os.environ.get("AWS_REGION", "ap-southeast-2")
BUCKET = os.environ.get("VECTOR_BUCKET", "linklogic-vectors-<account-id>")
INDEX = os.environ.get("VECTOR_INDEX", "company-names")
MODEL = "amazon.titan-embed-text-v2:0"
DIMS = 256

bedrock = boto3.client("bedrock-runtime", region_name=REGION)
vectors = boto3.client("s3vectors", region_name=REGION)

LEGAL = re.compile(r"\b(pvt|private|ltd|limited|llp|inc|incorporated|corp|corporation|co|company|plc|gmbh|sa|sas|sarl|ag|bv|nv|llc|oyj|ab|as|spa|srl)\b")


def normalize(name):
    s = re.sub(r"[^a-z0-9 ]+", " ", name.lower())
    return re.sub(r"\s+", " ", LEGAL.sub(" ", s)).strip()


def embed(text):
    resp = bedrock.invoke_model(
        modelId=MODEL,
        body=json.dumps({"inputText": text, "dimensions": DIMS, "normalize": True}),
    )
    return json.loads(resp["body"].read())["embedding"]


def index_records(records):
    batch = [
        {
            "key": str(r["id"]),
            "data": {"float32": embed(normalize(r["name"]))},
            "metadata": {"country": r["country"], "name": r["name"]},
        }
        for r in records
    ]
    for i in range(0, len(batch), 500):
        vectors.put_vectors(vectorBucketName=BUCKET, indexName=INDEX, vectors=batch[i:i + 500])
    return {"indexed": len(batch)}


def query_records(records, top_k=5):
    out = []
    for r in records:
        res = vectors.query_vectors(
            vectorBucketName=BUCKET,
            indexName=INDEX,
            queryVector={"float32": embed(normalize(r["name"]))},
            topK=top_k,
            filter={"country": r["country"]},
            returnMetadata=True,
            returnDistance=True,
        )
        out.append({
            "id": r["id"],
            "candidates": [
                {"key": v["key"], "name": v["metadata"]["name"],
                 "cosine_similarity": round(1 - v["distance"], 4)}
                for v in res["vectors"]
            ],
        })
    return out


def handler(event, context):
    if "Records" in event:  # SQS trigger
        records = [json.loads(m["body"]) for m in event["Records"]]
        mode = records[0].get("mode", "query")
    else:
        records, mode = event["records"], event.get("mode", "query")
    result = index_records(records) if mode == "index" else query_records(records)
    print(json.dumps({"mode": mode, "n": len(records)}))  # lands in CloudWatch Logs
    return result
