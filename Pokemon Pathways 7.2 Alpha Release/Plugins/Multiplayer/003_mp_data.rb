#===============================================================================
#  Pokemon Pathways Multiplayer Client - Data Models
<<<<<<< HEAD
#  REMOTE SKIN SYNC v3.0 — Added character_hue, trainer_type, safe accessors
=======
>>>>>>> aada347da767172eb53ec24119bd43fe6fa1c095
#
#  RemotePlayer is a pure data struct: position, interpolation, appearance.
#  It does NOT hold any Sprite or Bitmap references - those live in
#  MP_Game_RemotePlayer (005). This separation keeps data safe to read/write
#  from any thread.
<<<<<<< HEAD
=======
#
#  FIXES vs original:
#   * Removed screen_x/screen_y/screen_z helpers (moved to Game_Character subclass).
#   * Interpolation now snapshots current real_x/real_y as the start of the lerp,
#     so mid-interpolation re-targets don't snap the character backwards.
>>>>>>> aada347da767172eb53ec24119bd43fe6fa1c095
#===============================================================================

class RemotePlayerData
  attr_accessor :id, :name, :map_id, :x, :y, :real_x, :real_y,
<<<<<<< HEAD
                :direction, :sprite_name, :character_hue, :trainer_type, :outfit, :party_display,
=======
                :direction, :sprite_name, :outfit, :party_display,
>>>>>>> aada347da767172eb53ec24119bd43fe6fa1c095
                :visible

  # Interpolation state
  attr_reader :interp_from_x, :interp_from_y,
              :interp_to_x,   :interp_to_y,
              :interp_start,  :interp_duration,
              :interpolating

<<<<<<< HEAD
  def initialize(id, name, map_id, x, y, dir, sprite = "", outfit = 0, hue = 0, trainer_type = "")
=======
  def initialize(id, name, map_id, x, y, dir, sprite = "", outfit = 0)
>>>>>>> aada347da767172eb53ec24119bd43fe6fa1c095
    @id          = id
    @name        = name
    @map_id      = map_id
    @x           = x
    @y           = y
    @real_x      = tile_to_real_x(x)
    @real_y      = tile_to_real_y(y)
    @direction   = dir
    @sprite_name = sprite.to_s
<<<<<<< HEAD
    @character_hue = hue.to_i
    @trainer_type = trainer_type.to_s
=======
>>>>>>> aada347da767172eb53ec24119bd43fe6fa1c095
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

<<<<<<< HEAD
=======
  # Called when we receive a new position target.
  # FIX: snapshot current real_x/real_y as interp start, not tile coords.
  # This prevents the character snapping back when a new target arrives mid-lerp.
>>>>>>> aada347da767172eb53ec24119bd43fe6fa1c095
  def set_target(nx, ny)
    new_real_x = tile_to_real_x(nx)
    new_real_y = tile_to_real_y(ny)
    return if new_real_x == @real_x && new_real_y == @real_y && !@interpolating

<<<<<<< HEAD
    @interp_from_x = @real_x
=======
    @interp_from_x = @real_x   # wherever we are RIGHT NOW (may be mid-interpolation)
>>>>>>> aada347da767172eb53ec24119bd43fe6fa1c095
    @interp_from_y = @real_y
    @interp_to_x   = new_real_x
    @interp_to_y   = new_real_y
    @interp_start  = Time.now.to_f * 1000
    @interpolating = true
    @x             = nx
    @y             = ny
    @last_update   = @interp_start
  end

<<<<<<< HEAD
=======
  # Teleport immediately (used on MAP_PLAYER_LIST / initial placement).
>>>>>>> aada347da767172eb53ec24119bd43fe6fa1c095
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

<<<<<<< HEAD
=======
  # Advance the interpolation. Call once per frame from the game loop.
>>>>>>> aada347da767172eb53ec24119bd43fe6fa1c095
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
<<<<<<< HEAD
=======
      # Smoothstep easing (no jump at endpoints)
>>>>>>> aada347da767172eb53ec24119bd43fe6fa1c095
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
