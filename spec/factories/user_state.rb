FactoryBot.define do
  factory :user_kanji do
    user
    kanji
  end

  factory :user_word do
    user
    word
  end

  factory :review do
    user
    association :reviewable, factory: :user_kanji
    question_type { "kana_to_kanji" }
    grade { "good" }
    presented_at { Time.current }
    answered_at { Time.current }
    correct { true }
  end
end
