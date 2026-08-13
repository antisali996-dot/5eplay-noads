/*
 * hook.m — 5EPlay 7.2.1 去开屏广告 v2.0 插件（TrollFools）
 *
 * 目标类:  SADSplashAdViewController
 * 目标方法: -[SADSplashAdViewController handleAdInfo:]   (冷/热启动开屏广告数据共同入口)
 *
 * 逆向依据（5EPlay_7.2.1_decrypted）:
 *   handleAdInfo:  @ 0x1022F7474, 签名 v24@0:8@16 (实例方法, 1 个对象参数)
 *   closeController: @ 0x1022F759C, 签名 v20@0:8B16 (BOOL 参数)
 *   - handleAdInfo: 是冷启动/热启动进入 Splash 数据处理后的共同分叉点:
 *       冷启动: enterSplashAD → fetchAdInfoIsHotLaunch:NO  → callback → handleAdInfo:
 *       热启动: enterForeground → enterHotLaunchAD → fetchAdInfoIsHotLaunch:YES → handleAdInfo:
 *       （handleAdInfo: 的 objc_msgSend stub 唯二调用者即上述两个回调 block）
 *   - handleAdInfo: 内部按数据分叉（adv_brand != nil → handleBrandAd:；
 *       adv_slot_items != nil → handleAdList:；都为空 → closeController:），
 *       因此 Hook handleAdInfo: 同时覆盖品牌 Splash 与第三方聚合 Splash
 *       （CSJ / GDT / OCT / BeiZi / CJMobile / Sigmob）
 *   - loadAdData: 是广告 SDK 初始化/加载路径（appKeyInitPlatform:appkey:callBack: 唯一入口），
 *       只能从 handleBrandAd:/handleAdList: 分支进入 —— 在 handleAdInfo: 阻断后不会到达，
 *       第三方广告 SDK 不会初始化
 *   - closeController: 内部调用 closeHandle block → afterADShowFinished
 *     → 发 Notif_AfterADShowFinished → 继续 App 启动流程
 *
 * v2.0 策略:
 *   1) Hook handleAdInfo: → 直接 return（品牌 + 第三方聚合 Splash 全部阻断）
 *   2) 立即调用 closeController:YES 正常结束 Splash 生命周期，避免启动页卡住
 *      （YES = 正常关闭，不写入 saveFailSplashADDate，不污染服务端频控）
 *   3) 日志确认 hook 生效；弹窗可见验证
 *
 * v3.0 正式版:
 *   - 正式 Hook 只有 handleAdInfo: 一个（冷/热启动开屏广告共同入口）
 *   - 拦截品牌 Splash + 第三方聚合 Splash，closeController:YES 正常收尾
 *   - 保留「NoBrandSplash Injected OK」注入确认弹窗（1 秒自动消失，QSNoAds v25 同款）
 *   - 已移除全部诊断弹窗/计数（HOOK HIT 等）
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
#import <stdio.h>

/* ========== 0. 目标定义 ========== */
#define PLUGIN_TAG        "NoBrandSplash"
#define TARGET_BUNDLE_ID  "com.5e.5eplay"
#define TARGET_CLASS_NAME "SADSplashAdViewController"
#define TARGET_SEL_ADINFO "handleAdInfo:"        /* 开屏广告数据总入口（冷/热启动汇合点） */
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
static BOOL hook_instance_method(Class cls, const char *selName, IMP newImp)
{
    if (!cls) {
        LOG("hook: class NULL for %s", selName);
        return NO;
    }
    SEL sel = p_sel_registerName(selName);
    Method m = p_class_getInstanceMethod(cls, sel);
    if (m) {
        p_method_setImplementation(m, newImp);
        LOG("hook OK: -[%s %s]", TARGET_CLASS_NAME, selName);
        return YES;
    }
    LOG("hook MISS (method not found): -[%s %s]", TARGET_CLASS_NAME, selName);
    return NO;
}

/* ========== 4. 注入确认弹窗（QSNoAds v25 同款：UIAlertView + NSTimer 1 秒自动消失） ========== */

static void show_alert_msg(const char *title, const char *msg)
{
    typedef id (*msg_1)(id, SEL);
    typedef id (*msg_3)(id, SEL, id, id, id, id, id);
    typedef id (*msg_timer)(id, SEL, double, BOOL, id);
    typedef void (*msg_3v)(id, SEL, long, BOOL);

    id a = ((msg_1)p_objc_msgSend)((id)p_objc_getClass("UIAlertView"),
                                   p_sel_registerName("alloc"));
    if (!a) return;
    id t = ((id(*)(id, SEL, const char *))p_objc_msgSend)(
        (id)p_objc_getClass("NSString"), p_sel_registerName("stringWithUTF8String:"), title);
    id m = ((id(*)(id, SEL, const char *))p_objc_msgSend)(
        (id)p_objc_getClass("NSString"), p_sel_registerName("stringWithUTF8String:"), msg);
    id ok = ((id(*)(id, SEL, const char *))p_objc_msgSend)(
        (id)p_objc_getClass("NSString"), p_sel_registerName("stringWithUTF8String:"), "OK");
    id v = ((msg_3)p_objc_msgSend)(a,
        p_sel_registerName("initWithTitle:message:delegate:cancelButtonTitle:otherButtonTitles:"),
        t, m, nil, ok, nil);
    if (!v) return;
    ((void(*)(id, SEL))p_objc_msgSend)(v, p_sel_registerName("show"));
    /* 1 秒后自动消失，无需点击 */
    ((msg_timer)p_objc_msgSend)(
        (id)p_objc_getClass("NSTimer"),
        p_sel_registerName("scheduledTimerWithTimeInterval:repeats:block:"),
        1.0, NO,
        (id)^(id timer) {
            ((msg_3v)p_objc_msgSend)(v,
                p_sel_registerName("dismissWithClickedButtonIndex:animated:"), 0, YES);
        });
}

/* ========== 5. 开屏广告总入口替换实现 ========== */
/*
 * 原实现: -[SADSplashAdViewController handleAdInfo:(SADAdDataModel *)adInfo]
 *   adv_brand != nil     → setAdtype:1 + handleBrandAd:（品牌 Splash）
 *   adv_slot_items != nil→ setAdtype:2 + handleAdList:（第三方聚合 Splash，eCPM 竞价）
 *   都为空               → closeController:NO
 * v2.0: 在共同分叉点直接阻断（品牌 + 第三方双覆盖，冷启动 + 热启动双覆盖），
 *       并调用 closeController:YES 正常结束 Splash 生命周期。
 * 必须调用 closeController:，否则 splash 视图常驻导致启动页卡死。
 *
 * v3.0 正式版: 直接阻断 + 关闭控制器继续启动流程。
 * 必须调用 closeController:，否则 splash 视图常驻导致启动页卡死。
 */
static void hook_handleAdInfo(id self, SEL _cmd, id adInfo)
{
    LOG("BLOCKED: -[%s handleAdInfo:] — splash suppressed (brand + third-party)", TARGET_CLASS_NAME);

    /* 继续启动流程：closeController 内部会触发 closeHandle → afterADShowFinished */
    SEL closeSel = p_sel_registerName(TARGET_SEL_CLOSE);
    ((void (*)(id, SEL, BOOL))p_objc_msgSend)(self, closeSel, YES);
}

/* ========== 6.（空，横幅逻辑见 section 4） ========== */

/* ========== 7. 启动完成回调（Hook 全部在这里执行，主线程） ========== */
static void on_did_finish_launching(void)
{
    LOG("app did finish launching, begin hooking");

    Class cls = p_objc_getClass(TARGET_CLASS_NAME);
    if (!cls) {
        LOG("target class %s NOT FOUND — version mismatch, need re-analyze", TARGET_CLASS_NAME);
        return;
    }

    /* 7.1 正式拦截：开屏广告数据总入口（冷/热启动共同分叉点） */
    hook_instance_method(cls, TARGET_SEL_ADINFO, (IMP)hook_handleAdInfo);

    /* 7.2 注入确认弹窗（1 秒自动消失） */
    show_alert_msg("NoBrandSplash", TARGET_ALERT_MSG);

    LOG("hook phase done");
}

/* ========== 8. 入口 ========== */
__attribute__((constructor))
static void init(void)
{
    LOG("plugin loaded, resolving symbols...");

    /* 8.1 解析全部 objc 符号（运行时获取，不静态链接） */
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

    /* 8.2 注册启动完成通知（NSNotificationCenter block 观察者，主线程回调——
     *      QSNoAds v25 验证过的可靠方案；Darwin 通知回调线程不保证主线程） */
    Class ncClass  = p_objc_getClass("NSNotificationCenter");
    Class strClass = p_objc_getClass("NSString");
    if (!ncClass || !strClass) {
        LOG("FATAL: NSNotificationCenter/NSString not available");
        return;
    }
    id nc = ((id(*)(id, SEL))p_objc_msgSend)((id)ncClass, p_sel_registerName("defaultCenter"));
    id name = ((id(*)(id, SEL, const char *))p_objc_msgSend)(
        (id)strClass, p_sel_registerName("stringWithUTF8String:"),
        "UIApplicationDidFinishLaunchingNotification");
    void (^hookBlock)(id) = ^(id note) { on_did_finish_launching(); };
    ((id(*)(id, SEL, id, id, id, id, id))p_objc_msgSend)(
        nc, p_sel_registerName("addObserverForName:object:queue:usingBlock:"),
        name, nil, nil, (id)hookBlock, nil);

    LOG("constructor done, waiting for app launch");
}
