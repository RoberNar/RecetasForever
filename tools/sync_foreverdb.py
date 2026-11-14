#!/usr/bin/env python3
"""
Descarga una sola vez las recetas desde la API de ForeverDB.net (usando caché
local para evitar consultas repetidas) y genera RecetarioForever/ForeverDB_Data.lua.

Uso:
  1. Copia tools/foreverdb_config.example.json a tools/foreverdb_config.json
     y coloca tu token en "token" (o usa la variable de entorno FOREVERDB_TOKEN).
  2. Ejecuta:  python tools/sync_foreverdb.py
  3. Dentro del juego, abre /recetas y pulsa "Cargar ForeverDB" una sola vez.

También puedes convertir un JSON ya descargado sin hacer llamadas a la API:
  python tools/sync_foreverdb.py --from-file recipes.json
"""

from __future__ import annotations

import argparse
import datetime as dt
import hashlib
import json
import os
import sys
import time
import urllib.error
import urllib.request
from pathlib import Path
from typing import Any

ROOT = Path(__file__).resolve().parent.parent
TOOLS_DIR = Path(__file__).resolve().parent
CONFIG_PATH = TOOLS_DIR / "foreverdb_config.json"
EXAMPLE_PATH = TOOLS_DIR / "foreverdb_config.example.json"
CACHE_DIR = TOOLS_DIR / "cache"
OUT_LUA = ROOT / "RecetarioForever" / "ForeverDB_Data.lua"

PROF_MAP = {
    "alchemy": "Alchemy",
    "blacksmithing": "Blacksmithing",
    "cooking": "Cooking",
    "enchanting": "Enchanting",
    "engineering": "Engineering",
    "first-aid": "First Aid",
    "first aid": "First Aid",
    "leatherworking": "Leatherworking",
    "mining": "Mining",
    "smelting": "Mining",
    "tailoring": "Tailoring",
    "jewelcrafting": "Jewelcrafting",
    "inscription": "Inscription",
}

SOURCE_MAP = {
    "trainer": "trainer",
    "entrenador": "trainer",
    "instructor": "trainer",
    "vendor": "vendor",
    "vendedor": "vendor",
    "reputation": "reputation",
    "reputacion": "reputation",
    "quest": "quest",
    "mision": "quest",
    "drop": "drop",
    "world_drop": "drop",
    "discovery": "discovery",
}


def load_config() -> dict[str, Any]:
    path = CONFIG_PATH if CONFIG_PATH.exists() else EXAMPLE_PATH
    with path.open("r", encoding="utf-8") as fh:
        cfg = json.load(fh)
    env_token = os.environ.get("FOREVERDB_TOKEN", "").strip()
    if env_token:
        cfg["token"] = env_token
    return cfg


def fetch_json(url: str, cfg: dict[str, Any], refresh: bool) -> Any:
    CACHE_DIR.mkdir(parents=True, exist_ok=True)
    cache_key = hashlib.sha256(url.encode("utf-8")).hexdigest()[:20]
    cache_file = CACHE_DIR / f"{cache_key}.json"
    if cache_file.exists() and not refresh:
        return json.loads(cache_file.read_text(encoding="utf-8"))

    token = str(cfg.get("token", "")).strip()
    if not token or token == "PEGA_AQUI_TU_TOKEN_DE_FOREVERDB":
        raise RuntimeError(
            "Falta el token de ForeverDB. Ponlo en tools/foreverdb_config.json "
            "o en la variable FOREVERDB_TOKEN."
        )

    headers = {
        "Accept": "application/json",
        "User-Agent": "RecetarioForever-Sync/1.0 (+https://github.com/RoberNar/RecetasForever)",
        cfg.get("auth_header", "Authorization"): f"{cfg.get('auth_prefix', 'Bearer ')}{token}",
    }
    req = urllib.request.Request(url, headers=headers, method="GET")
    delay = float(cfg.get("request_delay_sec", 1.5))
    time.sleep(max(0.5, delay))

    try:
        with urllib.request.urlopen(req, timeout=30) as resp:
            raw = resp.read().decode("utf-8")
    except urllib.error.HTTPError as exc:
        body = exc.read().decode("utf-8", errors="replace")[:300]
        raise RuntimeError(f"HTTP {exc.code} al consultar {url}: {body}") from exc

    data = json.loads(raw)
    cache_file.write_text(json.dumps(data, ensure_ascii=False, indent=2), encoding="utf-8")
    return data


def extract_list(payload: Any) -> list[dict[str, Any]]:
    if isinstance(payload, list):
        return [x for x in payload if isinstance(x, dict)]
    if isinstance(payload, dict):
        for key in ("recipes", "data", "items", "results"):
            val = payload.get(key)
            if isinstance(val, list):
                return [x for x in val if isinstance(x, dict)]
    return []


def parse_thresholds(entry: dict[str, Any]) -> list[int | None]:
    sr = entry.get("thresholds") or entry.get("skillRange") or entry.get("skill_range")
    if isinstance(sr, list) and len(sr) >= 4:
        return [int(x) if x is not None else None for x in sr[:4]]
    if isinstance(sr, dict):
        return [
            sr.get("orange") or sr.get("optimal"),
            sr.get("yellow") or sr.get("medium"),
            sr.get("green") or sr.get("easy"),
            sr.get("gray") or sr.get("grey") or sr.get("trivial"),
        ]
    return [
        entry.get("orange") or entry.get("minSkill") or entry.get("reqSkill") or entry.get("skillRequired"),
        entry.get("yellow"),
        entry.get("green"),
        entry.get("gray") or entry.get("grey") or entry.get("maxTrivialLevel"),
    ]


def build_source_text(entry: dict[str, Any]) -> str | None:
    for key in ("sourceText", "source_text", "acquisition", "howToGet"):
        val = entry.get(key)
        if isinstance(val, str) and val.strip():
            return val.strip()
    parts: list[str] = []
    for label, key in (
        ("NPC", "npc"),
        ("Vendedor", "vendor"),
        ("Instructor", "trainer"),
        ("Zona", "zone"),
        ("Misión", "quest"),
        ("Facción", "faction"),
        ("Botín", "drop"),
    ):
        val = entry.get(key)
        if isinstance(val, str) and val.strip():
            parts.append(f"{label}: {val.strip()}")
        elif isinstance(val, dict) and val.get("name"):
            parts.append(f"{label}: {val['name']}")
    return "\n".join(parts) if parts else None


def normalize_entry(raw: dict[str, Any], default_prof: str | None = None) -> dict[str, Any] | None:
    prof_raw = str(raw.get("prof") or raw.get("profession") or default_prof or "").strip()
    prof = PROF_MAP.get(prof_raw.lower(), prof_raw)
    name = raw.get("name") or raw.get("recipeName") or raw.get("spellName")
    rid = raw.get("id") or raw.get("recipeID") or raw.get("spellID") or raw.get("spell_id")
    if not prof or (not name and not rid):
        return None

    thresholds = parse_thresholds(raw)
    req_skill = raw.get("reqSkill") or raw.get("skillRequired") or raw.get("minSkill") or thresholds[0]
    src_raw = str(raw.get("source") or raw.get("sourceType") or raw.get("source_type") or "").strip().lower()
    source = SOURCE_MAP.get(src_raw) or (src_raw if src_raw else None)

    reagents_out: list[dict[str, int]] = []
    for rg in raw.get("reagents") or []:
        if isinstance(rg, dict):
            item_id = rg.get("itemID") or rg.get("item_id") or rg.get("id")
            count = rg.get("count") or rg.get("quantity") or 1
            if item_id:
                reagents_out.append({"itemID": int(item_id), "count": int(count)})

    return {
        "prof": prof,
        "id": int(rid) if rid is not None else None,
        "name": str(name) if name else None,
        "reqSkill": int(req_skill) if req_skill is not None else None,
        "thresholds": [int(x) if x is not None else None for x in thresholds],
        "source": source,
        "sourceText": build_source_text(raw),
        "productID": int(raw["productID"]) if raw.get("productID") else None,
        "icon": raw.get("icon"),
        "reagents": reagents_out,
    }


def lua_str(value: str) -> str:
    escaped = (
        value.replace("\\", "\\\\")
        .replace('"', '\\"')
        .replace("\r", "")
        .replace("\n", "|n")
    )
    return f'"{escaped}"'


def render_lua(recipes: list[dict[str, Any]]) -> str:
    today = dt.datetime.now().strftime("%Y-%m-%d %H:%M")
    lines = [
        "-- Generado por tools/sync_foreverdb.py (Data from ForeverDB.net)",
        "local ADDON, ns = ...",
        "",
        "ns.ExternalDB = {",
        "    meta = {",
        '        source = "ForeverDB.net",',
        f"        updatedAt = {lua_str(today)},",
        f"        count = {len(recipes)},",
        "    },",
        "    recipes = {",
    ]
    for r in recipes:
        fields = [f"prof = {lua_str(r['prof'])}"]
        if r["id"] is not None:
            fields.append(f"id = {r['id']}")
        if r["name"]:
            fields.append(f"name = {lua_str(r['name'])}")
        if r["reqSkill"] is not None:
            fields.append(f"reqSkill = {r['reqSkill']}")
        th = r["thresholds"]
        if any(x is not None for x in th):
            th_lua = ", ".join(str(x) if x is not None else "nil" for x in th)
            fields.append(f"thresholds = {{ {th_lua} }}")
        if r["source"]:
            fields.append(f"source = {lua_str(r['source'])}")
        if r["sourceText"]:
            fields.append(f"sourceText = {lua_str(r['sourceText'])}")
        if r["productID"] is not None:
            fields.append(f"productID = {r['productID']}")
        if r["reagents"]:
            rg_items = ", ".join(
                f"{{ itemID = {rg['itemID']}, count = {rg['count']} }}" for rg in r["reagents"]
            )
            fields.append(f"reagents = {{ {rg_items} }}")
        lines.append("        { " + ", ".join(fields) + " },")
    lines.extend(["    },", "}", ""])
    return "\n".join(lines)


def main() -> int:
    parser = argparse.ArgumentParser(description="Sincroniza recetas de ForeverDB a Lua.")
    parser.add_argument("--from-file", type=Path, help="Convierte un JSON local sin consultar la API.")
    parser.add_argument("--refresh", action="store_true", help="Ignora la caché local y vuelve a consultar.")
    args = parser.parse_args()

    normalized: list[dict[str, Any]] = []
    if args.from_file:
        payload = json.loads(args.from_file.read_text(encoding="utf-8"))
        for raw in extract_list(payload):
            item = normalize_entry(raw)
            if item:
                normalized.append(item)
    else:
        cfg = load_config()
        base = str(cfg.get("base_url", "https://foreverdb.net")).rstrip("/")
        endpoint = str(cfg.get("recipes_endpoint", "/api/recipes"))
        profs = cfg.get("professions") or []
        if "{profession}" in endpoint and profs:
            for p in profs:
                url = f"{base}{endpoint.format(profession=p)}"
                payload = fetch_json(url, cfg, args.refresh)
                for raw in extract_list(payload):
                    item = normalize_entry(raw, default_prof=p)
                    if item:
                        normalized.append(item)
        else:
            url = f"{base}{endpoint}"
            payload = fetch_json(url, cfg, args.refresh)
            for raw in extract_list(payload):
                item = normalize_entry(raw)
                if item:
                    normalized.append(item)

    OUT_LUA.write_text(render_lua(normalized), encoding="utf-8")
    print(f"Generado {OUT_LUA} con {len(normalized)} recetas.")
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except RuntimeError as exc:
        print(f"Error: {exc}", file=sys.stderr)
        raise SystemExit(1)
