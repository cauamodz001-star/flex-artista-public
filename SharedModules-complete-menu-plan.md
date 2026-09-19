# Plano completo do menu SharedModules

O dump analisado contém 251.806 linhas e 9.922 interfaces. O catálogo foi organizado por áreas para que o Flex não mostre símbolos aleatórios, mas ofereça funções agrupadas por finalidade.

## Categorias do menu

| Categoria | Componentes principais | Funções planejadas | Nível inicial |
|---|---|---|---|
| Tema e cores | `WATheme`, `WDSColorScheme`, `WAChatTheme` | modo claro/escuro, cor de destaque, cores de fundo, texto, links e navegação | Seguro quando aplicado à árvore UIKit ativa |
| Wallpaper de conversas | `WAWallpaperLibrary`, `WAMutableChatSession`, `WAChatWallpaper`, `WAPreferences` | escolher imagem, remover, voltar ao padrão, escurecimento, doodle, imagem clara/escura | Experimental por depender da instância de `WAChatSession` |
| Tipografia | `WATheme`, `WATextFormatter`, `WABadgedLabel`, `WAContactNameLabel`, `WATextMessage` | fonte base, nomes, mensagens, timestamps, links, negrito, itálico e monoespaçada | Seguro para views UIKit; APIs proprietárias precisam de assinatura validada |
| Navigation Bar | `WDSTabBar`, `WDSTabBarItem`, `WANavigationController`, `UITabBarController` | nomes, ícones, cor, item selecionado, item não selecionado e ordem | Seguro quando a barra ativa for identificada |
| Ícones e imagens | `WACircularImageButton`, `WDSIconButtonConfiguration`, `WAMessage`, células de lista | substituir ícones por imagem própria, preservar escala, recorte e template | Seguro somente por classe/contexto; não substituir imagens globalmente |
| Conversas e mensagens | `WAMutableChatSession`, classes de chat bubble e message cell | wallpaper, bolhas, raio, espaçamento, fonte de mensagem, timestamp e preview | Experimental até validar as classes da versão instalada |
| Listas | `WDSChatListItemView`, `WDSChatListItemTableCell`, `UITableView` | fonte, avatar, separador, altura, destaque, animação original | Seguro em subclasses identificadas |
| Animações | métodos `willDisplay`, configurações de transição e animação do projeto original | manter estilos originais, habilitar/desabilitar, intensidade e aplicação por tela | Preservar o motor original; sem swizzle novo por padrão |
| Gestos e toque | `UIWindow`, `UIScrollView`, controles UIKit e visualizador original | indicador de toque, tamanho, linha, cor, estilo e gestos de navegação | Preservar o sistema original do ZIP; alterações devem ser opcionais |
| Mídia e status | `WAPaintCanvasView`, `WAPaintCanvasTextView`, `WAStatusTextView` | fonte de status, estilos de texto e configurações de mídia | Experimental e restrito às telas correspondentes |
| Recursos do Watusi | classes e propriedades `WAABProperties`, `WAPreferences` e módulos WDS | expor somente flags comprovadas e reversíveis | Experimental; nunca habilitar flags de servidor/crash sem teste |
| Funções dinâmicas | navegador de framework/classe/método do Flex | validar classe, seletor, assinatura, retorno, valor e status | Núcleo do Flex, seguindo a lógica original |

## Regras de aplicação

Cada função deve validar a existência da classe, do método e do tipo de retorno antes de ser ativada. A unidade deve registrar `ready`, `invalid` ou `default`, com uma mensagem curta explicando o resultado. O valor `default` não deve substituir o método original. Para métodos booleanos sem argumentos, `true` e `false` devem ser normalizados para os valores que o executor original já suporta.

A substituição de imagens deve usar o tamanho do controle original, `scaleAspectFit`, preservação de proporção e recorte somente dentro dos limites da view. Nunca se deve trocar todas as imagens do aplicativo por uma regra global, pois isso pode afetar avatares, thumbnails, stickers e ícones sem relação com a função selecionada.

O sistema original de animação e toque deve permanecer como fonte de verdade. O design novo deve controlar apenas preferências, cores, fontes e ativos; ele não deve substituir o ciclo original de eventos. Hooks em classes proprietárias do WhatsApp devem ser dirigidos por classe e instalados somente depois que a janela principal estiver disponível.

## Menu proposto

O caminho principal será `Flex → três pontos → WhatsApp UI`. Dentro dele haverá `Tema e cores`, `Wallpaper de conversas`, `Tipografia`, `Navigation Bar`, `Ícones e imagens`, `Conversas e mensagens`, `Listas`, `Animações`, `Gestos e toque` e `Funções dinâmicas`. As categorias experimentais devem apresentar um aviso de compatibilidade e registrar falhas sem derrubar o WhatsApp.

## Limitações conhecidas

O dump descreve interfaces e assinaturas, mas não garante que toda classe esteja instanciada em todas as versões do Zap. Por isso, o menu deve validar a classe ativa em tempo de execução. Alterações em `WATheme`, `WAMutableChatSession` e classes Swift/WDS devem ser feitas somente após confirmar o tipo real do objeto. Métodos com argumentos complexos não devem ser chamados por `NSInvocation` genérico sem uma assinatura conhecida.
