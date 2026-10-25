class SeasonCopiesController < AuthenticatedController
  def create
    year = params.expect(:year).to_i
    result = SeasonCopy.new(Current.group, year).run
    notice = if result.copied.any?
      "Copied #{helpers.pluralize(result.copied.size, "crop")} from #{year - 1} to #{year}."
    elsif result.failed.empty?
      "Nothing to copy. Every field with a #{year - 1} crop already has a #{year} crop."
    end
    alert = if result.failed.any?
      "Couldn't copy " + result.failed.map do |planting|
        "#{planting.plant.name} on #{planting.field.name} (#{planting.errors.full_messages.to_sentence})"
      end.to_sentence + "."
    end
    redirect_to setup_path(year:), notice:, alert:
  end
end
