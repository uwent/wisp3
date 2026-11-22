require "rails_helper"
require Rails.root.join("db/migrate/20261122130000_store_irrigation_per_planting")

# The move of system irrigation into field and plot entries (D15): each planting keeps the amount the
# old precedence gave it. Runs inside the example's transaction (Postgres DDL is transactional), so
# the table it recreates and drops is rolled back with the rest.
RSpec.describe StoreIrrigationPerPlanting do
  let(:date) { Date.new(2026, 7, 10) }
  let(:a) { create(:pivot, name: "A", pump_capacity_gpm: 1000) }
  let(:b) { create(:pivot, name: "B", farm: a.farm) }

  def plot(field, pivot: field.pivot, **season)
    create(:planting, field:, partial: true, area_acres: 1, **season).tap { |planting| planting.update_column(:pivot_id, pivot.id) }
  end

  def irrigation(pivot, **values)
    columns = {pivot_id: pivot.id, date:, created_at: Time.current, updated_at: Time.current}.merge(values)
    columns[:field_ids] = "{#{columns[:field_ids].join(",")}}" if columns[:field_ids]
    ActiveRecord::Base.connection.insert_fixture(columns, "pivot_irrigations")
  end

  def field_amount(field) = FieldEntry.find_by(field:, date:)&.irrigation_in
  def plot_amount(plot) = PlantingEntry.find_by(planting: plot, date:)&.irrigation_in

  before do
    migration = described_class.new
    migration.verbose = false
    migration.down # the table as it was, empty
  end

  def migrate
    migration = described_class.new
    migration.verbose = false
    migration.up
  end

  it "gives each field its system's irrigation and each plot its own system's, a field's own amount first" do
    whole = create(:field, pivot: a, name: "Whole")
    create(:planting, field: whole)
    # A field of plots: the earliest's system is the field's that day; the other's season runs on B
    field = create(:field, pivot: a, name: "F")
    on_a = plot(field, season_start: Date.new(2026, 4, 1))
    on_b = plot(field, pivot: b, season_start: Date.new(2026, 5, 1))
    own = create(:field, pivot: a, name: "Own")
    own_plot = plot(own)
    own.field_entries.create!(date:, irrigation_in: 0.3)
    left_out = create(:field, pivot: a, name: "Left out")
    create(:planting, field: left_out)
    irrigation(a, inches: 0.8, field_ids: [whole.id, field.id, own.id], notes: "Night")
    irrigation(b, inches: 0.5)

    migrate

    expect(field_amount(whole)).to eq(0.8)
    expect(field_amount(field)).to eq(0.8)
    expect(plot_amount(on_a)).to eq(0.8)
    expect(plot_amount(on_b)).to eq(0.5) # its own system's, not its field's
    expect(field_amount(own)).to eq(0.3) # its own amount stays
    expect(plot_amount(own_plot)).to eq(0.3) # the field's own amount came first
    expect(field_amount(left_out)).to be_nil
    expect(FieldEntry.find_by(field: own, date:).notes).to eq("Night")
    expect(ActiveRecord::Base.connection.table_exists?(:pivot_irrigations)).to be(false)
  end

  it "converts run hours over the acres watered, and keeps run hours it can't convert in the fields' notes" do
    north = create(:field, pivot: a, name: "North", area_acres: 50)
    south = create(:field, pivot: a, name: "South", area_acres: 50)
    [north, south].each { |field| create(:planting, field:) }
    on_b = create(:field, pivot: b, name: "On B", area_acres: 20)
    create(:planting, field: on_b)
    irrigation(a, run_hours: 10)
    irrigation(b, run_hours: 6, notes: "Gun only")

    migrate

    expect(field_amount(north)).to be_within(1e-4).of(1000.0 * 10 * 60 / (27_154 * 100))
    expect(field_amount(south)).to eq(field_amount(north))
    expect(field_amount(on_b)).to be_nil
    expect(FieldEntry.find_by(field: on_b, date:).notes).to eq("Ran 6 h (not converted to inches); Gun only")
  end
end
