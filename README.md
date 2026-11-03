# تطبيق سجل السيارات اليومي (Flutter Android App)

تطبيق متكامل لتتبع حركة وسجل السيارات اليومي وعدادات الكيلومترات مع التعبئة الذكية والربط السحابي مع Google Sheets.

## متطلبات التشغيل
- Flutter SDK (الإصدار 3.0 فما فوق)
- Android SDK وجهاز أندرويد أو محاكي

## طريقة بناء ملف APK في دقيقة:
1. افتح موجه الأوامر (Terminal) في مجلد المشروع.
2. نفّذ الأمر التالي:
```bash
flutter pub get
flutter build apk --release
```
3. ستجد ملف الـ APK جاهزاً للتثبيت المباشر على الهاتف في المسار:
`build/app/outputs/flutter-apk/app-release.apk`

## التجميع التلقائي المجاني عبر GitHub Actions
يحتوي المشروع على ملف جاهز `.github/workflows/build_apk.yml`.
عند رفع المشروع على حسابك في GitHub، سيتم بناء الـ APK تلقائياً على خوادم GitHub السحابية وتستطيع تحميله من تبويب **Actions > Artifacts** مباشرة دون الحاجة لتثبيت أي برامج على حاسوبك!
