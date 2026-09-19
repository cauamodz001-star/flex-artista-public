from PIL import Image
from pathlib import Path
src = Image.open('/home/ubuntu/dylibtest/Resources/profile-reference.jpg').convert('RGB')
out = Path('/home/ubuntu/dylibtest/Resources')
# A referência é um screenshot vertical; estes recortes isolam a faixa de banner e o avatar sobreposto.
src.crop((0, 73, 548, 245)).save(out / 'profile-banner-default.jpg', quality=92)
src.crop((28, 177, 169, 318)).save(out / 'profile-avatar-default.jpg', quality=92)
print(src.size)
