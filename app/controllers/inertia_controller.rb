# Base for every controller that renders Svelte pages, including the Devise controllers
# (config.parent_controller in config/initializers/devise.rb).
class InertiaController < ApplicationController
  inertia_share do
    {
      # The date the balance runs to, so the browser's "today" agrees with it; the example
      # farm's day there (Current.today)
      today: Current.today.iso8601,
      # Viewing the example farm (ExampleMode): its day, for the bar across the top and read-only pages
      example: example_group && {as_of: example_group.example_as_of.iso8601},
      auth: {
        user: current_user && UserSerializer.new(current_user).to_h,
        group: Current.group && GroupSerializer.new(Current.group).to_h,
        # Whether the user owns the current group (Q8), so pages can hide what only owners can do
        owner: Current.owner?,
        groups: current_user ? GroupSerializer.new(current_user.groups.order(:name)).to_h : [],
        # The admin signed in as this user for support, for the bar across the top of every page
        impersonator: impersonator && {name: impersonator.display_name, email: impersonator.email}
      }
    }
  end

  private

  # An ISO 8601 date param (2026-07-20) as a Date, or nil when it's missing or malformed
  def parse_date(value)
    Date.iso8601(value) if value.is_a?(String) && value.present?
  rescue Date::Error
    nil
  end

  # A CSV export (CsvExport) as a download
  def send_csv(csv, filename)
    send_data csv, filename:, type: "text/csv; charset=utf-8"
  end

  # A list sent as indexed names (rows[0][name]): an array, or a hash keyed "0", "1", … in order
  def indexed_list(value)
    return [] if value.blank?
    value.is_a?(Array) ? value : value.to_h.sort_by { |key, _| key.to_i }.map(&:last)
  end

  # Inertia expects validation errors as {field => [messages]} on a redirect back to the form.
  # Takes a record, its ActiveModel::Errors, or a hash already in that shape.
  def redirect_with_errors(path, record_or_errors)
    errors = record_or_errors.respond_to?(:errors) ? record_or_errors.errors : record_or_errors
    errors = errors.to_hash(true) if errors.is_a?(ActiveModel::Errors)
    redirect_to path, inertia: {errors:}
  end
end
