defmodule Auto.Render do
  defmodule Strip do
    defstruct date: nil,
              day: nil,
              time: nil,
              current: nil,
              current_start: nil,
              current_stop: nil,
              next: nil,
              next_start: nil,
              next_stop: nil,
              pm: nil,
              voc: nil
  end

  @text_color "#00ffff"
  @text_highlight_color "#ff00ff"
  @text_highlight_secondary_color "#a900a9"
  @text_secondary_color "#00a9a9"

  alias Auto.Render.Strip

  def new_strip do
    %Strip{}
    |> refresh_now()
  end

  def refresh_now(strip) do
    dt = DateTime.now!("Europe/Stockholm")
    now_time = dt |> DateTime.to_iso8601() |> String.slice(11, 5)
    date = DateTime.to_date(dt)
    today_date = date |> Date.to_iso8601()
    day = date |> Date.day_of_week() |> day_nice()

    %{strip | date: today_date, time: now_time, day: day}
  end

  def current(strip, current) do
    %{strip | current: current}
  end

  @doc """
  Set the air quality column. Each line is a list of `{text, colour}` segments
  so every reading carries its own colour; the caller owns the thresholds, this
  only lays them out.
  """
  def air(strip, %{pm: pm, voc: voc}) do
    %{strip | pm: pm, voc: voc}
  end

  def next(strip, next) do
    next =
      case String.trim(next) do
        "" -> "-"
        other -> other
      end

    %{strip | next: next}
  end

  @font_size 32
  # Events run a little smaller than the date/air columns: they are the longest
  # strings on the strip and the only ones that can overrun their space.
  @event_font_size 28
  @strip_width 800

  # The air column sits where "Current:"/"Next:" used to print, so dropping
  # those labels costs the events nothing: they start further right but no
  # longer carry a prefix.
  @col_left 5
  @col_air 205
  @col_air_width 120
  @col_events 335

  def render_strip(strip) do
    date =
      Image.Text.text!(strip.date,
        font_size: @font_size,
        text_fill_color: @text_highlight_color
      )

    day_time =
      Image.Text.text!("#{strip.day} #{strip.time}",
        font_size: @font_size,
        text_fill_color: @text_highlight_secondary_color
      )

    current = event_text(strip.current, @text_color)
    next = event_text(strip.next, @text_secondary_color)

    pm = air_text(strip.pm)
    voc = air_text(strip.voc)

    img =
      Image.new!(@strip_width, 100)
      |> Image.compose!(
        [
          {date, [x: @col_left, y: 10]},
          {day_time, [x: @col_left, y: 60]},
          {pm, [x: @col_air, y: 10]},
          {voc, [x: @col_air, y: 60]},
          {current, [x: @col_events, y: 10]},
          {next, [x: @col_events, y: 60]}
        ],
        x: :left,
        y: :top
      )

    img
    |> Image.write!(:memory, suffix: ".jpg", quality: 100)
  end

  defp event_text(nil, _color), do: Image.new!(1, 1)

  defp event_text(text, color) do
    if String.trim(text) == "" do
      Image.new!(1, 1)
    else
      Image.Text.text!(text, font_size: @event_font_size, text_fill_color: color)
    end
  end

  defp air_text(nil), do: Image.new!(1, 1)

  defp air_text(segments) do
    Auto.Text.fit_row(segments,
      font_size: @font_size,
      min_font_size: 18,
      max_width: @col_air_width
    )
  end

  defp day_nice(1), do: "Mon"
  defp day_nice(2), do: "Tue"
  defp day_nice(3), do: "Wed"
  defp day_nice(4), do: "Thu"
  defp day_nice(5), do: "Fri"
  defp day_nice(6), do: "Sat"
  defp day_nice(7), do: "Sun"
end
