defmodule Auto.Text do
  @moduledoc """
  Shared text rendering for the Stream Deck keys and the LCD strip.
  """

  alias Vix.Vips.Operation

  # Matches Image.Text's default so mixed-colour rows sit alongside plain ones.
  @font "Helvetica"

  @doc """
  Render text, stepping the face down until it fits `max_width`.

  Readings are normally short and render at the requested size; this only
  engages when a line would otherwise be clipped, which is exactly when
  losing a digit would be worst. Bottoms out at `min_font_size` rather than
  shrinking without limit.
  """
  def fit(text, opts) do
    color = Keyword.fetch!(opts, :color)
    fit_row([{text, color}], opts)
  end

  @doc """
  Render one line built from `{text, colour}` segments, each in its own colour.

  Goes through Pango markup rather than composing separate images so the
  segments share a baseline: `Image.Text.text!/2` renders a mask and tints it
  a single colour, so it cannot do this, and separately rendered images are
  trimmed to their own glyph bounds and no longer line up.

  Fits to `max_width` the same way `fit/2` does.
  """
  def fit_row(segments, opts) do
    font_size = Keyword.fetch!(opts, :font_size)
    min_font_size = Keyword.get(opts, :min_font_size, 16)
    max_width = Keyword.fetch!(opts, :max_width)

    markup =
      Enum.map_join(segments, fn {text, color} ->
        ~s(<span foreground="#{color}">#{escape(text)}</span>)
      end)

    Enum.reduce_while(font_size..min_font_size//-2, nil, fn font_size, _acc ->
      {:ok, {img, _}} = Operation.text(markup, font: "#{@font} #{font_size}", rgba: true)
      if Image.width(img) <= max_width, do: {:halt, img}, else: {:cont, img}
    end)
  end

  defp escape(text) do
    text
    |> to_string()
    |> String.replace("&", "&amp;")
    |> String.replace("<", "&lt;")
    |> String.replace(">", "&gt;")
  end
end
