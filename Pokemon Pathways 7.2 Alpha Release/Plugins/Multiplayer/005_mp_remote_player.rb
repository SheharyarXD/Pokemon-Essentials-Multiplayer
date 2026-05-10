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
#   * OW SHADOWS EX: Sprite_OWShadow calls event.name and runs regex on it.
#     Plain Game_Character / remote players must return a String (never nil) or
#     the shadow plugin raises when the second remote sprite is created.
#   * character_name reader: never nil — OWShadow matches SHADOWLESS patterns
#     with character_name[/regex/].
#   * @pattern: safe when walk animation runs before base init sets pattern.
#   * update / name sprite: guarded so one failure does not kill the map loop.
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
    @pattern        = 0       # OW / Sprite_Character assume a numeric pattern

    # Sync initial position from data
    @x          = data.x
    @y          = data.y
    @real_x     = data.real_x.to_i
    @real_y     = data.real_y.to_i
    @direction  = data.direction
    @original_direction = data.direction

    set_character_graphic(data.sprite_name)

    # Sprite_OWShadow#jump_sprite reads these; ensure numeric even if base init differs.
    @jump_count           = 0 if @jump_count.nil?
    @jump_peak            = 0 if @jump_peak.nil?
    @jump_distance        = 0 if @jump_distance.nil?
    @jump_distance_left   = 0 if @jump_distance_left.nil?

    # Name label sprite (nil until create_name_sprite is called)
    @name_sprite    = nil
    @name_viewport  = nil
  end

  # Overworld Shadows EX (and similar) call event.name — must be a String.
  def name
    ""
  end

  # Safe for plugins that do character_name[/regex/] (nil would crash).
  def character_name
    n = @character_name
    (n.nil? || n.to_s.empty?) ? "boy_bike" : n.to_s
  end

  # ─── Frame update ──────────────────────────────────────────────────────────

  def update
    @data.update_interpolation if MP_ClientConfig::INTERPOLATION_ENABLED

    @real_x     = @data.real_x.to_i
    @real_y     = @data.real_y.to_i
    @x          = @data.x
    @y          = @data.y
    @direction  = @data.direction

    if @data.interpolating
      pat = @pattern || 0
      @pattern = (pat + 1) % 4 if Graphics.frame_count % 8 == 0
    end

    update_name_sprite_position
    super
  rescue => e
    mp_log_exception("MP_Game_RemotePlayer#update id=#{@mp_id}", e) if defined?(mp_log_exception)
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
    if viewport.nil? || (viewport.respond_to?(:disposed?) && viewport.disposed?)
      mp_log("MP_Game_RemotePlayer#create_name_sprite skipped: viewport nil/disposed id=#{@mp_id}") if defined?(mp_log)
      return
    end

    width  = 160
    height = 36

    bitmap = Bitmap.new(width, height)

    bitmap.font.size  = 16
    bitmap.font.bold  = true
    bitmap.font.color = Color.new(255, 255, 255)
    shadow_color      = Color.new(0, 0, 0, 180)
    bitmap.font.color = shadow_color
    bitmap.draw_text(1, 1, width, 20, @mp_name, 1)
    bitmap.font.color = Color.new(255, 255, 255)
    bitmap.draw_text(0, 0, width, 20, @mp_name, 1)

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

    @name_sprite    = Sprite.new(viewport)
    @name_sprite.bitmap = bitmap
    @name_sprite.ox = width / 2
    @name_sprite.oy = height
    @name_sprite.z  = 5000
  rescue => e
    mp_log_exception("MP_Game_RemotePlayer#create_name_sprite id=#{@mp_id}", e) if defined?(mp_log_exception)
    dispose_name_sprite
  end

  def dispose_name_sprite
    if @name_sprite && !@name_sprite.disposed?
      @name_sprite.bitmap.dispose if @name_sprite.bitmap && !@name_sprite.bitmap.disposed?
      @name_sprite.dispose
    end
    @name_sprite = nil
  rescue => e
    mp_log_exception("MP_Game_RemotePlayer#dispose_name_sprite id=#{@mp_id}", e) if defined?(mp_log_exception)
    @name_sprite = nil
  end

  def update_name_sprite_position
    return unless @name_sprite && !@name_sprite.disposed?
    vp = @name_sprite.viewport
    return if vp && vp.respond_to?(:disposed?) && vp.disposed?
    @name_sprite.x       = screen_x
    @name_sprite.y       = screen_y - 48
    @name_sprite.visible = !@transparent && @data.visible
  rescue => e
    mp_log_exception("MP_Game_RemotePlayer#update_name_sprite_position id=#{@mp_id}", e) if defined?(mp_log_exception)
  end

  # Rebuild the name label (e.g. after party update).
  def refresh_name_sprite(viewport = nil)
    vp = viewport || (@name_sprite&.viewport)
    return if vp && vp.respond_to?(:disposed?) && vp.disposed?
    create_name_sprite(vp)
  end

  # ─── Cleanup ───────────────────────────────────────────────────────────────

  def dispose
    dispose_name_sprite
  rescue => e
    mp_log_exception("MP_Game_RemotePlayer#dispose id=#{@mp_id}", e) if defined?(mp_log_exception)
  end
end
