from fastapi import FastAPI, HTTPException
from fastapi.middleware.cors import CORSMiddleware
from pydantic import BaseModel
import anthropic
import httpx
import os
from dotenv import load_dotenv

load_dotenv()

app = FastAPI(title="Quran Recitation API")

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_methods=["*"],
    allow_headers=["*"],
)

claude = anthropic.Anthropic(api_key=os.getenv("ANTHROPIC_API_KEY"))

QURAN_API_BASE = "https://api.quran.com/api/v4"

EDITIONS = {
    "hafs": "quran-uthmani",
    "warsh": "quran-warsh-hafs",
}


class RecitationCheck(BaseModel):
    surah: int
    ayah: int
    riwaya: str  # "hafs" or "warsh"
    transcribed_text: str


class VerseRequest(BaseModel):
    surah: int
    ayah: int
    riwaya: str


@app.get("/verse")
async def get_verse(surah: int, ayah: int, riwaya: str = "hafs"):
    edition = EDITIONS.get(riwaya, EDITIONS["hafs"])
    url = f"{QURAN_API_BASE}/verses/by_key/{surah}:{ayah}?words=true&translation_fields=text&word_fields=text_uthmani,text_imlaei"

    async with httpx.AsyncClient() as client:
        resp = await client.get(url)
        if resp.status_code != 200:
            raise HTTPException(500, "Failed to fetch verse from Quran API")
        data = resp.json()

    verse = data.get("verse", {})
    words = verse.get("words", [])
    text = " ".join(w.get("text_uthmani", "") for w in words if w.get("char_type_name") == "word")

    # For Warsh, fetch the warsh-specific edition
    if riwaya == "warsh":
        url2 = f"{QURAN_API_BASE}/verses/by_key/{surah}:{ayah}?words=false&translations=131"
        async with httpx.AsyncClient() as client:
            resp2 = await client.get(url2)
            if resp2.status_code == 200:
                data2 = resp2.json()
                warsh_text = data2.get("verse", {}).get("translations", [{}])[0].get("text", text)
                text = warsh_text if warsh_text else text

    return {
        "surah": surah,
        "ayah": ayah,
        "riwaya": riwaya,
        "text": text,
        "words": [w.get("text_uthmani", "") for w in words if w.get("char_type_name") == "word"],
    }


@app.get("/surah/{surah_number}/info")
async def get_surah_info(surah_number: int):
    async with httpx.AsyncClient() as client:
        resp = await client.get(f"{QURAN_API_BASE}/chapters/{surah_number}")
        if resp.status_code != 200:
            raise HTTPException(500, "Failed to fetch surah info")
        return resp.json()


@app.get("/surahs")
async def list_surahs():
    async with httpx.AsyncClient() as client:
        resp = await client.get(f"{QURAN_API_BASE}/chapters?language=ar")
        if resp.status_code != 200:
            raise HTTPException(500, "Failed to fetch surahs list")
        return resp.json()


@app.post("/check")
async def check_recitation(req: RecitationCheck):
    # Fetch expected verse text
    verse_data = await get_verse(req.surah, req.ayah, req.riwaya)
    expected_text = verse_data["text"]

    riwaya_name = "حفص عن عاصم" if req.riwaya == "hafs" else "ورش عن نافع"

    prompt = f"""أنت متخصص في علم التجويد والقراءات القرآنية.
المستخدم يتلو الآية {req.ayah} من سورة رقم {req.surah} برواية {riwaya_name}.

النص المتوقع (رواية {riwaya_name}):
{expected_text}

ما تلاه المستخدم (تفريغ الصوت):
{req.transcribed_text}

قم بمقارنة ما تلاه المستخدم بالنص المتوقع وحدد:
1. هل التلاوة صحيحة؟
2. قائمة الأخطاء إن وجدت مع:
   - الكلمة الخاطئة
   - الكلمة الصحيحة
   - نوع الخطأ (خطأ في الرواية / خطأ في التجويد / نقص / زيادة)
   - الحكم التجويدي المخالف إن وجد

أجب بصيغة JSON فقط بالشكل التالي:
{{
  "is_correct": true/false,
  "score": 0-100,
  "errors": [
    {{
      "wrong_word": "...",
      "correct_word": "...",
      "error_type": "...",
      "rule": "...",
      "explanation": "..."
    }}
  ],
  "general_feedback": "..."
}}"""

    message = claude.messages.create(
        model="claude-sonnet-4-6",
        max_tokens=1024,
        messages=[{"role": "user", "content": prompt}],
    )

    import json
    try:
        response_text = message.content[0].text
        # Extract JSON from response
        start = response_text.find("{")
        end = response_text.rfind("}") + 1
        result = json.loads(response_text[start:end])
    except Exception:
        result = {
            "is_correct": False,
            "score": 0,
            "errors": [],
            "general_feedback": message.content[0].text,
        }

    return {
        "expected_text": expected_text,
        "transcribed_text": req.transcribed_text,
        "riwaya": req.riwaya,
        **result,
    }


@app.get("/health")
async def health():
    return {"status": "ok"}
