module ApplicationHelper
  QUESTION_TYPE_LABELS = {
    "kana_to_kanji" => "Choose the kanji",
    "sentence_to_kanji" => "Choose the kanji",
    "kanji_to_meaning" => "Choose the meaning"
  }.freeze

  def question_type_label(type)
    QUESTION_TYPE_LABELS.fetch(type, type)
  end
end
