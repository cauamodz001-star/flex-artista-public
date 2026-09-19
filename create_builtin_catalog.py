from pathlib import Path
import json

base = json.loads(Path('/home/ubuntu/dylibtest/FTZSafePatches.json').read_text(encoding='utf-8'))
units = base[0].get('units', []) if base and isinstance(base[0], dict) else []

def u(name, cls, method, return_type, selector=None, description=''):
    return {
        'name': name,
        'class': cls,
        'selector': selector or method.split(' ')[0],
        'method': f'{method} ➔ [{return_type}]',
        'overrideType': 'default',
        'customValue': '',
        'arguments': [],
        'source': 'SharedModules-built-in',
        'description': description,
        'validationStatus': 'pending'
    }

builtins = [
    {
        'name': 'Flex · Mensagens e presença',
        'desc': 'Funções comuns de leitura de estado para mensagens, contatos e presença. Desativadas por padrão.',
        'source': 'SharedModules-built-in', 'enabled': False,
        'units': [
            u('WAContact · isVerified', 'WAContact', 'isVerified', 'boolean', description='Controla o retorno lógico do estado verificado do contato.'),
            u('WAName · isVerifiedBusiness', 'WAName', 'isVerifiedBusiness', 'boolean', description='Controla o estado de empresa verificada.'),
            u('WAMessage · containsMentions', 'WAMessage', 'containsMentions', 'boolean', description='Consulta se a mensagem contém menções.'),
            u('WAMessage · isTextOrURL', 'WAMessage', 'isTextOrURL', 'boolean', description='Identifica mensagens de texto ou URL.'),
            u('WAMessage · textContainsURLs', 'WAMessage', 'textContainsURLs', 'boolean', description='Identifica URLs no texto da mensagem.'),
            u('WAMessageContainer · isValid', 'WAMessageContainer', 'isValid', 'boolean', description='Consulta a validade do contêiner da mensagem.'),
            u('WATextMessage · usesFontLeading', 'WATextMessage', 'usesFontLeading', 'boolean', description='Controla o uso de font leading na renderização de texto.'),
        ]
    },
    {
        'name': 'Flex · Wallpaper e tema avançado',
        'desc': 'Estados de wallpaper, doodle e experimentos visuais encontrados no SharedModules.',
        'source': 'SharedModules-built-in', 'enabled': False,
        'units': [
            u('WAMutableChatSession · hasCustomWallpaper', 'WAMutableChatSession', 'hasCustomWallpaper', 'boolean', description='Consulta se a conversa tem wallpaper personalizado.'),
            u('WAMutableChatSession · hasValidWallpaper', 'WAMutableChatSession', 'hasValidWallpaper', 'boolean', description='Consulta se o wallpaper da conversa é válido.'),
            u('WAChatWallpaper · isDoodleEnabled', 'WAChatWallpaper', 'isDoodleEnabled', 'boolean', description='Consulta o estado do doodle do wallpaper.'),
            u('WAWallpaperLibrary · wallpaperDoodleEnabledLight', 'WAWallpaperLibrary', 'wallpaperDoodleEnabledLight', 'boolean', description='Estado do doodle no modo claro.'),
            u('WAWallpaperLibrary · wallpaperDoodleEnabledDark', 'WAWallpaperLibrary', 'wallpaperDoodleEnabledDark', 'boolean', description='Estado do doodle no modo escuro.'),
            u('WDSWallpaperDoodleOverlayView · isDoodleImageHidden', 'WDSWallpaperDoodleOverlayView', 'isDoodleImageHidden', 'boolean', description='Consulta se a camada de doodle está oculta.'),
            u('WAPreferences · wallpaperParallaxDisabled', 'WAPreferences', 'wallpaperParallaxDisabled', 'boolean', description='Consulta a preferência de desativação do parallax.'),
        ]
    },
    {
        'name': 'Flex · Indicadores online e notificações',
        'desc': 'Flags reversíveis de presença, badge e notificações. Devem ser validadas na versão instalada.',
        'source': 'SharedModules-built-in', 'enabled': False,
        'units': [
            u('WAABProperties · ios_group_online_green_dot_enabled', 'WAABProperties', 'ios_group_online_green_dot_enabled', 'boolean', description='Flag visual do ponto verde de grupos online.'),
            u('WAABProperties · info_online_presence_text_enabled', 'WAABProperties', 'info_online_presence_text_enabled', 'boolean', description='Flag de texto informativo de presença.'),
            u('WAABProperties · ios_live_wallpapers_enabled', 'WAABProperties', 'ios_live_wallpapers_enabled', 'boolean', description='Flag de suporte a wallpapers animados.'),
            u('GraphQLNotificationProcessor · stickyNotificationsOn', 'GraphQL.GraphQLNotificationProcessor', 'stickyNotificationsOn', 'boolean', description='Consulta o estado de notificações persistentes.'),
            u('PeerMessageStatusNotificationManager · status', 'PeerMessages.PeerMessageStatusNotificationManager', 'status', 'object', description='Inspeciona o estado do gerenciador de notificações de mensagens.'),
        ]
    },
    {
        'name': 'Flex · Tipografia e componentes visuais',
        'desc': 'Pontos de entrada para fonte, labels, botões e componentes visuais do WhatsApp.',
        'source': 'SharedModules-built-in', 'enabled': False,
        'units': [
            u('WATheme · chatMessageFont', 'WATheme', 'chatMessageFont', 'object', description='Fonte usada nas mensagens de conversa.'),
            u('WATheme · chatTimestampFont', 'WATheme', 'chatTimestampFont', 'object', description='Fonte usada nos timestamps.'),
            u('WATheme · contactNameFont', 'WATheme', 'contactNameFont', 'object', description='Fonte usada nos nomes de contatos.'),
            u('WABadgedLabel · font', 'WABadgedLabel', 'font', 'object', description='Fonte do label com badge.'),
            u('WACircularImageButton · iconTintColor', 'WACircularImageButton', 'iconTintColor', 'object', description='Cor do ícone do botão circular.'),
        ]
    }
]

for patch in builtins:
    for item in base:
        if item.get('name') == patch['name']:
            break
    else:
        base.append(patch)

out = Path('/home/ubuntu/dylibtest/FTZSafePatches.json')
out.write_text(json.dumps(base, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')
print('patches', len(base), 'units', sum(len(p.get('units', [])) for p in base))
