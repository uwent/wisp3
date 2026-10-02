# Alba serializers for Inertia page props. `bin/rails typelizer:generate` turns each one into a
# TypeScript type in app/frontend/types/serializers.
class ApplicationSerializer
  include Alba::Resource
  include Typelizer::DSL
end
