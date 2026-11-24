require "rails_helper"

RSpec.describe "Normalizing names and free text" do
  it "trims a name, collapses its runs of space and drops control characters" do
    expect(Farm.normalize_value_for(:name, "  North\t\tFarm\n\u0000 ")).to eq("North Farm")
  end

  it "makes a name with nothing in it NULL" do
    expect(User.normalize_value_for(:first_name, " \n ")).to be_nil
  end

  it "keeps line breaks in notes, as \\n" do
    expect(Field.normalize_value_for(:notes, "  Wet corner\r\n\r\nTile\u0007 line  ")).to eq("Wet corner\n\nTile line")
  end

  it "makes notes with nothing in them NULL" do
    expect(Planting.normalize_value_for(:notes, "\r\n  ")).to be_nil
  end
end
