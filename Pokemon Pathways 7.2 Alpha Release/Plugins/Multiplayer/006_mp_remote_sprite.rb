#===============================================================================
#  Pokemon Pathways Multiplayer Client - Remote Player Sprite
#
#  Thin subclass of Sprite_Character used by the existing Spriteset_Map
#  render pipeline. The base class handles all tile-offset, animation-frame,
#  and z-depth calculations automatically, so we just need to hook dispose.
#
#  FIXES vs original:
#   * Removed Spriteset_Map.viewport class-method call (doesn't exist in PE v19.1).
#     The viewport is now passed in by MP_OverworldManager which holds a reference.
#   * dispose now calls MP_Game_RemotePlayer#dispose to clean up the name sprite.
#===============================================================================

class Sprite_MP_RemotePlayer < Sprite_Character
  # @param viewport [Viewport]            the map's tile viewport
  # @param character [MP_Game_RemotePlayer]
  def initialize(viewport, character)
    super(viewport, character)
    @mp_character = character
  end

  def update
    return if @character.nil?
    super
    # Name sprite position is updated inside MP_Game_RemotePlayer#update
    # via update_name_sprite_position, so nothing extra needed here.
  rescue => e
    # Prevent a sprite update crash from killing the whole spriteset update loop
    mp_log("SPRITE: update error #{e.class}: #{e.message}") if defined?(mp_log)
  end

  def dispose
    # Dispose the character's name sprite first (must happen on main thread)
    @mp_character.dispose if @mp_character.respond_to?(:dispose)
    super
  end
end
