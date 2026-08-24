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

  def double_text({main_text, main_color}, {sub_text, sub_color}) do
    t =
      Image.Text.text!(to_string(main_text),
        font_size: @big_font_size,
        text_fill_color: main_color
      )

    s = Image.Text.text!(to_string(sub_text), font_size: @font_size, text_fill_color: sub_color)

    Image.new!(120, 120)
    |> Image.compose!(t, x: :center, y: 24)
    |> Image.compose!(s, x: :center, y: -24)
    |> Image.write!(:memory, suffix: ".jpg", quality: 100)
  end

  # Three stacked lines on one key. The top line is the headline value so it
  # gets a slightly larger face than the two below it.
  @key_size 120
  @key_padding 4
  @triple_main_font_size 34
  @triple_font_size 28
  @triple_min_font_size 16
  @triple_rows [{@triple_main_font_size, 14}, {@triple_font_size, 52}, {@triple_font_size, 88}]

  def triple_text(lines) when length(lines) == 3 do
    @triple_rows
    |> Enum.zip(lines)
    |> Enum.reduce(Image.new!(@key_size, @key_size), fn {{font_size, y}, {text, color}}, canvas ->
      Image.compose!(canvas, fit_text(to_string(text), font_size, color), x: :center, y: y)
    end)
    |> Image.write!(:memory, suffix: ".jpg", quality: 100)
  end

  # Step the face down until the line fits the key width. Readings are normally
  # one or two digits and render at full size; this only engages when a line
  # would otherwise be clipped, which is exactly when losing a digit is worst.
  defp fit_text(text, font_size, color) do
    max_width = @key_size - 2 * @key_padding

    Enum.reduce_while(font_size..@triple_min_font_size//-2, nil, fn font_size, _acc ->
      t = Image.Text.text!(text, font_size: font_size, text_fill_color: color)
      if Image.width(t) <= max_width, do: {:halt, t}, else: {:cont, t}
    end)
  end
end
