# Wording shared by the daily digest's HTML and text parts
module DigestHelper
  # "Potato (Russet) · Home farm › Pivot 1", with the operation when the digest spans several
  def digest_place(entry, digest)
    planting = entry.status.planting
    crop = planting.variety.present? ? "#{planting.plant.name} (#{planting.variety})" : planting.plant.name
    place = [(entry.group.name if digest.several_groups?), entry.farm.name, entry.field.pivot.name].compact.join(" › ")
    "#{crop} · #{place}"
  end

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

  # The one-line outlook for a field that's fine, or why there isn't one
  def digest_summary(entry)
    if entry.status.weather_pending? then "Weather for this pivot is on the way."
    elsif entry.outlook then entry.outlook.headline
    else "No forecast yet."
    end
  end
end
