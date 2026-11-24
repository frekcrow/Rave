#import <Foundation/Foundation.h>
#import <objc/message.h>
#import <objc/runtime.h>
#import <os/log.h>

static os_log_t ravefix_log(void) {
    static os_log_t logger = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        logger = os_log_create("com.ravefix.tweak", "RaveFix");
    });
    return logger;
}

#define RFLog(fmt, ...) os_log(ravefix_log(), "%{public}@", [NSString stringWithFormat:(fmt), ##__VA_ARGS__])

// --- Bugfender hook ---
typedef void (*BugfenderLogIMP)(id self, SEL _cmd, NSInteger lineNumber, NSString *method, NSString *file, NSUInteger level, NSString *tag, NSString *message);
static BugfenderLogIMP orig_bf_log = NULL;

static void hook_bf_log(id self, SEL _cmd, NSInteger lineNumber, NSString *method, NSString *file, NSUInteger level, NSString *tag, NSString *message) {
    RFLog(@"[BF][%lu][%@] %@:%ld %@ -> %@",
          (unsigned long)level,
          tag ?: @"",
          file.lastPathComponent ?: @"",
          (long)lineNumber,
          method ?: @"",
          message ?: @"");
    if (orig_bf_log) {
        orig_bf_log(self, _cmd, lineNumber, method, file, level, tag, message);
    }
}

static void install_bugfender_hook(void) {
    Class bfClass = objc_getClass("Bugfender");
    if (!bfClass) {
        RFLog(@"[RaveFix] Bugfender class not found");
        return;
    }

    SEL printSel = sel_registerName("setPrintToConsole:");
    if ([bfClass respondsToSelector:printSel]) {
        ((void (*)(id, SEL, BOOL))objc_msgSend)(bfClass, printSel, YES);
    }

    SEL logSel = sel_registerName("logWithLineNumber:method:file:level:tag:message:");
    Method m = class_getClassMethod(bfClass, logSel);
    if (m) {
        orig_bf_log = (BugfenderLogIMP)method_setImplementation(m, (IMP)hook_bf_log);
        RFLog(@"[RaveFix] Hooked +[Bugfender logWithLineNumber:method:file:level:tag:message:]");
    } else {
        RFLog(@"[RaveFix] Bugfender log method not found");
    }
}

// --- NSURLSession diagnostic hook ---
typedef NSURLSessionDataTask *(*DataTaskReqIMP)(id self, SEL _cmd, NSURLRequest *request, void (^completionHandler)(NSData *data, NSURLResponse *response, NSError *error));
static DataTaskReqIMP orig_dataTaskWithRequest = NULL;

static BOOL is_interesting_url(NSURL *url) {
    NSString *host = url.host.lowercaseString;
    if (!host) return NO;
    return [host containsString:@"youtube.com"] ||
           [host containsString:@"googlevideo.com"] ||
           [host containsString:@"wemesh.ca"] ||
           [host containsString:@"a-l-p-a.com"] ||
           [host containsString:@"hilljam.com"];
}

static NSURLSessionDataTask *hook_dataTaskWithRequest(id self, SEL _cmd, NSURLRequest *request, void (^completionHandler)(NSData *data, NSURLResponse *response, NSError *error)) {
    NSURL *url = request.URL;
    if (!completionHandler || !is_interesting_url(url)) {
        return orig_dataTaskWithRequest(self, _cmd, request, completionHandler);
    }

    NSString *method = request.HTTPMethod ?: @"GET";
    NSString *urlStr = url.absoluteString ?: @"";

    void (^wrapped)(NSData *, NSURLResponse *, NSError *) = ^(NSData *data, NSURLResponse *response, NSError *error) {
        NSInteger status = 0;
        if ([response isKindOfClass:[NSHTTPURLResponse class]]) {
            status = ((NSHTTPURLResponse *)response).statusCode;
        }
        if (error || status < 200 || status >= 300 || [urlStr containsString:@"youtubei/v1/player"] || [urlStr containsString:@"wemesh.ca"] || [urlStr containsString:@"a-l-p-a.com"]) {
            NSString *preview = @"";
            if (data.length > 0 && data.length < 65536) {
                NSString *body = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
                if (body.length > 500) {
                    body = [body substringToIndex:500];
                }
                preview = body ?: [NSString stringWithFormat:@"<%lu bytes>", (unsigned long)data.length];
            } else if (data.length > 0) {
                preview = [NSString stringWithFormat:@"<%lu bytes>", (unsigned long)data.length];
            }
            RFLog(@"[HTTP] %@ %@ -> status=%ld err=%@ body=%@",
                  method,
                  urlStr,
                  (long)status,
                  error.localizedDescription ?: @"none",
                  preview);
        }
        completionHandler(data, response, error);
    };

    return orig_dataTaskWithRequest(self, _cmd, request, wrapped);
}

static void install_network_hook(void) {
    Class sessionClass = objc_getClass("NSURLSession");
    if (!sessionClass) return;

    SEL sel = sel_registerName("dataTaskWithRequest:completionHandler:");
    Method m = class_getInstanceMethod(sessionClass, sel);
    if (m) {
        orig_dataTaskWithRequest = (DataTaskReqIMP)method_setImplementation(m, (IMP)hook_dataTaskWithRequest);
        RFLog(@"[RaveFix] Hooked -[NSURLSession dataTaskWithRequest:completionHandler:]");
    }
}

__attribute__((constructor))
static void ravefix_init(void) {
    @autoreleasepool {
        RFLog(@"[RaveFix] Loaded into %@ (%@)",
              NSBundle.mainBundle.bundleIdentifier ?: @"unknown",
              NSBundle.mainBundle.infoDictionary[@"CFBundleShortVersionString"] ?: @"?");
        install_bugfender_hook();
        install_network_hook();
    }
}
