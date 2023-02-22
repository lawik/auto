defmodule Auto.Repo do
  use Ecto.Repo,
    otp_app: :auto,
    adapter: Ecto.Adapters.SQLite3
end
