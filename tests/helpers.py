"""Shared test helpers. Synthetic data only."""
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SCHEMAS = ROOT / 'contracts' / 'schemas' / 'v1'
SENTINEL = ROOT / 'fivem' / 'resources' / '[sentinel]' / 'sentinel_telemetry'
ECONOMY = ROOT / 'fivem' / 'resources' / '[rp]' / 'rp_economy'


def load_json(path):
    return json.loads(Path(path).read_text(encoding='utf-8'))


def validator_for(event_type):
    from jsonschema import Draft202012Validator, FormatChecker

    schema = load_json(SCHEMAS / f'{event_type}.schema.json')
    Draft202012Validator.check_schema(schema)
    return Draft202012Validator(schema, format_checker=FormatChecker())


def lua_runtime(*files):
    """Lua 5.4 runtime (via lupa) with the given resource files loaded."""
    from lupa import lua54

    lua = lua54.LuaRuntime(unpack_returned_tuples=True)
    for file in files:
        lua.execute(Path(file).read_text(encoding='utf-8'))
    return lua


def lua_to_py(value):
    """Convert a Lua table into plain dict/list structures."""
    if hasattr(value, 'items'):
        items = dict(value.items())
        if items and all(isinstance(k, int) for k in items):
            return [lua_to_py(items[k]) for k in sorted(items)]
        return {k: lua_to_py(v) for k, v in items.items()}
    return value


def pair(result):
    """Normalise a Lua `return a, b` / `return a` call result to a 2-tuple."""
    if isinstance(result, tuple):
        return (result + (None, None))[:2]
    return result, None
