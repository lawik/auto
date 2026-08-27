defmodule Auto.HomeAssistant.OfficeHumidity do
  use Homex.Entity.Sensor,
    name: "office-humidity",
    unit_of_measurement: "%",
    device_class: "humidity",
    state_class: "measurement",
    retain: true

  def handle_init(entity) do
    Phoenix.PubSub.subscribe(Auto.PubSub, "airquality")
    entity
  end

  # A missing reading is left alone rather than published as a value.
  def handle_message({:air_quality_data, %{humidity: nil}}, entity), do: entity

  def handle_message({:air_quality_data, data}, entity) do
    entity |> set_value(data.humidity)
  end
end
