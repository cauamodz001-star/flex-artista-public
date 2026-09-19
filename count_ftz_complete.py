from pathlib import Path
import json
from collections import Counter, defaultdict

src = Path('/home/ubuntu/dylibtest/ftz-plist-sanitized.json')
data = json.loads(src.read_text(encoding='utf-8'))
patches = data.get('patches', data if isinstance(data, list) else [])
classes = Counter()
selectors = Counter()
methods = Counter()
units_total = 0
units_with_args = 0
message_units = 0
argument_values = 0
patch_rows = []
for patch in patches:
    units = patch.get('units', []) if isinstance(patch, dict) else []
    patch_rows.append({'name': patch.get('name', ''), 'units': len(units), 'appIdentifier': patch.get('appIdentifier', '')})
    for unit in units:
        if not isinstance(unit, dict):
            continue
        units_total += 1
        method_objc = unit.get('methodObjc') or {}
        cls = unit.get('class') or method_objc.get('className') or ''
        selector = unit.get('selector') or method_objc.get('selector') or ''
        display = unit.get('method') or unit.get('displayName') or method_objc.get('displayName') or ''
        if cls: classes[cls] += 1
        if selector: selectors[selector] += 1
        if display: methods[display] += 1
        overrides = unit.get('overrides') or []
        if overrides:
            units_with_args += 1
            argument_values += len(overrides)
        if any(token in f'{cls} {selector} {display}'.lower() for token in ('message', 'text', 'composer', 'chat', 'send', 'receipt', 'typing')):
            message_units += 1
out = {
    'source': str(src),
    'patches': len(patches),
    'units': units_total,
    'unique_classes': len(classes),
    'unique_selectors': len(selectors),
    'unique_method_displays': len(methods),
    'units_with_overrides_or_arguments': units_with_args,
    'argument_override_entries': argument_values,
    'message_related_units': message_units,
    'top_classes': classes.most_common(100),
    'top_selectors': selectors.most_common(100),
    'patch_rows': patch_rows,
}
Path('/home/ubuntu/dylibtest/ftz-complete-count.json').write_text(json.dumps(out, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')
print(json.dumps({k: v for k, v in out.items() if k not in ('top_classes', 'top_selectors', 'patch_rows')}, ensure_ascii=False, indent=2))
print('PATCHES:')
for row in patch_rows:
    print(f"{row['units']}\t{row['appIdentifier']}\t{row['name']}")
