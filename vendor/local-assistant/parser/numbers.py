from __future__ import annotations
import re

UNITS = {"zero":0,"one":1,"two":2,"three":3,"four":4,"five":5,"six":6,
         "seven":7,"eight":8,"nine":9,"ten":10,"eleven":11,"twelve":12,
         "thirteen":13,"fourteen":14,"fifteen":15,"sixteen":16,"seventeen":17,
         "eighteen":18,"nineteen":19}
TENS = {"twenty":20,"thirty":30,"forty":40,"fifty":50,"sixty":60,"seventy":70,
        "eighty":80,"ninety":90}

def words_to_number(text: str) -> int | None:
    words = re.findall(r"[a-z]+", text.lower())
    if not words:
        return None
    total, current = 0, 0
    seen = False
    for w in words:
        if w in UNITS:
            current += UNITS[w]; seen = True
        elif w in TENS:
            current += TENS[w]; seen = True
        elif w == "hundred":
            current = (current or 1) * 100; seen = True
        else:
            return None
    if not seen:
        return None
    total += current
    return total if 0 <= total <= 100_000 else None
