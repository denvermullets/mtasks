class ApplicationMailer < ActionMailer::Base
  default from: ENV.fetch('DEFAULT_FROM_EMAIL', 'noreply@mtasks.app')
  layout 'mailer'
end
