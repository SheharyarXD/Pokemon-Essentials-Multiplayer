#===============================================================================
#  Pokemon Pathways Multiplayer Client - Data Models
#  REMOTE SKIN SYNC v3.0 — Added character_hue, trainer_type, safe accessors
#
#  RemotePlayer is a pure data struct: position, interpolation, appearance.
#  It does NOT hold any Sprite or Bitmap references - those live in
#  MP_Game_RemotePlayer (005). This separation keeps data safe to read/write
#  from any thread.
#===============================================================================

class RemotePlayerData
  attr_accessor :id, :name, :map_id, :x, :y, :real_x, :real_y,
                :direction, :sprite_name, :character_hue, :trainer_type, :outfit, :party_display,
                :visible

  # Interpolation state
  attr_reader :interp_from_x, :interp_from_y,
              :interp_to_x,   :interp_to_y,
              :interp_start,  :interp_duration,
              :interpolating

  def initialize(id, name, map_id, x, y, dir, sprite = "", outfit = 0, hue = 0, trainer_type = "")
    @id          = id
    @name        = name
    @map_id      = map_id
    @x           = x
    @y           = y
    @real_x      = tile_to_real_x(x)
    @real_y      = tile_to_real_y(y)
    @direction   = dir
    @sprite_name = sprite.to_s
    @character_hue = hue.to_i
    @trainer_type = trainer_type.to_s
    @outfit      = outfit.to_i
    @party_display = nil
    @visible     = true

    @interp_from_x  = @real_x
    @interp_from_y  = @real_y
    @interp_to_x    = @real_x
    @interp_to_y    = @real_y
    @interp_start   = 0
    @interp_duration= MP_ClientConfig::INTERPOLATION_DURATION.to_f
    @interpolating  = false
    @last_update    = Time.now.to_f * 1000
  end

  # ─── Movement / interpolation ───────────────────────────────────────────────

  def set_target(nx, ny)
    new_real_x = tile_to_real_x(nx)
    new_real_y = tile_to_real_y(ny)
    return if new_real_x == @real_x && new_real_y == @real_y && !@interpolating

    @interp_from_x = @real_x
    @interp_from_y = @real_y
    @interp_to_x   = new_real_x
    @interp_to_y   = new_real_y
    @interp_start  = Time.now.to_f * 1000
    @interpolating = true
    @x             = nx
    @y             = ny
    @last_update   = @interp_start
  end

  def warp_to(nx, ny)
    @x          = nx
    @y          = ny
    @real_x     = tile_to_real_x(nx)
    @real_y     = tile_to_real_y(ny)
    @interp_from_x = @real_x
    @interp_from_y = @real_y
    @interp_to_x   = @real_x
    @interp_to_y   = @real_y
    @interpolating = false
    @last_update   = Time.now.to_f * 1000
  end

  def update_interpolation
    return unless @interpolating

    now     = Time.now.to_f * 1000
    elapsed = now - @interp_start

    if elapsed >= @interp_duration
      @real_x        = @interp_to_x
      @real_y        = @interp_to_y
      @interpolating = false
    else
      t = elapsed / @interp_duration
      t = t * t * (3.0 - 2.0 * t)
      @real_x = @interp_from_x + (@interp_to_x - @interp_from_x) * t
      @real_y = @interp_from_y + (@interp_to_y - @interp_from_y) * t
    end
  end

  # ─── Visibility ─────────────────────────────────────────────────────────────

  def distance_to_player
    return 999 unless $game_player
    dx = @x - $game_player.x
    dy = @y - $game_player.y
    Math.sqrt(dx * dx + dy * dy)
  end

  def should_cull?
    distance_to_player > MP_ClientConfig::VISIBLE_DISTANCE
  end

  private

  def tile_to_real_x(tx)
    tx * (Game_Map::REAL_RES_X rescue 128)
  rescue
    tx * 128
  end

  def tile_to_real_y(ty)
    ty * (Game_Map::REAL_RES_Y rescue 128)
  rescue
    ty * 128
  end
end
