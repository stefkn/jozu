require "rails_helper"

RSpec.describe "Access-link profile on mobile", type: :system do
  include CorpusHelper

  before { build_corpus! }

  it "creates a profile, saves its link and restores it after signing out" do
    visit root_path
    click_on "Create my learning profile"
    expect(page).to have_content("Save your access link")
    link = find("#access-link").value
    expect(link).to include("/access/")
    click_on "Copy link"
    expect(page).to have_css('[role="status"]', text: /Link copied|Select and copy/)
    click_on "Start learning"
    expect(page).to have_content("Take the diagnostic")
    click_on "Settings"
    click_on "Sign out"
    expect(page).to have_content("Create my learning profile")
    visit link
    expect(page).to have_content("Bookmark this page")
    click_on "Continue to my profile"
    click_on "Settings"
    expect(find("#access-link").value).to eq(link)
    expect(User.count).to eq(1)
    expect(page.evaluate_script("document.documentElement.scrollWidth <= window.innerWidth")).to be true
    page.save_screenshot(Rails.root.join("tmp/screenshots/accounts-mobile.png"))
  end
end
