"""Validador de mods para autores: python -m pocx.mods validate <carpeta-del-mod>

Aplica las mismas reglas que game/core/mod_registry.gd (manifiesto, id == carpeta, juegos,
tablas protegidas) y avisa de lo que el lanzador rechazaria al cargar.
"""
from __future__ import annotations

import json
import re
import sys
from pathlib import Path

API_VERSION = 1
GAMES = ("yugi", "kaiba", "joey")
ENGINES = ("faithful", "ocg")
SUPPORTED_ENGINES = ("faithful",)
PROTECTED_PREFIXES = ("common/bin/", "common/db/")
PROTECTED_FILES = ("inventory.json", "voice_manifest.json")
ID_RE = re.compile(r"^[a-z0-9][a-z0-9_-]{1,39}$")
SCRIPT_RE = re.compile(r"^scripts/[A-Za-z0-9_-]+(/[A-Za-z0-9_-]+)*\.gd$")
MAX_SCRIPTS = 8


def validate_manifest(data: object, folder_name: str) -> list[str]:
    """Errores del manifiesto (lista vacia = valido)."""
    if not isinstance(data, dict):
        return ["mod.json no es un objeto JSON valido"]
    errors: list[str] = []
    mod_id = str(data.get("id", ""))
    if not ID_RE.match(mod_id):
        errors.append("id invalido (a-z, 0-9, _ y -, 2 a 40 caracteres)")
    elif mod_id != folder_name:
        errors.append(f"la carpeta '{folder_name}' no coincide con el id '{mod_id}'")
    if not str(data.get("name", "")).strip():
        errors.append("falta name")
    if not str(data.get("version", "")).strip():
        errors.append("falta version")
    api = data.get("api")
    if isinstance(api, bool) or not isinstance(api, (int, float)) or api != API_VERSION:
        errors.append(f"api debe ser {API_VERSION}")
    games = data.get("games", list(GAMES))
    if not isinstance(games, list) or not games:
        errors.append("games no puede estar vacio")
    else:
        errors += [f"juego desconocido: {g}" for g in games if str(g) not in GAMES]
    if str(data.get("engine", "faithful")) not in ENGINES:
        errors.append(f"engine desconocido: {data.get('engine')}")
    requires = data.get("requires", [])
    if not isinstance(requires, list):
        errors.append("requires debe ser una lista")
    else:
        errors += [f"requires contiene un id invalido: {r}" for r in requires if not ID_RE.match(str(r))]
    scripts = data.get("scripts", [])
    if not isinstance(scripts, list):
        errors.append("scripts debe ser una lista de rutas scripts/<nombre>.gd")
    else:
        if len(scripts) > MAX_SCRIPTS:
            errors.append(f"scripts admite como mucho {MAX_SCRIPTS} archivos")
        errors += [f"script invalido (usa scripts/<nombre>.gd): {s}" for s in scripts
                   if not (isinstance(s, str) and len(s) <= 100 and SCRIPT_RE.match(s))]
    return errors


LANGS = ("spa", "eng", "fra", "ger", "ita", "jpn")
ATTRIBUTES = ("none", "light", "dark", "water", "fire", "earth", "wind", "divine")
KINDS = ("normal", "effect", "fusion", "ritual")
KEY_RE = re.compile(r"^[a-z0-9_]{1,40}$")
IMAGE_RE = re.compile(r"^[a-z0-9_.-]{1,60}\.(png|webp)$")
PASSWORD_RE = re.compile(r"^[0-9]{8}$")
EFFECT_RE = re.compile(r"^[a-z][a-z0-9_]{0,39}$")


def _texts(raw: object, field: str, max_len: int) -> list[str]:
    if not isinstance(raw, dict) or "eng" not in raw:
        return [f'{field} necesita al menos "eng"']
    errors = []
    for lang, text in raw.items():
        if lang not in LANGS or not isinstance(text, str):
            errors.append(f"{field}: idioma o texto invalido ({lang})")
        elif len(text) > max_len:
            errors.append(f"{field}.{lang} supera {max_len} caracteres")
    return errors


def _int_in(card: dict, field: str, lo: int, hi: int) -> list[str]:
    v = card.get(field)
    ok = isinstance(v, (int, float)) and not isinstance(v, bool) and v == int(v) and lo <= v <= hi
    return [] if ok else [f"{field} debe ser un entero entre {lo} y {hi}"]


def validate_card(card: object, mod_games: list[str]) -> list[str]:
    """Errores de una carta de cards.json (misma validacion que ModCards.parse_card)."""
    if not isinstance(card, dict):
        return ["la carta no es un objeto"]
    errors: list[str] = []
    if not KEY_RE.match(str(card.get("key", ""))):
        errors.append("key invalida (a-z, 0-9 y _, hasta 40)")
    category = str(card.get("category", "monster"))
    if category not in ("monster", "spell", "trap"):
        errors.append("category debe ser monster, spell o trap")
    errors += _texts(card.get("names"), "names", 60)
    errors += _texts(card.get("descriptions"), "descriptions", 1000)
    if category == "monster":
        errors += _int_in(card, "atk", 0, 5110) + _int_in(card, "defense", 0, 5110)
        if card.get("atk", 0) % 10 or card.get("defense", 0) % 10:
            errors.append("atk y defense deben ser multiplos de 10")
        errors += _int_in(card, "level", 0, 15) + _int_in(card, "type_id", 1, 24)
        if str(card.get("attribute", "none")) not in ATTRIBUTES:
            errors.append(f"attribute desconocido: {card.get('attribute')}")
        if str(card.get("monster_kind", "normal")) not in KINDS:
            errors.append(f"monster_kind desconocido: {card.get('monster_kind')}")
    games = card.get("games", mod_games)
    if not isinstance(games, list) or not games:
        errors.append("games no puede estar vacio")
    else:
        errors += [f"juego desconocido: {g}" for g in games if str(g) not in GAMES]
    image = card.get("image")
    if image is not None and not (isinstance(image, str) and IMAGE_RE.match(image)):
        errors.append("image debe ser un nombre de archivo .png/.webp sin carpetas")
    if not PASSWORD_RE.match(str(card.get("password", "00000000"))):
        errors.append("password debe tener 8 digitos")
    effect = card.get("effect", "")
    if effect != "" and not (isinstance(effect, str) and EFFECT_RE.match(effect)):
        errors.append("effect debe ser una clave a-z, 0-9 y _ (la implementa un script del mod)")
    if "revive_by" in card:
        revive = card["revive_by"]
        if not isinstance(revive, list):
            errors.append("revive_by debe ser una lista de ids internos (ej. 1008 = Monster Reborn)")
        else:
            for entry in revive:
                ok = isinstance(entry, int) and not isinstance(entry, bool) and 1 <= entry <= 1999
                if isinstance(entry, str):
                    try:
                        ok = 1 <= int(entry, 0) <= 1999
                    except ValueError:
                        ok = False
                if not ok:
                    errors.append(f"revive_by: id invalido: {entry}")
    return errors


def is_protected(rel_lower: str) -> bool:
    return rel_lower in PROTECTED_FILES or rel_lower.startswith(PROTECTED_PREFIXES)


def validate_mod(folder: Path) -> tuple[list[str], list[str]]:
    """(errores, avisos) de una carpeta de mod."""
    manifest_path = folder / "mod.json"
    if not manifest_path.is_file():
        return ["falta mod.json"], []
    try:
        data = json.loads(manifest_path.read_text(encoding="utf-8"))
    except (OSError, ValueError) as exc:
        return [f"mod.json ilegible: {exc}"], []
    errors = validate_manifest(data, folder.name)
    warnings: list[str] = []
    if errors:
        return errors, warnings
    if data.get("engine", "faithful") not in SUPPORTED_ENGINES:
        warnings.append(f"el lanzador aun no ejecuta el motor '{data['engine']}'")
    games = data.get("games", list(GAMES))
    for script in data.get("scripts", []):
        if not (folder / script).is_file():
            errors.append(f"falta el script {script}")
    if data.get("scripts"):
        warnings.append("este mod ejecuta codigo: el jugador debe activar 'Permitir mods que ejecutan codigo'")
    cards_path = folder / "cards.json"
    if cards_path.is_file():
        try:
            cards = json.loads(cards_path.read_text(encoding="utf-8"))
        except (OSError, ValueError) as exc:
            return [f"cards.json ilegible: {exc}"], warnings
        if not isinstance(cards, list):
            return ["cards.json debe ser una lista"], warnings
        keys: set[str] = set()
        for position, card in enumerate(cards):
            label = card.get("key", f"#{position}") if isinstance(card, dict) else f"#{position}"
            errors += [f"carta {label}: {e}" for e in validate_card(card, games)]
            if isinstance(card, dict):
                if card.get("key") in keys:
                    errors.append(f"carta {label}: key repetida")
                keys.add(card.get("key"))
                image = card.get("image")
                if isinstance(image, str):
                    for sub in ("card", "mini"):
                        if not (folder / "assets" / "common" / sub / image).is_file():
                            warnings.append(f"carta {label}: falta assets/common/{sub}/{image}")
        if errors:
            return errors, warnings
    seen: dict[str, str] = {}
    assets = folder / "assets"
    for path in sorted(p for p in assets.rglob("*") if p.is_file()) if assets.is_dir() else []:
        rel = path.relative_to(assets).as_posix()
        key = rel.lower()
        if key in seen and seen[key] != rel:
            errors.append(f"rutas que solo difieren en mayusculas: {seen[key]} / {rel}")
        seen[key] = rel
        if is_protected(key):
            warnings.append(f"se rechazara (tabla protegida): {rel}")
        elif key.split("/")[0] in GAMES and key.split("/")[0] not in games:
            warnings.append(f"se rechazara (juego no declarado): {rel}")
    return errors, warnings


MAX_INDEX = 0x45B


def image_size(path: Path) -> tuple[int, int] | None:
    """Ancho y alto de un PNG o WebP leyendo solo la cabecera (None si no se reconoce)."""
    import struct
    head = path.read_bytes()[:40]
    if head[:8] == b"\x89PNG\r\n\x1a\n":
        return struct.unpack(">II", head[16:24])
    if head[:4] == b"RIFF" and head[8:12] == b"WEBP":
        kind = head[12:16]
        if kind == b"VP8X":
            return (int.from_bytes(head[24:27], "little") + 1, int.from_bytes(head[27:30], "little") + 1)
        if kind == b"VP8L":
            bits = int.from_bytes(head[21:25], "little")
            return ((bits & 0x3FFF) + 1, ((bits >> 14) & 0x3FFF) + 1)
        if kind == b"VP8 ":
            return (struct.unpack("<H", head[26:28])[0] & 0x3FFF, struct.unpack("<H", head[28:30])[0] & 0x3FFF)
    return None


def inspect_tables(resources: Path, engine_src: Path | None = None) -> list[str]:
    """Informe de las tablas reales (PoC Data/resources) para fijar supuestos del cargador de cartas."""
    import struct
    out: list[str] = []
    bin_dir = resources / "common" / "bin"

    def read(name: str, fmt: str) -> tuple[int, ...]:
        raw = (bin_dir / name).read_bytes()
        size = struct.calcsize(fmt)
        return struct.unpack(f"<{len(raw) // size}{fmt}", raw[: len(raw) // size * size])

    ids, int_ids = read("card_id.bin", "H"), read("card_intid.bin", "H")
    props, packs = read("card_prop.bin", "I"), read("card_pack.bin", "H")
    out.append(f"entradas: card_id={len(ids)} card_intid={len(int_ids)} card_prop={len(props)} card_pack={len(packs)} (MAX_INDEX={MAX_INDEX})")
    occupied = [i for i in range(1, len(ids)) if ids[i] or (i < len(props) and props[i]) or (i < len(packs) and packs[i])]
    end = (max(occupied) + 1) if occupied else 1
    out.append(f"cartas ocupadas: {len(occupied)}; primer indice libre tras las tablas: {end}; hueco hasta MAX_INDEX: {max(0, MAX_INDEX - end + 1)}")
    used = {ids[i] for i in occupied}
    slots = {i % 2000 for i in used}
    out.append(f"ids internos en uso: {len(used)} (min {min(used)}, max {max(used)}); con variante +2000: {sum(1 for i in used if i >= 2000)}")
    bad = [i for i in occupied if ids[i] >= 2000 and (ids[i] - 2000 >= len(int_ids) or int_ids[ids[i] - 2000] + 1 != i)]
    out.append(f"variantes que NO cumplen index_of(id)=CARD_IntID[id%2000]+1: {len(bad)}" + (f" p.ej. indices {bad[:5]}" if bad else ""))
    mism = [i for i in occupied if ids[i] < 2000 and (ids[i] >= len(int_ids) or int_ids[ids[i]] != i)]
    out.append(f"ids base cuyo CARD_IntID no apunta a su indice: {len(mism)}" + (f" p.ej. indices {mism[:5]}" if mism else ""))
    candidates = [i for i in range(0x77F, 0, -1) if i not in slots][:40]
    out.append(f"primeros ids que asignaria el cargador (de 1919 hacia abajo): {candidates[:12]}")
    kinds, attrs, types = {}, {}, {}
    for i in occupied:
        p = props[i]
        t = (p >> 20) & 0x1F
        types[t] = types.get(t, 0) + 1
        if t < 21:
            attrs[(p >> 29) & 7] = attrs.get((p >> 29) & 7, 0) + 1
            kinds[(p >> 18) & 3] = kinds.get((p >> 18) & 3, 0) + 1
    out.append(f"tipos usados: {sorted(types.items())}")
    out.append(f"atributos de monstruo usados (0 none,1 light,2 dark,3 water,4 fire,5 earth,6 wind, 7 libre?): {sorted(attrs.items())}")
    out.append(f"clases de monstruo: {sorted(kinds.items())}")
    for label, t in (("magia", 22), ("trampa", 21)):
        sample = next((props[i] for i in occupied if (props[i] >> 20) & 0x1F == t), None)
        out.append(f"prop de ejemplo de {label}: {sample:#010x}" if sample is not None else f"sin {label}")
    for sub in ("card", "mini"):
        sizes: dict[tuple[int, int], int] = {}
        files = sorted((resources / "common" / sub).glob("*.*"))[:200] if (resources / "common" / sub).is_dir() else []
        for f in files:
            size = image_size(f)
            if size:
                sizes[size] = sizes.get(size, 0) + 1
        top = sorted(sizes.items(), key=lambda kv: -kv[1])[:3]
        out.append(f"tamanos de imagen en common/{sub} (los mas comunes, de {len(files)} archivos): {top}" if top else f"sin imagenes reconocibles en common/{sub}")
    db = resources / "common" / "db" / "cards.json"
    if db.is_file():
        cards = json.loads(db.read_text(encoding="utf-8"))
        db_end = 1
        for c in cards:
            if int(c["internal_id"]) != 0 or str(c.get("names", {}).get("eng", "")) != "":
                db_end = max(db_end, int(c["index"]) + 1)
        out.append(f"cards.json: {len(cards)} cartas; primer indice libre segun CardDB: {db_end} -> " + ("COINCIDE con las tablas" if db_end == end else f"NO COINCIDE (tablas {end})"))
    else:
        out.append("no hay common/db/cards.json en esa carpeta")
    if engine_src is not None and engine_src.is_dir():
        literals: set[int] = set()
        for f in engine_src.rglob("*.gd"):
            text = f.read_text(encoding="utf-8", errors="replace")
            literals.update(int(m, 16) for m in re.findall(r"\b0x([0-9a-fA-F]{1,4})\b", text))
            literals.update(int(m) for m in re.findall(r"\b(\d{1,4})\b", text))
        clash = [c for c in candidates if c in literals]
        out.append(f"ids candidatos que aparecen como literal en {engine_src}: {clash}" + (" (revisar antes de usarlos)" if clash else " (ninguno)"))
    return out


def main(argv: list[str]) -> int:
    if len(argv) >= 2 and argv[0] == "inspect":
        resources = Path(argv[1])
        try:
            for line in inspect_tables(resources, Path(argv[2]) if len(argv) > 2 else None):
                print(line)
        except (OSError, ValueError) as exc:
            print("error:", exc)
            return 1
        return 0
    if len(argv) != 2 or argv[0] != "validate":
        print("uso: python -m pocx.mods validate <carpeta-del-mod>")
        print("     python -m pocx.mods inspect <PoC Data/resources> [game/duel]")
        return 2
    errors, warnings = validate_mod(Path(argv[1]).resolve())
    for w in warnings:
        print("aviso:", w)
    for e in errors:
        print("error:", e)
    print("OK" if not errors else f"{len(errors)} error(es)")
    return 1 if errors else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
