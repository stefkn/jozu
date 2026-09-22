# Attribution

Jozu's reference data sources and licenses:

## Reference data (full bank)

Jozu's kanji, vocabulary, and frequency data are derived from the
**`jkindrix/japanese-language-data`** unified build (pinned commit
`04014e06019fc9d4af76e6dbb64ec709fe863c4d`), which aggregates:

- **JMdict / JMnedict** — vocabulary, readings, meanings.
  Copyright © The Electronic Dictionary Research and Development Group (EDRDG).
  See https://www.edrdg.org/jmdict/edict_doc.html
- **KANJIDIC2** — kanji metadata (grade, stroke count, readings, meanings, frequency).
  Copyright © The Electronic Dictionary Research and Development Group (EDRDG).
  See https://www.edrdg.org/kanjidic/kanjidic2_doc.html
- **Kangxi radicals** — KRADFILE / RADKFILE (EDRDG) + Wikipedia Kangxi radical
  meanings and numbers (CC BY-SA 4.0).
- **Word frequency ranks** — Leeds University web corpus (CC-BY), matched against
  JMdict vocabulary and integrated by the unified build.

The unified dataset is licensed **CC BY-SA 4.0**; the converted `vendor/data/*.tsv`
files that Jozu imports are derivatives and carry the same license. The raw source
files live in `vendor/data/sources/` (gitignored, reproducible via
`script/fetch_reference_data.rb`); its `ATTRIBUTION.md` / `LICENSE` are authoritative.

> **EDRDG compliance:** the EDRDG License requires web-facing dictionary
> applications to refresh JMdict/KANJIDIC2-derived data at least monthly. Before
> shipping Jozu publicly, re-run `script/fetch_reference_data.rb` + `jozu:convert_reference`
> + `jozu:import` on a monthly cadence.

`source`/`external_id` are recorded on every sentence row for traceability.

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