# Testing the APK on a phone (Phase 3)

Use the **profile** build `tilawa-profile-arm64-v2.apk`: it is compiled like the final app
(fast), and keeps the diagnostics screen. First uninstall the previous debug version.

1. Install `tilawa-profile-arm64-v2.apk` (allow "install unknown apps" for your file manager).
2. First launch: read the screen, tap «السماح باستخدام الميكروفون», allow the microphone.
3. Choose «حفص عن عاصم», Al-Fātiḥa, ayah 1 → «ابدأ» → «ابدأ الاستماع». Recite normally,
   then pause. While listening, the bar under the ayah shows the microphone level (green when
   your voice is detected). Words turn green / orange / red as you go. Tap a coloured word.
4. Try deliberate mistakes: skip a word, replace a word, repeat a word, recite the next ayah.
5. Gating: by default nothing blocks yet (Phase 5 rule). To see it, enable
   الإعدادات → خيارات المطوّر → «اعتبار أخطاء الكلمات مانعة».
6. Speed: الإعدادات → شاشة التشخيص وقياس السرعة → «قياس السرعة على هذا الهاتف»; recite for
   5 seconds. Send a screenshot of the results (the «CPU» line shows which instructions are
   used) and of the diagnostics block (device, tier, asr_live_ms / asr_final_ms p50/p95).

Nothing is recorded or saved; the speed test keeps 5 seconds in memory and erases it.
Warsh can be tried too, but its acoustic results are not validated (model assumed Hafs-only).
