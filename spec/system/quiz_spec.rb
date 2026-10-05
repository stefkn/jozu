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
    visit access_path(access_token: make_user.access_token)
    click_on "Continue to my profile"
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

    # Burst: each new kanji gets meaning + kana + sentence follow-ups, so the
    # session runs to the daily review target (10) across 4 kanji (1 stale + 3 new).
    expect(answered).to eq(10)
    expect(page).to have_content("Session complete", wait: 5)
    expect(Review.count).to eq(10)
    expect(UserKanji.count).to eq(4)

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
  # session-complete card. Selenium can raise transient "node detached"
  # errors when Chrome inspects a node Turbo swaps out mid-poll; treat
  # those as "not advanced yet" and let the next poll decide.
  def frame_advances(previous_token)
    ->(_) {
      content_done = begin
        page.has_content?("Session complete")
      rescue Selenium::WebDriver::Error::UnknownError
        false
      end
      return true if content_done

      current = begin
        page.find("#question_token", visible: false).value
      rescue Capybara::ElementNotFound, Selenium::WebDriver::Error::UnknownError
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
