class FarmSerializer < ApplicationSerializer
  # use_model_precip: its rainfall setting, which its irrigation groups follow unless they have their own (Q7)
  attributes :id, :name, :notes, :use_model_precip

  many :pivot_groups, resource: PivotGroupSerializer
  many :pivots, resource: PivotSerializer
end
