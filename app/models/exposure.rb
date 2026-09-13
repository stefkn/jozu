class Exposure < ApplicationRecord
  belongs_to :user
  belongs_to :kanji
  belongs_to :sentence, optional: true

  KINDS = %w[review sentence reading].freeze

  validates :kind, presence: true, inclusion: { in: KINDS }

  scope :recent_for, ->(user, kanji, within:) {
    where(user:, kanji:).where("occurred_at >= ?", within)
  }
end
