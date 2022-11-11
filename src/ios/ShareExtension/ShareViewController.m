//
//  ShareViewController.m
//  OpenWith - Share Extension
//

//
// The MIT License (MIT)
//
// Copyright (c) 2017 Jean-Christophe Hoelt
//
// Permission is hereby granted, free of charge, to any person obtaining a copy
// of this software and associated documentation files (the "Software"), to deal
// in the Software without restriction, including without limitation the rights
// to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
// copies of the Software, and to permit persons to whom the Software is
// furnished to do so, subject to the following conditions:
//
// The above copyright notice and this permission notice shall be included in
// all copies or substantial portions of the Software.
//
// THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
// IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
// FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
// AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
// LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
// OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
// THE SOFTWARE.
//

#import <UIKit/UIKit.h>
#import <Social/Social.h>
#import "ShareViewController.h"

@interface ShareViewController : UIViewController {
    int _verbosityLevel;
    NSUserDefaults *_userDefaults;
    NSString *_backURL;
}
@property (nonatomic) int verbosityLevel;
@property (nonatomic,retain) NSUserDefaults *userDefaults;
@property (nonatomic,retain) NSString *backURL;
@property (nonatomic,retain) NSFileManager *fileManager;
@property (nonatomic,retain) NSURL *appGroupCacheDirectory;
@end

/*
 * Constants
 */

#define VERBOSITY_DEBUG  0
#define VERBOSITY_INFO  10
#define VERBOSITY_WARN  20
#define VERBOSITY_ERROR 30

@implementation ShareViewController

@synthesize verbosityLevel = _verbosityLevel;
@synthesize userDefaults = _userDefaults;
@synthesize backURL = _backURL;

- (void) log:(int)level message:(NSString*)message {
    if (level >= self.verbosityLevel) {
        NSLog(@"[ShareViewController.m]%@", message);
    }
}
- (void) debug:(NSString*)message { [self log:VERBOSITY_DEBUG message:message]; }
- (void) info:(NSString*)message { [self log:VERBOSITY_INFO message:message]; }
- (void) warn:(NSString*)message { [self log:VERBOSITY_WARN message:message]; }
- (void) error:(NSString*)message { [self log:VERBOSITY_ERROR message:message]; }

-(void) viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = UIColor.systemBackgroundColor;
    printf("did load");
    [self debug:@"[viewDidLoad]"];
}
- (void) viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    [self debug:@"[viewWillAppear]"];
    [self submit];
}

- (void) setup {
    self.userDefaults = [[NSUserDefaults alloc] initWithSuiteName:SHAREEXT_GROUP_IDENTIFIER];
    self.verbosityLevel = [self.userDefaults integerForKey:@"verbosityLevel"];
    self.fileManager = [NSFileManager defaultManager];
    NSURL* cacheUrl = [_fileManager containerURLForSecurityApplicationGroupIdentifier:SHAREEXT_GROUP_IDENTIFIER];
    self.appGroupCacheDirectory = [cacheUrl URLByAppendingPathComponent:@"Library/Caches/ShareExt" isDirectory:true];
    
    [self removeAppGroupCacheFile];
    [self createAppGroupCacheDirectory];
    
    [self debug:@"[setup]"];
}

- (BOOL) isContentValid {
    return YES;
}

- (void) openURL:(nonnull NSURL *)url {

    SEL selector = NSSelectorFromString(@"openURL:options:completionHandler:");

    UIResponder* responder = self;
    while ((responder = [responder nextResponder]) != nil) {
        NSLog(@"responder = %@", responder);
        if([responder respondsToSelector:selector] == true) {
            NSMethodSignature *methodSignature = [responder methodSignatureForSelector:selector];
            NSInvocation *invocation = [NSInvocation invocationWithMethodSignature:methodSignature];

            // Arguments
            void (^completion)(BOOL success) = ^void(BOOL success) {
                NSLog(@"Completions block: %i", success);
            };
            if (@available(iOS 13.0, *)) {
                UISceneOpenExternalURLOptions * options = [[UISceneOpenExternalURLOptions alloc] init];
                options.universalLinksOnly = false;
                
                [invocation setTarget: responder];
                [invocation setSelector: selector];
                [invocation setArgument: &url atIndex: 2];
                [invocation setArgument: &options atIndex:3];
                [invocation setArgument: &completion atIndex: 4];
                [invocation invoke];
                break;
            } else {
                NSDictionary<NSString *, id> *options = [NSDictionary dictionary];
                
                [invocation setTarget: responder];
                [invocation setSelector: selector];
                [invocation setArgument: &url atIndex: 2];
                [invocation setArgument: &options atIndex:3];
                [invocation setArgument: &completion atIndex: 4];
                [invocation invoke];
                break;
            }
        }
    }
}

- (void) submit {

    [self setup];
    [self debug:@"[submit]"];

    __block long attachmentCount = ((NSExtensionItem*)self.extensionContext.inputItems[0]).attachments.count;
    __block NSMutableArray* shareItems = [NSMutableArray array];
    
    void(^openCordovaAppIfNeed)(void) = ^{
        attachmentCount--;
        if (attachmentCount <= 0) {
            [self.userDefaults setObject:shareItems forKey:@"image"];
            // Emit a URL that opens the cordova app
            NSString *url = [NSString stringWithFormat:@"%@://image", SHAREEXT_URL_SCHEME];
            [self openURL:[NSURL URLWithString:url]];
            
            // Inform the host that we're done, so it un-blocks its UI.
            [self.extensionContext completeRequestReturningItems:@[] completionHandler:nil];
        }
    };
    
    // This is called after the user selects Post. Do the upload of contentText and/or NSExtensionContext attachments.
    NSExtensionItem *inputItem = self.extensionContext.inputItems[0];
    [inputItem.attachments enumerateObjectsUsingBlock:^(NSItemProvider *itemProvider, NSUInteger idx, BOOL *stop) {
        @try {
            void(^textCommpletionHandler)(NSString* item, NSError *error) = ^(NSString* item, NSError *error){
                [self debug:[NSString stringWithFormat:@"textCommpletionHandler text length = %lu", (unsigned long)item.length]];
                if (error) {
                    [self error:error.description];
                    openCordovaAppIfNeed();
                    return;
                }
                NSString *uti = SHAREEXT_UNIFORM_TYPE_IDENTIFIER;
                NSArray<NSString *> *utis = @[];
                if ([itemProvider.registeredTypeIdentifiers count] > 0) {
                    uti = itemProvider.registeredTypeIdentifiers[0];
                    utis = itemProvider.registeredTypeIdentifiers;
                }
                NSDictionary *dict = @{
                    @"backURL": self.backURL,
                    @"data" : [item dataUsingEncoding:NSUTF8StringEncoding],
                    @"text" : item,
                    @"uti": uti,
                    @"utis": utis,
                    @"name": @"",
                };
                [shareItems addObject:dict];
                openCordovaAppIfNeed();
            };
            
            if ([itemProvider hasItemConformingToTypeIdentifier:@"public.url"] &&
                itemProvider.registeredTypeIdentifiers.count == 1) {
                [self debug:[NSString stringWithFormat:@"item provider = %@", itemProvider]];
                [itemProvider loadItemForTypeIdentifier:@"public.url" options:nil completionHandler: ^(NSURL* item, NSError *error) {
                    textCommpletionHandler(item.absoluteString, error);
                }];
            }
            else if ([itemProvider hasItemConformingToTypeIdentifier:@"public.plain-text"]) {
                [self debug:[NSString stringWithFormat:@"item provider = %@", itemProvider]];
                [itemProvider loadItemForTypeIdentifier:@"public.plain-text" options:nil completionHandler: textCommpletionHandler];
            }
            else if ([itemProvider hasItemConformingToTypeIdentifier:@"public.data"]) {
                [self debug:[NSString stringWithFormat:@"item provider = %@", itemProvider]];
                [itemProvider loadFileRepresentationForTypeIdentifier:@"public.data"
                                                    completionHandler:^(NSURL* srcUrl, NSError *loadError) {
                    NSString *suggestedName = srcUrl.lastPathComponent;
                    if ([itemProvider respondsToSelector:NSSelectorFromString(@"getSuggestedName")]) {
                        suggestedName = [itemProvider valueForKey:@"suggestedName"];
                    }
                    
                    NSString *uti = @"public.data";
                    NSArray<NSString *> *utis = @[];
                    if ([itemProvider.registeredTypeIdentifiers count] > 0) {
                        uti = itemProvider.registeredTypeIdentifiers[0];
                        utis = itemProvider.registeredTypeIdentifiers;
                    }
                    
                    NSURL* saveToUrl = [self.appGroupCacheDirectory URLByAppendingPathComponent:[NSString stringWithFormat:@"ShareExt-%ld", idx]];
                    NSError* copyError = nil;
                    [[NSFileManager defaultManager] copyItemAtURL:srcUrl toURL:saveToUrl error:&copyError];
                    if (copyError) {
                        NSLog(@"copy Error: %@", copyError.description);
                        openCordovaAppIfNeed();
                        return;
                    }
                    NSDictionary *dict = @{
                        @"backURL": self.backURL,
                        @"uri": saveToUrl.absoluteString,
                        @"uti": uti,
                        @"utis": utis,
                        @"name": suggestedName
                    };
                    [shareItems addObject:dict];
                    openCordovaAppIfNeed();
                }];
            }
            else {
                // Inform the host that we're done, so it un-blocks its UI.
                openCordovaAppIfNeed();
            }
        }
        @catch(NSException* exception) {
            openCordovaAppIfNeed();
        }
    }];
}

- (NSArray*) configurationItems {
    // To add configuration options via table cells at the bottom of the sheet, return an array of SLComposeSheetConfigurationItem here.
    return @[];
}

- (NSString*) backURLFromBundleID: (NSString*)bundleId {
    if (bundleId == nil) return nil;
    // App Store - com.apple.AppStore
    if ([bundleId isEqualToString:@"com.apple.AppStore"]) return @"itms-apps://";
    // Calculator - com.apple.calculator
    // Calendar - com.apple.mobilecal
    // Camera - com.apple.camera
    // Clock - com.apple.mobiletimer
    // Compass - com.apple.compass
    // Contacts - com.apple.MobileAddressBook
    // FaceTime - com.apple.facetime
    // Find Friends - com.apple.mobileme.fmf1
    // Find iPhone - com.apple.mobileme.fmip1
    // Game Center - com.apple.gamecenter
    // Health - com.apple.Health
    // iBooks - com.apple.iBooks
    // iTunes Store - com.apple.MobileStore
    // Mail - com.apple.mobilemail - message://
    if ([bundleId isEqualToString:@"com.apple.mobilemail"]) return @"message://";
    // Maps - com.apple.Maps - maps://
    if ([bundleId isEqualToString:@"com.apple.Maps"]) return @"maps://";
    // Messages - com.apple.MobileSMS
    // Music - com.apple.Music
    // News - com.apple.news - applenews://
    if ([bundleId isEqualToString:@"com.apple.news"]) return @"applenews://";
    // Notes - com.apple.mobilenotes - mobilenotes://
    if ([bundleId isEqualToString:@"com.apple.mobilenotes"]) return @"mobilenotes://";
    // Phone - com.apple.mobilephone
    // Photos - com.apple.mobileslideshow
    if ([bundleId isEqualToString:@"com.apple.mobileslideshow"]) return @"photos-redirect://";
    // Podcasts - com.apple.podcasts
    // Reminders - com.apple.reminders - x-apple-reminder://
    if ([bundleId isEqualToString:@"com.apple.reminders"]) return @"x-apple-reminder://";
    // Safari - com.apple.mobilesafari
    // Settings - com.apple.Preferences
    // Stocks - com.apple.stocks
    // Tips - com.apple.tips
    // Videos - com.apple.videos - videos://
    if ([bundleId isEqualToString:@"com.apple.videos"]) return @"videos://";
    // Voice Memos - com.apple.VoiceMemos - voicememos://
    if ([bundleId isEqualToString:@"com.apple.VoiceMemos"]) return @"voicememos://";
    // Wallet - com.apple.Passbook
    // Watch - com.apple.Bridge
    // Weather - com.apple.weather
    return @"";
}

// This is called at the point where the Post dialog is about to be shown.
// We use it to store the _hostBundleID
- (void) willMoveToParentViewController: (UIViewController*)parent {
    NSString *hostBundleID = [parent valueForKey:(@"_hostBundleID")];
    self.backURL = [self backURLFromBundleID:hostBundleID];
}

- (void) removeAppGroupCacheFile {
    NSError* error = nil;
    if ([_fileManager fileExistsAtPath:_appGroupCacheDirectory.path]) {
        [_fileManager removeItemAtURL:_appGroupCacheDirectory error:&error];
        if (error) {
            NSLog(@"failed to remove cache directory: %@", error.description);
        }
    }
}

- (void) createAppGroupCacheDirectory {
    NSError* error = nil;
    [_fileManager createDirectoryAtURL:_appGroupCacheDirectory withIntermediateDirectories:true attributes:nil error:&error];
    if (error) {
        NSLog(@"failed to create cache directory: %@", error.description);
    }
}
@end
