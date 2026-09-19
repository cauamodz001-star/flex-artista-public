import plistlib
import json
from pathlib import Path

src = Path('/home/ubuntu/dylibtest/ftz-import/patches.plist')
raw = plistlib.loads(src.read_bytes())

def shape(value, depth=0):
    if depth > 3:
        return type(value).__name__
    if isinstance(value, dict):
        return {str(k): shape(v, depth + 1) for k, v in list(value.items())[:20]}
    if isinstance(value, list):
        return {'__list__': len(value), 'sample': [shape(v, depth + 1) for v in value[:3]]}
    return type(value).__name__

summary = {
    'root_type': type(raw).__name__,
    'count': len(raw) if hasattr(raw, '__len__') else None,
    'shape': shape(raw),
}
Path('/home/ubuntu/dylibtest/ftz-plist-summary.json').write_text(json.dumps(summary, ensure_ascii=False, indent=2), encoding='utf-8')
print(json.dumps(summary, ensure_ascii=False, indent=2))
if isinstance(raw, dict):
    print('ROOT_KEYS:', list(raw.keys())[:50])
    for key, value in list(raw.items())[:10]:
        print('ENTRY', repr(key), type(value).__name__, repr(value)[:500])
else:
    for i, value in enumerate(raw[:10]):
        print('ENTRY', i, type(value).__name__, repr(value)[:500])
