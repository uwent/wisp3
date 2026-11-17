# The public example farm (PLAN.md G.8, ExampleMode): /example starts viewing it, read-only, from its
# dashboard; DELETE /example (the bar's Leave) goes back to the landing page, or the user's own
# operation.
class ExamplesController < InertiaController
  def show
    return redirect_to root_path, alert: "There's no example farm to show yet." unless Group.example

    session[ExampleMode::SESSION_KEY] = true
    redirect_to root_path
  end

  def destroy
    leave_example
    redirect_to root_path, status: :see_other
  end
end
