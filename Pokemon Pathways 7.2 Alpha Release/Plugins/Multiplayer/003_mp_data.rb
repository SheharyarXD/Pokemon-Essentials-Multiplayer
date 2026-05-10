#===============================================================================
#  Pokemon Pathways Multiplayer Plugin - Data Models
#  RemotePlayer struct and related data structures
#===============================================================================

class RemotePlayer
  attr_accessor :id, :name, :map_id, :x, :y, :real_x, :real_y, :dir, :sprite,
                :outfit, :party_display, :target_x, :target_y, :interpolating,
                :interpolate_start, :interpolate_duration, :last_update, :visible

  def initialize(id, name, map_id, x, y, dir, sprite = "", outfit = 0)
    @id = id
    @name = name
    @map_id = map_id
    @x = x
    @y = y
    @real_x = x * Game_Map::REAL_RES_X
    @real_y = y * Game_Map::REAL_RES_Y
    @dir = dir
    @sprite = sprite
    @outfit = outfit
    @party_display = nil
    @target_x = x
    @target_y = y
    @interpolating = false
    @interpolate_start = 0
    @interpolate_duration = MP_ClientConfig::INTERPOLATION_DURATION
    @last_update = Time.now.to_f * 1000
    @visible = true
  end

  def update_interpolation
    return unless @interpolating

    now = Time.now.to_f * 1000
    elapsed = now - @interpolate_start

    if elapsed >= @interpolate_duration
      @x = @target_x
      @y = @target_y
      @real_x = @x * Game_Map::REAL_RES_X
      @real_y = @y * Game_Map::REAL_RES_Y
      @interpolating = false
    else
      t = elapsed / @interpolate_duration
      # Ease-in-out lerp
      t = t < 0.5 ? 2 * t * t : 1 - 2 * (1 - t) * (1 - t)
      current_x = lerp(@x, @target_x, t)
      current_y = lerp(@y, @target_y, t)
      @real_x = current_x * Game_Map::REAL_RES_X
      @real_y = current_y * Game_Map::REAL_RES_Y
    end
  end

  def set_target(nx, ny)
    return if nx == @x && ny == @y

    @target_x = nx
    @target_y = ny
    @interpolating = true
    @interpolate_start = Time.now.to_f * 1000
  end

  def screen_x
    ret = ((@real_x - $game_map.display_x) / Game_Map::X_SUBPIXELS).round
    ret += Game_Map::TILE_WIDTH / 2
    return ret
  end

  def screen_y
    ret = ((@real_y - $game_map.display_y) / Game_Map::Y_SUBPIXELS).round
    ret += Game_Map::TILE_HEIGHT
    return ret
  end

  def screen_z
    z = ((@real_y - $game_map.display_y) / Game_Map::Y_SUBPIXELS).round
    z += Game_Map::TILE_HEIGHT
    return z
  end

  def distance_to_player
    dx = @x - $game_player.x
    dy = @y - $game_player.y
    Math.sqrt(dx * dx + dy * dy)
  end

  def should_cull?
    return false unless $game_map
    distance_to_player > MP_ClientConfig::VISIBLE_DISTANCE
  end

  private

  def lerp(a, b, t)
    a + (b - a) * t
  end
end
