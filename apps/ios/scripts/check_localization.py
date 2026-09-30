#!/usr/bin/env python3
"""Check translation coverage and printf arguments without requiring an Xcode build."""
import json
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
CATALOG = ROOT / "Multiverse/Resources/Localizable.xcstrings"
strings = json.loads(CATALOG.read_text())["strings"]
issues = []
placeholder = re.compile(r"%(?:(\d+)\$)?(?:0?\d+)?(lld|ld|d|f|@)")


def arguments(value):
    matches = placeholder.findall(value.replace("%%", ""))
    return sorted((int(position or i + 1), kind) for i, (position, kind) in enumerate(matches))


def units(localization):
    if "stringUnit" in localization:
        return {"default": localization["stringUnit"]}
    return {rule: variant["stringUnit"] for rule, variant in localization["variations"]["plural"].items()}


for key, entry in strings.items():
    localizations = entry.get("localizations", {})
    if set(localizations) != {"pt-BR", "en"}:
        issues.append(f"Missing or unexpected language: {key}")
        continue
    pt, en = units(localizations["pt-BR"]), units(localizations["en"])
    if set(pt) != set(en):
        issues.append(f"Plural rules differ: {key}")
        continue
    for rule in pt:
        if any(unit[rule]["state"] != "translated" for unit in [pt, en]):
            issues.append(f"Unfinished translation: {key}/{rule}")
        if arguments(pt[rule]["value"]) != arguments(en[rule]["value"]):
            issues.append(f"Format arguments differ: {key}/{rule}")

pattern = re.compile(r'L10n\.(?:text|format)\("((?:\\.|[^"\\])*)"')
for folder in ["Multiverse", "MultiverseWidgets"]:
    for source in (ROOT / folder).rglob("*.swift"):
        for match in pattern.finditer(source.read_text()):
            key = json.loads('"' + match.group(1) + '"')
            if key not in strings:
                issues.append(f"Missing catalog entry in {source.relative_to(ROOT)}: {key}")

if issues:
    raise SystemExit("\n".join(issues))
print(f"Localization OK: {len(strings)} entries in pt-BR/en; placeholders and source references checked.")
