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
    FieldEntry.record(field.field_entries, date, rain_in: nil)
    expect(FieldEntry.count).to eq(0)
  end

  describe "a day ahead" do
    before { travel_to Time.zone.local(2026, 7, 1, 12) }

    it "takes planned irrigation and notes, but not rain or readings" do
      ahead = date + 1
      expect(FieldEntry.record(field.field_entries, ahead, irrigation_in: 1.0, notes: "planned")).to be_persisted
      entry = FieldEntry.record(field.field_entries, ahead, rain_in: 0.5, soil_moisture_pct: 30)
      expect(entry.errors.attribute_names).to contain_exactly(:rain_in, :soil_moisture_pct)
      expect(FieldEntry.record(field.field_entries, date, rain_in: 0.5)).to be_persisted
    end

    it "is ahead of the day the pages show (Current.today), not the server's date" do
      Current.as_of = date - 10
      entry = FieldEntry.record(field.field_entries, date, rain_in: 0.5)
      expect(entry.errors).to include(:rain_in)
    end
  end
end
