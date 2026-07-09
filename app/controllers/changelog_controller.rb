class ChangelogController < ApplicationController
  CHANGELOG_PATH = Rails.root.join('CHANGELOG.md').freeze

  def index
    @body = File.exist?(CHANGELOG_PATH) ? File.read(CHANGELOG_PATH) : ''
  end
end
