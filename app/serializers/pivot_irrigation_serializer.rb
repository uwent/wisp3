# field_ids null = every field under the pivot. applied_inches is inches as entered, or converted
# from the percent timer or run hours (null if it can't be). circles null = one.
class PivotIrrigationSerializer < ApplicationSerializer
  attributes :id, :pivot_id, :date, :inches, :run_hours, :percent_timer, :circles, :field_ids, :notes

  attribute :applied_inches, &:applied_inches

  typelize field_ids: "number[] | null", applied_inches: "number | null"
end
