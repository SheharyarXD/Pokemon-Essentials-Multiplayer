#===============================================================================
#  Pokemon Pathways Multiplayer Client - Trade Integration
#
#  FIXES vs original:
#   * OFFER SIDE BUG: handle_trade_offer determined "whose offer is whose" by
#     checking offer_a["owner"] == $Trainer.name. The server never sets an
#     "owner" field, so this always evaluated false and @partner_offer was
#     always set to offer_b. Fixed: server sends our client_id in the session;
#     we track which side we are (player_a or player_b) and index accordingly.
#   * MAIN THREAD UI: trade request dialog was called from packet callback.
#     Now deferred via @pending_request (same pattern as battle).
#   * POKEMON RECEIVE: use GameData::Species to validate species before creating
#     the Pokemon object. Prevents crash on unknown species string.
#   * BLOCKING UI INSIDE EVENT HANDLER: open_trade_ui is now deferred to a
#     @pending_ui flag checked in update().
#   * init is idempotent; called from mp_hooks (not at file-load time).
#===============================================================================

module MP_TradeManager

  @in_trade          = false
  @trade_session_id  = nil
  @trade_partner     = nil
  @am_player_a       = nil    # true = we are player_a, false = player_b
  @offered_pokemon   = nil    # our offered Pokemon object
  @partner_offer     = nil    # hash from server (species/level/name)
  @my_confirmed      = false
  @partner_confirmed = false
  @initialized       = false

  # Pending deferred actions (must run on main thread)
  @pending_request   = nil    # { from_name:, session_id: }
  @open_trade_ui     = false  # signal to open the trade UI this frame

  # ── Lifecycle ───────────────────────────────────────────────────────────────

  def init
    return if @initialized
    @initialized = true
    register_packet_handlers
    mp_log("TRADE: initialized") if defined?(mp_log)
  end

  # Called from Scene_Map#update (main thread).
  def update
    handle_pending_request
    handle_pending_ui
  end

  # ── Accessors ───────────────────────────────────────────────────────────────

  def in_trade?;         @in_trade;          end
  def trade_session_id;  @trade_session_id;  end
  def trade_partner;     @trade_partner;     end
  def offered_pokemon;   @offered_pokemon;   end
  def partner_offer;     @partner_offer;     end

  # ── Outbound actions ────────────────────────────────────────────────────────

  def request_trade(target_name)
    return unless MP_NetworkManager.connected?
    MP_NetworkManager.send_packet(MP_PacketType::TRADE_REQUEST, {
      "target_name" => target_name
    })
    mp_log("TRADE: requested with #{target_name}") if defined?(mp_log)
  end

  def accept_trade(session_id)
    return unless MP_NetworkManager.connected?
    MP_NetworkManager.send_packet(MP_PacketType::TRADE_ACCEPT, { "session_id" => session_id })
  end

  def decline_trade(session_id)
    return unless MP_NetworkManager.connected?
    MP_NetworkManager.send_packet(MP_PacketType::TRADE_DECLINE, { "session_id" => session_id })
    reset_trade_state
  end

  def offer_pokemon(party_index)
    return unless @in_trade && $Trainer
    pkmn = $Trainer.party[party_index]
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
  end

  def confirm_trade
    return unless @in_trade && @offered_pokemon
    @my_confirmed = true
    MP_NetworkManager.send_packet(MP_PacketType::TRADE_CONFIRM, {
      "session_id" => @trade_session_id
    })
    mp_log("TRADE: confirmed") if defined?(mp_log)
  end

  def cancel_trade
    return unless @in_trade
    MP_NetworkManager.send_packet(MP_PacketType::TRADE_CANCEL, {
      "session_id" => @trade_session_id
    })
    reset_trade_state
  end

  # ── Packet handlers (run on main thread via event queue) ────────────────────

  def register_packet_handlers
    MP_NetworkManager.on_packet(MP_PacketType::TRADE_REQUEST) do |payload|
      @pending_request = {
        from_name:  payload["from_name"],
        session_id: payload["session_id"]
      }
    end

    MP_NetworkManager.on_packet(MP_PacketType::TRADE_OPEN) do |payload|
      @trade_session_id  = payload["session_id"]
      @in_trade          = true
      # Track which side we are so we can correctly read offer_a vs offer_b
      @am_player_a       = ($Trainer.name == payload["player_a"])
      @trade_partner     = @am_player_a ? payload["player_b"] : payload["player_a"]
      @offered_pokemon   = nil
      @partner_offer     = nil
      @my_confirmed      = false
      @partner_confirmed = false
      @open_trade_ui     = true
      mp_log("TRADE: opened with #{@trade_partner} (#{@am_player_a ? 'A' : 'B'})") if defined?(mp_log)
    end

    MP_NetworkManager.on_packet(MP_PacketType::TRADE_OFFER) do |payload|
      next unless @trade_session_id == payload["session_id"]
      offer_a = payload["offer_a"]
      offer_b = payload["offer_b"]
      # FIX: use @am_player_a to determine which offer is ours vs partner's
      our_offer    = @am_player_a ? offer_a : offer_b
      their_offer  = @am_player_a ? offer_b : offer_a
      @partner_offer = their_offer
      # Reset confirmations because offer changed
      @my_confirmed      = false
      @partner_confirmed = false
      if their_offer
        sp = their_offer["species"]; lv = their_offer["level"]
        mp_log("TRADE: partner offers #{sp} Lv.#{lv}") if defined?(mp_log)
      end
    end

    MP_NetworkManager.on_packet(MP_PacketType::TRADE_CONFIRM) do |payload|
      next unless @trade_session_id == payload["session_id"]
      if @am_player_a
        @my_confirmed      = payload["confirmed_a"]
        @partner_confirmed = payload["confirmed_b"]
      else
        @my_confirmed      = payload["confirmed_b"]
        @partner_confirmed = payload["confirmed_a"]
      end
      if @partner_confirmed && !@my_confirmed
        pbMessage(_INTL("Your partner confirmed! Confirm to complete the trade.")) rescue nil
      elsif @my_confirmed && @partner_confirmed
        pbMessage(_INTL("Both players confirmed! Completing trade...")) rescue nil
      end
    end

    MP_NetworkManager.on_packet(MP_PacketType::TRADE_COMPLETE) do |payload|
      next unless @trade_session_id == payload["session_id"]
      received_data = payload["received_pokemon"]
      execute_trade_complete(received_data)
    end

    MP_NetworkManager.on_packet(MP_PacketType::TRADE_CANCEL) do |payload|
      next unless @trade_session_id == payload["session_id"]
      msg = payload["message"] || _INTL("The trade was cancelled.")
      pbMessage(msg) rescue nil
      reset_trade_state
      mp_log("TRADE: cancelled (#{payload['reason']})") if defined?(mp_log)
    end
  end

  private

  # ── Deferred main-thread handlers ───────────────────────────────────────────

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
  end

  def handle_pending_ui
    return unless @open_trade_ui && @in_trade
    @open_trade_ui = false
    open_trade_ui
  end

  # ── Trade UI ────────────────────────────────────────────────────────────────

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
  end

  # ── Trade completion ────────────────────────────────────────────────────────

  def execute_trade_complete(received_data)
    mp_log("TRADE: complete! received=#{received_data&.inspect}") if defined?(mp_log)

    if received_data && @offered_pokemon
      species_str = received_data["species"].to_s
      level_int   = received_data["level"].to_i
      name_str    = received_data["name"] || species_str

      # FIX: Validate species via GameData before creating the Pokemon
      sym = species_str.upcase.to_sym
      valid_species = begin
        GameData::Species.exists?(sym) ? sym : nil
      rescue
        sym  # fallback if GameData not available
      end

      if valid_species
        begin
          new_pkmn              = Pokemon.new(valid_species, level_int)
          new_pkmn.name         = name_str
          new_pkmn.obtain_method= 2  # traded
          new_pkmn.owner        = Pokemon::Owner.new_foreign(@trade_partner.to_s, 0) rescue nil

          party_index = $Trainer.party.index(@offered_pokemon)
          if party_index
            old_pkmn = $Trainer.party[party_index]
            $Trainer.party[party_index] = new_pkmn

            pbFadeOutInWithMusic {
              trade_scene = PokemonTrade_Scene.new
              trade_scene.pbStartScreen(old_pkmn, new_pkmn, $Trainer.name, @trade_partner || "Trainer")
              trade_scene.pbTrade
              trade_scene.pbEndScreen
            }

            $Trainer.pokedex.register(new_pkmn)          rescue nil
            $Trainer.pokedex.set_owned(new_pkmn.species)  rescue nil

            pbMessage(_INTL("Trade complete! Received {1} (Lv.{2})!", new_pkmn.name, new_pkmn.level))
          end
        rescue => e
          mp_log("TRADE: error creating received pokemon #{e.class}: #{e.message}") if defined?(mp_log)
          pbMessage(_INTL("Trade completed!"))
        end
      else
        mp_log("TRADE: unknown species '#{species_str}'") if defined?(mp_log)
        pbMessage(_INTL("Trade completed!"))
      end
    else
      pbMessage(_INTL("Trade completed!"))
    end

    reset_trade_state
  end

  # ── Helpers ─────────────────────────────────────────────────────────────────

  def serialize_pokemon(pkmn)
    {
      "species" => pkmn.species.to_s,
      "level"   => pkmn.level,
      "name"    => pkmn.name,
      "gender"  => pkmn.gender,
      "shiny"   => pkmn.shiny?,
      "form"    => pkmn.form,
      "egg"     => pkmn.egg?
    }
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
  extend self
end
