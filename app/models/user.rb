class User < ApplicationRecord
  before_validation :assign_access_token, on: :create
  validates :access_token, presence: true, uniqueness: true,
                           format: { with: /\A[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}\z/ }

  THEMES = %w[system light dark].freeze
  has_many :user_kanji, dependent: :destroy
  has_many :kanji, through: :user_kanji
  has_many :user_words, dependent: :destroy
  has_many :words, through: :user_words
  has_many :reviews, dependent: :destroy
  has_many :exposures, dependent: :destroy

  def skip_number_kanji?
    settings["skip_number_kanji"].present?
  end

  def practice_mode?
    settings["practice_mode"].present?
  end

  def theme
    settings["theme"].presence_in(THEMES) || "system"
  end

  def dark_mode?(system_dark: false)
    case theme
    when "dark" then true
    when "light" then false
    else system_dark
    end
  end

  def set_setting(key, value)
    update!(settings: (settings || {}).merge(key.to_s => value))
  end
  private

  def assign_access_token
    self.access_token ||= SecureRandom.uuid
  end
end
