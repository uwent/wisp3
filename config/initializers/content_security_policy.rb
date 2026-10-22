# Content Security Policy (PLAN.md Phase 8 C, the code audit). Scripts come only from WISP itself,
# so injected markup can't run code; the one inline script (the theme, in the layout) carries this
# request's nonce. The map's tiles and data and the soil survey come from many public services,
# loaded by the browser (lib/map/overlays.ts, basemaps.ts, lib/soils.ts), so images and connections
# allow any https source rather than a list that a new layer would quietly break. Svelte, MapLibre
# and ECharts set inline styles, hence 'unsafe-inline' for styles only. The smoke tests fail on any
# console error, a violation included.
Rails.application.configure do
  config.content_security_policy do |policy|
    policy.default_src :self
    policy.script_src :self
    policy.style_src :self, :unsafe_inline
    policy.img_src :self, :data, :blob, :https
    policy.font_src :self, :data
    policy.connect_src :self, :https
    policy.worker_src :self, :blob
    policy.object_src :none
    policy.base_uri :self
    policy.form_action :self
    policy.frame_ancestors :none

    # The Vite dev server: its client, hot reloading over a websocket, and the modules, fonts and
    # images it serves (built assets come from WISP itself)
    if Rails.env.development?
      vite = "http://#{ViteRuby.config.host_with_port}"
      policy.script_src :self, :unsafe_eval, vite
      policy.style_src :self, :unsafe_inline, vite
      policy.font_src :self, :data, vite
      policy.img_src :self, :data, :blob, :https, vite
      policy.connect_src :self, :https, vite, vite.sub("http:", "ws:")
      policy.worker_src :self, :blob, vite
    end
  end

  config.content_security_policy_nonce_generator = ->(_request) { SecureRandom.base64(16) }
  config.content_security_policy_nonce_directives = %w[script-src]
end
