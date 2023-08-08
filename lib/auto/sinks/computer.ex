defmodule Auto.Sinks.Computer do
  use GenServer
  require Logger

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, [])
  end

  def init(_opts) do
    Phoenix.PubSub.subscribe(Auto.PubSub, "input")
    {:ok, %{}}
  end

  def handle_info({:plus, message}, state) do
    case message do
      %{event: :button, part: :keys, states: states} ->
        if Enum.at(states, 2) == :down do
          Logger.info("Dotooling playpause")
          Dotool.cmd("key playpause")
          Phoenix.PubSub.broadcast!(Auto.PubSub, "computer", :toggle_play)
        end

        if Enum.at(states, 3) == :down do
          Logger.info("Dotooling micmute")
          Dotool.cmd("key micmute")
          Phoenix.PubSub.broadcast!(Auto.PubSub, "computer", :toggle_mute)
        end

      _ ->
        nil
    end

    {:noreply, state}
  end

  def handle_info({:pedal, message}, state) do
    case message do
      %{event: :button, states: states} ->
        if Enum.at(states, 1) == :down do
          Logger.info("Dotooling micmute")
          Dotool.cmd("key micmute")
          Phoenix.PubSub.broadcast!(Auto.PubSub, "computer", :toggle_mute)
        end

        if Enum.at(states, 1) == :up do
          Logger.info("Dotooling micmute")
          Dotool.cmd("key micmute")
          Phoenix.PubSub.broadcast!(Auto.PubSub, "computer", :toggle_mute)
        end

      _ ->
        nil
    end

    {:noreply, state}
  end

  def handle_info(_, state) do
    {:noreply, state}
  end
end
