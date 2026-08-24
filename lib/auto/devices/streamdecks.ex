defmodule Auto.Devices.Streamdecks do
  use GenServer

  alias Auto.Icons
  require Logger

  @icon_on "#00ffff"
  @icon_off "#ffff00"

  @check_interval 10_000
  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, opts)
  end

  @spec init(any) :: {:ok, %{pedal: nil, plus: nil}}
  def init(_opts) do
    # TODO: Subscribe to events about keylight changes to push those to display
    Phoenix.PubSub.subscribe(Auto.PubSub, "calendar")
    Phoenix.PubSub.subscribe(Auto.PubSub, "computer")
    Phoenix.PubSub.subscribe(Auto.PubSub, "volumes")
    Phoenix.PubSub.subscribe(Auto.PubSub, "cameras")
    Phoenix.PubSub.subscribe(Auto.PubSub, "airquality")

    send(self(), :check_devices)
    strip = Auto.Render.new_strip()

    {:ok,
     %{
       pedal: nil,
       plus: nil,
       plus_reader: nil,
       pedal_reader: nil,
       show_play?: true,
       unmuted?: true,
       strip: strip,
       input_volume: "0%",
       output_volume: "0%"
     }}
  end

  # Detect new devices, ensure started
  def handle_info(:check_devices, state) do
    devices = Streamdex.devices()

    pedal =
      Enum.find(devices, fn d ->
        d.config.name == "Stream Deck Pedal"
      end)

    plus =
      Enum.find(devices, fn d ->
        d.config.name == "Stream Deck +"
      end)

    me = self()

    {new_pedal, pedal_reader} =
      if is_nil(state.pedal) and pedal do
        started = Streamdex.start(pedal)
        reader = spawn_link(fn -> read_loop(started, :pedal, me) end)
        Logger.info("Started blocking reader for pedal")
        {started, reader}
      else
        {state.pedal, state.pedal_reader}
      end

    {new_plus, plus_reader} =
      if is_nil(state.plus) and plus do
        plus = Streamdex.start(plus)
        plus_reader = spawn_link(fn -> read_loop(plus, :plus, me) end)
        Logger.info("Started blocking reader for plus")

        on = Icons.i("lightbulb", @icon_on)
        off = Icons.i("lightbulb-off", @icon_off)
        auto_on = Icons.i("lightbulb-fill", @icon_on)
        play = Icons.i("play-circle", @icon_on)
        unmuted = Icons.i("mic", @icon_on)

        plus.module.set_key_image(plus, 0, on)
        plus.module.set_key_image(plus, 1, off)
        plus.module.set_key_image(plus, 2, play)
        plus.module.set_key_image(plus, 3, unmuted)
        plus.module.set_key_image(plus, 4, auto_on)

        img =
          state.strip
          |> Auto.Render.render_strip()

        plus.module.set_lcd_image(plus, 0, 0, 800, 100, img)

        {plus, plus_reader}
      else
        {state.plus, state.plus_reader}
      end

    Process.send_after(self(), :check_devices, @check_interval)

    {:noreply,
     %{
       state
       | plus: new_plus,
         pedal: new_pedal,
         plus_reader: plus_reader,
         pedal_reader: pedal_reader
     }}
  end

  def handle_info({:hid_report, device_type, result}, state) do
    broadcast(result, device_type)
    {:noreply, state}
  end

  def handle_info({:current_events, events}, state) do
    summaries =
      events
      |> Enum.map(fn e ->
        start =
          e.dtstart
          |> DateTime.shift_zone!("Europe/Stockholm")
          |> DateTime.to_iso8601()
          |> String.slice(11, 5)

        stop =
          e.dtend
          |> DateTime.shift_zone!("Europe/Stockholm")
          |> DateTime.to_iso8601()
          |> String.slice(11, 5)

        "#{start}-#{stop} #{e.summary}"
      end)
      |> Enum.join(", ")

    #    img =
    #      "current: #{summaries}"
    #      |> Image.Text.simple_text!(width: 780, height: 40, autofit: true, align: :left, x: :left)
    #      |> Image.write!(:memory, suffix: ".jpg", quality: 100)

    strip = Auto.Render.current(state.strip, summaries)
    img = Auto.Render.render_strip(strip)

    # state.plus.module.set_lcd_image(state.plus, 10, 5, 780, 40, img)
    state.plus.module.set_lcd_image(state.plus, 0, 0, 800, 100, img)

    {:noreply, %{state | strip: strip}}
  end

  def handle_info({:upcoming_events, events}, state) do
    summaries =
      events
      |> Enum.take(2)
      |> Enum.map(fn e ->
        start =
          e.dtstart
          |> DateTime.shift_zone!("Europe/Stockholm")
          |> DateTime.to_iso8601()
          |> String.slice(11, 5)

        stop =
          e.dtend
          |> DateTime.shift_zone!("Europe/Stockholm")
          |> DateTime.to_iso8601()
          |> String.slice(11, 5)

        "#{start} #{e.summary}"
      end)
      |> Enum.join(", ")

    # img =
    #  "next: #{summaries}"
    #  |> Image.Text.simple_text!(width: 780, height: 40, autofit: true, align: :left, x: :left)
    #  |> Image.write!(:memory, suffix: ".jpg", quality: 100)
    strip = Auto.Render.next(state.strip, summaries)
    img = Auto.Render.render_strip(strip)

    # state.plus.module.set_lcd_image(state.plus, 10, 55, 780, 40, img)
    state.plus.module.set_lcd_image(state.plus, 0, 0, 800, 100, img)

    {:noreply, %{state | strip: strip}}
  end

  def handle_info(:toggle_play, state) do
    if state.plus do
      if state.show_play? do
        pause = Icons.i("pause-circle", @icon_on)
        state.plus.module.set_key_image(state.plus, 2, pause)
      else
        play = Icons.i("play-circle", @icon_off)
        state.plus.module.set_key_image(state.plus, 2, play)
      end
    end

    {:noreply, %{state | show_play?: not state.show_play?}}
  end

  def handle_info({:control_lights?, on?}, state) do
    if state.plus do
      icon =
        if on? do
          Icons.i("lightbulb-fill", @icon_on)
        else
          Icons.i("lightbulb-off-fill", @icon_off)
        end

      state.plus.module.set_key_image(state.plus, 4, icon)
    end

    {:noreply, state}
  end

  def handle_info(:toggle_mute, state) do
    if state.plus do
      if state.unmuted? do
        mute = Icons.i("mic-mute", @icon_off)
        state.plus.module.set_key_image(state.plus, 3, mute)
      else
        mic = Icons.i("mic", @icon_on)
        state.plus.module.set_key_image(state.plus, 3, mic)
      end
    end

    {:noreply, %{state | unmuted?: not state.unmuted?}}
  end

  def handle_info({:volumes, %{source: input_percent, sink: output_percent}}, state) do
    input = Icons.big_text(input_percent)
    output = Icons.big_text(output_percent)
    state.plus.module.set_key_image(state.plus, 7, input)
    state.plus.module.set_key_image(state.plus, 6, output)
    {:noreply, %{state | input_volume: input_percent, output_volume: output_percent}}
  end

  def handle_info({:air_quality_data, _data}, %{plus: nil} = state) do
    {:noreply, state}
  end

  def handle_info({:air_quality_data, data}, state) do
    color = air_quality_color(data)

    output =
      Icons.triple_text([
        {"#{value(data.temperature)}°", color},
        {value(data.co2), color},
        {pm_line(data), color}
      ])

    state.plus.module.set_key_image(state.plus, 5, output)
    {:noreply, state}
  end

  def handle_info(_, state) do
    {:noreply, state}
  end

  # PM1.0 | PM2.5 | PM10, all in µg/m³ so the unit is left off the key.
  defp pm_line(data) do
    Enum.map_join([data.pm1_0, data.pm2_5, data.pm10], " | ", &value/1)
  end

  defp value(nil), do: "-"
  defp value(v), do: v

  # The whole key takes the colour of its worst reading, so a glance answers
  # "is the air in here OK" without having to read which number moved.
  # Temperature is deliberately not in here — it has no bad level defined.
  defp air_quality_color(data) do
    [
      level(data.co2, 600, 800, 900),
      level(data.pm1_0, 9, 35, 55),
      level(data.pm2_5, 9, 35, 55),
      level(data.pm10, 54, 154, 254)
    ]
    |> Enum.reject(&is_nil/1)
    |> case do
      # Every reading missing: grey, rather than a cyan all-clear we can't back up.
      [] -> "#888888"
      levels -> levels |> Enum.max() |> level_color()
    end
  end

  defp level(nil, _good, _ok, _poor), do: nil

  defp level(v, good, ok, poor) do
    cond do
      v < good -> 0
      v < ok -> 1
      v < poor -> 2
      true -> 3
    end
  end

  # Same palette as the rest of the deck: cyan is fine, green is the alarm.
  defp level_color(0), do: "#00ffff"
  defp level_color(1), do: "#ff00ff"
  defp level_color(2), do: "#ffff00"
  defp level_color(3), do: "#00ff00"

  defp read_loop(device, device_type, parent) do
    case device.module.poll(device) do
      nil ->
        read_loop(device, device_type, parent)

      result ->
        send(parent, {:hid_report, device_type, result})
        read_loop(device, device_type, parent)
    end
  end

  defp broadcast(nil, _), do: nil

  defp broadcast(result, device_type) do
    Phoenix.PubSub.broadcast(Auto.PubSub, "input", {device_type, result})
  end
end
