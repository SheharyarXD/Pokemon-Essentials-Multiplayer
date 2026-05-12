#===============================================================================
#  Pokemon Pathways Multiplayer Client - Trade Integration (STABLE v2.1)
#
#  FIXES v2.1:
#   * All packet handlers wrapped in begin/rescue
#   * Pokemon creation guarded with species validation
#   * UI operations (pbFadeOutIn) wrapped in rescue
#   * Trade scene cleanup on failure paths
#   * String coercion on all payload accesses to prevent nil crashes
#===============================================================================

module MP_TradeManager
  module_function

  @in_trade          = false
  @trade_session_id  = nil
  @trade_partner     = nil
  @am_player_a       = nil
  @offered_pokemon   = nil
  @partner_offer     = nil
  @my_confirmed      = false
  @partner_confirmed = false
  @initialized       = false

  @pending_request   = nil
  @open_trade_ui     = false

  def init
    return if @initialized
    @initialized = true
    register_packet_handlers
    mp_log("TRADE: initialized v2.1") if defined?(mp_log)
  end

  def update
    begin
      handle_pending_request
      handle_pending_ui
    rescue => e
      mp_log_exception("TRADE: update", e) if defined?(mp_log_exception)
      reset_trade_state
    end
  end

  def in_trade?;         @in_trade;          end
  def trade_session_id;  @trade_session_id;  end
  def trade_partner;     @trade_partner;     end
  def offered_pokemon;   @offered_pokemon;   end
  def partner_offer;     @partner_offer;     end

  def request_trade(target_name)
    return unless MP_NetworkManager.connected?
    MP_NetworkManager.send_packet(MP_PacketType::TRADE_REQUEST, {
      "target_name" => target_name.to_s
    })
    mp_log("TRADE: requested with #{target_name}") if defined?(mp_log)
  end

  def accept_trade(session_id)
    return unless MP_NetworkManager.connected?
    MP_NetworkManager.send_packet(MP_PacketType::TRADE_ACCEPT, { "session_id" => session_id.to_s })
  end

  def decline_trade(session_id)
    return unless MP_NetworkManager.connected?
    MP_NetworkManager.send_packet(MP_PacketType::TRADE_DECLINE, { "session_id" => session_id.to_s })
    reset_trade_state
  end

  def offer_pokemon(party_index)
    return unless @in_trade && $Trainer
    idx = party_index.to_i
    pkmn = $Trainer.party[idx]
    return unless pkmn

    if pkmn.egg?
      pbMessage(_INTL("You cannot trade Eggs!"))
      return
    end

    @offered_pokemon  = pkmn
    @my_confirmed     = false
    @partner_confirmed= false

    MP_NetworkManager.send_packet(MP_PacketType::TRADE_OFFER, {
      "session_id" => @trade_session_id,
      "pokemon"    => serialize_pokemon(pkmn)
    })
    mp_log("TRADE: offered #{pkmn.name} Lv.#{pkmn.level}") if defined?(mp_log)
  rescue => e
    mp_log_exception("TRADE: offer_pokemon", e) if defined?(mp_log_exception)
  end

  def confirm_trade
    return unless @in_trade && @offered_pokemon
    @my_confirmed = true
    MP_NetworkManager.send_packet(MP_PacketType::TRADE_CONFIRM, {
      "session_id" => @trade_session_id
    })
    mp_log("TRADE: confirmed") if defined?(mp_log)
  rescue => e
    mp_log_exception("TRADE: confirm", e) if defined?(mp_log_exception)
  end

  def cancel_trade
    return unless @in_trade
    MP_NetworkManager.send_packet(MP_PacketType::TRADE_CANCEL, {
      "session_id" => @trade_session_id
    })
    reset_trade_state
  rescue => e
    mp_log_exception("TRADE: cancel", e) if defined?(mp_log_exception)
    reset_trade_state
  end

  private

  def register_packet_handlers
    MP_NetworkManager.on_packet(MP_PacketType::TRADE_REQUEST) do |payload|
      begin
        @pending_request = {
          from_name:  payload["from_name"].to_s,
          session_id: payload["session_id"].to_s
        }
      rescue => e
        mp_log_exception("TRADE: TRADE_REQUEST handler", e) if defined?(mp_log_exception)
      end
    end

    MP_NetworkManager.on_packet(MP_PacketType::TRADE_OPEN) do |payload|
      begin
        @trade_session_id  = payload["session_id"].to_s
        @in_trade          = true
        @am_player_a       = ($Trainer&.name == payload["player_a"])
        @trade_partner     = @am_player_a ? payload["player_b"].to_s : payload["player_a"].to_s
        @offered_pokemon   = nil
        @partner_offer     = nil
        @my_confirmed      = false
        @partner_confirmed = false
        @open_trade_ui     = true
        mp_log("TRADE: opened with #{@trade_partner} (#{@am_player_a ? 'A' : 'B'})") if defined?(mp_log)
      rescue => e
        mp_log_exception("TRADE: TRADE_OPEN handler", e) if defined?(mp_log_exception)
        reset_trade_state
      end
    end

    MP_NetworkManager.on_packet(MP_PacketType::TRADE_OFFER) do |payload|
      begin
        next unless @trade_session_id == payload["session_id"]
        offer_a = payload["offer_a"] || {}
        offer_b = payload["offer_b"] || {}
        our_offer    = @am_player_a ? offer_a : offer_b
        their_offer  = @am_player_a ? offer_b : offer_a
        @partner_offer = their_offer
        @my_confirmed      = false
        @partner_confirmed = false
        if their_offer
          sp = their_offer["species"]; lv = their_offer["level"]
          mp_log("TRADE: partner offers #{sp} Lv.#{lv}") if defined?(mp_log)
        end
      rescue => e
        mp_log_exception("TRADE: TRADE_OFFER handler", e) if defined?(mp_log_exception)
      end
    end

    MP_NetworkManager.on_packet(MP_PacketType::TRADE_CONFIRM) do |payload|
      begin
        next unless @trade_session_id == payload["session_id"]
        if @am_player_a
          @my_confirmed      = !!payload["confirmed_a"]
          @partner_confirmed = !!payload["confirmed_b"]
        else
          @my_confirmed      = !!payload["confirmed_b"]
          @partner_confirmed = !!payload["confirmed_a"]
        end
        if @partner_confirmed && !@my_confirmed
          pbMessage(_INTL("Your partner confirmed! Confirm to complete the trade.")) rescue nil
        elsif @my_confirmed && @partner_confirmed
          pbMessage(_INTL("Both players confirmed! Completing trade...")) rescue nil
        end
      rescue => e
        mp_log_exception("TRADE: TRADE_CONFIRM handler", e) if defined?(mp_log_exception)
      end
    end

    MP_NetworkManager.on_packet(MP_PacketType::TRADE_COMPLETE) do |payload|
      begin
        next unless @trade_session_id == payload["session_id"]
        received_data = payload["received_pokemon"]
        execute_trade_complete(received_data)
      rescue => e
        mp_log_exception("TRADE: TRADE_COMPLETE handler", e) if defined?(mp_log_exception)
        reset_trade_state
      end
    end

    MP_NetworkManager.on_packet(MP_PacketType::TRADE_CANCEL) do |payload|
      begin
        next unless @trade_session_id == payload["session_id"]
        msg = payload["message"] || _INTL("The trade was cancelled.")
        pbMessage(msg.to_s) rescue nil
        reset_trade_state
        mp_log("TRADE: cancelled (#{payload['reason']})") if defined?(mp_log)
      rescue => e
        mp_log_exception("TRADE: TRADE_CANCEL handler", e) if defined?(mp_log_exception)
        reset_trade_state
      end
    end
  end

  def handle_pending_request
    return unless @pending_request
    req = @pending_request
    @pending_request = nil

    result = pbMessage(
      _INTL("{1} wants to trade! Accept?", req[:from_name]),
      [_INTL("Accept"), _INTL("Decline")],
      -1
    ) rescue 1

    result == 0 ? accept_trade(req[:session_id]) : decline_trade(req[:session_id])
  rescue => e
    mp_log_exception("TRADE: handle_pending_request", e) if defined?(mp_log_exception)
  end

  def handle_pending_ui
    return unless @open_trade_ui && @in_trade
    @open_trade_ui = false
    open_trade_ui
  rescue => e
    mp_log_exception("TRADE: handle_pending_ui", e) if defined?(mp_log_exception)
    reset_trade_state
  end

  def open_trade_ui
    pbFadeOutIn(99999) {
      scene  = PokemonParty_Scene.new
      screen = PokemonPartyScreen.new(scene, $Trainer.party)
      screen.pbStartScene(_INTL("Choose a Pokemon to trade with #{@trade_partner}"), false)

      loop do
        screen.pbSetHelpText(_INTL("Choose a Pokemon."))
        idx = screen.pbChoosePokemon

        if idx < 0
          cancel_trade
          break
        end

        pkmn = $Trainer.party[idx]
        if pkmn.egg?
          pbMessage(_INTL("You cannot trade Eggs!"))
          next
        end

        offer_pokemon(idx)

        cmd = pbMessage(
          _INTL("Offer {1} (Lv.{2})?", pkmn.name, pkmn.level),
          [_INTL("Confirm"), _INTL("Change"), _INTL("Cancel")],
          -1
        )

        case cmd
        when 0
          confirm_trade
          break
        when 2
          cancel_trade
          break
        end
      end

      screen.pbEndScene
    }
  rescue => e
    mp_log_exception("TRADE: open_trade_ui", e) if defined?(mp_log_exception)
    reset_trade_state
  end

  def execute_trade_complete(received_data)
    mp_log("TRADE: complete! received=#{received_data&.inspect}") if defined?(mp_log)

    if received_data && @offered_pokemon
      species_str = received_data["species"].to_s
      level_int   = received_data["level"].to_i
      name_str    = received_data["name"] || species_str

      sym = species_str.upcase.to_sym
      valid_species = nil
      begin
        valid_species = GameData::Species.exists?(sym) ? sym : nil
      rescue
        valid_species = sym
      end

      if valid_species && level_int > 0
        begin
          new_pkmn = Pokemon.new(valid_species, level_int)
          new_pkmn.name = name_str.to_s
          new_pkmn.obtain_method = 2 if new_pkmn.respond_to?(:obtain_method=)
          begin
            new_pkmn.owner = Pokemon::Owner.new_foreign(@trade_partner.to_s, 0)
          rescue
            nil
          end

          party_index = $Trainer.party.index(@offered_pokemon)
          if party_index
            old_pkmn = $Trainer.party[party_index]
            $Trainer.party[party_index] = new_pkmn

            begin
              pbFadeOutInWithMusic {
                trade_scene = PokemonTrade_Scene.new
                trade_scene.pbStartScreen(old_pkmn, new_pkmn, $Trainer.name, @trade_partner || "Trainer")
                trade_scene.pbTrade
                trade_scene.pbEndScreen
              }
            rescue => e
              mp_log_exception("TRADE: trade scene", e) if defined?(mp_log_exception)
            end

            $Trainer.pokedex.register(new_pkmn)         rescue nil
            $Trainer.pokedex.set_owned(new_pkmn.species) rescue nil

            pbMessage(_INTL("Trade complete! Received {1} (Lv.{2})!", new_pkmn.name, new_pkmn.level))
          end
        rescue => e
          mp_log_exception("TRADE: execute", e) if defined?(mp_log_exception)
          pbMessage(_INTL("Trade completed!"))
        end
      else
        mp_log("TRADE: invalid species '#{species_str}' or level #{level_int}") if defined?(mp_log)
        pbMessage(_INTL("Trade completed!"))
      end
    else
      pbMessage(_INTL("Trade completed!"))
    end

    reset_trade_state
  rescue => e
    mp_log_exception("TRADE: execute_trade_complete", e) if defined?(mp_log_exception)
    reset_trade_state
  end

  def serialize_pokemon(pkmn)
    {
      "species" => pkmn.species.to_s,
      "level"   => pkmn.level,
      "name"    => pkmn.name.to_s,
      "gender"  => pkmn.gender,
      "shiny"   => pkmn.shiny?,
      "form"    => pkmn.form,
      "egg"     => pkmn.egg?
    }
  rescue => e
    { "species" => :PIDGEY.to_s, "level" => 5, "name" => "Pidgey" }
  end

  def reset_trade_state
    @in_trade          = false
    @trade_session_id  = nil
    @trade_partner     = nil
    @am_player_a       = nil
    @offered_pokemon   = nil
    @partner_offer     = nil
    @my_confirmed      = false
    @partner_confirmed = false
    @pending_request   = nil
    @open_trade_ui     = false
  end
end

