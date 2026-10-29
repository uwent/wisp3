require "rails_helper"

# The cases in outlook_cases.json, which lib/outlook.test.ts runs too
RSpec.describe Outlook do
  cases = JSON.parse(Rails.root.join("spec/fixtures/files/outlook_cases.json").read)

  # The parts of a PlantingStatus Outlook reads, from a case's summary (the field page's props)
  def status_from(summary)
    crossing = ->(c) { c && PlantingStatus::Crossing.new(date: Date.parse(c["date"]), days: c["days"], ad: c["ad"], refill: c["refill"]) }
    projection = summary["projection"].map { |day| day.merge("date" => Date.parse(day["date"])) }
    today = summary["date"] && Date.parse(summary["date"])
    double(PlantingStatus, phase: summary["phase"].to_sym, today:, current: today && :today,
      params: double(target_in: summary["target_in"]), crossing: crossing.call(summary["crossing"]),
      dry_crossing: crossing.call(summary["dry_crossing"]), ensemble_size: summary["ensemble_size"],
      forecast_days: projection.map { |day| double(inputs: double(date: day["date"])) },
      ensemble: projection.select { |day| day["chance"] }.map { |day|
        EnsembleProjection::Band.new(date: day["date"], p10: nil, p50: nil, p90: nil, chance: day["chance"])
      })
  end

  cases.fetch("cases").each do |example|
    it example["name"] do
      depth = DailyDigest.new(build(:user, unit_system: example["units"])).method(:depth)
      result = described_class.for(status_from(cases.fetch("base").merge(example["summary"])), depth:)
      expect(result&.to_h&.transform_keys(&:to_s)).to eq(example["expected"])
    end
  end
end
