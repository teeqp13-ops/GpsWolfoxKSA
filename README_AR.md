# مشروع GPS

نسخة كاملة منظّمة بعد الفحص وإصلاح الأخطاء، مبنية على تحليل الملف المرفق `GPSPlus(1).zip` وعلى شكل الواجهة في الصور.

## الاسم المعتمد

**GPS**

## قاعدة الحالة

- الأخضر = يعمل / مفعّل
- الأسود = مغلق / غير مفعّل

## ما يدعمه المشروع

- زر إغلاق يمين أعلى الشاشة.
- زر معلومات الكود يسار أعلى الشاشة.
- اسم GPS في الوسط أعلى الشاشة.
- عرض الخريطة بثلاثة أوضاع: خريطة، قمر صناعي، مخطط.
- البحث باستخدام:
  - إحداثيات مباشرة.
  - رابط Google Maps.
  - رابط Apple Maps.
  - اسم مكان.
- المفضلة: حفظ الموقع الحالي، اختيار موقع محفوظ، حذف كل المفضلات.
- إعدادات المعرف المحلي.
- رفع صورة من الجهاز عبر مستعرض الملفات.
- إخفاء الأداة والتحكم بعدد الضغطات لإظهارها.
- زر اختيار الموقع وتفعيل GPS.
- محاكاة حركة بسيطة حول الموقع المحدد بمسافة تقريبية 10 أمتار.

## بنية المشروع

```text
GPS_Final_Complete_Project/
├── Makefile
├── control
├── GPS.plist
├── GPS.mm
├── Sources/
│   └── GPS.mm
├── scripts/
│   ├── build-rootless.sh
│   ├── build-rootful.sh
│   ├── install-device.sh
│   └── clean.sh
├── docs/
│   ├── CHECK_REPORT_AR.md
│   ├── IMPLEMENTATION_GUIDE_AR.md
│   ├── FILE_ANALYSIS_SUMMARY_AR.md
│   └── PROJECT_STRUCTURE_AR.md
├── assets/
│   ├── preview.png
│   └── reference_ui.png
└── packages/
```

## البناء

Rootless:

```bash
./scripts/build-rootless.sh
```

Rootful:

```bash
./scripts/build-rootful.sh
```

## التثبيت

```bash
./scripts/install-device.sh 192.168.1.10
```

## ملاحظة مهمة

ملف التحليل الأصلي يحتوي رموز Bypass/Identity. لم يتم نسخ هذه الأجزاء في المشروع النهائي. الموجود هنا هو واجهة GPS والبحث والخريطة والمفضلة والمحاكاة المحلية فقط.


---

# إضافة لوحة التحكم الكاملة

تمت إضافة مجلد:

```text
server/
```

ويحتوي على لوحة تحكم كاملة + API + SQLite + نظام أكواد + إدارة أجهزة + تصدير.

## ملفات مهمة

```text
server/public/install.php
server/public/index.php
server/public/api/activate.php
server/public/api/status.php
server/public/api/config.php
server/public/api/heartbeat.php
server/public/api/upload_image.php
Sources/GPSApiClient.h
Sources/GPSApiClient.mm
docs/API_LINKING_GUIDE_AR.md
docs/ADMIN_PANEL_GUIDE_AR.md
docs/FULL_LINKING_STEPS_AR.md
```

## قاعدة الحالة

- الأخضر = يعمل.
- الأسود = مغلق.



---

## نسخة الفحص والدمج والتنصيب الكامل

أضيف في هذه النسخة:

- `install.sh` برنامج تنصيب وتجهيز شامل من جذر المشروع.
- `tools/verify_all.sh` فحص شامل للملفات و PHP وملفات الربط.
- `tools/merge_api_config.sh` دمج رابط API والمفتاح داخل ملف iOS.
- `tools/run_local_server.sh` تشغيل لوحة التحكم محليًا للاختبار.
- `tools/backup_server.php` إنشاء نسخة احتياطية من قاعدة SQLite.
- `server/public/api/ping.php` فحص سريع لحالة API.
- `install.php` في جذر المشروع يحول مباشرة إلى تنصيب اللوحة.

ابدأ بـ:

```bash
chmod +x install.sh scripts/*.sh tools/*.sh
./install.sh
```
