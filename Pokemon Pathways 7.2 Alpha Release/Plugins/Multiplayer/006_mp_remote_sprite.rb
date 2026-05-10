#===============================================================================
#  Pokemon Pathways Multiplayer Plugin - Remote Player Sprite
#  Sprite_Character subclass for rendering remote players on the map
#===============================================================================

class Sprite_MP_RemotePlayer < Sprite_Character
  def initialize(viewport, character)
    super(viewport, character)
    @remote_player = character
  end

  def update
    return if @character.nil?
    super
    # Ensure the remote player's name sprite stays positioned
    if @remote_player.respond_to?(:update_name_sprite)
      @remote_player.update_name_sprite
    end
  end

  def dispose
    if @remote_player.respond_to?(:dispose_name_sprite)
      @remote_player.dispose_name_sprite
    end
    super
  end
end
