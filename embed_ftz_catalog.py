from pathlib import Path
import json
import base64

src = Path('/home/ubuntu/dylibtest/FTZWhatsAppCompleteCatalog.json')
data = json.loads(src.read_text(encoding='utf-8'))
compact = json.dumps(data, ensure_ascii=False, separators=(',', ':')).encode('utf-8')
encoded = base64.b64encode(compact).decode('ascii')
chunks = [encoded[i:i+120] for i in range(0, len(encoded), 120)]
lines = ['#import <Foundation/Foundation.h>', '', 'static NSString * const kFTZEmbeddedSafeCatalogBase64 =', *[f'    @"{chunk}"' + (';' if i == len(chunks)-1 else '') for i, chunk in enumerate(chunks)], '', 'static NSString *FTZEmbeddedSafeCatalogString(void) {', '    NSData *data = [[NSData alloc] initWithBase64EncodedString:kFTZEmbeddedSafeCatalogBase64 options:0];', '    return data ? [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding] : @"[]";', '}', '']
Path('/home/ubuntu/dylibtest/FTZEmbeddedCatalog.h').write_text('\n'.join(lines), encoding='utf-8')
print('base64_chunks', len(chunks), 'json_bytes', len(compact))
