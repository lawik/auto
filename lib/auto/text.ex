defmodule Auto.Text do
  @moduledoc """
  Shared text rendering for the Stream Deck keys and the LCD strip.
  """

  @doc """
  Render text, stepping the face down until it fits `max_width`.

  Readings are normally short and render at the requested size; this only
  engages when a line would otherwise be clipped, which is exactly when
  losing a digit would be worst. Bottoms out at `min_font_size` rather than
  shrinking without limit.
  """
  def fit(text, opts) do
    font_size = Keyword.fetch!(opts, :font_size)
    min_font_size = Keyword.get(opts, :min_font_size, 16)
    max_width = Keyword.fetch!(opts, :max_width)
    color = Keyword.fetch!(opts, :color)

    Enum.reduce_while(font_size..min_font_size//-2, nil, fn font_size, _acc ->
      t = Image.Text.text!(to_string(text), font_size: font_size, text_fill_color: color)
      if Image.width(t) <= max_width, do: {:halt, t}, else: {:cont, t}
    end)
  end
end
