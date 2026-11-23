require "rails_helper"

# The demo file (db/demo/farms.yml) changes as the demo is tidied, so these check that it builds and
# round-trips, not what's in it
RSpec.describe DemoSeed do
  before { ReferenceData.load! }

  def demo_group = User.find_by!(email: "demo@example.com").groups.find_by!(name: DemoSeed::GROUP_NAME)

  it "builds every farm, system, field and planting in the demo file" do
    data = YAML.safe_load_file(DemoSeed::FILE)
    result = described_class.new(email: "demo@example.com", year: 2026).run
    expect(result[:password]).to be_present

    systems = data["farms"].flat_map { |farm| farm["systems"] }
    fields = systems.flat_map { |system| system["fields"] }
    expect(result).to include(farms: data["farms"].size, fields: fields.size,
      plantings: fields.sum { |field| Array(field["plantings"]).size })
    group = demo_group
    expect(group.systems.count).to eq(systems.size)
    group.fields.where.not(boundary: nil).each do |field|
      expect(FieldBoundary.errors(field.boundary)).to be_empty, "#{field.name}: #{FieldBoundary.errors(field.boundary)}"
    end
  end

  it "exports what it seeded, so the demo can be edited in the app and written back" do
    described_class.new(email: "demo@example.com", year: 2026).run
    exported = DemoExport.new(demo_group, year: 2026).to_yaml

    file = Tempfile.create(["farms", ".yml"])
    File.write(file.path, exported)
    described_class.new(email: "demo@example.com", year: 2026, file: file.path).run
    expect(DemoExport.new(demo_group, year: 2026).to_yaml).to eq(exported)
  ensure
    File.unlink(file.path) if file
  end

  it "rebuilds rather than duplicating, and keeps the user's password" do
    described_class.new(email: "demo@example.com", password: "a fine password").run
    result = described_class.new(email: "demo@example.com").run
    user = User.find_by!(email: "demo@example.com")
    expect(user.groups.where(name: DemoSeed::GROUP_NAME).count).to eq(1)
    expect(result[:password]).to be_nil
    expect(user.valid_password?("a fine password")).to be(true)
  end
end
