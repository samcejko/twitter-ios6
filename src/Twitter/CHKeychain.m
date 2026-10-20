#import "CHLegacyCollections.h"
#import "CHKeychain.h"
#import "CHCommon.h"
#import <Security/Security.h>

static NSString * const CHKeychainService = @"com.samcejko.Chirpie";

@implementation CHKeychain

+ (NSMutableDictionary *)queryForKey:(NSString *)key
{
    return [@{ (__bridge id)kSecClass: (__bridge id)kSecClassGenericPassword,
               (__bridge id)kSecAttrService: CHKeychainService,
               (__bridge id)kSecAttrAccount: key ?: @"" } mutableCopy];
}

+ (NSString *)stringForKey:(NSString *)key
{
    NSMutableDictionary *q = [self queryForKey:key];
    CHLegacyDictionarySet(q, (__bridge id)kSecReturnData, (__bridge id)kCFBooleanTrue);
    CHLegacyDictionarySet(q, (__bridge id)kSecMatchLimit, (__bridge id)kSecMatchLimitOne);
    CFTypeRef result = NULL;
    if (SecItemCopyMatching((__bridge CFDictionaryRef)q, &result) == errSecSuccess && result) {
        NSData *data = (__bridge_transfer NSData *)result;
        return [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
    }
    NSString *fallback = [[NSUserDefaults standardUserDefaults] stringForKey:[@"kc." stringByAppendingString:key]];
    return fallback;
}

+ (void)setString:(NSString *)value forKey:(NSString *)key
{
    NSMutableDictionary *q = [self queryForKey:key];
    SecItemDelete((__bridge CFDictionaryRef)q);
    if (!value.length) {
        [[NSUserDefaults standardUserDefaults] removeObjectForKey:[@"kc." stringByAppendingString:key]];
        return;
    }
    CHLegacyDictionarySet(q, (__bridge id)kSecValueData, [value dataUsingEncoding:NSUTF8StringEncoding]);
    CHLegacyDictionarySet(q, (__bridge id)kSecAttrAccessible, (__bridge id)kSecAttrAccessibleAfterFirstUnlock);
    OSStatus status = SecItemAdd((__bridge CFDictionaryRef)q, NULL);
    if (status != errSecSuccess) {
        [[NSUserDefaults standardUserDefaults] setObject:value forKey:[@"kc." stringByAppendingString:key]];
        [[NSUserDefaults standardUserDefaults] synchronize];
    }
}

@end
