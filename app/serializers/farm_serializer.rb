class FarmSerializer < ApplicationSerializer
  attributes :id, :name, :notes

  many :pivot_groups, resource: PivotGroupSerializer
  many :pivots, resource: PivotSerializer
end
