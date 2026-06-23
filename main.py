import asyncio
import json
from fastapi import FastAPI, HTTPException
from fastapi.middleware.cors import CORSMiddleware
from pydantic import BaseModel
import anthropic
import httpx
import os
from dotenv import load_dotenv

load_dotenv()

app = FastAPI(title="المثابة — Quran API")

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_methods=["*"],
    allow_headers=["*"],
)

claude = anthropic.Anthropic(api_key=os.getenv("ANTHROPIC_API_KEY"))
QURAN_API_BASE = "https://api.quran.com/api/v4"


# ── Models ────────────────────────────────────────────────────────────────────

class WordCheckRequest(BaseModel):
    spoken: str          # word recognized by STT
    expected: str        # expected Quran word
    surah: int
    ayah: int
    riwaya: str = "hafs"


class RecitationCheck(BaseModel):
    surah: int
    ayah: int
    riwaya: str
    transcribed_text: str


# ── Helpers ───────────────────────────────────────────────────────────────────

async def _fetch_verse_words(client: httpx.AsyncClient, surah: int, ayah: int) -> dict | None:
    url = (
        f"{QURAN_API_BASE}/verses/by_key/{surah}:{ayah}"
        f"?words=true&word_fields=text_uthmani,text_imlaei"
    )
    try:
        resp = await client.get(url, timeout=12.0)
        if resp.status_code != 200:
            return None
        data = resp.json()
        verse = data.get("verse", {})
        raw_words = verse.get("words", [])
        words = [
            w.get("text_uthmani", "")
            for w in raw_words
            if w.get("char_type_name") == "word"
        ]
        return {
            "surah": surah,
            "ayah": ayah,
            "words": words,
            "text": " ".join(words),
        }
    except Exception:
        return None


# ── Endpoints ─────────────────────────────────────────────────────────────────

@app.get("/surahs")
async def list_surahs():
    async with httpx.AsyncClient() as client:
        resp = await client.get(f"{QURAN_API_BASE}/chapters?language=ar")
        if resp.status_code != 200:
            raise HTTPException(500, "فشل تحميل قائمة السور")
        return resp.json()


@app.get("/verses/range")
async def get_verses_range(surah: int, start_ayah: int, end_ayah: int, riwaya: str = "hafs"):
    """Fetch multiple verses in parallel — core endpoint for real-time recitation."""
    start = max(1, start_ayah)
    end = max(start, end_ayah)

    async with httpx.AsyncClient() as client:
        tasks = [_fetch_verse_words(client, surah, a) for a in range(start, end + 1)]
        results = await asyncio.gather(*tasks)

    verses = [r for r in results if r is not None]
    verses.sort(key=lambda v: v["ayah"])
    return {"verses": verses, "surah": surah, "riwaya": riwaya}


@app.get("/verse")
async def get_verse(surah: int, ayah: int, riwaya: str = "hafs"):
    async with httpx.AsyncClient() as client:
        result = await _fetch_verse_words(client, surah, ayah)
    if result is None:
        raise HTTPException(500, "فشل تحميل الآية")
    return {**result, "riwaya": riwaya}


@app.post("/tajweed/explain")
async def explain_tajweed_error(req: WordCheckRequest):
    """Ask Claude to explain a tajweed error for the blocked word."""
    riwaya_name = "حفص عن عاصم" if req.riwaya == "hafs" else "ورش عن نافع"
    prompt = (
        f"في رواية {riwaya_name}، قرأ المستخدم كلمة «{req.spoken}» "
        f"بدلاً من «{req.expected}» في الآية {req.ayah} من سورة رقم {req.surah}.\n"
        "اشرح الفرق باختصار (جملة واحدة) وقدم نصيحة تجويدية عملية."
    )
    message = claude.messages.create(
        model="claude-sonnet-4-6",
        max_tokens=200,
        messages=[{"role": "user", "content": prompt}],
    )
    return {"explanation": message.content[0].text}


@app.post("/check")
async def check_recitation(req: RecitationCheck):
    """Full verse analysis — used for summary after completing a verse."""
    verse_data = await get_verse(req.surah, req.ayah, req.riwaya)
    expected_text = verse_data["text"]
    riwaya_name = "حفص عن عاصم" if req.riwaya == "hafs" else "ورش عن نافع"

    prompt = f"""أنت متخصص في علم التجويد والقراءات القرآنية.
رواية {riwaya_name} — سورة {req.surah} آية {req.ayah}.

النص المتوقع: {expected_text}
ما تلاه المستخدم: {req.transcribed_text}

أجب بـ JSON فقط:
{{
  "is_correct": true/false,
  "score": 0-100,
  "errors": [{{"wrong_word":"","correct_word":"","error_type":"","rule":"","explanation":""}}],
  "general_feedback": ""
}}"""

    message = claude.messages.create(
        model="claude-sonnet-4-6",
        max_tokens=1024,
        messages=[{"role": "user", "content": prompt}],
    )
    text = message.content[0].text
    try:
        result = json.loads(text[text.find("{"):text.rfind("}") + 1])
    except Exception:
        result = {"is_correct": False, "score": 0, "errors": [], "general_feedback": text}

    return {"expected_text": expected_text, "transcribed_text": req.transcribed_text, **result}


@app.get("/page/{page_number}")
async def get_page_words(page_number: int, riwaya: str = "hafs"):
    """Fetch all words on a Quran page (Madina Mushaf layout, 604 pages)."""
    page_number = max(1, min(604, page_number))
    url = (
        f"{QURAN_API_BASE}/verses/by_page/{page_number}"
        f"?words=true&word_fields=text_uthmani&per_page=50"
        f"&fields=chapter_id,verse_number,verse_key"
    )
    async with httpx.AsyncClient() as client:
        resp = await client.get(url, timeout=15.0)
    if resp.status_code != 200:
        raise HTTPException(500, f"فشل تحميل الصفحة {page_number}")
    data = resp.json()
    verses_out = []
    for verse in data.get("verses", []):
        surah_id = verse.get("chapter_id", 1)
        verse_num = verse.get("verse_number", 1)
        verse_key = verse.get("verse_key", f"{surah_id}:{verse_num}")
        raw_words = verse.get("words", [])
        words = [
            w.get("text_uthmani", "")
            for w in raw_words
            if w.get("char_type_name") == "word"
        ]
        verses_out.append({
            "surah": surah_id,
            "ayah": verse_num,
            "verse_key": verse_key,
            "words": words,
        })
    return {
        "page": page_number,
        "total_pages": 604,
        "riwaya": riwaya,
        "verses": verses_out,
    }


@app.get("/surah/{surah_id}/meta")
async def get_surah_meta(surah_id: int):
    """Get surah metadata including its first/last page in Madina Mushaf."""
    async with httpx.AsyncClient() as client:
        resp = await client.get(
            f"{QURAN_API_BASE}/chapters/{surah_id}?language=ar",
            timeout=10.0,
        )
    if resp.status_code != 200:
        raise HTTPException(404, "السورة غير موجودة")
    ch = resp.json().get("chapter", {})
    pages = ch.get("pages", [1, 1])
    return {
        "id": ch.get("id"),
        "name_arabic": ch.get("name_arabic", ""),
        "name_simple": ch.get("name_simple", ""),
        "verses_count": ch.get("verses_count", 7),
        "first_page": pages[0] if pages else 1,
        "last_page": pages[1] if len(pages) > 1 else (pages[0] if pages else 1),
        "revelation_place": ch.get("revelation_place", "makkah"),
    }


@app.get("/health")
async def health():
    return {"status": "ok", "app": "المثابة"}
