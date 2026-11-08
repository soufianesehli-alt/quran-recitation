# Testing the debug APK on a phone (Phase 3)

1. Install `tilawa-debug-arm64.apk` (allow "install unknown apps" for your file manager).
2. First launch: read the screen, tap «السماح باستخدام الميكروفون», allow the microphone.
3. Choose «حفص عن عاصم», Al-Fātiḥa, ayah 1 → «ابدأ» → «ابدأ الاستماع». Recite normally,
   then pause. Watch the words turn green / orange / red. Tap a coloured word.
4. Try deliberate mistakes: skip a word, replace a word, repeat a word, recite the next ayah.
5. Gating: by default nothing blocks yet (Phase 5 rule). To see it, enable
   الإعدادات → خيارات المطوّر → «اعتبار أخطاء الكلمات مانعة».
6. Speed: الإعدادات → شاشة التشخيص وقياس السرعة → «قياس السرعة على هذا الهاتف»; recite for
   5 seconds. Send a screenshot of the results and of the diagnostics block
   (device, tier, p50/p95 timings).

Nothing is recorded or saved; the speed test keeps 5 seconds in memory and erases it.
Warsh can be tried too, but its acoustic results are not validated (model assumed Hafs-only).
