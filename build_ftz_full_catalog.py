from pathlib import Path
import json
from collections import defaultdict

root = json.loads(Path('/home/ubuntu/dylibtest/ftz-plist-sanitized.json').read_text(encoding='utf-8'))
patches = root.get('patches', [])
classes = defaultdict(lambda: {'units': 0, 'selectors': set(), 'methods': set(), 'apps': set(), 'patches': set()})
complete = []
for pidx, patch in enumerate(patches):
    if not isinstance(patch, dict):
        continue
    item = dict(patch)
    item['catalogIndex'] = pidx
    item['catalogSource'] = 'FTZ-complete-sanitized'
    item['enabled'] = False
    item['validationState'] = 'needs-validation'
    app = str(item.get('appIdentifier', ''))
    normalized_units = []
    for uidx, raw in enumerate(item.get('units', []) or []):
        if not isinstance(raw, dict):
            continue
        unit = dict(raw)
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
        normalized_units.append(unit)
        if cls:
            c = classes[cls]
            c['units'] += 1
            c['apps'].add(app)
            c['patches'].add(str(item.get('name', '')))
            if selector: c['selectors'].add(selector)
            if display: c['methods'].add(display)
    item['units'] = normalized_units
    complete.append(item)

serializable_classes = []
for cls in sorted(classes, key=lambda x: x.lower()):
    c = classes[cls]
    serializable_classes.append({
        'class': cls,
        'unitCount': c['units'],
        'selectors': sorted(c['selectors']),
        'methods': sorted(c['methods']),
        'appIdentifiers': sorted(c['apps']),
        'patchNames': sorted(c['patches']),
        'validationState': 'needs-validation'
    })

Path('/home/ubuntu/dylibtest/FTZCompleteCatalog.json').write_text(json.dumps({'source':'FTZ-complete-sanitized','patches':complete}, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')
Path('/home/ubuntu/dylibtest/FTZClassesCatalog.json').write_text(json.dumps({'source':'FTZ-complete-sanitized','classes':serializable_classes}, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')
summary = {
    'patches': len(complete),
    'units': sum(len(p['units']) for p in complete),
    'uniqueClasses': len(serializable_classes),
    'uniqueSelectors': len({s for c in serializable_classes for s in c['selectors']}),
    'apps': sorted({str(p.get('appIdentifier','')) for p in complete}),
    'whatsappPatches': sum(1 for p in complete if p.get('appIdentifier') == 'net.whatsapp.WhatsApp'),
    'whatsappUnits': sum(len(p['units']) for p in complete if p.get('appIdentifier') == 'net.whatsapp.WhatsApp'),
    'whatsappSMBPatches': sum(1 for p in complete if p.get('appIdentifier') == 'net.whatsapp.WhatsAppSMB'),
    'whatsappSMBUnits': sum(len(p['units']) for p in complete if p.get('appIdentifier') == 'net.whatsapp.WhatsAppSMB'),
    'parameterizedUnits': sum(1 for p in complete for u in p['units'] if u.get('overrides') or u.get('arguments')),
    'messageRelatedUnits': sum(1 for p in complete for u in p['units'] if any(t in f"{u.get('class','')} {u.get('selector','')} {u.get('method','')}".lower() for t in ('message','text','composer','chat','send','receipt','typing')))
}
Path('/home/ubuntu/dylibtest/FTZFullCatalogSummary.json').write_text(json.dumps(summary, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')
print(json.dumps(summary, ensure_ascii=False, indent=2))
