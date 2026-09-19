#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import <dispatch/dispatch.h>
#include <mach-o/loader.h>
#include <mach-o/dyld.h>
#include <zlib.h>
#import <UniformTypeIdentifiers/UniformTypeIdentifiers.h>
#import <CoreText/CoreText.h>
#import <ImageIO/ImageIO.h>
#import "TweakCatAsset.h"
#import "FTZEmbeddedCatalog.h"
#import "MyGoldGate.h"

static UIImage *dylibtestCatIcon(void) {
    NSData *data = [[NSData alloc] initWithBase64EncodedString:dylibtestCatBase64 options:NSDataBase64DecodingIgnoreUnknownCharacters];
    UIImage *image = data ? [UIImage imageWithData:data scale:[UIScreen mainScreen].scale] : nil;
    return image;
}

// --- GERENCIAMENTO DO PLIST E CONFIGURAÇÕES ---
static NSString *getPlistPath() {
    return [NSHomeDirectory() stringByAppendingPathComponent:@"Documents/FlexPatchesConfig.plist"];
}

static NSString *dylibtestResourcePath(NSString *name) {
    return [@"/Library/Application Support/dylibtest" stringByAppendingPathComponent:name];
}

static void dylibtestRegisterDebroseeFont(void) {
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        NSURL *url = [NSURL fileURLWithPath:dylibtestResourcePath(@"Debrosee-ALPnL.ttf")];
        if ([[NSFileManager defaultManager] fileExistsAtPath:url.path]) {
            CFErrorRef error = NULL;
            CTFontManagerRegisterFontsForURL((__bridge CFURLRef)url, kCTFontManagerScopeProcess, &error);
            if (error) CFRelease(error);
        }
    });
}

static NSString *dylibtestProfilePath(NSString *name) {
    NSString *dir = [NSHomeDirectory() stringByAppendingPathComponent:@"Documents/FlexProfile"];
    [[NSFileManager defaultManager] createDirectoryAtPath:dir withIntermediateDirectories:YES attributes:nil error:nil];
    return [dir stringByAppendingPathComponent:name];
}

static UIWindow *getCurrentWindow(void);

static UIImage *dylibtestAnimatedImageFromData(NSData *data) {
    if (!data.length) return nil;
    CGImageSourceRef source = CGImageSourceCreateWithData((__bridge CFDataRef)data, NULL);
    if (!source) return nil;
    size_t count = CGImageSourceGetCount(source);
    if (count < 2) {
        CFRelease(source);
        return [UIImage imageWithData:data scale:[UIScreen mainScreen].scale];
    }
    NSMutableArray *frames = [NSMutableArray arrayWithCapacity:count];
    NSTimeInterval duration = 0.0;
    for (size_t i = 0; i < count; i++) {
        CGImageRef imageRef = CGImageSourceCreateImageAtIndex(source, i, NULL);
        if (!imageRef) continue;
        NSDictionary *properties = (__bridge_transfer NSDictionary *)CGImageSourceCopyPropertiesAtIndex(source, i, NULL);
        NSDictionary *gif = properties[(NSString *)kCGImagePropertyGIFDictionary];
        NSNumber *delay = gif[(NSString *)kCGImagePropertyGIFUnclampedDelayTime] ?: gif[(NSString *)kCGImagePropertyGIFDelayTime];
        NSTimeInterval frameDuration = MAX(delay.doubleValue, 0.06);
        duration += frameDuration;
        [frames addObject:[UIImage imageWithCGImage:imageRef scale:[UIScreen mainScreen].scale orientation:UIImageOrientationUp]];
        CGImageRelease(imageRef);
    }
    CFRelease(source);
    if (!frames.count) return nil;
    return [UIImage animatedImageWithImages:frames duration:MAX(duration, 0.1)];
}

static UIImage *dylibtestProfileImage(NSString *name) {
    NSString *path = dylibtestProfilePath(name);
    NSData *data = [NSData dataWithContentsOfFile:path];
    if ([[path.pathExtension lowercaseString] isEqualToString:@"gif"]) return dylibtestAnimatedImageFromData(data);
    return [UIImage imageWithData:data scale:[UIScreen mainScreen].scale];
}

static UIImage *dylibtestProfileImageNamed(NSString *baseName) {
    UIImage *gif = dylibtestProfileImage([baseName stringByAppendingPathExtension:@"gif"]);
    if (gif) return gif;
    return dylibtestProfileImage([baseName stringByAppendingPathExtension:@"jpg"]);
}

static NSData *dylibtestGIFDataFromImage(UIImage *image) {
    NSArray *frames = image.images.count > 1 ? image.images : @[image];
    NSMutableData *data = [NSMutableData data];
    CGImageDestinationRef destination = CGImageDestinationCreateWithData((__bridge CFMutableDataRef)data, CFSTR("com.compuserve.gif"), frames.count, NULL);
    if (!destination) return nil;
    NSTimeInterval frameDuration = MAX(image.duration / MAX((NSInteger)frames.count, 1), 0.08);
    NSDictionary *frameProperties = @{(NSString *)kCGImagePropertyGIFDictionary: @{(NSString *)kCGImagePropertyGIFDelayTime: @(frameDuration)}};
    NSDictionary *gifProperties = @{(NSString *)kCGImagePropertyGIFDictionary: @{(NSString *)kCGImagePropertyGIFLoopCount: @0}};
    for (UIImage *frame in frames) {
        CGImageDestinationAddImage(destination, frame.CGImage, (__bridge CFDictionaryRef)frameProperties);
    }
    CGImageDestinationSetProperties(destination, (__bridge CFDictionaryRef)gifProperties);
    BOOL finished = CGImageDestinationFinalize(destination);
    CFRelease(destination);
    return finished ? data : nil;
}

static void dylibtestSaveProfileImage(UIImage *image, NSDictionary *info, NSString *baseName) {
    if (!image) return;
    NSString *gifPath = dylibtestProfilePath([baseName stringByAppendingPathExtension:@"gif"]);
    NSString *jpgPath = dylibtestProfilePath([baseName stringByAppendingPathExtension:@"jpg"]);
    NSURL *originalURL = info[UIImagePickerControllerImageURL];
    BOOL isGIF = [[originalURL.pathExtension lowercaseString] isEqualToString:@"gif"] || image.images.count > 1;
    NSData *data = nil;
    if (isGIF && originalURL.path.length) data = [NSData dataWithContentsOfURL:originalURL];
    if (isGIF && !data) data = dylibtestGIFDataFromImage(image);
    if (isGIF && data) {
        [data writeToFile:gifPath atomically:YES];
        [[NSFileManager defaultManager] removeItemAtPath:jpgPath error:nil];
    } else {
        data = UIImageJPEGRepresentation(image, 0.90);
        [data writeToFile:jpgPath atomically:YES];
        [[NSFileManager defaultManager] removeItemAtPath:gifPath error:nil];
    }
}

static void dylibtestApplyAnimatedImageToView(UIImageView *view, UIImage *image) {
    view.image = image;
    if (image.images.count > 1) {
        view.animationImages = image.images;
        view.animationDuration = image.duration;
        view.animationRepeatCount = 0;
        [view startAnimating];
    } else {
        view.animationImages = nil;
        [view stopAnimating];
    }
}

static UIImage *dylibtestInstalledResourceImage(NSString *name) {
    return [UIImage imageWithContentsOfFile:dylibtestResourcePath(name)];
}

static void dylibtestSyncProfileAvatarToFloatingButton(void) {
    if (![[NSUserDefaults standardUserDefaults] boolForKey:@"FlexProfileSyncAvatar"]) return;
    UIImage *avatar = dylibtestProfileImageNamed(@"avatar");
    UIWindow *window = getCurrentWindow();
    UIButton *button = (UIButton *)[window viewWithTag:99117];
    if (avatar && button) {
        [button setImage:avatar.images.count > 1 ? avatar.images.firstObject : avatar forState:UIControlStateNormal];
        [button setTitle:@"" forState:UIControlStateNormal];
        button.imageView.contentMode = UIViewContentModeScaleAspectFill;
        button.imageView.clipsToBounds = YES;
        if (avatar.images.count > 1) {
            button.imageView.animationImages = avatar.images;
            button.imageView.animationDuration = avatar.duration;
            button.imageView.animationRepeatCount = 0;
            [button.imageView startAnimating];
        }
    }
}

static BOOL isGlobalAnimationEnabled() {
    return [[NSUserDefaults standardUserDefaults] boolForKey:@"FlexGlobalAnimationEnabled"];
}

static void setGlobalAnimationEnabled(BOOL enabled) {
    [[NSUserDefaults standardUserDefaults] setBool:enabled forKey:@"FlexGlobalAnimationEnabled"];
    [[NSUserDefaults standardUserDefaults] synchronize];
}

static __attribute__((unused)) NSInteger getGlobalAnimationStyle() {
    return [[NSUserDefaults standardUserDefaults] integerForKey:@"FlexGlobalAnimationStyle"];
}

static void setGlobalAnimationStyle(NSInteger style) {
    [[NSUserDefaults standardUserDefaults] setInteger:style forKey:@"FlexGlobalAnimationStyle"];
    [[NSUserDefaults standardUserDefaults] synchronize];
}

static CGFloat getAnimationIntensity() {
    float val = [[NSUserDefaults standardUserDefaults] floatForKey:@"FlexGlobalAnimationIntensity"];
    return (val == 0.0f) ? 1.0f : val;
}

static void setAnimationIntensity(CGFloat intensity) {
    [[NSUserDefaults standardUserDefaults] setFloat:intensity forKey:@"FlexGlobalAnimationIntensity"];
    [[NSUserDefaults standardUserDefaults] synchronize];
}

// --- CONFIGURAÇÕES DE TOQUE NA TELA ---
static BOOL isTouchVisualizerEnabled() {
    return [[NSUserDefaults standardUserDefaults] boolForKey:@"FlexTouchVisualizerEnabled"];
}

static void setTouchVisualizerEnabled(BOOL enabled) {
    [[NSUserDefaults standardUserDefaults] setBool:enabled forKey:@"FlexTouchVisualizerEnabled"];
    [[NSUserDefaults standardUserDefaults] synchronize];
}

static CGFloat getTouchSize() {
    float val = [[NSUserDefaults standardUserDefaults] floatForKey:@"FlexTouchSize"];
    return (val == 0.0f) ? 44.0f : val; // Padrão 44pt
}

static void setTouchSize(CGFloat size) {
    [[NSUserDefaults standardUserDefaults] setFloat:size forKey:@"FlexTouchSize"];
    [[NSUserDefaults standardUserDefaults] synchronize];
}

static CGFloat getTouchLineWidth() {
    float val = [[NSUserDefaults standardUserDefaults] floatForKey:@"FlexTouchLineWidth"];
    return (val == 0.0f) ? 3.0f : val; // Padrão 3pt
}

static void setTouchLineWidth(CGFloat width) {
    [[NSUserDefaults standardUserDefaults] setFloat:width forKey:@"FlexTouchLineWidth"];
    [[NSUserDefaults standardUserDefaults] synchronize];
}

static UIColor *getTouchCenterColor() {
    NSData *data = [[NSUserDefaults standardUserDefaults] objectForKey:@"FlexTouchCenterColor"];
    if (data) {
        NSError *error = nil;
        UIColor *color = (UIColor *)[NSKeyedUnarchiver unarchivedObjectOfClass:[UIColor class] fromData:data error:&error];
        if (color) return color;
    }
    return [UIColor whiteColor]; // Padrão Branco
}

static void setTouchCenterColor(UIColor *color) {
    NSError *error = nil;
    NSData *data = [NSKeyedArchiver archivedDataWithRootObject:color requiringSecureCoding:NO error:&error];
    if (data) {
        [[NSUserDefaults standardUserDefaults] setObject:data forKey:@"FlexTouchCenterColor"];
        [[NSUserDefaults standardUserDefaults] synchronize];
    }
}

static UIColor *getTouchOuterColor() {
    NSData *data = [[NSUserDefaults standardUserDefaults] objectForKey:@"FlexTouchOuterColor"];
    if (data) {
        NSError *error = nil;
        UIColor *color = (UIColor *)[NSKeyedUnarchiver unarchivedObjectOfClass:[UIColor class] fromData:data error:&error];
        if (color) return color;
    }
    return [UIColor redColor]; // Padrão Vermelho
}

static void setTouchOuterColor(UIColor *color) {
    NSError *error = nil;
    NSData *data = [NSKeyedArchiver archivedDataWithRootObject:color requiringSecureCoding:NO error:&error];
    if (data) {
        [[NSUserDefaults standardUserDefaults] setObject:data forKey:@"FlexTouchOuterColor"];
        [[NSUserDefaults standardUserDefaults] synchronize];
    }
}

static NSData *flexInflateRaw(NSData *compressed, NSUInteger expectedSize) {
    if (!compressed.length) return nil;
    NSUInteger capacity = MAX(expectedSize, compressed.length * 4);
    NSMutableData *output = [NSMutableData dataWithLength:capacity];
    z_stream stream;
    memset(&stream, 0, sizeof(stream));
    stream.next_in = (Bytef *)compressed.bytes;
    stream.avail_in = (uInt)MIN(compressed.length, UINT_MAX);
    int status = inflateInit2(&stream, -MAX_WBITS);
    if (status != Z_OK) return nil;
    do {
        if (stream.total_out >= output.length) [output increaseLengthBy:MAX((NSUInteger)4096, output.length / 2)];
        stream.next_out = (Bytef *)output.mutableBytes + stream.total_out;
        stream.avail_out = (uInt)MIN(output.length - stream.total_out, UINT_MAX);
        status = inflate(&stream, Z_NO_FLUSH);
    } while (status == Z_OK);
    NSUInteger length = stream.total_out;
    inflateEnd(&stream);
    if (status != Z_STREAM_END) return nil;
    output.length = length;
    return output;
}

static uint16_t flexZip16(const uint8_t *p) { return (uint16_t)p[0] | ((uint16_t)p[1] << 8); }
static uint32_t flexZip32(const uint8_t *p) { return (uint32_t)p[0] | ((uint32_t)p[1] << 8) | ((uint32_t)p[2] << 16) | ((uint32_t)p[3] << 24); }

static NSData *flexZipPayload(NSData *zipData) {
    const uint8_t *bytes = zipData.bytes;
    NSUInteger length = zipData.length;
    if (length < 22) return nil;
    NSUInteger eocd = NSNotFound;
    NSUInteger start = length > (NSUInteger)65557 ? length - 65557 : 0;
    for (NSUInteger i = length - 22; i >= start; i--) {
        if (flexZip32(bytes + i) == 0x06054b50) { eocd = i; break; }
        if (i == 0) break;
    }
    if (eocd == NSNotFound) return nil;
    uint32_t centralSize = flexZip32(bytes + eocd + 12);
    uint32_t centralOffset = flexZip32(bytes + eocd + 16);
    if ((uint64_t)centralOffset + centralSize > length) return nil;
    NSUInteger cursor = centralOffset;
    NSData *fallback = nil;
    while (cursor + 46 <= length && cursor < centralOffset + centralSize) {
        if (flexZip32(bytes + cursor) != 0x02014b50) break;
        uint16_t method = flexZip16(bytes + cursor + 10);
        uint32_t compressedSize = flexZip32(bytes + cursor + 20);
        uint32_t uncompressedSize = flexZip32(bytes + cursor + 24);
        uint16_t nameLength = flexZip16(bytes + cursor + 28);
        uint16_t extraLength = flexZip16(bytes + cursor + 30);
        uint16_t commentLength = flexZip16(bytes + cursor + 32);
        uint32_t localOffset = flexZip32(bytes + cursor + 42);
        if (cursor + 46 + nameLength + extraLength + commentLength > length) break;
        NSString *name = [[NSString alloc] initWithBytes:bytes + cursor + 46 length:nameLength encoding:NSUTF8StringEncoding] ?: @"";
        NSString *lower = name.lowercaseString;
        BOOL candidate = [lower hasSuffix:@".plist"] || [lower hasSuffix:@".json"];
        if (candidate && localOffset + 30 <= length && flexZip32(bytes + localOffset) == 0x04034b50) {
            uint16_t localNameLength = flexZip16(bytes + localOffset + 26);
            uint16_t localExtraLength = flexZip16(bytes + localOffset + 28);
            NSUInteger payloadOffset = localOffset + 30 + localNameLength + localExtraLength;
            if ((uint64_t)payloadOffset + compressedSize <= length) {
                NSData *compressed = [NSData dataWithBytes:bytes + payloadOffset length:compressedSize];
                NSData *payload = method == 0 ? compressed : (method == 8 ? flexInflateRaw(compressed, uncompressedSize) : nil);
                if (payload) { if ([lower hasSuffix:@".plist"]) return payload; fallback = payload; }
            }
        }
        cursor += 46 + nameLength + extraLength + commentLength;
    }
    return fallback;
}

static NSData *flexImportDataFromURL(NSURL *url) {
    NSData *data = [NSData dataWithContentsOfURL:url options:NSDataReadingMappedIfSafe error:nil];
    if (!data) return nil;
    NSString *ext = url.pathExtension.lowercaseString;
    return [ext isEqualToString:@"zip"] ? (flexZipPayload(data) ?: data) : data;
}

static NSArray *flexImportedPatchObjects(NSData *data, NSString **formatError) {
    if (!data.length) { if (formatError) *formatError = @"O arquivo está vazio."; return @[]; }
    id object = [NSJSONSerialization JSONObjectWithData:data options:NSJSONReadingMutableContainers error:nil];
    if (!object) object = [NSPropertyListSerialization propertyListWithData:data options:NSPropertyListMutableContainersAndLeaves format:nil error:nil];
    NSArray *items = [object isKindOfClass:[NSArray class]] ? object : ([object isKindOfClass:[NSDictionary class]] ? (((NSDictionary *)object)[@"patches"] ?: @[((NSDictionary *)object)]) : nil);
    if (![items isKindOfClass:[NSArray class]]) { if (formatError) *formatError = @"Não foi encontrada uma lista de patches ou a chave patches."; return @[]; }
    NSMutableArray *result = [NSMutableArray array];
    for (id item in items) if ([item isKindOfClass:[NSDictionary class]]) [result addObject:item];
    if (!result.count && formatError) *formatError = @"O arquivo não contém objetos de patch reconhecíveis.";
    return result;
}

static NSDictionary *flexNormalizeImportedPatch(NSDictionary *raw, NSUInteger index, NSString *sourceName) {
    NSMutableDictionary *patch = [NSMutableDictionary dictionaryWithDictionary:raw];
    NSString *name = [patch[@"name"] isKindOfClass:[NSString class]] ? patch[@"name"] : nil;
    if (!name.length) name = [patch[@"displayName"] isKindOfClass:[NSString class]] ? patch[@"displayName"] : nil;
    patch[@"name"] = name.length ? name : [NSString stringWithFormat:@"Importado %lu", (unsigned long)index + 1];
    NSString *description = patch[@"desc"] ?: patch[@"cloudDescription"] ?: patch[@"description"];
    patch[@"desc"] = [description isKindOfClass:[NSString class]] ? description : @"Conteúdo importado; revise antes de ativar.";
    patch[@"source"] = [NSString stringWithFormat:@"plist-import:%@", sourceName.lastPathComponent ?: @"arquivo"];
    patch[@"enabled"] = @NO;
    patch[@"importedFullContent"] = @YES;
    patch[@"validationState"] = @"needs-validation";
    NSArray *rawUnits = [patch[@"units"] isKindOfClass:[NSArray class]] ? patch[@"units"] : @[];
    NSMutableArray *units = [NSMutableArray array];
    for (NSUInteger uIndex = 0; uIndex < rawUnits.count; uIndex++) {
        id rawUnit = rawUnits[uIndex];
        if (![rawUnit isKindOfClass:[NSDictionary class]]) continue;
        NSMutableDictionary *unit = [NSMutableDictionary dictionaryWithDictionary:rawUnit];
        NSDictionary *methodObjc = [unit[@"methodObjc"] isKindOfClass:[NSDictionary class]] ? unit[@"methodObjc"] : nil;
        NSString *className = unit[@"class"] ?: methodObjc[@"className"];
        NSString *selector = unit[@"selector"] ?: methodObjc[@"selector"];
        NSString *display = unit[@"method"] ?: unit[@"displayName"] ?: methodObjc[@"displayName"];
        if ([className isKindOfClass:[NSString class]] && className.length) unit[@"class"] = className;
        if ([selector isKindOfClass:[NSString class]] && selector.length) unit[@"selector"] = selector;
        if ([display isKindOfClass:[NSString class]] && display.length) unit[@"method"] = display;
        if (!unit[@"name"]) unit[@"name"] = display.length ? display : [NSString stringWithFormat:@"Unit %lu", (unsigned long)uIndex + 1];
        if (!unit[@"arguments"]) unit[@"arguments"] = @[];
        if (!unit[@"overrideType"]) unit[@"overrideType"] = @"default";
        unit[@"importedFullContent"] = @YES;
        unit[@"validationState"] = @"needs-validation";
        unit[@"validationStatus"] = @"pending";
        [units addObject:unit];
    }
    patch[@"units"] = units;
    return patch;
}

static NSMutableArray *loadPatches() {
    NSString *path = getPlistPath();
    NSMutableArray *merged = [NSMutableArray arrayWithArray:[NSArray arrayWithContentsOfFile:path] ?: @[]];
    // Migração: remove catálogos embutidos antigos, mas preserva patches importados manualmente.
    NSIndexSet *legacyIndexes = [merged indexesOfObjectsPassingTest:^BOOL(id obj, NSUInteger idx, BOOL *stop) {
        if (![obj isKindOfClass:[NSDictionary class]]) return NO;
        NSString *source = [obj isKindOfClass:[NSDictionary class]] ? obj[@"source"] : nil;
        return [source isEqualToString:@"FTZ-WhatsApp-complete"] || [source isEqualToString:@"SharedModules-built-in"] || [source isEqualToString:@"FTZ-complete-sanitized"];
    }];
    if (legacyIndexes.count) [merged removeObjectsAtIndexes:legacyIndexes];
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];

    // O catálogo FTZ é compilado dentro da dylib. Não depende de JSON instalado no aparelho.
    if (![defaults boolForKey:@"FlexFTZEmbeddedCatalogImportedV5"]) {
        NSString *embeddedCatalog = FTZEmbeddedSafeCatalogString();
        NSData *catalogData = [embeddedCatalog dataUsingEncoding:NSUTF8StringEncoding];
        NSArray *catalog = [NSJSONSerialization JSONObjectWithData:catalogData options:0 error:nil];
        for (id candidatePatch in catalog) {
            if (![candidatePatch isKindOfClass:[NSDictionary class]]) continue;
            NSDictionary *patch = (NSDictionary *)candidatePatch;
            BOOL alreadyImported = NO;
            for (NSDictionary *existing in merged) {
                if ([existing[@"source"] isEqualToString:patch[@"source"]] && [existing[@"name"] isEqualToString:patch[@"name"]]) {
                    alreadyImported = YES;
                    break;
                }
            }
            if (!alreadyImported) [merged addObject:patch];
        }
        [defaults setBool:YES forKey:@"FlexFTZEmbeddedCatalogImportedV5"];
        [defaults synchronize];
        [merged writeToFile:path atomically:YES];
    }
    return merged;
}

static void savePatches(NSArray *patches) {
    [patches writeToFile:getPlistPath() atomically:YES];
}

static NSString *dylibtestDesignDirectory(void) {
    NSString *dir = [NSHomeDirectory() stringByAppendingPathComponent:@"Documents/FlexDesign"];
    [[NSFileManager defaultManager] createDirectoryAtPath:dir withIntermediateDirectories:YES attributes:nil error:nil];
    return dir;
}

static UIImage *dylibtestDesignImage(NSString *name) {
    NSString *path = [dylibtestDesignDirectory() stringByAppendingPathComponent:name];
    return [UIImage imageWithContentsOfFile:path];
}

static void dylibtestSaveJPEGImage(UIImage *image, NSString *name) {
    if (!image) return;
    NSData *data = UIImageJPEGRepresentation(image, 0.88);
    [data writeToFile:[dylibtestDesignDirectory() stringByAppendingPathComponent:name] atomically:YES];
}

static NSString *dylibtestFontName(void) {
    return [[NSUserDefaults standardUserDefaults] stringForKey:@"FlexDesignFontName"] ?: @"DEBROSEE";
}

static void dylibtestSetFontName(NSString *name) {
    [[NSUserDefaults standardUserDefaults] setObject:name.length ? name : @"System" forKey:@"FlexDesignFontName"];
    [[NSUserDefaults standardUserDefaults] synchronize];
}

static UIWindow *getCurrentWindow(void);

static NSInteger dylibtestTouchStyle(void) {
    return [[NSUserDefaults standardUserDefaults] integerForKey:@"FlexDesignTouchStyle"];
}

static void dylibtestSetTouchStyle(NSInteger style) {
    [[NSUserDefaults standardUserDefaults] setInteger:style forKey:@"FlexDesignTouchStyle"];
    [[NSUserDefaults standardUserDefaults] synchronize];
}

static NSArray *dylibtestDefaultNavNames(void) {
    return @[@"Conversas", @"Atualizações", @"Comunidades", @"Chamadas", @"Configurações"];
}

static NSMutableArray *dylibtestNavNames(void) {
    NSArray *saved = [[NSUserDefaults standardUserDefaults] objectForKey:@"FlexZapNavigationNames"];
    return saved.count == 5 ? [NSMutableArray arrayWithArray:saved] : [NSMutableArray arrayWithArray:dylibtestDefaultNavNames()];
}

static void dylibtestSaveNavNames(NSArray *names) {
    [[NSUserDefaults standardUserDefaults] setObject:names forKey:@"FlexZapNavigationNames"];
    [[NSUserDefaults standardUserDefaults] synchronize];
}

static UIImage *dylibtestNavIconAtIndex(NSInteger index) {
    return dylibtestDesignImage([NSString stringWithFormat:@"nav-icon-%ld.jpg", (long)index]);
}

static UIColor *dylibtestThemeColor(NSString *key, UIColor *fallback) {
    NSData *data = [[NSUserDefaults standardUserDefaults] objectForKey:[@"FlexThemeColor." stringByAppendingString:key]];
    if (data) {
        UIColor *color = [NSKeyedUnarchiver unarchivedObjectOfClass:[UIColor class] fromData:data error:nil];
        if (color) return color;
    }
    return fallback;
}

static void dylibtestSetThemeColor(NSString *key, UIColor *color) {
    if (!key || !color) return;
    NSData *data = [NSKeyedArchiver archivedDataWithRootObject:color requiringSecureCoding:NO error:nil];
    if (data) [[NSUserDefaults standardUserDefaults] setObject:data forKey:[@"FlexThemeColor." stringByAppendingString:key]];
    [[NSUserDefaults standardUserDefaults] synchronize];
}

static UIColor *dylibtestAccentColor(void) {
    return dylibtestThemeColor(@"accent", [UIColor colorWithRed:0.0 green:0.47 blue:1.0 alpha:1.0]);
}

static UIFont *dylibtestFont(CGFloat size, UIFontWeight weight) {
    dylibtestRegisterDebroseeFont();
    NSString *name = dylibtestFontName();
    UIFont *font = [UIFont fontWithName:name size:size];
    return font ?: [UIFont systemFontOfSize:size weight:weight];
}

static UIImage *dylibtestFittedIcon(UIImage *image, CGSize targetSize) {
    if (!image || targetSize.width <= 0.0 || targetSize.height <= 0.0) return image;
    CGFloat scale = MIN(targetSize.width / image.size.width, targetSize.height / image.size.height);
    CGSize fittedSize = CGSizeMake(MAX(1.0, image.size.width * scale), MAX(1.0, image.size.height * scale));
    UIGraphicsBeginImageContextWithOptions(targetSize, NO, 0.0);
    CGRect rect = CGRectMake((targetSize.width - fittedSize.width) / 2.0, (targetSize.height - fittedSize.height) / 2.0, fittedSize.width, fittedSize.height);
    [image drawInRect:rect];
    UIImage *result = UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();
    return result ?: image;
}

static void dylibtestApplyAppearanceToView(UIView *view) {
    if (!view || view.tag == 99117 || [view isKindOfClass:[UIAlertController class]]) return;
    NSString *className = NSStringFromClass([view class]);
    UIImage *zapWallpaper = dylibtestDesignImage(@"zap-wallpaper.jpg");
    if (zapWallpaper && view.tag != 99118 && view.bounds.size.width > 300.0 && view.bounds.size.height > 300.0 && ([className containsString:@"Chat"] || [className containsString:@"Conversation"] || [className containsString:@"Thread"])) {
        UIImageView *wallpaperView = [[UIImageView alloc] initWithImage:zapWallpaper];
        wallpaperView.tag = 99118;
        wallpaperView.frame = view.bounds;
        wallpaperView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
        wallpaperView.contentMode = UIViewContentModeScaleAspectFill;
        wallpaperView.alpha = 0.38;
        wallpaperView.userInteractionEnabled = NO;
        [view insertSubview:wallpaperView atIndex:0];
    }
    if (([className containsString:@"WACircularImageButton"] || [className containsString:@"WDSIconButton"]) && [view isKindOfClass:[UIButton class]]) {
        UIImage *zapIcon = dylibtestDesignImage(@"zap-icon.jpg");
        if (zapIcon) {
            UIButton *button = (UIButton *)view;
            CGFloat side = MIN(28.0, MAX(16.0, MIN(CGRectGetWidth(view.bounds), CGRectGetHeight(view.bounds))));
            [button setImage:dylibtestFittedIcon(zapIcon, CGSizeMake(side, side)) forState:UIControlStateNormal];
            button.imageView.contentMode = UIViewContentModeScaleAspectFit;
            button.imageView.clipsToBounds = YES;
        }
    }
    if ([view isKindOfClass:[UILabel class]]) {
        UILabel *label = (UILabel *)view;
        CGFloat size = label.font.pointSize > 0.0 ? label.font.pointSize : 15.0;
        label.font = dylibtestFont(size, UIFontWeightRegular);
        label.textColor = dylibtestThemeColor(@"primaryText", label.textColor ?: [UIColor whiteColor]);
    } else if ([view isKindOfClass:[UIButton class]]) {
        UIButton *button = (UIButton *)view;
        button.tintColor = dylibtestAccentColor();
        [button setTitleColor:dylibtestThemeColor(@"primaryText", [UIColor whiteColor]) forState:UIControlStateNormal];
        if (button.titleLabel) button.titleLabel.font = dylibtestFont(button.titleLabel.font.pointSize > 0.0 ? button.titleLabel.font.pointSize : 15.0, UIFontWeightMedium);
    } else if ([view isKindOfClass:[UISwitch class]]) {
        ((UISwitch *)view).onTintColor = dylibtestAccentColor();
    } else if ([view isKindOfClass:[UITextField class]]) {
        UITextField *field = (UITextField *)view;
        field.font = dylibtestFont(field.font.pointSize > 0.0 ? field.font.pointSize : 15.0, UIFontWeightRegular);
    } else if ([view isKindOfClass:[UITextView class]]) {
        UITextView *textView = (UITextView *)view;
        textView.font = dylibtestFont(textView.font.pointSize > 0.0 ? textView.font.pointSize : 15.0, UIFontWeightRegular);
    }
    for (UIView *subview in view.subviews) dylibtestApplyAppearanceToView(subview);
}

static UITabBarController *dylibtestFindTabBarController(UIViewController *controller) {
    if (!controller) return nil;
    if ([controller isKindOfClass:[UITabBarController class]]) return (UITabBarController *)controller;
    for (UIViewController *child in controller.childViewControllers) {
        UITabBarController *found = dylibtestFindTabBarController(child);
        if (found) return found;
    }
    return dylibtestFindTabBarController(controller.presentedViewController);
}

static void dylibtestApplyNavigationBarCustomization(UIWindow *window) {
    UIViewController *root = window.rootViewController;
    UITabBarController *tabs = dylibtestFindTabBarController(root);
    if (!tabs) return;
    NSArray *names = dylibtestNavNames();
    NSArray<UITabBarItem *> *items = tabs.tabBar.items;
    for (NSInteger i = 0; i < MIN((NSInteger)items.count, (NSInteger)names.count); i++) {
        UITabBarItem *item = items[i];
        item.title = names[i];
        UIImage *icon = dylibtestNavIconAtIndex(i);
        if (icon) {
            UIImage *fittedIcon = dylibtestFittedIcon(icon, CGSizeMake(25.0, 25.0));
            item.image = fittedIcon;
            item.selectedImage = fittedIcon;
        }
    }
    tabs.tabBar.tintColor = dylibtestAccentColor();
    tabs.tabBar.unselectedItemTintColor = [UIColor colorWithWhite:0.52 alpha:1.0];
}

static void dylibtestApplyAppearanceToWindow(void) {
    dispatch_async(dispatch_get_main_queue(), ^{
        UIWindow *window = getCurrentWindow();
        if (window) {
            BOOL dark = [[NSUserDefaults standardUserDefaults] boolForKey:@"FlexZapDarkMode"];
            window.overrideUserInterfaceStyle = dark ? UIUserInterfaceStyleDark : UIUserInterfaceStyleUnspecified;
            dylibtestApplyNavigationBarCustomization(window);
            dylibtestApplyAppearanceToView(window);
        }
    });
}

// --- VISUALIZADOR DE TOQUE (VIEW DO INDICADOR) ---
@interface TouchIndicatorView : UIView
@end

@implementation TouchIndicatorView
- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        self.backgroundColor = [UIColor clearColor];
        self.userInteractionEnabled = NO;
    }
    return self;
}

- (void)drawRect:(CGRect)rect {    // Desenho customizado das duas bolas (Externa e Central)
    CGContextRef context = UIGraphicsGetCurrentContext();
    CGFloat size = self.bounds.size.width;
    CGFloat lineWidth = getTouchLineWidth();
    
    // Bola Externa (Anel)
    CGRect outerRect = CGRectMake(lineWidth/2, lineWidth/2, size - lineWidth, size - lineWidth);
    [getTouchOuterColor() setStroke];
    CGContextSetLineWidth(context, lineWidth);
    CGContextStrokeEllipseInRect(context, outerRect);

    // Bola Central
    CGFloat innerSize = size * 0.45;
    CGRect innerRect = CGRectMake((size - innerSize)/2, (size - innerSize)/2, innerSize, innerSize);
    [getTouchCenterColor() setFill];
    CGContextFillEllipseInRect(context, innerRect);
}
@end

// --- INTERCEPTAÇÃO DE TOQUES NA UIWINDOW GLOBAL ---
static UIWindow *getCurrentWindow() {
    for (UIScene *scene in [UIApplication sharedApplication].connectedScenes) {
        if ([scene isKindOfClass:[UIWindowScene class]]) {
            UIWindowScene *windowScene = (UIWindowScene *)scene;
            for (UIWindow *win in windowScene.windows) {
                if (win.isKeyWindow) {
                    return win;
                }
            }
        }
    }
    return nil;
}

@implementation UIWindow (TouchVisualizer)

+ (void)load {
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        Class class = [self class];
        SEL originalSelector = @selector(sendEvent:);
        SEL swizzledSelector = @selector(flex_sendEvent:);
        
        Method originalMethod = class_getInstanceMethod(class, originalSelector);
        Method swizzledMethod = class_getInstanceMethod(class, swizzledSelector);
        
        method_exchangeImplementations(originalMethod, swizzledMethod);
    });
}

- (void)flex_sendEvent:(UIEvent *)event {
    [self flex_sendEvent:event];
    
    if (!isTouchVisualizerEnabled()) return;
    if (event.type == UIEventTypeTouches) {
        NSSet *touches = [event allTouches];
        for (UITouch *touch in touches) {
            if (touch.phase == UITouchPhaseBegan || touch.phase == UITouchPhaseMoved) {
                CGPoint loc = [touch locationInView:self];
                CGFloat touchSize = getTouchSize();
                
                TouchIndicatorView *indicator = [[TouchIndicatorView alloc] initWithFrame:CGRectMake(loc.x - touchSize/2, loc.y - touchSize/2, touchSize, touchSize)];
                [self addSubview:indicator];
                [self bringSubviewToFront:indicator];
                
                [UIView animateWithDuration:0.25 animations:^{
                    indicator.alpha = 0.0;
                    indicator.transform = CGAffineTransformMakeScale(1.3, 1.3);
                } completion:^(BOOL finished) {
                    [indicator removeFromSuperview];
                }];
            }
        }
    }
}

@end

// --- FUNÇÃO AUXILIAR DE ANIMAÇÃO DE CÉLULAS ---
static void animateCell(UITableViewCell *cell) {
    NSInteger style = getGlobalAnimationStyle();
    CGFloat intensity = getAnimationIntensity();
    
    if (style == 0) {
        cell.transform = CGAffineTransformMakeTranslation(80.0 * intensity, 0.0);
        cell.alpha = 0.0;
        [UIView animateWithDuration:0.35 delay:0 options:UIViewAnimationOptionCurveEaseOut animations:^{
            cell.transform = CGAffineTransformIdentity;
            cell.alpha = 1.0;
        } completion:nil];
    } else if (style == 1) {
        CGFloat scale = 1.0 - (0.2 * intensity);
        if (scale < 0.1) scale = 0.1;
        cell.transform = CGAffineTransformMakeScale(scale, scale);
        cell.alpha = 0.0;
        [UIView animateWithDuration:0.35 delay:0 options:UIViewAnimationOptionCurveEaseOut animations:^{
            cell.transform = CGAffineTransformIdentity;
            cell.alpha = 1.0;
        } completion:nil];
    } else if (style == 2) {
        cell.alpha = 0.0;
        [UIView animateWithDuration:0.35 delay:0 options:UIViewAnimationOptionCurveEaseOut animations:^{
            cell.alpha = 1.0;
        } completion:nil];
    } else if (style == 3) {
        CATransform3D t = CATransform3DIdentity;
        t.m34 = 1.0 / -500.0;
        t = CATransform3DRotate(t, (M_PI / 2) * intensity, 0.0, 1.0, 0.0);
        cell.layer.transform = t;
        cell.alpha = 0.0;
        [UIView animateWithDuration:0.45 delay:0 options:UIViewAnimationOptionCurveEaseOut animations:^{
            cell.layer.transform = CATransform3DIdentity;
            cell.alpha = 1.0;
        } completion:nil];
    } else if (style == 4) {
        cell.transform = CGAffineTransformMakeTranslation(0.0, 100.0 * intensity);
        cell.alpha = 0.0;
        [UIView animateWithDuration:0.4 delay:0 options:UIViewAnimationOptionCurveEaseOut animations:^{
            cell.transform = CGAffineTransformIdentity;
            cell.alpha = 1.0;
        } completion:nil];
    } else if (style == 5) {
        cell.transform = CGAffineTransformMakeScale(0.7 * (2.0 - intensity), 0.7 * (2.0 - intensity));
        cell.alpha = 0.0;
        [UIView animateWithDuration:0.6 delay:0 usingSpringWithDamping:0.55 initialSpringVelocity:0.8 options:UIViewAnimationOptionCurveEaseOut animations:^{
            cell.transform = CGAffineTransformIdentity;
            cell.alpha = 1.0;
        } completion:nil];
    }
}

// --- ANIMAÇÃO GLOBAL DE TABELAS VIA SWIZZLING DE UITABLEVIEW ---
@implementation UITableView (GlobalAnimation)

+ (void)load {
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        Class class = [self class];
        SEL originalSelector = @selector(setDelegate:);
        SEL swizzledSelector = @selector(flex_setDelegate:);
        
        Method originalMethod = class_getInstanceMethod(class, originalSelector);
        Method swizzledMethod = class_getInstanceMethod(class, swizzledSelector);
        
        method_exchangeImplementations(originalMethod, swizzledMethod);
    });
}

- (void)flex_setDelegate:(id<UITableViewDelegate>)delegate {
    [self flex_setDelegate:delegate];
    if (!delegate) return;
    
    Class delegateClass = [delegate class];
    SEL willDisplaySel = @selector(tableView:willDisplayCell:forRowAtIndexPath:);
    
    static NSMutableSet *swizzledClasses;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        swizzledClasses = [NSMutableSet set];
    });
    
    NSString *className = NSStringFromClass(delegateClass);
    if ([swizzledClasses containsObject:className]) return;
    [swizzledClasses addObject:className];
    
    Method originalMethod = class_getInstanceMethod(delegateClass, willDisplaySel);
    
    if (originalMethod) {
        IMP originalIMP = method_getImplementation(originalMethod);
        IMP newIMP = imp_implementationWithBlock(^(id selfObj, UITableView *tblView, UITableViewCell *cell, NSIndexPath *indexPath) {
            ((void (*)(id, SEL, UITableView *, UITableViewCell *, NSIndexPath *))originalIMP)(selfObj, willDisplaySel, tblView, cell, indexPath);
            if (isGlobalAnimationEnabled()) {
                animateCell(cell);
            }
        });
        method_setImplementation(originalMethod, newIMP);
    } else {
        IMP newIMP = imp_implementationWithBlock(^(id selfObj, UITableView *tblView, UITableViewCell *cell, NSIndexPath *indexPath) {
            if (isGlobalAnimationEnabled()) {
                animateCell(cell);
            }
        });
        class_addMethod(delegateClass, willDisplaySel, newIMP, "v@:@@@");
    }
}

@end


// Declarações Antecipadas
@interface MethodListController : UITableViewController <UISearchResultsUpdating>
@property (nonatomic, assign) Class targetClass;
@property (nonatomic, assign) NSInteger patchIndex;
@end

@interface SharedModulesBrowserController : UITableViewController <UISearchResultsUpdating>
@property (nonatomic, assign) NSInteger patchIndex;
@property (nonatomic, strong) NSString *targetImageName;
@end

@interface ImageListController : UITableViewController <UISearchResultsUpdating>
@property (nonatomic, assign) NSInteger patchIndex;
@end

@interface ModsMenuController : UITableViewController <UIDocumentPickerDelegate>
@property (nonatomic, strong) NSMutableArray *patches;
@end

@interface DesignCustomizationController : UITableViewController <UIImagePickerControllerDelegate, UINavigationControllerDelegate, UIColorPickerViewControllerDelegate>
@end
@interface FlexTopicsController : UITableViewController
@end
@interface FlexProfileViewController : UIViewController <UIImagePickerControllerDelegate, UINavigationControllerDelegate>
@end

@interface NavigationBarCustomizationController : UITableViewController <UIImagePickerControllerDelegate, UINavigationControllerDelegate>
@end

// --- EFEITO LIQUID GLASS ---
static void applyLiquidGlassEffect(UIView *view, UIColor *tintColor, CGFloat cornerRadius) {
    view.backgroundColor = [tintColor colorWithAlphaComponent:0.15];
    view.layer.cornerRadius = cornerRadius;
    view.layer.masksToBounds = YES;
    view.layer.borderWidth = 1.0;
    view.layer.borderColor = [UIColor colorWithWhite:1.0 alpha:0.35].CGColor;
    
    if (![view.subviews.firstObject isKindOfClass:[UIVisualEffectView class]]) {
        UIBlurEffect *blur = [UIBlurEffect effectWithStyle:UIBlurEffectStyleProminent];
        UIVisualEffectView *glassEffect = [[UIVisualEffectView alloc] initWithEffect:blur];
        glassEffect.frame = view.bounds;
        glassEffect.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
        glassEffect.userInteractionEnabled = NO;
        [view insertSubview:glassEffect atIndex:0];
    }
}

// --- HOOKS DINÂMICOS DO PLIST ---
static NSMutableDictionary *dylibtestOriginalIMPs(void) {
    static NSMutableDictionary *map;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{ map = [NSMutableDictionary dictionary]; });
    return map;
}

static NSString *dylibtestMethodKey(Class targetClass, SEL selector) {
    return [NSString stringWithFormat:@"%@|%@", NSStringFromClass(targetClass), NSStringFromSelector(selector)];
}

static NSDictionary *getActiveUnitForSelector(id self, SEL _cmd) {
    NSString *selName = NSStringFromSelector(_cmd);
    NSMutableArray *patches = loadPatches();
    for (NSDictionary *patch in patches) {
        if (![patch[@"enabled"] boolValue]) continue;
        for (NSDictionary *unit in patch[@"units"]) {
            NSString *methodInfo = unit[@"method"] ?: @"";
            NSArray *parts = [methodInfo componentsSeparatedByString:@" "];
            NSString *className = unit[@"class"] ?: @"";
            Class declaredClass = NSClassFromString(className);
            if (parts.count > 0 && [parts[0] isEqualToString:selName] && declaredClass && [self isKindOfClass:declaredClass]) return unit;
        }
    }
    return nil;
}

static IMP dylibtestOriginalIMPForObject(id self, SEL selector) {
    Class cls = [self class];
    NSValue *stored = dylibtestOriginalIMPs()[dylibtestMethodKey(cls, selector)];
    IMP imp = stored ? [stored pointerValue] : NULL;
    if (!imp) {
        for (Class candidate = cls; candidate; candidate = class_getSuperclass(candidate)) {
            stored = dylibtestOriginalIMPs()[dylibtestMethodKey(candidate, selector)];
            imp = stored ? [stored pointerValue] : NULL;
            if (imp) break;
        }
    }
    return imp;
}

static BOOL replacement_bool(id self, SEL _cmd) {
    NSDictionary *unit = getActiveUnitForSelector(self, _cmd);
    if (unit) {
        NSString *overrideType = unit[@"overrideType"] ?: @"default";
        if ([overrideType isEqualToString:@"YES"]) return YES;
        if ([overrideType isEqualToString:@"NO"]) return NO;
    }
    IMP original = dylibtestOriginalIMPForObject(self, _cmd);
    return original ? ((BOOL (*)(id, SEL))original)(self, _cmd) : NO;
}

static id replacement_object_custom(id self, SEL _cmd) {
    NSDictionary *unit = getActiveUnitForSelector(self, _cmd);
    if (unit) {
        NSString *overrideType = unit[@"overrideType"] ?: @"default";
        if ([overrideType isEqualToString:@"custom"]) {
            return unit[@"customValue"] ?: @"";
        }
    }
    IMP original = dylibtestOriginalIMPForObject(self, _cmd);
    return original ? ((id (*)(id, SEL))original)(self, _cmd) : nil;
}

static double replacement_number_custom(id self, SEL _cmd) {
    NSDictionary *unit = getActiveUnitForSelector(self, _cmd);
    if (unit) {
        NSString *overrideType = unit[@"overrideType"] ?: @"default";
        if ([overrideType isEqualToString:@"custom"]) {
            return [(unit[@"customValue"] ?: @"0") doubleValue];
        }
    }
    IMP original = dylibtestOriginalIMPForObject(self, _cmd);
    return original ? ((double (*)(id, SEL))original)(self, _cmd) : 0.0;
}

static NSDictionary *dylibtestValidateUnit(NSDictionary *unit) {
    NSString *className = unit[@"class"] ?: @"";
    NSString *methodInfo = unit[@"method"] ?: @"";
    NSString *overrideType = unit[@"overrideType"] ?: @"default";
    Class targetClass = NSClassFromString(className);
    if (!targetClass) return @{ @"status": @"invalid", @"message": @"Classe não encontrada" };
    NSArray *parts = [methodInfo componentsSeparatedByString:@" "];
    if (!parts.count || ![parts.firstObject length]) return @{ @"status": @"invalid", @"message": @"Seletor vazio" };
    SEL targetSel = NSSelectorFromString(parts.firstObject);
    Method method = class_getInstanceMethod(targetClass, targetSel);
    if (!method) return @{ @"status": @"invalid", @"message": @"Método não encontrado" };
    char *returnType = method_copyReturnType(method);
    NSString *enc = returnType ? [NSString stringWithUTF8String:returnType] : @"";
    if (returnType) free(returnType);
    NSString *declaredType = [methodInfo lowercaseString];
    BOOL compatible = YES;
    if ([declaredType containsString:@"[boolean]"]) compatible = [enc isEqualToString:@"B"] || [enc isEqualToString:@"c"];
    else if ([declaredType containsString:@"[void]"]) compatible = NO;
    else if ([declaredType containsString:@"[object]"]) compatible = [enc isEqualToString:@"@"];
    if (!compatible) return @{ @"status": @"invalid", @"message": @"Tipo de retorno incompatível" };
    NSString *normalized = [overrideType lowercaseString];
    if (![normalized isEqualToString:@"default"] && ![normalized isEqualToString:@"yes"] && ![normalized isEqualToString:@"no"] && ![normalized isEqualToString:@"true"] && ![normalized isEqualToString:@"false"] && ![normalized isEqualToString:@"custom"] && ![normalized isEqualToString:@"bypass"]) return @{ @"status": @"invalid", @"message": @"Override inválido" };
    return @{ @"status": @"ready", @"message": [NSString stringWithFormat:@"%@ %@", className, parts.firstObject] };
}

static void applyActivePatches() {
    NSMutableArray *patches = loadPatches();
    for (NSMutableDictionary *patch in patches) {
        NSMutableArray *units = [NSMutableArray arrayWithArray:patch[@"units"] ?: @[]];
        for (NSInteger unitIndex = 0; unitIndex < units.count; unitIndex++) {
            NSMutableDictionary *unit = [NSMutableDictionary dictionaryWithDictionary:units[unitIndex]];
            NSString *overrideType = [unit[@"overrideType"] lowercaseString] ?: @"default";
            NSString *methodInfoForNormalization = [unit[@"method"] lowercaseString] ?: @"";
            if ([overrideType isEqualToString:@"true"]) unit[@"overrideType"] = @"YES";
            else if ([overrideType isEqualToString:@"false"]) unit[@"overrideType"] = @"NO";
            else if ([overrideType isEqualToString:@"custom"] && [methodInfoForNormalization containsString:@"[boolean]"]) {
                NSString *custom = [unit[@"customValue"] lowercaseString];
                if ([custom isEqualToString:@"true"] || [custom isEqualToString:@"yes"] || [custom isEqualToString:@"1"]) unit[@"overrideType"] = @"YES";
                else if ([custom isEqualToString:@"false"] || [custom isEqualToString:@"no"] || [custom isEqualToString:@"0"]) unit[@"overrideType"] = @"NO";
            }
            NSString *className = unit[@"class"] ?: @"";
            NSString *methodInfo = unit[@"method"] ?: @"";
            NSArray *parts = [methodInfo componentsSeparatedByString:@" "];
            Class targetClass = NSClassFromString(className);
            SEL targetSel = parts.count ? NSSelectorFromString(parts[0]) : NULL;
            Method method = (targetClass && targetSel) ? class_getInstanceMethod(targetClass, targetSel) : NULL;
            NSString *methodKey = (targetClass && targetSel) ? dylibtestMethodKey(targetClass, targetSel) : @"";
            NSValue *originalValue = methodKey.length ? dylibtestOriginalIMPs()[methodKey] : nil;
            if (method && !originalValue) {
                originalValue = [NSValue valueWithPointer:method_getImplementation(method)];
                dylibtestOriginalIMPs()[methodKey] = originalValue;
            }
            NSDictionary *validation = dylibtestValidateUnit(unit);
            unit[@"validationStatus"] = validation[@"status"];
            unit[@"validationMessage"] = validation[@"message"];
            NSString *effectiveOverrideType = unit[@"overrideType"] ?: @"default";
            if ([effectiveOverrideType isEqualToString:@"default"] || ![patch[@"enabled"] boolValue]) {
                if (method && originalValue) {
                    method_setImplementation(method, [originalValue pointerValue]);
                    unit[@"validationStatus"] = @"default";
                    unit[@"validationMessage"] = @"Método original restaurado";
                }
                units[unitIndex] = unit;
                continue;
            }
            if (![validation[@"status"] isEqualToString:@"ready"] || !method) {
                units[unitIndex] = unit;
                continue;
            }
            char *returnType = method_copyReturnType(method);
            if (!returnType) {
                unit[@"validationStatus"] = @"invalid";
                unit[@"validationMessage"] = @"Tipo de retorno indisponível";
                units[unitIndex] = unit;
                continue;
            }
            NSString *enc = [NSString stringWithUTF8String:returnType];
            IMP replacement = NULL;
            if ([enc isEqualToString:@"B"] || [enc isEqualToString:@"c"]) replacement = (IMP)replacement_bool;
            else if ([enc isEqualToString:@"@"]) replacement = (IMP)replacement_object_custom;
            else replacement = (IMP)replacement_number_custom;
            class_replaceMethod(targetClass, targetSel, replacement, method_getTypeEncoding(method));
            Method installed = class_getInstanceMethod(targetClass, targetSel);
            BOOL applied = installed && method_getImplementation(installed) == replacement;
            unit[@"validationStatus"] = applied ? @"applied" : @"invalid";
            unit[@"validationMessage"] = applied ? @"Override instalado no método ativo" : @"Não foi possível instalar o override";
            free(returnType);
            units[unitIndex] = unit;
        }
        patch[@"units"] = units;
    }
    savePatches(patches);
}
// --- TELA 5: EDITAR UNIT ---
@interface UnitDetailEditorController : UITableViewController
@property (nonatomic, assign) NSInteger patchIndex;
@property (nonatomic, assign) NSInteger unitIndex;
@property (nonatomic, strong) NSMutableDictionary *unitData;
@end

@implementation UnitDetailEditorController
- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"Edit Unit";
}

- (void)tableView:(UITableView *)tableView willDisplayCell:(UITableViewCell *)cell forRowAtIndexPath:(NSIndexPath *)indexPath {
    if (isGlobalAnimationEnabled()) animateCell(cell);
}

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView { return 3; }
- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    if (section == 0) return 2;
    NSMutableArray *patches = loadPatches();
    if (self.patchIndex < patches.count) {
        NSDictionary *patchDict = patches[self.patchIndex];
        NSArray *units = patchDict[@"units"];
        if (units && self.unitIndex < units.count) {
            self.unitData = [NSMutableDictionary dictionaryWithDictionary:units[self.unitIndex]];
        }
    }
    if (section == 1) {
        NSString *methodInfo = self.unitData[@"method"] ?: @"";
        if ([methodInfo containsString:@"[void]"]) return 2;
        if ([methodInfo containsString:@"[boolean]"]) return 3;
        return 2;
    } else {
        NSArray *arguments = self.unitData[@"arguments"];
        return (arguments && arguments.count > 0) ? arguments.count : 1;
    }
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
    if (section == 0) return @"Unit Information";
    if (section == 1) return @"Override Return / Behavior";
    return @"Arguments (Function Parameters)";
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    static NSString *cellID = @"Cell";
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:cellID];
    if (!cell) cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleValue1 reuseIdentifier:cellID];
    cell.accessoryType = UITableViewCellAccessoryNone;
    cell.detailTextLabel.text = nil;
    
    if (indexPath.section == 0) {
        if (indexPath.row == 0) {
            cell.textLabel.text = @"Method";
            cell.detailTextLabel.text = self.unitData[@"method"];
            cell.detailTextLabel.font = [UIFont fontWithName:@"Courier" size:10.0];
        } else {
            cell.textLabel.text = @"Class";
            cell.detailTextLabel.text = self.unitData[@"class"];
        }
    } else if (indexPath.section == 1) {
        NSString *methodInfo = self.unitData[@"method"] ?: @"";
        NSString *currentOverride = self.unitData[@"overrideType"] ?: @"default";
        
        if ([methodInfo containsString:@"[void]"]) {
            if (indexPath.row == 0) { cell.textLabel.text = @"Default"; if ([currentOverride isEqualToString:@"default"]) cell.accessoryType = UITableViewCellAccessoryCheckmark; }
            else if (indexPath.row == 1) { cell.textLabel.text = @"Bypass"; if ([currentOverride isEqualToString:@"bypass"]) cell.accessoryType = UITableViewCellAccessoryCheckmark; }
        } else if ([methodInfo containsString:@"[boolean]"]) {
            if (indexPath.row == 0) { cell.textLabel.text = @"Default"; if ([currentOverride isEqualToString:@"default"]) cell.accessoryType = UITableViewCellAccessoryCheckmark; }
            else if (indexPath.row == 1) { cell.textLabel.text = @"true (YES)"; if ([currentOverride caseInsensitiveCompare:@"YES"] == NSOrderedSame || [currentOverride caseInsensitiveCompare:@"true"] == NSOrderedSame) cell.accessoryType = UITableViewCellAccessoryCheckmark; }
            else if (indexPath.row == 2) { cell.textLabel.text = @"false (NO)"; if ([currentOverride caseInsensitiveCompare:@"NO"] == NSOrderedSame || [currentOverride caseInsensitiveCompare:@"false"] == NSOrderedSame) cell.accessoryType = UITableViewCellAccessoryCheckmark; }
        } else {
            if (indexPath.row == 0) { cell.textLabel.text = @"Default"; if ([currentOverride isEqualToString:@"default"]) cell.accessoryType = UITableViewCellAccessoryCheckmark; }
            else if (indexPath.row == 1) {
                cell.textLabel.text = @"Custom Value...";
                cell.detailTextLabel.text = self.unitData[@"customValue"] ?: @"Not set";
                if ([currentOverride isEqualToString:@"custom"]) cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
            }
        }
    } else {
        cell.textLabel.text = @"No arguments";
    }
    return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    if (indexPath.section == 1) {
        NSString *methodInfo = self.unitData[@"method"] ?: @"";
        if ([methodInfo containsString:@"[void]"]) {
            self.unitData[@"overrideType"] = (indexPath.row == 0) ? @"default" : @"bypass";
            [self saveChangesAndReload];
        } else if ([methodInfo containsString:@"[boolean]"]) {
            if (indexPath.row == 0) self.unitData[@"overrideType"] = @"default";
            else if (indexPath.row == 1) self.unitData[@"overrideType"] = @"YES";
            else if (indexPath.row == 2) self.unitData[@"overrideType"] = @"NO";
            [self saveChangesAndReload];
        } else if (indexPath.row == 1) {
            UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Custom Value" message:@"Enter value" preferredStyle:UIAlertControllerStyleAlert];
            [alert addTextFieldWithConfigurationHandler:^(UITextField *tf) { tf.text = self.unitData[@"customValue"] ?: @""; }];
            [alert addAction:[UIAlertAction actionWithTitle:@"Save" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
                self.unitData[@"overrideType"] = @"custom";
                self.unitData[@"customValue"] = alert.textFields[0].text ?: @"";
                [self saveChangesAndReload];
            }]];
            [alert addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
            [self presentViewController:alert animated:YES completion:nil];
        }
    }
}

- (void)saveChangesAndReload {
    NSMutableArray *patches = loadPatches();
    if (self.patchIndex < patches.count) {
        NSMutableDictionary *patch = [NSMutableDictionary dictionaryWithDictionary:patches[self.patchIndex]];
        NSMutableArray *units = [NSMutableArray arrayWithArray:patch[@"units"]];
        if (self.unitIndex < units.count) {
            units[self.unitIndex] = self.unitData;
            patch[@"units"] = units;
            patches[self.patchIndex] = patch;
            savePatches(patches);
            applyActivePatches();
        }
    }
    [self.tableView reloadData];
}
@end

// --- TELA 4: UNITS DO PATCH ---
@interface PatchUnitsController : UITableViewController
@property (nonatomic, assign) NSInteger patchIndex;
@property (nonatomic, strong) NSMutableDictionary *patchData;
@end

@implementation PatchUnitsController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = self.patchData[@"name"] ?: @"Patch Units";
    self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemAdd target:self action:@selector(addUnitsToPatch)];
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    NSMutableArray *patches = loadPatches();
    if (self.patchIndex < patches.count) {
        self.patchData = [NSMutableDictionary dictionaryWithDictionary:patches[self.patchIndex]];
        [self.tableView reloadData];
    }
}

- (void)tableView:(UITableView *)tableView willDisplayCell:(UITableViewCell *)cell forRowAtIndexPath:(NSIndexPath *)indexPath {
    if (isGlobalAnimationEnabled()) animateCell(cell);
}

- (void)addUnitsToPatch {
    ImageListController *imageListVC = [[ImageListController alloc] initWithStyle:UITableViewStylePlain];
    imageListVC.patchIndex = self.patchIndex;
    [self.navigationController pushViewController:imageListVC animated:YES];
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    NSArray *units = self.patchData[@"units"];
    return units ? units.count : 0;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    static NSString *cellID = @"UnitCell";
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:cellID];
    if (!cell) cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:cellID];
    NSDictionary *unit = self.patchData[@"units"][indexPath.row];
    cell.textLabel.text = unit[@"name"];
    cell.textLabel.font = [UIFont fontWithName:@"Courier" size:11.0];
    cell.detailTextLabel.text = [NSString stringWithFormat:@"Class: %@ | Return: %@", unit[@"class"], unit[@"overrideType"] ?: @"default"];
    cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
    return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    UnitDetailEditorController *editorVC = [[UnitDetailEditorController alloc] initWithStyle:UITableViewStyleGrouped];
    editorVC.patchIndex = self.patchIndex;
    editorVC.unitIndex = indexPath.row;
    [self.navigationController pushViewController:editorVC animated:YES];
}

// --- FUNÇÃO DE APAGAR UNITS (SWIPE TO DELETE) ---
- (BOOL)tableView:(UITableView *)tableView canEditRowAtIndexPath:(NSIndexPath *)indexPath {
    return YES; // Habilita a edição para permitir apagar a linha
}

- (void)tableView:(UITableView *)tableView commitEditingStyle:(UITableViewCellEditingStyle)editingStyle forRowAtIndexPath:(NSIndexPath *)indexPath {
    if (editingStyle == UITableViewCellEditingStyleDelete) {
        NSMutableArray *patches = loadPatches();
        if (self.patchIndex < patches.count) {
            NSMutableDictionary *patch = [NSMutableDictionary dictionaryWithDictionary:patches[self.patchIndex]];
            NSMutableArray *units = [NSMutableArray arrayWithArray:patch[@"units"] ?: @[]];
            
            if (indexPath.row < units.count) {
                [units removeObjectAtIndex:indexPath.row];
                patch[@"units"] = units;
                patches[self.patchIndex] = patch;
                savePatches(patches);
                
                // Atualiza os dados locais e remove a linha da tela com animação
                self.patchData = patch;
                [tableView deleteRowsAtIndexPaths:@[indexPath] withRowAnimation:UITableViewRowAnimationAutomatic];
                
                // Reaplica os patches ativos imediatamente
                applyActivePatches();
            }
        }
    }
}

@end

// --- TELA 3: LISTA DE MÉTODOS ---
@implementation MethodListController {
    NSMutableArray *_methodList;
    NSMutableArray *_filteredMethodList;
    NSMutableSet *_selectedMethods;
    UISearchController *_searchController;
    NSInteger _patchIndex; // Armazena o patch atual
}

- (instancetype)initWithClass:(Class)cls patchIndex:(NSInteger)patchIndex {
    self = [super initWithStyle:UITableViewStylePlain];
    if (self) {
        self.targetClass = cls;
        _patchIndex = patchIndex;
        _methodList = [NSMutableArray array];
        _filteredMethodList = [NSMutableArray array];
        _selectedMethods = [NSMutableSet set];
    }
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = [NSString stringWithUTF8String:class_getName(self.targetClass)];
    self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemDone target:self action:@selector(saveSelectedUnitsToPatch)];
    
    _searchController = [[UISearchController alloc] initWithSearchResultsController:nil];
    _searchController.searchResultsUpdater = self;
    _searchController.obscuresBackgroundDuringPresentation = NO;
    _searchController.searchBar.placeholder = @"Pesquisar método...";
    self.navigationItem.searchController = _searchController;
    self.definesPresentationContext = YES;

    // Carregar units existentes para manter selecionadas
    NSMutableArray *patches = loadPatches();
    if (_patchIndex < patches.count) {
        NSDictionary *patch = patches[_patchIndex];
        NSArray *units = patch[@"units"];
        NSString *className = [NSString stringWithUTF8String:class_getName(self.targetClass)];
        for (NSDictionary *unit in units) {
            if ([unit[@"class"] isEqualToString:className]) {
                NSString *methodInfo = unit[@"method"];
                if (methodInfo) {
                    [_selectedMethods addObject:methodInfo];
                }
            }
        }
    }

    unsigned int methodCount = 0;
    Method *methods = class_copyMethodList(self.targetClass, &methodCount);
    if (methods) {
        for (unsigned int i = 0; i < methodCount; i++) {
            SEL sel = method_getName(methods[i]);
            const char *selName = sel_getName(sel);
            char *returnType = method_copyReturnType(methods[i]);
            NSString *typeStr = @"unknown";
            if (returnType) {
                NSString *enc = [NSString stringWithUTF8String:returnType];
                if ([enc isEqualToString:@"B"] || [enc isEqualToString:@"c"]) typeStr = @"boolean";
                else if ([enc isEqualToString:@"@"]) typeStr = @"object";
                else if ([enc isEqualToString:@"v"]) typeStr = @"void";
                else typeStr = @"number";
                free(returnType);
            }
            // Formato limpo guardado internamente ou exibido
            NSString *methodFormatted = [NSString stringWithFormat:@"%s ➔ [%@]", selName, typeStr];
            [_methodList addObject:methodFormatted];
        }
        free(methods);
    }
    [_methodList sortUsingSelector:@selector(localizedCaseInsensitiveCompare:)];
}

- (void)tableView:(UITableView *)tableView willDisplayCell:(UITableViewCell *)cell forRowAtIndexPath:(NSIndexPath *)indexPath {
    if (isGlobalAnimationEnabled()) animateCell(cell);
}

- (void)updateSearchResultsForSearchController:(UISearchController *)searchController {
    NSString *searchText = searchController.searchBar.text;
    [_filteredMethodList removeAllObjects];
    if (searchText.length > 0) {
        NSPredicate *predicate = [NSPredicate predicateWithFormat:@"self CONTAINS[c] %@", searchText];
        [_filteredMethodList addObjectsFromArray:[_methodList filteredArrayUsingPredicate:predicate]];
    } else {
        [_filteredMethodList addObjectsFromArray:_methodList];
    }
    [self.tableView reloadData];
}

- (BOOL)isSearching { return _searchController.isActive && _searchController.searchBar.text.length > 0; }
- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section { return [self isSearching] ? _filteredMethodList.count : _methodList.count; }

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    static NSString *cellID = @"MethodCell";
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:cellID];
    if (!cell) cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:cellID];
    
    NSString *methodInfo = [self isSearching] ? _filteredMethodList[indexPath.row] : _methodList[indexPath.row];
    cell.textLabel.text = methodInfo;
    cell.textLabel.font = [UIFont fontWithName:@"Courier" size:11.0];
    
    // Mantém marcado se já estiver salvo na Unit
    cell.accessoryType = [_selectedMethods containsObject:methodInfo] ? UITableViewCellAccessoryCheckmark : UITableViewCellAccessoryNone;
    return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    NSString *methodInfo = [self isSearching] ? _filteredMethodList[indexPath.row] : _methodList[indexPath.row];
    if ([_selectedMethods containsObject:methodInfo]) {
        [_selectedMethods removeObject:methodInfo];
    } else {
        [_selectedMethods addObject:methodInfo];
    }
    [tableView reloadRowsAtIndexPaths:@[indexPath] withRowAnimation:UITableViewRowAnimationNone];
}

- (void)saveSelectedUnitsToPatch {
    NSMutableArray *patches = loadPatches();
    if (_patchIndex < patches.count) {
        NSMutableDictionary *patch = [NSMutableDictionary dictionaryWithDictionary:patches[_patchIndex]];
        NSMutableArray *units = [NSMutableArray array];
        NSString *className = [NSString stringWithUTF8String:class_getName(self.targetClass)];
        
        // Reconstrói as units preservando configurações anteriores ou criando novas
        NSArray *oldUnits = patch[@"units"] ?: @[];
        for (NSString *methodInfo in _selectedMethods) {
            NSDictionary *existingUnit = nil;
            for (NSDictionary *u in oldUnits) {
                if ([u[@"class"] isEqualToString:className] && [u[@"method"] isEqualToString:methodInfo]) {
                    existingUnit = u;
                    break;
                }
            }
            if (existingUnit) {
                [units addObject:existingUnit];
            } else {
                [units addObject:@{
                    @"name": [NSString stringWithFormat:@"[%@] %@", className, methodInfo],
                    @"class": className,
                    @"method": methodInfo,
                    @"overrideType": @"default",
                    @"customValue": @"",
                    @"arguments": @[]
                }];
            }
        }
        patch[@"units"] = units;
        patches[_patchIndex] = patch;
        savePatches(patches);
        applyActivePatches();
    }
    
    for (UIViewController *vc in self.navigationController.viewControllers) {
        if ([vc isKindOfClass:[PatchUnitsController class]]) {
            [self.navigationController popToViewController:vc animated:YES];
            return;
        }
    }
    [self.navigationController popViewControllerAnimated:YES];
}
@end

// --- TELA 2A & 2B ---
@implementation ImageListController {
    NSMutableArray *_imageList;
    NSMutableArray *_filteredImageList;
    UISearchController *_searchController;
}
- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"Select Dylib";
    _imageList = [NSMutableArray array];
    _filteredImageList = [NSMutableArray array];
    _searchController = [[UISearchController alloc] initWithSearchResultsController:nil];
    _searchController.searchResultsUpdater = self;
    self.navigationItem.searchController = _searchController;
    self.definesPresentationContext = YES;
    
    uint32_t imageCount = _dyld_image_count();
    for (uint32_t i = 0; i < imageCount; i++) {
        const char *imageName = _dyld_get_image_name(i);
        if (imageName) {
            NSString *imgStr = [NSString stringWithUTF8String:imageName];
            if (![_imageList containsObject:imgStr]) [_imageList addObject:imgStr];
        }
    }
    [_imageList sortUsingSelector:@selector(localizedCaseInsensitiveCompare:)];
}
- (void)tableView:(UITableView *)tableView willDisplayCell:(UITableViewCell *)cell forRowAtIndexPath:(NSIndexPath *)indexPath {
    if (isGlobalAnimationEnabled()) animateCell(cell);
}
- (void)updateSearchResultsForSearchController:(UISearchController *)searchController {
    NSString *searchText = searchController.searchBar.text;
    [_filteredImageList removeAllObjects];
    if (searchText.length > 0) {
        NSPredicate *predicate = [NSPredicate predicateWithFormat:@"self CONTAINS[c] %@", searchText];
        [_filteredImageList addObjectsFromArray:[_imageList filteredArrayUsingPredicate:predicate]];
    } else { [_filteredImageList addObjectsFromArray:_imageList]; }
    [self.tableView reloadData];
}
- (BOOL)isSearching { return _searchController.isActive && _searchController.searchBar.text.length > 0; }
- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section { return [self isSearching] ? _filteredImageList.count : _imageList.count; }
- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    static NSString *cellID = @"ImageCell";
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:cellID];
    if (!cell) cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:cellID];
    NSString *imagePath = [self isSearching] ? _filteredImageList[indexPath.row] : _imageList[indexPath.row];
    cell.textLabel.text = [imagePath lastPathComponent];
    cell.detailTextLabel.text = imagePath;
    cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
    return cell;
}
- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    NSString *imagePath = [self isSearching] ? _filteredImageList[indexPath.row] : _imageList[indexPath.row];
    SharedModulesBrowserController *classBrowser = [[SharedModulesBrowserController alloc] initWithStyle:UITableViewStylePlain];
    classBrowser.targetImageName = imagePath;
    classBrowser.patchIndex = self.patchIndex;
    [self.navigationController pushViewController:classBrowser animated:YES];
}
@end

// --- NAVEGADOR DE MÓDULOS E PESQUISA DE MÉTODOS (CORRIGIDO PARA SALVAR A CLASSE EXATA) ---
@implementation SharedModulesBrowserController {
    NSMutableArray *_classList;
    NSMutableArray *_filteredItems;
    NSMutableSet *_selectedMethodSignatures;
    NSMutableDictionary *_methodToClassMap; // Mapeia exatamente qual método pertence a qual classe
    UISearchController *_searchController;
    dispatch_queue_t _searchQueue;
    NSInteger _searchToken;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = self.targetImageName ? [self.targetImageName lastPathComponent] : @"Classes";
    _classList = [NSMutableArray array];
    _filteredItems = [NSMutableArray array];
    _selectedMethodSignatures = [NSMutableSet set];
    _methodToClassMap = [NSMutableDictionary dictionary];
    _searchQueue = dispatch_queue_create("com.flex.searchQueue", DISPATCH_QUEUE_SERIAL);
    _searchToken = 0;
    
    self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemDone target:self action:@selector(confirmSelectedMethodsToPatch)];
    
    _searchController = [[UISearchController alloc] initWithSearchResultsController:nil];
    _searchController.searchResultsUpdater = self;
    _searchController.obscuresBackgroundDuringPresentation = NO;
    _searchController.searchBar.placeholder = @"Pesquisar classe ou função...";
    self.navigationItem.searchController = _searchController;
    self.definesPresentationContext = YES;
    
    // Pré-carrega units já salvas para manter marcadas
    NSMutableArray *patches = loadPatches();
    if (self.patchIndex < patches.count) {
        NSDictionary *patch = patches[self.patchIndex];
        NSArray *units = patch[@"units"] ?: @[];
        for (NSDictionary *unit in units) {
            NSString *methodFull = unit[@"method"];
            NSString *clsName = unit[@"class"];
            if (methodFull && clsName) {
                [_selectedMethodSignatures addObject:methodFull];
                _methodToClassMap[methodFull] = clsName; // Guarda o mapeamento
            }
        }
    }
    
    int numClasses = objc_getClassList(NULL, 0);
    if (numClasses > 0) {
        Class *classes = (Class *)malloc(sizeof(Class) * numClasses);
        numClasses = objc_getClassList(classes, numClasses);
        for (int i = 0; i < numClasses; i++) {
            Class cls = classes[i];
            const char *imageName = class_getImageName(cls);
            if (imageName) {
                NSString *imgStr = [NSString stringWithUTF8String:imageName];
                if (self.targetImageName && [imgStr isEqualToString:self.targetImageName]) {
                    [_classList addObject:[NSString stringWithUTF8String:class_getName(cls)]];
                }
            }
        }
        free(classes);
    }
    [_classList sortUsingSelector:@selector(localizedCaseInsensitiveCompare:)];
}

- (void)tableView:(UITableView *)tableView willDisplayCell:(UITableViewCell *)cell forRowAtIndexPath:(NSIndexPath *)indexPath {
    if (isGlobalAnimationEnabled()) animateCell(cell);
}

- (void)updateSearchResultsForSearchController:(UISearchController *)searchController {
    NSString *searchText = searchController.searchBar.text;
    
    if (searchText.length == 0) {
        [_filteredItems removeAllObjects];
        [self.tableView reloadData];
        return;
    }
    
    NSInteger currentToken = ++_searchToken;
    NSArray *classesSnapshot = [_classList copy];
    
    dispatch_async(_searchQueue, ^{
        NSMutableArray *results = [NSMutableArray array];
        NSMutableSet *seenClassMethods = [NSMutableSet set]; // Controla classe + método para permitir nomes iguais em classes diferentes
        NSMutableDictionary *tempMap = [NSMutableDictionary dictionary];
        
        for (NSString *className in classesSnapshot) {
            if (currentToken != self->_searchToken) return;
            
            if ([className localizedCaseInsensitiveContainsString:searchText]) {
                [results addObject:@{
                    @"type": @"class",
                    @"class": className,
                    @"name": className
                }];
            }
            
            Class cls = NSClassFromString(className);
            if (cls) {
                unsigned int methodCount = 0;
                Method *methods = class_copyMethodList(cls, &methodCount);
                if (methods) {
                    for (unsigned int m = 0; m < methodCount; m++) {
                        if (currentToken != self->_searchToken) {
                            free(methods);
                            return;
                        }
                        SEL sel = method_getName(methods[m]);
                        NSString *methodName = [NSString stringWithUTF8String:sel_getName(sel)];
                        
                        if ([methodName localizedCaseInsensitiveContainsString:searchText]) {
                            char *returnType = method_copyReturnType(methods[m]);
                            NSString *typeStr = @"unknown";
                            if (returnType) {
                                NSString *enc = [NSString stringWithUTF8String:returnType];
                                if ([enc isEqualToString:@"B"] || [enc isEqualToString:@"c"]) typeStr = @"boolean";
                                else if ([enc isEqualToString:@"@"]) typeStr = @"object";
                                else if ([enc isEqualToString:@"v"]) typeStr = @"void";
                                else typeStr = @"number";
                                free(returnType);
                            }
                            
                            NSString *formattedMethod = [NSString stringWithFormat:@"%@ ➔ [%@]", methodName, typeStr];
                            
                            // Cria uma chave única combinando a CLASSE e o MÉTODO
                            NSString *uniqueKey = [NSString stringWithFormat:@"%@_%@", className, formattedMethod];
                            
                            // Só adiciona se essa combinação exata ainda não foi vista
                            if (![seenClassMethods containsObject:uniqueKey]) {
                                [seenClassMethods addObject:uniqueKey];
                                tempMap[formattedMethod] = className;
                                
                                [results addObject:@{
                                    @"type": @"method",
                                    @"class": className,
                                    @"methodName": methodName,
                                    @"returnType": typeStr,
                                    @"formattedMethod": formattedMethod,
                                    @"name": methodName
                                }];
                            }
                            
                            if (results.count > 120) break;
                        }
                    }
                    free(methods);
                }
            }
            if (results.count > 120) break;
        }
        
        dispatch_async(dispatch_get_main_queue(), ^{
            if (currentToken == self->_searchToken) {
                [self->_filteredItems setArray:results];
                [self->_methodToClassMap addEntriesFromDictionary:tempMap];
                [self.tableView reloadData];
            }
        });
    });
}

- (BOOL)isSearching { return _searchController.isActive && _searchController.searchBar.text.length > 0; }

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return [self isSearching] ? _filteredItems.count : _classList.count;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    static NSString *cellID = @"ModuleCell";
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:cellID];
    if (!cell) cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:cellID];

    if ([self isSearching]) {
        if (indexPath.row < _filteredItems.count) {
            NSDictionary *item = _filteredItems[indexPath.row];
            if ([item[@"type"] isEqualToString:@"class"]) {
                cell.textLabel.text = item[@"class"];
                cell.detailTextLabel.text = @"Classe Principal (Toque para abrir métodos)";
                cell.detailTextLabel.font = [UIFont systemFontOfSize:11.0];
                cell.detailTextLabel.textColor = [UIColor systemGrayColor];
                cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
            } else {
                cell.textLabel.text = item[@"methodName"];
                cell.textLabel.font = [UIFont fontWithName:@"Courier" size:12.0];
                cell.detailTextLabel.text = [NSString stringWithFormat:@"Classe: %@ | Tipo: [%@]", item[@"class"], item[@"returnType"]];
                cell.detailTextLabel.font = [UIFont fontWithName:@"Courier-Bold" size:10.0];
                cell.detailTextLabel.textColor = [UIColor systemBlueColor];
                
                NSString *formatted = item[@"formattedMethod"];
                cell.accessoryType = [_selectedMethodSignatures containsObject:formatted] ? UITableViewCellAccessoryCheckmark : UITableViewCellAccessoryNone;
            }
        }
    } else {
        if (indexPath.row < _classList.count) {
            cell.textLabel.text = _classList[indexPath.row];
            cell.textLabel.font = [UIFont systemFontOfSize:14.0];
            cell.detailTextLabel.text = nil;
            cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
        }
    }
    return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    
    if (![self isSearching]) {
        NSString *className = _classList[indexPath.row];
        Class targetClass = NSClassFromString(className);
        if (targetClass) {
            MethodListController *methodVC = [[MethodListController alloc] initWithClass:targetClass patchIndex:self.patchIndex];
            [self.navigationController pushViewController:methodVC animated:YES];
        }
        return;
    }
    
    NSDictionary *item = _filteredItems[indexPath.row];
    if ([item[@"type"] isEqualToString:@"class"]) {
        Class targetClass = NSClassFromString(item[@"class"]);
        if (targetClass) {
            MethodListController *methodVC = [[MethodListController alloc] initWithClass:targetClass patchIndex:self.patchIndex];
            [self.navigationController pushViewController:methodVC animated:YES];
        }
    } else {
        NSString *formatted = item[@"formattedMethod"];
        NSString *clsName = item[@"class"];
        
        // Garante o registro correto no mapa de classes
        if (formatted && clsName) {
            _methodToClassMap[formatted] = clsName;
        }
        
        if ([_selectedMethodSignatures containsObject:formatted]) {
            [_selectedMethodSignatures removeObject:formatted];
        } else {
            [_selectedMethodSignatures addObject:formatted];
        }
        [tableView reloadRowsAtIndexPaths:@[indexPath] withRowAnimation:UITableViewRowAnimationNone];
    }
}

- (void)confirmSelectedMethodsToPatch {
    NSMutableArray *patches = loadPatches();
    if (self.patchIndex < patches.count) {
        NSMutableDictionary *patch = [NSMutableDictionary dictionaryWithDictionary:patches[self.patchIndex]];
        NSMutableArray *units = [NSMutableArray array];
        NSArray *oldUnits = patch[@"units"] ?: @[];
        
        for (NSString *methodFormatted in _selectedMethodSignatures) {
            // Busca a classe correta mapeada pelo dicionário de referência
            NSString *foundClass = _methodToClassMap[methodFormatted];
            
            // Fallback caso não ache no mapa recém criado
            if (!foundClass || [foundClass isEqualToString:@"UnknownClass"]) {
                for (NSDictionary *u in oldUnits) {
                    if ([u[@"method"] isEqualToString:methodFormatted]) {
                        foundClass = u[@"class"];
                        break;
                    }
                }
            }
            if (!foundClass) foundClass = @"NSObject"; // Fallback final seguro
            
            NSDictionary *existingUnit = nil;
            for (NSDictionary *u in oldUnits) {
                if ([u[@"class"] isEqualToString:foundClass] && [u[@"method"] isEqualToString:methodFormatted]) {
                    existingUnit = u;
                    break;
                }
            }
            
            if (existingUnit) {
                [units addObject:existingUnit];
            } else {
                [units addObject:@{
                    @"name": [NSString stringWithFormat:@"[%@] %@", foundClass, methodFormatted],
                    @"class": foundClass,
                    @"method": methodFormatted,
                    @"overrideType": @"default",
                    @"customValue": @"",
                    @"arguments": @[]
                }];
            }
        }
        
        patch[@"units"] = units;
        patches[self.patchIndex] = patch;
        savePatches(patches);
        applyActivePatches();
    }
    
    for (UIViewController *vc in self.navigationController.viewControllers) {
        if ([vc isKindOfClass:[PatchUnitsController class]]) {
            [self.navigationController popToViewController:vc animated:YES];
            return;
        }
    }
    [self.navigationController popViewControllerAnimated:YES];
}
@end

@implementation NavigationBarCustomizationController
- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"Navigation Bar";
    self.view.backgroundColor = [UIColor blackColor];
    self.tableView.backgroundColor = [UIColor blackColor];
    self.tableView.separatorStyle = UITableViewCellSeparatorStyleNone;
    self.tableView.rowHeight = 64.0;
    self.navigationItem.leftBarButtonItem = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemClose target:self action:@selector(closeNavigationBar)];
}
- (void)closeNavigationBar { [self dismissViewControllerAnimated:YES completion:nil]; }
- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section { return 5; }
- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"NavItemCell"];
    if (!cell) {
        cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:@"NavItemCell"];
        cell.backgroundColor = [UIColor blackColor];
        cell.textLabel.textColor = [UIColor colorWithWhite:0.9 alpha:1.0];
        cell.detailTextLabel.textColor = [UIColor colorWithWhite:0.5 alpha:1.0];
        cell.textLabel.font = [UIFont systemFontOfSize:14.0 weight:UIFontWeightMedium];
        cell.detailTextLabel.font = [UIFont systemFontOfSize:10.0 weight:UIFontWeightRegular];
        cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
    }
    NSArray *names = dylibtestNavNames();
    cell.textLabel.text = names[indexPath.row];
    cell.detailTextLabel.text = dylibtestNavIconAtIndex(indexPath.row) ? @"Nome e ícone personalizados" : @"Toque para alterar nome e ícone";
    UIImage *icon = dylibtestNavIconAtIndex(indexPath.row);
    cell.imageView.image = icon ?: [UIImage systemImageNamed:@"square.dashed" ];
    cell.imageView.tintColor = dylibtestAccentColor();
    return cell;
}
- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Nome do item" message:@"Defina o nome que aparecerá na Navigation Bar." preferredStyle:UIAlertControllerStyleAlert];
    [alert addTextFieldWithConfigurationHandler:^(UITextField *field) { field.text = dylibtestNavNames()[indexPath.row]; field.placeholder = @"Nome"; }];
    [alert addAction:[UIAlertAction actionWithTitle:@"Salvar nome" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
        NSMutableArray *names = dylibtestNavNames();
        NSString *name = alert.textFields.firstObject.text;
        if (name.length) names[indexPath.row] = name;
        dylibtestSaveNavNames(names);
        [self.tableView reloadRowsAtIndexPaths:@[indexPath] withRowAnimation:UITableViewRowAnimationNone];
        dylibtestApplyAppearanceToWindow();
    }]];
    [alert addAction:[UIAlertAction actionWithTitle:@"Escolher ícone" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
        UIImagePickerController *picker = [[UIImagePickerController alloc] init];
        picker.sourceType = UIImagePickerControllerSourceTypePhotoLibrary;
        picker.delegate = self;
        picker.view.tag = 100 + indexPath.row;
        [self presentViewController:picker animated:YES completion:nil];
    }]];
    [alert addAction:[UIAlertAction actionWithTitle:@"Cancelar" style:UIAlertActionStyleCancel handler:nil]];
    [self presentViewController:alert animated:YES completion:nil];
}
- (void)imagePickerController:(UIImagePickerController *)picker didFinishPickingMediaWithInfo:(NSDictionary *)info {
    UIImage *image = info[UIImagePickerControllerOriginalImage];
    NSInteger index = picker.view.tag - 100;
    dylibtestSaveJPEGImage(image, [NSString stringWithFormat:@"nav-icon-%ld.jpg", (long)index]);
    [picker dismissViewControllerAnimated:YES completion:^{ [self.tableView reloadData]; dylibtestApplyAppearanceToWindow(); }];
}
- (void)imagePickerControllerDidCancel:(UIImagePickerController *)picker { [picker dismissViewControllerAnimated:YES completion:nil]; }
@end

@implementation FlexTopicsController
- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"WhatsApp UI";
    self.tableView.backgroundColor = [UIColor blackColor];
    self.tableView.separatorStyle = UITableViewCellSeparatorStyleNone;
    self.tableView.rowHeight = 64.0;
    self.navigationItem.leftBarButtonItem = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemClose target:self action:@selector(closeTopics)];
}
- (void)closeTopics { [self dismissViewControllerAnimated:YES completion:nil]; }
- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section { return 7; }
- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"TopicCell"];
    if (!cell) {
        cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:@"TopicCell"];
        cell.backgroundColor = [UIColor blackColor];
        cell.textLabel.textColor = [UIColor colorWithWhite:0.92 alpha:1.0];
        cell.detailTextLabel.textColor = [UIColor colorWithWhite:0.48 alpha:1.0];
        cell.textLabel.font = [UIFont systemFontOfSize:15.0 weight:UIFontWeightMedium];
        cell.detailTextLabel.font = [UIFont systemFontOfSize:11.0 weight:UIFontWeightRegular];
        cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
        cell.tintColor = [UIColor colorWithWhite:0.55 alpha:1.0];
    }
    NSArray *titles = @[@"Aparência", @"Navigation Bar", @"Conversas e mensagens", @"Listas e contatos", @"Animações", @"Gestos e toque", @"Funções dinâmicas"];
    NSArray *details = @[@"Wallpaper, tema, fonte, cores e ícones", @"Nomes, ícones, cor e ordem dos itens", @"Bolhas, timestamps e pré-visualização", @"Avatares, células e separadores", @"Estilos originais e intensidade", @"Indicador e preferências de toque", @"Frameworks, classes, métodos e validação"];
    cell.textLabel.text = titles[indexPath.row];
    cell.detailTextLabel.text = details[indexPath.row];
    return cell;
}
- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    NSArray *topicTitles = @[@"Aparência", @"Navigation Bar", @"Conversas e mensagens", @"Listas e contatos", @"Animações", @"Gestos e toque", @"Funções dinâmicas"];
    if (indexPath.row == 0) {
        DesignCustomizationController *vc = [[DesignCustomizationController alloc] initWithStyle:UITableViewStylePlain];
        [self.navigationController pushViewController:vc animated:YES];
    } else if (indexPath.row == 1) {
        NavigationBarCustomizationController *vc = [[NavigationBarCustomizationController alloc] initWithStyle:UITableViewStylePlain];
        [self.navigationController pushViewController:vc animated:YES];
    } else if (indexPath.row == 4) {
        UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Animações" message:@"Selecione um estilo original do Flex." preferredStyle:UIAlertControllerStyleActionSheet];
        NSArray *styles = @[@"Desativar", @"Deslizar", @"Escala", @"Fade", @"Giro", @"Subir", @"Mola"];
        for (NSInteger i = 0; i < styles.count; i++) [alert addAction:[UIAlertAction actionWithTitle:styles[i] style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) { setGlobalAnimationEnabled(i != 0); if (i > 0) setGlobalAnimationStyle(i - 1); }]];
        [alert addAction:[UIAlertAction actionWithTitle:@"Cancelar" style:UIAlertActionStyleCancel handler:nil]];
        [self presentViewController:alert animated:YES completion:nil];
    } else if (indexPath.row == 5) {
        UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Gestos e toque" message:@"As rotinas originais são preservadas." preferredStyle:UIAlertControllerStyleActionSheet];
        [alert addAction:[UIAlertAction actionWithTitle:isTouchVisualizerEnabled() ? @"Desativar indicador" : @"Ativar indicador" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) { setTouchVisualizerEnabled(!isTouchVisualizerEnabled()); }]];
        [alert addAction:[UIAlertAction actionWithTitle:@"Cancelar" style:UIAlertActionStyleCancel handler:nil]];
        [self presentViewController:alert animated:YES completion:nil];
    } else if (indexPath.row == 6) {
        SharedModulesBrowserController *vc = [[SharedModulesBrowserController alloc] initWithStyle:UITableViewStylePlain];
        [self.navigationController pushViewController:vc animated:YES];
    } else {
        UIAlertController *alert = [UIAlertController alertControllerWithTitle:topicTitles[indexPath.row] message:@"Essa categoria usa os componentes detectados no SharedModules e será aplicada somente quando a classe correspondente estiver ativa no WhatsApp." preferredStyle:UIAlertControllerStyleAlert];
        [alert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
        [self presentViewController:alert animated:YES completion:nil];
    }
}
@end

@implementation DesignCustomizationController
- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"WhatsApp UI";
    self.view.backgroundColor = [UIColor blackColor];
    self.tableView.backgroundColor = [UIColor blackColor];
    self.tableView.separatorStyle = UITableViewCellSeparatorStyleNone;
    self.tableView.rowHeight = 62.0;
    self.navigationItem.leftBarButtonItem = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemClose target:self action:@selector(closeDesign)];
}
- (void)closeDesign {
    [self dismissViewControllerAnimated:YES completion:nil];
}
- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section { return 8; }
- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"DesignCell"];
    if (!cell) {
        cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleValue1 reuseIdentifier:@"DesignCell"];
        cell.backgroundColor = [UIColor blackColor];
        cell.textLabel.textColor = [UIColor colorWithWhite:0.9 alpha:1.0];
        cell.detailTextLabel.textColor = [UIColor colorWithWhite:0.48 alpha:1.0];
        cell.textLabel.font = [UIFont systemFontOfSize:14.0 weight:UIFontWeightRegular];
        cell.detailTextLabel.font = [UIFont systemFontOfSize:11.0 weight:UIFontWeightRegular];
        cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
        cell.tintColor = [UIColor colorWithWhite:0.55 alpha:1.0];
    }
    NSArray *titles = @[@"Wallpaper do WhatsApp", @"Ícones do WhatsApp", @"Fonte do WhatsApp", @"Tema e cores", @"Navigation Bar", @"Animações do WhatsApp", @"Gestos e toque", @"Mapa SharedModules"];
    NSArray *details = @[
        dylibtestDesignImage(@"zap-wallpaper.jpg") ? @"Personalizado" : @"Padrão do WhatsApp",
        dylibtestDesignImage(@"zap-icon.jpg") ? @"Personalizado" : @"Padrão do WhatsApp",
        dylibtestFontName(),
        [[NSUserDefaults standardUserDefaults] boolForKey:@"FlexZapDarkMode"] ? @"Escuro" : @"Claro",
        @"Nomes e ícones dos itens",
        isGlobalAnimationEnabled() ? [NSString stringWithFormat:@"Ativa • estilo %ld", (long)getGlobalAnimationStyle()] : @"Desativada",
        isTouchVisualizerEnabled() ? @[@"Anel", @"Ponto", @"Glow"][MIN(dylibtestTouchStyle(), 2)] : @"Desativado",
        @"Wallpaper, fonte, ícones, temas, listas, gestos e chat"
    ];
    cell.textLabel.text = titles[indexPath.row];
    cell.detailTextLabel.text = details[indexPath.row];
    return cell;
}
- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    if (indexPath.row == 0 || indexPath.row == 1) {
        UIImagePickerController *picker = [[UIImagePickerController alloc] init];
        picker.sourceType = UIImagePickerControllerSourceTypePhotoLibrary;
        picker.delegate = self;
        picker.view.tag = indexPath.row;
        [self presentViewController:picker animated:YES completion:nil];
    } else if (indexPath.row == 2) {
        NSArray *fontNames = @[@"System", @"AvenirNext-Regular", @"AvenirNext-Medium", @"HelveticaNeue", @"HelveticaNeue-Bold", @"Futura-Medium", @"Georgia", @"Menlo-Regular", @"Courier", @"MarkerFelt-Wide"];
        UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Fonte do WhatsApp" message:@"Escolha uma fonte instalada no iOS para aplicar à interface do WhatsApp." preferredStyle:UIAlertControllerStyleActionSheet];
        for (NSString *fontName in fontNames) {
            if ([fontName isEqualToString:@"System"] || [UIFont fontWithName:fontName size:14.0]) {
                [alert addAction:[UIAlertAction actionWithTitle:fontName style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
                    dylibtestSetFontName(fontName);
                    dylibtestApplyAppearanceToWindow();
                    [self.tableView reloadData];
                }]];
            }
        }
        [alert addAction:[UIAlertAction actionWithTitle:@"Cancelar" style:UIAlertActionStyleCancel handler:nil]];
        alert.popoverPresentationController.sourceView = self.tableView;
        alert.popoverPresentationController.sourceRect = [self.tableView rectForRowAtIndexPath:indexPath];
        [self presentViewController:alert animated:YES completion:nil];
    } else if (indexPath.row == 3) {
        UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Tema e cores" message:@"Escolha o token visual que deseja editar." preferredStyle:UIAlertControllerStyleActionSheet];
        NSArray *tokens = @[@"accent", @"primaryText", @"secondaryText", @"background", @"incomingBubble", @"outgoingBubble", @"link", @"statusOnline", @"notificationBadge", @"composer"];
        NSDictionary *labels = @{@"accent": @"Destaque", @"primaryText": @"Texto principal", @"secondaryText": @"Texto secundário", @"background": @"Fundo", @"incomingBubble": @"Bolha recebida", @"outgoingBubble": @"Bolha enviada", @"link": @"Links", @"statusOnline": @"Status online", @"notificationBadge": @"Badge de notificação", @"composer": @"Composer"};
        for (NSString *token in tokens) {
            [alert addAction:[UIAlertAction actionWithTitle:labels[token] style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
                if (@available(iOS 14.0, *)) {
                    UIColorPickerViewController *picker = [[UIColorPickerViewController alloc] init];
                    picker.delegate = self;
                    picker.title = token;
                    picker.selectedColor = dylibtestThemeColor(token, [UIColor systemBlueColor]);
                    [self presentViewController:picker animated:YES completion:nil];
                } else {
                    UIColor *fallback = dylibtestThemeColor(token, [UIColor systemBlueColor]);
                    dylibtestSetThemeColor(token, fallback);
                    dylibtestApplyAppearanceToWindow();
                }
            }]];
        }
        [alert addAction:[UIAlertAction actionWithTitle:@"Modo claro/escuro" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
            BOOL dark = [[NSUserDefaults standardUserDefaults] boolForKey:@"FlexZapDarkMode"];
            [[NSUserDefaults standardUserDefaults] setBool:!dark forKey:@"FlexZapDarkMode"];
            [[NSUserDefaults standardUserDefaults] synchronize];
            getCurrentWindow().overrideUserInterfaceStyle = !dark ? UIUserInterfaceStyleDark : UIUserInterfaceStyleLight;
            dylibtestApplyAppearanceToWindow();
            [self.tableView reloadData];
        }]];
        [alert addAction:[UIAlertAction actionWithTitle:@"Cancelar" style:UIAlertActionStyleCancel handler:nil]];
        alert.popoverPresentationController.sourceView = self.tableView;
        alert.popoverPresentationController.sourceRect = [self.tableView rectForRowAtIndexPath:indexPath];
        [self presentViewController:alert animated:YES completion:nil];
    } else if (indexPath.row == 4) {
        NavigationBarCustomizationController *navVC = [[NavigationBarCustomizationController alloc] initWithStyle:UITableViewStylePlain];
        UINavigationController *nav = [[UINavigationController alloc] initWithRootViewController:navVC];
        nav.modalPresentationStyle = UIModalPresentationFormSheet;
        [self presentViewController:nav animated:YES completion:nil];
    } else if (indexPath.row == 5) {
        UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Animações do WhatsApp" message:@"Os estilos originais do Flex são preservados e podem ser aplicados às células visíveis." preferredStyle:UIAlertControllerStyleActionSheet];
        NSArray *styles = @[@"Desativar", @"Deslizar", @"Escala", @"Fade", @"Giro", @"Subir", @"Mola"];
        for (NSInteger i = 0; i < styles.count; i++) {
            [alert addAction:[UIAlertAction actionWithTitle:styles[i] style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) { setGlobalAnimationEnabled(i != 0); if (i > 0) setGlobalAnimationStyle(i - 1); [self.tableView reloadData]; }]];
        }
        [alert addAction:[UIAlertAction actionWithTitle:@"Cancelar" style:UIAlertActionStyleCancel handler:nil]];
        [self presentViewController:alert animated:YES completion:nil];
    } else if (indexPath.row == 6) {
        UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Gestos e toque" message:@"Preserva o visualizador original e altera apenas suas preferências salvas." preferredStyle:UIAlertControllerStyleActionSheet];
        [alert addAction:[UIAlertAction actionWithTitle:isTouchVisualizerEnabled() ? @"Desativar indicador" : @"Ativar indicador" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) { setTouchVisualizerEnabled(!isTouchVisualizerEnabled()); [self.tableView reloadData]; }]];
        NSArray *styles = @[@"Anel", @"Ponto", @"Glow"];
        for (NSInteger i = 0; i < styles.count; i++) [alert addAction:[UIAlertAction actionWithTitle:styles[i] style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) { dylibtestSetTouchStyle(i); [self.tableView reloadData]; }]];
        [alert addAction:[UIAlertAction actionWithTitle:@"Cancelar" style:UIAlertActionStyleCancel handler:nil]];
        [self presentViewController:alert animated:YES completion:nil];
    } else if (indexPath.row == 7) {
        UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Mapa SharedModules" message:@"Categorias disponíveis: tema e cores, wallpaper de conversas, tipografia, Navigation Bar, ícones e imagens, conversas e mensagens, listas, animações, gestos e toque, mídia/status e funções dinâmicas validadas." preferredStyle:UIAlertControllerStyleAlert];
        [alert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
        [self presentViewController:alert animated:YES completion:nil];
    }
}
- (void)imagePickerController:(UIImagePickerController *)picker didFinishPickingMediaWithInfo:(NSDictionary *)info {
    UIImage *image = info[UIImagePickerControllerOriginalImage];
    dylibtestSaveJPEGImage(image, picker.view.tag == 0 ? @"zap-wallpaper.jpg" : @"zap-icon.jpg");
    dylibtestApplyAppearanceToWindow();
    [picker dismissViewControllerAnimated:YES completion:^{ [self.tableView reloadData]; }];
}
- (void)imagePickerControllerDidCancel:(UIImagePickerController *)picker { [picker dismissViewControllerAnimated:YES completion:nil]; }
- (void)colorPickerViewControllerDidSelectColor:(UIColorPickerViewController *)viewController API_AVAILABLE(ios(14.0)) {
    NSString *token = viewController.title;
    if (token.length) {
        dylibtestSetThemeColor(token, viewController.selectedColor);
        dylibtestApplyAppearanceToWindow();
        [self.tableView reloadData];
    }
}
@end

// --- PERFIL DO MENU FLEX ---
@implementation FlexProfileViewController {
    UIImageView *_bannerView;
    UIImageView *_avatarView;
    UIView *_onlineDot;
    UITextField *_nameField;
    UISwitch *_syncSwitch;
}
- (UILabel *)labelWithText:(NSString *)text frame:(CGRect)frame size:(CGFloat)size color:(UIColor *)color weight:(UIFontWeight)weight {
    UILabel *label = [[UILabel alloc] initWithFrame:frame];
    label.text = text;
    label.textColor = color;
    label.font = dylibtestFont(size, weight);
    label.autoresizingMask = UIViewAutoresizingFlexibleWidth;
    return label;
}
- (UIView *)infoCardWithIcon:(NSString *)icon title:(NSString *)title value:(NSString *)value frame:(CGRect)frame {
    UIView *card = [[UIView alloc] initWithFrame:frame];
    card.backgroundColor = [UIColor colorWithWhite:0.075 alpha:1.0];
    card.layer.cornerRadius = 18.0;
    UILabel *iconLabel = [self labelWithText:icon frame:CGRectMake(18, 13, 32, 28) size:18 color:[UIColor colorWithWhite:0.86 alpha:1.0] weight:UIFontWeightRegular];
    iconLabel.textAlignment = NSTextAlignmentCenter;
    iconLabel.backgroundColor = [UIColor colorWithWhite:0.12 alpha:1.0];
    iconLabel.layer.cornerRadius = 16;
    iconLabel.layer.masksToBounds = YES;
    [card addSubview:iconLabel];
    UILabel *titleLabel = [self labelWithText:title.uppercaseString frame:CGRectMake(64, 10, frame.size.width - 120, 20) size:11 color:[UIColor colorWithWhite:0.48 alpha:1.0] weight:UIFontWeightRegular];
    [card addSubview:titleLabel];
    UILabel *valueLabel = [self labelWithText:value frame:CGRectMake(64, 29, frame.size.width - 84, 28) size:16 color:[UIColor colorWithWhite:0.82 alpha:1.0] weight:UIFontWeightRegular];
    valueLabel.lineBreakMode = NSLineBreakByTruncatingTail;
    [card addSubview:valueLabel];
    UILabel *eye = [self labelWithText:@"◉" frame:CGRectMake(frame.size.width - 45, 30, 25, 24) size:15 color:[UIColor colorWithWhite:0.35 alpha:1.0] weight:UIFontWeightRegular];
    eye.textAlignment = NSTextAlignmentCenter;
    [card addSubview:eye];
    return card;
}
- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"Profile";
    self.view.backgroundColor = UIColor.blackColor;
    self.navigationController.navigationBar.tintColor = UIColor.whiteColor;
    self.navigationController.navigationBar.titleTextAttributes = @{NSForegroundColorAttributeName: UIColor.whiteColor, NSFontAttributeName: dylibtestFont(16.0, UIFontWeightMedium)};
    self.navigationItem.leftBarButtonItem = [[UIBarButtonItem alloc] initWithTitle:@"‹  Patches" style:UIBarButtonItemStylePlain target:self action:@selector(closeProfile)];
    self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemSave target:self action:@selector(saveProfile)];

    CGFloat width = MAX(self.view.bounds.size.width, 340.0);
    _bannerView = [[UIImageView alloc] initWithFrame:CGRectMake(0, 0, width, 172)];
    _bannerView.autoresizingMask = UIViewAutoresizingFlexibleWidth;
    UIImage *bannerImage = dylibtestProfileImageNamed(@"banner") ?: dylibtestInstalledResourceImage(@"profile-banner-default.jpg");
    dylibtestApplyAnimatedImageToView(_bannerView, bannerImage);
    _bannerView.contentMode = UIViewContentModeScaleAspectFill;
    _bannerView.clipsToBounds = YES;
    _bannerView.userInteractionEnabled = YES;
    [_bannerView addGestureRecognizer:[[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(selectBanner)]];
    [self.view addSubview:_bannerView];

    _avatarView = [[UIImageView alloc] initWithFrame:CGRectMake(28, 118, 106, 106)];
    UIImage *avatarImage = dylibtestProfileImageNamed(@"avatar") ?: dylibtestInstalledResourceImage(@"profile-avatar-default.jpg");
    dylibtestApplyAnimatedImageToView(_avatarView, avatarImage);
    _avatarView.backgroundColor = [UIColor colorWithWhite:0.12 alpha:1.0];
    _avatarView.contentMode = UIViewContentModeScaleAspectFill;
    _avatarView.layer.cornerRadius = 53;
    _avatarView.layer.borderWidth = 3;
    _avatarView.layer.borderColor = UIColor.blackColor.CGColor;
    _avatarView.clipsToBounds = YES;
    _avatarView.userInteractionEnabled = YES;
    [_avatarView addGestureRecognizer:[[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(selectAvatar)]];
    [self.view addSubview:_avatarView];

    _onlineDot = [[UIView alloc] initWithFrame:CGRectMake(126, 200, 20, 20)];
    _onlineDot.backgroundColor = [UIColor colorWithRed:0.0 green:0.80 blue:0.32 alpha:1.0];
    _onlineDot.layer.cornerRadius = 10;
    _onlineDot.layer.borderWidth = 3;
    _onlineDot.layer.borderColor = UIColor.blackColor.CGColor;
    [self.view addSubview:_onlineDot];

    _nameField = [[UITextField alloc] initWithFrame:CGRectMake(28, 236, width - 56, 48)];
    _nameField.autoresizingMask = UIViewAutoresizingFlexibleWidth;
    _nameField.text = [[NSUserDefaults standardUserDefaults] stringForKey:@"FlexProfileName"] ?: @"Flex User";
    _nameField.textColor = UIColor.whiteColor;
    _nameField.font = dylibtestFont(25.0, UIFontWeightRegular);
    _nameField.placeholder = @"Nome do perfil";
    _nameField.borderStyle = UITextBorderStyleNone;
    _nameField.clearButtonMode = UITextFieldViewModeWhileEditing;
    [self.view addSubview:_nameField];

    UILabel *editHint = [self labelWithText:@"✎" frame:CGRectMake(width - 56, 246, 26, 28) size:15 color:[UIColor colorWithWhite:0.5 alpha:1.0] weight:UIFontWeightRegular];
    editHint.autoresizingMask = UIViewAutoresizingFlexibleLeftMargin;
    [self.view addSubview:editHint];

    CGFloat cardWidth = width - 56;
    UIView *info = [[UIView alloc] initWithFrame:CGRectMake(28, 300, cardWidth, 190)];
    info.autoresizingMask = UIViewAutoresizingFlexibleWidth;
    info.backgroundColor = [UIColor colorWithWhite:0.075 alpha:1.0];
    info.layer.cornerRadius = 18.0;
    [self.view addSubview:info];
    [info addSubview:[self infoCardWithIcon:@"▣" title:@"UDID" value:@"••••••••-••••••••••••••" frame:CGRectMake(0, 0, cardWidth, 63)]];
    [info addSubview:[self infoCardWithIcon:@"▣" title:@"KEY" value:@"••••" frame:CGRectMake(0, 63, cardWidth, 63)]];
    UIView *expiration = [self infoCardWithIcon:@"▦" title:@"EXPIRATION" value:@"25/12/2028" frame:CGRectMake(0, 126, cardWidth, 64)];
    UILabel *active = [self labelWithText:@"Active" frame:CGRectMake(cardWidth - 100, 20, 76, 32) size:13 color:[UIColor colorWithRed:0 green:0.82 blue:0.40 alpha:1] weight:UIFontWeightRegular];
    active.textAlignment = NSTextAlignmentCenter;
    active.layer.cornerRadius = 16;
    active.layer.borderWidth = 1;
    active.layer.borderColor = [UIColor colorWithRed:0 green:0.55 blue:0.28 alpha:1].CGColor;
    active.layer.masksToBounds = YES;
    [expiration addSubview:active];
    [info addSubview:expiration];

    UIView *themeCard = [[UIView alloc] initWithFrame:CGRectMake(28, 510, cardWidth, 116)];
    themeCard.autoresizingMask = UIViewAutoresizingFlexibleWidth;
    themeCard.backgroundColor = [UIColor colorWithWhite:0.075 alpha:1.0];
    themeCard.layer.cornerRadius = 18.0;
    [self.view addSubview:themeCard];
    UILabel *gear = [self labelWithText:@"⚙" frame:CGRectMake(18, 17, 40, 40) size:22 color:[UIColor colorWithWhite:0.85 alpha:1] weight:UIFontWeightRegular];
    gear.textAlignment = NSTextAlignmentCenter;
    gear.backgroundColor = [UIColor colorWithWhite:0.12 alpha:1];
    gear.layer.cornerRadius = 20;
    gear.layer.masksToBounds = YES;
    [themeCard addSubview:gear];
    [themeCard addSubview:[self labelWithText:@"Theme Settings" frame:CGRectMake(72, 13, cardWidth - 120, 28) size:17 color:[UIColor colorWithWhite:0.86 alpha:1] weight:UIFontWeightRegular]];
    [themeCard addSubview:[self labelWithText:@"colors, icons, layout" frame:CGRectMake(72, 40, cardWidth - 120, 22) size:12 color:[UIColor colorWithWhite:0.5 alpha:1] weight:UIFontWeightRegular]];
    UILabel *arrow = [self labelWithText:@"›" frame:CGRectMake(cardWidth - 40, 28, 24, 28) size:25 color:[UIColor colorWithWhite:0.5 alpha:1] weight:UIFontWeightRegular];
    arrow.textAlignment = NSTextAlignmentCenter;
    [themeCard addSubview:arrow];
    UILabel *syncLabel = [self labelWithText:@"Sincronizar avatar com a bolinha" frame:CGRectMake(72, 78, cardWidth - 160, 24) size:11 color:[UIColor colorWithWhite:0.52 alpha:1] weight:UIFontWeightRegular];
    [themeCard addSubview:syncLabel];
    _syncSwitch = [[UISwitch alloc] initWithFrame:CGRectMake(cardWidth - 64, 75, 45, 28)];
    _syncSwitch.transform = CGAffineTransformMakeScale(0.72, 0.72);
    _syncSwitch.onTintColor = [UIColor colorWithRed:0.0 green:0.72 blue:0.34 alpha:1.0];
    _syncSwitch.on = [[NSUserDefaults standardUserDefaults] boolForKey:@"FlexProfileSyncAvatar"];
    [_syncSwitch addTarget:self action:@selector(syncSwitchChanged:) forControlEvents:UIControlEventValueChanged];
    [themeCard addSubview:_syncSwitch];
}
- (void)closeProfile { [self dismissViewControllerAnimated:YES completion:nil]; }
- (void)saveProfile {
    NSString *name = [_nameField.text stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    [[NSUserDefaults standardUserDefaults] setObject:name.length ? name : @"Flex User" forKey:@"FlexProfileName"];
    [[NSUserDefaults standardUserDefaults] synchronize];
    [self closeProfile];
}
- (void)selectBanner { [self presentPickerForTag:1]; }
- (void)selectAvatar { [self presentPickerForTag:2]; }
- (void)syncSwitchChanged:(UISwitch *)sender {
    [[NSUserDefaults standardUserDefaults] setBool:sender.isOn forKey:@"FlexProfileSyncAvatar"];
    [[NSUserDefaults standardUserDefaults] synchronize];
    if (sender.isOn) dylibtestSyncProfileAvatarToFloatingButton();
}

- (void)presentPickerForTag:(NSInteger)tag {
    UIImagePickerController *picker = [[UIImagePickerController alloc] init];
    picker.sourceType = UIImagePickerControllerSourceTypePhotoLibrary;
    picker.delegate = self;
    picker.view.tag = tag;
    [self presentViewController:picker animated:YES completion:nil];
}
- (void)imagePickerController:(UIImagePickerController *)picker didFinishPickingMediaWithInfo:(NSDictionary *)info {
    UIImage *image = info[UIImagePickerControllerOriginalImage];
    if (image) {
        NSString *baseName = picker.view.tag == 1 ? @"banner" : @"avatar";
        dylibtestSaveProfileImage(image, info, baseName);
        if (picker.view.tag == 1) dylibtestApplyAnimatedImageToView(_bannerView, image);
        else {
            dylibtestApplyAnimatedImageToView(_avatarView, image);
            dylibtestSyncProfileAvatarToFloatingButton();
        }
    }
    [picker dismissViewControllerAnimated:YES completion:nil];
}
- (void)imagePickerControllerDidCancel:(UIImagePickerController *)picker { [picker dismissViewControllerAnimated:YES completion:nil]; }
@end

// --- TELA 1: MENU PRINCIPAL ---
@interface DylibtestPanelNavigationController : UINavigationController
@end

@implementation DylibtestPanelNavigationController
- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = [UIColor blackColor];
    self.view.layer.cornerRadius = 18.0;
    self.view.layer.masksToBounds = YES;
}
- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    UIWindow *window = self.view.window;
    CGRect bounds = window ? window.bounds : [UIScreen mainScreen].bounds;
    CGFloat width = MIN(CGRectGetWidth(bounds) * 0.84, 370.0);
    CGFloat height = MIN(CGRectGetHeight(bounds) * 0.82, 760.0);
    self.view.frame = CGRectMake((CGRectGetWidth(bounds) - width) / 2.0,
                                 (CGRectGetHeight(bounds) - height) / 2.0,
                                 width, height);
    self.view.layer.cornerRadius = 18.0;
}
@end

static NSData *flexSanitizeXMLIfNeeded(NSData *data) {
    if (!data.length) return data;
    const uint8_t *bytes = data.bytes;
    BOOL looksXML = data.length > 5 && (bytes[0] == '<' || (bytes[0] == 0xEF && bytes[1] == 0xBB && bytes[2] == 0xBF));
    if (!looksXML) return data;
    NSMutableData *clean = [NSMutableData dataWithCapacity:data.length];
    for (NSUInteger i = 0; i < data.length; i++) {
        uint8_t c = bytes[i];
        BOOL valid = (c == 0x09 || c == 0x0A || c == 0x0D || c >= 0x20);
        if (valid) [clean appendBytes:&c length:1];
    }
    return clean;
}

@implementation ModsMenuController
- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"Patches";
    self.view.backgroundColor = [UIColor blackColor];
    self.tableView.backgroundColor = [UIColor blackColor];
    self.tableView.separatorStyle = UITableViewCellSeparatorStyleNone;
    self.tableView.contentInset = UIEdgeInsetsMake(8.0, 0.0, 8.0, 0.0);
    self.tableView.rowHeight = 68.0;
    self.navigationItem.leftBarButtonItem = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemClose target:self action:@selector(closeTapped)];
    UIBarButtonItem *addBtn = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemAdd target:self action:@selector(addNewPatchPrompt)];
    [self updateNavigationButtonsWithAddButton:addBtn];
    self.navigationController.navigationBar.tintColor = [UIColor colorWithWhite:0.72 alpha:1.0];
    self.navigationController.navigationBar.titleTextAttributes = @{NSForegroundColorAttributeName: [UIColor colorWithWhite:0.88 alpha:1.0], NSFontAttributeName: dylibtestFont(14.0, UIFontWeightMedium)};
}

- (void)openProfile {
    FlexProfileViewController *profile = [[FlexProfileViewController alloc] init];
    UINavigationController *nav = [[UINavigationController alloc] initWithRootViewController:profile];
    nav.modalPresentationStyle = UIModalPresentationPageSheet;
    [self presentViewController:nav animated:YES completion:nil];
}

- (void)handlePatchLongPress:(UILongPressGestureRecognizer *)gesture {
    if (gesture.state == UIGestureRecognizerStateBegan) {
        UITableViewCell *cell = (UITableViewCell *)gesture.view;
        NSIndexPath *indexPath = [self.tableView indexPathForCell:cell];
        if (indexPath && indexPath.row < self.patches.count) {
            NSDictionary *currentPatch = self.patches[indexPath.row];
            
            UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Editar Patch" message:@"Altere o nome e a descrição do patch" preferredStyle:UIAlertControllerStyleAlert];
            
            [alert addTextFieldWithConfigurationHandler:^(UITextField *tf) {
                tf.text = currentPatch[@"name"] ?: @"";
                tf.placeholder = @"Nome do Patch";
            }];
            
            [alert addTextFieldWithConfigurationHandler:^(UITextField *tf) {
                tf.text = currentPatch[@"desc"] ?: @"";
                tf.placeholder = @"Descrição";
            }];
            
            [alert addAction:[UIAlertAction actionWithTitle:@"Salvar" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
                NSMutableDictionary *updatedPatch = [NSMutableDictionary dictionaryWithDictionary:currentPatch];
                updatedPatch[@"name"] = alert.textFields[0].text.length > 0 ? alert.textFields[0].text : @"Untitled";
                updatedPatch[@"desc"] = alert.textFields[1].text.length > 0 ? alert.textFields[1].text : @"";
                
                self.patches[indexPath.row] = updatedPatch;
                savePatches(self.patches);
                [self.tableView reloadRowsAtIndexPaths:@[indexPath] withRowAnimation:UITableViewRowAnimationAutomatic];
            }]];
            
            [alert addAction:[UIAlertAction actionWithTitle:@"Cancelar" style:UIAlertActionStyleCancel handler:nil]];
            
            UIWindow *window = getCurrentWindow();
            UIViewController *topVC = window ? window.rootViewController : nil;
            while (topVC.presentedViewController) topVC = topVC.presentedViewController;
            if (topVC) {
                [topVC presentViewController:alert animated:YES completion:nil];
            }
        }
    }
}

- (void)updateNavigationButtonsWithAddButton:(UIBarButtonItem *)addBtn {
    BOOL isAnimOn = isGlobalAnimationEnabled();
    BOOL isTouchOn = isTouchVisualizerEnabled();
    
    UIAction *opt1 = [UIAction actionWithTitle:@"Ativar Todos Patches" image:[UIImage systemImageNamed:@"checkmark.circle"] identifier:nil handler:^(__kindof UIAction *action) {
        [self toggleAllPatches:YES];
    }];
    
    UIAction *opt2 = [UIAction actionWithTitle:@"Desativar Todos Patches" image:[UIImage systemImageNamed:@"xmark.circle"] identifier:nil handler:^(__kindof UIAction *action) {
        [self toggleAllPatches:NO];
    }];

    UIAction *importPlistOpt = [UIAction actionWithTitle:@"Importar plist ou ZIP..." image:[UIImage systemImageNamed:@"square.and.arrow.down"] identifier:nil handler:^(__kindof UIAction *action) {
        [self presentPatchDocumentPicker];
    }];
    
    UIAction *animToggleOpt = [UIAction actionWithTitle:isAnimOn ? @"Desativar Animação Global" : @"Ativar Animação Global" image:[UIImage systemImageNamed:isAnimOn ? @"sparkles.slash" : @"sparkles"] identifier:nil handler:^(__kindof UIAction *action) {
        setGlobalAnimationEnabled(!isAnimOn);
        [self updateNavigationButtonsWithAddButton:addBtn];
        [self.tableView reloadData];
    }];
    
    UIAction *animStyleOpt = [UIAction actionWithTitle:@"Estilo da Animação..." image:[UIImage systemImageNamed:@"slider.horizontal.3"] identifier:nil handler:^(__kindof UIAction *action) {
        [self showAnimationStylePicker];
    }];
    
    UIAction *animIntensityOpt = [UIAction actionWithTitle:@"Intensidade da Animação..." image:[UIImage systemImageNamed:@"dial.max"] identifier:nil handler:^(__kindof UIAction *action) {
        [self showAnimationIntensityPicker];
    }];
    
    UIAction *touchToggleOpt = [UIAction actionWithTitle:isTouchOn ? @"Desativar Mostrar Toques" : @"Ativar Mostrar Toques" image:[UIImage systemImageNamed:isTouchOn ? @"hand.tap.fill" : @"hand.tap"] identifier:nil handler:^(__kindof UIAction *action) {
        setTouchVisualizerEnabled(!isTouchOn);
        [self updateNavigationButtonsWithAddButton:addBtn];
    }];
    
    UIAction *touchConfigOpt = [UIAction actionWithTitle:@"Configurar Toques na Tela..." image:[UIImage systemImageNamed:@"paintpalette"] identifier:nil handler:^(__kindof UIAction *action) {
        [self showTouchConfigPicker];
    }];
    UIAction *whatsappUIOpt = [UIAction actionWithTitle:@"WhatsApp UI..." image:[UIImage systemImageNamed:@"iphone.gen.3"] identifier:nil handler:^(__kindof UIAction *action) {
        FlexTopicsController *topicsVC = [[FlexTopicsController alloc] initWithStyle:UITableViewStylePlain];
        UINavigationController *designNav = [[UINavigationController alloc] initWithRootViewController:topicsVC];
        designNav.modalPresentationStyle = UIModalPresentationFormSheet;
        [self presentViewController:designNav animated:YES completion:nil];
    }];
    UIMenu *menuOptions = [UIMenu menuWithTitle:@"Opções do Flex" children:@[opt1, opt2, importPlistOpt, whatsappUIOpt, animToggleOpt, animStyleOpt, animIntensityOpt, touchToggleOpt, touchConfigOpt]];
    UIBarButtonItem *threeDotsBtn = [[UIBarButtonItem alloc] initWithImage:[UIImage systemImageNamed:@"ellipsis.circle"] menu:menuOptions];
    UIBarButtonItem *profileBtn = [[UIBarButtonItem alloc] initWithImage:[UIImage systemImageNamed:@"person.crop.circle"] style:UIBarButtonItemStylePlain target:self action:@selector(openProfile)];
    profileBtn.accessibilityLabel = @"Abrir perfil";
    self.navigationItem.rightBarButtonItems = @[addBtn, threeDotsBtn, profileBtn];
}

- (void)tableView:(UITableView *)tableView willDisplayCell:(UITableViewCell *)cell forRowAtIndexPath:(NSIndexPath *)indexPath {
    if (isGlobalAnimationEnabled()) animateCell(cell);
}

- (void)showAnimationStylePicker {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Estilo de Animação" message:@"Escolha o efeito" preferredStyle:UIAlertControllerStyleActionSheet];
    [alert addAction:[UIAlertAction actionWithTitle:@"Deslizar da Direita" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) { setGlobalAnimationStyle(0); [self.tableView reloadData]; }]];
    [alert addAction:[UIAlertAction actionWithTitle:@"Zoom / Escala" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) { setGlobalAnimationStyle(1); [self.tableView reloadData]; }]];
    [alert addAction:[UIAlertAction actionWithTitle:@"Fade" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) { setGlobalAnimationStyle(2); [self.tableView reloadData]; }]];
    [alert addAction:[UIAlertAction actionWithTitle:@"Flip 3D" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) { setGlobalAnimationStyle(3); [self.tableView reloadData]; }]];
    [alert addAction:[UIAlertAction actionWithTitle:@"Fly (Voo)" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) { setGlobalAnimationStyle(4); [self.tableView reloadData]; }]];
    [alert addAction:[UIAlertAction actionWithTitle:@"Spring (Elástico)" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) { setGlobalAnimationStyle(5); [self.tableView reloadData]; }]];
    [alert addAction:[UIAlertAction actionWithTitle:@"Cancelar" style:UIAlertActionStyleCancel handler:nil]];
    
    UIWindow *window = getCurrentWindow();
    UIViewController *topVC = window ? window.rootViewController : nil;
    while (topVC.presentedViewController) topVC = topVC.presentedViewController;
    if (topVC) {
        if (alert.popoverPresentationController) {
            alert.popoverPresentationController.sourceView = topVC.view;
            alert.popoverPresentationController.sourceRect = CGRectMake(topVC.view.bounds.size.width/2, topVC.view.bounds.size.height/2, 1, 1);
        }
        [topVC presentViewController:alert animated:YES completion:nil];
    }
}

- (void)showAnimationIntensityPicker {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Intensidade da Animação" message:@"Ajuste a força" preferredStyle:UIAlertControllerStyleAlert];
    [alert addTextFieldWithConfigurationHandler:^(UITextField *tf) {
        tf.keyboardType = UIKeyboardTypeDecimalPad;
        tf.text = [NSString stringWithFormat:@"%.1f", getAnimationIntensity()];
    }];
    [alert addAction:[UIAlertAction actionWithTitle:@"Salvar" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
        CGFloat val = [alert.textFields.firstObject.text floatValue];
        if (val > 0.0) { setAnimationIntensity(val); [self.tableView reloadData]; }
    }]];
    [alert addAction:[UIAlertAction actionWithTitle:@"Cancelar" style:UIAlertActionStyleCancel handler:nil]];
    
    UIWindow *window = getCurrentWindow();
    UIViewController *topVC = window ? window.rootViewController : nil;
    while (topVC.presentedViewController) topVC = topVC.presentedViewController;
    if (topVC) [topVC presentViewController:alert animated:YES completion:nil];
}

- (void)showTouchConfigPicker {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Personalizar Toques" message:@"Escolha o parâmetro para ajustar" preferredStyle:UIAlertControllerStyleActionSheet];
    
    [alert addAction:[UIAlertAction actionWithTitle:@"Cor Central (Ex: Branco, Azul, Verde...)" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
        [self promptColorSelectionForCenter:YES];
    }]];
    
    [alert addAction:[UIAlertAction actionWithTitle:@"Cor Externa (Anel) (Ex: Vermelho, Amarelo...)" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
        [self promptColorSelectionForCenter:NO];
    }]];
    
    [alert addAction:[UIAlertAction actionWithTitle:@"Tamanho do Toque (Raio)" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
        [self promptSizeSelection];
    }]];
    
    [alert addAction:[UIAlertAction actionWithTitle:@"Espessura do Anel" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
        [self promptLineWidthSelection];
    }]];
    
    [alert addAction:[UIAlertAction actionWithTitle:@"Cancelar" style:UIAlertActionStyleCancel handler:nil]];
    
    UIWindow *window = getCurrentWindow();
    UIViewController *topVC = window ? window.rootViewController : nil;
    while (topVC.presentedViewController) topVC = topVC.presentedViewController;
    if (topVC) {
        if (alert.popoverPresentationController) {
            alert.popoverPresentationController.sourceView = topVC.view;
            alert.popoverPresentationController.sourceRect = CGRectMake(topVC.view.bounds.size.width/2, topVC.view.bounds.size.height/2, 1, 1);
        }
        [topVC presentViewController:alert animated:YES completion:nil];
    }
}

- (void)promptColorSelectionForCenter:(BOOL)isCenter {
    NSString *title = isCenter ? @"Cor Central" : @"Cor Externa";
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:title message:@"Selecione uma cor da paleta abaixo:" preferredStyle:UIAlertControllerStyleActionSheet];
    
    // Lista de cores da paleta visual
    NSDictionary *colorPalette = @{
        @"🔴 Vermelho": [UIColor redColor],
        @"🔵 Azul": [UIColor blueColor],
        @"🟢 Verde": [UIColor greenColor],
        @"🟡 Amarelo": [UIColor yellowColor],
        @"🟠 Laranja": [UIColor orangeColor],
        @"🟣 Roxo": [UIColor purpleColor],
        @"⚪ Branco": [UIColor whiteColor],
        @"⚫ Preto": [UIColor blackColor]
    };
    
    for (NSString *colorName in colorPalette.allKeys) {
        UIColor *selectedColor = colorPalette[colorName];
        [alert addAction:[UIAlertAction actionWithTitle:colorName style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
            if (isCenter) {
                setTouchCenterColor(selectedColor);
            } else {
                setTouchOuterColor(selectedColor);
            }
        }]];
    }
    
    [alert addAction:[UIAlertAction actionWithTitle:@"Cancelar" style:UIAlertActionStyleCancel handler:nil]];
    
    UIWindow *window = getCurrentWindow();
    UIViewController *topVC = window ? window.rootViewController : nil;
    while (topVC.presentedViewController) topVC = topVC.presentedViewController;
    if (topVC) {
        if (alert.popoverPresentationController) {
            alert.popoverPresentationController.sourceView = topVC.view;
            alert.popoverPresentationController.sourceRect = CGRectMake(topVC.view.bounds.size.width/2, topVC.view.bounds.size.height/2, 1, 1);
        }
        [topVC presentViewController:alert animated:YES completion:nil];
    }
}

- (void)promptSizeSelection {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Tamanho do Toque" message:@"Informe o tamanho em pixels (Ex: 44, 60, 80)" preferredStyle:UIAlertControllerStyleAlert];
    [alert addTextFieldWithConfigurationHandler:^(UITextField *tf) {
        tf.keyboardType = UIKeyboardTypeDecimalPad;
        tf.text = [NSString stringWithFormat:@"%.0f", getTouchSize()];
    }];
    [alert addAction:[UIAlertAction actionWithTitle:@"Salvar" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
        CGFloat val = [alert.textFields.firstObject.text floatValue];
        if (val > 10.0) setTouchSize(val);
    }]];
    [alert addAction:[UIAlertAction actionWithTitle:@"Cancelar" style:UIAlertActionStyleCancel handler:nil]];
    
    UIWindow *window = getCurrentWindow();
    UIViewController *topVC = window ? window.rootViewController : nil;
    while (topVC.presentedViewController) topVC = topVC.presentedViewController;
    if (topVC) [topVC presentViewController:alert animated:YES completion:nil];
}

- (void)promptLineWidthSelection {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Espessura do Anel" message:@"Informe a espessura da borda (Ex: 2, 4, 6)" preferredStyle:UIAlertControllerStyleAlert];
    [alert addTextFieldWithConfigurationHandler:^(UITextField *tf) {
        tf.keyboardType = UIKeyboardTypeDecimalPad;
        tf.text = [NSString stringWithFormat:@"%.0f", getTouchLineWidth()];
    }];
    [alert addAction:[UIAlertAction actionWithTitle:@"Salvar" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
        CGFloat val = [alert.textFields.firstObject.text floatValue];
        if (val > 0.0) setTouchLineWidth(val);
    }]];
    [alert addAction:[UIAlertAction actionWithTitle:@"Cancelar" style:UIAlertActionStyleCancel handler:nil]];
    
    UIWindow *window = getCurrentWindow();
    UIViewController *topVC = window ? window.rootViewController : nil;
    while (topVC.presentedViewController) topVC = topVC.presentedViewController;
    if (topVC) [topVC presentViewController:alert animated:YES completion:nil];
}

- (void)presentPatchDocumentPicker {
    UIDocumentPickerViewController *picker = nil;
    if (@available(iOS 14.0, *)) {
        NSArray *types = @[[UTType typeWithIdentifier:@"public.property-list"], [UTType typeWithIdentifier:@"public.json"], [UTType typeWithIdentifier:@"public.zip-archive"], [UTType typeWithIdentifier:@"public.data"]];
        picker = [[UIDocumentPickerViewController alloc] initForOpeningContentTypes:types asCopy:YES];
    } else {
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
        picker = [[UIDocumentPickerViewController alloc] initWithDocumentTypes:@[@"public.property-list", @"public.json", @"public.zip-archive", @"public.data"] inMode:UIDocumentPickerModeImport];
#pragma clang diagnostic pop
    }
    picker.delegate = self;
    picker.allowsMultipleSelection = NO;
    picker.modalPresentationStyle = UIModalPresentationFormSheet;
    [self presentViewController:picker animated:YES completion:nil];
}

- (void)documentPicker:(UIDocumentPickerViewController *)controller didPickDocumentsAtURLs:(NSArray<NSURL *> *)urls {
    NSURL *url = urls.firstObject;
    if (!url) return;
    BOOL accessed = [url startAccessingSecurityScopedResource];
    NSData *rawData = flexImportDataFromURL(url);
    if (accessed) [url stopAccessingSecurityScopedResource];
    rawData = flexSanitizeXMLIfNeeded(rawData);
    NSString *formatError = nil;
    NSArray *rawPatches = flexImportedPatchObjects(rawData, &formatError);
    if (!rawPatches.count) {
        UIAlertController *error = [UIAlertController alertControllerWithTitle:@"Importação não concluída" message:formatError ?: @"Não foi possível ler o plist, JSON ou ZIP selecionado." preferredStyle:UIAlertControllerStyleAlert];
        [error addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
        [self presentViewController:error animated:YES completion:nil];
        return;
    }
    NSMutableArray *patches = loadPatches();
    NSUInteger importedUnits = 0;
    NSUInteger importedPatches = 0;
    for (NSUInteger i = 0; i < rawPatches.count; i++) {
        NSDictionary *normalized = flexNormalizeImportedPatch(rawPatches[i], i, url.lastPathComponent ?: @"arquivo");
        NSArray *units = normalized[@"units"];
        importedUnits += units.count;
        BOOL duplicate = NO;
        for (NSDictionary *existing in patches) {
            if ([existing[@"source"] isEqualToString:normalized[@"source"]] && [existing[@"name"] isEqualToString:normalized[@"name"]]) { duplicate = YES; break; }
        }
        if (!duplicate) { [patches addObject:normalized]; importedPatches++; }
    }
    savePatches(patches);
    self.patches = patches;
    [self.tableView reloadData];
    NSString *message = [NSString stringWithFormat:@"%lu patch(es) e %lu função(ões) importados. Todos os itens foram preservados, inclusive argumentos e textos originais. Eles estão desativados e aguardam validação antes da aplicação.", (unsigned long)importedPatches, (unsigned long)importedUnits];
    UIAlertController *done = [UIAlertController alertControllerWithTitle:@"Importação concluída" message:message preferredStyle:UIAlertControllerStyleAlert];
    [done addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
    [self presentViewController:done animated:YES completion:nil];
}

- (void)toggleAllPatches:(BOOL)enable {
    NSMutableArray *patches = loadPatches();
    for (NSMutableDictionary *patch in patches) patch[@"enabled"] = @(enable);
    savePatches(patches);
    self.patches = patches;
    [self.tableView reloadData];
    applyActivePatches();
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    self.patches = loadPatches();
    [self.tableView reloadData];
}

- (void)closeTapped { [self dismissViewControllerAnimated:YES completion:nil]; }

- (void)addNewPatchPrompt {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"New Patch" message:@"Enter patch name" preferredStyle:UIAlertControllerStyleAlert];
    [alert addTextFieldWithConfigurationHandler:^(UITextField *tf) { tf.placeholder = @"Patch Name"; }];
    [alert addTextFieldWithConfigurationHandler:^(UITextField *tf) { tf.placeholder = @"Description"; }];
    [alert addAction:[UIAlertAction actionWithTitle:@"Create" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
        NSMutableArray *patches = loadPatches();
        [patches addObject:@{
            @"name": alert.textFields[0].text.length > 0 ? alert.textFields[0].text : @"Untitled",
            @"desc": alert.textFields[1].text.length > 0 ? alert.textFields[1].text : @"",
            @"enabled": @NO,
            @"units": @[]
        }];
        savePatches(patches);
        self.patches = patches;
        [self.tableView reloadData];
    }]];
    [alert addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
    
    UIWindow *window = getCurrentWindow();
    UIViewController *topVC = window ? window.rootViewController : nil;
    while (topVC.presentedViewController) topVC = topVC.presentedViewController;
    if (topVC) [topVC presentViewController:alert animated:YES completion:nil];
}

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView { return 1; }
- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section { return self.patches.count; }
- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    static NSString *cellID = @"PatchCell";
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:cellID];
    if (!cell) {
        cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:cellID];
        cell.backgroundColor = [UIColor blackColor];
        cell.contentView.backgroundColor = [UIColor blackColor];
        cell.textLabel.textColor = [UIColor colorWithWhite:0.88 alpha:1.0];
        cell.textLabel.font = dylibtestFont(13.0, UIFontWeightRegular);
        cell.detailTextLabel.textColor = [UIColor colorWithWhite:0.48 alpha:1.0];
        cell.detailTextLabel.font = dylibtestFont(9.0, UIFontWeightRegular);
        cell.imageView.layer.cornerRadius = 18.0;
        cell.imageView.layer.masksToBounds = YES;
        cell.imageView.contentMode = UIViewContentModeScaleAspectFill;
        UIImage *catIcon = dylibtestCatIcon();
        if (catIcon) cell.imageView.image = catIcon;
        UISwitch *sw = [[UISwitch alloc] init];
        sw.transform = CGAffineTransformMakeScale(0.78, 0.78);
        sw.onTintColor = [UIColor colorWithWhite:0.52 alpha:1.0];
        sw.thumbTintColor = [UIColor whiteColor];
        [sw addTarget:self action:@selector(switchChanged:) forControlEvents:UIControlEventValueChanged];
        cell.accessoryView = sw;
        
        // Adiciona o gesto de toque longo na célula para edição
        UILongPressGestureRecognizer *longPress = [[UILongPressGestureRecognizer alloc] initWithTarget:self action:@selector(handlePatchLongPress:)];
        [cell addGestureRecognizer:longPress];
    }
    NSDictionary *patch = self.patches[indexPath.row];
    cell.textLabel.text = patch[@"name"];
    NSArray *unitList = patch[@"units"] ?: @[];
    NSInteger invalidUnits = 0;
    for (NSDictionary *unit in unitList) if ([unit[@"validationStatus"] isEqualToString:@"invalid"]) invalidUnits++;
    NSString *baseDescription = patch[@"desc"] ?: @"";
    cell.detailTextLabel.text = invalidUnits > 0 ? [NSString stringWithFormat:@"%@ • %ld inválida(s)", baseDescription, (long)invalidUnits] : (unitList.count ? [NSString stringWithFormat:@"%@ • Validado", baseDescription] : baseDescription);
    UISwitch *sw = (UISwitch *)cell.accessoryView;
    sw.tag = indexPath.row;
    sw.on = [patch[@"enabled"] boolValue];
    return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    PatchUnitsController *unitsVC = [[PatchUnitsController alloc] initWithStyle:UITableViewStylePlain];
    unitsVC.patchIndex = indexPath.row;
    [self.navigationController pushViewController:unitsVC animated:YES];
}

- (void)switchChanged:(UISwitch *)sender {
    if (sender.tag < self.patches.count) {
        NSMutableDictionary *patch = [NSMutableDictionary dictionaryWithDictionary:self.patches[sender.tag]];
        patch[@"enabled"] = @(sender.isOn);
        self.patches[sender.tag] = patch;
        savePatches(self.patches);
        applyActivePatches();
    }
}

- (void)tableView:(UITableView *)tableView commitEditingStyle:(UITableViewCellEditingStyle)editingStyle forRowAtIndexPath:(NSIndexPath *)indexPath {
    if (editingStyle == UITableViewCellEditingStyleDelete) {
        [self.patches removeObjectAtIndex:indexPath.row];
        savePatches(self.patches);
        applyActivePatches();
        [tableView deleteRowsAtIndexPaths:@[indexPath] withRowAnimation:UITableViewRowAnimationAutomatic];
    }
}
@end

// --- DRAG BOTÃO ---
@interface MenuDragHelper : NSObject
+ (void)handlePan:(UIPanGestureRecognizer *)gesture;
@end

@implementation MenuDragHelper
+ (void)handlePan:(UIPanGestureRecognizer *)gesture {
    UIView *btn = gesture.view;
    UIWindow *window = getCurrentWindow();
    if (!window) return;
    CGPoint translation = [gesture translationInView:window];
    CGPoint newCenter = CGPointMake(btn.center.x + translation.x, btn.center.y + translation.y);
    CGFloat halfW = btn.frame.size.width / 2;
    CGFloat halfH = btn.frame.size.height / 2;
    CGSize winSize = window.bounds.size;
    newCenter.x = MAX(halfW, MIN(winSize.width - halfW, newCenter.x));
    newCenter.y = MAX(halfH + 40, MIN(winSize.height - halfH - 40, newCenter.y));
    btn.center = newCenter;
    [gesture setTranslation:CGPointZero inView:window];
}
@end

// --- INICIALIZAÇÃO ---
__attribute__((constructor))
static void init_dylib(void) {
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(3.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            applyActivePatches();
        });
        
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(4.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            UIWindow *targetWindow = getCurrentWindow();
            if (!targetWindow || [targetWindow viewWithTag:99117]) return;
            if (!targetWindow) return;

            UIButton *menuBtn = [UIButton buttonWithType:UIButtonTypeCustom];
            CGFloat savedY = [[NSUserDefaults standardUserDefaults] doubleForKey:@"dylibtest.menuY"];
            if (savedY < 1.0) savedY = targetWindow.bounds.size.height * 0.45;
            menuBtn.frame = CGRectMake(targetWindow.bounds.size.width - 62.0, savedY, 62.0, 62.0);
            menuBtn.tag = 99117;
            [menuBtn setTitle:@"Fl3x" forState:UIControlStateNormal];
            NSString *assetPath = [[NSBundle bundleForClass:[ModsMenuController class]] pathForResource:@"IMG_0703" ofType:@"jpeg"];
            if (!assetPath) assetPath = @"/var/jb/Library/Application Support/dylibtest/IMG_0703.jpeg";
            if (!assetPath || ![[NSFileManager defaultManager] fileExistsAtPath:assetPath]) assetPath = @"/Library/Application Support/dylibtest/IMG_0703.jpeg";
            UIImage *menuImage = assetPath ? [UIImage imageWithContentsOfFile:assetPath] : nil;
            UIImage *syncedAvatar = ([[NSUserDefaults standardUserDefaults] boolForKey:@"FlexProfileSyncAvatar"]) ? dylibtestProfileImage(@"avatar.jpg") : nil;
            if (syncedAvatar) menuImage = syncedAvatar;
            if (menuImage) { [menuBtn setImage:menuImage forState:UIControlStateNormal]; [menuBtn setTitle:@"" forState:UIControlStateNormal]; menuBtn.imageView.contentMode = UIViewContentModeScaleAspectFill; menuBtn.imageView.clipsToBounds = YES; }
            [menuBtn setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
            menuBtn.titleLabel.font = [UIFont boldSystemFontOfSize:18];
            
            applyLiquidGlassEffect(menuBtn, [UIColor colorWithRed:0.0 green:0.47 blue:1.0 alpha:1.0], 31.0);
            
            menuBtn.layer.shadowColor = [UIColor colorWithRed:0.0 green:0.47 blue:1.0 alpha:0.4].CGColor;
            menuBtn.layer.shadowRadius = 8;
            menuBtn.layer.shadowOpacity = 0.8;
            menuBtn.layer.shadowOffset = CGSizeMake(0, 4);
            
            [menuBtn addTarget:[ModsMenuController class] action:@selector(openModsMenuGated) forControlEvents:UIControlEventTouchUpInside];
            
            UIPanGestureRecognizer *pan = [[UIPanGestureRecognizer alloc] initWithTarget:[MenuDragHelper class] action:@selector(handlePan:)];
            [menuBtn addGestureRecognizer:pan];
            
            [targetWindow addSubview:menuBtn];
            [targetWindow bringSubviewToFront:menuBtn];
            dylibtestApplyAppearanceToWindow();
        });
        [[NSNotificationCenter defaultCenter] addObserverForName:UIApplicationDidBecomeActiveNotification object:nil queue:[NSOperationQueue mainQueue] usingBlock:^(NSNotification *note) {
            dylibtestApplyAppearanceToWindow();
        }];
    });
}

@interface ModsMenuController (MenuExtension)
+ (void)openModsMenu;
+ (void)openModsMenuGated;
@end

@implementation ModsMenuController (MenuExtension)
+ (void)openModsMenuGated { MyGoldGateOpenMenuOrLogin(); }

+ (void)openModsMenu {
    UIWindow *window = getCurrentWindow();
    UIViewController *topController = window ? window.rootViewController : nil;
    while (topController.presentedViewController) topController = topController.presentedViewController;
    if (!topController) return;
    
    ModsMenuController *menuVC = [[ModsMenuController alloc] initWithStyle:UITableViewStylePlain];
        DylibtestPanelNavigationController *nav = [[DylibtestPanelNavigationController alloc] initWithRootViewController:menuVC];
    nav.modalPresentationStyle = UIModalPresentationOverFullScreen;
    nav.view.backgroundColor = [UIColor blackColor];
    nav.view.alpha = 0.97;
    if (@available(iOS 13.0, *)) {
        UINavigationBarAppearance *appearance = [[UINavigationBarAppearance alloc] init];
        [appearance configureWithOpaqueBackground];
        appearance.backgroundColor = [UIColor blackColor];
        appearance.shadowColor = [UIColor clearColor];
        appearance.titleTextAttributes = @{NSForegroundColorAttributeName: [UIColor colorWithWhite:0.88 alpha:1.0], NSFontAttributeName: [UIFont systemFontOfSize:13.0 weight:UIFontWeightMedium]};
        nav.navigationBar.standardAppearance = appearance;
        nav.navigationBar.scrollEdgeAppearance = appearance;
        nav.navigationBar.compactAppearance = appearance;
        nav.navigationBar.tintColor = [UIColor colorWithWhite:0.72 alpha:1.0];
    }
    [topController presentViewController:nav animated:YES completion:nil];
}
@end
