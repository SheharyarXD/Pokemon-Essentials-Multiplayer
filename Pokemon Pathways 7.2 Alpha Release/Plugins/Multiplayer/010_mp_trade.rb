#===============================================================================
#  Pokemon Pathways Multiplayer Plugin - Trade Integration
#  Extends UI_Trading flow for network trades
#  Sends TRADE_REQUEST, handles TRADE_OPEN/OFFER/CONFIRM/COMPLETE
#===============================================================================

module MP_TradeManager
  module_function

  @in_trade = false
  @trade_session_id = nil
  @trade_partner = nil
  @offered_pokemon = nil
  @partner_offer = nil
  @confirmed = false
  @initialized = false

  def init
    return if @initialized
    @initialized = true
    register_packet_handlers
  end

  def register_packet_handlers
    MP_NetworkManager.on_packet(MP_PacketType::TRADE_REQUEST) do |payload|
      handle_trade_request(payload)
    end

    MP_NetworkManager.on_packet(MP_PacketType::TRADE_OPEN) do |payload|
      handle_trade_open(payload)
    end

    MP_NetworkManager.on_packet(MP_PacketType::TRADE_OFFER) do |payload|
      handle_trade_offer(payload)
    end

    MP_NetworkManager.on_packet(MP_PacketType::TRADE_CONFIRM) do |payload|
      handle_trade_confirm(payload)
    end

    MP_NetworkManager.on_packet(MP_PacketType::TRADE_COMPLETE) do |payload|
      handle_trade_complete(payload)
    end

    MP_NetworkManager.on_packet(MP_PacketType::TRADE_CANCEL) do |payload|
      handle_trade_cancel(payload)
    end
  end

  def request_trade(target_name)
    return unless MP_NetworkManager.connected?
    MP_NetworkManager.send_packet(MP_PacketType::TRADE_REQUEST, {
      target_name: target_name
    })
    echoln "[MP][Trade] Sent trade request to #{target_name}"
  end

  def accept_trade(session_id)
    return unless MP_NetworkManager.connected?
    MP_NetworkManager.send_packet(MP_PacketType::TRADE_ACCEPT, {
      session_id: session_id
    })
  end

  def decline_trade(session_id)
    return unless MP_NetworkManager.connected?
    MP_NetworkManager.send_packet(MP_PacketType::TRADE_DECLINE, {
      session_id: session_id
    })
    reset_trade_state
  end

  def offer_pokemon(party_index)
    return unless MP_NetworkManager.connected? && @in_trade
    return unless $Trainer && $Trainer.party[party_index]

    pkmn = $Trainer.party[party_index]

    # Don't allow eggs
    if pkmn.egg?
      pbMessage(_INTL("You cannot trade Eggs!"))
      return
    end

    @offered_pokemon = pkmn
    @confirmed = false

    pokemon_data = serialize_pokemon(pkmn)
    MP_NetworkManager.send_packet(MP_PacketType::TRADE_OFFER, {
      session_id: @trade_session_id,
      pokemon: pokemon_data
    })

    echoln "[MP][Trade] Offered #{pkmn.name} (Lv.#{pkmn.level})"
  end

  def confirm_trade
    return unless MP_NetworkManager.connected? && @in_trade
    return unless @offered_pokemon

    @confirmed = true
    MP_NetworkManager.send_packet(MP_PacketType::TRADE_CONFIRM, {
      session_id: @trade_session_id
    })

    echoln "[MP][Trade] Confirmed trade"
  end

  def cancel_trade
    return unless MP_NetworkManager.connected? && @in_trade
    MP_NetworkManager.send_packet(MP_PacketType::TRADE_CANCEL, {
      session_id: @trade_session_id
    })
    reset_trade_state
  end

  def handle_trade_request(payload)
    from_name = payload["from_name"]
    session_id = payload["session_id"]

    echoln "[MP][Trade] Trade request from #{from_name}"

    result = pbMessage(_INTL("{1} wants to trade! Accept?", from_name),
                       [_INTL("Accept"), _INTL("Decline")], -1)

    if result == 0
      accept_trade(session_id)
    else
      decline_trade(session_id)
    end
  end

  def handle_trade_open(payload)
    session_id = payload["session_id"]
    player_a = payload["player_a"]
    player_b = payload["player_b"]
    timeout = payload["timeout"]

    @trade_session_id = session_id
    @in_trade = true
    @trade_partner = ($Trainer.name == player_a) ? player_b : player_a
    @offered_pokemon = nil
    @partner_offer = nil
    @confirmed = false

    echoln "[MP][Trade] Trade window opened with #{@trade_partner}"

    # Open trade UI
    open_trade_ui
  end

  def open_trade_ui
    # Show party selection for trade
    pbFadeOutIn(99999) {
      scene = PokemonParty_Scene.new
      screen = PokemonPartyScreen.new(scene, $Trainer.party)
      screen.pbStartScene(_INTL("Choose a Pokemon to trade with #{@trade_partner}"), false)

      loop do
        screen.pbSetHelpText(_INTL("Choose a Pokemon."))
        pokemon_index = screen.pbChoosePokemon

        if pokemon_index < 0
          # Cancelled
          cancel_trade
          screen.pbEndScene
          break
        end

        pkmn = $Trainer.party[pokemon_index]
        if pkmn.egg?
          pbMessage(_INTL("You cannot trade Eggs!"))
          next
        end

        # Offer this Pokemon
        offer_pokemon(pokemon_index)

        # Show confirmation
        commands = [_INTL("Confirm"), _INTL("Change"), _INTL("Cancel")]
        cmd = pbMessage(_INTL("Offer {1} (Lv.{2})?", pkmn.name, pkmn.level), commands, -1)

        case cmd
        when 0
          confirm_trade
          screen.pbEndScene
          break
        when 2
          cancel_trade
          screen.pbEndScene
          break
        end
      end
    }
  end

  def handle_trade_offer(payload)
    session_id = payload["session_id"]
    offer_a = payload["offer_a"]
    offer_b = payload["offer_b"]

    return unless @trade_session_id == session_id

    # Get the partner's offer (whichever is not ours)
    @partner_offer = ($Trainer.name == payload["offer_a"]&.[]("owner")) ? offer_b : offer_a

    if @partner_offer
      species = @partner_offer["species"] || @partner_offer[:species]
      level = @partner_offer["level"] || @partner_offer[:level]
      echoln "[MP][Trade] Partner offers: #{species} Lv.#{level}"
    end
  end

  def handle_trade_confirm(payload)
    session_id = payload["session_id"]
    confirmed_a = payload["confirmed_a"]
    confirmed_b = payload["confirmed_b"]

    return unless @trade_session_id == session_id

    if confirmed_a && confirmed_b
      pbMessage(_INTL("Both players confirmed! Completing trade..."))
    elsif confirmed_a || confirmed_b
      pbMessage(_INTL("Waiting for your partner to confirm...")) unless @confirmed
    end
  end

  def handle_trade_complete(payload)
    session_id = payload["session_id"]
    received_data = payload["received_pokemon"]

    return unless @trade_session_id == session_id

    echoln "[MP][Trade] Trade completed!"

    if received_data
      species = received_data["species"] || received_data[:species]
      level = received_data["level"] || received_data[:level]
      name = received_data["name"] || received_data[:name] || species

      # Create the received Pokemon
      begin
        new_pokemon = Pokemon.new(species.to_sym, level.to_i)
        new_pokemon.name = name if name
        new_pokemon.obtain_method = 2 # traded
        if @trade_partner
          new_pokemon.owner = Pokemon::Owner.new_foreign(@trade_partner, 0)
        end

        # Find the offered Pokemon and replace it
        if @offered_pokemon
          party_index = $Trainer.party.index(@offered_pokemon)
          if party_index
            old_pokemon = $Trainer.party[party_index]
            $Trainer.party[party_index] = new_pokemon

            # Show trade animation
            pbFadeOutInWithMusic {
              trade_scene = PokemonTrade_Scene.new
              trade_scene.pbStartScreen(old_pokemon, new_pokemon,
                                        $Trainer.name, @trade_partner || "Trainer")
              trade_scene.pbTrade
              trade_scene.pbEndScreen
            }

            $Trainer.pokedex.register(new_pokemon)
            $Trainer.pokedex.set_owned(new_pokemon.species)

            pbMessage(_INTL("Trade complete! Received {1} (Lv.{2})!", new_pokemon.name, new_pokemon.level))
          end
        end
      rescue => e
        echoln "[MP][Trade] Error creating received Pokemon: #{e.class}: #{e.message}"
        pbMessage(_INTL("Trade completed!"))
      end
    end

    reset_trade_state
  end

  def handle_trade_cancel(payload)
    session_id = payload["session_id"]
    reason = payload["reason"]
    message = payload["message"]

    if @trade_session_id == session_id
      pbMessage(message || _INTL("The trade was cancelled."))
      reset_trade_state
    end
  end

  def reset_trade_state
    @in_trade = false
    @trade_session_id = nil
    @trade_partner = nil
    @offered_pokemon = nil
    @partner_offer = nil
    @confirmed = false
  end

  def serialize_pokemon(pkmn)
    {
      species: pkmn.species.to_s,
      level: pkmn.level,
      name: pkmn.name,
      gender: pkmn.gender,
      shiny: pkmn.shiny?,
      form: pkmn.form,
      egg: pkmn.egg?,
      owner: $Trainer.name
    }
  end

  def in_trade?
    @in_trade
  end

  def trade_session_id
    @trade_session_id
  end

  def trade_partner
    @trade_partner
  end

  def offered_pokemon
    @offered_pokemon
  end

  def partner_offer
    @partner_offer
  end
end

# Initialize when plugin loads
MP_TradeManager.init
