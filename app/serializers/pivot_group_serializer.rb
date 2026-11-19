class PivotGroupSerializer < ApplicationSerializer
  # use_model_precip: null follows its farm's rainfall setting (Q7)
  attributes :id, :name, :created_by_id, :use_model_precip
end
