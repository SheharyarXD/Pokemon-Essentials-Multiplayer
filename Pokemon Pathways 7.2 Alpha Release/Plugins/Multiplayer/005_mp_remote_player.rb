#===============================================================================
#  Pokemon Pathways Multiplayer Plugin - Remote Player Character
#  Game_Character subclass that mirrors remote player movement
#  Includes party display (first Pokemon species + level above sprite)
#===============================================================================

class MP_Game_RemotePlayer < Game_Character
  attr_accessor :mp_id, :mp_name, :party_display, :name_sprite
  attr_reader :target_x, :target_y, :interpolating

  def initialize(mp_id, name, map_id, x, y, dir, sprite = "", outfit = 0)
    super($game_map)
    @mp_id = mp_id
    @mp_name = name
    @party_display = nil
    @through = true
    @walk_anime = true
    @step_anime = false
    @transparent = false
    @opacity = 255

    # Set initial position
    @x = x
    @y = y
    @real_x = x * Game_Map::REAL_RES_X
    @real_y = y * Game_Map::REAL_RES_Y
    @direction = dir
    @original_direction = dir

    # Set sprite
    if sprite && !sprite.empty?
      @character_name = sprite
    else
      @character_name = "boy_bike" # default
    end
    @character_hue = 0

    # Interpolation state
    @target_x = x
    @target_y = y
    @interpolating = false
    @interpolate_start = 0
    @interpolate_duration = MP_ClientConfig::INTERPOLATION_DURATION
    @last_update = Time.now.to_f * 1000

    # Name display sprite
    @name_sprite = nil
  end

  def update
    super
    update_interpolation if MP_ClientConfig::INTERPOLATION_ENABLED
    update_name_sprite if @name_sprite
  end

  def set_target(nx, ny)
    return if nx == @x && ny == @y

    @target_x = nx
    @target_y = ny
    @interpolating = true
    @interpolate_start = Time.now.to_f * 1000
    @last_update = @interpolate_start
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
      t = t < 0.5 ? 2 * t * t : 1 - 2 * (1 - t) * (1 - t)
      current_x = lerp(@x, @target_x, t)
      current_y = lerp(@y, @target_y, t)
      @real_x = current_x * Game_Map::REAL_RES_X
      @real_y = current_y * Game_Map::REAL_RES_Y
    end
  end

  def set_direction(dir)
    @direction = dir
    @original_direction = dir
    @stop_count = 0
  end

  def set_sprite(sprite, outfit_val = 0)
    return if sprite.nil? || sprite.empty?
    @character_name = sprite
    @outfit = outfit_val
  end

  def set_party_display(display)
    @party_display = display
  end

  def distance_to_player
    return 999 unless $game_player
    dx = @x - $game_player.x
    dy = @y - $game_player.y
    Math.sqrt(dx * dx + dy * dy)
  end

  def should_cull?
    distance_to_player > MP_ClientConfig::VISIBLE_DISTANCE
  end

  def dispose_name_sprite
    if @name_sprite
      @name_sprite.bitmap.dispose if @name_sprite.bitmap
      @name_sprite.dispose
      @name_sprite = nil
    end
  end

  def update_name_sprite
    return unless @name_sprite
    @name_sprite.x = screen_x
    @name_sprite.y = screen_y - 20
    @name_sprite.z = screen_z + 100
    @name_sprite.visible = !@transparent
  end

  def create_name_bitmap
    dispose_name_sprite
    return unless @mp_name

    bitmap = Bitmap.new(160, 32)
    bitmap.font.size = 16
    bitmap.font.color = Color.new(255, 255, 255)
    bitmap.draw_text(0, 0, 160, 20, @mp_name, 1)

    if @party_display
      species_name = @party_display[:species] || @party_display["species"]
      level = @party_display[:level] || @party_display["level"]
      if species_name && level
        info_text = "Lv.#{level} #{species_name}"
        bitmap.font.size = 12
        bitmap.font.color = Color.new(200, 220, 255)
        bitmap.draw_text(0, 16, 160, 14, info_text, 1)
      end
    end

    @name_sprite = Sprite.new
    @name_sprite.bitmap = bitmap
    @name_sprite.ox = 80
    @name_sprite.oy = 16
    @name_sprite.x = screen_x
    @name_sprite.y = screen_y - 20
    @name_sprite.z = screen_z + 100
  end

  private

  def lerp(a, b, t)
    a + (b - a) * t
  end
end
