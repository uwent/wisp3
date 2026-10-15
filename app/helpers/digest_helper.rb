# Wording shared by the daily digest's HTML and text parts
module DigestHelper
  # "Potato (Russet)"
  def digest_crop(entry)
    planting = entry.status.planting
    planting.variety.present? ? "#{planting.plant.name} (#{planting.variety})" : planting.plant.name
  end

  # "Home farm › Pivot 1", with the operation when the digest spans several
  def digest_place(entry, digest)
    [(entry.group.name if digest.several_groups?), entry.farm.name, entry.pivot.name].compact.join(" › ")
  end

  # "Weather zone 1 (44.13°N, 89.52°W)"
  def digest_zone(zone)
    cell = zone.cell
    "Weather zone #{zone.number} (#{format("%.2f", cell.latitude.abs)}°#{cell.latitude.negative? ? "S" : "N"}, " \
      "#{format("%.2f", cell.longitude.abs)}°#{cell.longitude.negative? ? "W" : "E"})"
  end

  # The pivots a weather zone covers: "North 160, South 80"
  def digest_zone_pivots(zone) = zone.pivots.map { |section| section.pivot.name }.join(", ")

  # "AD 0.45 in of 1.20 in · 9.5% moisture", or just "AD 0.45 in"
  def digest_ad(entry, digest, short: false)
    result = entry.status.current.result
    return "AD #{digest.depth(result.ad)}" if short

    "AD #{digest.depth(result.ad)} of #{digest.depth(entry.status.params.ad_max)} · #{format("%.1f", result.pct_moisture)}% moisture"
  end

  # The latest rain or irrigation: "0.40 in, Oct 1", or "None"
  def digest_last(entry, digest, kind)
    day = (kind == :rain) ? entry.status.last_rain : entry.status.last_irrigation
    day ? "#{digest.depth(day.inputs.public_send(kind))}, #{day.inputs.date.strftime("%b %-d")}" : "None"
  end

  # What's due for a field (PlantingTasks): ["Enter a soil moisture reading (last Oct 1)", …]
  def digest_tasks(entry) = entry.status.tasks.select(&:due).map(&:todo)

  # The one-line outlook for a field that's fine, or why there isn't one
  def digest_summary(entry)
    if entry.status.weather_pending? then "Weather for this pivot is on the way."
    elsif entry.outlook then entry.outlook.headline
    else "No forecast yet."
    end
  end

  # A weather zone's weather, one line each for the last week and the week ahead:
  # ["Past 7 days: 0.85 in rain · 1.12 in ET · highs 68–82°F, lows 48–60°F", "Next 7 days: …"]
  def digest_weather(section, digest)
    lines = {past: "Past", ahead: "Next"}.filter_map do |key, label|
      span = section.weather[key]
      next unless span

      temps = [("highs #{digest.temperatures(span.tmax)}" if span.tmax), ("lows #{digest.temperatures(span.tmin)}" if span.tmin)]
      parts = [("#{digest.depth(span.precip)} rain" if span.precip), ("#{digest.depth(span.et0)} ET" if span.et0),
        temps.compact.join(", ").presence].compact
      "#{label} #{span.days} #{"day".pluralize(span.days)}: #{parts.any? ? parts.join(" · ") : "no data"}"
    end
    lines.presence || ["Weather for these pivots is on the way."]
  end

  # Why the reader gets this email, and how often
  def digest_reason(user, test:)
    reason = case user.digest_frequency
    when "needed" then "You get this email from WISP on mornings when a field needs irrigation within #{PlantingStatus::LEAD_DAYS} days."
    when "daily" then "You get this email from WISP each morning while your fields are in season."
    else "WISP's daily email is turned off for you."
    end
    test ? "This is a test you sent from WISP's Alerts page. #{reason}" : reason
  end
end
