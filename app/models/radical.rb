class Radical < ApplicationRecord
  has_many :kanji, dependent: :nullify

  validates :character, presence: true, uniqueness: true
  validates :name, presence: true
end
