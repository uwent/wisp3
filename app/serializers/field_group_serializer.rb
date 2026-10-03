class FieldGroupSerializer < ApplicationSerializer
  attributes :id, :name

  attribute :field_ids do |group|
    group.field_ids
  end
  typelize field_ids: "number[]"
end
