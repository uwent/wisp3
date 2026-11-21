# The web app manifest (public/manifest.webmanifest, for Add to Home Screen) with its own type,
# which Rack doesn't know
Rack::Mime::MIME_TYPES[".webmanifest"] = "application/manifest+json"
