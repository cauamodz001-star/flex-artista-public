from pathlib import Path
import json
from collections import defaultdict

src = Path('/home/ubuntu/dylibtest/ftz-plist-sanitized.json')
root = json.loads(src.read_text(encoding='utf-8'))
allowed = {'net.whatsapp.WhatsApp', 'net.whatsapp.WhatsAppSMB'}
# Recursos solicitados pelo usuário ficam disponíveis somente no importador manual.
manual_only_terms = ('auto_reply', 'autoreply', 'auto reply', 'preserve text after send', 'preserve selection after send', 'repeat message')
selected = []
classes = defaultdict(lambda: {'units': 0, 'selectors': set(), 'methods': set(), 'apps': set(), 'patches': set()})
for pidx, raw_patch in enumerate(root.get('patches', [])):
    if not isinstance(raw_patch, dict) or raw_patch.get('appIdentifier') not in allowed:
        continue
    patch_text = json.dumps(raw_patch, ensure_ascii=False).lower()
    if any(term in patch_text for term in manual_only_terms):
        continue
    patch = dict(raw_patch)
    patch['catalogSource'] = 'FTZ-WhatsApp-complete'
    patch['catalogIndex'] = pidx
    patch['enabled'] = False
    patch['validationState'] = 'needs-validation'
    units = []
    for uidx, raw_unit in enumerate(patch.get('units', []) or []):
        if not isinstance(raw_unit, dict):
            continue
        unit_text = json.dumps(raw_unit, ensure_ascii=False).lower()
        if any(term in unit_text for term in manual_only_terms):
            continue
        unit = dict(raw_unit)
        obj = unit.get('methodObjc') if isinstance(unit.get('methodObjc'), dict) else {}
        cls = unit.get('class') or obj.get('className') or ''
        selector = unit.get('selector') or obj.get('selector') or ''
        display = unit.get('method') or unit.get('displayName') or obj.get('displayName') or ''
        unit['catalogUnitIndex'] = uidx
        unit['class'] = cls
        unit['selector'] = selector
        unit['method'] = display
        unit.setdefault('name', display or f'Unit {uidx + 1}')
        unit.setdefault('arguments', [])
        unit.setdefault('overrideType', 'default')
        unit['enabled'] = False
        unit['validationState'] = 'needs-validation'
        unit['validationStatus'] = 'pending'
        unit['appIdentifier'] = raw_patch.get('appIdentifier')
        units.append(unit)
        if cls:
            c = classes[cls]
            c['units'] += 1
            c['apps'].add(raw_patch.get('appIdentifier'))
            c['patches'].add(str(raw_patch.get('name', '')))
            if selector: c['selectors'].add(selector)
            if display: c['methods'].add(display)
    patch['units'] = units
    selected.append(patch)

class_rows = []
for cls in sorted(classes, key=str.lower):
    c = classes[cls]
    class_rows.append({'class': cls, 'unitCount': c['units'], 'selectors': sorted(c['selectors']), 'methods': sorted(c['methods']), 'appIdentifiers': sorted(c['apps']), 'patchNames': sorted(c['patches']), 'validationState': 'needs-validation'})

Path('/home/ubuntu/dylibtest/FTZWhatsAppCompleteCatalog.json').write_text(json.dumps(selected, ensure_ascii=False, separators=(',', ':')) + '\n', encoding='utf-8')
Path('/home/ubuntu/dylibtest/FTZWhatsAppClassesCatalog.json').write_text(json.dumps({'source':'FTZ-WhatsApp-complete','classes':class_rows}, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')
summary = {'patches': len(selected), 'units': sum(len(p['units']) for p in selected), 'uniqueClasses': len(class_rows), 'uniqueSelectors': len({s for c in class_rows for s in c['selectors']}), 'mainWhatsAppPatches': sum(p.get('appIdentifier') == 'net.whatsapp.WhatsApp' for p in selected), 'mainWhatsAppUnits': sum(len(p['units']) for p in selected if p.get('appIdentifier') == 'net.whatsapp.WhatsApp'), 'businessPatches': sum(p.get('appIdentifier') == 'net.whatsapp.WhatsAppSMB' for p in selected), 'businessUnits': sum(len(p['units']) for p in selected if p.get('appIdentifier') == 'net.whatsapp.WhatsAppSMB'), 'parameterizedUnits': sum(bool(u.get('overrides') or u.get('arguments')) for p in selected for u in p['units']), 'messageRelatedUnits': sum(any(t in f"{u.get('class','')} {u.get('selector','')} {u.get('method','')}".lower() for t in ('message','text','composer','chat','send','receipt','typing')) for p in selected for u in p['units'])}
Path('/home/ubuntu/dylibtest/FTZWhatsAppCatalogSummary.json').write_text(json.dumps(summary, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')
print(json.dumps(summary, ensure_ascii=False, indent=2))
