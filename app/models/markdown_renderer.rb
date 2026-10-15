# Turns a Markdown string into sanitized HTML, with GitHub-flavored extensions
# (tables, task lists, strikethrough and autolinks).
#
# Note bodies are user input, so the HTML is cleaned twice: Commonmarker drops
# raw HTML and unsafe links, and the Rails sanitizer then keeps only the tags and
# attributes below.
class MarkdownRenderer
  OPTIONS = {
    extension: { table: true, tasklist: true, strikethrough: true, autolink: true, header_ids: nil },
    render: { unsafe: false, github_pre_lang: false }
  }.freeze

  ALLOWED_TAGS = %w[
    h1 h2 h3 h4 h5 h6 p br hr blockquote
    ul ol li input
    strong em del code pre a img
    table thead tbody tr th td
  ].freeze

  ALLOWED_ATTRIBUTES = %w[href src alt title class type checked disabled align start].freeze

  def self.render(markdown)
    new.render(markdown)
  end

  def render(markdown)
    html = Commonmarker.to_html(markdown.to_s.encode(Encoding::UTF_8), options: OPTIONS, plugins: { syntax_highlighter: nil })
    sanitizer.sanitize(html, tags: ALLOWED_TAGS, attributes: ALLOWED_ATTRIBUTES).html_safe
  end

  private
    def sanitizer
      Rails::HTML::Sanitizer.safe_list_sanitizer.new
    end
end
