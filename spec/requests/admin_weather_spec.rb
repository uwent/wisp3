require "rails_helper"

RSpec.describe "Admin weather status", type: :request do
  let(:admin) { create(:user, admin: true) }

  it "is hidden from users who aren't admins" do
    sign_in create(:user)
    get root_path
    get admin_weather_path
    expect(response).to have_http_status(:not_found)
    post refresh_admin_weather_path
    expect(response).to have_http_status(:not_found)
  end

  it "requires signing in" do
    get admin_weather_path
    expect(response).to redirect_to(new_user_session_path)
  end

  it "shows the API mode and each cell's coverage, forecast and errors" do
    travel_to(Time.zone.parse("2026-07-20 12:00")) do
      field = create(:field, pivot: create(:pivot, latitude: 44.12, longitude: -89.53))
      create(:planting, field:, season_start: Date.new(2026, 7, 10), end_date: Date.new(2026, 9, 30))
      cell = field.pivot.reload.weather_cell
      cell.update!(timezone: "America/Chicago", last_error: "Open-Meteo 503", last_error_at: 1.hour.ago)
      (Date.new(2026, 7, 10)..Date.new(2026, 7, 17)).each do |date|
        cell.weather_days.create!(date:, model: "best_match", hours: 24, fetched_at: Time.current, final: date < Date.new(2026, 7, 13))
      end
      cell.weather_forecasts.create!(issued_at: 2.hours.ago, model: "best_match", payload: {days: [{date: "2026-08-04"}]})

      sign_in admin
      get admin_weather_path
      expect_inertia.to render_component("Admin/Weather")
      expect(inertia.props[:api]).to include(mode: "free", model: "best_match", soil_model: "ecmwf_ifs")
      expect(inertia.props[:cells].sole).to include(pivot_count: 1, active: true, season_start: "2026-07-10",
        days_stored: 8, missing_days: 2, provisional_days: 5, latest_date: "2026-07-17",
        forecast_through: "2026-08-04", last_error: "Open-Meteo 503")
    end
  end

  it "queues a refresh" do
    sign_in admin
    expect { post refresh_admin_weather_path }.to have_enqueued_job(WeatherRefreshJob)
    expect(response).to redirect_to(admin_weather_path)
  end
end
