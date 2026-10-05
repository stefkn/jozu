require "rails_helper"

RSpec.describe User do
  it "assigns different random UUIDv4 access links to new users" do
    first = create(:user)
    second = create(:user)
    expect(first.access_token).to match(/\A[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}\z/)
    expect(second.access_token).not_to eq(first.access_token)
    expect(first.reload.access_token).to eq(first.access_token)
    expect(build(:user, access_token: first.access_token)).not_to be_valid
  end
end
