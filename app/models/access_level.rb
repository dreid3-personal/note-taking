# A level of access to a note or folder: none < view < edit. Edit includes view.
#
#   AccessLevel[:view] < AccessLevel[:edit]          # => true
#   AccessLevel.highest([ "view", :edit ]).edit?     # => true
#   AccessLevel.highest([])                          # => AccessLevel::NONE
class AccessLevel
  include Comparable

  NAMES = %w[none view edit].freeze

  attr_reader :name

  def initialize(name)
    @name = name
    freeze
  end

  NONE, VIEW, EDIT = NAMES.map { |name| new(name) }
  private_class_method :new

  # Looks up a level by name ("view", :view) and passes an AccessLevel through unchanged.
  def self.[](level)
    case level
    when AccessLevel then level
    when nil then NONE
    else
      { "none" => NONE, "view" => VIEW, "edit" => EDIT }.fetch(level.to_s) do
        raise ArgumentError, "unknown access level: #{level.inspect}"
      end
    end
  end

  # The highest of the given levels, or none for an empty list.
  def self.highest(levels)
    levels.map { |level| self[level] }.max || NONE
  end

  # Compares with another level or a level name; anything else, including an unknown name, isn't
  # comparable (nil), so == is false rather than raising.
  def <=>(other)
    other_rank =
      case other
      when AccessLevel then other.rank
      when String, Symbol then NAMES.index(other.to_s)
      end
    rank <=> other_rank if other_rank
  end

  def none?
    self == NONE
  end

  def view?
    self >= VIEW
  end

  def edit?
    self == EDIT
  end

  def to_s
    name
  end

  def to_sym
    name.to_sym
  end

  def inspect
    "#<AccessLevel #{name}>"
  end

  protected
    def rank
      NAMES.index(name)
    end
end
