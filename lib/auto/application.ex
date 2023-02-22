defmodule Auto.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      # Start the Telemetry supervisor
      AutoWeb.Telemetry,
      # Start the Ecto repository
      Auto.Repo,
      # Start the PubSub system
      {Phoenix.PubSub, name: Auto.PubSub},
      Auto.InputListener,
      Auto.OutputListener,
      # Start Finch
      {Finch, name: Auto.Finch},
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