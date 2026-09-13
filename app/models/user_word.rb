class UserWord < ApplicationRecord
  self.table_name = "user_words"

  belongs_to :user
  belongs_to :word

  has_many :reviews, as: :reviewable, dependent: :destroy

  validates :word_id, uniqueness: { scope: :user_id }
end
