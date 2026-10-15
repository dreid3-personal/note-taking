require "test_helper"

class MarkdownRendererTest < ActiveSupport::TestCase
  test "renders headings" do
    html = render("# Title\n\n### Smaller")

    assert_includes html, "<h1>Title</h1>"
    assert_includes html, "<h3>Smaller</h3>"
  end

  test "renders bulleted and numbered lists" do
    html = render("- one\n- two\n\n1. first\n2. second")

    assert_match %r{<ul>\s*<li>one</li>\s*<li>two</li>\s*</ul>}, html
    assert_match %r{<ol>\s*<li>first</li>\s*<li>second</li>\s*</ol>}, html
  end

  test "renders task lists as disabled checkboxes" do
    html = render("- [ ] todo\n- [x] done")

    assert_includes html, '<input type="checkbox" disabled> todo'
    assert_includes html, '<input type="checkbox" checked disabled> done'
  end

  test "renders tables" do
    html = render("| Name | Age |\n| --- | ---: |\n| Ada | 36 |")

    assert_includes html, "<table>"
    assert_includes html, "<th>Name</th>"
    assert_includes html, '<td align="right">36</td>'
  end

  test "renders code blocks and inline code" do
    html = render("```ruby\nputs \"<b>hi</b>\"\n```\n\nUse `x < y`.")

    assert_includes html, %(<pre><code class="language-ruby">puts "&lt;b&gt;hi&lt;/b&gt;"\n</code></pre>)
    assert_includes html, "<code>x &lt; y</code>"
  end

  test "renders strikethrough and autolinks" do
    html = render("~~gone~~ https://example.com")

    assert_includes html, "<del>gone</del>"
    assert_includes html, '<a href="https://example.com">https://example.com</a>'
  end

  test "removes script tags" do
    html = render("Hi\n\n<script>alert(1)</script>\n\ninline <script>alert(2)</script>")

    assert_includes html, "<p>Hi</p>"
    assert_no_match(/<script/i, html)
  end

  test "removes on event attributes" do
    html = render(<<~MARKDOWN)
      <a href="#" onclick="alert(1)">x</a>

      <img src="x.png" onerror="alert(2)">

      ![pic](x.png "t\\" onerror=\\"alert(3)")
    MARKDOWN

    attributes = Nokogiri::HTML5.fragment(html).css("*").flat_map { |node| node.attribute_nodes.map(&:name) }
    assert_includes attributes, "src"
    assert_empty attributes.grep(/\Aon/i)
  end

  test "removes javascript links" do
    html = render("[click](javascript:alert(1))\n\n<a href=\"javascript:alert(2)\">raw</a>\n\n[enc](JaVaScRiPt&#58;alert(3))")

    assert_no_match(/javascript/i, html)
  end

  test "returns an html_safe string and handles nil" do
    assert_predicate render("text"), :html_safe?
    assert_equal "", render(nil)
  end

  private
    def render(markdown)
      MarkdownRenderer.render(markdown)
    end
end
