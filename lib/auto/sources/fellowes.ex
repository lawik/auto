defmodule Auto.Sources.Fellowes do
  use GenServer

  @moduledoc """
    This module provides a GenServer that periodically checks data from Fellowes.

    Sample response in priv/fellowes.json

    values? pm2.5 tvoc co2 air_quality temperature humidity pm1 pm10 air_pressure
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

  def handle_call(request, from, state) do
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
        data = %{
          co2: get_in(body, ["shadow", "reported", "properties", "co2"]),
          humidity: get_in(body, ["shadow", "reported", "properties", "humidity"]),
          pressure: get_in(body, ["shadow", "reported", "properties", "pressure"]),
          temperature: get_in(body, ["shadow", "reported", "properties", "temperature"]),
          voc: get_in(body, ["shadow", "reported", "properties", "voc"])
        }

        Phoenix.PubSub.broadcast(Auto.PubSub, "airquality", {:air_quality_data, data})
        %{state | data: data}

      err ->
        Logger.error("Error fetching data from Fellowes: #{inspect(err)}")
        state
    end
  end
end
