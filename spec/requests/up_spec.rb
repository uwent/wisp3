require "rails_helper"

RSpec.describe "/up", type: :request do
  let(:problem) do
    HealthCheck::Problem.new(kind: :missing_weather, summary: "2 weather cells missing weather",
      details: ["Cell 4 (44.1200, -89.5300): no forecast", "Cell 9 (43.0100, -89.4000): no forecast"])
  end

  it "says it's up, signed out, with the database and no health check yet" do
    get "/up"
    expect(response).to have_http_status(:ok)
    expect(response.headers["Cache-Control"]).to eq("no-store")
    expect(response.parsed_body).to include("status" => "ok", "database" => "ok",
      "health_check" => {"checked_at" => nil, "overdue" => false, "problems" => {}})
  end

  it "is degraded when the last health check found problems, giving only their kinds and counts" do
    allow_any_instance_of(HealthCheck).to receive(:problems).and_return([problem])
    HealthCheck.run(now: Time.zone.local(2026, 7, 20, 7))

    get "/up"
    expect(response).to have_http_status(:ok)
    expect(response.parsed_body).to include("status" => "degraded")
    expect(response.parsed_body["health_check"]).to include("checked_at" => "2026-07-20T07:00:00-05:00",
      "problems" => {"missing_weather" => 2})
    expect(response.body).not_to include("Cell 4", "44.12")
  end

  it "is degraded when the morning check is overdue where jobs run" do
    allow(HealthCheck).to receive(:solid_queue?).and_return(true)
    get "/up"
    expect(response.parsed_body).to include("status" => "degraded")
    expect(response.parsed_body["health_check"]).to include("overdue" => true)
  end

  it "is down when the database doesn't answer" do
    allow(ActiveRecord::Base.connection).to receive(:select_value).and_raise(ActiveRecord::ConnectionNotEstablished)
    get "/up"
    expect(response).to have_http_status(:service_unavailable)
    expect(response.parsed_body).to include("status" => "down", "database" => "error", "health_check" => nil)
  end
end
