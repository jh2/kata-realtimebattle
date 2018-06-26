defmodule YourBot do

  use RealTimeBattleBot.Bot

  alias RealTimeBattleBot.BotContext

  # Customize your bot here
  @name "jh2"
  @color_home  "abcdef"
  @color_away  "fedcba"

  @reset_time_robot_hunt 1_000
  @reset_time_cookie_hunt 4_000
  @reset_time_braking 1_000
  @direction_change_interval 10_000

  defstruct state: :explore, timer: nil


  def init(_) do
    # Prepare some other stuff you need for your bot here, like a state different from :state
    {:ok, %YourBot{}}
  end

  def handle_info(:reset, state) do
    L.log("RESET")
    reset()
    {:noreply, %YourBot{}}
  end

  def handle_info({:change_direction, angle}, %YourBot{state: :explore} = state) do
    L.log("change_direction #{inspect angle}")
    P.send_rotate(:robot, angle)
    new_angle = angle * Enum.random([1, -1])
    Process.send_after(self(), {:change_direction, new_angle}, @direction_change_interval)
    {:noreply, state}
  end
  def handle_info({:change_direction, angle}, state) do
    Process.send_after(self(), {:change_direction, angle}, @direction_change_interval)
    {:noreply, state}
  end


  def handle_message({:init,  %{first_sequence: true}}, _context, _state) do
    # Starting the sequence of games
    L.log("INIT SEQUENCE")
    P.send_name(@name)
    P.send_colour(@color_home, @color_away)
  end

  def handle_message(:game_starts, _context, _state) do
    # Starting a single game, make your first moves
    L.log("GAME STARTS")

    reset()

    Process.send_after(self(), {:change_direction, -1.0}, @direction_change_interval)
  end

  def handle_message({:radar, %{object_type: :wall}}, _context, %YourBot{state: :braking}) do
    nil
  end
  def handle_message(
    {:radar, %{object_type: :wall, distance: distance}},
    %BotContext{speed: speed},
    state)
    when (distance < 3 and speed > 4) or (distance < 1 and speed > 1) do

    L.log("Braking for wall distance #{inspect distance} speed #{inspect speed}")
    drive_slow()
    rotate_to(Enum.random([3.0, -3.0]))
    Process.send_after(self(), :reset, @reset_time_braking)
    {:state, %YourBot{state | state: :braking}}
  end
  def handle_message({:radar, %{object_type: :wall}}, _context, _state) do
    nil
  end

  def handle_message({:radar, %{object_type: :cookie, radar_angle: radar_angle}}, context, %YourBot{state: :explore}) do
    L.log("Trying to eat the cookie  #{inspect context}")
    drive_slow()
    rotate_to(radar_angle)
    # Process.send_after(self(), :reset, @reset_time_cookie_hunt)
    {:state, %YourBot{state: :cookie_huntin}}
  end

  def handle_message({:radar, %{object_type: _, distance: _}}, _context, _state)  do
    # Your radar has detected something.
    # If its another robot, a :robot_info will follow.
  end

  def handle_message({:robot_info, _robot_info}, %BotContext{last_radar: %{object_type: :robot, radar_angle: enemy_angle}}, state) do
    # There is a robot in front of you.
    L.log("Shooting at enemy robot #{inspect enemy_angle}")
    P.send_sweep([:radar, :cannon], 10.0, -1.0, 1.0)
    P.send_shoot(20.0)
    rotate_to(enemy_angle)
    new_state =
      case state do
        %YourBot{state: :robot_huntin, timer: ref} ->
          L.log("Keep huntin")
          Process.cancel_timer(ref)
          new_ref = Process.send_after(self(), :reset, @reset_time_robot_hunt)
          %YourBot{state | timer: new_ref}
        _ ->
          L.log("Start huntin")
          drive_fast()
          ref = Process.send_after(self(), :reset, @reset_time_robot_hunt)
          %YourBot{state | state: :robot_huntin, timer: ref}
      end
    {:state, new_state}
  end


  def handle_message({:collision, %{object_type: :cookie}}, _context, %YourBot{state: :cookie_huntin}) do
    L.log("Got that cookie!")
    reset()
    {:state, %YourBot{}}
  end
  def handle_message({:collision, %{angle: _, object_type: type, object_type_id: _}}, _context, _state) do
    L.log("Got hit by a #{inspect type}")
  end

  def handle_message({:rotation_reached, %{what_id: _, what_list: [:robot]} = s}, _context, %YourBot{state: :cookie_huntin}) do
    L.log("rotation_reached #{inspect s}")
    drive_fast()
  end
  def handle_message({:rotation_reached, %{what_id: _, what_list: _} = s}, _context, _state), do: nil

  # Available but not really needed callbacks.
  def handle_message({:robots_left, _}, _context, _state), do: nil
  def handle_message({:energy, _}, _context, _state), do: nil
  def handle_message({:coordinates, %{angle: _, x: _, y: _}}, _context, _state), do: nil
  def handle_message({:info, %{canon_angle: _, speed: _, time: _}}, _context, _state), do: nil
  def handle_message({:game_option, %{option: _, value: _}}, _context, _state), do: nil
  def handle_message({:warning, %{message: _}}, _context, _state), do: nil

  def handle_message(message, context, state) do
    L.log("Not handling message you might want to know about.")
    L.log(message)
    L.log(context)
    L.log(state)
  end

  # Helper functions

  defp drive_slow() do
    P.send_brake(80.0)
    P.send_accelerate(0.1)
  end

  defp drive_normal() do
    P.send_brake(60.0)
    P.send_accelerate(0.3)
  end

  defp drive_fast() do
    P.send_brake(0.0)
    P.send_accelerate(1.0)
  end

  defp steer_left() do
    P.send_rotate(:robot, 2.0)
  end

  defp rotate_to(angle) do
    P.send_rotate_amount(:robot, 5.0, angle)
  end

  defp reset() do
    P.send_sweep([:radar, :cannon], 10.0, -0.75, 0.75)
    P.send_rotate(:robot, 1.0)
    drive_fast()
  end

end
