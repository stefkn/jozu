class Sentence < ApplicationRecord
  SOURCES = %w[llm tatoeba curated].freeze

  has_many :sentence_words, dependent: :destroy
  has_many :words, through: :sentence_words

  validates :japanese, presence: true
  validates :source, presence: true, inclusion: { in: SOURCES }
end
