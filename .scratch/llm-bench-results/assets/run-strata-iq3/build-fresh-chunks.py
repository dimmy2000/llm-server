#!/usr/bin/env python3
"""Ticket 06 (strata-iq3): пересборка чанков НА СВЕЖЕМ тексте + архив attempt1.

Зачем: прогон 06-attempt1 (свап-гонка) уже подавал движку strata-iq3 тексты
40000-a..d3 и 120000-a..d3. Strata-контекст-кэш матчит ТЕЛО запроса (salt в
префиксе его не бьёт), поэтому повтор тех же текстов вернул бы cache hit.
Скрипт:
  1) архивирует старые файлы заменяемых слотов в realdata/chunks-attempt1/ и
     ПЕРЕНОСИТ их диапазоны в manifest (иначе курсора по книгам потеряли бы
     уже использованный текст, и следующий билд взял бы его повторно);
  2) строит те же слоты из текста, который ни один движок бенча не видел
     (хвосты локальных книг + новые книги из Standard Ebooks, см. realdata/src);
  3) считает размер токенизатором ЦЕЛЕВОГО движка (MODEL; для 06 = strata-iq3)
     и в конце вытесняет собранные тексты из контекст-кэша этого движка
     одноразовым запросом-филлером (--no-flush выключает).

Логика курсоров/резов/допусков — как в make-chunks.py (границы по абзацам,
отклонение >5 % = ошибка). Отличие: hi-граница зонда ограничена контекстом
движка (131072 у iq3), поэтому она не может быть 1.8x таргета, как у qwen.

  URL=http://localhost:8080 MODEL=strata-iq3 python3 build-fresh-chunks.py \
    --plan '120000:a,b,c,d1,d2,d3;40000:a,b,c,d1,d2,d3,0-3,100-105,200,201'
"""
import argparse
import hashlib
import json
import os
import re
import sys
import time
import urllib.error
import urllib.request

ROOT = os.path.dirname(os.path.abspath(__file__))
GUTENBERG = ["war_and_peace", "moby_dick", "dracula", "monte_cristo",
             "don_quixote", "les_miserables"]


class Overflow(Exception):
    """Зонд длиннее контекста движка."""


def strip_gutenberg(t):
    m = re.search(r"\*\*\* ?START OF (THE|THIS) PROJECT GUTENBERG.*?\*\*\*", t)
    if m:
        t = t[m.end():]
    m = re.search(r"\*\*\* ?END OF (THE|THIS) PROJECT GUTENBERG.*?\*\*\*", t)
    if m:
        t = t[:m.start()]
    return t.strip()


def make_counter(url, model):
    def count(text):
        body = json.dumps({"model": model,
                           "messages": [{"role": "user", "content": text}]}).encode()
        req = urllib.request.Request(
            f"{url}/v1/messages/count_tokens", data=body,
            headers={"Content-Type": "application/json"})
        for attempt in range(5):
            try:
                with urllib.request.urlopen(req, timeout=300) as r:
                    return json.load(r)["input_tokens"]
            except urllib.error.HTTPError as e:
                if e.code in (400, 413):
                    raise Overflow(
                        f"HTTP {e.code}: {e.read(200).decode('utf-8', 'replace')}")
                if attempt == 4:
                    raise
                print(f"  count_tokens retry {attempt+1}: {e}", flush=True)
                time.sleep(3)
            except Exception as e:
                if attempt == 4:
                    raise
                print(f"  count_tokens retry {attempt+1}: {e}", flush=True)
                time.sleep(3)
    return count


def flush_cache(url, model, count, target_tokens):
    """Вытеснить собранные чанки из контекст-кэша ЦЕЛЕВОГО движка."""
    import random
    words = ("alpha bravo charlie delta echo foxtrot golf hotel india juliet "
             "kilo lima mike november oscar papa quebec romeo sierra tango "
             "uniform victor whiskey xray yankee zulu").split()
    r = random.Random(99)
    pool = " ".join(r.choice(words) for _ in range(240_000))
    probe = pool[:150_000]
    cpt = 150_000 / max(count(probe), 1)
    txt = pool[:int(target_tokens * 0.97 * cpt)]
    n = count(txt)
    if n < target_tokens:
        txt = pool[:int(len(txt) * target_tokens * 0.98 / max(n, 1))]
    body = json.dumps({"model": model,
                       "messages": [{"role": "user", "content": f"[flush] {txt}"}],
                       "max_tokens": 1}).encode()
    req = urllib.request.Request(f"{url}/v1/chat/completions", data=body,
                                 headers={"Content-Type": "application/json"})
    t0 = time.time()
    try:
        with urllib.request.urlopen(req, timeout=1800) as resp:
            resp.read()
        print(f"engine context cache flushed ({model}, unrelated "
              f"{count(txt):,}-token request, {time.time()-t0:.0f} s)", flush=True)
    except Exception as e:
        print(f"WARN: flush failed ({e}) — первый прогон может дать cache hit")


def parse_plan(spec):
    plan = []
    for part in spec.split(";"):
        depth, slots = part.split(":")
        parsed = []
        for s in slots.split(","):
            s = s.strip()
            if not s:
                continue
            if "-" in s and s.split("-")[0].isdigit():
                a, b = s.split("-")
                parsed.extend(str(x) for x in range(int(a), int(b) + 1))
            else:
                parsed.append(s)
        plan.append((int(depth), parsed))
    return plan


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--url", default=os.environ.get("URL", "http://localhost:8080"))
    ap.add_argument("--model", default=os.environ.get("MODEL"))
    ap.add_argument("--data-dir", default=os.environ.get("DATA_DIR",
                      os.path.join(os.path.dirname(ROOT), "llm-bench", "realdata")))
    ap.add_argument("--plan", required=True,
                    help="'120000:a,b,c,d1,d2,d3;40000:a,b,c,d1,d2,d3,0-3,100-105,200,201'")
    ap.add_argument("--archive-dir", default="chunks-attempt1")
    ap.add_argument("--tol", type=float, default=0.005)
    ap.add_argument("--flush-tokens", type=int, default=128000)
    ap.add_argument("--no-flush", action="store_true")
    args = ap.parse_args()

    url = args.url.rstrip("/")
    model = args.model
    if not model:
        with urllib.request.urlopen(f"{url}/v1/models", timeout=10) as r:
            model = json.load(r)["data"][0]["id"]
    data = args.data_dir
    man_path = os.path.join(data, "manifest.json")
    manifest = json.load(open(man_path, encoding="utf-8")) if os.path.exists(man_path) else {}
    count = make_counter(url, model)

    books = {}
    for fn in sorted(os.listdir(os.path.join(data, "src"))):
        if fn.endswith(".txt"):
            books[fn[:-4]] = strip_gutenberg(
                open(os.path.join(data, "src", fn), encoding="utf-8",
                     errors="replace").read())
    print(f"model {model}  url {url}")
    print("books: " + ", ".join(f"{b} {len(t):,}" for b, t in sorted(books.items())))

    plan = parse_plan(args.plan)

    # 1) архив заменяемых слотов: файл -> chunks-attempt1/, диапазон -> manifest
    adir = os.path.join(data, args.archive_dir)
    os.makedirs(adir, exist_ok=True)
    archived = 0
    for depth, slots in plan:
        for slot in slots:
            fn = f"{depth}-{slot}.txt"
            src = os.path.join(data, "chunks", fn)
            if not os.path.exists(src):
                continue
            text = open(src, encoding="utf-8").read()
            hit = next(((b, books[b].find(text[:2000])) for b in books
                        if books[b].find(text[:2000]) != -1), None)
            meta = dict(manifest.pop(f"chunks/{fn}", None) or {})
            meta.update({"target_tokens": depth, "chars": len(text),
                         "sha256": hashlib.sha256(text.encode()).hexdigest()[:16]})
            if hit:
                b, pos = hit
                meta["book"] = b
                meta["char_start"] = pos
            if not meta.get("tokens"):
                try:
                    meta["tokens"] = count(text)
                except Overflow as e:
                    meta["tokens"] = None
                    meta["tokens_note"] = f"count overflow: {e}"
            meta["archived_by"] = "build-fresh-chunks.py (06-attempt1, swap race)"
            manifest[f"{args.archive_dir}/{fn}"] = meta
            os.rename(src, os.path.join(adir, fn))
            archived += 1
    json.dump(manifest, open(man_path, "w"), indent=1)
    print(f"archived {archived} чанков -> {adir}/ (диапазоны перенесены в manifest)")

    # 2) курсоры: за край ВСЕГО учтённого (файлы на диске + manifest, см. make-chunks)
    cursor = {b: 0 for b in books}
    used = 0
    for fn in sorted(os.listdir(os.path.join(data, "chunks"))):
        if not fn.endswith(".txt"):
            continue
        text = open(os.path.join(data, "chunks", fn), encoding="utf-8").read()
        hit = next(((b, books[b].find(text[:2000])) for b in books
                    if books[b].find(text[:2000]) != -1), None)
        if hit:
            b, pos = hit
            cursor[b] = max(cursor[b], pos + len(text))
            used += 1
    for key, meta in manifest.items():
        b = meta.get("book")
        if b in cursor and meta.get("char_start") is not None:
            cursor[b] = max(cursor[b], meta["char_start"] + meta.get("chars", 0))
    print(f"cursors ({used} чанков на диске учтено): "
          + " ".join(f"{b}@{cursor[b]:,}" for b in sorted(books)))

    def cut_at(t, pos, brk):
        ln = t.find(brk, pos)
        return ln + len(brk) if ln != -1 else None

    def bisect(t, start, target, brk, lo, hi):
        best = None
        for _ in range(18):
            mid = (lo + hi) // 2
            end = cut_at(t, mid, brk) or hi
            try:
                n = count(t[start:end])
            except Overflow:
                hi = mid - 1
                if hi <= lo:
                    break
                continue
            if best is None or abs(n - target) < abs(best[1] - target):
                best = (end, n)
            if abs(n - target) <= target * args.tol:
                break
            if n < target:
                lo = mid + 1
            else:
                hi = mid - 1
            if hi <= lo:
                break
        return best

    def build(book, target):
        t = books[book]
        start = cut_at(t, cursor[book], "\n\n")
        if start is None or start >= len(t) - 1000:
            return ("short", None)          # книга кончилась
        probe_end = min(start + 100_000, len(t) - 1)
        if probe_end - start < 1000:
            return ("short", None)
        cpt = (probe_end - start) / max(count(t[start:probe_end]), 1)
        if len(t) - start < target * 1.15 * cpt:
            return ("short", None)
        # hi-граница зонда держим внутри контекста движка: ~1.05 таргета токенов
        hi = n_hi = None
        for factor in (1.05, 1.03, 1.01, 1.07, 1.09):
            cand = min(len(t) - 1, int(start + target * factor * cpt))
            end = cut_at(t, cand, "\n\n") or cand
            if end <= start:
                continue
            try:
                n_hi = count(t[start:end])
            except Overflow:
                continue
            hi = end
            if n_hi >= target * 1.005:
                break
        if hi is None or n_hi < target * 0.99:
            return ("nowindow", (hi, n_hi))  # текст есть, но таргет не влезает в окно
        lo = max(start + 1, start + int(target * 0.9 * cpt))
        end = n = None
        for brk in ("\n\n", "\n", ""):
            end, n = bisect(t, start, target, brk, lo, hi)
            if abs(n - target) <= target * 0.02:
                return ("ok", (t[start:end], start, n))
        return ("coarse", (end, n))

    def save(depth, slot, book, text, cstart, ntok):
        manifest[f"chunks/{depth}-{slot}.txt"] = {
            "target_tokens": depth, "tokens": ntok, "chars": len(text),
            "book": book, "char_start": cstart,
            "sha256": hashlib.sha256(text.encode()).hexdigest()[:16],
            "built_by": "build-fresh-chunks.py (fresh text, ticket 06 strata-iq3)",
        }
        json.dump(manifest, open(man_path, "w"), indent=1)

    total = sum(len(slots) for _, slots in plan)
    done = 0
    worst = 0.0
    for depth, slots in plan:
        for slot in slots:
            done += 1
            picked = None
            for book in sorted(books, key=lambda b: -(len(books[b]) - cursor[b])):
                if len(books[book]) - cursor[book] < depth * 4:
                    continue
                kind, payload = build(book, depth)
                if kind == "ok":
                    picked = (book, payload)
                    break
                if kind == "short":
                    cursor[book] = len(books[book])
                    print(f"  {book}: остатка не хватает, беру следующую", flush=True)
                elif kind == "nowindow":
                    print(f"  {book}: таргет {depth} не влезает в окно кэша "
                          f"(hi={payload[1]}), беру следующую", flush=True)
                elif picked is None or abs(payload[1] - depth) < abs(picked[1][1] - depth):
                    picked = (book, payload)   # coarse: помним, но ищем лучше
            if picked is None:
                sys.exit(f"не хватает уникального текста для слота {depth}-{slot}")
            book, payload = picked
            if len(payload) == 3 and isinstance(payload[0], str):
                text, cstart, ntok = payload
            else:
                end, ntok = payload
                cstart = cut_at(books[book], cursor[book], "\n\n")
                text = books[book][cstart:end]
            off = abs(ntok - depth) / depth
            worst = max(worst, off)
            if off > 0.05:
                sys.exit(f"чанк {depth}-{slot} вышел {ntok} токенов при таргете "
                         f"{depth} (>5 %) — сравнивать глубину нельзя")
            cursor[book] = cstart + len(text)
            open(os.path.join(data, "chunks", f"{depth}-{slot}.txt"), "w",
                 encoding="utf-8").write(text)
            save(depth, slot, book, text, cstart, ntok)
            flag = f"  off {off*100:+.2f}%" if off > args.tol else ""
            origin = "NEW" if book not in GUTENBERG else "tail"
            print(f"{depth}-{slot:<5} {ntok:>7,} tok  book={book:<20} {origin:<4} "
                  f"chars@{cstart:,}  ({done}/{total}){flag}", flush=True)
    print(f"manifest: {man_path}  худшее отклонение по глубине: {worst*100:.2f} %")
    print("cursor после сборки: " + " ".join(f"{b}@{cursor[b]:,}" for b in sorted(books)))

    if not args.no_flush:
        flush_cache(url, model, count, args.flush_tokens)


if __name__ == "__main__":
    main()
