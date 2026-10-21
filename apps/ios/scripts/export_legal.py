#!/usr/bin/env python3
"""Export the same offline app documents to static, bilingual HTML; never deploys."""
import argparse
import html
import json
import re
from pathlib import Path
from urllib.parse import quote

ROOT = Path(__file__).resolve().parent.parent
RESOURCES = ROOT / 'Multiverse/Resources'
parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--output', type=Path, default=ROOT / 'build/legal')
parser.add_argument('--require-final', action='store_true', help='Refuse drafts or missing owner/contact.')
args = parser.parse_args()
config = json.loads((RESOURCES / 'LegalConfiguration.json').read_text())
email = config.get('supportEmail')
valid_email = email and re.fullmatch(r'[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}', email)
if args.require_final and (config['isDraft'] or not config.get('responsibleName') or not valid_email):
    parser.error('Publication pending: finalize the documents and confirm responsibleName/supportEmail first.')

escape = html.escape
style = '''body{margin:0;background:#f5f1e8;color:#202020;font:17px/1.6 system-ui,sans-serif}
main{max-width:740px;margin:auto;padding:32px 24px}h1,h2{line-height:1.2}h1{font-size:2.4rem}
h2{font-size:1.25rem;margin-top:2rem}a{color:inherit;text-underline-offset:4px}
nav{display:flex;gap:18px;flex-wrap:wrap}p{overflow-wrap:anywhere}.notice{border:2px solid;padding:16px;background:#ffe74a}
footer{margin-top:36px;border-top:2px solid;padding-top:20px}@media(prefers-color-scheme:dark){body{background:#191919;color:#f5f1e8}.notice{color:#202020}}'''
for lang in ['pt-BR', 'en']:
    docs = json.loads((RESOURCES / f'{lang}.lproj/LegalDocuments.json').read_text())
    out = args.output / lang
    out.mkdir(parents=True, exist_ok=True)
    for kind, doc in docs.items():
        nav = ' '.join(f'<a href="{escape(key)}.html">{escape(value["title"])}</a>' for key, value in docs.items())
        other = 'en' if lang == 'pt-BR' else 'pt-BR'
        nav += f' <a href="../{other}/{kind}.html" lang="{other}">{"English" if other == "en" else "Português"}</a>'
        draft = ''
        if config['isDraft']:
            draft = '<p class="notice">'+ ('Documento em revisão antes do lançamento público.' if lang == 'pt-BR' else 'Document under review before public launch.')+'</p>'
        owner = f'<p>{escape(config["responsibleName"])}</p>' if config.get('responsibleName') else ''
        sections = ''.join(f'<section><h2>{escape(s["title"])}</h2><p>{escape(s["body"])}</p></section>' for s in doc['sections'])
        contact = f'<a href="mailto:{quote(email, safe="@")}">{escape(email)}</a>' if valid_email else ('Contato de atendimento pendente.' if lang == 'pt-BR' else 'Support contact pending.')
        text = f'<!doctype html>\n<html lang="{lang}"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1"><title>{escape(doc["title"])} · Multiverse</title><style>{style}</style></head><body><main><nav aria-label="Multiverse">{nav}</nav><h1>{escape(doc["title"])}</h1><p>Multiverse · {escape(config["revision"])}</p>{draft}{owner}{sections}<footer>{contact}</footer></main></body></html>\n'
        (out / f'{kind}.html').write_text(text)
print(f'Exported 6 pages to {args.output.resolve()}; no publication performed.')
