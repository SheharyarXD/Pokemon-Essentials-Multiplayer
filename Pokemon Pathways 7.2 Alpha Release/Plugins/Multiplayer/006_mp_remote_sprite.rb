#===============================================================================
#  Pokemon Pathways Multiplayer Client - Remote Player Sprite
#  STABILIZED v2.1 — Safe Sprite_Character subclass with rescue guards
#
#  Thin subclass of Sprite_Character used by Spriteset_Map render pipeline.
#  Base class handles tile-offset, animation-frame, and z-depth.
#  We add safe dispose and update guards to prevent crashes from stale
#  viewport or missing charset bitmap.
#===============================================================================

class Sprite_MP_RemotePlayer < Sprite_Character
  def initialize(viewport, character)
    @mp_character = character
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
    end
  end

  def update
    return if @character.nil?
    begin
      super
    rescue => e
      mp_log("SPRITE: update error #{e.class}: #{e.message}") if defined?(mp_log)
    end
  end

  def dispose
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

  def create_placeholder_bitmap(viewport)
    begin
      @bitmap = Bitmap.new(32, 48)
      @bitmap.fill_rect(0, 0, 32, 48, Color.new(255, 0, 255, 128))
      self.bitmap = @bitmap if respond_to?(:bitmap=)
    rescue => e
      mp_log("SPRITE: placeholder bitmap failed #{e.class}: #{e.message}") if defined?(mp_log)
    end
  end
end
