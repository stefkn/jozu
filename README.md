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
bin/rails db:create db:migrate db:seed   # seeds a demo user + tiny curated corpus
bin/rails server
```

Then open http://localhost:3000. On first launch the app runs a short diagnostic
to estimate what you already know, then presents daily quiz sessions.

## Data pipeline

- `bin/rails jozu:import` — idempotent import of `vendor/data/kanji.tsv`,
  `vendor/data/words.tsv`, and `vendor/data/generated_sentences.jsonl` (see
  `lib/imports/corpus_importer.rb` for the expected row formats).
- `bin/rails jozu:generate_sentences` — batch LLM sentence generation into
  `vendor/data/generated_sentences.jsonl` (requires `OPENAI_API_KEY`).
- `bin/rails jozu:stats` — session/review sanity counts.

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