# Funções de mensagens e personalização do WhatsApp

## Funções solicitadas

| Categoria | Função | Implementação segura | Dependência |
|---|---|---|---|
| Mensagens | Preservar o texto digitado depois de enviar | Salvar o último rascunho local e restaurá-lo no composer após o envio | Identificar a classe/view do composer ativa |
| Mensagens | Repetir a última mensagem | Botão local de repetir o texto anterior, sem envio automático | Hook do composer e confirmação do usuário |
| Mensagens | Pré-visualização de texto longo | Mostrar preview local com contagem de caracteres e linhas | UIKit, sem envio |
| Mensagens | Fonte e cor do texto | Aplicar fonte, cor e peso a labels/text views de mensagem | `WATheme`, `WATextMessage`, células ativas |
| Mensagens | Bolhas | Cor, raio, borda, sombra e espaçamento | Classes de bubble da versão instalada |
| Mensagens | Replies e previews | Fonte, cor, fundo e borda do trecho citado | Views de reply ativas |
| Privacidade | Confirmação de leitura | Controle local e reversível, validando `readReceiptSettingsMixin` | Instância de privacidade ativa |
| Privacidade | Indicador de digitação | Controle visual local de `typing indicator` | Classes de typing/presence |
| Privacidade | Status online | Personalizar somente a apresentação local do indicador | Não alterar presença real de terceiros |
| Privacidade | Status visto por último | Preferência visual local, sem burlar política do servidor | API de privacidade da versão instalada |
| Privacidade | Silenciar chamadas desconhecidas | Expor apenas se a preferência estiver presente e for reversível | `privacy_silence_unknown_caller` |
| Tema | Criar tema | Nome, modo, paleta, fonte, wallpaper, ícones e dimensões | Modelo persistente próprio |
| Tema | Paleta | Abrir `UIColorPickerViewController` para cada token | UIKit |
| Tema | Tokens | Fundo, superfície, texto, texto secundário, destaque, bolha recebida, bolha enviada, link e alerta | AppearanceEngine dirigido |
| Tema | Exportar/importar | JSON local do tema, sem dados de mensagens | Armazenamento do tweak |
| Notificações | Cor e estilo do badge | Aplicar somente ao badge visual local | `notificationBadgeCount` e views ativas |
| Notificações | Som/feedback local | Preferências para a UI, sem interceptar notificações de terceiros | Notification Center/versão instalada |
| Notificações | Preview | Controlar visibilidade de preview na interface local | Classes de notification content |
| Status | Cor do indicador | Ajustar o círculo/bolha de status nas views ativas | `statusButton`, chips e views de status |
| Status | Imagem/GIF local | Usar imagem própria somente em componentes selecionados | Preservar tamanho e proporção original |
| Status | Texto do status | Fonte, cor, alinhamento e fundo | `WAStatusTextView`, composer de status |
| Status | Vídeo | Ajustar apresentação local e preview | Não remover limites de upload ou duração do servidor |
| Ícones | Substituição persistente | Trocar somente o componente identificado, usando o tamanho original | Classe/contexto do botão |
| Navigation Bar | Nome e ícone | Aplicar por item e salvar configuração | `UITabBarController`/`WDSTabBar` ativo |

## Sistema de temas

Cada tema deve ser salvo com um identificador, nome, modo claro/escuro, mapa de cores, fonte, wallpaper e ativos. A tela do editor deve listar cada token com o nome da propriedade e uma amostra colorida; ao tocar, abre a paleta nativa para escolher a cor. O editor deve oferecer salvar, duplicar, ativar, exportar e restaurar padrão.

Os tokens iniciais são `background`, `surface`, `primaryText`, `secondaryText`, `accent`, `incomingBubble`, `outgoingBubble`, `link`, `separator`, `statusOnline`, `notificationBadge` e `composer`. A aplicação deve ser feita na árvore UIKit ativa e, quando a classe proprietária for confirmada, nos objetos `WATheme` ou `WDSColorScheme` correspondentes.

## Regras de validação

Antes de qualquer hook, o Flex deve confirmar classe, seletor, assinatura, tipo de retorno e instância ativa. A função deve aparecer no menu como `Pronta`, `Aplicada`, `Não encontrada` ou `Incompatível`. O modo `default` deve deixar o comportamento original. Nenhuma função deve enviar mensagens automaticamente, alterar presença real de terceiros, provocar crash ou burlar limites de mídia do WhatsApp.

## Limites técnicos

O SharedModules é um dump de interfaces e não garante que todas as classes estejam instanciadas na mesma versão. `WAMutableChatSession`, `WATheme`, `WDSTabBar` e componentes Swift/WDS precisam ser obtidos a partir da instância ativa; chamar métodos em uma classe encontrada mas sem objeto correto pode falhar. O recurso de preservar o composer e repetir texto requer identificar o controlador real da conversa, não apenas procurar qualquer `UITextView`.

A matriz completa de classes e métodos está em `SharedModules-customization-catalog.md`, `SharedModules-message-privacy-status-map.txt` e `SharedModules-function-matrix.md`.
