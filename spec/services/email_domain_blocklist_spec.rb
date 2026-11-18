require "rails_helper"

RSpec.describe EmailDomainBlocklist do
  it "blocks the listed top-level domains, as legacy WISP blocked .ru" do
    %w[a@mail.ru a@rambler.ua a@postpro.fun a@triol.site a@ggmail.website A@Mail.RU].each do |email|
      expect(described_class.blocked?(email)).to be(true), email
    end
  end

  it "blocks disposable-address services and their subdomains" do
    expect(described_class.blocked?("a@mailinator.com")).to be(true)
    expect(described_class.blocked?("a@inbox.mailinator.com")).to be(true)
  end

  it "allows ordinary addresses, including ones that only contain a listed name" do
    %w[a@gmail.com a@wisc.edu a@tds.net a@example.farm a@notmailinator.example a@ru.example.com].each do |email|
      expect(described_class.blocked?(email)).to be(false), email
    end
  end

  it "leaves addresses without a domain to the format check" do
    expect(described_class.blocked?("")).to be(false)
    expect(described_class.blocked?("nobody")).to be(false)
  end
end
