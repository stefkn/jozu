class Review < ApplicationRecord
  QUESTION_TYPES = %w[kana_to_kanji sentence_to_kanji kanji_to_meaning kanji_recognition].freeze
  GRADES = %w[again hard good easy].freeze
  CONFIDENCES = %w[instant knew thought guessed unknown].freeze

  belongs_to :user
  belongs_to :reviewable, polymorphic: true

  validates :question_type, presence: true, inclusion: { in: QUESTION_TYPES }
  validates :grade, presence: true, inclusion: { in: GRADES }
  validates :confidence, inclusion: { in: CONFIDENCES }, allow_nil: true
  validates :correct, inclusion: { in: [ true, false ] }
  validates :question_token, uniqueness: true, allow_nil: true
end
