# KFGQPC Warsh source (official package, unmodified)

| | |
|---|---|
| File | `UthmanicWarsh_v2-1.zip` (9,042,379 bytes), committed **unopened** |
| Publisher | King Fahd Glorious Qur'an Printing Complex (KFGQPC), Madinah |
| Official page | https://qurancomplex.gov.sa/quran-dev/ ("خط الرسم العثماني (رواية ورش)") |
| Official URL | https://download.qurancomplex.gov.sa/resources_dev/UthmanicWarsh_v2-1.zip |
| Version | data v2.1, update 6.0, last updated 2022-09-07 |
| Obtained from | https://cdn.quran.ws/KFGQPC/resources/quran-dev/uthmanic-warsh/UthmanicWarsh_v2-1.zip on 2026-11-08 (the official host returned 503 to this cloud) |
| MD5 (published by KFGQPC) | `4701e8bbf053098220cf2cf4cda206a1` ✅ matches |
| SHA-1 (published by KFGQPC) | `44ecea8feb23817fdc01a8ee2162a6a0cf08cae7` ✅ matches |
| SHA-256 | `d847a7e7002dfbed5d28db6684fd1d9c3d50b8bb63ad64cb38a46b9dad788b47` |

## Authenticity evidence
1. The MD5 and SHA-1 match the values KFGQPC publishes on its developer page. Those values
   were read from the archive's capture of that page; an independent check through the Wayback
   Machine failed (connection reset). The match is tested in `tools/tests`.
2. `uthmanic_warsh_v21.docx` inside the zip has an XML digital signature from a DigiCert code
   signing certificate issued to "King Fahd Glorious Quran Printing complex" (Al Madinah Al
   Munawwarah, SA), signed 2022-09-07T08:02:47Z. The signer was inspected; the signature
   itself was not cryptographically validated.
3. The normalized text of **all 114 surahs** of `warshData_v2-1.json` occurs, in order, in that
   signed document.

## Terms
- Data: no terms of use are published with it, on the page or in the zip.
- Font `uthmanic_warsh_v21.ttf`: its embedded name table carries a copyright notice ("may not be
  reproduced, modified without the express written approval") **and** an end-user license
  ("rights to Use, Copy, Distribute" free of cost; no selling, modification or reverse
  engineering). Both are copied verbatim in `app/assets/fonts/KFGQPC-Warsh-font-license.txt`.
  Product-owner decision: build now, request written permission before any public release.
