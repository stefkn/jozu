# Attribution

Jozu's reference data sources and licenses:

## Planned reference data (full bank)

- **JMdict / JMnedict** — vocabulary, readings, meanings.
  Copyright © The Electronic Dictionary Research and Development Group (EDRDG).
  License: Creative Commons Attribution-ShareAlike 4.0 International (CC BY-SA 4.0).
  See https://www.edrdg.org/jmdict/edict_doc.html
- **KANJIDIC2** — kanji metadata (grade, stroke count, readings, meanings).
  Copyright © The Electronic Dictionary Research and Development Group (EDRDG).
  License: freely available, attribution requested. See https://www.edrdg.org/kanjidic/kanjidic2_doc.html
- **Word frequency ranks** — BCCWJ-derived frequency data as integrated by the
  unified `jkindrix/japanese-language-data` build (CC BY-SA 4.0).

The unified dataset is preferred for Plan A imports; `source`/`external_id` are
recorded on every sentence row for traceability.

## LLM-generated example sentences

Sentences generated via an LLM (`source: "llm"` in the `sentences` table) carry no
attribution obligation. Each row records `generation_version` (model + prompt version
+ seed) and a content hash in `external_id` so the bank is reproducible and diffable.

## Seeded demo corpus

The tiny corpus in `db/seeds.rb` is hand-curated for development and testing only.
It is not shipped as reference data.

## License

Jozu itself is licensed under the MIT License (see `LICENSE`). This attribution
notice does not apply Jozu's license to the reference data listed above; that data
remains under its respective licenses.