# A field's outline (PLAN.md Phase 8 G.10): a GeoJSON Polygon or MultiPolygon in WGS84 longitude
# and latitude, for the map and the suggested area only (the balance never reads it). Drawn on the
# field's outline page or imported from a file in the browser, which simplifies a detailed shape to
# MAX_VERTICES. Limits and area are mirrored in lib/geo.ts.
class FieldBoundary
  # Plenty for a field's edge; CLU and machine exports are simplified to it on import
  MAX_VERTICES = 1000
  # Over two full sections; a field is rarely more than one
  MAX_ACRES = 1500
  MIN_ACRES = 0.01
  EARTH_RADIUS_M = 6_371_008.8
  SQUARE_METERS_PER_ACRE = 4046.8564224
  # About a centimeter; more digits are noise from reprojection
  DIGITS = 7

  # The geometry as stored: a Polygon or MultiPolygon with 2D positions rounded to DIGITS, or the
  # value as given when it isn't readable (errors says why). A JSON string is parsed.
  def self.normalize(value)
    value = JSON.parse(value) if value.is_a?(String)
    return value unless value.is_a?(Hash)
    type = value["type"] || value[:type]
    coordinates = value["coordinates"] || value[:coordinates]
    rounded = position_map(coordinates, (type == "MultiPolygon") ? 3 : 2)
    rounded ? {"type" => type, "coordinates" => rounded} : value
  rescue JSON::ParserError
    value
  end

  # What's wrong with a geometry, as sentences for the field's boundary attribute
  def self.errors(geometry)
    polygons = polygons(geometry)
    return ["must be a polygon or multipolygon"] unless polygons
    rings = polygons.flatten(1)
    errors = []
    errors << "has a ring with fewer than 3 corners" if rings.any? { |ring| ring.length < 4 }
    errors << "has a ring that isn't closed" if rings.any? { |ring| ring.length >= 4 && ring.first != ring.last }
    if vertex_count(geometry) > MAX_VERTICES
      errors << "has too many corners (at most #{MAX_VERTICES.to_fs(:delimited)}; simplify it)"
    end
    positions = rings.flatten(1)
    unless positions.all? { |lng, lat| Pivot::LATITUDES.cover?(lat) && Pivot::LONGITUDES.cover?(lng) }
      errors << "must be in the US or Canada"
    end
    return errors if errors.any?
    acres = acres(geometry)
    errors << "is too small (at least #{MIN_ACRES} acres)" if acres < MIN_ACRES
    errors << "is larger than a field (at most #{MAX_ACRES.to_fs(:delimited)} acres)" if acres > MAX_ACRES
    errors
  end

  # The polygons' rings, [[outer, *holes], ...], or nil for anything else
  def self.polygons(geometry)
    return unless geometry.is_a?(Hash)
    case geometry["type"]
    when "Polygon" then [geometry["coordinates"]]
    when "MultiPolygon" then geometry["coordinates"]
    end
  end

  # Corners counted once each (a ring's closing position repeats its first)
  def self.vertex_count(geometry)
    (polygons(geometry) || []).flatten(1).sum { |ring| [ring.length - 1, 0].max }
  end

  # Area in acres on a spherical earth: each polygon's outer ring less its holes
  def self.acres(geometry)
    (polygons(geometry) || []).sum do |outer, *holes|
      ring_area_m2(outer) - holes.sum { |hole| ring_area_m2(hole) }
    end / SQUARE_METERS_PER_ACRE
  end

  # The spherical excess of a ring (Chamberlain and Duquette, 2007, as Turf computes it), in m²
  def self.ring_area_m2(ring)
    n = ring.length
    return 0.0 if n < 4
    radians = ring.map { |lng, lat| [lng * Math::PI / 180, lat * Math::PI / 180] }
    total = (0...n - 1).sum do |i|
      lower = radians[i]
      middle = radians[(i + 1) % (n - 1)]
      upper = radians[(i + 2) % (n - 1)]
      (upper[0] - lower[0]) * Math.sin(middle[1])
    end
    (total * EARTH_RADIUS_M**2 / 2).abs
  end

  # Positions nested depth arrays deep, each [lng, lat] (an altitude dropped) rounded; nil when
  # the nesting or a position isn't numbers
  def self.position_map(value, depth)
    return unless value.is_a?(Array)
    if depth.zero?
      return unless value.length >= 2 && value[0..1].all?(Numeric)
      return value[0..1].map { |number| number.to_f.round(DIGITS) }
    end
    mapped = value.map { |inner| position_map(inner, depth - 1) }
    mapped unless mapped.any?(&:nil?)
  end
  private_class_method :position_map
end
