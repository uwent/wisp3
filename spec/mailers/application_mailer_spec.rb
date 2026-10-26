require "rails_helper"

RSpec.describe ApplicationMailer do
  it "frames every email with the UW bar, WISP's header and the footer credit" do
    membership = create(:membership, group: create(:group), user: create(:user))

    mail = MembershipMailer.added(membership, create(:user))
    html = Nokogiri::HTML(mail.html_part.body.decoded)
    expect(html.at_css("body")["style"]).to include("background:#ffffff")
    expect(html.at_css("a[href='https://www.wisc.edu']").text).to eq("University of Wisconsin–Madison")
    expect(html.at_css("img[src='http://example.com/icon-email.png']")).to be_present
    expect(html.at_css("a[href='https://cals.wisc.edu/']").text).to eq("College of Agricultural and Life Sciences")
    expect(html.css("a").map { |link| link.attributes.key?("ses:no-track") }).to all(be true)
    expect(mail.text_part.body.decoded).to end_with(
      "Developed by the College of Agricultural and Life Sciences at the University of Wisconsin–Madison: https://cals.wisc.edu/\n"
    )
  end
end
