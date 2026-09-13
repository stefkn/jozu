module Learning
  # Keeps issued questions available for answer verification and idempotency.
  # Backed by the Rails cache with a short TTL — the quiz is stateless otherwise.
  class QuestionStore
    TTL = 24.hours
    KEY_PREFIX = "jozu:question"

    def self.put(question)
      Rails.cache.write(key(question.token), question, expires_in: TTL)
    end

    def self.fetch(token)
      Rails.cache.read(key(token))
    end

    def self.delete(token)
      Rails.cache.delete(key(token))
    end

    def self.key(token)
      "#{KEY_PREFIX}:#{token}"
    end
  end
end
