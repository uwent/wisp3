require "net/http"

module Weather
  # Open-Meteo client (PLAN.md §8). Requests hourly values in metric units with timezone=auto,
  # so times come back in each location's local time; Weather::Daily turns them into daily
  # values. With an API key (OPEN_METEO_API_KEY, or credentials open_meteo.api_key) it uses the
  # customer-* hosts; without one, the free hosts and the free-tier rate limits.
  class OpenMeteo
    ENDPOINTS = {
      forecast: ["api.open-meteo.com", "/v1/forecast"],
      historical_forecast: ["historical-forecast-api.open-meteo.com", "/v1/forecast"],
      archive: ["archive-api.open-meteo.com", "/v1/archive"],
      ensemble: ["ensemble-api.open-meteo.com", "/v1/ensemble"]
    }.freeze

    # Atmospheric variables come from the primary models; soil variables from ECMWF IFS, the only
    # model with them over North America (best_match, GFS and NBM return none).
    VARIABLES = %w[
      temperature_2m dew_point_2m relative_humidity_2m et0_fao_evapotranspiration precipitation rain
      snowfall snow_depth pressure_msl vapour_pressure_deficit wind_speed_10m wind_gusts_10m
      wind_direction_10m cloud_cover cloud_cover_low cloud_cover_mid cloud_cover_high
    ].freeze
    SOIL_VARIABLES = %w[
      soil_temperature_0_to_7cm soil_temperature_7_to_28cm soil_temperature_28_to_100cm
      soil_temperature_100_to_255cm soil_moisture_0_to_7cm soil_moisture_7_to_28cm
      soil_moisture_28_to_100cm soil_moisture_100_to_255cm
    ].freeze
    SOIL_MODEL = "ecmwf_ifs"
    # The ensemble for the projection's uncertainty (PLAN.md §6): GFS, 31 members (the control and
    # 30 perturbed) over the full 16 days. ECMWF's 51 members stop at 15 days. Each member has its
    # own et0 and precipitation.
    ENSEMBLE_MODEL = "gfs_seamless"
    ENSEMBLE_MEMBERS = 31
    ENSEMBLE_VARIABLES = %w[et0_fao_evapotranspiration precipitation].freeze
    BATCH_SIZE = 25 # locations per request
    RETRY_DELAYS = [2, 8].freeze # seconds, for 429 / 5xx / network errors before giving up

    # One location's hourly response
    Hourly = Data.define(:latitude, :longitude, :timezone, :elevation, :times, :values)

    def self.api_key = ENV["OPEN_METEO_API_KEY"].presence || Rails.application.credentials.dig(:open_meteo, :api_key)

    # Models for ET, rain and the rest, in order of preference: each daily value comes from the
    # first that has it. NBM matched AgWeather best (docs/weather-comparison.md) but covers only
    # the contiguous US and has no cloud cover, so best_match fills in.
    DEFAULT_MODELS = %w[ncep_nbm_conus best_match].freeze

    def self.primary_models = ENV["OPEN_METEO_MODELS"].presence&.split(",")&.map(&:strip) || DEFAULT_MODELS

    attr_reader :api_key

    def initialize(api_key: self.class.api_key, limiter: nil, sleeper: ->(seconds) { sleep(seconds) })
      @api_key, @sleeper = api_key, sleeper
      @limiter = limiter || RateLimiter.new(limits: api_key ? nil : RateLimiter::FREE_LIMITS, sleeper:)
    end

    def mode = api_key ? :customer : :free

    # Hourly values for each location, in order. dates: past_days:/forecast_days: (forecast) or
    # start_date:/end_date:. From the ensemble endpoint, values also has each member's series
    # ("precipitation_member01", ...; the unsuffixed one is the control), and Open-Meteo counts
    # each member as a variable.
    def hourly(locations, endpoint:, model:, variables:, **dates)
      locations.each_slice(BATCH_SIZE).flat_map do |batch|
        params = {
          latitude: batch.map { |lat, _| lat.round(6) }.join(","),
          longitude: batch.map { |_, lng| lng.round(6) }.join(","),
          hourly: variables.join(","), models: model, timezone: "auto", **dates.compact
        }
        days = dates[:start_date] ? (dates[:end_date] - dates[:start_date]).to_i + 1 : dates.values_at(:past_days, :forecast_days).compact.sum
        counted = (endpoint == :ensemble) ? variables.size * ENSEMBLE_MEMBERS : variables.size
        @limiter.acquire!(RateLimiter.weight(locations: batch.size, variables: counted, days:))
        Array.wrap(get(endpoint, params)).map { |json| parse(json, variables) }
      end
    end

    def url(endpoint, params)
      host, path = ENDPOINTS.fetch(endpoint)
      host = "customer-#{host}" if api_key
      URI::HTTPS.build(host:, path:, query: URI.encode_www_form(params.merge(api_key ? {apikey: api_key} : {})))
    end

    private

    NETWORK_ERRORS = [Net::OpenTimeout, Net::ReadTimeout, SocketError, Errno::ECONNREFUSED, Errno::ECONNRESET].freeze

    def get(endpoint, params)
      uri = url(endpoint, params)
      attempts = 0
      begin
        response = Net::HTTP.start(uri.host, uri.port, use_ssl: true, open_timeout: 10, read_timeout: 60) do |http|
          http.request(Net::HTTP::Get.new(uri))
        end
        handle(response)
      rescue TransientError, *NETWORK_ERRORS => e
        error = e.is_a?(TransientError) ? e : TransientError.new("Open-Meteo unreachable: #{e.message}")
        raise error if attempts >= RETRY_DELAYS.size
        @sleeper.call(RETRY_DELAYS[attempts])
        attempts += 1
        retry
      end
    end

    def handle(response)
      body = begin
        JSON.parse(response.body)
      rescue JSON::ParserError
        nil
      end
      case response.code.to_i
      when 200 then body
      when 429, 500..599 then raise TransientError, "Open-Meteo #{response.code}: #{reason(body)}"
      else raise Error, "Open-Meteo #{response.code}: #{reason(body)}"
      end
    end

    def reason(body) = body.is_a?(Hash) ? body["reason"] : "no details"

    def parse(json, variables)
      hourly = json.fetch("hourly")
      Hourly.new(latitude: json["latitude"], longitude: json["longitude"], timezone: json["timezone"],
        elevation: json["elevation"], times: hourly.fetch("time"),
        values: variables.to_h { |variable| [variable, hourly[variable] || []] }.merge(hourly.except("time")))
    end
  end
end
