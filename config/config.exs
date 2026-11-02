# This file is responsible for configuring your application
# and its dependencies with the aid of the Config module.
#
# This configuration file is loaded before any dependency and
# is restricted to this project.

# General application configuration
import Config

config :auto,
  ecto_repos: [Auto.Repo]

# Configures the endpoint
config :auto, AutoWeb.Endpoint,
  url: [host: "localhost"],
  render_errors: [
    formats: [html: AutoWeb.ErrorHTML, json: AutoWeb.ErrorJSON],
    layout: false
  ],
  pubsub_server: Auto.PubSub,
  live_view: [signing_salt: "N0Dz7BM7"]

# Configures the mailer
#
# By default it uses the "Local" adapter which stores the emails
# locally. You can see the emails in your browser, at "/dev/mailbox".
#
# For production it's recommended to configure a different adapter
# at the `config/runtime.exs`.
config :auto, Auto.Mailer, adapter: Swoosh.Adapters.Local

# Configure esbuild (the version is required)
config :esbuild,
  version: "0.14.41",
  default: [
    args:
      ~w(js/app.js --bundle --target=es2017 --outdir=../priv/static/assets --external:/fonts/* --external:/images/*),
    cd: Path.expand("../assets", __DIR__),
    env: %{"NODE_PATH" => Path.expand("../deps", __DIR__)}
  ]

# Configure tailwind (the version is required)
config :tailwind,
  version: "3.1.8",
  default: [
    args: ~w(
      --config=tailwind.config.js
      --input=css/app.css
      --output=../priv/static/assets/app.css
    ),
    cd: Path.expand("../assets", __DIR__)
  ]

# Configures Elixir's Logger
config :logger, :console,
  format: "$time $metadata[$level] $message\n",
  metadata: [:request_id]

# Use Jason for JSON parsing in Phoenix
config :phoenix, :json_library, Jason

config :homex,
  broker: [host: "192.168.2.223", port: 1883, username: "nerves", password: "ofsteel"],
  device: [
    name: "Office Workstation",
    manufacturer: "Underjord",
    model: "Workstation"
  ],
  entities: [
    Auto.HomeAssistant.OfficeCO2,
    Auto.HomeAssistant.OfficeTemperature,
    Auto.HomeAssistant.OfficePM1,
    Auto.HomeAssistant.OfficePM25,
    Auto.HomeAssistant.OfficePM10,
    Auto.HomeAssistant.OfficeVOC,
    Auto.HomeAssistant.OfficeHumidity,
    Auto.HomeAssistant.OfficePressure
    # Disabled: wifiman-desktop.service is not installed on this machine.
    # Auto.HomeAssistant.WifimanService
  ]

# Import environment specific config. This must remain at the bottom
# of this file so it overrides the configuration defined above.
# Home cluster node (lawik/home_base). Capture hardware is :on_request: the mic and camera
# are only opened while a lease holds them. The physical displays are not vended; emerge
# only ever draws in a Wayland window, and only while something is shown on "win0".
# Structs can't be named here (config is evaluated before emerge compiles), hence the
# {:window, fields} tuple.
config :home_base,
  device_id: "monolith",
  data_dir: Path.expand("~/.local/share/auto/home_base"),
  capabilities: [
    %{
      id: "mic0",
      kind: :audio_in,
      availability: :on_request,
      adapter: Home.Adapters.Audio.PortAudioIn
    },
    %{
      id: "spk0",
      kind: :audio_out,
      availability: :on_request,
      adapter: Home.Adapters.Audio.PortAudioOut
    },
    %{
      id: "cam0",
      kind: :video_in,
      availability: :on_request,
      adapter: Home.Adapters.Video.Camera,
      # Video negotiation reads w/h/fps as x264's size and rate on this node: without them
      # the stream's size is unknown and small sinks (a watch) aren't sent a scaled stream.
      # The Cam Link only delivers its HDMI input's mode, so these must match that source.
      meta: %{
        device: "/dev/v4l/by-id/usb-Elgato_Cam_Link_4K_0004A17E28000-video-index0",
        w: 1920,
        h: 1080,
        fps: 30
      }
    },
    %{
      id: "win0",
      kind: :display,
      meta: %{w: 1280, h: 720},
      adapter:
        {Home.Adapters.Display,
         output: {:window, backend: :wayland, title: "Home", size: {1280, 720}}}
    }
  ],
  # The same static peer list the Nerves nodes use (their names resolve over mDNS).
  cluster: [
    backend:
      {Home.Cluster.Static,
       nodes: [
         :"nerves_phone@nerves-6a3a.local",
         :"nerves_phone@nerves-a835.local",
         :"hello_watch@nerves-0453.local",
         :"home@192.168.4.148"
       ]}
  ]

import_config "#{config_env()}.exs"
