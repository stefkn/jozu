module ApplicationHelper
  QUESTION_TYPE_LABELS = {
    "kana_to_kanji" => "Choose the kanji",
    "kanji_to_reading" => "Choose the reading",
    "sentence_to_kanji" => "Choose the kanji",
    "kanji_to_meaning" => "Choose the meaning"
  }.freeze

  def question_type_label(type)
    QUESTION_TYPE_LABELS.fetch(type, type)
  end

  def session_progress(user = current_user)
    Learning::SessionProgress.call(user)
  end
end
