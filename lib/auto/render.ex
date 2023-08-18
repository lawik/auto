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
              next_stop: nil
  end

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

  def next(strip, next) do
    %{strip | next: next}
  end

  @font_size 32
  def render_strip(strip) do
    date =
      Image.Text.text!(strip.date,
        font_size: @font_size
      )

    day_time =
      Image.Text.text!("#{strip.day} #{strip.time}",
        font_size: @font_size
      )

    current =
      "Current: #{strip.current}"
      |> Image.Text.text!(font_size: @font_size)

    next =
      "Next: #{strip.next}"
      |> Image.Text.text!(
        font_size: @font_size,
        text_fill_color: "#a9a9a9"
      )

    img =
      Image.new!(800, 100)
      |> Image.compose!(
        [
          {date, [x: 5, y: 10]},
          {day_time, [x: 5, y: 60]},
          {current, [x: 205, y: 10]},
          {next, [x: 205, y: 60]}
        ],
        x: :left,
        y: :top
      )

    Image.write(img, "priv/test.jpg", quality: 100)

    img
    |> Image.write!(:memory, suffix: ".jpg", quality: 100)
  end

  defp day_nice(1), do: "Mon"
  defp day_nice(2), do: "Tue"
  defp day_nice(3), do: "Wed"
  defp day_nice(4), do: "Thu"
  defp day_nice(5), do: "Fri"
  defp day_nice(6), do: "Sat"
  defp day_nice(7), do: "Sun"
end
