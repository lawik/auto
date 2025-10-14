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
    t = Image.Text.text!(main_text, font_size: @big_font_size, text_fill_color: main_color)
    s = Image.Text.text!(sub_text, font_size: @font_size, text_fill_color: sub_color)

    Image.new!(120, 120)
    |> Image.compose!(t, x: :center, y: 24)
    |> Image.compose!(s, x: :center, y: -24)
    |> Image.write!(:memory, suffix: ".jpg", quality: 100)
  end
end
