# Kanji Learning PWA — Product & Learning Algorithm Concept

## 1. Project overview

Build a personal web app / PWA for an unusual but well-defined Japanese-learning use case:

> The learner is fluent in conversational Japanese and can read hiragana and katakana, but has only rudimentary knowledge of kanji. The goal is to turn existing spoken/vocabulary knowledge into reliable Japanese reading ability.

This is **not** intended to be a generic Japanese beginner app.

The learner already understands Japanese vocabulary, grammar, pronunciation, and conversation. The principal missing mapping is:

```text
known spoken word → written Japanese / kanji
```

For example, the learner may already know:

```text
きめる = decide
```

but not reliably recognise:

```text
決める
```

The application should exploit this existing knowledge rather than teaching Japanese from scratch.

---

## 2. Product philosophy

The central learning loop is:

```text
See → recognise → understand → reinforce → encounter again
```

The fundamental learning unit should not be an isolated kanji. It should be:

```text
Kanji → Word → Sentence → Context
```

The primary objective is:

> Turn Japanese the learner already knows into Japanese they can comfortably read.

Therefore the application should optimise for **useful reading ability**, not merely number of kanji memorised.

Key principles:

- Prioritise high-frequency, useful kanji.
- Give extra priority to kanji contained in vocabulary the learner already knows.
- Teach primarily through natural Japanese sentences.
- Use spaced repetition for deliberate recall.
- Use contextual exposure to reinforce already-stable kanji.
- Prefer recognition/retrieval over typing.
- Keep interactions short enough for 2–5 minute sessions.
- Avoid assuming beginner-level Japanese knowledge.
- Minimise English when it is unnecessary.
- Avoid requiring production unless production is specifically being tested.

---

# 3. Core learner model

The application should distinguish at least three related but separate forms of knowledge:

1. **Word knowledge**
   - Does the learner know the Japanese word and its meaning?
2. **Kanji recognition**
   - Can the learner recognise the character?
3. **Contextual reading**
   - Can the learner recognise the character naturally inside real Japanese words/sentences?

Example:

```text
決
recognition: 0.91
reading:     0.72
context:     0.84
```

And:

```text
決める   word mastery: 0.95
決まる   word mastery: 0.65
決定     word mastery: 0.40
解決     word mastery: 0.20
```

The learner may therefore know the kanji while still needing exposure to particular words containing it.

---

# 4. Data model

Use PostgreSQL with Rails / ActiveRecord.

## 4.1 User

Standard application user.

Potential fields:

```text
id
...
```

---

## 4.2 Kanji

Static metadata for each character.

Suggested fields:

```text
id
character
unicode_codepoint
grade
frequency_rank
stroke_count
meaning_summary
```

Potentially include additional authoritative metadata later, but avoid prematurely building a huge kanji ontology.

---

## 4.3 Reading

Represents possible readings associated with a kanji.

```text
id
kanji_id
reading
type
```

Where `type` could be:

- onyomi
- kunyomi
- nanori

However, word-level readings are more important than isolated kanji readings because isolated readings can be ambiguous.

---

## 4.4 Word

Represents vocabulary.

```text
id
surface
reading
frequency_rank
jlpt_level
meaning
```

Examples:

```text
決める | きめる | decide
決まる | きまる | be decided
決定   | けってい | decision
解決   | かいけつ | solution
```

The database should contain enough common vocabulary to support personalised kanji selection.

---

## 4.5 WordKanji

Many-to-many relationship between words and kanji.

```text
word_id
kanji_id
position
```

This enables queries such as:

> Which common words contain kanji that this learner does not yet know?

---

## 4.6 Sentence

Natural Japanese example sentence.

```text
id
japanese
translation
difficulty
source
audio_url
```

Do not rely entirely on LLM-generated sentences in the initial version. Prefer an authentic or curated sentence corpus, with generation added later where useful.

---

## 4.7 SentenceWord

Links vocabulary to sentences.

```text
sentence_id
word_id
start_position
end_position
```

This allows sentence selection based on the learner's existing vocabulary knowledge.

---

# 5. User knowledge state

## 5.1 UserKanji

Represents the learner's current knowledge of a kanji.

Suggested fields:

```text
user_id
kanji_id

mastery_score
recognition_strength
reading_strength
context_strength

confidence
ease_factor
interval_days
due_at

first_seen_at
last_seen_at

times_seen
times_correct
times_incorrect
```

Mastery should be continuous rather than simply known/unknown.

Conceptual scale:

```text
0.00 — unknown
0.20 — familiar
0.40 — recognition emerging
0.60 — usually recognised
0.75 — reliable
0.90 — strong
0.97 — automatic
```

These values need not be exposed directly to the learner.

---

## 5.2 UserWord

Represents knowledge of an individual vocabulary item.

```text
user_id
word_id

mastery_score
ease_factor
interval_days
due_at

times_seen
times_correct
times_incorrect
```

A word's knowledge should be independent of the learner's knowledge of its component kanji.

---

## 5.3 Review

Review events should be immutable rather than overwriting history.

Suggested fields:

```text
id
user_id

reviewable_type
reviewable_id

question_type

presented_at
answered_at

correct
response_time_ms
confidence

previous_interval
new_interval
previous_mastery
new_mastery
```

This raw history will allow later experimentation with different SRS algorithms and analysis of the learner's actual performance.

---

# 6. Learning priority algorithm

Do not simply teach kanji in JLPT order or raw frequency order.

Candidate kanji should receive a personalised learning priority.

Conceptual formula:

```text
priority =
    frequency_score
  × vocabulary_leverage
  × personal_relevance
  × uncertainty
  × prerequisite_bonus
```

The exact formula should be treated as tunable.

---

## 6.1 Frequency score

High-frequency kanji should generally receive higher priority.

A logarithmic transformation is preferable to a linear one because the difference between very common characters matters more than small differences among rare characters.

Example conceptual calculation:

```ruby
frequency_score = 1.0 / Math.log2(frequency_rank + 2)
```

Normalise the result to a useful 0–1 range.

---

## 6.2 Vocabulary leverage

This should be one of the application's defining features.

If the learner already knows:

```text
必要
必ず
必死
必須
```

but does not know 必, then 必 is highly valuable.

Conceptually:

```text
leverage =
  sum(weight of known/common words containing the kanji)
```

Example:

```text
必

必要      1.0
必ず       0.9
必死       0.6
必須       0.4

leverage = 2.9
```

A character such as 葡, which may primarily unlock 葡萄, should have much lower leverage.

This can be surfaced as a motivating metric:

> Learn 必 — unlocks 8 words you already know.

Potential future metric:

> Kanji leverage: 8×

---

## 6.3 Personal relevance

The learner should eventually be able to provide arbitrary Japanese text.

For example, imported text might contain:

```text
家族
育児
必要
経験
```

If a particular character repeatedly occurs in the learner's own material, increase its priority.

Conceptually:

```text
personal_relevance =
    frequency_in_user_material
```

This makes the curriculum increasingly personalised.

---

## 6.4 Uncertainty

Characters with inconsistent performance should receive more attention.

Example:

```text
決
14 correct
1 incorrect
→ low uncertainty

定
5 correct
4 incorrect
→ high uncertainty
```

The algorithm should target the learner's uncertainty boundary rather than repeatedly drilling characters that are already automatic.

---

## 6.5 Prerequisite / visual familiarity bonus

If the learner already knows a visually related component or character, give related characters a modest bonus.

Example:

```text
青
├── 晴
├── 清
├── 精
└── 静
```

This is not a strict prerequisite system. It simply recognises that visual familiarity can reduce acquisition cost.

---

# 7. Question types

The initial application should support a small number of high-quality recognition questions.

## 7.1 Sentence → meaning

Example:

```text
何を決めたの？
```

Question:

> What does 決 mean here?

Multiple choice:

```text
A. decide
B. arrive
C. forget
D. return
```

Useful primarily during initial acquisition.

---

## 7.2 Sentence → kanji

Example:

```text
明日までに＿＿めます。
```

Options:

```text
決
結
定
別
```

This should be one of the most important question types.

It directly tests the target skill:

> Which written character belongs to a Japanese word the learner already knows?

---

## 7.3 Kana → kanji

Example:

```text
きめる
```

Options:

```text
決める
結める
定める
極める
```

This is particularly valuable for this learner profile because the word's pronunciation is already known.

---

## 7.4 Kanji → reading

Example:

```text
決定
```

Options:

```text
けってい
けつてい
きめてい
けって
```

Use this selectively because reading ability is a secondary dimension.

---

## 7.5 Contextual recognition

Show a sentence:

```text
彼はまだ決めていない。
```

Ask the learner to identify which kanji they confidently recognise.

This provides richer evidence than a binary right/wrong answer.

---

# 8. Question selection

Do not ask the same question type repeatedly.

Select question types according to the learner's weakest dimension.

Example:

```text
決

recognition = 0.95
reading     = 0.55
compound/context = 0.40
```

Then favour:

```text
60% compound/context questions
30% reading questions
10% basic recognition
```

The percentages should eventually be configurable/tunable.

The objective is to strengthen underlying knowledge rather than train the learner to answer a particular flashcard format.

---

# 9. Intelligent distractors

Multiple-choice distractors should be plausible.

Avoid:

```text
決める

A. 決める
B. 水
C. 山
D. 犬
```

Prefer distractors based on the target:

- visually similar kanji
- same/similar readings
- semantically related vocabulary
- characters occurring in similar words
- common learner confusions

Example:

```text
きめる

決める
極める
定める
絞める
```

The distractor selection system should eventually learn from the learner's actual confusion patterns.

---

# 10. Confusion network

Track repeated confusions.

Example:

```text
待
├── 持
├── 特
└── 侍
```

If the learner repeatedly confuses 待 and 持, deliberately create contrast questions:

```text
先生を＿＿っています。
```

Options:

```text
待っています
持っています
```

This should be a targeted intervention rather than random drilling.

---

# 11. Spaced repetition

Use an established algorithm such as **FSRS** for explicit review scheduling rather than inventing a new interval formula initially.

The application's novel contribution is primarily:

> deciding what to learn and what material to show,

not inventing a new SRS scheduler.

Map application-level outcomes to SRS grades approximately:

```text
wrong + guessed       → Again
correct + guessed     → Hard
correct + slow        → Hard
correct + normal      → Good
correct + instant     → Easy
```

Response time and confidence should be recorded even if the first implementation uses a simple mapping.

---

# 12. Confidence

After answering, optionally ask:

> How did that feel?

Options:

```text
Instant
Knew it
Had to think
Guessed
Didn't know
```

This can distinguish:

```text
correct + instant
```

from:

```text
correct + barely guessed
```

These should not be treated as equally strong evidence.

Keep the interaction fast.

---

# 13. Explicit review vs natural exposure

Distinguish two mechanisms.

### Explicit SRS review

The learner is deliberately tested:

```text
決める → choose the correct kanji
```

This should strongly affect mastery.

### Natural exposure

The learner encounters:

```text
明日までに決めます。
```

during reading.

This should also contribute to mastery, but less strongly.

Conceptual weighting:

```text
Explicit correct recall          +1.0
Correct contextual recognition   +0.4
Passive sentence exposure        +0.1
Reading exposure                 +0.15
```

Exact values are tunable.

This distinction allows the system to stop explicitly drilling a stable kanji while continuing to reinforce it naturally.

---

# 14. Sentence selection algorithm

For a target kanji `K`, select sentences satisfying approximately:

```text
contains(K)
AND
natural
AND
target word is useful
AND
other vocabulary is familiar
AND
not seen recently
```

Then score candidates using factors such as:

```text
sentence_score =
    target_word_frequency
  × comprehension_score
  × naturalness
  × novelty
```

The most important principle is:

> The target kanji should be the difficult part, not the rest of the sentence.

Prefer:

```text
明日は必ず行きます。
```

over an unnecessarily difficult sentence containing several unfamiliar words.

---

# 15. Vocabulary knownness

Do not model vocabulary knowledge as simply true/false.

Prefer a probability/strength:

```text
明日       0.99
家族       0.98
必要       0.81
条件       0.42
不可欠     0.11
```

Sentence selection can then estimate how comprehensible a sentence will be to the learner.

This is especially important because the learner already knows a large amount of Japanese vocabulary that they may not know how to spell.

---

# 16. Learning lifecycle

A kanji should conceptually move through:

```text
UNKNOWN
   ↓
DISCOVERED
   ↓
LEARNING
   ↓
RECOGNITION
   ↓
STABLE
   ↓
AUTOMATIC
```

Example:

### Day 1

```text
決める
```

Explicit multiple-choice question.

### Day 2

```text
明日までに決めます。
```

Contextual recognition.

### Day 5

```text
まだ決まっていません。
```

Another contextual encounter.

### Day 12

```text
問題を解決する必要があります。
```

Natural reading exposure.

Eventually:

```text
決
```

should no longer feel like an object being studied. It should simply become visually familiar Japanese.

---

# 17. Reading stream

Once the learner has sufficient knowledge, provide short passages composed primarily of familiar vocabulary and kanji.

Example:

```text
来週、家族と東京に行く予定です。
今回は三日間ホテルに泊まります。
天気が良ければ、いろいろな場所を見て回りたいです。
```

Unknown or weak kanji can be highlighted.

The learner can tap a character for:

- reading
- meaning
- example words
- additional sentences
- pronunciation/audio

Then return immediately to the passage.

This bridges:

```text
study → actual reading
```

---

# 18. "How much can I read?" metric

Provide progress in terms meaningful to the actual goal.

Possible metrics:

```text
Most common 500 kanji
████████████░░░░░░ 61%

Known: 307
Learning: 42
Weak: 89
Unknown: 62
```

Potential future metrics:

- percentage of common kanji recognised
- percentage of kanji in a representative article
- number of common words unlocked
- number of successful contextual encounters
- reading difficulty the learner can handle

Avoid making JLPT level the primary progress metric.

---

# 19. Kanji radar / imported Japanese

A high-value future feature is allowing the learner to paste arbitrary Japanese text.

The system analyses it and reports:

```text
You recognise 71% of the kanji in this text.

12 characters are high-value learning candidates.

9 words contain kanji you have not mastered.
```

The learner can turn selected characters/words into the next study session.

This allows the application to adapt to:

- books
- news
- manga
- websites
- messages
- personal interests

rather than relying entirely on a fixed curriculum.

---

# 20. Passive / contextual learning

Eventually the app should be able to recommend that a kanji no longer needs direct drilling.

For example:

```text
決
Recognition: 92%
Words known: 7/10
Sentence exposures: 46
Last explicit review: 3 days ago
```

Recommendation:

> Stop explicitly studying this kanji; reinforce it through reading.

This prevents SRS from wasting time on characters that are already effectively automatic.

---

# 21. Daily session design

The application should be optimised for very short sessions.

Home screen:

```text
Today's session

12 reviews
3 new kanji
1 short reading

[Start]
```

A complete session should be possible in roughly 2–5 minutes.

No long lessons, mandatory course progression, or typing-heavy exercises.

The PWA should work well on a phone.

---

# 22. Recommended initial MVP

Keep the first implementation deliberately small.

## Data

Start with:

- approximately 2,000 common kanji
- approximately 10,000–20,000 common vocabulary items
- approximately 50,000–100,000 natural example sentences
- frequency metadata
- readings
- basic meanings

The exact corpus can be selected during technical planning based on licensing and availability.

## User state

Implement:

- `user_kanji`
- `user_word`
- `reviews`

## Question types

Initially implement only:

1. Kana → Kanji
2. Sentence → Kanji
3. Kanji → Meaning

## Algorithms

Implement:

1. initial diagnostic
2. candidate kanji ranking
3. vocabulary leverage calculation
4. sentence selection
5. multiple-choice distractor selection
6. mastery calculation
7. FSRS-based review scheduling
8. contextual exposure tracking

---

# 23. Initial onboarding / diagnostic

Do not ask the learner to select a generic Japanese level.

Instead, perform a rapid recognition diagnostic.

Example:

```text
Which is 食事?

食事
飲事
飯時
飲時
```

Then:

```text
Which is せんせい?

先生
生先
先正
生正
```

The learner should not need to know English definitions.

The diagnostic is measuring:

> Can the learner recognise written Japanese they already understand?

Approximately 50–100 rapid questions should produce an initial knowledge estimate.

---

# 24. Recommended Rails architecture

Use:

- Ruby on Rails
- PostgreSQL
- Hotwire / Turbo
- Stimulus
- PWA support
- background jobs where useful

React should not be necessary for the initial UI.

The core domain logic should live outside controllers.

Suggested service objects:

```text
Learning::NextKanji
Learning::NextReview
Learning::QuestionGenerator
Learning::DistractorSelector
Learning::SentenceSelector
Learning::MasteryCalculator
Learning::PriorityCalculator
Learning::ExposureRecorder
```

Example controller:

```ruby
def next
  @question = Learning::NextReview.call(current_user)
end
```

The learning services should be independently unit-testable.

---

# 25. Suggested implementation architecture

Conceptually:

```text
                    ┌───────────────┐
                    │ Kanji corpus  │
                    └───────┬───────┘
                            │
                    ┌───────▼───────┐
                    │ Vocabulary    │
                    │ + sentences   │
                    └───────┬───────┘
                            │
                            ▼
                 ┌─────────────────────┐
                 │ Personal knowledge  │
                 │ model               │
                 └──────────┬──────────┘
                            │
                 ┌──────────▼──────────┐
                 │ Priority engine     │
                 │                     │
                 │ What should I learn │
                 │ next?               │
                 └──────────┬──────────┘
                            │
                            ▼
                 ┌─────────────────────┐
                 │ Question generator  │
                 └──────────┬──────────┘
                            │
                            ▼
                      ┌───────────┐
                      │   Quiz    │
                      └─────┬─────┘
                            │
                            ▼
                    ┌───────────────┐
                    │ Review event  │
                    └───────┬───────┘
                            │
                            ▼
                 ┌─────────────────────┐
                 │ Update user model   │
                 └──────────┬──────────┘
                            │
                            └───────► repeat
```

---

# 26. Long-term adaptive learning

Once enough review data exists, the application can learn what works specifically for this learner.

For example, it may discover:

```text
Kana → Kanji
82% retention

Sentence → Kanji
94% retention

Kanji → English
71% retention
```

It can then reduce low-value question types and increase effective ones.

Similarly, it may discover that the learner tends to retain a kanji particularly well after:

- 4–6 different word encounters
- over approximately 2 weeks
- with contextual rather than isolated questions

The long-term goal is therefore:

> Optimise the learning process around the learner's actual reading development rather than implementing a fixed textbook curriculum.

---

# 27. Key product differentiation

Do not position this as:

> Anki but with a different UI.

The distinctive concept is:

> **A personalised orthographic acquisition system for people who already speak Japanese.**

The key optimisation target is:

```text
spoken vocabulary already known
              ↓
      useful kanji selected
              ↓
natural words and sentences
              ↓
multiple-choice recognition
              ↓
spaced repetition
              ↓
contextual exposure
              ↓
comfortable reading
```

The application should make maximum use of the learner's existing Japanese competence instead of forcing them through beginner material.

---

# 28. Technical planning questions for the next agent

Before implementation, produce a technical plan covering at least:

1. Exact Rails/PostgreSQL schema and associations.
2. Recommended sources/corpora for kanji, vocabulary, frequency data and example sentences, including licensing considerations.
3. Initial diagnostic design.
4. Exact kanji priority formula and normalisation.
5. Vocabulary leverage calculation.
6. User-word knownness model.
7. Mastery model.
8. FSRS integration and mapping of review outcomes.
9. Sentence selection algorithm.
10. Distractor generation algorithm.
11. Confusion-pair detection.
12. Contextual exposure weighting.
13. PWA architecture and offline behaviour.
14. Hotwire/Stimulus UI architecture.
15. Background jobs and data ingestion.
16. Seed/import pipeline for Japanese linguistic data.
17. Testing strategy, particularly for the learning algorithms.
18. Analytics required to determine whether the algorithm is actually improving reading ability.
19. MVP scope and implementation sequence.
20. Future architecture for imported text / personal reading material.

The technical plan should prioritise a simple, testable MVP while preserving the domain model needed for the adaptive learning system.
