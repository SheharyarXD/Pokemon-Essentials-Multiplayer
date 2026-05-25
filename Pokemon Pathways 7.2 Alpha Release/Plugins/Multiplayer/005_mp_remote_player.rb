#===============================================================================
#  Pokemon Pathways Multiplayer Client - Remote Player Character
#  REMOTE SKIN SYNC v3.1 — MKXP-Z compatibility: expose ALL methods
#  Sprite_Character expects, including step_anime READER.
#
#  CRITICAL FIX: Game_Character in PE v19.1 has @step_anime as an
#  instance variable but may NOT expose a reader method. Sprite_Character
#  calls character.step_anime directly. We must add explicit readers
#  for every field Sprite_Character touches.
#===============================================================================

class MP_Game_RemotePlayer < Game_Character
  attr_reader   :mp_id, :mp_name, :data
  attr_accessor :mp_sprite

  # Sprite_Character compatibility shims — MKXP-Z may check these directly
  def name; @mp_name; end
  def id; 0; end
  def erased?; false; end

  # Explicit readers so Sprite_Character can access them
  def character_name; @character_name; end
  def character_hue; @character_hue; end

  # CRITICAL: Sprite_Character reads these directly from the character object
  # PE v19.1 Game_Character uses attr_accessor but MKXP-Z may not see them
  # properly due to C-extension class loading order. We add explicit methods.
  def step_anime; @step_anime; end
  def walk_anime; @walk_anime; end
  def pattern; @pattern; end
  def original_pattern; @original_pattern; end
  def original_direction; @original_direction; end
  def stop_count; @stop_count; end
  def jump_count; @jump_count; end
  def jump_peak; @jump_peak; end
  def move_frequency; @move_frequency; end
  def anime_count; @anime_count; end
  def blend_type; @blend_type; end

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
    @pattern        = 0
    @original_pattern = 0
    @original_direction = data.direction
    @stop_count     = 0
    @jump_count     = 0
    @jump_peak      = 0
    @move_frequency = 6
    @anime_count    = 0
    @blend_type     = 0

    @x          = data.x
    @y          = data.y
    @real_x     = data.real_x.to_i
    @real_y     = data.real_y.to_i
    @direction  = data.direction

    @character_name = data.sprite_name.to_s
    @character_hue  = data.character_hue.to_i
    set_character_graphic(data.sprite_name, data.character_hue)

    @name_sprite    = nil
    @name_viewport  = nil
  end

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

  def set_character_graphic(name, hue = 0)
    n = name.to_s.strip
    h = hue.to_i

    mp_log("SPRITE: set_character_graphic called '#{n}' (hue:#{h}) for #{@mp_name}") if defined?(mp_log)

    if n.empty? || n =~ /^\d+$/
      n = resolve_trainer_charset
    end

    if n.empty?
      mp_log("SPRITE: fallback placeholder used for #{@mp_name} (no valid charset)") if defined?(mp_log)
      n = "trainer_POKEMONTRAINER_Red"
    end

    @character_name = n
    @character_hue  = h
    @data.sprite_name = n if @data
    @data.character_hue = h if @data

    mp_log("SPRITE: applying charset '#{@character_name}' (hue:#{@character_hue}) for #{@mp_name}") if defined?(mp_log)
  end

  def resolve_trainer_charset
    trainer_type = @data.trainer_type.to_s rescue ""
    outfit = @data.outfit.to_i rescue 0

    mp_log("SPRITE: resolving charset for #{@mp_name} (type:#{trainer_type}, outfit:#{outfit})") if defined?(mp_log)

    if !trainer_type.empty?
      candidates = [
        "trainer_#{trainer_type}",
        "trchar_#{trainer_type}",
        trainer_type.to_s
      ]
      candidates.each do |c|
        if charset_file_exists?(c)
          mp_log("SPRITE: resolved '#{c}' from trainer_type") if defined?(mp_log)
          return c
        end
      end
    end

    case outfit
    when 0; "trainer_POKEMONTRAINER_Red"
    when 1; "trainer_POKEMONTRAINER_Leaf"
    when 2; "trainer_POKEMONTRAINER_Brendan"
    when 3; "trainer_POKEMONTRAINER_May"
    else;   "trainer_POKEMONTRAINER_Red"
    end
  end

  def charset_file_exists?(name)
    return false if name.nil? || name.empty?
    paths = [
      "Graphics/Characters/#{name}.png",
      "Graphics/Characters/#{name}.jpg",
      "Graphics/Characters/#{name}.bmp",
      "Graphics/Characters/#{name}.gif",
      "Graphics/Characters/#{name}"
    ]
    paths.any? { |p| FileTest.exist?(p) }
  rescue => e
    false
  end

  def safe_character_name; @character_name.to_s; end
  def safe_character_hue; @character_hue.to_i; end

  def set_direction(dir)
    @direction = dir.to_i
    @original_direction = @direction
    @stop_count = 0
    @data.direction = @direction
  end

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

  def dispose
    dispose_name_sprite
  end
end
