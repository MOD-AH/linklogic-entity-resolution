"""Turn gleif_sample.jsonl into records.csv: each LEI once, plus noisy variants with the same truth_group."""
import csv
import json
import random
import re

random.seed(42)
SRC = "gleif_sample.jsonl"
OUT = "records.csv"
VARIANT_RATE = 0.5

SUFFIX_SWAPS = [
    (r"\bLIMITED\b", "LTD"), (r"\bLTD\.?\b", "LIMITED"),
    (r"\bPRIVATE\b", "PVT"), (r"\bPVT\.?\b", "PRIVATE"),
    (r"\bCOMPANY\b", "CO"), (r"\bCORPORATION\b", "CORP"),
    (r"\bAND\b", "&"), (r"&", "AND"),
    (r"\bINDUSTRIES\b", "INDS"), (r"\bTECHNOLOGIES\b", "TECH"),
]


def typo(s):
    i = random.randrange(1, len(s) - 1)
    kind = random.choice(["drop", "swap", "dup"])
    if kind == "drop":
        return s[:i] + s[i + 1:]
    if kind == "swap":
        return s[:i] + s[i + 1] + s[i] + s[i + 2:]
    return s[:i] + s[i] + s[i:]


def make_variant(rec):
    name = rec["name"]
    # a registered trading name is the most realistic alias
    if rec["other_names"] and random.random() < 0.3:
        return random.choice(rec["other_names"]), "alias"
    ops = random.sample(["suffix", "case", "punct", "typo", "the", "dropword"], k=random.choice([1, 1, 2]))
    for op in ops:
        if op == "suffix":
            for pat, rep in random.sample(SUFFIX_SWAPS, len(SUFFIX_SWAPS)):
                if re.search(pat, name, flags=re.I):
                    name = re.sub(pat, rep, name, count=1, flags=re.I)
                    break
        elif op == "case":
            name = random.choice([name.upper(), name.title(), name.lower()])
        elif op == "punct":
            name = re.sub(r"[ ,.]+", lambda m: random.choice([" ", ", ", ". "]), name)
        elif op == "typo" and len(name) > 6:
            name = typo(name)
        elif op == "the":
            name = "THE " + name
        elif op == "dropword":
            words = name.split()
            if len(words) > 2:
                words.pop(random.randrange(1, len(words)))
                name = " ".join(words)
    return name, "+".join(ops)


rows = []
aliases = []
with open(SRC, encoding="utf-8") as f:
    for line in f:
        r = json.loads(line)
        aliases += [(r["lei"], a) for a in r["other_names"]]
        rows.append(("GLEIF", r["lei"], r["name"], r["country"], r["city"], r["postcode"], r["lei"], "base"))
        if random.random() < VARIANT_RATE:
            vname, how = make_variant(r)
            pc = r["postcode"] if random.random() < 0.7 else ""
            rows.append(("NOISY_COPY", r["lei"] + "#v", vname, r["country"], r["city"], pc, r["lei"], how))

random.shuffle(rows)
with open(OUT, "w", newline="", encoding="utf-8") as f:
    w = csv.writer(f)
    w.writerow(["source", "source_key", "name_raw", "country", "city", "postcode", "truth_group", "variant_kind", "arrival"])
    for i, row in enumerate(rows):
        w.writerow(list(row) + [i])
print(len(rows), "rows;", sum(1 for r in rows if r[0] == "NOISY_COPY"), "variants")

with open("aliases.csv", "w", newline="", encoding="utf-8") as f:
    w = csv.writer(f)
    w.writerow(["lei", "alias"])
    w.writerows(aliases)
print(len(aliases), "registered trading names")
