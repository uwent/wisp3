namespace :golden do
  desc "Split a legacy export (script/legacy/export_golden_fixtures.rb) into spec/fixtures/legacy/"
  task import: :environment do
    # Skip anything legacy Rails printed to stdout before the JSON (e.g. boot warnings)
    text = File.read(ENV.fetch("FILE"))
    fixtures = JSON.parse(text[text.index(/^\[/)..])
    dir = Rails.root.join("spec/fixtures/legacy")
    fixtures.each do |fixture|
      File.write(dir.join("#{fixture.fetch("fixture")}.json"), JSON.pretty_generate(fixture) + "\n")
    end
    puts "Wrote #{fixtures.size} fixtures to #{dir.relative_path_from(Rails.root)}"
  end
end
