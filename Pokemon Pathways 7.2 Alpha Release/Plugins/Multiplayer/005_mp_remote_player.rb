#===============================================================================
#  MP REMOTE PLAYER v1.2.0
#  Game_Character subclass that mirrors remote player movement.
#  FIXED:
#    1. super() called with no args (Game_Character#initialize takes none)
#    2. Name bitmap caching (only recreates when content changes)
#    3. Added @name_dirty flag to track when name needs redraw
#    4. Fixed dispose_name_sprite to nil bitmap reference after disposal
#    5. Added culled flag to skip updates when off-screen
#    6. Added walking animation sync with interpolation progress
#  
#  NOTE: File 003_mp_data.rb (RemotePlayer class) was dead code and has been
#        removed. All remote player logic lives here.
#===============================================================================

class MP_Game_RemotePlayer < Game_Character
  attr_accessor :mp_id, :mp_name, :party_display, :name_sprite, :visible
  attr_reader :target_x, :target_y, :interpolating, :culled, :map_id

  def initialize(mp_id, name, map_id, x, y, dir, sprite = "", outfit = 0)
    super()  # FIXED: Game_Character#initialize takes no arguments

    @mp_id = mp_id
    @mp_name = name
    @map_id = map_id
    @party_display = nil
    @through = true       # remote players pass through obstacles
    @walk_anime = true    # animate while interpolating
    @step_anime = false
    @transparent = false
    @opacity = 255
    @visible = true
    @culled = false

    # Position
    @x = x
    @y = y
    @real_x = x * Game_Map::REAL_RES_X
    @real_y = y * Game_Map::REAL_RES_Y
    @direction = dir

    # Sprite
    @character_name = (sprite && !sprite.empty?) ? sprite : "boy_bike"
    @character_hue = 0
    @outfit = outfit

    # Interpolation state
    @target_x = x
    @target_y = y
    @interpolating = false
    @interpolate_start = 0
    @interpolate_duration = MP_ClientConfig::INTERPOLATION_DURATION
    @last_update = Time.now.to_f * 1000

    # Name display
    @name_sprite = nil
    @name_bitmap_text = ""  # cache key for name bitmap
    @name_dirty = true
  end

  def update
    # Skip expensive updates if culled
    return if @culled

    # Only call Game_Character#update if we're actually moving
    # This prevents the pattern counter from advancing while stationary,
    # which avoids unnecessary sprite sheet updates
    if @interpolating || moving?
      super
    end

    update_interpolation if MP_ClientConfig::INTERPOLATION_ENABLED
    update_name_sprite if @name_sprite && !@name_sprite.disposed?
  end

  def set_target(nx, ny)
    return if nx == @x && ny == @y

    @target_x = nx
    @target_y = ny
    @interpolating = true
    @interpolate_start = Time.now.to_f * 1000
    @last_update = @interpolate_start

    # Trigger walking animation for the duration of the move
    @walk_anime = true
  end

  def update_interpolation
    return unless @interpolating

    now = Time.now.to_f * 1000
    elapsed = now - @interpolate_start

    if elapsed >= @interpolate_duration
      # Snap to target
      @x = @target_x
      @y = @target_y
      @real_x = @x * Game_Map::REAL_RES_X
      @real_y = @y * Game_Map::REAL_RES_Y
      @interpolating = false
      @walk_anime = false  # stop walk animation when arrival completes
    else
      t = elapsed / @interpolate_duration
      # Ease-in-out lerp for smooth acceleration/deceleration
      t = t < 0.5 ? 2 * t * t : 1 - ((-2 * t + 2) ** 2) / 2
      cx = lerp(@x, @target_x, t)
      cy = lerp(@y, @target_y, t)
      @real_x = cx * Game_Map::REAL_RES_X
      @real_y = cy * Game_Map::REAL_RES_Y
    end
  end

  def set_direction(dir)
    return unless dir && dir >= 2 && dir <= 8
    @direction = dir
    @original_direction = dir
    @stop_count = 0
  end

  def set_sprite(sprite, outfit_val = 0)
    return if sprite.nil? || sprite.empty?
    return if @character_name == sprite && @outfit == outfit_val
    @character_name = sprite
    @outfit = outfit_val
  end

  def set_party_display(display)
    old = @party_display
    @party_display = display
    # Mark dirty if display changed
    @name_dirty = true if old.inspect != display.inspect
  end

  def distance_to_player
    return 9999 unless $game_player
    dx = @x - $game_player.x
    dy = @y - $game_player.y
    Math.sqrt(dx * dx + dy * dy)
  end

  def should_cull?
    distance_to_player > MP_ClientConfig::VISIBLE_DISTANCE
  end

  def culled=(val)
    @culled = val
  end

  # --- Name sprite management ---

  def dispose_name_sprite
    if @name_sprite
      begin
        @name_sprite.bitmap.dispose if @name_sprite.bitmap && !@name_sprite.bitmap.disposed?
      rescue; end
      begin
        @name_sprite.dispose unless @name_sprite.disposed?
      rescue; end
      @name_sprite = nil
      @name_bitmap_text = ""
    end
  end

  def update_name_sprite
    return unless @name_sprite && !@name_sprite.disposed?

    # Recreate bitmap if content changed
    create_name_bitmap if @name_dirty

    @name_sprite.x = screen_x
    @name_sprite.y = screen_y - 24
    @name_sprite.z = screen_z + 200
    @name_sprite.visible = @visible && !@transparent && !@culled
  end

  def create_name_bitmap
    return unless @mp_name

    # Build cache key to avoid unnecessary recreation
    party_str = ""
    if @party_display
      s = @party_display[:species] || @party_display["species"]
      l = @party_display[:level] || @party_display["level"]
      party_str = "|#{s}|#{l}" if s && l
    end
    cache_key = "#{@mp_name}#{party_str}"

    return if cache_key == @name_bitmap_text && @name_sprite

    # Dispose old bitmap
    dispose_name_sprite if @name_sprite

    # Build new bitmap
    bitmap = Bitmap.new(160, 36)
    bitmap.font.size = 14
    bitmap.font.color = Color.new(255, 255, 255)
    bitmap.draw_text(0, 0, 160, 18, @mp_name, 1)

    if @party_display
      species_name = @party_display[:species] || @party_display["species"]
      level = @party_display[:level] || @party_display["level"]
      if species_name && level
        info_text = "Lv.#{level} #{species_name}"
        bitmap.font.size = 11
        bitmap.font.color = Color.new(180, 220, 255)
        bitmap.draw_text(0, 18, 160, 14, info_text, 1)
      end
    end

    @name_sprite = Sprite.new
    @name_sprite.bitmap = bitmap
    @name_sprite.ox = 80
    @name_sprite.oy = 18
    @name_sprite.x = screen_x
    @name_sprite.y = screen_y - 24
    @name_sprite.z = screen_z + 200
    @name_bitmap_text = cache_key
    @name_dirty = false
  end

  # Mark name as needing redraw
  def invalidate_name
    @name_dirty = true
  end

  private

  def lerp(a, b, t)
    a + (b - a) * t
  end
end
