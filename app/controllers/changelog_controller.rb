class ChangelogController < ApplicationController
  CHANGELOG_PATH = Rails.root.join('CHANGELOG.md').freeze

  def index
    @body = Rails.cache.fetch('changelog:body', expires_in: 5.minutes) do
      File.exist?(CHANGELOG_PATH) ? File.read(CHANGELOG_PATH) : ''
    end
  end
end
