#===============================================================================
#  Pokemon Pathways Multiplayer Client - Remote Player Character (STABLE v2.1)
#
#  CRITICAL FIX: Addresses Root Cause #5 (name sprite viewport staleness) and
#  hardens all rendering-related code paths.
#
#  ARCHITECTURE:
#    Subclass of Game_Character. PE's Spriteset_Map can render us like any
#    other character. Position/animation reads from RemotePlayerData.
#
#  KEY SAFETY CHANGES:
#    * update_name_sprite_position: validates sprite AND bitmap AND viewport
#      on every call. Disposes and nils if any are invalid.
#    * create_name_sprite: additional validation that viewport isn't disposed.
#    * No direct bitmap disposal without nil check.
#    * All update paths wrapped in begin/rescue.
#    * screen_x/screen_y delegates to data's real_x/real_y (no super call
#      to Game_Character#update which has side effects).
#===============================================================================

class MP_Game_RemotePlayer < Game_Character
  attr_reader   :mp_id, :mp_name, :data
  attr_accessor :mp_sprite

  def initialize(data)
    super()
    @data    = data
    @mp_id   = data.id
    @mp_name = data.name

    # Game_Character configuration
    @through        = true
    @walk_anime     = true
    @step_anime     = false
    @transparent    = false
    @opacity        = 255
    @move_speed     = 4
    @pattern        = 0
    @priority_type  = 1   # 0=below, 1=same, 2=above player

    # Sync initial position from data
    @x          = data.x
    @y          = data.y
    @real_x     = data.real_x.to_i
    @real_y     = data.real_y.to_i
    @direction  = data.direction
    @original_direction = data.direction

    set_character_graphic(data.sprite_name)

    # Ensure jump vars exist (some plugins read them)
    @jump_count         = 0
    @jump_peak          = 0
    @jump_distance      = 0
    @jump_distance_left = 0

    # Name label sprite (nil until create_name_sprite is called)
    @name_sprite    = nil
    @name_viewport  = nil
    @name_valid     = false  # true when name sprite is confirmed alive
  end

  # Overworld Shadows EX calls event.name — must be a String.
  def name
    ""
  end

  # Safe for plugins that do character_name[/regex/] (nil => crash).
  def character_name
    n = @character_name
    (n.nil? || n.to_s.empty?) ? "" : n.to_s
  end

  # Override to provide our own pattern for animation
  def pattern
    @pattern || 0
  end

  # ─── Frame update (called by MP_OverworldManager) ──────────────────────────

  def update
    # Interpolate position
    if MP_ClientConfig::INTERPOLATION_ENABLED
      begin
        @data.update_interpolation
      rescue => e
        # Interpolation failure is non-fatal
      end
    end

    # Sync position from data to Game_Character vars
    @real_x     = @data.real_x.to_i
    @real_y     = @data.real_y.to_i
    @x          = @data.x
    @y          = @data.y
    @direction  = @data.direction

    # Walk animation pattern cycling
    if @data.interpolating || @data.respond_to?(:moving?) && @data.moving?
      @pattern = ((@pattern || 0) + 1) % 4 if Graphics.frame_count % 8 == 0
    else
      @pattern = 1  # standing frame
    end

    # Update name label position
    update_name_sprite_position

    # DO NOT call super — Game_Character#update has move route processing,
    # collision detection, and other side effects we don't want for remote
    # players. All our state comes from @data.
  rescue => e
    mp_log_exception("MP_Game_RemotePlayer#update id=#{@mp_id}", e) if defined?(mp_log_exception)
  end

  # ─── Screen position (used by sprite) ──────────────────────────────────────

  # Override to use our real_x/real_y directly (matches PE formula)
  def screen_x
    ((@real_x + Game_Map::REAL_RES_X / 2) / Game_Map::REAL_RES_X rescue
     (@real_x + 128) / 256).to_i + 16
  rescue
    (@x || 0) * 32 + 16
  end

  def screen_y
    ((@real_y + Game_Map::REAL_RES_Y / 2) / Game_Map::REAL_RES_Y rescue
     (@real_y + 128) / 256).to_i + 32
  rescue
    (@y || 0) * 32 + 32
  end

  def screen_z(z = 0)
    return z + 100 if @priority_type == 2
    if @priority_type == 1 && $game_player
      return z + (screen_y <= $game_player.screen_y ? 100 : 0)
    end
    z
  rescue
    z + 50
  end

  # ─── Appearance setters ────────────────────────────────────────────────────

  def set_character_graphic(name)
    n = name.to_s
    # Don't crash on missing charset — let the sprite handle it
    @character_name = n
    @character_hue  = 0
  end

  def set_direction(dir)
    d = dir.to_i
    @direction = d
    @original_direction = d
    @stop_count = 0
    @data.direction = d
  end

  # ─── Name sprite (main thread only) ────────────────────────────────────────

  def create_name_sprite(viewport = nil)
    dispose_name_sprite
    return unless @mp_name

    # PHASE 1: if rendering is disabled, skip name sprite too
    return unless MP_ClientConfig::REMOTE_RENDERING_ENABLED

    # Validate viewport thoroughly
    if viewport.nil? || !viewport.respond_to?(:disposed?)
      mp_log("NAME: skipped (nil viewport) id=#{@mp_id}") if defined?(mp_log)
      return
    end
    if viewport.disposed?
      mp_log("NAME: skipped (disposed viewport) id=#{@mp_id}") if defined?(mp_log)
      return
    end

    width  = 160
    height = 36

    begin
      bitmap = Bitmap.new(width, height)

      # Shadow text
      bitmap.font.size  = 16
      bitmap.font.bold  = true
      bitmap.font.color = Color.new(0, 0, 0, 180)
      bitmap.draw_text(1, 1, width, 20, @mp_name.to_s, 1)
      # Main text
      bitmap.font.color = Color.new(255, 255, 255)
      bitmap.draw_text(0, 0, width, 20, @mp_name.to_s, 1)

      # Party display
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

      @name_sprite = Sprite.new(viewport)
      @name_sprite.bitmap = bitmap
      @name_sprite.ox = width / 2
      @name_sprite.oy = height
      @name_sprite.z  = 5000
      @name_valid = true
      @name_viewport = viewport

      mp_log("NAME: created id=#{@mp_id}") if defined?(mp_log)
    rescue => e
      mp_log_exception("NAME: create failed id=#{@mp_id}", e) if defined?(mp_log_exception)
      dispose_name_sprite
    end
  end

  def dispose_name_sprite
    @name_valid = false
    @name_viewport = nil

    if @name_sprite && !@name_sprite.disposed?
      begin
        if @name_sprite.bitmap && !@name_sprite.bitmap.disposed?
          @name_sprite.bitmap.dispose
        end
      rescue
        nil
      end
      begin
        @name_sprite.dispose
      rescue
        nil
      end
    end
    @name_sprite = nil
  rescue => e
    mp_log_exception("NAME: dispose failed id=#{@mp_id}", e) if defined?(mp_log_exception)
    @name_sprite = nil
    @name_valid = false
  end

  def update_name_sprite_position
    return unless @name_valid
    return unless @name_sprite && !@name_sprite.disposed?
    return unless @name_sprite.bitmap && !@name_sprite.bitmap.disposed?

    # Validate viewport every frame — it may have been disposed during
    # map transition.
    vp = @name_sprite.viewport
    if vp && vp.respond_to?(:disposed?) && vp.disposed?
      # Viewport was disposed — kill the name sprite and recreate next frame
      mp_log("NAME: viewport disposed, cleaning up id=#{@mp_id}") if defined?(mp_log)
      dispose_name_sprite
      return
    end

    begin
      @name_sprite.x       = screen_x
      @name_sprite.y       = screen_y - 48
      @name_sprite.visible = !@transparent && @data.visible
    rescue => e
      # Non-fatal: log once then stop trying
      mp_log_exception("NAME: position update id=#{@mp_id}", e) if defined?(mp_log_exception)
      dispose_name_sprite
    end
  end

  def refresh_name_sprite(viewport = nil)
    vp = viewport || @name_viewport
    return if vp && vp.respond_to?(:disposed?) && vp.disposed?
    create_name_sprite(vp)
  end

  # ─── Cleanup ───────────────────────────────────────────────────────────────

  def dispose
    dispose_name_sprite
  rescue => e
    mp_log_exception("MP_Game_RemotePlayer#dispose id=#{@mp_id}", e) if defined?(mp_log_exception)
  end

  # Visibility used by culling
  def visible
    @data.visible
  end

  def visible=(v)
    @data.visible = v
  end

  # bush_depth for sprite integration
  def bush_depth
    0
  end
end

