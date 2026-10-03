module Weather
  # The ECMWF IFS O1280 octahedral reduced Gaussian grid (~9 km), which Open-Meteo's ecmwf_ifs
  # model uses: 2N = 2560 latitude rings at the Gauss–Legendre nodes, ring k from the nearest pole
  # holding 20 + 4(k − 1) evenly spaced points starting at longitude 0. Pivots are grouped into
  # its cells, and requests are made at the cell center, so every pivot in a cell gets the same
  # series. Ported from Ben's R client (get_o1280_cells); only the rings near a point are computed.
  module Grid
    N = 1280
    RINGS = 2 * N
    Cell = Data.define(:latitude, :longitude, :ring, :lat_north, :lat_south, :lng_west, :lng_east)

    module_function

    def cell_for(latitude, longitude)
      j = ring_for(latitude)
      k = [j, RINGS - j + 1].min # rings from the nearest pole
      points = 20 + 4 * (k - 1)
      step = 360.0 / points
      i = ((longitude % 360) / step).round % points
      center = i * step
      center -= 360 if center > 180
      Cell.new(latitude: ring_latitude(j), longitude: center, ring: j, lat_north: edge(j - 1, j),
        lat_south: edge(j, j + 1), lng_west: center - step / 2, lng_east: center + step / 2)
    end

    # Ring index (1 = northernmost) whose band contains the latitude
    def ring_for(latitude)
      guess = ((90.0 - latitude) / 180.0 * (RINGS + 0.5) + 0.25).round.clamp(1, RINGS)
      (guess - 2..guess + 2).map { |j| j.clamp(1, RINGS) }.uniq.find do |j|
        latitude <= edge(j - 1, j) && latitude > edge(j, j + 1)
      end || guess
    end

    # Latitude boundary between two rings: halfway between them (±90 at the poles)
    def edge(north, south)
      return 90.0 if north < 1
      return -90.0 if south > RINGS
      (ring_latitude(north) + ring_latitude(south)) / 2
    end

    # Latitude (degrees) of ring j: the j-th largest root of the Legendre polynomial P_2N
    def ring_latitude(j)
      @latitudes ||= {}
      @latitudes[j] ||= begin
        x = Math.cos(Math::PI * (j - 0.25) / (RINGS + 0.5)) # asymptotic first guess
        6.times do
          p_n, p_prev = legendre(x)
          derivative = RINGS * (x * p_n - p_prev) / (x * x - 1)
          x -= p_n / derivative
        end
        Math.asin(x) * 180 / Math::PI
      end
    end

    # [P_n(x), P_(n−1)(x)] for n = RINGS, by the three-term recurrence
    def legendre(x)
      p_prev, p_n = 1.0, x
      (1...RINGS).each { |k| p_prev, p_n = p_n, ((2 * k + 1) * x * p_n - k * p_prev) / (k + 1) }
      [p_n, p_prev]
    end
  end
end
