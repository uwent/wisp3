# Base for every controller that renders Svelte pages, including the Devise controllers
# (config.parent_controller in config/initializers/devise.rb).
class InertiaController < ApplicationController
  inertia_share do
    {
      auth: {
        user: current_user && UserSerializer.new(current_user).to_h,
        group: Current.group && GroupSerializer.new(Current.group).to_h,
        groups: current_user ? GroupSerializer.new(current_user.groups.order(:name)).to_h : []
      }
    }
  end

  private

  # Inertia expects validation errors as {field => [messages]} on a redirect back to the form.
  # Takes a record, its ActiveModel::Errors, or a hash already in that shape.
  def redirect_with_errors(path, record_or_errors)
    errors = record_or_errors.respond_to?(:errors) ? record_or_errors.errors : record_or_errors
    errors = errors.to_hash(true) if errors.is_a?(ActiveModel::Errors)
    redirect_to path, inertia: {errors:}
  end
end
