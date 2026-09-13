class Reading < ApplicationRecord
  belongs_to :kanji

  KINDS = %w[onyomi kunyomi nanori].freeze

  validates :reading, presence: true, uniqueness: { scope: :kanji_id }
  validates :kind, presence: true, inclusion: { in: KINDS }
end
