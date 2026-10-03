class SeasonCopiesController < AuthenticatedController
  def create
    year = params.expect(:year).to_i
    copied = SeasonCopy.new(Current.group, year).run
    notice = if copied.any?
      "Copied #{helpers.pluralize(copied.size, "planting")} from #{year - 1}"
    else
      "Nothing to copy: every field with a #{year - 1} crop already has one in #{year}"
    end
    redirect_to setup_path(year:), notice:
  end
end
