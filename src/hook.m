/*
 * hook.m — 5EPlay 7.2.1 去开屏品牌广告 MVP 插件（TrollFools）
 *
 * 目标类:  SADSplashAdViewController
 * 目标方法: -[SADSplashAdViewController handleBrandAd:]   (品牌开屏广告入口)
 *
 * 逆向依据（5EPlay_7.2.1_decrypted）:
 *   handleBrandAd: @ 0x1022F7998, 签名 v24@0:8@16 (实例方法, 1 个对象参数)
 *   closeController:  @ 0x1022F759C, 签名 v20@0:8B16 (BOOL 参数)
 *   - handleBrandAd: 是「品牌 Splash 广告」唯一入口:
 *       GET /v1/home/adv_slot/list → adv_display==1 → adv_brand!=nil
 *       → handleAdInfo: → handleBrandAd: → loadAdData: → SADBrandSplashAd.showAd
 *   - closeController: 内部调用 closeHandle block → afterADShowFinished
 *     → 发 Notif_AfterADShowFinished → 继续 App 启动流程
 *
 * MVP 策略:
 *   1) Hook handleBrandAd: → 直接 return（不进入品牌广告加载/展示）
 *   2) 立即调用 closeController:YES 继续启动流程，避免 Splash 卡住
 *      （YES = 正常关闭，不写入 saveFailSplashADDate，不污染服务端频控）
 *   3) 日志确认 hook 生效；弹窗可见验证
 *
 * 结构（skill 强制要求）:
 *   - constructor 只 dlsym + 注册 UIApplicationDidFinishLaunchingNotification
 *   - 全部 Hook 在启动完成通知回调内执行（constructor 早期调 objc API 会 SIGILL）
 */

#import <Foundation/Foundation.h>
#import <CoreFoundation/CoreFoundation.h>
#import <objc/runtime.h>
#import <objc/message.h>
#import <dlfcn.h>

/* ========== 0. 目标定义 ========== */
#define PLUGIN_TAG        "NoBrandSplash"
#define TARGET_BUNDLE_ID  "com.5e.5eplay"
#define TARGET_CLASS_NAME "SADSplashAdViewController"
#define TARGET_SEL_BRAND  "handleBrandAd:"        /* 品牌开屏广告入口 */
#define TARGET_SEL_CLOSE  "closeController:"      /* 关闭控制器（继续启动流程） */
#define TARGET_ALERT_MSG  "NoBrandSplash Injected OK"

/* ========== 1. 运行时符号指针（constructor 里 dlsym 解析） ========== */
static Class (*p_objc_getClass)(const char *name);
static id   (*p_objc_msgSend)(id self, SEL _cmd, ...);
static SEL  (*p_sel_registerName)(const char *str);
static Method (*p_class_getInstanceMethod)(Class cls, SEL name);
static IMP  (*p_method_setImplementation)(Method method, IMP imp);

/* ========== 2. 调试日志（stderr） ========== */
#define LOG(fmt, ...) fprintf(stderr, "[" PLUGIN_TAG "] " fmt "\n", ##__VA_ARGS__)

/* ========== 3. Hook 辅助（MISS 记录，不崩溃） ========== */
static void hook_instance_method(Class cls, const char *selName, IMP newImp)
{
    if (!cls) {
        LOG("hook: class NULL for %s", selName);
        return;
    }
    SEL sel = p_sel_registerName(selName);
    Method m = p_class_getInstanceMethod(cls, sel);
    if (m) {
        p_method_setImplementation(m, newImp);
        LOG("hook OK: -[%s %s]", TARGET_CLASS_NAME, selName);
    } else {
        LOG("hook MISS (method not found): -[%s %s]", TARGET_CLASS_NAME, selName);
    }
}

/* ========== 4. 品牌广告入口替换实现 ========== */
/*
 * 原实现: -[SADSplashAdViewController handleBrandAd:(SADAdBrandModel *)brand]
 *   processingBrandData → loadAdData → performSelector checkTimeout ...
 * MVP: 直接阻断 + 关闭控制器继续启动流程。
 * 必须调用 closeController:，否则 splash 视图常驻导致启动页卡死。
 */
static void hook_handleBrandAd(id self, SEL _cmd, id brand)
{
    LOG("BLOCKED: -[%s handleBrandAd:] — brand splash suppressed", TARGET_CLASS_NAME);

    /* 继续启动流程：closeController 内部会触发 closeHandle → afterADShowFinished */
    SEL closeSel = p_sel_registerName(TARGET_SEL_CLOSE);
    ((void (*)(id, SEL, BOOL))p_objc_msgSend)(self, closeSel, YES);
}

/* ========== 5. 可见验证弹窗 ========== */
static void show_alert(void)
{
    Class cls = (Class)p_objc_getClass("UIAlertView");
    if (!cls) { LOG("UIAlertView class not available"); return; }

    SEL initSel    = p_sel_registerName("initWithTitle:message:delegate:cancelButtonTitle:otherButtonTitles:");
    SEL showSel    = p_sel_registerName("show");
    SEL dismissSel = p_sel_registerName("dismissWithClickedButtonIndex:animated:");

    id alert = p_objc_msgSend(cls, initSel,
                              @"NoBrandSplash",
                              TARGET_ALERT_MSG,
                              nil, nil, nil);
    if (alert) {
        p_objc_msgSend(alert, showSel);
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(2LL * NSEC_PER_SEC)),
                       dispatch_get_main_queue(), ^{
            p_objc_msgSend(alert, dismissSel, 0, YES);
        });
    }
}

/* ========== 6. 启动完成回调（Hook 全部在这里执行） ========== */
static void on_did_finish_launching(CFNotificationCenterRef center, void *observer,
                                    CFStringRef name, const void *object, CFDictionaryRef userInfo)
{
    LOG("app did finish launching, begin hooking");

    Class cls = p_objc_getClass(TARGET_CLASS_NAME);
    if (!cls) {
        LOG("target class %s NOT FOUND — version mismatch, need re-analyze", TARGET_CLASS_NAME);
        return;
    }

    /* 6.1 逐点 Hook（MISS 会打日志，不崩溃） */
    hook_instance_method(cls, TARGET_SEL_BRAND, (IMP)hook_handleBrandAd);

    /* 6.2 可见验证弹窗 */
    show_alert();

    LOG("hook phase done");
}

/* ========== 7. 入口 ========== */
__attribute__((constructor))
static void init(void)
{
    LOG("plugin loaded, resolving symbols...");

    /* 7.1 解析全部 objc 符号（运行时获取，不静态链接） */
    *(void **)&p_objc_getClass         = dlsym(RTLD_DEFAULT, "objc_getClass");
    *(void **)&p_objc_msgSend          = dlsym(RTLD_DEFAULT, "objc_msgSend");
    *(void **)&p_sel_registerName      = dlsym(RTLD_DEFAULT, "sel_registerName");
    *(void **)&p_class_getInstanceMethod = dlsym(RTLD_DEFAULT, "class_getInstanceMethod");
    *(void **)&p_method_setImplementation = dlsym(RTLD_DEFAULT, "method_setImplementation");

    if (!p_objc_getClass || !p_objc_msgSend || !p_sel_registerName ||
        !p_class_getInstanceMethod || !p_method_setImplementation) {
        LOG("FATAL: symbol resolution failed — cannot hook");
        return;
    }

    /* 7.2 注册启动完成通知（constructor 阶段不执行任何 Hook） */
    CFNotificationCenterAddObserver(CFNotificationCenterGetDarwinNotifyCenter(),
                                    NULL, on_did_finish_launching,
                                    CFSTR("UIApplicationDidFinishLaunchingNotification"),
                                    NULL, CFNotificationSuspensionBehaviorDeliverImmediately);

    LOG("constructor done, waiting for app launch");
}
