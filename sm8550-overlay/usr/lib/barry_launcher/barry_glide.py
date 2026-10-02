"""barry_glide: glide typing for Barry Launcher's on-screen keyboard.

A glide is the finger's path over the letter keys. A word's ideal path runs
straight from key centre to key centre through its letters; the decoder
scores each dictionary word by how far the glide runs from that path (where
it went) and how unlike it is once both are scaled to the same size (what
it looked like), plus how common the word is, and returns the best few.

Candidates are the words that start near where the finger went down and end
near where it lifted, whose every letter the glide passed close to. Plain
Python: the filters leave a few hundred words to score.

Coordinates are the keyboard's own (any unit); keys maps each letter to its
key centre and key_size is a key's width in the same unit.
"""
from __future__ import annotations

import math

N = 32  # points both paths are resampled to
NEAR = 1.1  # key widths: how close the start and end must be to a word's first and last key
PASS = 1.0  # key widths: how close the glide must come to each of its letters
LOC_SIGMA = 0.45  # key widths
SHAPE_SIGMA = 0.22  # of the path's size
LEVEL_PRIOR = {10: 0.0, 20: -0.75, 35: -1.65, 40: -2.25}


def path_length(pts: list) -> float:
    return sum(math.dist(a, b) for a, b in zip(pts, pts[1:]))


def resample(pts: list, n: int = N) -> list:
    """n points evenly spaced along the path."""
    if len(pts) == 1:
        return [pts[0]] * n
    total = path_length(pts)
    if total == 0:
        return [pts[0]] * n
    step = total / (n - 1)
    out = [pts[0]]
    i, carry = 1, 0.0
    a = pts[0]
    while len(out) < n - 1 and i < len(pts):
        b = pts[i]
        seg = math.dist(a, b)
        if carry + seg >= step and seg > 0:
            t = (step - carry) / seg
            a = (a[0] + (b[0] - a[0]) * t, a[1] + (b[1] - a[1]) * t)
            out.append(a)
            carry = 0.0
        else:
            carry += seg
            a = b
            i += 1
    while len(out) < n:
        out.append(pts[-1])
    return out


def normalized(pts: list) -> list:
    """Centred on its centroid and scaled to a unit bounding box."""
    cx = sum(p[0] for p in pts) / len(pts)
    cy = sum(p[1] for p in pts) / len(pts)
    w = max(p[0] for p in pts) - min(p[0] for p in pts)
    h = max(p[1] for p in pts) - min(p[1] for p in pts)
    size = max(w, h) or 1.0
    return [((p[0] - cx) / size, (p[1] - cy) / size) for p in pts]


def mean_distance(a: list, b: list) -> float:
    return sum(math.dist(p, q) for p, q in zip(a, b)) / len(a)


def display(word: str) -> str:
    """How a word is typed: "i'm" as "I'm"."""
    return "I" + word[1:] if word == "i" or word.startswith("i'") else word


class Decoder:
    def __init__(self, words_path: str) -> None:
        self.words: list[tuple[str, str, int]] = []  # (word, its letter keys, level)
        self.by_ends: dict[tuple[str, str], list[int]] = {}
        with open(words_path, encoding="utf-8") as fh:
            for line in fh:
                if line.startswith("#") or not line.strip():
                    continue
                word, level = line.split()
                # Matched on its lower-case letters, typed as written ("SteamOS").
                plain = word.replace("'", "").lower()
                letters = "".join(c for i, c in enumerate(plain) if i == 0 or c != plain[i - 1])
                if len(letters) < 2:
                    continue
                self.by_ends.setdefault((letters[0], letters[-1]), []).append(len(self.words))
                self.words.append((word, letters, int(level)))
        self._ideal: dict[tuple, tuple] = {}

    def _ideal_path(self, letters: str, keys: dict, layout: tuple) -> tuple:
        cached = self._ideal.get((layout, letters))
        if cached is None:
            pts = [keys[c] for c in letters]
            rs = resample(pts)
            cached = (pts, path_length(pts), rs, normalized(rs))
            self._ideal[(layout, letters)] = cached
        return cached

    def decode(self, path: list, keys: dict, key_size: float, limit: int = 4) -> list[str]:
        """The likeliest words for a glide, best first; [] for a tap or no match."""
        path = [tuple(p) for p in path]
        if len(path) < 2 or path_length(path) < 0.8 * key_size:
            return []
        keys = {c: tuple(xy) for c, xy in keys.items() if len(c) == 1 and c.isalpha()}
        layout = tuple(sorted(keys.items()))
        if len(self._ideal) > 20000:
            self._ideal.clear()

        def near(pt):
            close = [c for c, xy in keys.items() if math.dist(pt, xy) <= NEAR * key_size]
            return close or [min(keys, key=lambda c: math.dist(pt, keys[c]))]

        starts, ends = near(path[0]), near(path[-1])
        rp = resample(path)
        np_ = normalized(rp)
        lp = path_length(path)
        # How close the glide comes to each key, once per glide.
        dense = resample(path, 64)
        gap = {c: min(math.dist(xy, q) for q in dense) / key_size for c, xy in keys.items()}
        scored = []
        for s in starts:
            for e in ends:
                for idx in self.by_ends.get((s, e), ()):
                    word, letters, level = self.words[idx]
                    # Every letter must lie near the glide.
                    if any(gap.get(c, PASS + 1) > PASS for c in letters):
                        continue
                    pts, li, ri, ni = self._ideal_path(letters, keys, layout)
                    if li > 0 and not (0.5 <= lp / li <= 2.5):
                        continue
                    loc = mean_distance(rp, ri) / key_size
                    shape = mean_distance(np_, ni)
                    score = (-(loc / LOC_SIGMA) ** 2 - (shape / SHAPE_SIGMA) ** 2
                             + LEVEL_PRIOR.get(level, -3.0))
                    scored.append((score, word))
        scored.sort(reverse=True)
        out = []
        for _, word in scored:
            w = display(word)
            if w not in out:
                out.append(w)
            if len(out) == limit:
                break
        return out


# Autocorrect: the same dictionary, for tapped words.

# QWERTY key centres in key widths (rows offset as on the keyboard), for
# how near a wrong key was to the right one.
QWERTY = {c: (x + off, y) for y, (row, off) in enumerate((("qwertyuiop", 0.0), ("asdfghjkl", 0.5), ("zxcvbnm", 1.5)))
          for x, c in enumerate(row)}
NEIGHBOUR = 1.5  # key widths: a slip onto a neighbouring key
COST_NEAR, COST_FAR, COST_SWAP, COST_EXTRA, COST_DOUBLE, COST_MISSING = 0.45, 1.0, 0.6, 0.9, 0.4, 0.9
# Tuned on simulated typos against rarer real words (SCOWL 50) left as
# typed: about 4 in 5 typos fixed, under 1 in 25 such words changed.
MAX_COST = 0.9  # the most a correction may cost
COST_WEIGHT = 4.0  # per unit of cost, against LEVEL_PRIOR
MARGIN = 2.5  # how far ahead of the runner-up the winner must be
CORRECT_TO_LEVEL = 20  # only ever correct to a common word
# Classic slips a tie between two words would otherwise leave alone.
FIXED = {"teh": "the", "hte": "the", "adn": "and", "nad": "and", "taht": "that", "thta": "that",
         "waht": "what", "wiht": "with", "becuase": "because", "beacuse": "because",
         "recieve": "receive", "recieved": "received", "thier": "their", "freind": "friend",
         "freinds": "friends", "wierd": "weird", "untill": "until", "definately": "definitely",
         "seperate": "separate", "occured": "occurred", "alot": "a lot", "im": "I'm"}


# Endings that make a known word into another real one, and what the stem
# may have lost ("hoping" from "hope", "tried" from "try", "stopped").
INFLECTIONS = (("s", ("",)), ("es", ("", "e")), ("ies", ("y",)), ("ied", ("y",)),
               ("ed", ("", "e")), ("ing", ("", "e")), ("er", ("", "e")), ("ers", ("", "e")),
               ("ly", ("",)), ("ness", ("",)), ("able", ("", "e")))


def sub_cost(a: str, b: str) -> float:
    pa, pb = QWERTY.get(a), QWERTY.get(b)
    if pa and pb and math.dist(pa, pb) <= NEIGHBOUR:
        return COST_NEAR
    return COST_FAR


def typo_cost(typed: str, word: str) -> float:
    """Damerau-Levenshtein with keyboard-aware costs."""
    n, m = len(typed), len(word)
    d = [[0.0] * (m + 1) for _ in range(n + 1)]
    for i in range(1, n + 1):
        d[i][0] = i * COST_EXTRA
    for j in range(1, m + 1):
        d[0][j] = j * COST_MISSING
    for i in range(1, n + 1):
        for j in range(1, m + 1):
            a, b = typed[i - 1], word[j - 1]
            best = d[i - 1][j - 1] + (0.0 if a == b else sub_cost(a, b))
            # An extra letter: a doubled one, or a slip that hit two keys.
            extra = COST_DOUBLE if (i > 1 and typed[i - 2] == a) or (j and word[j - 1] == a) else COST_EXTRA
            best = min(best, d[i - 1][j] + extra)
            missing = COST_DOUBLE if j > 1 and word[j - 2] == b else COST_MISSING
            best = min(best, d[i][j - 1] + missing)
            if i > 1 and j > 1 and a == word[j - 2] and typed[i - 2] == b:
                best = min(best, d[i - 2][j - 2] + COST_SWAP)
            d[i][j] = best
    return d[n][m]


def deletes(word: str) -> set:
    return {word[:i] + word[i + 1:] for i in range(len(word))}


class Corrector:
    """Corrections and completions for tapped words. Words the user keeps
    (by undoing a correction) count as known from then on."""

    def __init__(self, decoder: Decoder, personal_path: str | None = None) -> None:
        self.level: dict[str, int] = {}
        self.typed: dict[str, str] = {}  # lower-case -> as typed ("steamos" -> "SteamOS")
        for word, _letters, level in decoder.words:
            plain = word.lower()
            self.level.setdefault(plain, level)
            self.typed.setdefault(plain, word)
        for w in ("a", "i"):
            self.level.setdefault(w, 10)
        self.typed.setdefault("i", "I")
        # Contractions typed without the apostrophe ("dont"), unless that is
        # a word itself ("cant", "wont", "its", "well").
        self.contractions = {}
        for plain, typed in self.typed.items():
            if "'" in plain:
                bare = plain.replace("'", "")
                if bare not in self.level:
                    self.contractions[bare] = typed
        # Each word under itself and with each one letter removed: a typo
        # one edit away shares a key with the word it meant.
        self.index: dict[str, list] = {}
        for plain in self.level:
            if "'" in plain:
                continue
            for key in deletes(plain) | {plain}:
                self.index.setdefault(key, []).append(plain)
        self.sorted = sorted(self.level)
        self.personal_path = personal_path
        self.personal: set[str] = set()
        if personal_path:
            try:
                with open(personal_path, encoding="utf-8") as fh:
                    self.personal = {l.strip().lower() for l in fh if l.strip()}
            except OSError:
                pass

    def known(self, word: str) -> bool:
        w = word.lower()
        if w in self.level or w.replace("'", "") in self.level or w in self.personal:
            return True
        # Forms the list leaves out ("couplings"): a known word plus an ending.
        for end, back in INFLECTIONS:
            if w.endswith(end) and len(w) - len(end) >= 3:
                stem = w[: len(w) - len(end)]
                if any(stem + b in self.level for b in back):
                    return True
        return False

    def keep(self, word: str) -> None:
        """Never correct this word again."""
        w = word.lower()
        if w in self.personal or not self.personal_path:
            return
        self.personal.add(w)
        try:
            with open(self.personal_path, "a", encoding="utf-8") as fh:
                fh.write(w + "\n")
        except OSError:
            pass

    def correct(self, word: str) -> str | None:
        """The word meant, when a tapped word is a clear typo; else None.

        Leaves alone: known words, words of one or two letters, and anything
        with digits, symbols or capitals past the first letter."""
        if not word.isalpha() or not word.isascii() or any(c.isupper() for c in word[1:]):
            return None
        plain = word.lower()
        if plain in self.personal:
            return None
        fixed = FIXED.get(plain) or self.contractions.get(plain)
        if fixed:
            return fixed[0].upper() + fixed[1:] if word[0].isupper() else fixed
        if len(word) < 3 or self.known(word):
            return None
        candidates = set()
        for key in deletes(plain) | {plain}:
            candidates.update(self.index.get(key, ()))
        scored = []
        for cand in candidates:
            cost = typo_cost(plain, cand)
            if cost <= MAX_COST:
                scored.append((-COST_WEIGHT * cost + LEVEL_PRIOR.get(self.level[cand], -3.0), cand))
        if not scored:
            return None
        scored.sort(reverse=True)
        if len(scored) > 1 and scored[0][0] - scored[1][0] < MARGIN:
            return None
        if self.level[scored[0][1]] > CORRECT_TO_LEVEL:
            return None
        best = self.typed[scored[0][1]]
        # Keep a capital the user typed ("Teh" -> "The").
        if word[0].isupper():
            best = best[0].upper() + best[1:]
        return best

    def near(self, word: str, limit: int = 3) -> list[str]:
        """Words one slip away ("dig" -> dog, dug), likeliest first."""
        plain = word.lower()
        if len(plain) < 2 or not plain.isalpha():
            return []
        candidates = set()
        for key in deletes(plain) | {plain}:
            candidates.update(self.index.get(key, ()))
        candidates.discard(plain)
        scored = []
        for cand in candidates:
            cost = typo_cost(plain, cand)
            if cost <= MAX_COST:
                scored.append((-COST_WEIGHT * cost + LEVEL_PRIOR.get(self.level[cand], -3.0), cand))
        scored.sort(reverse=True)
        out = []
        for _, cand in scored[:limit]:
            t = self.typed[cand]
            out.append(t[0].upper() + t[1:] if word[0].isupper() else t)
        return out

    def suggest(self, word: str, limit: int = 3) -> list[str]:
        """The strip's words while a word is typed: for a real word ("dig")
        the words one slip away first, then completions; for a word still
        being typed ("keyb") completions first."""
        near, more = self.near(word, limit), self.complete(word, limit)
        first, then = (near, more) if self.known(word) or not more else (more, near)
        # Two of the first kind and one of the other, when there are both.
        out = []
        for w in first[: limit - 1] + then[:1] + first[limit - 1:] + then[1:]:
            if w.lower() != word.lower() and w not in out:
                out.append(w)
        return out[:limit]

    def complete(self, prefix: str, limit: int = 3) -> list[str]:
        """Common words starting with prefix (two letters or more)."""
        p = prefix.lower()
        if len(p) < 2 or not p.isalpha():
            return []
        import bisect
        lo = bisect.bisect_left(self.sorted, p)
        hi = bisect.bisect_left(self.sorted, p + "￿")
        found = sorted(self.sorted[lo:hi], key=lambda w: (self.level[w], len(w)))
        out = []
        for w in found:
            if w == p or "'" in w:
                continue
            t = self.typed[w]
            out.append(prefix[0] + t[1:] if prefix[0].isupper() else t)
            if len(out) == limit:
                break
        return out
