require "rails_helper"

# The digest's wording, for the cases the mailer specs' fields don't reach
RSpec.describe DigestHelper, type: :helper do
  let(:user) { build(:user, digest_frequency: "daily") }
  let(:digest) { DailyDigest.new(user) }
  let(:planting) do
    build(:planting, plant: build(:plant, name: "Potato"), variety: nil, season_start: Date.new(2027, 4, 1),
      end_date: Date.new(2027, 9, 15))
  end

  def entry(status: double(planting:), farm: "Home", pivot: "Pivot 1", group: "Sands Farms")
    double(status:, group: double(name: group), farm: double(name: farm), pivot: double(name: pivot))
  end

  it "names the crop with its variety when there is one" do
    expect(helper.digest_crop(entry)).to eq("Potato")
    planting.variety = "Russet"
    expect(helper.digest_crop(entry)).to eq("Potato (Russet)")
  end

  it "names the operation in a field's place only when the email spans several" do
    allow(digest).to receive(:several_groups?).and_return(false)
    expect(helper.digest_place(entry, digest)).to eq("Home › Pivot 1")
    allow(digest).to receive(:several_groups?).and_return(true)
    expect(helper.digest_place(entry, digest)).to eq("Sands Farms › Home › Pivot 1")
  end

  it "says when a field's season starts, or ended, or that it has no crop" do
    expect(helper.digest_off_season(entry(status: double(planting:, phase: :upcoming)))).to eq("Potato · season starts Apr 1")
    expect(helper.digest_off_season(entry(status: double(planting:, phase: :ended)))).to eq("Potato · season ended Sep 15")
    expect(helper.digest_off_season(entry(status: nil))).to eq("No crop this season")
  end

  it "gives the latest rain or irrigation, or none" do
    irrigated = double(inputs: double(irrigation: 0.6, date: Date.new(2026, 7, 6)))
    status = double(last_rain: nil, last_irrigation: irrigated)
    expect(helper.digest_last(entry(status:), digest, :irrigation)).to eq("0.60 in, Jul 6")
    expect(helper.digest_last(entry(status:), digest, :rain)).to eq("none recorded")
  end

  it "says when a field has no forecast yet" do
    status = double(weather_pending?: false)
    expect(helper.digest_summary(double(status:, outlook: nil))).to eq("No forecast is available for this field yet.")
  end

  it "gives a zone's weather with what's there, and says when none of it is" do
    span = ->(**values) { WeatherSummary::Span.new(days: 7, precip: nil, et0: nil, tmax: nil, tmin: nil, **values) }
    section = double(weather: {past: span.call(precip: 0.4, tmin: 50.0..60.0), ahead: span.call(days: 1)})
    expect(helper.digest_weather(section, digest)).to eq(["Past 7 days: 0.40 in rain · lows 50–60°F", "Next 1 day: not available yet"])
    expect(helper.digest_weather(double(weather: {past: nil, ahead: nil}), digest)).to eq(["Weather for these pivots is on the way."])
  end

  it "says how often the email comes, for each frequency" do
    {"needed" => "on mornings when a field needs irrigation within 3 days.", "daily" => "each morning while your fields are in season.",
     "daily_all_year" => "every morning, all year."}.each do |frequency, ending|
      user.digest_frequency = frequency
      expect(helper.digest_reason(user, test: false)).to eq("You get this email from WISP #{ending}")
    end
    user.digest_frequency = "never"
    expect(helper.digest_reason(user, test: false)).to eq("WISP's daily email is turned off for you.")
  end
end
