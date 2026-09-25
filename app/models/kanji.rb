class Kanji < ApplicationRecord
  self.table_name = "kanji"

  # Canonical numeral kanji. Learners who already know 1, 2, 3, 100, 1000, 10000
  # can opt out of drilling these entirely (user setting "skip_number_kanji").
  NUMBER_KANJI = %w[一 二 三 四 五 六 七 八 九 十 百 千 万 億 兆 〇 零].freeze

  has_many :readings, dependent: :destroy
  has_many :word_kanji, dependent: :destroy
  has_many :words, through: :word_kanji
  has_many :user_kanji, dependent: :destroy
  has_many :exposures, dependent: :destroy
  belongs_to :radical, optional: true

  validates :character, presence: true, uniqueness: true

  def self.number?(character)
    NUMBER_KANJI.include?(character)
  end

  def unicode_codepoint
    super || "U+%04X" % character.ord
  end

  def reading_for(word)
    readings.find { |r| word.reading.include?(r.reading) }&.reading
  end
end
