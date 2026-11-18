namespace :email_blocklist do
  desc "Download the current list of disposable email domains into config/email_blocklist/disposable.txt"
  task update: :environment do
    require "net/http"

    source = "https://github.com/disposable-email-domains/disposable-email-domains"
    url = URI("https://raw.githubusercontent.com/disposable-email-domains/disposable-email-domains/main/disposable_email_blocklist.conf")
    response = Net::HTTP.get_response(url)
    abort "Couldn't download the list: HTTP #{response.code}" unless response.is_a?(Net::HTTPSuccess)

    domains = response.body.lines.map(&:strip).reject { |line| line.empty? || line.start_with?("#") }
    abort "The download had only #{domains.size} domains; leaving the list as it was" if domains.size < 1000

    File.write(EmailDomainBlocklist::DISPOSABLE_FILE, <<~TEXT + domains.join("\n") + "\n")
      # Disposable email domains, from #{source}
      # (disposable_email_blocklist.conf, CC0), downloaded #{Date.current.iso8601}. Refresh with bin/rails email_blocklist:update.
    TEXT
    puts "#{domains.size} domains written to #{EmailDomainBlocklist::DISPOSABLE_FILE.relative_path_from(Rails.root)}"
  end
end
