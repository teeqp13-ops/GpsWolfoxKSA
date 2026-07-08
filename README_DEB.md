# GPS Plus / KSA Deb Tools

هذا المستند يجهز المستودع لاستخراج وفحص ملفات `.deb` الخاصة بتويك GPS Plus / KSA.

## الملفات المهمة

- `KSA.mm` سورس التويك.
- `debs/` ضع ملفات `.deb` هنا إذا أردت استخراجها داخل GitHub Actions.
- `scripts/extract_deb.sh` استخراج محتوى ملفات deb.
- `scripts/package_deb.sh` إعادة تجهيز حزمة deb من مجلد package.
- `.github/workflows/deb-tools.yml` تشغيل تلقائي لاستخراج الحزم ورفع الناتج كـ Artifact.

## طريقة الاستخدام داخل GitHub

1. ارفع ملف deb داخل مجلد `debs/`.
2. ادخل على Actions.
3. شغل Workflow باسم `DEB Tools`.
4. بعد الانتهاء ستجد ملف Artifact باسم `deb-extracted-output` يحتوي الملفات المستخرجة.

## استخراج محليًا

```bash
chmod +x scripts/extract_deb.sh
./scripts/extract_deb.sh debs/GPSPlus_Rootless.deb out/rootless
./scripts/extract_deb.sh debs/GPSPlus_Rootful.deb out/rootful
```

## إعادة بناء deb محليًا

```bash
chmod +x scripts/package_deb.sh
./scripts/package_deb.sh package GPSPlus_Custom.deb
```

> ملاحظة: المستودع الحالي يجهز أدوات الاستخراج والتنظيم. ملف deb نفسه يمكن رفعه داخل `debs/` عند الحاجة.