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
#   * update rescues: bad charset / disposed viewport / plugin conflicts must not
#     freeze or close the game when a second remote player appears.
#===============================================================================

class Sprite_MP_RemotePlayer < Sprite_Character
  # @param viewport [Viewport]            the map's tile viewport
  # @param character [MP_Game_RemotePlayer]
  def initialize(viewport, character)
    if viewport.nil? || (viewport.respond_to?(:disposed?) && viewport.disposed?)
      raise ArgumentError, "Sprite_MP_RemotePlayer: invalid viewport"
    end
    if defined?(mp_log) && (MP_ClientConfig::NETWORK_DIAGNOSTICS rescue false)
      mp_log("SPRITE: create viewport=#{viewport.object_id} char=#{character&.mp_id} graphic=#{character&.character_name}")
    end
    super(viewport, character)
    @mp_character = character
  end

  def update
    return if @character.nil?
    return if disposed?
    super
  rescue => e
    mp_log_exception("Sprite_MP_RemotePlayer#update char=#{@mp_character&.mp_id}", e) if defined?(mp_log_exception)
  end

  def dispose
    char = @mp_character
    @mp_character = nil
    if char&.respond_to?(:dispose)
      begin
        char.dispose
      rescue => e
        mp_log_exception("Sprite_MP_RemotePlayer#dispose (character)", e) if defined?(mp_log_exception)
      end
    end
    super
  rescue => e
    mp_log_exception("Sprite_MP_RemotePlayer#dispose (sprite)", e) if defined?(mp_log_exception)
  end
end
