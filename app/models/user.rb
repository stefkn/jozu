class User < ApplicationRecord
  has_many :user_kanji, dependent: :destroy
  has_many :kanji, through: :user_kanji
  has_many :user_words, dependent: :destroy
  has_many :words, through: :user_words
  has_many :reviews, dependent: :destroy
  has_many :exposures, dependent: :destroy
end
