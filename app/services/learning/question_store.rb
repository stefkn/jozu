module Learning
  # Issued questions are private to the learner, including diagnostic flashcards.
  class QuestionStore
    TTL = 24.hours
    KEY_PREFIX = "jozu:question:v2"

    def self.put(question, user:)
      Rails.cache.write(key(question.token, user:), question, expires_in: TTL)
    end

    def self.fetch(token, user:)
      Rails.cache.read(key(token, user:))
    end

    def self.delete(token, user:)
      Rails.cache.delete(key(token, user:))
    end

    def self.key(token, user:)
      "#{KEY_PREFIX}:#{user.id}:#{token}"
    end
  end
end
