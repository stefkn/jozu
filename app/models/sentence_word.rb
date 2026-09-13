class SentenceWord < ApplicationRecord
  belongs_to :sentence
  belongs_to :word

  validates :word_id, uniqueness: { scope: :sentence_id }
end
