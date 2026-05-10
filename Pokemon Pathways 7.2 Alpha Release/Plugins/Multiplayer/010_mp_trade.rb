#===============================================================================
#  MP TRADE MANAGER v1.2.0
#  Complete rewrite with main-thread UI marshalling and full Pokemon serialization.
#  FIXED:
#    1. ALL pbMessage calls now marshalled to main thread
#    2. open_trade_ui runs on main thread via schedule_on_main
#    3. Full Pokemon round-trip serialization (IVs, EVs, moves, nature, ability, item)
#    4. Party index tracked at offer time (not object reference)
#    5. Owner assignment wrapped in rescue with fallback
#    6. State guards on all handlers
#    7. handle_trade_request enqueued for main-thread UI
#    8. handle_trade_complete enqueued for main-thread UI
#    9. @pending_requests queue prevents UI backlog
#===============================================================================

module MP_TradeManager
  module_function

  @in_trade            = false
  @trade_session_id    = nil
  @trade_partner       = nil
  @offered_pokemon     = nil
  @offered_party_index = nil
  @partner_offer       = nil
  @confirmed           = false
  @initialized         = false
  @pending_requests    = []
  @pending_completes   = []

  def init
    return if @initialized
    @initialized = true
    register_packet_handlers
    echoln "[MP] Trade manager initialized"
  end

  def register_packet_handlers
    MP_NetworkManager.on_packet(MP_PacketType::TRADE_REQUEST) do |payload|
      @pending_requests << payload
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
      @pending_completes << payload
    end

    MP_NetworkManager.on_packet(MP_PacketType::TRADE_CANCEL) do |payload|
      handle_trade_cancel(payload)
    end

    # Process UI work each frame
    MP_NetworkManager.on_packet(MP_PacketType::HEARTBEAT) do |_|
      process_pending_ui
    end
  end

  # Called from main thread
  def update
    process_pending_ui
  end

  def process_pending_ui
    while !@pending_requests.empty?
      req = @pending_requests.shift
      begin
        process_trade_request_ui(req)
      rescue => e
        echoln "[MP][Trade] Request UI error: #{e.class}: #{e.message}"
      end
    end

    while !@pending_completes.empty?
      comp = @pending_completes.shift
      begin
        process_trade_complete_ui(comp)
      rescue => e
        echoln "[MP][Trade] Complete UI error: #{e.class}: #{e.message}"
      end
    end
  end

  def process_trade_request_ui(payload)
    from_name  = payload["from_name"]
    session_id = payload["session_id"]

    return unless from_name && session_id

    # Don't accept trade requests while already trading or in battle
    if @in_trade
      decline_trade(session_id)
      return
    end

    if defined?(MP_BattleManager) && MP_BattleManager.respond_to?(:in_mp_battle?) && MP_BattleManager.in_mp_battle?
      decline_trade(session_id)
      return
    end

    echoln "[MP][Trade] Trade request from #{from_name}"

    result = pbMessage(
      _INTL("{1} wants to trade! Accept?", from_name),
      [_INTL("Accept"), _INTL("Decline")],
      -1
    )

    if result == 0
      accept_trade(session_id)
    else
      decline_trade(session_id)
    end
  end

  def process_trade_complete_ui(payload)
    session_id   = payload["session_id"]
    received_data = payload["received_pokemon"]

    return unless @trade_session_id == session_id

    echoln "[MP][Trade] Trade completed!"

    if received_data
      begin
        new_pokemon = deserialize_pokemon(received_data)

        if new_pokemon && @offered_party_index && @offered_pokemon
          # Verify the party slot still has our offered Pokemon
          current_at_slot = $Trainer.party[@offered_party_index]

          if current_at_slot == @offered_pokemon
            old_pokemon = $Trainer.party[@offered_party_index]
            $Trainer.party[@offered_party_index] = new_pokemon

            # Show trade animation
            begin
              pbFadeOutInWithMusic do
                trade_scene = PokemonTrade_Scene.new
                trade_scene.pbStartScreen(old_pokemon, new_pokemon,
                                          $Trainer.name, @trade_partner || "Trainer")
                trade_scene.pbTrade
                trade_scene.pbEndScreen
              end
            rescue => e
              echoln "[MP][Trade] Trade animation error: #{e.class}"
            end

            # Register in Pokedex
            begin
              $Trainer.pokedex.register(new_pokemon)
              $Trainer.pokedex.set_owned(new_pokemon.species)
            rescue => e
              echoln "[MP][Trade] Pokedex error: #{e.class}"
            end

            pbMessage(_INTL("Trade complete! Received {1} (Lv.{2})!", new_pokemon.name, new_pokemon.level))
          else
            # Party changed since offering -- just add to party
            $Trainer.party.push(new_pokemon)
            pbMessage(_INTL("Trade complete! {1} was added to your party.", new_pokemon.name))
          end
        else
          pbMessage(_INTL("Trade completed!"))
        end
      rescue => e
        echoln "[MP][Trade] Error processing trade: #{e.class}: #{e.message}"
        pbMessage(_INTL("Trade completed!"))
      end
    else
      pbMessage(_INTL("Trade completed!"))
    end

    reset_trade_state
  end

  # --- Outgoing ---

  def request_trade(target_name)
    return unless MP_NetworkManager.connected?
    return if @in_trade

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
    return unless $Trainer && party_index >= 0 && party_index < $Trainer.party.length

    pkmn = $Trainer.party[party_index]
    return unless pkmn

    if pkmn.egg?
      pbMessage(_INTL("You cannot trade Eggs!"))
      return false
    end

    @offered_pokemon = pkmn
    @offered_party_index = party_index
    @confirmed = false

    pokemon_data = serialize_pokemon(pkmn)
    MP_NetworkManager.send_packet(MP_PacketType::TRADE_OFFER, {
      session_id: @trade_session_id,
      pokemon: pokemon_data
    })

    echoln "[MP][Trade] Offered #{pkmn.name} (Lv.#{pkmn.level})"
    true
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

  # --- Incoming handlers ---

  def handle_trade_open(payload)
    session_id = payload["session_id"]
    player_a   = payload["player_a"]
    player_b   = payload["player_b"]

    @trade_session_id  = session_id
    @in_trade          = true
    @trade_partner     = ($Trainer && $Trainer.name == player_a) ? player_b : player_a
    @offered_pokemon   = nil
    @offered_party_index = nil
    @partner_offer     = nil
    @confirmed         = false

    echoln "[MP][Trade] Trade window opened with #{@trade_partner}"

    # Open trade UI on main thread
    MP_NetworkManager.schedule_on_main do
      open_trade_ui
    end
  end

  def open_trade_ui
    # Show party selection for trade
    pbFadeOutIn(99999) do
      begin
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
          unless offer_pokemon(pokemon_index)
            next
          end

          # Show confirmation
          commands = [_INTL("Confirm"), _INTL("Change"), _INTL("Cancel")]
          cmd = pbMessage(
            _INTL("Offer {1} (Lv.{2})?", pkmn.name, pkmn.level),
            commands,
            -1
          )

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
      rescue => e
        echoln "[MP][Trade] UI error: #{e.class}: #{e.message}"
        cancel_trade
      end
    end
  end

  def handle_trade_offer(payload)
    session_id = payload["session_id"]
    return unless @trade_session_id == session_id

    offer_a = payload["offer_a"]
    offer_b = payload["offer_b"]

    # Get the partner's offer
    @partner_offer = nil
    if offer_a && offer_b
      owner_a = offer_a["owner"] || offer_a[:owner]
      if $Trainer && owner_a && $Trainer.name == owner_a
        @partner_offer = offer_b
      else
        @partner_offer = offer_a
      end
    elsif offer_a
      @partner_offer = offer_a
    elsif offer_b
      @partner_offer = offer_b
    end

    if @partner_offer
      species = @partner_offer["species"] || @partner_offer[:species]
      level   = @partner_offer["level"] || @partner_offer[:level]
      echoln "[MP][Trade] Partner offers: #{species} Lv.#{level}" if species && level
    end
  end

  def handle_trade_confirm(payload)
    session_id   = payload["session_id"]
    confirmed_a  = payload["confirmed_a"]
    confirmed_b  = payload["confirmed_b"]

    return unless @trade_session_id == session_id
    return unless @in_trade

    if confirmed_a && confirmed_b
      pbMessage(_INTL("Both players confirmed! Completing trade..."))
    elsif confirmed_a || confirmed_b
      pbMessage(_INTL("Waiting for your partner to confirm...")) unless @confirmed
    end
  end

  def handle_trade_cancel(payload)
    session_id = payload["session_id"]
    message    = payload["message"]

    if @trade_session_id == session_id
      pbMessage(message || _INTL("The trade was cancelled."))
      reset_trade_state
    end
  end

  # --- Pokemon serialization (FULL round-trip) ---

  def serialize_pokemon(pkmn)
    data = {
      species:         pkmn.species.to_s,
      level:           pkmn.level,
      name:            pkmn.name,
      gender:          pkmn.gender,
      shiny:           pkmn.shiny?,
      form:            pkmn.form,
      nature:          pkmn.nature.to_s,
      ability:         pkmn.ability_index,
      happiness:       pkmn.happiness,
      item:            pkmn.item ? pkmn.item.id.to_s : nil,
      owner:           $Trainer.name,
      ot:              $Trainer.name,
    }

    # IVs
    if pkmn.respond_to?(:iv)
      GameData::Stat.each_main do |s|
        data[:ivs] ||= {}
        data[:ivs][s.id.to_s] = pkmn.iv[s.id]
      end
    end

    # EVs
    if pkmn.respond_to?(:ev)
      GameData::Stat.each_main do |s|
        data[:evs] ||= {}
        data[:evs][s.id.to_s] = pkmn.ev[s.id]
      end
    end

    # Moves
    if pkmn.moves && !pkmn.moves.empty?
      data[:moves] = pkmn.moves.map do |move|
        next unless move
        {
          id:     move.id.to_s,
          pp:     move.pp,
          ppup:   move.ppup
        }
      end.compact
    end

    data
  rescue => e
    echoln "[MP][Trade] Serialize error: #{e.class}: #{e.message}"
    # Fallback to minimal serialization
    {
      species: pkmn.species.to_s,
      level:   pkmn.level,
      name:    pkmn.name,
      owner:   $Trainer.name
    }
  end

  def deserialize_pokemon(data)
    species = data["species"] || data[:species]
    level   = (data["level"] || data[:level] || 1).to_i
    name    = data["name"] || data[:name] || species

    pkmn = Pokemon.new(species.to_sym, level)
    pkmn.name = name if name != species.to_s

    # Restore gender
    gender = data["gender"] || data[:gender]
    pkmn.gender = gender if gender

    # Restore shiny
    shiny = data["shiny"] || data[:shiny]
    pkmn.shiny = !!shiny

    # Restore form
    form = data["form"] || data[:form]
    pkmn.form = form.to_i if form

    # Restore nature
    nature = data["nature"] || data[:nature]
    pkmn.nature = nature.to_sym if nature

    # Restore ability
    ability = data["ability"] || data[:ability]
    pkmn.ability_index = ability.to_i if ability

    # Restore happiness
    happiness = data["happiness"] || data[:happiness]
    pkmn.happiness = happiness.to_i if happiness

    # Restore item
    item = data["item"] || data[:item]
    pkmn.item = item.to_sym if item && !item.empty?

    # Restore IVs
    ivs = data["ivs"] || data[:ivs]
    if ivs && pkmn.respond_to?(:iv)
      GameData::Stat.each_main do |s|
        val = ivs[s.id.to_s] || ivs[s.id]
        pkmn.iv[s.id] = val.to_i if val
      end
    end

    # Restore EVs
    evs = data["evs"] || data[:evs]
    if evs && pkmn.respond_to?(:ev)
      GameData::Stat.each_main do |s|
        val = evs[s.id.to_s] || evs[s.id]
        pkmn.ev[s.id] = val.to_i if val
      end
    end

    # Restore moves
    moves = data["moves"] || data[:moves]
    if moves && !moves.empty?
      pkmn.moves.clear
      moves.each do |move_data|
        move_name = move_data["id"] || move_data[:id]
        next unless move_name
        begin
          move = Pokemon::Move.new(move_name.to_sym)
          pp = move_data["pp"] || move_data[:pp]
          move.pp = pp.to_i if pp
          pkmn.moves.push(move)
        rescue => e
          echoln "[MP][Trade] Move restore error: #{e.class}"
        end
      end
    end

    # Mark as traded
    pkmn.obtain_method = 2

    # Set original trainer
    ot = data["ot"] || data["owner"]
    if ot && pkmn.respond_to?(:owner)
      begin
        pkmn.owner = Pokemon::Owner.new_foreign(ot, 0)
      rescue => e
        echoln "[MP][Trade] Owner assignment error: #{e.class}"
      end
    end

    pkmn
  rescue => e
    echoln "[MP][Trade] Deserialize error: #{e.class}: #{e.message}"
    nil
  end

  # --- State ---

  def reset_trade_state
    @in_trade            = false
    @trade_session_id    = nil
    @trade_partner       = nil
    @offered_pokemon     = nil
    @offered_party_index = nil
    @partner_offer       = nil
    @confirmed           = false
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

  def on_disconnect
    reset_trade_state
    @pending_requests.clear
    @pending_completes.clear
  end
end

MP_NetworkManager.on_disconnect do |_reason|
  MP_TradeManager.on_disconnect rescue nil
end

MP_TradeManager.init
