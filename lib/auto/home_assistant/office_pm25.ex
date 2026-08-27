defmodule Auto.HomeAssistant.OfficePM25 do
  use Homex.Entity.Sensor,
    name: "office-pm25",
    unit_of_measurement: "µg/m³",
    device_class: "pm25",
    state_class: "measurement",
    retain: true

  def handle_init(entity) do
    Phoenix.PubSub.subscribe(Auto.PubSub, "airquality")
    entity
  end

  # A missing reading is left alone rather than published as a value.
  def handle_message({:air_quality_data, %{pm2_5: nil}}, entity), do: entity

  def handle_message({:air_quality_data, data}, entity) do
    entity |> set_value(data.pm2_5)
  end
end
