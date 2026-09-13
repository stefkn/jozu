class WordKanji < ApplicationRecord
  self.table_name = "word_kanji"

  belongs_to :word
  belongs_to :kanji

  validates :position, presence: true
  validates :kanji_id, uniqueness: { scope: :word_id }
end
