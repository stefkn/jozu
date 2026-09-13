FactoryBot.define do
  factory :kanji do
    sequence(:character) { |n| "字#{n}" }
    sequence(:frequency_rank)
    meaning_summary { "meaning" }
  end

  factory :reading do
    kanji
    reading { "おん" }
    kind { "onyomi" }
  end

  factory :word do
    surface { "単語" }
    reading { "たんご" }
    meaning { "word" }
    sequence(:frequency_rank)
  end

  factory :sentence do
    japanese { "これは文です。" }
    translation { "This is a sentence." }
    source { "curated" }
    difficulty { 3 }
  end
end
