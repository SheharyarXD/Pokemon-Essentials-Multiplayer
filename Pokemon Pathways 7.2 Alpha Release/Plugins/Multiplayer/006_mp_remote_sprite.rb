#===============================================================================
#  Pokemon Pathways Multiplayer Client - Remote Player Sprite
<<<<<<< HEAD
#  REMOTE SKIN SYNC v3.1 — CRITICAL FIX: Never bypass super() in MKXP-Z
#
#  MKXP-Z REQUIRES that super() be called in Sprite_Character#initialize
#  to allocate internal C-level instance data. Bypassing super() causes:
#    "No instance data for variable (missing call to super?)"
#
#  Strategy:
#    1. ALWAYS call super() first — wrap in rescue
#    2. If super() raises NoMethodError (character incompatibility),
#       we CANNOT use this as a Sprite_Character. Instead, create a
#       plain Sprite and draw a placeholder bitmap.
#    3. Never return early from initialize without super() — that is
#       guaranteed to crash MKXP-Z when any method is called later.
=======
#  STABILIZED v2.1 — Safe Sprite_Character subclass with rescue guards
#
#  Thin subclass of Sprite_Character used by Spriteset_Map render pipeline.
#  Base class handles tile-offset, animation-frame, and z-depth.
#  We add safe dispose and update guards to prevent crashes from stale
#  viewport or missing charset bitmap.
>>>>>>> aada347da767172eb53ec24119bd43fe6fa1c095
#===============================================================================

class Sprite_MP_RemotePlayer < Sprite_Character
  def initialize(viewport, character)
    @mp_character = character
<<<<<<< HEAD
    @mp_is_placeholder = false
    @mp_safe_init = false

    # CRITICAL: Always attempt super() first. MKXP-Z allocates C structs here.
    begin
      super(viewport, character)
      @mp_safe_init = true
      mp_log("SPRITE: Sprite_MP_RemotePlayer created for #{character.name}") if MP_ClientConfig::DEBUG_SPRITES && defined?(mp_log)
    rescue NoMethodError => e
      # Sprite_Character tried to call a missing method on the character.
      # We cannot use Sprite_Character without super(), so create a plain Sprite.
      mp_log("SPRITE: super() NoMethodError for #{character.mp_name rescue '??'} — #{e.message}") if defined?(mp_log)
      init_as_plain_sprite(viewport, character)
    rescue => e
      mp_log("SPRITE: super() error #{e.class}: #{e.message} — using plain Sprite fallback") if defined?(mp_log)
      init_as_plain_sprite(viewport, character)
=======
    @mp_safe_init = false
    begin
      super(viewport, character)
      @mp_safe_init = true
      mp_log("SPRITE: Sprite_MP_RemotePlayer created for #{character.mp_name}") if MP_ClientConfig::DEBUG_SPRITES && defined?(mp_log)
    rescue => e
      mp_log("SPRITE: init error #{e.class}: #{e.message} — using placeholder") if defined?(mp_log)
      @character = character
      @viewport  = viewport
      @mp_safe_init = false
      create_placeholder_bitmap(viewport)
>>>>>>> aada347da767172eb53ec24119bd43fe6fa1c095
    end
  end

  def update
<<<<<<< HEAD
    if @mp_is_placeholder
      update_placeholder
      return
    end
=======
>>>>>>> aada347da767172eb53ec24119bd43fe6fa1c095
    return if @character.nil?
    begin
      super
    rescue => e
      mp_log("SPRITE: update error #{e.class}: #{e.message}") if defined?(mp_log)
    end
  end

  def dispose
<<<<<<< HEAD
    if @mp_is_placeholder
      begin; super; rescue; end
      return
    end
=======
>>>>>>> aada347da767172eb53ec24119bd43fe6fa1c095
    begin
      @mp_character.dispose if @mp_character.respond_to?(:dispose)
    rescue => e
      mp_log("SPRITE: dispose character error #{e.class}: #{e.message}") if defined?(mp_log)
    end
    begin
      super
    rescue => e
      mp_log("SPRITE: dispose super error #{e.class}: #{e.message}") if defined?(mp_log)
    end
  end

  private

<<<<<<< HEAD
  # When Sprite_Character super() fails, we create a plain Sprite with
  # a placeholder bitmap. This avoids the MKXP-Z "missing call to super?"
  # crash because we NEVER leave the object partially constructed.
  def init_as_plain_sprite(viewport, character)
    @mp_is_placeholder = true
    @mp_character = character

    # Call Sprite's initialize (NOT Sprite_Character's) to get valid C data
    begin
      Sprite.instance_method(:initialize).bind(self).call(viewport)
    rescue => e
      mp_log("SPRITE: plain Sprite init failed #{e.class}: #{e.message}") if defined?(mp_log)
    end

    create_placeholder_bitmap
    self.visible = true
    self.z = 100

    mp_log("SPRITE: plain Sprite placeholder created for #{character.mp_name rescue '??'}") if defined?(mp_log)
  end

  def create_placeholder_bitmap
    begin
      @bitmap = Bitmap.new(32, 48)
      @bitmap.fill_rect(0, 0, 32, 48, Color.new(255, 0, 255, 128))
      self.bitmap = @bitmap
=======
  def create_placeholder_bitmap(viewport)
    begin
      @bitmap = Bitmap.new(32, 48)
      @bitmap.fill_rect(0, 0, 32, 48, Color.new(255, 0, 255, 128))
      self.bitmap = @bitmap if respond_to?(:bitmap=)
>>>>>>> aada347da767172eb53ec24119bd43fe6fa1c095
    rescue => e
      mp_log("SPRITE: placeholder bitmap failed #{e.class}: #{e.message}") if defined?(mp_log)
    end
  end
<<<<<<< HEAD

  def update_placeholder
    return unless @mp_character
    begin
      self.x = @mp_character.screen_x rescue 0
      self.y = @mp_character.screen_y rescue 0
      self.z = @mp_character.screen_z rescue 100
      self.opacity = @mp_character.opacity rescue 255
      self.visible = !(@mp_character.transparent rescue false)
    rescue => e
      mp_log("SPRITE: placeholder update error #{e.class}: #{e.message}") if defined?(mp_log)
    end
  end
=======
>>>>>>> aada347da767172eb53ec24119bd43fe6fa1c095
end
