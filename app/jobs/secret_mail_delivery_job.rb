# Delivers mail whose arguments are secrets, without logging them: a sign-in link's token and its
# code would otherwise appear in the log as each job is enqueued and performed
class SecretMailDeliveryJob < ActionMailer::MailDeliveryJob
  self.log_arguments = false
end
