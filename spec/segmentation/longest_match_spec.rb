require "rails_helper"

RSpec.describe Segmentation::LongestMatch do
  it "segments a string by the longest match" do
    segmenter = described_class.build(%w[決める 必ず 必要 先生])
    tokens = segmenter.segment("先生は必ず決める")
    expect(tokens.map(&:surface)).to eq(%w[先生 必ず 決める])
  end

  it "skips unmatched characters" do
    segmenter = described_class.build(%w[決める])
    tokens = segmenter.segment("これは決めることです")
    expect(tokens.map(&:surface)).to eq(%w[決める])
  end

  it "reports correct character positions" do
    segmenter = described_class.build(%w[決める])
    token = segmenter.segment("明日決める").first
    expect(token.start_position).to eq(2)
    expect(token.end_position).to eq(4)
  end

  it "prefers the longer match when two words share a prefix" do
    segmenter = described_class.build(%w[必ず 必ずしも])
    tokens = segmenter.segment("必ずしも")
    expect(tokens.map(&:surface)).to eq(%w[必ずしも])
  end

  it "handles empty input" do
    expect(described_class.build(%w[a]).segment("")).to eq([])
  end
end
