class ApplicationRecord < ActiveRecord::Base
  primary_abstract_class

  # Control characters other than tab and newline: pasted from elsewhere, never meant, and NUL is
  # one Postgres refuses to store
  CONTROL_CHARACTERS = /[^\P{Cc}\t\n]/

  # A one-line name: no control characters, no space at either end, and runs of spaces (tabs and
  # newlines included) collapsed to one; NULL when nothing's left
  def self.normalizes_name(*names)
    normalizes(*names, with: ->(name) { name.gsub(CONTROL_CHARACTERS, "").squish.presence })
  end

  # Free text such as notes: line breaks kept (as \n), no control characters, no space at either
  # end, and NULL when nothing's left
  def self.normalizes_text(*names)
    normalizes(*names, with: ->(text) { text.gsub(/\r\n?/, "\n").gsub(CONTROL_CHARACTERS, "").strip.presence })
  end
end
