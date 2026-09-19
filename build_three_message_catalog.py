from pathlib import Path
import json

features = [
    {
        'name': 'Mensagens · Gatilho com resposta',
        'desc': 'Quando uma mensagem recebida corresponder ao gatilho configurado, usar a resposta definida pelo usuário. Recurso desativado por padrão e limitado para evitar loops.',
        'source': 'Flex-message-feature',
        'enabled': False,
        'featureType': 'message-trigger-reply',
        'customHandler': 'FlexMessageTriggerReply',
        'validationState': 'custom-feature',
        'units': [{
            'name': 'Gatilho e resposta configuráveis',
            'class': 'FlexMessageTriggerReply',
            'selector': 'handleIncomingMessage:inChatSession:',
            'method': 'handleIncomingMessage:inChatSession: ➔ [void]',
            'arguments': ['triggerText', 'replyText', 'scope'],
            'overrideType': 'custom',
            'customValue': {'triggerText': '.', 'replyText': '', 'scope': 'manual'},
            'featureType': 'message-trigger-reply',
            'validationStatus': 'custom-feature-pending',
            'validationState': 'custom-feature'
        }]
    },
    {
        'name': 'Mensagens · Preservar texto após envio',
        'desc': 'Mantém o conteúdo digitado no composer depois do envio para permitir repetir a mensagem sem redigitar.',
        'source': 'Flex-message-feature',
        'enabled': False,
        'featureType': 'preserve-composer-text',
        'customHandler': 'FlexMessageComposerPersistence',
        'validationState': 'custom-feature',
        'units': [{
            'name': 'Preservar texto do composer',
            'class': 'FlexMessageComposerPersistence',
            'selector': 'restoreComposerTextAfterSend:',
            'method': 'restoreComposerTextAfterSend: ➔ [void]',
            'arguments': ['composerText'],
            'overrideType': 'custom',
            'customValue': {'enabled': True},
            'featureType': 'preserve-composer-text',
            'validationStatus': 'custom-feature-pending',
            'validationState': 'custom-feature'
        }]
    },
    {
        'name': 'Mensagens · Preservar seleção após envio',
        'desc': 'Restaura a seleção local de texto ou itens do composer quando o usuário retorna à conversa depois do envio.',
        'source': 'Flex-message-feature',
        'enabled': False,
        'featureType': 'preserve-composer-selection',
        'customHandler': 'FlexMessageComposerPersistence',
        'validationState': 'custom-feature',
        'units': [{
            'name': 'Preservar seleção do composer',
            'class': 'FlexMessageComposerPersistence',
            'selector': 'restoreComposerSelectionAfterSend:',
            'method': 'restoreComposerSelectionAfterSend: ➔ [void]',
            'arguments': ['selectionState'],
            'overrideType': 'custom',
            'customValue': {'enabled': True},
            'featureType': 'preserve-composer-selection',
            'validationStatus': 'custom-feature-pending',
            'validationState': 'custom-feature'
        }]
    }
]
Path('/home/ubuntu/dylibtest/FTZWhatsAppCompleteCatalog.json').write_text(json.dumps(features, ensure_ascii=False, separators=(',', ':')) + '\n', encoding='utf-8')
classes = []
for p in features:
    for u in p['units']:
        classes.append({'class': u['class'], 'unitCount': 1, 'selectors': [u['selector']], 'methods': [u['method']], 'appIdentifiers': ['net.whatsapp.WhatsApp'], 'patchNames': [p['name']], 'validationState': 'custom-feature'})
Path('/home/ubuntu/dylibtest/FTZWhatsAppClassesCatalog.json').write_text(json.dumps({'source':'Flex-message-features-only','classes':classes}, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')
summary = {'patches': 3, 'units': 3, 'uniqueClasses': 2, 'uniqueSelectors': 3, 'onlyFeatures': [p['featureType'] for p in features], 'importMode': 'manual plist/ZIP remains available'}
Path('/home/ubuntu/dylibtest/FTZWhatsAppCatalogSummary.json').write_text(json.dumps(summary, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')
print(json.dumps(summary, ensure_ascii=False, indent=2))
