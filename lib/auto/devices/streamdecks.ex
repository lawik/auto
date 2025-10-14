defmodule Auto.Devices.Streamdecks do
  use GenServer

  alias Auto.Icons

  @icon_on "#00ffff"
  @icon_off "#ffff00"

  @check_interval 10_000
  @poll_interval 100
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

    send(self(), :check_devices)
    send(self(), :poll)
    strip = Auto.Render.new_strip()

    {:ok,
     %{
       pedal: nil,
       plus: nil,
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

    new_pedal =
      if is_nil(state.pedal) and pedal do
        Streamdex.start(pedal)
      else
        state.pedal
      end

    new_plus =
      if is_nil(state.plus) and plus do
        plus = Streamdex.start(plus)

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

        plus
      else
        state.plus
      end

    Process.send_after(self(), :check_devices, @check_interval)
    {:noreply, %{state | plus: new_plus, pedal: new_pedal}}
  end

  def handle_info(:poll, state) do
    if state.plus do
      state.plus
      |> state.plus.module.poll()
      |> broadcast(:plus)
    end

    if state.pedal do
      state.pedal
      |> state.pedal.module.poll()
      |> broadcast(:pedal)
    end

    Process.send_after(self(), :poll, @poll_interval)
    {:noreply, %{state | strip: Auto.Render.refresh_now(state.strip)}}
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
    input = Icons.from_text(input_percent)
    output = Icons.from_text(output_percent)
    state.plus.module.set_key_image(state.plus, 7, input)
    state.plus.module.set_key_image(state.plus, 6, output)
    {:noreply, %{state | input_volume: input_percent, output_volume: output_percent}}
  end

  def handle_info(_, state) do
    {:noreply, state}
  end

  defp broadcast(nil, _), do: nil

  defp broadcast(result, device_type) do
    Phoenix.PubSub.broadcast(Auto.PubSub, "input", {device_type, result})
  end
end
