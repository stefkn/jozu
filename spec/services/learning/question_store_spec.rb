require "rails_helper"

RSpec.describe Learning::QuestionStore do
  it "persists questions and diagnostic state across separate database cache instances" do
    user = create(:user)
    original = Rails.cache
    namespace = "cache-persistence-#{SecureRandom.uuid}"
    first = ActiveSupport::Cache.lookup_store(:solid_cache_store, namespace:)
    second = ActiveSupport::Cache.lookup_store(:solid_cache_store, namespace:)
    flashcard = Learning::Flashcard.new(token: SecureRandom.uuid, word_id: 1, front: "決定", back: "けってい")
    begin
      Rails.cache = first
      described_class.put(flashcard, user:)
      state = Learning::Diagnostic.state_for(user)
      Rails.cache = second
      expect(described_class.fetch(flashcard.token, user:)).to eq(flashcard)
      expect(Learning::Diagnostic.state_for(user)).to eq(state)
      described_class.delete(flashcard.token, user:)
      Rails.cache = first
      expect(described_class.fetch(flashcard.token, user:)).to be_nil
    ensure
      first.clear
      Rails.cache = original
    end
  end
end
