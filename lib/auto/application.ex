defmodule Auto.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    calendars =
      [
        "CALENDAR_URL_1",
        "CALENDAR_URL_2",
        "CALENDAR_URL_3"
      ]
      |> Enum.map(&System.fetch_env!/1)

    children = [
      # Start the Telemetry supervisor
      AutoWeb.Telemetry,
      # Start the Ecto repository
      Auto.Repo,
      # Start the PubSub system
      {Phoenix.PubSub, name: Auto.PubSub},
      # Start Finch
      {Finch, name: Auto.Finch},
      Dotool,
      Auto.Sinks.Computer,
      Auto.Devices.Keylights,
      Auto.Devices.Streamdecks,
      Auto.Devices.Cameras,
      {Auto.Sources.Calendars, calendars: calendars},
      Auto.Sources.Pulseaudio,
      # Start the Endpoint (http/https)
      AutoWeb.Endpoint
      # Start a worker by calling: Auto.Worker.start_link(arg)
      # {Auto.Worker, arg}
    ]

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: Auto.Supervisor]
    Supervisor.start_link(children, opts)
  end

  # Tell Phoenix to update the endpoint configuration
  # whenever the application is updated.
  @impl true
  def config_change(changed, _new, removed) do
    AutoWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end
