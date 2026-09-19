# Mapa de personalização do WhatsApp/Watusi

## Escopo analisado

O arquivo `SharedModules.txt` contém aproximadamente **251.806 linhas**, **7,3 MB** e **9.922 interfaces**. O inventário foi processado por blocos de `@interface` e classificado por símbolos associados a wallpaper, imagens, ícones, fonte, tema, cor, toque, gesto, navegação e componentes UIKit.

O dump é uma lista de interfaces e assinaturas, não é o código-fonte das implementações. Portanto, ele revela pontos de entrada e tipos prováveis, mas não garante que todas as propriedades sejam públicas, que existam instâncias acessíveis em todos os fluxos ou que as assinaturas permaneçam iguais entre versões do Zap.

## Pontos mais promissores

| Área | Classes encontradas | Símbolos relevantes | Estratégia recomendada | Risco |
|---|---|---|---|---|
| Wallpaper de conversa | `WAChatSession`, `WAMutableChatSession`, `WAChatWallpaper`, `WAWallpaperLibrary` | `wallpaper`, `chatTheme`, `colorScheme`, `setWallpaperImagePath:isGenAIImage:`, `setWallpaperSolidColor:`, `setWallpaperDimming:`, `setChatWallpaper:`, `setCurrentWallpaperImage:dimLevel:isGenAIImage:forChatSession:forDarkMode:` | Localizar a sessão ativa e chamar setters somente quando a classe e a assinatura existirem | Alto |
| Tema e cores globais | `WATheme`, `WASearchTheme`, `WAThemeColoringHelperWrapper` | `applyAppearances`, `reloadColorsAndStyles`, `applySwitchAppearance`, `setActive:`, `highlightedTintColorForColor:` | Obter o objeto de tema em tempo de execução e aplicar uma paleta controlada, com checagem de seletor | Alto |
| Tipografia do app | `WATheme` | `genericHeaderFont`, `genericButtonFont`, `contactNameFont`, `chatNameFont`, `chatMessageFont`, `chatTimestampFont`, `reloadFonts`, `reloadFontsInView:` | Preferir `reloadFontsInView:` ou a API de recarga já existente; não substituir fontes indiscriminadamente em objetos desconhecidos | Médio/alto |
| Ícones e botões | `WACircularImageButton`, `WDSIconButton`, `WDSIconButtonConfiguration` | `iconTintColor`, `iconBackgroundColor`, `borderColor`, `setIcon:`, `setForegroundColor:`, `setBackgroundColor:` | Alterar somente instâncias identificadas por classe, acessibilidade ou contexto de tela; evitar substituir toda `UIImageView` | Médio/alto |
| Navegação e barras | `WANavigationController`, `WDSTabBar`, `WDSTabBarItem` | `setNavigationBarHidden:animated:`, `setViewControllers:`, `applyTopBarAppearanceWorkaroundIfNeededForAnimatedPop:actions:` | Personalizar a aparência das barras e tabs por instância ativa, sem trocar métodos de navegação | Médio |
| Lista de conversas | `WDSChatListItemView`, `WDSChatListItemTableCell` | `updateWithConfig:`, `updateWithConfigurator:`, `config` | Aplicar estilo após a célula ser configurada; exige identificação da instância e momento de atualização | Alto |
| Editor e texto multimídia | `WAMediaGraphicFontTypeHelper`, `WAMediaGraphicTextView`, `WAMultiSendHeaderView` | `fontType`, `textFont`, `setTextFontType:`, `applyFontType:`, `createEditingBottomBarViewWithMode:selectedFontType:selectedColor:` | Focar primeiro no menu e no composer; editor tem assinaturas mais voláteis | Alto |
| Toque e gestos | `WAClosureTapGestureRecognizer`, `WASecondaryClickGestureRecognizer`, vários delegates UIKit | `handlePanGesture:`, `handleTapGesture:`, `gestureRecognizer:shouldReceiveTouch:`, `touchesBegan:withEvent:` | Usar uma camada própria de indicador e preferências; somente criar gestos adicionais em telas específicas | Médio |

## O que o dump permite fazer com segurança relativa

A parte mais segura é personalizar a **nossa própria interface**: ícone dos patches, wallpaper do painel, fonte dos textos do painel e estilo do indicador de toque. Isso já foi integrado na dylibtest e permanece persistente em `Documents/FlexDesign` e `NSUserDefaults`.

Também é relativamente seguro aplicar uma paleta visual a instâncias UIKit encontradas na janela ativa, desde que a alteração seja limitada a `UILabel`, `UIButton`, `UISwitch`, `UITableView` e barras conhecidas. Essa camada deve ser reaplicada quando uma tela termina de aparecer, sem swizzle global de `UIView` ou `UIWindow`.

## O que exige engenharia dirigida à versão do Zap

A troca do wallpaper real das conversas deve usar `WAChatSession`/`WAWallpaperLibrary`. O dump mostra setters específicos e estruturas de wallpaper, mas não informa como obter a sessão ativa nem quais argumentos concretos cada versão espera. A implementação correta precisa descobrir a instância em runtime, validar `respondsToSelector:`, preservar o objeto original e aplicar a mudança depois que uma conversa estiver aberta.

A troca dos ícones do próprio WhatsApp também não pode ser feita substituindo todas as imagens globalmente. O dump mostra configuradores de ícones (`WDSIconButtonConfiguration`) e botões circulares (`WACircularImageButton`), mas cada tela pode fornecer o ícone por um configurador diferente. O caminho seguro é criar regras por classe/contexto, começando por botões com identificador de acessibilidade ou por uma tela específica.

A troca de toda a fonte do app é possível em tese por `WATheme`, porque existem várias propriedades tipográficas e métodos de recarga. Porém, forçar uma fonte que não esteja instalada ou substituir diretamente objetos internos pode provocar tela quebrada. A primeira versão deve aceitar apenas nomes retornados por `UIFont familyNames` e manter fallback para a fonte do sistema.

## Arquitetura de integração proposta

1. **DesignStore** mantém imagens, fonte, cores, escala e estilo de toque.
2. **AppearanceEngine** aplica apenas alterações seguras à janela ativa e aos componentes conhecidos.
3. **ZapAdapters** contém adaptadores opcionais para `WATheme`, `WAWallpaperLibrary`, `WAChatSession`, `WACircularImageButton` e `WDSIconButtonConfiguration`.
4. Cada adaptador deve testar a existência da classe e dos seletores antes de executar.
5. A aplicação deve ser acionada pelo menu e por eventos de ciclo de vida, não por swizzle global indiscriminado.
6. O menu deve mostrar o estado de cada personalização e permitir desfazer/restaurar o padrão.

## Conclusão

Sim, o SharedModules mostra que existe uma superfície real para alterar o próprio Zap: **wallpaper de conversa, tema, esquema de cores, fontes de mensagens e cabeçalhos, botões circulares, ícones configuráveis, barras de navegação, tabs e gestos**. O caminho correto não é alterar tudo ao mesmo tempo. É começar pelo motor seguro e pelos componentes com assinaturas claras, depois ativar adaptadores de wallpaper, tema e ícones por versão, sempre com fallback e validação de seletor para evitar o fechamento automático do WhatsApp.

O inventário bruto e os blocos de assinaturas permanecem no repositório para auditoria: `SharedModules.txt`, `SharedModules-signatures.txt`, `SharedModules-candidate-index.txt` e `SharedModules-inventory.txt`.
