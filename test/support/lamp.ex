defmodule Avwe.Test.Lamp do
  @moduledoc """
  A test-only system with a rhythm of the day and no randomness: it lights at
  06:00 and goes dark at 18:00, says so in an event each time (`:lit`, `:dark`),
  and keeps whether it is lit in the environment. Used where a test wants a system
  that acts at a moment of the day, as `Tick.crossed?/3` makes it do.
  """

  @behaviour Avwe.System

  alias Avwe.{Calendar, Event, Region, Tick}

  @impl Avwe.System
  def system_id, do: "test.lamp/step"

  @impl Avwe.System
  def run(region, tick) do
    lit = lit?(Calendar.time_of_day(Tick.end_time(tick)))

    events =
      cond do
        Tick.crossed?(tick, Calendar.day(), 6 * Calendar.hour()) -> [Event.new(:lit)]
        Tick.crossed?(tick, Calendar.day(), 18 * Calendar.hour()) -> [Event.new(:dark)]
        true -> []
      end

    {Region.put_env(region, :lit, lit), events}
  end

  defp lit?(time_of_day),
    do: time_of_day >= 6 * Calendar.hour() and time_of_day < 18 * Calendar.hour()
end
