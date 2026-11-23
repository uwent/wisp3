require "csv"

# What WISP's CSV exports share. Each opens with frontmatter, as PRISM's exports do: a title line,
# then "Label: value" lines in the first column (what the file covers, its units, who exported it
# and when, where the data comes from), and a blank line before the data. Numbers have four
# decimals and missing values are left blank; names typed by growers are escaped so a spreadsheet
# doesn't run them as formulas. Files start with a UTF-8 byte order mark, without which Excel reads
# them as Windows-1252 (° and – garbled). The frontend's chart downloads (lib/csv.ts) open the same way.
module CsvExport
  BOM = "\uFEFF"

  SOURCE = "WISP, the Wisconsin Irrigation Scheduling Program (University of Wisconsin–Madison); " \
    "weather modeled by Open-Meteo"
  UNITS = "depths in inches, temperatures in °F, as WISP stores them"

  private

  def generate(&) = CSV.generate(BOM.dup, &)

  # details: {label => value}, after the title; a nil value leaves its line out
  def frontmatter(csv, title, details, exported_by:, about_url:, units: UNITS)
    exported = Time.current.strftime("%Y-%m-%d %H:%M %Z")
    lines = details.merge("Units" => units, "Exported by" => exporter(exported_by), "Exported" => exported,
      "Source" => SOURCE, "Details" => about_url)
    csv << [title]
    lines.each { |label, value| csv << ["#{label}: #{value}"] unless value.nil? }
    csv << []
  end

  # The frontmatter line naming the weather corrections, for exports with weather in them
  def weather_corrections
    labels = Weather::Corrections::DAILY.map { |id| Weather::Corrections.label(id) }
    {"Weather corrections" => "Open-Meteo's solar radiation and humidity corrected against Wisconsin weather " \
      "stations, and reference ET computed by WISP from them (#{labels.join(", ")}); see Details"}
  end

  def exporter(user)
    user && (user.name.present? ? "#{user.name} (#{user.email})" : user.email)
  end

  def num(value) = value && format("%.4f", value)

  # Text a spreadsheet would read as a formula (=, +, -, @, or a leading tab or return) gets a quote;
  # a plain number written as text ("-4.5") doesn't, as it can't run anything. Same rule as lib/csv.ts.
  def text(value)
    formula = value.is_a?(String) && value.match?(/\A[=+\-@\t\r]/) && !value.match?(/\A-?\d+(\.\d+)?\z/)
    formula ? "'#{value}" : value
  end

  def pct(fraction) = (fraction * 100).round(2)
end
