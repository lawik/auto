defmodule Auto.Sources.Fellowes do
  use GenServer

  @moduledoc """
    This module provides a GenServer that periodically checks data from Fellowes.

    Sample response in priv/fellowes.json

    values? pm2.5 tvoc co2 air_quality temperature humidity pm1 pm10 air_pressure

    The pm*_in readings are the intake side (room air), pm*_out is post-filter.
  """

  require Logger

  @check_interval 30_000

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  def check do
    GenServer.call(__MODULE__, :check)
  end

  def handle_call(:check, _from, state) do
    state = check_data(state)
    {:reply, state.data, state}
  end

  def init(opts) do
    token = Keyword.fetch!(opts, :token)
    url = Keyword.fetch!(opts, :url)
    send(self(), :check_data)
    {:ok, %{token: token, url: url, data: %{}}}
  end

  def handle_info(:check_data, state) do
    state =
      try do
        check_data(state)
      rescue
        e ->
          Logger.error("Error fetching data from Fellowes: #{inspect(e)}")
          state
      end

    Process.send_after(self(), :check_data, @check_interval)
    {:noreply, state}
  end

  defp check_data(state) do
    %{token: token, url: url} = state

    response =
      Req.new(
        url: url,
        auth: {:bearer, token},
        retry: false,
        headers: %{
          "user-agent" => ["curl/7.81.0"],
          "accept" => ["*/*"],
          "accept-encoding" => ["gzip"]
        }
      )
      |> Req.get()

    case response do
      {:ok, %{status: 200, body: body}} ->
        props = get_in(body, ["shadow", "reported", "properties"]) || %{}

        data = %{
          co2: props["co2"],
          humidity: props["humidity"],
          pressure: props["pressure"],
          temperature: props["temperature"],
          voc: props["voc"],
          # Particulate matter, µg/m³, as measured on the intake (ie. the room)
          pm1_0: props["pm1_0_in"],
          pm2_5: props["pm2_5_in"],
          pm10: props["pm10_in"]
        }

        Phoenix.PubSub.broadcast(Auto.PubSub, "airquality", {:air_quality_data, data})
        %{state | data: data}

      err ->
        Logger.error("Error fetching data from Fellowes: #{inspect(err)}")
        state
    end
  end
end
