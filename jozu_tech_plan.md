# Jozu — Technical Plan: Plan A (Thin Vertical Slice) + Plan B Extensions

Status: Draft v1 — **Plan A implemented (see "Implementation status" below)**
Based on: `jozu_concept.md`

This plan describes a first-pass MVP ("Plan A") that proves the core learning loop
end-to-end, with explicit notes on how each part extends to the full scope described
in concept section 22 ("Plan B").

---

## Implementation status (for other agents)

Everything in this section is authoritative state as of 2026-09. The Plan A
vertical slice is implemented end-to-end and green (79 RSpec examples, RuboCop
clean, Brakeman / bundler-audit / importmap-audit clean). See the table in §15
for the Plan B delta.

### Environment / toolchain (non-obvious)

- **Ruby 4.0.6** (Homebrew), **Rails 8.1.3.1**, **PostgreSQL 17** (Homebrew).
  `bin/rails` lives at `/opt/homebrew/lib/ruby/gems/4.0.0/bin`; prefix commands
  with `export PATH="/opt/homebrew/opt/ruby/bin:/opt/homebrew/lib/ruby/gems/4.0.0/bin:$PATH"`.
- **`json` is pinned to `~> 2.7`** in the Gemfile. Rails 8.1.3's
  `ActiveSupport::JSON.decode` passes a positional options hash to `JSON.parse`;
  json ≥ 3.0 requires keyword args and broke `db:schema:dump`. Do not "upgrade" json.
- The system Ruby (2.6) predates Rails 8; it is not used. The RSpec suite and
  system tests run on the Homebrew Ruby.
- Test environment uses `config.cache_store = :memory_store` (not the default
  `:null_store`) because `Learning::QuestionStore` verifies answers via the cache.
- System tests (Capybara + Selenium headless Chrome) work with Rails' pinned/
  shared-connection mechanism — data created in `before` hooks is visible to the
  in-process server. Do not switch the test DB strategy to truncation.
- **Tailwind v4 wiring (do not revert):** the layout uses
  `stylesheet_link_tag "tailwind"` (NOT the default `:app`), the CSS entry file is
  `app/assets/tailwind/application.css` (contains `@import "tailwindcss";` plus
  custom `.kanji-prompt` and touch-action rules), and the compiled output lives in
  `app/assets/builds/tailwind.css`. There is **no auto-rebuild**: running
  `bin/rails server` serves whatever was last built, so after view/CSS changes you
  must run `bin/rails tailwindcss:build`, or run `bin/dev` (foreman: puma +
  `tailwindcss:watch`). A stale build produced an unstyled page — that was the
  "unstyled HTML" symptom. `app/assets/stylesheets/application.css` was deleted.

### What is implemented

- **Schema (§3)** — all tables: `kanji`, `readings`, `words`, `word_kanji`,
  `sentences`, `sentence_words`, `user_kanji`, `user_words`, `reviews`
  (polymorphic, immutable), `exposures`. Note `kanji` / `word_kanji` are the
  actual table names (models override `self.table_name`); all `t.references :kanji`
  use `foreign_key: { to_table: :kanji }`.
- **Domain core (M2)** — `app/services/learning/`: `Config` (all tunables),
  `MasteryCalculator` (per-dimension deltas per §5.2), `Scheduler` (fsrs 0.9.2
  adapter, grade mapping per §6), `PriorityCalculator`, `LeverageCalculator`,
  `ExposureRecorder`. All hot-path services take an injectable `now:`.
- **Question engine (M3)** — `NextReview`, `QuestionGenerator`, `DistractorSelector`
  (plausible-by-construction pools), `SentenceSelector` (target-kanji-is-the-difficult-part),
  `Segmentation::LongestMatch` trie in `lib/segmentation`.
- **Quiz UX (M4)** — home summary, Turbo-frame quiz with a Stimulus controller
  (response-time measurement, feedback, confidence row), POST-driven review flow,
  session-end tally, `question_token` idempotency. `Learning::QuestionStore`
  (Rails.cache) holds issued questions for tamper-proof answer verification.
- **Diagnostic (M5)** — `Learning::Diagnostic` + `DiagnosticController`: adaptive
  kana→kanji staircase across 3 frequency bands, batch-seeds `user_kanji` /
  `user_words`, records answers as reviews. Home shows a "Take the diagnostic" CTA
  until the user has state.
- **Progress (M6)** — `Learning::Progress` + progress view (top-N coverage,
  Known/Learning/Weak/Unknown buckets, words unlocked).
- **Import pipeline (M1 tooling)** — `lib/imports/corpus_importer.rb`,
  `lib/generation/validation.rb` (§4.3 gates), `lib/generation/sentence_generator.rb`
  (LLM → versioned JSONL). Rake tasks in `lib/tasks/jozu.rake`:
  `jozu:import`, `jozu:generate_sentences`, `jozu:stats`.
- **Seeds** — `db/seeds.rb`: demo user + tiny curated corpus (107 kanji,
  111 words, 192 sentences, word_kanji + sentence_words linked via longest-match).
- **CI** — `.github/workflows/ci.yml` updated for RSpec; lint + security scans +
  test + system-test jobs; headless Chrome installed in the system-test job.

### Decisions / deviations from the plan (read before editing)

- **New-kanji cap is per UTC day, not per session** (§8.1 "limit 3 per session").
  `NextReview` stops introducing when 3 `user_kanji` rows were created today
  (`created_at.all_day`). A session therefore ends after the daily allotment.
  `Learning::Session.new_kanji_count` uses the same rule.
- **The quiz is POST-driven.** The next question comes from the `POST /reviews`
  turbo_stream response; `GET /sessions/next` is only the entry point.
  Controllers respond to **both** `turbo_stream` and `html` formats (Turbo's
  frame submission sends an HTML Accept header in some flows; the html fallback
  returns the bare `turbo-frame` partial).
- **Confidence buttons are native submit buttons** (`name="confidence" value="…"`),
  not JS-driven. A JS `requestSubmit()` did not reliably fire Turbo's interception;
  native submits do.
- **`Learning::Question` is a `Data` class** carrying `presented_at`; it is stored
  in `QuestionStore` keyed by token.
- **The onboarding diagnostic is flashcard-based, not kana→kanji multiple-choice.**
  `Learning::Diagnostic` still samples adaptively across frequency bands, but each
  item is a `Learning::Flashcard` (front = kanji word, back = reading) shown with a
  tap-to-reveal card; the learner self-assesses (Knew it / Guessed / Didn't know),
  which maps to `correct` + `confidence` for band adjustment and state seeding.
  Diagnostic reviews use `question_type: "kanji_recognition"` (added to
  `Review::QUESTION_TYPES`). The stimulus controller is
  `app/javascript/controllers/flashcard_controller.js`.
- **`fsrs` 0.9.2 API**: `Fsrs::Card.new` takes no keyword args; use
  `Scheduler#repeat(card, now_utc)` → hash of `Rating => SchedulingInfo` (card +
  review_log). All card state round-trips through `srs_state` jsonb.
- **`ExposureRecorder.record!`** writes both a `kind: "review"` and (when a
  sentence is shown) a `kind: "sentence"` row; `SentenceSelector` uses the
  sentence rows for dedupe/novelty.
- `Learning.config` (module singleton methods) lives in `app/services/learning.rb`
  (Zeitwerk loads the namespace file on any `Learning` reference); `Config` is in
  `config.rb`. Don't move the module methods back into `config.rb` — they were
  never autoloaded from there.

### Running it

```sh
bin/rails db:drop db:create db:migrate db:seed
bin/dev                                  # recommended: puma + tailwind watch
bin/rails server -b 0.0.0.0 -p 3001      # plain server (rebuild CSS manually first)
bundle exec rspec && bundle exec rubocop
```

**Mobile access over Tailscale**: the dev server runs on `0.0.0.0:3001`
(port 3000 is taken by an unrelated node process on this machine). Reachable at
`http://100.113.17.95:3001` or `http://stefans-macbook-pro.tailc95d26.ts.net:3001`.
`config/environments/development.rb` adds `*.ts.net`, the Tailscale IP, and the
raw hostname to `config.hosts` (Rails Host Authorization blocks unknown hosts).
If the Tailscale IP changes, update that file (or set `DEV_ALLOWED_HOST`).

### Known limitations / next steps

- Only the 3 Plan A question types exist; `reading_strength` is seeded but not
  drilled (§5.1). No kanji→reading questions yet.
- `sentence_to_kanji` can run dry when the corpus lacks a valid sentence for a
  kanji; `NextReview` falls back to the other question type.
- Importers read documented TSV/JSONL formats but the full `japanese-language-data`
  bank is **not vendored** — `jozu:import` skips missing files gracefully.
- Plan B work: real auth, SolidQueue ingestion, Sudachi/mecab, FSRS parameter
  optimization, passive-exposure weighting, reading stream, offline quiz queue.

---

## 0. Guiding principles

1. **Prove the loop, not the scale.** Plan A is a thin vertical slice: a single user
   can complete a session of real, algorithmically-chosen questions and see progress.
2. **Domain logic lives outside controllers** (concept §24). All `Learning::*` services
   are plain Ruby objects, independently unit-testable, with no framework dependencies
   in the hot path.
3. **Prefer known-good building blocks.** Use the `fsrs` gem instead of writing an
   interval formula; use licensed corpora for kanji/vocabulary and validated LLM
   generation for sentences instead of building a linguistic ontology.
4. **Keep the full domain model's shape.** Even where Plan A simplifies behaviour, the
   schema keeps the columns/tables Plan B needs, so extending is additive, not a rewrite.

---

## 1. Stack decisions

| Concern | Decision | Rationale |
|---|---|---|
| Framework | Ruby on Rails 8 (API-friendly, default propshaft/turbo) | Concept §24; fastest path to a Hotwire PWA |
| Database | PostgreSQL | Concept §4; jsonb for SRS card state |
| UI | Hotwire (Turbo + Stimulus), server-rendered, Tailwind CSS | Concept §24; no React needed for MVP |
| PWA | Rails 8 built-in generators (`bin/rails g pwa:install`) | Manifest + service worker + offline page, zero deps |
| SRS | `fsrs` gem (v0.9.x, MIT) — Ruby port of py-fsrs | Concept §11; avoids inventing a scheduler |
| Background jobs | None in Plan A (rake task for import) | SolidQueue added for Plan B ingestion |
| Auth | None in Plan A (single user, seeded demo user) | Keep `users` table + `user_id` FKs for later |
| Tests | RSpec + Capybara + system tests | Algorithms need deterministic tests |

> **Alternative considered:** `nagori-fsrs` (fsrs-rs bindings) is newer and faster but
> requires a Rust toolchain. Stick with pure-Ruby `fsrs` for Plan A; both share the
> same FSRS-6 model, so swapping later is internal to the scheduler adapter.

---

## 2. Application structure

```
app/
  controllers/
    home_controller.rb          # GET / — today's session summary
    sessions_controller.rb      # GET /sessions/next, POST /sessions/complete
    reviews_controller.rb       # POST /reviews
    progress_controller.rb      # GET /progress
  services/
    learning/
      diagnostic.rb
      priority_calculator.rb
      leverage_calculator.rb
      sentence_selector.rb
      question_generator.rb
      distractor_selector.rb
      mastery_calculator.rb
      scheduler.rb              # fsrs gem adapter
      exposure_recorder.rb
      next_review.rb            # orchestrates "what to show next"
      session.rb                # session summary (counts)
  models/                       # see schema §3
  javascript/controllers/       # quiz stimulus controllers
  views/pwa/                    # generated manifest/service-worker
lib/
  imports/
    corpus_importer.rb          # generic batched importer
    jmdict_parser.rb
    kanjidic_parser.rb
    generated_sentences_parser.rb
  generation/
    sentence_generator.rb       # batch LLM generation → versioned JSONL
    validation.rb               # §4.3 validation gates
  segmentation/
    longest_match.rb            # trie-based word segmentation (MVP)
db/
  seeds.rb                      # demo user + tiny dev corpus
```

Core loop (concept §25) maps 1:1 onto services:

```
NextReview ──► QuestionGenerator ──► quiz UI ──► Review row
      ▲                                             │
      └──────── MasteryCalculator + Scheduler ───────┘
```

---

## 3. Database schema

Everything the concept §4–§5 lists is included. Plan A differences are called out per
table. All `user_*` tables carry `user_id` even though there is one user.

### 3.1 Static reference data

**`kanji`**
```ruby
t.string :character,          null: false, index: { unique: true }
t.string :unicode_codepoint
t.integer :grade              # school grade or nil
t.integer :frequency_rank     # from KANJIDIC2 / unified dataset
t.integer :stroke_count
t.string :meaning_summary
t.integer :radical_id, null: true   # used by distractor selection + prereq bonus
```
**`readings`**
```ruby
t.belongs_to :kanji, null: false
t.string :reading, null: false
t.string :kind, null: false   # onyomi | kunyomi | nanori
t.index %i[kanji_id reading], unique: true
```
**`words`**
```ruby
t.string :surface, null: false, index: { unique: true }   # 決める
t.string :reading, null: false, index: true               # きめる
t.integer :frequency_rank, null: true, index: true
t.string :jlpt_level, null: true
t.text :meaning, null: false
t.string :part_of_speech, null: true                      # rough POS, helps distractors
```
**`word_kanji`** — many-to-many with position (concept §4.5)
```ruby
t.belongs_to :word,  null: false
t.belongs_to :kanji, null: false
t.integer :position, null: false   # index of kanji within surface
t.index %i[word_id kanji_id], unique: true
t.index :kanji_id                  # reverse lookup: words containing a kanji
```
**`sentences`**
```ruby
t.text :japanese, null: false
t.text :translation, null: true    # English translation (LLM-generated)
t.integer :difficulty, null: true  # 1..5, computed at import (see §8.4)
t.string :source, null: false      # "llm" | "tatoeba" | "curated"
t.string :external_id, null: true, index: true  # generation row hash / tatoeba id
t.string :generation_version, null: true        # model + prompt_version + seed (LLM rows)
```
**`sentence_words`** — approximate in Plan A (see §4.4)
```ruby
t.belongs_to :sentence, null: false
t.belongs_to :word,     null: false
t.integer :start_position
t.integer :end_position
t.index %i[sentence_id word_id], unique: true
t.index :word_id
```

### 3.2 User state

**`user_kanji`** (concept §5.1)
```ruby
t.belongs_to :user, null: false
t.belongs_to :kanji, null: false

t.float :mastery_score, default: 0.0
t.float :recognition_strength, default: 0.0
t.float :reading_strength,     default: 0.0
t.float :context_strength,     default: 0.0

t.jsonb :srs_state, default: {}        # serialized Fsrs::Card (state/stability/difficulty/etc.)
t.datetime :due_at, index: true

t.datetime :first_seen_at
t.datetime :last_seen_at
t.integer :times_seen, default: 0
t.integer :times_correct, default: 0
t.integer :times_incorrect, default: 0

t.index %i[user_id kanji_id], unique: true
```
**`user_words`** (concept §5.2)
```ruby
t.belongs_to :user, null: false
t.belongs_to :word, null: false

t.float :mastery_score, default: 0.0
t.jsonb :srs_state, default: {}
t.datetime :due_at, index: true

t.datetime :first_seen_at
t.datetime :last_seen_at
t.integer :times_seen, default: 0
t.integer :times_correct, default: 0
t.integer :times_incorrect, default: 0

t.index %i[user_id word_id], unique: true
```

### 3.3 Events

**`reviews`** (concept §5.3) — immutable append-only history
```ruby
t.belongs_to :user, null: false
t.references :reviewable, polymorphic: true, null: false   # user_kanji | user_word

t.string :question_type, null: false   # kana_to_kanji | sentence_to_kanji | kanji_to_meaning
t.string :grade, null: false           # again | hard | good | easy (FSRS rating)
t.jsonb :distractors, default: []      # ids shown as options (feeds confusion network in Plan B)

t.datetime :presented_at, null: false
t.datetime :answered_at, null: false
t.boolean :correct, null: false
t.integer :response_time_ms, null: true
t.string :confidence, null: true       # instant | knew | thought | guessed | unknown

t.float :previous_interval
t.float :new_interval
t.float :previous_mastery
t.float :new_mastery

t.index %i[user_id reviewable_type reviewable_id]
t.index :created_at
```
**`exposures`** (Plan A: minimal; Plan B: full) — dedup + passive tracking
```ruby
t.belongs_to :user, null: false
t.belongs_to :kanji, null: false
t.belongs_to :sentence, null: true
t.string :kind, null: false            # review | sentence | reading (Plan B)
t.datetime :occurred_at
t.index %i[user_id kanji_id occurred_at]
```

> **Plan A simplification:** `exposures` is written only to dedupe sentence selection
> (i.e. "has this sentence been shown for this kanji recently"). Passive-weighting and
> the reading-stream kinds are Plan B additions that reuse the same table.

---

## 4. Data pipeline

Two layers: (a) **reference data** — kanji, vocabulary, readings, frequency — from
licensed corpora, and (b) **example sentences generated and validated by an LLM**
instead of an external sentence corpus.

This deliberately deviates from concept §4.6 ("prefer an authentic corpus") in exchange
for two Plan A wins: exact control over the "target kanji is the difficult part"
property (concept §14), and no sentence-corpus licensing burden. The mitigation is a
strict validation pipeline (§4.3). Authentic/imported material still matters for the
Plan B reading stream (§15) and slots in without schema changes.

### 4.1 Reference data (kanji, vocabulary, frequency)

| Data | Source | License | Plan A scope |
|---|---|---|---|
| Kanji metadata + readings + freq | **KANJIDIC2** | EDRDG (free, attribution) | top ~500 by frequency |
| Vocabulary, readings, meanings | **JMdict** (XML) | EDRDG | ~2,000–4,000 common words |
| Word frequency | BCCWJ-derived ranks (unified dataset below) | CC BY-SA 4.0 | top ~4,000 |

**Recommended shortcut:** use the **`jkindrix/japanese-language-data`** unified build,
which pre-integrates JMdict + KANJIDIC2 + frequency into one coherent dataset. Fall back
to parsing raw sources if you need a looser license than CC BY-SA.

> **Attribution:** `ATTRIBUTION.md` credits JMdict / KANJIDIC2 / the frequency source.
> Generated sentences carry no attribution obligation, but `source`/`external_id` are
> still recorded on every row for traceability.

### 4.2 LLM sentence generation

Sentences are generated **offline, in batch, into a versioned JSONL file**, then
imported like any corpus — runtime behaviour is unchanged: `SentenceSelector` keeps
reading the `sentences` table, and `source: "llm"` distinguishes the rows.

- **Target list:** one sentence per in-scope (word × kanji) pair, plus context
  sentences for high-leverage kanji with no word pair. ≈5–8k generations for Plan A.
- **Job:** `bin/rails jozu:generate_sentences`
  1. Build generation units (word, target kanji, other-kanji frequency budget).
  2. Call an OpenAI-compatible chat endpoint (Ruby `ruby-openai` gem) with a strict
     prompt; each unit returns `{"ja": ..., "en": ...}` JSON.
  3. Append raw results to `vendor/data/generated_sentences.jsonl` with `model`,
     `prompt_version`, `temperature`, `seed`. **The API is called once; the file is the
     source of truth** for all later imports — reproducible, diffable, and human-reviewable
     before import.

Prompt sketch (Japanese for the sentence, English for the translation):
```
Write one natural, grammatically correct Japanese sentence that uses the word "{word}"
(meaning: "{meaning}") in context.
Requirements:
- Must contain the exact word "{word}".
- Apart from that word, every kanji must be among the top {n} most frequent kanji.
- 6–30 characters, natural everyday Japanese, no filler set-phrases.
Return strict JSON: {"ja": "...", "en": "..."}
```

- **Determinism:** `generation_version = model + prompt_version + seed` is stored on
  each `sentences` row so a bank can be regenerated and diffed cleanly.

### 4.3 Validation gates (applied at import)

1. **Structural:** exact target word present (via segmentation below), 6–30 chars, ends
   in Japanese sentence punctuation, non-empty `en`.
2. **Kanji budget:** every other kanji within the configured frequency band — guarantees
   concept §14 ("the target kanji is the difficult part") by construction.
3. **Dedupe:** exact-hash, then a Jaccard gate on the normalised kanji set.
4. **Naturalness pass** (config flag, default on): a second, cheaper LLM call rates each
   sentence 1–5; keep ≥3. Failing rows get ≤2 retries at a higher temperature, then drop.
5. **Fallback:** a word with no surviving sentence simply produces no
   `sentence_to_kanji` questions until a valid one is generated.

**Cost:** ≈5–8k generations + naturalness pass ≈ a few dollars at current API pricing —
negligible vs. the corpus-parsing and licensing effort it replaces.

### 4.4 Word ↔ sentence linking

**Trie longest-match segmentation** (`lib/segmentation/longest_match.rb`): a prefix trie
of JMdict surfaces, scanned left-to-right emitting the longest match. ~100 lines,
deterministic, testable; gives approximate `sentence_words` boundaries good enough for
comprehension scoring. Swap for Sudachi/mecab in Plan B and rebuild `sentence_words`.

### 4.5 Import pipeline

`bin/rails jozu:import`, idempotent (upsert on `external_id`), batched in transactions:

1. Load reference data from `vendor/data/`.
2. Filter kanji to top ~500 by frequency.
3. Filter words containing ≥1 in-scope kanji, top ~4,000 by frequency.
4. Build `word_kanji` (position = index of each kanji char in surface).
5. Read `generated_sentences.jsonl`; run validation gates (§4.3); insert `sentences`
   (`source: "llm"`, `external_id` = generation row hash, `generation_version`).
6. Segment sentences → `sentence_words` (longest-match).
7. Compute `sentences.difficulty` from the kanji frequency profile (§8.4).
8. Compute `kanji.meaning_summary` from JMdict meanings of its words.

Also ship `db/seeds.rb` with a **tiny hand-curated corpus** (~30 kanji / 100 words /
200 sentences) for fast tests and dev; tests run against fixtures, not the real bank.

> **Plan B:** ingestion moves to SolidQueue jobs; the bank scales to ~50k sentences with
> **on-demand generation** for gaps, plus an optional authentic corpus (Tatoeba) to
> anchor the reading stream; Sudachi/mecab replaces longest-match.

---

## 5. User knowledge model (mastery)

### 5.1 Per-dimension strengths

Each kanji carries three strengths in `[0,1]` (concept §3):

```ruby
recognition_strength   # "I can pick this character out"
reading_strength       # "I know how it sounds here"
context_strength       # "I read it correctly inside real words/sentences"
mastery_score = 0.5*recognition_strength + 0.2*reading_strength + 0.3*context_strength
```

Question types update exactly one dimension:

| Question type | Dimension updated |
|---|---|
| kana_to_kanji | recognition |
| kanji_to_meaning | recognition (meaning leg) |
| sentence_to_kanji | context |

`reading_strength` is seeded by the diagnostic and by word readings but **not yet**
drilled in Plan A (the concept defers reading questions — §22 lists only 3 types).

### 5.2 Update rule (`Learning::MasteryCalculator`)

Delta applied to the dimension's strength on each review:

```ruby
DELTAS = {
  %w[instant knew]  => { correct: +0.14, wrong: -0.20 },
  %w[thought]       => { correct: +0.09, wrong: -0.22 },
  %w[guessed]       => { correct: +0.05, wrong: -0.25 },
  %w[unknown]       => { correct: +0.03, wrong: -0.30 },
}
new = clamp01(old + delta)
```

`times_seen / times_correct / times_incorrect` updated independently. Word mastery uses
the same rule on `user_words.mastery_score`.

> **Plan B:** add passive-exposure deltas (concept §13 weights: review +1.0,
> contextual recognition +0.4, sentence exposure +0.1, reading +0.15), plus the
> lifecycle (UNKNOWN → … → AUTOMATIC, concept §16) and the "stop explicit drilling"
> recommendation (§20). All operate on the same columns.

---

## 6. FSRS scheduling (`Learning::Scheduler`)

Wrap the `fsrs` gem behind a thin adapter so nothing else touches the gem API.

```ruby
class Learning::Scheduler
  # Build Fsrs::Card from user_kanji.srs_state
  # next_ratings(user_kanji) -> {again:, hard:, good:, easy:} scheduling cards
  # apply!(user_kanji, rating, now:) -> stores card jsonb + due_at
end
```

**Grade mapping** (concept §11) from raw outcome + confidence + response time:

```ruby
def grade_for(correct:, confidence:, response_time_ms:)
  return :again if !correct || confidence == "unknown"
  return :hard  if confidence.in?(%w[guessed]) || slow?(response_time_ms)
  return :easy  if confidence == "instant" && fast?(response_time_ms)
  :good
end
```

Thresholds (e.g. slow > 4000 ms, fast < 1500 ms) live in a config object so they can be
tuned without code changes. The scheduler persists the returned `Fsrs::Card` attributes
into `srs_state` jsonb and denormalizes `due_at`.

**New items:** `Fsrs::Card.new` with `State::NEW`; a "new kanji" appears in sessions as
a plain question (not an SRS review) and only becomes an SRS card after its first
answer.

> **Plan B:** keep raw review logs (already stored) so FSRS parameter *optimization*
> (training the 21 weights on this learner's history) can be added; the adapter is the
> seam for that.

---

## 7. Priority & leverage (`Learning::PriorityCalculator`, `Learning::LeverageCalculator`)

Concept §6, implemented for the factors Plan A uses:

```ruby
priority =
  frequency_score * leverage_score * uncertainty
# personal_relevance and prerequisite_bonus default to 1.0 (stubbed; Plan B)
```

**frequency_score** (concept §6.1), normalised to 0..1:
```ruby
raw = 1.0 / Math.log2(kanji.frequency_rank + 2)
frequency_score = raw / max_raw   # max_raw = value at rank 1
```

**leverage_score** (concept §6.2): sum over words containing the kanji of a weight =
estimated knownness of that word:

```ruby
word_weight(word) =
  user_words[word]&.mastery_score ||           # known word → strong signal
  prior_by_frequency(word.frequency_rank)      # unseen word → frequency prior (e.g. 0.5 * exp decay)

leverage_score = normalize1(
  words_containing(kanji).sum { |w| word_weight(w) }
)
```

**uncertainty** (concept §6.4): target the learner's uncertainty boundary.
```ruby
p = (times_correct + 1.0) / (times_seen + 2.0)   # smoothed correct rate
uncertainty = 4 * p * (1 - p)                     # peak 1.0 at p=0.5, →0 as p→0 or 1
uncertainty = 0.6 if times_seen.zero?             # unseen items start at a neutral default
```

**Surface metric** for the UI: `LeverageCalculator#unlock_count(kanji, user)` → "Learn
必 — unlocks 8 words you already know."

> **Plan B:** add `personal_relevance` (frequency in user-imported text, concept §6.3)
> and `prerequisite_bonus` (shared radicals/components with known kanji, concept §6.5).
> Both are extra multiplicative factors with default 1.0, so Plan A code is untouched.

---

## 8. Question engine

### 8.1 Orchestration (`Learning::NextReview`)

Deterministic single-call "what's next":

1. **Reviews first:** pick the due item (earliest `due_at`) among `user_kanji` +
   `user_words` with an SRS card in state `LEARNING/REVIEW/RELEARNING`.
2. **New kanji:** if no reviews due (or fewer than session target), take the highest
   `priority` kanji with no `user_kanji` row yet (limit 3 per session — concept §21).
3. Choose question type from the item's weakest dimension (concept §8), constrained to
   the 3 Plan A types:
   - `kanji_to_meaning` for first exposure of a new kanji (initial acquisition).
   - otherwise `sentence_to_kanji` (context) if `context_strength` is lowest.
   - else `kana_to_kanji` (recognition).
4. Return a question DTO:
   ```ruby
   Question = Data.define(:reviewable_type, :reviewable_id, :question_type,
                          :prompt, :options, :correct_option_id, :distractors)
   ```

### 8.2 Question formats

- **kana_to_kanji:** prompt = word.reading (e.g. きめる); options = kanji-form words.
- **sentence_to_kanji:** prompt = sentence with target word's kanji blanked
  (＿＿めます), options = single kanji; correct option = target kanji.
- **kanji_to_meaning:** prompt = kanji (or a word containing it); options = meanings.

### 8.3 Distractors (`Learning::DistractorSelector`)

For each question type, pool candidates then pick 3 distinct plausible distractors
(concept §9):

```ruby
# kana_to_kanji: words sharing the same reading; else words sharing first char or
#                a visually similar kanji (same radical) at the same position
# sentence_to_kanji: kanji sharing onyomi/kunyomi with target, or visually similar
#                    (same radical / similar stroke count)
# kanji_to_meaning: meanings of visually similar kanji (same radical)
```

Validity contract (property-tested): options are unique, correct answer is present
exactly once, distractors are "plausible by construction" (i.e. they came from the
same reading/radical pool, never random unrelated kanji). The chosen `distractors`
are persisted on the review row for later confusion analysis.

> **Plan B:** distractor selection learns from actual confusion pairs (concept §10) and
> generates deliberate contrast questions (待/持); the stored `distractors` array is the
> training data.

### 8.4 Sentence selection (`Learning::SentenceSelector`)

For a target kanji K (used by `sentence_to_kanji`):

```ruby
candidates = Sentence.joins(:sentence_words)
                     .where(sentence_words: { word_id: words_containing(K) })
                     .where("length(japanese) <= ?", 40)
                     .where.not("seen recently")   # exposures table dedupe
# filter: all other kanji in the sentence are frequent (rank <= threshold) OR already
#         known by the user (mastery > 0.6) — "the target kanji is the difficult part"
score =
  target_word_frequency_factor  # from frequency_rank of the target word
  * comprehension_score          # mean estimated knownness of other words (user_words or prior)
  * novelty                      # 1 / (1 + times this sentence shown for K)
```

`difficulty` on the sentence row is computed at import as a baseline (mean kanji
frequency profile) so the filter is cheap at request time.

> **Plan B:** full per-user sentence scoring with vocabulary knownness probabilities
> (concept §15), passive exposure weighting, and the reading stream (concept §17).

---

## 9. Onboarding diagnostic (`Learning::Diagnostic`)

Concept §23. On first launch the learner answers ~40 rapid questions (a capped version
of the 50–100 planned):

- Formats: kana→kanji and "which is X" recognition only. **No English required.**
- Sampling: adaptive staircase across 3 frequency bands; wrong answers push easier,
  correct push harder.
- After the last answer, batch-seed `user_kanji` / `user_words`:
  - correct → `recognition_strength`/`mastery_score` ≈ 0.75 (with per-confidence
    adjustment), plus a NEW SRS card.
  - wrong → 0.20, plus an SRS card in `LEARNING` due immediately.
  - Words implied by a correct kana→kanji answer get `mastery_score = 0.6` (the
    learner already knew the word's sound).
- Untested items keep defaults; the priority engine (with `uncertainty = 0.6`) drives
  what's learned next.

Diagnostic answers are recorded as `reviews` too, so nothing is lost.

---

## 10. UI / UX architecture

### 10.1 Screens

1. **Home** — "Today's session" card: `N reviews · M new kanji · 1 short reading`.
   `Learning::Session.summary(user)` computes counts (reading count = 0 in Plan A).
2. **Quiz** — one question at a time:
   - Server-rendered `<turbo-frame id="question">`.
   - Stimulus `quiz_controller` handles: option click → disable options → show
     correct/incorrect → optional confidence row → measure `response_time_ms`
     client-side → POST /reviews.
   - Response replaces the frame with the next question (or the session-end card).
3. **Session end** — correct/incorrect tally + "Done" → home.
4. **Progress** — "How much can I read?" (concept §18): bar for top-500 kanji coverage,
   counts of Known/Learning/Weak/Unknown, and "unlocked words" count.
5. **About** — attribution for JMdict / KANJIDIC2 / the frequency source (reference
   data); LLM-generated sentences carry no attribution obligation.

### 10.2 Request flow

```
GET /                 → home (summary)
GET /sessions/next    → quiz frame (renders Question DTO)
POST /reviews         → params: reviewable_type/id, answer_id, confidence, response_time_ms
                        1. Load Question by idempotency token
                        2. Learning::NextReview already knows the target; verify answer
                        3. MasteryCalculator.update!
                        4. Scheduler.apply!
                        5. ExposureRecorder.record!
                        6. Review.create!(immutable)
                        7. Turbo Stream: next question or session end
```

Controllers are thin: they only translate HTTP ↔ service objects (concept §24). A
client-generated `question_token` (UUID stored on the review) makes the quiz
idempotent against double-submits.

### 10.3 PWA (Rails 8 built-ins)

- `bin/rails g pwa:install` → `app/views/pwa/manifest.json.erb` +
  `service-worker.js` + offline page.
- Manifest: name/short_name, 512/192 icons, standalone, portrait, theme color.
- Service worker: **network-first** for app shell; cache static assets on install.
- **No offline quiz queue in Plan A** — that is explicitly deferred (offline answer
  sync is a Plan B item and the riskiest PWA feature).

> **Plan B PWA:** cache question batches + answer queue with background sync, so a
> session started on a train can finish offline.

---

## 11. Testing strategy

Test framework: **RSpec** + Capybara system tests.

| Layer | What | Fixtures |
|---|---|---|
| Unit — algorithms | Priority/leverage/mastery formulas, grade mapping, sentence scoring with fixed inputs and asserted outputs | `spec/fixtures/japanese/` tiny corpus |
| Unit — schedulers | `Learning::Scheduler`: grade→rating mapping; due_at advances; srs_state round-trips through jsonb | — |
| Property tests | `DistractorSelector`: options unique, exactly one correct, distractor plausibility invariant | random kanji pools |
| Segmentation | Longest-match on hand-written boundary cases | small strings |
| Controller | Thinness: params→service call→render; no logic in controller | request specs |
| System | Full session: home → N questions → confidence → session end → progress updates; Turbo frames swap correctly | Capybara + headless Chrome |
| Import | Idempotency (run twice, same row count); filter rules | tiny source files |

**Determinism:** all services take time as an injectable `now:` param. No
`Time.now`/`Date.current` anywhere in the domain layer.

> **Plan B adds:** algorithm evaluation harness (replay `reviews` log through the
> mastery model and compare predicted vs. actual), and retention-by-question-type
> analytics (concept §26).

---

## 12. Implementation sequence

Each milestone has an explicit exit criterion.

### M0 — Scaffold + CI (~0.5 wk)
- `rails new jozu` (PostgreSQL, Turbo, Tailwind, solid_cache default), RSpec, RuboCop,
  GitHub Actions (lint + test).
- Exit: `bin/rails test` + `bundle exec rspec` green in CI; PWA generator run.

### M1 — Data pipeline + sentence generation (~1–2 wk)
- Vendor `japanese-language-data` build (or raw sources) for kanji/vocab/frequency;
  write importers; tiny corpus in `db/seeds.rb`; fixtures.
- Build `jozu:generate_sentences` (batch LLM generation → versioned JSONL) and the
  validation gates (§4.3); run the naturalness pass on a sample.
- Exit: `bin/rails jozu:import` idempotent; counts match expectations; a sample of
  generated sentences passes manual QA; segmentation spot-checks look sane;
  `ATTRIBUTION.md` written.

### M2 — Domain core (~1 wk)
- `MasteryCalculator`, `Scheduler` (fsrs adapter), `PriorityCalculator`,
  `LeverageCalculator`, `ExposureRecorder`.
- Exit: deterministic unit tests green; grade mapping matches §6; leverage metric
  surfaces for a known kanji.

### M3 — Question engine (~1–1.5 wk)
- `NextReview`, `QuestionGenerator`, `DistractorSelector`, `SentenceSelector`.
- Exit: property tests pass; a session can produce kana_to_kanji, sentence_to_kanji,
  and kanji_to_meaning questions with plausible distractors from the tiny corpus.

### M4 — Quiz UX (~1 wk)
- Home summary, quiz frame + Stimulus controller, review POST flow, session end.
- Exit: system test completes a full session and progress changes.

### M5 — Diagnostic (~0.5–1 wk)
- Onboarding flow + batch state seeding.
- Exit: fresh user → 40 questions → populated user_kanji/user_words; first real session
  is sensible.

### M6 — Progress view + polish (~0.5–1 wk)
- Progress screen, PWA install test on phone, confidence UX polish, empty/edge states.
- Exit: installable PWA; a 2–5 min session is comfortable on mobile.

**Total: ~6–9 weeks.**

---

## 13. Analytics (Plan A minimum)

- Raw `reviews` are stored regardless (this is the analytics substrate).
- Progress screen computes: top-500 kanji coverage %, Known/Learning/Weak/Unknown
  counts, words unlocked.
- One rake task `jozu:stats` prints session/review counts for sanity checks.

> **Plan B:** retention by question type, confusion-pair mining, FSRS parameter
> optimization, and the "should I keep drilling this kanji?" recommendation — all read
> from the same `reviews` + `exposures` tables.

---

## 14. Risks & open decisions

| Risk | Mitigation |
|---|---|
| Corpus licensing friction | Prefer the unified CC-BY-SA build; ship attribution; record `source`/`external_id` on every row |
| `fsrs` gem maturity | Wrap behind `Learning::Scheduler`; pure-Ruby, no C deps; swap seam exists |
| LLM sentence quality / hallucination | Validation gates (§4.3) + naturalness rating pass + human-reviewable versioned JSONL |
| LLM cost & non-determinism | One-shot batch to a versioned file (API called once); regeneration is a diffable, reviewable job |
| Approximate segmentation | Longest-match is deterministic + testable; real tokenizer is a Plan B swap behind the same `sentence_words` table |
| Double-submit / answer tampering | `question_token` idempotency; review rows immutable |
| Algorithm parameters feel arbitrary | All constants in a config object / `now:` injection; unit-tested so tuning is safe |

### Decisions to confirm before M1
1. Unified dataset vs. raw sources (licensing posture).
2. Frequency source of truth (the dataset's BCCWJ-derived ranks vs. KANJIDIC2).
3. Whether Plan A ships an installable PWA at all (nice-to-have vs. required for the
   phone-based 2–5 min sessions).

---

## 15. Plan A → Plan B extension map

| Area | Plan A | Plan B |
|---|---|---|
| Reference data | 500 kanji / ~4k words | 2,000 / 10–20k |
| Sentences | ~5k LLM-validated, batch-generated (§4.2) | ~50k; on-demand generation for gaps + optional authentic corpus (Tatoeba) for the reading stream |
| Segmentation | Longest-match trie | Sudachi/mecab tokenizer, real `sentence_words` boundaries |
| SRS | `fsrs` gem, default params | FSRS parameter optimization on this learner's `reviews` |
| Priority | freq × leverage × uncertainty | + personal_relevance, + prerequisite_bonus |
| Question types | kana→kanji, sentence→kanji, kanji→meaning | + kanji→reading, contextual recognition, contrast questions |
| Distractors | static pools (reading/radical) | confusion-network-learned distractors + deliberate contrast |
| Exposure | dedupe only | passive/reading weighting (§13 of concept), lifecycle states, "stop drilling" recommendation |
| Reading | none | reading stream + tap-for-detail (concept §17) |
| Imported text | none | kanji radar / pasted-text analysis (concept §19) |
| Users | single seeded user | real auth |
| Jobs | rake task | SolidQueue ingestion jobs |
| Analytics | progress screen | retention-by-type, algorithm evaluation harness |
| PWA | installable, network-first | offline quiz queue + background sync |

The schema (§3) and service seams (§2) are chosen so that every Plan B row above is an
**addition**, not a migration-heavy rewrite.