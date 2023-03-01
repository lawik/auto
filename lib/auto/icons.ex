defmodule Auto.Icons do
  import BsIcons, only: [svg_icon: 1, color: 2, size: 3, to_png: 1]

  def i(icon) do
    img =
      icon
      |> svg_icon()
      |> color("white")
      |> size(100, 100)
      |> to_png()
      |> Image.from_binary()
      |> elem(1)

    Image.new!(120, 120)
    |> Image.compose!(img, x: 10, y: 10)
    |> Image.write!(:memory, suffix: ".jpg", quality: 100)
  end
end
