require "rails_helper"

RSpec.describe DailyEntry do
  let(:field) { create(:field) }
  let(:date) { Date.new(2026, 7, 1) }

  it "creates an entry, changes only the values given, and deletes it once empty" do
    FieldEntry.record(field.field_entries, date, rain_in: 0.5, notes: "  gauge ")
    expect(field.field_entries.sole).to have_attributes(rain_in: 0.5, notes: "gauge")

    FieldEntry.record(field.field_entries, date, {"irrigation_in" => 0.0})
    expect(field.field_entries.sole).to have_attributes(rain_in: 0.5, irrigation_in: 0.0)

    FieldEntry.record(field.field_entries, date, rain_in: nil, irrigation_in: nil, notes: " ")
    expect(field.field_entries.reload).to be_empty
  end

  it "ignores unknown keys and returns an invalid entry unsaved" do
    entry = FieldEntry.record(field.field_entries, date, soil_moisture_pct: 120, field_id: 0)
    expect(entry).not_to be_persisted
    expect(entry.errors).to include(:soil_moisture_pct)
  end

  it "doesn't create anything for an empty day" do
    FieldGroupEntry.record(create(:field_group).field_group_entries, date, rain_in: nil)
    expect(FieldGroupEntry.count).to eq(0)
  end
end
