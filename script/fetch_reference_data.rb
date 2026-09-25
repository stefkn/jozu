#!/usr/bin/env ruby
# frozen_string_literal: true

# Downloads the pinned jkindrix/japanese-language-data files into
# vendor/data/sources/ (gitignored). Run this once, then:
#   bin/rails jozu:convert_reference
# to build the TSVs the importer reads.
#
# The dataset is CC BY-SA 4.0; see vendor/data/sources/ATTRIBUTION.md and the
# root ATTRIBUTION.md. Pin SHA overrides via JLD_SHA for reproducibility.

require "net/http"
require "fileutils"

REPO = "jkindrix/japanese-language-data"
SHA = ENV.fetch("JLD_SHA", "04014e06019fc9d4af76e6dbb64ec709fe863c4d")
FILES = %w[
  data/core/kanji.json
  data/core/words.json
  data/core/radicals.json
  data/enrichment/frequency-web.json
  LICENSE
  ATTRIBUTION.md
  README.md
].freeze
DEST = File.expand_path("../vendor/data/sources", __dir__)

def fetch(url, dest)
  uri = URI(url)
  response = Net::HTTP.start(uri.host, uri.port, use_ssl: true) do |http|
    http.request(Net::HTTP::Get.new(uri))
  end
  abort "Failed #{url}: #{response.code}" unless response.is_a?(Net::HTTPSuccess)

  File.write(dest, response.body)
  puts "  #{dest} (#{response.body.bytesize} bytes)"
end

FileUtils.mkdir_p(DEST)
FILES.each do |path|
  puts "Fetching #{path}..."
  fetch("https://raw.githubusercontent.com/#{REPO}/#{SHA}/#{path}", File.join(DEST, File.basename(path)))
end

puts "Done. Next: bin/rails jozu:convert_reference"
