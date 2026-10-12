"""Pull a small sample of public GLEIF Level 1 records (api.gleif.org, no login) into JSONL."""
import json
import time
import urllib.parse
import urllib.request

PLAN = {"IN": 2000, "GB": 1000, "DE": 1000, "FR": 500, "US": 500}
PAGE = 200
OUT = "gleif_sample.jsonl"


def fetch(country, page):
    q = urllib.parse.urlencode({
        "filter[entity.legalAddress.country]": country,
        "filter[entity.status]": "ACTIVE",
        "page[size]": PAGE,
        "page[number]": page,
    })
    req = urllib.request.Request(
        "https://api.gleif.org/api/v1/lei-records?" + q,
        headers={"Accept": "application/vnd.api+json"},
    )
    with urllib.request.urlopen(req, timeout=60) as r:
        return json.load(r)["data"]


def slim(rec):
    e = rec["attributes"]["entity"]
    addr = e["legalAddress"]
    return {
        "lei": rec["id"],
        "name": e["legalName"]["name"],
        "other_names": [n["name"] for n in e.get("otherNames", [])],
        "country": addr["country"],
        "city": addr.get("city"),
        "postcode": addr.get("postalCode"),
        "registered_as": e.get("registeredAs"),
        "category": e.get("category"),
    }


with open(OUT, "w", encoding="utf-8") as f:
    for country, n in PLAN.items():
        got = 0
        page = 1
        while got < n:
            for rec in fetch(country, page):
                f.write(json.dumps(slim(rec), ensure_ascii=False) + "\n")
                got += 1
            page += 1
            time.sleep(1)
        print(country, got, flush=True)
