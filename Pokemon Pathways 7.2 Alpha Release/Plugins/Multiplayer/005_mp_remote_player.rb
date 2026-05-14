#===============================================================================
#  Pokemon Pathways Multiplayer Client - Remote Player Character
#  STABILIZED v2.1 — Safe sprite creation, placeholder bitmap fallback
#
#  Subclass of Game_Character that the existing Spriteset_Map can render.
#  Reads position from RemotePlayerData and applies smoothed interpolation.
#  All Sprite/Bitmap creation happens on main thread via create_name_sprite.
#===============================================================================

class MP_Game_RemotePlayer < Game_Character
  attr_reader   :mp_id, :mp_name, :data
  attr_accessor :mp_sprite

  def initialize(data)
    super()
    @data    = data
    @mp_id   = data.id
    @mp_name = data.name

    @through        = true
    @walk_anime     = true
    @step_anime     = false
    @transparent    = false
    @opacity        = 255
    @move_speed     = 4

    @x          = data.x
    @y          = data.y
    @real_x     = data.real_x.to_i
    @real_y     = data.real_y.to_i
    @direction  = data.direction
    @original_direction = data.direction

    set_character_graphic(data.sprite_name)

    @pattern      ||= 0
    @original_direction ||= @direction

    @name_sprite    = nil
    @name_viewport  = nil
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
      @pattern = (@pattern + 1) % 4 if Graphics.frame_count % 8 == 0
    end

    update_name_sprite_position
    super
  end

  # ─── Appearance setters ────────────────────────────────────────────────────

  def set_character_graphic(name)
    return if name.nil?
    n = name.to_s.strip

    # Server sends sprite index as "0", "1", "2" etc. — these are NOT valid charset names.
    # Map them to proper trainer overworld sprites.
    if n.empty? || n =~ /^\d+$/
      n = resolve_trainer_charset
    end

    # If still invalid, use the user's specified default
    if n.empty? || n =~ /^\d+$/
      n = "trainer_POKEMONTRAINER_Red"
    end

    @character_name = n
    @character_hue  = 0
    mp_log("SPRITE: set character graphic to '#{@character_name}' for #{@mp_name}") if defined?(mp_log)
  end

  # Resolve trainer charset from server sprite index or local player data.
  # Server sends outfit index (0,1,2...) which maps to different trainer sprites.
  def resolve_trainer_charset
    # Try to use the local player's charset as a reference
    if $game_player && $game_player.character_name && !$game_player.character_name.empty?
      return $game_player.character_name
    end

    # Default trainer overworld sprites based on outfit index
    outfit = @data.outfit.to_i
    case outfit
    when 0
      "trainer_POKEMONTRAINER_Red"
    when 1
      "trainer_POKEMONTRAINER_Leaf"
    when 2
      "trainer_POKEMONTRAINER_Brendan"
    when 3
      "trainer_POKEMONTRAINER_May"
    else
      "trainer_POKEMONTRAINER_Red"
    end
  end

  def set_direction(dir)
    @direction = dir.to_i
    @original_direction = @direction
    @stop_count = 0
    @data.direction = @direction
  end

  # ─── Name sprite ───────────────────────────────────────────────────────────

  def create_name_sprite(viewport = nil)
    dispose_name_sprite
    return unless @mp_name

    width  = 160
    height = 36

    begin
      bitmap = Bitmap.new(width, height)
    rescue => e
      mp_log("SPRITE: Bitmap.new failed #{e.class}: #{e.message}") if defined?(mp_log)
      return
    end

    bitmap.font.size  = 16
    bitmap.font.bold  = true
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

    begin
      @name_sprite = Sprite.new(viewport)
      @name_sprite.bitmap = bitmap
      @name_sprite.ox = width / 2
      @name_sprite.oy = height
      @name_sprite.z  = 5000
      mp_log("SPRITE: name sprite created for #{@mp_name}") if MP_ClientConfig::DEBUG_SPRITES && defined?(mp_log)
    rescue => e
      mp_log("SPRITE: Sprite.new failed #{e.class}: #{e.message}") if defined?(mp_log)
      bitmap.dispose rescue nil
    end
  end

  def dispose_name_sprite
    if @name_sprite && !@name_sprite.disposed?
      @name_sprite.bitmap.dispose if @name_sprite.bitmap && !@name_sprite.bitmap.disposed?
      @name_sprite.dispose
      mp_log("SPRITE: name sprite disposed for #{@mp_name}") if MP_ClientConfig::DEBUG_SPRITES && defined?(mp_log)
    end
    @name_sprite = nil
  end

  def update_name_sprite_position
    return unless @name_sprite && !@name_sprite.disposed?
    return if @name_sprite.viewport && @name_sprite.viewport.disposed? rescue false
    @name_sprite.x       = screen_x
    @name_sprite.y       = screen_y - 48
    @name_sprite.visible = !@transparent && @data.visible
  end

  def refresh_name_sprite(viewport = nil)
    vp = (viewport || (@name_sprite&.viewport))
    create_name_sprite(vp)
  end

  # ─── Cleanup ───────────────────────────────────────────────────────────────

  def dispose
    dispose_name_sprite
  end
end
