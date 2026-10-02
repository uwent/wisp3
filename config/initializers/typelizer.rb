# TypeScript types for serializers (app/frontend/types/serializers) and typed route helpers
# (app/frontend/routes). Regenerated automatically in development; run
# `bin/rails typelizer:generate` after changing serializers or routes, and commit the output.
Typelizer.configure do |config|
  config.verbatim_module_syntax = true # matches @tsconfig/svelte
  config.routes.enabled = true
  config.routes.exclude = [%r{^/rails/}, %r{^/letter_opener}, %r{^/up}]
end
