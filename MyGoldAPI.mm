#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <CommonCrypto/CommonDigest.h>

static NSString * const kLicenseURL = @"https://aulh-hook.squareweb.app/api/login";
static NSString * const kSavedKey = @"dylibtest.license.key";

@interface MyGoldAPI : NSObject
@property(nonatomic, copy) NSString *username;
@property(nonatomic, copy) NSString *expiresAt;
@property(nonatomic, copy) NSString *lastMessage;
@property(nonatomic, assign, getter=isAuthenticated) BOOL authenticated;
+ (instancetype)shared;
- (void)validateKey:(NSString *)key completion:(void (^)(BOOL, NSString *))completion;
- (NSString *)savedKey;
- (void)logout;
@end

@implementation MyGoldAPI
+ (instancetype)shared {
    static MyGoldAPI *instance;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{ instance = [MyGoldAPI new]; });
    return instance;
}

- (NSString *)deviceHash {
    NSString *vendor = [[[UIDevice currentDevice] identifierForVendor] UUIDString] ?: @"";
    NSString *raw = [NSString stringWithFormat:@"%@|%@", vendor, UIDevice.currentDevice.model ?: @"iPhone"];
    unsigned char digest[CC_SHA256_DIGEST_LENGTH];
    CC_SHA256(raw.UTF8String, (CC_LONG)strlen(raw.UTF8String), digest);
    NSMutableString *result = [NSMutableString stringWithCapacity:CC_SHA256_DIGEST_LENGTH * 2];
    for (NSUInteger i = 0; i < CC_SHA256_DIGEST_LENGTH; i++) [result appendFormat:@"%02x", digest[i]];
    return result;
}

- (NSString *)savedKey {
    return [[NSUserDefaults standardUserDefaults] stringForKey:kSavedKey];
}

- (void)logout {
    [[NSUserDefaults standardUserDefaults] removeObjectForKey:kSavedKey];
    self.authenticated = NO;
    self.username = nil;
    self.expiresAt = nil;
}

- (void)validateKey:(NSString *)key completion:(void (^)(BOOL, NSString *))completion {
    NSString *normalized = [key stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    if (!normalized.length) { if (completion) completion(NO, @"Digite uma key válida."); return; }
    NSDictionary *payload = @{
        @"key": normalized,
        @"hwid": [self deviceHash],
        @"udid": [self deviceHash],
        @"device_type": UIDevice.currentDevice.model ?: @"iPhone",
        @"device_name": UIDevice.currentDevice.name ?: @"iPhone"
    };
    NSError *serializationError;
    NSData *body = [NSJSONSerialization dataWithJSONObject:payload options:0 error:&serializationError];
    if (!body) { if (completion) completion(NO, @"Não foi possível preparar a solicitação."); return; }
    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:[NSURL URLWithString:kLicenseURL]];
    request.HTTPMethod = @"POST";
    request.HTTPBody = body;
    request.timeoutInterval = 15.0;
    [request setValue:@"application/json" forHTTPHeaderField:@"Content-Type"];
    [request setValue:@"application/json" forHTTPHeaderField:@"Accept"];
    NSURLSessionDataTask *task = [[NSURLSession sharedSession] dataTaskWithRequest:request completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
        dispatch_async(dispatch_get_main_queue(), ^{
            if (error) { self.authenticated = NO; if (completion) completion(NO, @"Não foi possível conectar ao servidor."); return; }
            NSDictionary *json = data.length ? [NSJSONSerialization JSONObjectWithData:data options:0 error:nil] : nil;
            NSInteger statusCode = [(NSHTTPURLResponse *)response statusCode];
            BOOL accepted = statusCode >= 200 && statusCode < 300 && ([json[@"success"] boolValue] || [json[@"valid"] boolValue] || [json[@"status"] isEqual:@"active"] || [json[@"status"] isEqual:@"success"]);
            if (!accepted) { self.authenticated = NO; NSString *message = [json[@"error"] isKindOfClass:NSString.class] ? json[@"error"] : @"Key inválida ou expirada."; if (completion) completion(NO, message); return; }
            self.authenticated = YES;
            self.username = [json[@"username"] isKindOfClass:NSString.class] ? json[@"username"] : ([json[@"name"] isKindOfClass:NSString.class] ? json[@"name"] : @"Usuário");
            self.expiresAt = [json[@"expires_at"] isKindOfClass:NSString.class] ? json[@"expires_at"] : ([json[@"expiry"] isKindOfClass:NSString.class] ? json[@"expiry"] : nil);
            self.lastMessage = @"Acesso autorizado.";
            [[NSUserDefaults standardUserDefaults] setObject:normalized forKey:kSavedKey];
            [[NSUserDefaults standardUserDefaults] synchronize];
            if (completion) completion(YES, self.lastMessage);
        });
    }];
    [task resume];
}
@end

@interface MyGoldLoginViewController : UIViewController
@end

@interface ModsMenuController : UITableViewController
+ (void)openModsMenu;
@end

static UIWindow *MyGoldActiveWindow(void) {
    for (UIScene *scene in UIApplication.sharedApplication.connectedScenes) {
        if (![scene isKindOfClass:UIWindowScene.class]) continue;
        for (UIWindow *window in ((UIWindowScene *)scene).windows) if (window.isKeyWindow) return window;
    }
    for (UIScene *scene in UIApplication.sharedApplication.connectedScenes) {
        if (![scene isKindOfClass:UIWindowScene.class]) continue;
        UIWindowScene *windowScene = (UIWindowScene *)scene;
        if (windowScene.activationState == UISceneActivationStateUnattached) continue;
        if (windowScene.windows.firstObject) return windowScene.windows.firstObject;
    }
    return nil;
}

@implementation MyGoldLoginViewController {
    UITextField *_field;
    UILabel *_status;
    UIButton *_button;
    UIActivityIndicatorView *_spinner;
}
- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = [UIColor colorWithRed:.035 green:.043 blue:.075 alpha:1];
    self.title = @"Ativação";
    UILabel *title = [[UILabel alloc] initWithFrame:CGRectZero]; title.translatesAutoresizingMaskIntoConstraints = NO; title.text = @"Acesso seguro"; title.textColor = UIColor.whiteColor; title.font = [UIFont boldSystemFontOfSize:26]; title.textAlignment = NSTextAlignmentCenter;
    UILabel *detail = [[UILabel alloc] initWithFrame:CGRectZero]; detail.translatesAutoresizingMaskIntoConstraints = NO; detail.text = @"Insira sua key para abrir o menu."; detail.textColor = [UIColor colorWithWhite:1 alpha:.65]; detail.textAlignment = NSTextAlignmentCenter;
    _field = [[UITextField alloc] initWithFrame:CGRectZero]; _field.translatesAutoresizingMaskIntoConstraints = NO; _field.placeholder = @"KEY"; _field.textColor = UIColor.whiteColor; _field.textAlignment = NSTextAlignmentCenter; _field.autocorrectionType = UITextAutocorrectionTypeNo; _field.autocapitalizationType = UITextAutocapitalizationTypeAllCharacters; _field.backgroundColor = [UIColor colorWithWhite:0 alpha:.3]; _field.layer.cornerRadius = 14;
    _button = [UIButton buttonWithType:UIButtonTypeSystem]; _button.translatesAutoresizingMaskIntoConstraints = NO; [_button setTitle:@"VALIDAR" forState:UIControlStateNormal]; [_button setTitleColor:UIColor.blackColor forState:UIControlStateNormal]; _button.backgroundColor = [UIColor colorWithRed:.95 green:.72 blue:.12 alpha:1]; _button.layer.cornerRadius = 14; [_button addTarget:self action:@selector(submit) forControlEvents:UIControlEventTouchUpInside];
    _status = [[UILabel alloc] initWithFrame:CGRectZero]; _status.translatesAutoresizingMaskIntoConstraints = NO; _status.text = @"Aguardando key…"; _status.textColor = [UIColor colorWithWhite:1 alpha:.6]; _status.textAlignment = NSTextAlignmentCenter; _status.numberOfLines = 2;
    _spinner = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleMedium]; _spinner.translatesAutoresizingMaskIntoConstraints = NO; _spinner.color = UIColor.whiteColor;
    for (UIView *view in @[title, detail, _field, _button, _status, _spinner]) [self.view addSubview:view];
    UILayoutGuide *safe = self.view.safeAreaLayoutGuide;
    [NSLayoutConstraint activateConstraints:@[[title.topAnchor constraintEqualToAnchor:safe.topAnchor constant:100],[title.leadingAnchor constraintEqualToAnchor:safe.leadingAnchor constant:24],[title.trailingAnchor constraintEqualToAnchor:safe.trailingAnchor constant:-24],[detail.topAnchor constraintEqualToAnchor:title.bottomAnchor constant:12],[detail.leadingAnchor constraintEqualToAnchor:title.leadingAnchor],[detail.trailingAnchor constraintEqualToAnchor:title.trailingAnchor],[_field.topAnchor constraintEqualToAnchor:detail.bottomAnchor constant:30],[_field.leadingAnchor constraintEqualToAnchor:safe.leadingAnchor constant:28],[_field.trailingAnchor constraintEqualToAnchor:safe.trailingAnchor constant:-28],[_field.heightAnchor constraintEqualToConstant:55],[_button.topAnchor constraintEqualToAnchor:_field.bottomAnchor constant:16],[_button.leadingAnchor constraintEqualToAnchor:_field.leadingAnchor],[_button.trailingAnchor constraintEqualToAnchor:_field.trailingAnchor],[_button.heightAnchor constraintEqualToConstant:55],[_status.topAnchor constraintEqualToAnchor:_button.bottomAnchor constant:16],[_status.leadingAnchor constraintEqualToAnchor:_field.leadingAnchor],[_status.trailingAnchor constraintEqualToAnchor:_field.trailingAnchor],[_spinner.topAnchor constraintEqualToAnchor:_status.bottomAnchor constant:8],[_spinner.centerXAnchor constraintEqualToAnchor:self.view.centerXAnchor]]];
    NSString *saved = [MyGoldAPI.shared savedKey]; if (saved.length) { _field.text = saved; [self submit]; }
}
- (void)submit {
    _button.enabled = NO; _field.enabled = NO; [_spinner startAnimating]; _status.text = @"Validando no servidor…";
    __weak typeof(self) weakSelf = self;
    [[MyGoldAPI shared] validateKey:_field.text completion:^(BOOL success, NSString *message) {
        __strong typeof(weakSelf) self = weakSelf; if (!self) return;
        self->_button.enabled = YES; self->_field.enabled = YES; [self->_spinner stopAnimating]; self->_status.text = message;
        if (success) {
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.35 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{ [self dismissViewControllerAnimated:YES completion:^{ [ModsMenuController openModsMenu]; }]; });
        } else { self->_status.textColor = [UIColor systemRedColor]; }
    }];
}
@end

void MyGoldGateOpenMenuOrLogin(void) {
    dispatch_async(dispatch_get_main_queue(), ^{
        if (MyGoldAPI.shared.isAuthenticated) { [ModsMenuController openModsMenu]; return; }
        UIWindow *window = MyGoldActiveWindow(); UIViewController *top = window.rootViewController;
        while (top.presentedViewController) top = top.presentedViewController;
        if (!top || [top.presentedViewController isKindOfClass:MyGoldLoginViewController.class]) return;
        UINavigationController *nav = [[UINavigationController alloc] initWithRootViewController:[MyGoldLoginViewController new]];
        nav.modalPresentationStyle = UIModalPresentationFullScreen;
        [top presentViewController:nav animated:YES completion:nil];
    });
}
