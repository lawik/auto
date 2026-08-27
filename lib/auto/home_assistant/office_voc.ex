defmodule Auto.HomeAssistant.OfficeVOC do
  @moduledoc """
  The purifier's VOC reading is an SGP40 VOC Index, not a concentration: a
  1-500 scale where 100 is the sensor's own rolling 24h baseline. Home
  Assistant's volatile_organic_compounds classes are all concentrations
  (µg/m³ or ppb), so this deliberately carries no device class or unit —
  labelling an index with a mass unit would be wrong.
  """
  use Homex.Entity.Sensor,
    name: "office-voc",
    state_class: "measurement",
    retain: true

  def handle_init(entity) do
    Phoenix.PubSub.subscribe(Auto.PubSub, "airquality")
    entity
  end

  # A missing reading is left alone rather than published as a value.
  def handle_message({:air_quality_data, %{voc: nil}}, entity), do: entity

  def handle_message({:air_quality_data, data}, entity) do
    entity |> set_value(data.voc)
  end
end
