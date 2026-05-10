#===============================================================================
#  Pokemon Pathways Multiplayer Client - Remote Player Character
#
#  Subclass of Game_Character that the existing Spriteset_Map can render like
#  any other map character. Reads position from a RemotePlayerData instance
#  and applies smoothed interpolation each frame.
#
#  FIXES vs original:
#   * CONSTRUCTOR: super() with no arguments. Original called super($game_map)
#     but Game_Character#initialize in PE v19.1 takes no arguments.
#   * INTERPOLATION: now delegates to RemotePlayerData#update_interpolation which
#     snapshots from current real_x/real_y, preventing backwards snapping.
#   * NAME SPRITE VIEWPORT: creates name sprites on an explicit viewport with
#     high Z so they appear above tiles but below menus.
#   * No Sprite/Bitmap creation happens in initialize; create_name_sprite must
#     be called explicitly from the main thread only.
#===============================================================================

class MP_Game_RemotePlayer < Game_Character
  attr_reader   :mp_id, :mp_name, :data
  attr_accessor :mp_sprite  # back-reference to our Sprite_Character, set by overworld

  def initialize(data)
    super()   # FIX: no arguments - Game_Character#initialize takes none in PE v19.1
    @data    = data            # RemotePlayerData instance
    @mp_id   = data.id
    @mp_name = data.name

    # Game_Character configuration
    @through        = true    # don't block player movement
    @walk_anime     = true
    @step_anime     = false
    @transparent    = false
    @opacity        = 255
    @move_speed     = 4

    # Sync initial position from data
    @x          = data.x
    @y          = data.y
    @real_x     = data.real_x.to_i
    @real_y     = data.real_y.to_i
    @direction  = data.direction
    @original_direction = data.direction

    set_character_graphic(data.sprite_name)

    # Name label sprite (nil until create_name_sprite is called)
    @name_sprite    = nil
    @name_viewport  = nil
  end

  # ─── Frame update ──────────────────────────────────────────────────────────

  def update
    # Advance interpolation in RemotePlayerData
    @data.update_interpolation if MP_ClientConfig::INTERPOLATION_ENABLED

    # Mirror real_x/real_y from data to self (Game_Character uses these for rendering)
    @real_x     = @data.real_x.to_i
    @real_y     = @data.real_y.to_i
    @x          = @data.x
    @y          = @data.y
    @direction  = @data.direction

    # Animate walk cycle when interpolating
    if @data.interpolating
      @pattern    = (@pattern + 1) % 4 if Graphics.frame_count % 8 == 0
    end

    update_name_sprite_position
    super
  end

  # ─── Appearance setters (called from main thread) ──────────────────────────

  def set_character_graphic(name)
    return if name.nil?
    n = name.to_s
    n = "boy_bike" if n.empty?
    @character_name = n
    @character_hue  = 0
  end

  def set_direction(dir)
    @direction = dir.to_i
    @original_direction = @direction
    @stop_count = 0
    @data.direction = @direction
  end

  # ─── Name sprite ───────────────────────────────────────────────────────────

  # Must be called from the main (game loop) thread.
  def create_name_sprite(viewport = nil)
    dispose_name_sprite
    return unless @mp_name

    width  = 160
    height = 36

    bitmap = Bitmap.new(width, height)

    # Player name
    bitmap.font.size  = 16
    bitmap.font.bold  = true
    bitmap.font.color = Color.new(255, 255, 255)
    shadow_color      = Color.new(0, 0, 0, 180)
    bitmap.font.color = shadow_color
    bitmap.draw_text(1, 1, width, 20, @mp_name, 1)
    bitmap.font.color = Color.new(255, 255, 255)
    bitmap.draw_text(0, 0, width, 20, @mp_name, 1)

    # Party display (first Pokémon)
    pd = @data.party_display
    if pd
      species = pd["species"] || pd[:species]
      level   = pd["level"]   || pd[:level]
      if species && level
        bitmap.font.size  = 12
        bitmap.font.bold  = false
        bitmap.font.color = Color.new(200, 220, 255)
        bitmap.draw_text(0, 20, width, 16, "Lv.#{level} #{species}", 1)
      end
    end

    # FIX: use supplied viewport (passed in from overworld manager which has
    # the correct map viewport). Fallback to nil (default/full-screen) if none.
    @name_sprite    = Sprite.new(viewport)
    @name_sprite.bitmap = bitmap
    @name_sprite.ox = width / 2
    @name_sprite.oy = height
    @name_sprite.z  = 5000   # above tiles, below menus
  end

  def dispose_name_sprite
    if @name_sprite && !@name_sprite.disposed?
      @name_sprite.bitmap.dispose if @name_sprite.bitmap && !@name_sprite.bitmap.disposed?
      @name_sprite.dispose
    end
    @name_sprite = nil
  end

  def update_name_sprite_position
    return unless @name_sprite && !@name_sprite.disposed?
    @name_sprite.x       = screen_x
    @name_sprite.y       = screen_y - 48
    @name_sprite.visible = !@transparent && @data.visible
  end

  # Rebuild the name label (e.g. after party update).
  def refresh_name_sprite(viewport = nil)
    vp = (viewport || (@name_sprite&.viewport))
    create_name_sprite(vp)
  end

  # ─── Cleanup ───────────────────────────────────────────────────────────────

  def dispose
    dispose_name_sprite
  end
end
