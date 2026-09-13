class UserKanji < ApplicationRecord
  self.table_name = "user_kanji"

  belongs_to :user
  belongs_to :kanji

  has_many :reviews, as: :reviewable, dependent: :destroy

  validates :kanji_id, uniqueness: { scope: :user_id }

  MASTERY_WEIGHTS = { recognition: 0.5, reading: 0.2, context: 0.3 }.freeze

  def mastery_score
    self[:mastery_score] || recompute_mastery
  end

  def recompute_mastery
    (recognition_strength * MASTERY_WEIGHTS[:recognition] +
      reading_strength * MASTERY_WEIGHTS[:reading] +
      context_strength * MASTERY_WEIGHTS[:context]).round(4)
  end

  def weak_dimension
    [ %i[recognition_strength recognition], %i[context_strength context] ].min_by { |attr, _| send(attr) }[1]
  end
end
