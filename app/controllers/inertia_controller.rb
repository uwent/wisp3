# Base for every controller that renders Svelte pages, including the Devise controllers
# (config.parent_controller in config/initializers/devise.rb).
class InertiaController < ApplicationController
  inertia_share do
    {
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
