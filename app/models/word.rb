class Word < ApplicationRecord
  has_many :word_kanji, dependent: :destroy
  has_many :kanji, through: :word_kanji
  has_many :sentence_words, dependent: :destroy
  has_many :sentences, through: :sentence_words
  has_many :user_words, dependent: :destroy

  validates :surface, presence: true, uniqueness: true
  validates :meaning, presence: true

  def kanji_surfaces
    surface.chars.select { |c| c.ord >= 0x4e00 && c.ord <= 0x9fff }
  end
end
