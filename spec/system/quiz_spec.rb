require "rails_helper"

RSpec.describe "Quiz session", type: :system do
  include CorpusHelper

  before do
    build_corpus!
    make_user
    uk = UserKanji.create!(user: User.first, kanji: Kanji.first)
    uk.update_column(:created_at, 1.day.ago)
  end

  it "completes a full session and updates progress" do
    visit root_path
    expect(page).to have_content("Today's session")
    expect(page).not_to have_content("Take the diagnostic")
    click_on "Start"

    answered = 0
    while (frame = quiz_frame)
      token_before = frame.find("#question_token", visible: false).value
      frame.find("button[data-correct='true']", match: :first).click
      frame.find("button[name='confidence'][value='knew']").click
      answered += 1
      wait_until(frame_advances(token_before))
    end

    expect(answered).to eq(3)
    expect(page).to have_content("Session complete", wait: 5)
    expect(Review.count).to eq(3)
    expect(UserKanji.where(times_seen: 1).count).to eq(3)

    click_on "Done"
    expect(page).to have_content("Today's session")
  end

  private

  def quiz_frame
    page.find("[data-controller='quiz']", wait: 5)
  rescue Capybara::ElementNotFound
    nil
  end

  # Returns true once the frame is replaced by the next question or the
  # session-complete card.
  def frame_advances(previous_token)
    ->(_) {
      return true if page.has_content?("Session complete")

      current = begin
        page.find("#question_token", visible: false).value
      rescue Capybara::ElementNotFound
        return true
      end
      current != previous_token
    }
  end

  def wait_until(predicate)
    Timeout.timeout(10) do
      sleep 0.05 until predicate.call(self)
    end
  rescue Timeout::Error
    warn ">>> PAGE HTML AT TIMEOUT:\n#{page.html[0, 3000]}"
    raise Capybara::ExpectationNotMet, "quiz frame did not advance in time"
  end
end
