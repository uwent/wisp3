# Adapts Devise's responder to Inertia: when Devise would re-render a form with errors, redirect
# back to the form with the errors instead; when it redirects, use 303 so Inertia follows it as a GET.
module InertiaDeviseResponses
  extend ActiveSupport::Concern

  private

  def respond_with(resource, *args, location: nil, **options)
    if resource.respond_to?(:errors) && resource.errors.any?
      redirect_with_errors form_path_for_errors, resource
    elsif location
      redirect_to location, status: :see_other
    else
      super
    end
  end

  # Where to send the user back to when a submission fails; each controller defines this
  def form_path_for_errors
    raise NotImplementedError
  end
end
