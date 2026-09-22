# Jozu

A personalised orthographic acquisition system for people who already speak
Japanese. Turn the vocabulary you know into kanji you can read, through a fast
recognition quiz driven by a priority engine, FSRS spaced repetition, and
plausible-by-construction distractors.

See `jozu_concept.md` (product) and `jozu_tech_plan.md` (technical plan, Plan A
thin vertical slice).

## Setup

Requires Ruby 4.0+ and PostgreSQL.

```sh
bundle install
bin/rails db:create db:migrate
bin/rails jozu:import          # import the vendored reference bank (kanji/words/radicals)
bin/rails db:seed              # demo user (curated corpus only seeds an empty DB)
bin/rails server
```

Then open http://localhost:3000. On first launch the app runs a short diagnostic
to estimate what you already know, then presents daily quiz sessions.

## Data pipeline

The reference bank (top-500 kanji, ~4k words, 253 radicals) is derived from the
`jkindrix/japanese-language-data` unified build (CC BY-SA 4.0) and shipped as
`vendor/data/*.tsv`.

```sh
script/fetch_reference_data.rb      # (re)download pinned sources -> vendor/data/sources/
bin/rails jozu:convert_reference    # sources -> vendor/data/{radicals,kanji,words}.tsv
bin/rails jozu:import               # idempotent TSV + sentence import
bin/rails jozu:generate_sentences   # LLM sentence generation -> generated_sentences.jsonl
bin/rails jozu:rate_sentences       # naturalness gate -> generated_sentences.natural.jsonl
bin/rails jozu:stats                # sanity counts
```

LLM steps use OpenRouter (`ruby-openai` with `uri_base` pointed at
`https://openrouter.ai/api/v1`). Env vars:

| Var | Default | Purpose |
|---|---|---|
| `OPENROUTER_API_KEY` | — | required for generation/rating |
| `JOZU_LLM_MODEL` | `anthropic/claude-sonnet-4` | generation model slug |
| `JOZU_NATURALNESS_MODEL` | `JOZU_LLM_MODEL` | rating-pass model slug (e.g. a stronger model) |
| `JOZU_LLM_BASE_URL` | OpenRouter `/api/v1` | provider override |
| `JOZU_CONCURRENCY` | `1` | parallel in-flight requests |
| `LIMIT` | — | cap `jozu:generate_sentences` units |

Generation is resumable (skips already-generated word×kanji pairs) and the raw
JSONL is the source of truth; `jozu:import` prefers the naturalness-filtered file.
`jozu:generate_sentences` also supports `json_mode`/`send_seed` via
`Generation::SentenceGenerator` kwargs for providers that accept them.

Reference data licensing is documented in `ATTRIBUTION.md`.

## Tests

```sh
bundle exec rspec          # unit + request + system tests
bundle exec rubocop        # style
bin/rails jozu:stats       # sanity counts
```

System tests run headless Chrome via Selenium.

## Architecture

Domain logic lives in plain Ruby service objects under `app/services/learning/`
(priority, leverage, mastery, FSRS scheduling, question generation, distractor
selection, sentence selection, diagnostic). Controllers only translate HTTP to
service calls. The core loop:

```
NextReview → QuestionGenerator → quiz UI → Review row
     ▲                                 │
     └──── MasteryCalculator + Scheduler ──┘
```