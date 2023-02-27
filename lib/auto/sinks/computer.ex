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
    end

    {:noreply, state}
  end
end
