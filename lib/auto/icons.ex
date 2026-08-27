defmodule Auto.Icons do
  import BsIcons, only: [svg_icon: 1, color: 2, size: 3, to_png: 1]

  @icon_color "#00ffff"
  @text_color "#00ffff"

  def i(icon, color \\ @icon_color) do
    img =
      icon
      |> svg_icon()
      |> color(color)
      |> size(100, 100)
      |> to_png()
      |> Image.from_binary()
      |> elem(1)

    Image.new!(120, 120)
    |> Image.compose!(img, x: 10, y: 10)
    |> Image.write!(:memory, suffix: ".jpg", quality: 100)
  end

  @font_size 32
  def from_text(text, color \\ @text_color) do
    t = Image.Text.text!(text, font_size: @font_size, text_fill_color: color, x: :center)

    Image.new!(120, 120)
    |> Image.compose!(t, x: :center, y: :center)
    |> Image.write!(:memory, suffix: ".jpg", quality: 100)
  end

  @big_font_size 48
  def big_text(text, color \\ @text_color) do
    t = Image.Text.text!(text, font_size: @big_font_size, text_fill_color: color, x: :center)

    Image.new!(120, 120)
    |> Image.compose!(t, x: :center, y: :center)
    |> Image.write!(:memory, suffix: ".jpg", quality: 100)
  end

  @key_size 120
  @key_padding 4
  @key_min_font_size 16

  # Two rows on one key. Each row is a list of `{text, colour}` segments and is
  # fit to the key width, so a row can take an extra reading and shrink to suit
  # rather than overflowing. Rows are centred in their half of the key so that
  # shrinking one does not unbalance the pair.
  def key_rows([top, bottom]) do
    top = key_row(top, @big_font_size)
    bottom = key_row(bottom, @font_size)

    Image.new!(@key_size, @key_size)
    |> Image.compose!(top, x: :center, y: centre_on(top, 40))
    |> Image.compose!(bottom, x: :center, y: centre_on(bottom, 86))
    |> Image.write!(:memory, suffix: ".jpg", quality: 100)
  end

  defp key_row(segments, font_size) do
    Auto.Text.fit_row(segments,
      font_size: font_size,
      min_font_size: @key_min_font_size,
      max_width: @key_size - 2 * @key_padding
    )
  end

  defp centre_on(image, y), do: max(y - div(Image.height(image), 2), 0)
end
