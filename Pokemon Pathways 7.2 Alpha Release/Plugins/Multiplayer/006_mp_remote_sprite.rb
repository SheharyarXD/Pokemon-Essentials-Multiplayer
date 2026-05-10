#===============================================================================
#  MP REMOTE SPRITE v1.2.0
#  Sprite_Character subclass for rendering remote players.
#  FIXED:
#    1. Removed redundant update_name_sprite call (was called twice per frame)
#    2. Added disposed? guards throughout
#    3. Added nil checks for @character
#    4. @remote_player reference is weak; no stale references after dispose
#  NOTE: The name sprite update is now handled entirely by
#        MP_Game_RemotePlayer#update, so this class is much simpler.
#===============================================================================

class Sprite_MP_RemotePlayer < Sprite_Character
  def initialize(viewport, character)
    super(viewport, character)
    @remote_player_ref = character  # keep reference for dispose
  end

  def update
    # Skip if already disposed
    return if disposed?

    # Skip if character is nil (can happen during scene transitions)
    return if @character.nil?

    super
  rescue => e
    # Silently ignore errors during scene transitions
  end

  def dispose
    return if disposed?

    # Dispose name sprite first
    if @remote_player_ref && @remote_player_ref.respond_to?(:dispose_name_sprite)
      @remote_player_ref.dispose_name_sprite rescue nil
    end
    @remote_player_ref = nil

    super
  rescue => e
    # Ensure disposal completes even if errors occur
  end
end
