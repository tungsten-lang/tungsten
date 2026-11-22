/* runtime/credentials.m — passkeys (WebAuthn) and saved passwords through
 * macOS AuthenticationServices and the Keychain, behind core/credentials.w.
 *
 * A companion unit: linked only when a program's IR references @w_cred_
 * (compiler/lib/driver/link.w, gate `credentials`); runtime.c carries weak
 * stand-ins for every symbol here. AuthenticationServices is not linked: it
 * is dlopen'ed and its classes looked up by name on first use, so a program
 * pays for it only when it makes a credential request. Foundation and
 * Security are linked (Security's kSec* keys are data symbols).
 *
 * Every call takes and returns JSON text (binary fields base64url, unpadded),
 * so the Tungsten side needs no object handles:
 *
 *   w_cred_status()                     JSON: what this process may do (its
 *                                       application identifier, the web
 *                                       browser passkey entitlement, the
 *                                       passkey access state, macOS version)
 *   w_cred_webauthn_begin(json)         start a create/get; returns a ticket
 *   w_cred_list_passkeys(rp_id)         start listing the passkeys saved for
 *                                       an RP (conditional mediation); ticket
 *   w_cred_poll(ticket)                 nil while pending, else result JSON
 *                                       {"ok":true,...} or {"ok":false,
 *                                       "error":"NotAllowedError","message":..}
 *   w_cred_cancel(ticket)               cancel a pending request
 *   w_cred_kc_find(server)              JSON array of saved logins for a host
 *                                       (attributes only: no secret, no prompt)
 *   w_cred_kc_password(server, account) the saved password, or nil (the
 *                                       Keychain may ask the user first)
 *   w_cred_kc_save(server, account, password, label, protocol)
 *                                       "" or an error message
 *   w_cred_kc_delete(server, account)   true when an item was removed
 *   w_cred_strong_password()            a new xxxxxx-xxxxxx-xxxxxx password
 *                                       (Safari's format, SecRandomCopyBytes)
 *
 * Passkey requests use the web-browser forms of the AS API: the RP's origin
 * and challenge go in an ASPublicKeyCredentialClientData and the system
 * builds clientDataJSON (returned as rawClientDataJSON; the caller checks
 * it). Those forms need the restricted entitlement
 * com.apple.developer.web-browser.public-key-credential and an application
 * identifier (a provisioning profile); an ad hoc signed process has neither
 * and every AS request fails with ASAuthorizationErrorFailed ("The calling
 * process does not have an application identifier"). The begin call checks
 * first and answers NotAllowedError with that reason without showing UI.
 *
 * AS objects must be used on the main thread; results are stored under the
 * ticket from whichever queue AS calls back on. Manual retain/release (the
 * runtime builds without ARC). Secrets never leave this file except as the
 * return value of w_cred_kc_password, and are never logged. */

#import <Foundation/Foundation.h>
#import <AuthenticationServices/AuthenticationServices.h>
#import <Security/Security.h>
#include <objc/message.h>
#include <objc/runtime.h>
#include <dlfcn.h>
#include <string.h>

#include "runtime.h"
#include "wvalue.h"

/* ---- values ---- */

static NSString *cred_nsstring(WValue v) {
    if (w_is_rope(v)) v = w_rope_flatten(v);
    if (!w_is_string(v)) return nil;
    char buf[6];
    const char *s = NULL; size_t len = 0;
    w_str_data(v, buf, &s, &len);
    if (!s) return nil;
    return [[[NSString alloc] initWithBytes:s length:len encoding:NSUTF8StringEncoding] autorelease];
}

static int64_t cred_int(WValue v) {
    if (w_is_int(v)) return w_as_int(v);
    if (w_is_double(v)) return (int64_t)w_as_double(v);
    return w_as_int(v);
}

static WValue cred_wstring(NSString *s) {
    if (!s) return W_NIL;
    return w_string([s UTF8String]);
}

static NSString *cred_json(id obj) {
    NSData *d = [NSJSONSerialization dataWithJSONObject:obj options:0 error:NULL];
    if (!d) return @"{\"ok\":false,\"error\":\"UnknownError\",\"message\":\"could not encode the result\"}";
    return [[[NSString alloc] initWithData:d encoding:NSUTF8StringEncoding] autorelease];
}

static NSString *b64url(NSData *d) {
    if (!d) return nil;
    NSString *s = [d base64EncodedStringWithOptions:0];
    s = [s stringByReplacingOccurrencesOfString:@"+" withString:@"-"];
    s = [s stringByReplacingOccurrencesOfString:@"/" withString:@"_"];
    return [s stringByReplacingOccurrencesOfString:@"=" withString:@""];
}

static NSData *unb64url(id v) {
    if (![v isKindOfClass:[NSString class]]) return nil;
    NSMutableString *s = [[(NSString *)v mutableCopy] autorelease];
    [s replaceOccurrencesOfString:@"-" withString:@"+" options:0 range:NSMakeRange(0, [s length])];
    [s replaceOccurrencesOfString:@"_" withString:@"/" options:0 range:NSMakeRange(0, [s length])];
    while ([s length] % 4) [s appendString:@"="];
    return [[[NSData alloc] initWithBase64EncodedString:s options:0] autorelease];
}

static NSString *str_of(NSDictionary *d, NSString *k) {
    id v = [d objectForKey:k];
    return [v isKindOfClass:[NSString class]] ? v : nil;
}

static NSDictionary *err_result(NSString *name, NSString *message) {
    return @{@"ok": @NO, @"error": name ?: @"UnknownError", @"message": message ?: @""};
}

/* ---- AuthenticationServices, loaded on first use ---- */

static void *as_handle(void) {
    static void *h = NULL;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        h = dlopen("/System/Library/Frameworks/AuthenticationServices.framework/AuthenticationServices", RTLD_LAZY);
    });
    return h;
}

static Class as_class(const char *name) {
    if (!as_handle()) return Nil;
    return objc_getClass(name);
}

/* An NSString constant exported by AuthenticationServices, else `dflt`. */
static NSString *as_const(const char *name, NSString *dflt) {
    void *h = as_handle();
    if (!h) return dflt;
    NSString **p = (NSString **)dlsym(h, name);
    return (p && *p) ? *p : dflt;
}

/* ---- entitlements of this process ---- */

typedef struct __SecTask *SecTaskRef_;
extern SecTaskRef_ SecTaskCreateFromSelf(CFAllocatorRef allocator);
extern CFTypeRef SecTaskCopyValueForEntitlement(SecTaskRef_ task, CFStringRef entitlement, CFErrorRef *error);

static id cred_entitlement(NSString *name) {
    SecTaskRef_ t = SecTaskCreateFromSelf(kCFAllocatorDefault);
    if (!t) return nil;
    CFTypeRef v = SecTaskCopyValueForEntitlement(t, (CFStringRef)name, NULL);
    CFRelease(t);
    return v ? [(id)v autorelease] : nil;
}

static NSString *cred_app_identifier(void) {
    id v = cred_entitlement(@"com.apple.application-identifier");
    if (![v isKindOfClass:[NSString class]]) v = cred_entitlement(@"application-identifier");
    return [v isKindOfClass:[NSString class]] ? v : nil;
}

static BOOL cred_browser_entitled(void) {
    id v = cred_entitlement(@"com.apple.developer.web-browser.public-key-credential");
    return [v isKindOfClass:[NSNumber class]] && [v boolValue];
}

/* Items go to the data-protection keychain (the one iCloud Keychain syncs)
 * only when the process has an application identifier: without one,
 * SecItemAdd there fails with errSecMissingEntitlement (-34018), so ad hoc
 * builds use the login keychain. */
static BOOL cred_use_dp_keychain(void) {
    return cred_app_identifier() != nil;
}

/* ---- tickets ---- */

static NSMutableDictionary *cred_results = nil;    /* ticket -> NSString JSON */
static NSMutableDictionary *cred_live = nil;       /* ticket -> controller */
static int64_t cred_next = 1;

static int64_t cred_ticket(void) {
    @synchronized ([NSProcessInfo processInfo]) {
        if (!cred_results) cred_results = [[NSMutableDictionary alloc] init];
        if (!cred_live) cred_live = [[NSMutableDictionary alloc] init];
        return cred_next++;
    }
}

static void cred_finish(int64_t ticket, NSDictionary *result) {
    NSString *json = cred_json(result);
    @synchronized ([NSProcessInfo processInfo]) {
        if ([cred_results objectForKey:@(ticket)] == nil)
            [cred_results setObject:json forKey:@(ticket)];
        [cred_live removeObjectForKey:@(ticket)];
    }
}

static void cred_on_main(void (^blk)(void)) {
    if ([NSThread isMainThread]) blk();
    else dispatch_async(dispatch_get_main_queue(), blk);
}

/* ---- the authorization controller delegate ---- */

@interface TungstenCredDelegate : NSObject <ASAuthorizationControllerDelegate, ASAuthorizationControllerPresentationContextProviding>
@property (nonatomic) int64_t ticket;
@property (nonatomic) BOOL creating;
@end

static id cred_anchor(void) {
    Class app = objc_getClass("NSApplication");
    if (!app) return nil;
    id nsapp = ((id (*)(id, SEL))objc_msgSend)((id)app, sel_registerName("sharedApplication"));
    id w = ((id (*)(id, SEL))objc_msgSend)(nsapp, sel_registerName("keyWindow"));
    if (!w) w = ((id (*)(id, SEL))objc_msgSend)(nsapp, sel_registerName("mainWindow"));
    if (!w) {
        NSArray *ws = ((id (*)(id, SEL))objc_msgSend)(nsapp, sel_registerName("windows"));
        if ([ws count]) w = [ws objectAtIndex:0];
    }
    return w;
}

static NSArray *cred_transports_of(id cred) {
    if ([cred respondsToSelector:@selector(transports)]) {
        NSArray *t = [cred performSelector:@selector(transports)];
        if ([t isKindOfClass:[NSArray class]]) return t;
    }
    return nil;
}

static NSInteger cred_attachment_of(id cred) {
    if ([cred respondsToSelector:@selector(attachment)])
        return ((NSInteger (*)(id, SEL))objc_msgSend)(cred, @selector(attachment));
    return -1;
}

@implementation TungstenCredDelegate

- (ASPresentationAnchor)presentationAnchorForAuthorizationController:(ASAuthorizationController *)controller {
    (void)controller;
    return cred_anchor();
}

- (void)authorizationController:(ASAuthorizationController *)controller didCompleteWithAuthorization:(ASAuthorization *)authorization {
    (void)controller;
    id cred = [authorization performSelector:@selector(credential)];
    NSMutableDictionary *r = [NSMutableDictionary dictionary];
    [r setObject:@YES forKey:@"ok"];
    [r setObject:@"public-key" forKey:@"type"];
    Class platReg = as_class("ASAuthorizationPlatformPublicKeyCredentialRegistration");
    Class platAss = as_class("ASAuthorizationPlatformPublicKeyCredentialAssertion");
    BOOL platform = (platReg && [cred isKindOfClass:platReg]) || (platAss && [cred isKindOfClass:platAss]);
    if (![cred respondsToSelector:@selector(credentialID)] || ![cred respondsToSelector:@selector(rawClientDataJSON)]) {
        cred_finish(self.ticket, err_result(@"NotAllowedError", @"The authenticator returned an unexpected credential"));
        return;
    }
    NSData *cid = [cred performSelector:@selector(credentialID)];
    NSData *cdj = [cred performSelector:@selector(rawClientDataJSON)];
    if (!cid || !cdj) {
        cred_finish(self.ticket, err_result(@"NotAllowedError", @"The authenticator returned an incomplete credential"));
        return;
    }
    [r setObject:b64url(cid) forKey:@"raw_id"];
    [r setObject:b64url(cdj) forKey:@"client_data_json"];
    NSInteger att = cred_attachment_of(cred);
    [r setObject:(att == 1 || (!platform && att < 0)) ? @"cross-platform" : @"platform" forKey:@"authenticator_attachment"];
    if (self.creating) {
        NSData *ao = [cred respondsToSelector:@selector(rawAttestationObject)] ? [cred performSelector:@selector(rawAttestationObject)] : nil;
        if (!ao) {
            cred_finish(self.ticket, err_result(@"NotAllowedError", @"The authenticator returned no attestation object"));
            return;
        }
        [r setObject:b64url(ao) forKey:@"attestation_object"];
        NSArray *t = cred_transports_of(cred);
        if (t) [r setObject:t forKey:@"transports"];
        else if (platform) [r setObject:(att == 1 ? @[@"hybrid"] : @[@"hybrid", @"internal"]) forKey:@"transports"];
    } else {
        if (![cred respondsToSelector:@selector(rawAuthenticatorData)] || ![cred respondsToSelector:@selector(signature)]) {
            cred_finish(self.ticket, err_result(@"NotAllowedError", @"The authenticator returned no assertion"));
            return;
        }
        [r setObject:b64url([cred performSelector:@selector(rawAuthenticatorData)]) forKey:@"authenticator_data"];
        [r setObject:b64url([cred performSelector:@selector(signature)]) forKey:@"signature"];
        NSData *uh = [cred respondsToSelector:@selector(userID)] ? [cred performSelector:@selector(userID)] : nil;
        if (uh && [uh length]) [r setObject:b64url(uh) forKey:@"user_handle"];
    }
    /* extensions */
    if ([cred respondsToSelector:@selector(prf)]) {
        id prf = [cred performSelector:@selector(prf)];
        if (prf) {
            NSMutableDictionary *p = [NSMutableDictionary dictionary];
            if ([prf respondsToSelector:@selector(isSupported)])
                [p setObject:@(((BOOL (*)(id, SEL))objc_msgSend)(prf, @selector(isSupported))) forKey:@"enabled"];
            else
                [p setObject:@YES forKey:@"enabled"];
            NSData *first = [prf performSelector:@selector(first)];
            NSData *second = [prf respondsToSelector:@selector(second)] ? [prf performSelector:@selector(second)] : nil;
            if (first) {
                NSMutableDictionary *res = [NSMutableDictionary dictionaryWithObject:b64url(first) forKey:@"first"];
                if (second) [res setObject:b64url(second) forKey:@"second"];
                [p setObject:res forKey:@"results"];
            }
            [r setObject:p forKey:@"prf"];
        }
    }
    if ([cred respondsToSelector:@selector(largeBlob)]) {
        id lb = [cred performSelector:@selector(largeBlob)];
        if (lb) {
            NSMutableDictionary *l = [NSMutableDictionary dictionary];
            if ([lb respondsToSelector:@selector(isSupported)])
                [l setObject:@(((BOOL (*)(id, SEL))objc_msgSend)(lb, @selector(isSupported))) forKey:@"supported"];
            if ([lb respondsToSelector:@selector(readData)]) {
                NSData *blob = [lb performSelector:@selector(readData)];
                if (blob) [l setObject:b64url(blob) forKey:@"blob"];
            }
            if ([lb respondsToSelector:@selector(didWrite)])
                [l setObject:@(((BOOL (*)(id, SEL))objc_msgSend)(lb, @selector(didWrite))) forKey:@"written"];
            [r setObject:l forKey:@"large_blob"];
        }
    }
    cred_finish(self.ticket, r);
}

- (void)authorizationController:(ASAuthorizationController *)controller didCompleteWithError:(NSError *)error {
    (void)controller;
    NSString *name = @"NotAllowedError";
    NSString *msg = [error localizedFailureReason] ?: [error localizedDescription];
    if ([[error domain] isEqualToString:@"com.apple.AuthenticationServices.AuthorizationError"]) {
        switch ([error code]) {
            case 1001: msg = @"The operation either timed out or was not allowed."; break;  /* canceled */
            case 1006: name = @"InvalidStateError"; msg = @"The authenticator already holds a credential for this account."; break;
            default: break;
        }
    }
    cred_finish(self.ticket, err_result(name, msg));
}

@end

/* ---- building requests ---- */

static id cred_client_data(NSDictionary *q, NSData *challenge) {
    Class cdc = as_class("ASPublicKeyCredentialClientData");
    if (!cdc) return nil;
    id cd = [[cdc alloc] performSelector:@selector(initWithChallenge:origin:) withObject:challenge withObject:str_of(q, @"origin")];
    [cd autorelease];
    NSString *top = str_of(q, @"top_origin");
    if (top && [cd respondsToSelector:@selector(setTopOrigin:)]) [cd performSelector:@selector(setTopOrigin:) withObject:top];
    if ([cd respondsToSelector:@selector(setCrossOrigin:)]) {
        /* NotSet = 0, CrossOrigin = 1, SameOriginWithAncestors = 2 */
        NSInteger co = [[q objectForKey:@"cross_origin"] boolValue] ? 1 : 2;
        ((void (*)(id, SEL, NSInteger))objc_msgSend)(cd, @selector(setCrossOrigin:), co);
    }
    return cd;
}

static NSString *cred_uv_pref(NSDictionary *q) {
    NSString *uv = str_of(q, @"user_verification");
    if ([uv isEqual:@"required"]) return as_const("ASAuthorizationPublicKeyCredentialUserVerificationPreferenceRequired", @"required");
    if ([uv isEqual:@"discouraged"]) return as_const("ASAuthorizationPublicKeyCredentialUserVerificationPreferenceDiscouraged", @"discouraged");
    return as_const("ASAuthorizationPublicKeyCredentialUserVerificationPreferencePreferred", @"preferred");
}

static NSString *cred_attestation_pref(NSDictionary *q) {
    NSString *a = str_of(q, @"attestation");
    if ([a isEqual:@"direct"]) return as_const("ASAuthorizationPublicKeyCredentialAttestationKindDirect", @"direct");
    if ([a isEqual:@"indirect"]) return as_const("ASAuthorizationPublicKeyCredentialAttestationKindIndirect", @"indirect");
    if ([a isEqual:@"enterprise"]) return as_const("ASAuthorizationPublicKeyCredentialAttestationKindEnterprise", @"enterprise");
    return as_const("ASAuthorizationPublicKeyCredentialAttestationKindNone", @"none");
}

static NSString *cred_resident_pref(NSDictionary *q) {
    NSString *rk = str_of(q, @"resident_key");
    if ([rk isEqual:@"required"]) return as_const("ASAuthorizationPublicKeyCredentialResidentKeyPreferenceRequired", @"required");
    if ([rk isEqual:@"preferred"]) return as_const("ASAuthorizationPublicKeyCredentialResidentKeyPreferencePreferred", @"preferred");
    return as_const("ASAuthorizationPublicKeyCredentialResidentKeyPreferenceDiscouraged", @"discouraged");
}

static NSArray *cred_sk_transports(NSArray *names) {
    NSMutableArray *out = [NSMutableArray array];
    for (id n in names) {
        if ([n isEqual:@"usb"]) [out addObject:as_const("ASAuthorizationSecurityKeyPublicKeyCredentialDescriptorTransportUSB", @"usb")];
        else if ([n isEqual:@"nfc"]) [out addObject:as_const("ASAuthorizationSecurityKeyPublicKeyCredentialDescriptorTransportNFC", @"nfc")];
        else if ([n isEqual:@"ble"]) [out addObject:as_const("ASAuthorizationSecurityKeyPublicKeyCredentialDescriptorTransportBluetooth", @"ble")];
    }
    if ([out count] == 0) {
        NSArray *(*all)(void) = (NSArray *(*)(void))dlsym(as_handle(), "ASAuthorizationAllSupportedPublicKeyCredentialDescriptorTransports");
        if (all) return all();
    }
    return out;
}

/* descriptors from [{"id": b64url, "transports": [...]}] */
static NSArray *cred_descriptors(NSArray *list, BOOL security_key) {
    NSMutableArray *out = [NSMutableArray array];
    Class pd = as_class("ASAuthorizationPlatformPublicKeyCredentialDescriptor");
    Class sd = as_class("ASAuthorizationSecurityKeyPublicKeyCredentialDescriptor");
    for (id e in ([list isKindOfClass:[NSArray class]] ? list : @[])) {
        if (![e isKindOfClass:[NSDictionary class]]) continue;
        NSData *cid = unb64url([e objectForKey:@"id"]);
        if (!cid) continue;
        id d = nil;
        if (security_key && sd) {
            NSArray *t = [[e objectForKey:@"transports"] isKindOfClass:[NSArray class]] ? [e objectForKey:@"transports"] : @[];
            d = [[sd alloc] performSelector:@selector(initWithCredentialID:transports:) withObject:cid withObject:cred_sk_transports(t)];
        } else if (!security_key && pd) {
            d = [[pd alloc] performSelector:@selector(initWithCredentialID:) withObject:cid];
        }
        if (d) { [out addObject:d]; [d release]; }
    }
    return out;
}

static id cred_prf_values(NSDictionary *eval) {
    Class vc = as_class("ASAuthorizationPublicKeyCredentialPRFAssertionInputValues");
    if (!vc || ![eval isKindOfClass:[NSDictionary class]]) return nil;
    NSData *first = unb64url([eval objectForKey:@"first"]);
    if (!first) return nil;
    NSData *second = unb64url([eval objectForKey:@"second"]);
    return [[[vc alloc] performSelector:@selector(initWithSaltInput1:saltInput2:) withObject:first withObject:second] autorelease];
}

static void cred_set(id obj, SEL sel, id value) {
    if (value && [obj respondsToSelector:sel]) [obj performSelector:sel withObject:value];
}

static void cred_set_bool(id obj, SEL sel, BOOL value) {
    if ([obj respondsToSelector:sel]) ((void (*)(id, SEL, BOOL))objc_msgSend)(obj, sel, value);
}

/* The requests for one create/get: platform (Passwords, iCloud Keychain and
 * third-party credential providers such as 1Password, plus a phone over
 * hybrid) unless the RP asked for cross-platform only, and security keys
 * unless it asked for platform only. */
static NSArray *cred_requests(NSDictionary *q, NSString **why) {
    BOOL creating = [str_of(q, @"op") isEqual:@"create"];
    NSString *rp = str_of(q, @"rp_id");
    NSData *challenge = unb64url([q objectForKey:@"challenge"]);
    if (!rp || !challenge || !str_of(q, @"origin")) { *why = @"missing rpId, origin or challenge"; return nil; }
    NSString *attach = str_of(q, @"authenticator_attachment");
    BOOL want_platform = ![attach isEqual:@"cross-platform"];
    BOOL want_sk = ![attach isEqual:@"platform"] && ![[q objectForKey:@"conditional"] boolValue];
    Class pp = as_class("ASAuthorizationPlatformPublicKeyCredentialProvider");
    Class sp = as_class("ASAuthorizationSecurityKeyPublicKeyCredentialProvider");
    if (!pp || !as_class("ASPublicKeyCredentialClientData")) { *why = @"AuthenticationServices has no web browser passkey API on this macOS"; return nil; }
    NSMutableArray *reqs = [NSMutableArray array];
    NSDictionary *ext = [[q objectForKey:@"extensions"] isKindOfClass:[NSDictionary class]] ? [q objectForKey:@"extensions"] : @{};
    if (creating) {
        NSDictionary *user = [q objectForKey:@"user"];
        NSData *uid = unb64url([user objectForKey:@"id"]);
        NSString *name = str_of(user, @"name") ?: @"";
        NSString *display = str_of(user, @"display_name");
        if (!uid) { *why = @"missing user.id"; return nil; }
        if (want_platform) {
            id prov = [[[pp alloc] performSelector:@selector(initWithRelyingPartyIdentifier:) withObject:rp] autorelease];
            id cd = cred_client_data(q, challenge);
            id req = nil;
            if ([[q objectForKey:@"conditional"] boolValue] && [prov respondsToSelector:@selector(createCredentialRegistrationRequestWithClientData:name:userID:requestStyle:)])
                req = ((id (*)(id, SEL, id, id, id, NSInteger))objc_msgSend)(prov, @selector(createCredentialRegistrationRequestWithClientData:name:userID:requestStyle:), cd, name, uid, 1);
            else
                req = ((id (*)(id, SEL, id, id, id))objc_msgSend)(prov, @selector(createCredentialRegistrationRequestWithClientData:name:userID:), cd, name, uid);
            if (req) {
                cred_set(req, @selector(setDisplayName:), display);
                cred_set(req, @selector(setUserVerificationPreference:), cred_uv_pref(q));
                cred_set(req, @selector(setAttestationPreference:), cred_attestation_pref(q));
                cred_set(req, @selector(setExcludedCredentials:), cred_descriptors([q objectForKey:@"exclude_credentials"], NO));
                cred_set_bool(req, @selector(setShouldShowHybridTransport:), YES);
                NSDictionary *prf = [ext objectForKey:@"prf"];
                Class pri = as_class("ASAuthorizationPublicKeyCredentialPRFRegistrationInput");
                if ([prf isKindOfClass:[NSDictionary class]] && pri && [req respondsToSelector:@selector(setPrf:)]) {
                    id vals = cred_prf_values([prf objectForKey:@"eval"]);
                    id in = vals ? [[[pri alloc] performSelector:@selector(initWithInputValues:) withObject:vals] autorelease]
                                 : [pri performSelector:@selector(checkForSupport)];
                    [req performSelector:@selector(setPrf:) withObject:in];
                }
                NSDictionary *lb = [ext objectForKey:@"large_blob"];
                Class lbi = as_class("ASAuthorizationPublicKeyCredentialLargeBlobRegistrationInput");
                if ([lb isKindOfClass:[NSDictionary class]] && lbi && [req respondsToSelector:@selector(setLargeBlob:)]) {
                    /* Required = 1, Preferred = 2 */
                    NSInteger support = [str_of(lb, @"support") isEqual:@"required"] ? 1 : 2;
                    id in = ((id (*)(id, SEL, NSInteger))objc_msgSend)([lbi alloc], @selector(initWithSupportRequirement:), support);
                    [req performSelector:@selector(setLargeBlob:) withObject:in];
                    [in release];
                }
                [reqs addObject:req];
            }
        }
        if (want_sk && sp && display != nil) {
            id prov = [[[sp alloc] performSelector:@selector(initWithRelyingPartyIdentifier:) withObject:rp] autorelease];
            id cd = cred_client_data(q, challenge);
            id req = ((id (*)(id, SEL, id, id, id, id))objc_msgSend)(prov, @selector(createCredentialRegistrationRequestWithClientData:displayName:name:userID:), cd, display, name, uid);
            if (req) {
                NSMutableArray *params = [NSMutableArray array];
                Class pc = objc_getClass("ASAuthorizationPublicKeyCredentialParameters");
                for (id a in ([[q objectForKey:@"algorithms"] isKindOfClass:[NSArray class]] ? [q objectForKey:@"algorithms"] : @[@(-7)])) {
                    id p = ((id (*)(id, SEL, NSInteger))objc_msgSend)([pc alloc], @selector(initWithAlgorithm:), [a integerValue]);
                    if (p) { [params addObject:p]; [p release]; }
                }
                cred_set(req, @selector(setCredentialParameters:), params);
                cred_set(req, @selector(setUserVerificationPreference:), cred_uv_pref(q));
                cred_set(req, @selector(setAttestationPreference:), cred_attestation_pref(q));
                cred_set(req, @selector(setResidentKeyPreference:), cred_resident_pref(q));
                cred_set(req, @selector(setExcludedCredentials:), cred_descriptors([q objectForKey:@"exclude_credentials"], YES));
                [reqs addObject:req];
            }
        }
    } else {
        NSArray *allow = [q objectForKey:@"allow_credentials"];
        if (want_platform) {
            id prov = [[[pp alloc] performSelector:@selector(initWithRelyingPartyIdentifier:) withObject:rp] autorelease];
            id req = [prov performSelector:@selector(createCredentialAssertionRequestWithClientData:) withObject:cred_client_data(q, challenge)];
            if (req) {
                cred_set(req, @selector(setAllowedCredentials:), cred_descriptors(allow, NO));
                cred_set(req, @selector(setUserVerificationPreference:), cred_uv_pref(q));
                cred_set_bool(req, @selector(setShouldShowHybridTransport:), ![[q objectForKey:@"conditional"] boolValue]);
                NSDictionary *prf = [ext objectForKey:@"prf"];
                Class pai = as_class("ASAuthorizationPublicKeyCredentialPRFAssertionInput");
                if ([prf isKindOfClass:[NSDictionary class]] && pai && [req respondsToSelector:@selector(setPrf:)]) {
                    id vals = cred_prf_values([prf objectForKey:@"eval"]);
                    NSMutableDictionary *per = nil;
                    NSDictionary *byc = [prf objectForKey:@"eval_by_credential"];
                    if ([byc isKindOfClass:[NSDictionary class]]) {
                        per = [NSMutableDictionary dictionary];
                        for (NSString *k in byc) {
                            NSData *cid = unb64url(k);
                            id v = cred_prf_values([byc objectForKey:k]);
                            if (cid && v) [per setObject:v forKey:cid];
                        }
                    }
                    if (vals || [per count]) {
                        id in = [[[pai alloc] performSelector:@selector(initWithInputValues:perCredentialInputValues:) withObject:vals withObject:per] autorelease];
                        [req performSelector:@selector(setPrf:) withObject:in];
                    }
                }
                NSDictionary *lb = [ext objectForKey:@"large_blob"];
                Class lba = as_class("ASAuthorizationPublicKeyCredentialLargeBlobAssertionInput");
                if ([lb isKindOfClass:[NSDictionary class]] && lba && [req respondsToSelector:@selector(setLargeBlob:)]) {
                    NSData *write = unb64url([lb objectForKey:@"write"]);
                    /* Read = 0, Write = 1 */
                    id in = ((id (*)(id, SEL, NSInteger))objc_msgSend)([lba alloc], @selector(initWithOperation:), write ? 1 : 0);
                    if (write && [in respondsToSelector:@selector(setDataToWrite:)]) [in performSelector:@selector(setDataToWrite:) withObject:write];
                    [req performSelector:@selector(setLargeBlob:) withObject:in];
                    [in release];
                }
                [reqs addObject:req];
            }
        }
        if (want_sk && sp) {
            id prov = [[[sp alloc] performSelector:@selector(initWithRelyingPartyIdentifier:) withObject:rp] autorelease];
            id req = [prov performSelector:@selector(createCredentialAssertionRequestWithClientData:) withObject:cred_client_data(q, challenge)];
            if (req) {
                cred_set(req, @selector(setAllowedCredentials:), cred_descriptors(allow, YES));
                cred_set(req, @selector(setUserVerificationPreference:), cred_uv_pref(q));
                cred_set(req, @selector(setAppID:), str_of(ext, @"appid"));
                [reqs addObject:req];
            }
        }
    }
    if ([reqs count] == 0) { *why = @"no authenticator can satisfy these options"; return nil; }
    return reqs;
}

/* ---- the entry points ---- */

static NSString *cred_auth_state_name(NSInteger s) {
    switch (s) { case 0: return @"authorized"; case 1: return @"denied"; default: return @"not_determined"; }
}

WValue w_cred_status(void) {
    @autoreleasepool {
        NSMutableDictionary *r = [NSMutableDictionary dictionary];
        NSString *appid = cred_app_identifier();
        [r setObject:(appid ?: (id)[NSNull null]) forKey:@"application_identifier"];
        [r setObject:@(cred_browser_entitled()) forKey:@"web_browser_entitlement"];
        id groups = cred_entitlement(@"keychain-access-groups");
        [r setObject:@([groups isKindOfClass:[NSArray class]] && [groups count] > 0) forKey:@"keychain_access_groups"];
        [r setObject:@(cred_use_dp_keychain()) forKey:@"data_protection_keychain"];
        NSOperatingSystemVersion v = [[NSProcessInfo processInfo] operatingSystemVersion];
        [r setObject:[NSString stringWithFormat:@"%ld.%ld.%ld", (long)v.majorVersion, (long)v.minorVersion, (long)v.patchVersion] forKey:@"macos"];
        [r setObject:[[NSBundle mainBundle] bundleIdentifier] ?: (id)[NSNull null] forKey:@"bundle_identifier"];
        Class mgr = as_class("ASAuthorizationWebBrowserPublicKeyCredentialManager");
        [r setObject:@(as_class("ASPublicKeyCredentialClientData") != Nil) forKey:@"browser_api"];
        if (mgr) {
            id m = [[mgr alloc] init];
            NSInteger s = ((NSInteger (*)(id, SEL))objc_msgSend)(m, @selector(authorizationStateForPlatformCredentials));
            [r setObject:cred_auth_state_name(s) forKey:@"passkey_access"];
            [m release];
            if ([(id)mgr respondsToSelector:@selector(isDeviceConfiguredForPasskeys)])
                [r setObject:@(((BOOL (*)(id, SEL))objc_msgSend)((id)mgr, @selector(isDeviceConfiguredForPasskeys))) forKey:@"device_configured_for_passkeys"];
        }
        /* What a request needs and this process lacks, or "" */
        NSString *missing = @"";
        if (!appid) missing = @"an application identifier (Blade must be signed with a Team ID and a provisioning profile)";
        else if (!cred_browser_entitled()) missing = @"the com.apple.developer.web-browser.public-key-credential entitlement";
        [r setObject:missing forKey:@"passkeys_unavailable_because"];
        return cred_wstring(cred_json(r));
    }
}

WValue w_cred_webauthn_begin(WValue json_v) {
    int64_t ticket = cred_ticket();
    @autoreleasepool {
        NSString *json = cred_nsstring(json_v);
        NSDictionary *q = json ? [NSJSONSerialization JSONObjectWithData:[json dataUsingEncoding:NSUTF8StringEncoding] options:0 error:NULL] : nil;
        if (![q isKindOfClass:[NSDictionary class]]) {
            cred_finish(ticket, err_result(@"TypeError", @"malformed request"));
            return w_int(ticket);
        }
        if (!cred_app_identifier() || !cred_browser_entitled()) {
            cred_finish(ticket, err_result(@"NotAllowedError", cred_app_identifier()
                ? @"Passkeys are unavailable: this build of the browser lacks the com.apple.developer.web-browser.public-key-credential entitlement."
                : @"Passkeys are unavailable: this build of the browser is not signed with an application identifier (ad hoc signature)."));
            return w_int(ticket);
        }
        [q retain];
        cred_on_main(^{
            @autoreleasepool {
                NSString *why = nil;
                NSArray *reqs = cred_requests(q, &why);
                BOOL creating = [str_of(q, @"op") isEqual:@"create"];
                BOOL immediate = [[q objectForKey:@"immediate"] boolValue] || [[q objectForKey:@"conditional"] boolValue];
                [q release];
                if (!reqs) { cred_finish(ticket, err_result(@"NotSupportedError", why)); return; }
                Class cc = as_class("ASAuthorizationController");
                id c = [[cc alloc] performSelector:@selector(initWithAuthorizationRequests:) withObject:reqs];
                TungstenCredDelegate *d = [[TungstenCredDelegate alloc] init];
                d.ticket = ticket;
                d.creating = creating;
                [c performSelector:@selector(setDelegate:) withObject:d];
                [c performSelector:@selector(setPresentationContextProvider:) withObject:d];
                /* delegate and context provider are weak: the live table keeps both */
                @synchronized ([NSProcessInfo processInfo]) {
                    [cred_live setObject:@[c, d] forKey:@(ticket)];
                }
                if ([c respondsToSelector:@selector(performRequestsWithOptions:)])
                    ((void (*)(id, SEL, NSUInteger))objc_msgSend)(c, @selector(performRequestsWithOptions:), immediate ? 1 : 0);
                else
                    [c performSelector:@selector(performRequests)];
                [c release];
                [d release];
            }
        });
    }
    return w_int(ticket);
}

WValue w_cred_list_passkeys(WValue rp_v) {
    int64_t ticket = cred_ticket();
    @autoreleasepool {
        NSString *rp = [[cred_nsstring(rp_v) copy] autorelease];
        Class mgr = as_class("ASAuthorizationWebBrowserPublicKeyCredentialManager");
        if (!rp || !mgr || !cred_browser_entitled()) {
            cred_finish(ticket, @{@"ok": @YES, @"credentials": @[], @"reason": mgr ? @"not entitled" : @"unsupported"});
            return w_int(ticket);
        }
        [rp retain];
        cred_on_main(^{
            id m = [[mgr alloc] init];
            void (^list)(void) = ^{
                ((void (*)(id, SEL, id, id))objc_msgSend)(m, @selector(platformCredentialsForRelyingParty:completionHandler:), rp, ^(NSArray *creds) {
                    NSMutableArray *out = [NSMutableArray array];
                    for (id c in creds) {
                        NSMutableDictionary *e = [NSMutableDictionary dictionary];
                        [e setObject:[c performSelector:@selector(name)] ?: @"" forKey:@"name"];
                        if ([c respondsToSelector:@selector(customTitle)] && [c performSelector:@selector(customTitle)])
                            [e setObject:[c performSelector:@selector(customTitle)] forKey:@"custom_title"];
                        [e setObject:[c performSelector:@selector(relyingParty)] ?: @"" forKey:@"rp_id"];
                        [e setObject:b64url([c performSelector:@selector(credentialID)]) ?: @"" forKey:@"id"];
                        [e setObject:b64url([c performSelector:@selector(userHandle)]) ?: @"" forKey:@"user_handle"];
                        if ([c respondsToSelector:@selector(providerName)] && [c performSelector:@selector(providerName)])
                            [e setObject:[c performSelector:@selector(providerName)] forKey:@"provider"];
                        [out addObject:e];
                    }
                    cred_finish(ticket, @{@"ok": @YES, @"credentials": out});
                });
            };
            NSInteger s = ((NSInteger (*)(id, SEL))objc_msgSend)(m, @selector(authorizationStateForPlatformCredentials));
            if (s == 0) list();
            else if (s == 1) cred_finish(ticket, @{@"ok": @YES, @"credentials": @[], @"reason": @"denied"});
            else {
                /* asks the user once: "Allow <app> to use passkeys?" */
                ((void (*)(id, SEL, id))objc_msgSend)(m, @selector(requestAuthorizationForPublicKeyCredentials:), ^(NSInteger st) {
                    if (st == 0) list();
                    else cred_finish(ticket, @{@"ok": @YES, @"credentials": @[], @"reason": cred_auth_state_name(st)});
                });
            }
            /* m is not released: the manager must outlive its completion
             * handlers, and it is one small object per listing */
            [rp release];
        });
    }
    return w_int(ticket);
}

WValue w_cred_poll(WValue ticket_v) {
    NSString *r = nil;
    @synchronized ([NSProcessInfo processInfo]) {
        r = [[[cred_results objectForKey:@(cred_int(ticket_v))] retain] autorelease];
        if (r) [cred_results removeObjectForKey:@(cred_int(ticket_v))];
    }
    return r ? cred_wstring(r) : W_NIL;
}

WValue w_cred_cancel(WValue ticket_v) {
    int64_t ticket = cred_int(ticket_v);
    id pair = nil;
    @synchronized ([NSProcessInfo processInfo]) {
        pair = [[[cred_live objectForKey:@(ticket)] retain] autorelease];
    }
    if (pair) {
        [pair retain];
        cred_on_main(^{
            id c = [pair objectAtIndex:0];
            if ([c respondsToSelector:@selector(cancel)]) [c performSelector:@selector(cancel)];
            [pair release];
        });
    }
    cred_finish(ticket, err_result(@"AbortError", @"The operation was aborted."));
    return W_NIL;
}

/* ---- the Keychain: internet passwords, as browsers save them ---- */

static NSMutableDictionary *kc_query(NSString *server, NSString *account) {
    NSMutableDictionary *q = [NSMutableDictionary dictionary];
    [q setObject:(id)kSecClassInternetPassword forKey:(id)kSecClass];
    [q setObject:server forKey:(id)kSecAttrServer];
    if (account) [q setObject:account forKey:(id)kSecAttrAccount];
    if (cred_use_dp_keychain()) {
        [q setObject:@YES forKey:(id)kSecUseDataProtectionKeychain];
        [q setObject:(id)kSecAttrSynchronizableAny forKey:(id)kSecAttrSynchronizable];
    }
    return q;
}

static id kc_date(id d) {
    if (![d isKindOfClass:[NSDate class]]) return [NSNull null];
    return @((int64_t)[(NSDate *)d timeIntervalSince1970]);
}

WValue w_cred_kc_find(WValue server_v) {
    @autoreleasepool {
        NSString *server = cred_nsstring(server_v);
        if (![server length]) return cred_wstring(@"[]");
        NSMutableDictionary *q = kc_query(server, nil);
        [q setObject:(id)kSecMatchLimitAll forKey:(id)kSecMatchLimit];
        [q setObject:@YES forKey:(id)kSecReturnAttributes];
        CFTypeRef out = NULL;
        OSStatus s = SecItemCopyMatching((CFDictionaryRef)q, &out);
        NSMutableArray *list = [NSMutableArray array];
        if (s == errSecSuccess && out) {
            NSArray *items = [(id)out isKindOfClass:[NSArray class]] ? (NSArray *)out : @[(id)out];
            for (NSDictionary *it in items) {
                NSString *acct = [it objectForKey:(id)kSecAttrAccount];
                if (![acct isKindOfClass:[NSString class]]) continue;
                NSMutableDictionary *e = [NSMutableDictionary dictionary];
                [e setObject:acct forKey:@"account"];
                [e setObject:[it objectForKey:(id)kSecAttrServer] ?: server forKey:@"server"];
                id label = [it objectForKey:(id)kSecAttrLabel];
                if ([label isKindOfClass:[NSString class]]) [e setObject:label forKey:@"label"];
                id path = [it objectForKey:(id)kSecAttrPath];
                if ([path isKindOfClass:[NSString class]]) [e setObject:path forKey:@"path"];
                id port = [it objectForKey:(id)kSecAttrPort];
                if ([port isKindOfClass:[NSNumber class]]) [e setObject:port forKey:@"port"];
                [e setObject:kc_date([it objectForKey:(id)kSecAttrCreationDate]) forKey:@"created"];
                [e setObject:kc_date([it objectForKey:(id)kSecAttrModificationDate]) forKey:@"modified"];
                [list addObject:e];
            }
        }
        if (out) CFRelease(out);
        return cred_wstring(cred_json(list));
    }
}

WValue w_cred_kc_password(WValue server_v, WValue account_v) {
    @autoreleasepool {
        NSString *server = cred_nsstring(server_v), *account = cred_nsstring(account_v);
        if (![server length] || !account) return W_NIL;
        NSMutableDictionary *q = kc_query(server, account);
        [q setObject:(id)kSecMatchLimitOne forKey:(id)kSecMatchLimit];
        [q setObject:@YES forKey:(id)kSecReturnData];
        CFTypeRef out = NULL;
        OSStatus s = SecItemCopyMatching((CFDictionaryRef)q, &out);
        WValue r = W_NIL;
        if (s == errSecSuccess && out && CFGetTypeID(out) == CFDataGetTypeID()) {
            NSString *pw = [[[NSString alloc] initWithData:(NSData *)out encoding:NSUTF8StringEncoding] autorelease];
            if (pw) r = cred_wstring(pw);
        }
        if (out) CFRelease(out);
        return r;
    }
}

WValue w_cred_kc_save(WValue server_v, WValue account_v, WValue password_v, WValue label_v, WValue protocol_v) {
    @autoreleasepool {
        NSString *server = cred_nsstring(server_v), *account = cred_nsstring(account_v);
        NSString *password = cred_nsstring(password_v), *label = cred_nsstring(label_v);
        NSString *proto = cred_nsstring(protocol_v);
        if (![server length] || !account || !password) return cred_wstring(@"missing server, account or password");
        NSData *secret = [password dataUsingEncoding:NSUTF8StringEncoding];
        NSMutableDictionary *q = kc_query(server, account);
        [q setObject:([proto isEqual:@"http"] ? (id)kSecAttrProtocolHTTP : (id)kSecAttrProtocolHTTPS) forKey:(id)kSecAttrProtocol];
        NSMutableDictionary *add = [[q mutableCopy] autorelease];
        [add setObject:(id)kSecAttrAuthenticationTypeHTMLForm forKey:(id)kSecAttrAuthenticationType];
        [add setObject:([label length] ? label : server) forKey:(id)kSecAttrLabel];
        [add setObject:secret forKey:(id)kSecValueData];
        if (cred_use_dp_keychain()) {
            [add setObject:@YES forKey:(id)kSecAttrSynchronizable];
            [add setObject:(id)kSecAttrAccessibleWhenUnlocked forKey:(id)kSecAttrAccessible];
        }
        OSStatus s = SecItemAdd((CFDictionaryRef)add, NULL);
        if (s == errSecDuplicateItem) {
            NSDictionary *upd = @{(id)kSecValueData: secret};
            s = SecItemUpdate((CFDictionaryRef)q, (CFDictionaryRef)upd);
        }
        if (s == errSecSuccess) return cred_wstring(@"");
        CFStringRef m = SecCopyErrorMessageString(s, NULL);
        NSString *msg = [NSString stringWithFormat:@"%@ (%d)", m ? (NSString *)m : @"Keychain error", (int)s];
        if (m) CFRelease(m);
        return cred_wstring(msg);
    }
}

WValue w_cred_kc_delete(WValue server_v, WValue account_v) {
    @autoreleasepool {
        NSString *server = cred_nsstring(server_v), *account = cred_nsstring(account_v);
        if (![server length] || !account) return W_FALSE;
        OSStatus s = SecItemDelete((CFDictionaryRef)kc_query(server, account));
        return s == errSecSuccess ? W_TRUE : W_FALSE;
    }
}

/* A uniform random index below n from the system CSPRNG (rejection
 * sampling, so no modulo bias). */
static uint32_t cred_random_below(uint32_t n) {
    uint32_t limit = UINT32_MAX - (UINT32_MAX % n), x = 0;
    do {
        if (SecRandomCopyBytes(kSecRandomDefault, sizeof x, &x) != errSecSuccess) return UINT32_MAX;
    } while (x >= limit);
    return x % n;
}

/* Safari's strong-password shape: three groups of six joined by hyphens,
 * lowercase letters with one uppercase letter and one digit at random
 * places; look-alike characters (l, I, O, 0, 1) are left out. */
WValue w_cred_strong_password(void) {
    static const char lower[] = "abcdefghijkmnopqrstuvwxyz";
    static const char upper[] = "ABCDEFGHJKLMNPQRSTUVWXYZ";
    static const char digit[] = "23456789";
    char out[21];
    uint32_t up = cred_random_below(18), dg = cred_random_below(17);
    if (up == UINT32_MAX || dg == UINT32_MAX) return W_NIL;
    if (dg >= up) dg++;
    int k = 0;
    for (uint32_t i = 0; i < 18; i++) {
        if (i > 0 && i % 6 == 0) out[k++] = '-';
        const char *set = i == up ? upper : (i == dg ? digit : lower);
        uint32_t r = cred_random_below((uint32_t)strlen(set));
        if (r == UINT32_MAX) return W_NIL;
        out[k++] = set[r];
    }
    out[k] = 0;
    WValue v = w_string(out);
    memset(out, 0, sizeof out);
    return v;
}
