require "rails_helper"

# The days each account used WISP and which parts (ActivityDay, RecordsActivity)
RSpec.describe "Activity days", type: :request do
  let(:user) { create(:user) }
  let(:phone) { {"User-Agent" => "Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) Mobile/15E148"} }

  it "records each part of WISP used once a day, and whether any of it was on a phone" do
    sign_in user
    travel_to(Time.zone.parse("2026-07-20 08:00")) do
      get root_path
      get map_path
      get root_path
      expect(ActivityDay.sole).to have_attributes(user_id: user.id, date: Date.new(2026, 7, 20),
        areas: %w[dashboard map], phone: false)

      get root_path, headers: phone
      expect(ActivityDay.sole.phone).to be(true)
    end

    travel_to(Time.zone.parse("2026-07-21 08:00")) do
      get daily_entry_path
      expect(ActivityDay.order(:date).last).to have_attributes(date: Date.new(2026, 7, 21), areas: %w[daily])
    end
  end

  it "writes once per area per day, not on every request" do
    sign_in user
    get root_path
    expect(ActivityDay).not_to receive(:record)
    get root_path
  end

  it "counts a CSV download as reports, and leaves out what isn't a part of WISP" do
    sign_in user
    get season_report_path(format: :csv)
    get weather_updates_path(format: :json)
    expect(ActivityDay.sole.areas).to eq(%w[reports])
  end

  it "isn't recorded for admins, while impersonating, or on the example farm" do
    admin = create(:user, admin: true)
    sign_in admin
    get root_path
    post admin_user_impersonation_path(user)
    get root_path
    expect(ActivityDay.count).to eq(0)

    sign_out admin
    create(:planting, field: create(:field, pivot: create(:pivot, farm: create(:farm,
      group: create(:group, example_as_of: Date.new(2026, 7, 20))))))
    get example_path
    get root_path
    expect(ActivityDay.count).to eq(0)
  end

  it "is deleted with the account" do
    sign_in user
    get root_path
    expect { user.destroy! }.to change(ActivityDay, :count).by(-1)
  end
end
