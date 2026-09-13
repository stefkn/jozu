class Kanji < ApplicationRecord
  self.table_name = "kanji"

  has_many :readings, dependent: :destroy
  has_many :word_kanji, dependent: :destroy
  has_many :words, through: :word_kanji
  has_many :user_kanji, dependent: :destroy
  has_many :exposures, dependent: :destroy

  validates :character, presence: true, uniqueness: true

  def unicode_codepoint
    super || "U+%04X" % character.ord
  end

  def reading_for(word)
    readings.find { |r| word.reading.include?(r.reading) }&.reading
  end
end
