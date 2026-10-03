class FarmSerializer < ApplicationSerializer
  attributes :id, :name, :notes

  many :pivots, resource: PivotSerializer
end
