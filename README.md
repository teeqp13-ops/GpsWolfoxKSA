# WFLocationKit — لوحة تجربة موقع داخل التطبيق فقط

هذا الهيكل بديل آمن عن أي Hook/Tweak يعدّل `CLLocation` أو `identifierForVendor`
أو يُحقن تلقائيًا في تطبيقات أخرى أو في النظام. كل شيء هنا يعمل **داخل تطبيقك أنت فقط**،
كطبقة اختيارية فوق موقعك الحقيقي.

## الملفات

| الملف | الوظيفة |
|---|---|
| `WFSettingsStore.h/.m` | تخزين كل الإعدادات (تفعيل، إحداثيات، Jitter، المفضلة) في `NSUserDefaults` |
| `WFLocationProvider.h/.m` | يحوّل موقعك الحقيقي إلى موقع تجريبي *داخل الكود الخاص بتطبيقك* فقط |
| `WFFloatingButton.h/.m` | زر GPS عائم قابل للسحب، + عدّاد ضغطات سري للإظهار/الإخفاء |
| `WFBottomSheetViewController.h/.m` | لوحة تحكم كاملة: خريطة، بحث، اختيار نقطة، مفضلة، نسخ إحداثيات، Jitter |
| `WFIntegrationExample.m` | مثال دمج فعلي — انسخ منه داخل `RootViewController` عندك |

## كيف تدمجه

### 1. استبدال الموقع الحقيقي بموقعك التجريبي (داخل كودك أنت فقط)

في مكان استقبال التحديثات من `CLLocationManagerDelegate` الخاص بك:

```objc
- (void)locationManager:(CLLocationManager *)manager didUpdateLocations:(NSArray<CLLocation *> *)locations {
    CLLocation *real = locations.lastObject;
    CLLocation *effective = [[WFLocationProvider shared] currentLocationFromRealLocation:real];
    // استخدم effective بدل real في بقية منطق تطبيقك (مثلًا تحديث نقطة على خريطتك)
}
```

هذا **لا يغيّر** موقع الجهاز الحقيقي ولا يؤثر على تطبيقات أخرى — فقط يغيّر
القيمة التي يستخدمها الكود الخاص بك أنت.

### 2. إضافة الزر العائم ولوحة التحكم

انظر `WFIntegrationExample.m` — انسخ محتواه داخل `RootViewController` الخاص بتطبيقك.

### 3. الإظهار/الإخفاء

الزر مخفي افتراضيًا. لإظهاره اربط `WFSecretTapCounter` بأي منطقة تختارها
(مثلًا ضغط 5 مرات على شعار تطبيقك)، بدل ظهوره تلقائيًا للجميع.

## ما الذي لا يفعله هذا الكود عمدًا

- لا يعدّل `CLLocationManager` أو `CLLocation` على مستوى النظام.
- لا يستبدل `identifierForVendor` أو أي معرّف جهاز حقيقي.
- لا يحقن أي واجهة تلقائيًا في تطبيقات أخرى.
- لا يستخدم `method_swizzling` أو `Hooks` من أي نوع.

كل التأثير محصور داخل الكلاسات الخاصة بتطبيقك، وتقرر أنت متى وأين تُستخدم.
