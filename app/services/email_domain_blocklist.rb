# Email domains WISP doesn't take accounts from: a few top-level domains where nearly every sign-up
# has been spam (Russian and nearby country domains, as legacy WISP blocked .ru, and the cheap
# generic ones spammers register by the thousand), and the community list of disposable-address
# services (config/email_blocklist/disposable.txt, refreshed with bin/rails email_blocklist:update).
# A domain matches its subdomains too (x.mail.ru, inbox.mailinator.com).
class EmailDomainBlocklist
  TOP_LEVEL_DOMAINS = %w[ru su by ua fun site website online top xyz icu click cfd sbs buzz].to_set.freeze
  DISPOSABLE_FILE = Rails.root.join("config/email_blocklist/disposable.txt")

  def self.blocked?(email)
    domain = email.to_s.strip.downcase.split("@", 2)[1].to_s.delete_suffix(".")
    return false if domain.empty?

    labels = domain.split(".")
    return true if TOP_LEVEL_DOMAINS.include?(labels.last)
    (0...labels.size - 1).any? { |i| disposable.include?(labels[i..].join(".")) }
  end

  def self.disposable
    @disposable ||= File.foreach(DISPOSABLE_FILE).map(&:strip).reject { |line| line.empty? || line.start_with?("#") }.to_set.freeze
  end
end
