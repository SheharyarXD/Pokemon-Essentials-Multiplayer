#===============================================================================
#  Pokemon Pathways Multiplayer Client - Chat Overlay
#
#  Renders a small transparent message log in the bottom-left corner of the
#  map screen. Supports map-wide chat and whispers (/w name msg).
#
#  FIXES vs original:
#   * INPUT CONFLICT: was using Input::LEFT for backspace, which conflicts with
#     player movement. Removed all MKXP key-binding for text input; instead the
#     overlay now uses a simple pbDisplayText-style prompt via the game's own
#     input system (see activate_chat_input). Arrow keys stay for movement.
#   * PREMATURE SPRITE CREATION: ensure_chat_sprite is now called lazily only
#     when update() runs (i.e. inside Scene_Map), never at file-load time.
#   * VIEWPORT Z: chat overlay uses a Viewport with z=9999 so it appears above
#     all map sprites but below system menus.
#   * SYSTEM CHAT PACKET: CHAT_SYSTEM is now registered here and in the
#     disconnect handler; removed from battle manager to avoid duplicate messages.
#   * init is idempotent; called from mp_hooks (not at file-load time).
#===============================================================================

module MP_ChatOverlay
  module_function

  MAX_MESSAGES      = 5
  MESSAGE_FADE_MS   = 8000   # ms before a message starts fading
  CHAT_WIDTH        = 400
  CHAT_HEIGHT       = 110
  LINE_HEIGHT       = 22
  CHAT_X            = 4      # screen position
  CHAT_Y_OFFSET     = 24     # pixels above bottom of screen

  @messages     = []
  @chat_sprite  = nil
  @chat_bitmap  = nil
  @viewport     = nil
  @initialized  = false

  # ── Lifecycle ───────────────────────────────────────────────────────────────

  def init
    return if @initialized
    @initialized = true
    @messages    = []
    register_packet_handlers
    mp_log("CHAT: initialized") if defined?(mp_log)
  end

  def dispose
    dispose_sprites
    @messages.clear
    @initialized = false
    mp_log("CHAT: disposed") if defined?(mp_log)
  end

  def dispose_sprites
    if @chat_sprite && !@chat_sprite.disposed?
      @chat_sprite.dispose
    end
    if @chat_bitmap && !@chat_bitmap.disposed?
      @chat_bitmap.dispose
    end
    if @viewport && !@viewport.disposed?
      @viewport.dispose
    end
    @chat_sprite = nil
    @chat_bitmap = nil
    @viewport    = nil
  end

  # ── Update (called every frame from Scene_Map#update) ───────────────────────

  def update
    return unless @initialized
    check_chat_input
    update_message_alpha
    render_chat
  end

  # ── Public message API ───────────────────────────────────────────────────────

  def add_message(text, type = :normal)
    @messages << {
      text:      text.to_s[0, 100],   # hard cap per-message display length
      type:      type,
      timestamp: Time.now.to_f * 1000,
      alpha:     255
    }
    @messages.shift if @messages.length > MAX_MESSAGES * 2
    mp_log("CHAT: #{text}") if defined?(mp_log)
  end

  def send_chat_message(text)
    return unless MP_NetworkManager.connected?
    text = text.to_s.strip
    return if text.empty?

    if text.start_with?("/w ") || text.start_with?("/whisper ")
      parts = text.split(" ", 3)
      if parts.length >= 3
        MP_NetworkManager.send_packet(MP_PacketType::CHAT_WHISPER, {
          "target"  => parts[1],
          "message" => parts[2]
        })
        add_message("-> #{parts[1]}: #{parts[2]}", :whisper)
      else
        add_message("Usage: /w <player> <message>", :system)
      end
    else
      MP_NetworkManager.send_packet(MP_PacketType::CHAT_MESSAGE, { "message" => text })
      # Server echoes back the message so we don't add it locally here
    end
  end

  # ── Packet handler registration ─────────────────────────────────────────────

  def register_packet_handlers
    MP_NetworkManager.on_packet(MP_PacketType::CHAT_MESSAGE) do |p|
      add_message("#{p['sender']}: #{p['message']}", :normal)
    end

    MP_NetworkManager.on_packet(MP_PacketType::CHAT_WHISPER) do |p|
      if p["echo"]
        add_message("-> #{p['to'] || '?'}: #{p['message']}", :whisper)
      else
        add_message("[PM] #{p['sender']}: #{p['message']}", :whisper)
      end
    end

    MP_NetworkManager.on_packet(MP_PacketType::CHAT_SYSTEM) do |p|
      add_message("[*] #{p['message']}", :system)
    end
  end

  private

  # ── Chat input ─────────────────────────────────────────────────────────────

  # FIX: Use pbMessageFreeText (MKXP-Z / PE built-in text input) rather than
  # trying to intercept arrow keys. This shows a proper keyboard/on-screen input.
  # Trigger: press F5 (a key not used by PE movement/menu).
  # If pbMessageFreeText is not available, falls back to a stub.
  def check_chat_input
    return if $game_temp.in_menu || $game_temp.in_battle
    # Input::F5 = key code 116 in MKXP-Z (function key, unused by PE by default)
    return unless Input.trigger?(Input::F5) rescue false

    begin
      if defined?(pbMessageFreeText)
        text = pbMessageFreeText(_INTL("Chat:"), "", false, 200, Graphics.width)
      else
        # Minimal fallback: show a regular message prompt
        text = pbMessage(_INTL("Chat:"), [], -1).to_s
        text = ""  # can't easily get text from pbMessage; degrade gracefully
      end
      send_chat_message(text) unless text.nil? || text.strip.empty?
    rescue => e
      mp_log("CHAT: input error #{e.class}: #{e.message}") if defined?(mp_log)
    end
  end

  # ── Message fading ─────────────────────────────────────────────────────────

  def update_message_alpha
    now = Time.now.to_f * 1000
    @messages.each do |msg|
      elapsed = now - msg[:timestamp]
      if elapsed > MESSAGE_FADE_MS
        fade_progress = (elapsed - MESSAGE_FADE_MS) / 2000.0
        msg[:alpha] = [(255 * (1.0 - fade_progress)).to_i, 0].max
      else
        msg[:alpha] = 255
      end
    end
    @messages.reject! { |m| m[:alpha] <= 0 }
    @messages = @messages.last(MAX_MESSAGES * 2) if @messages.length > MAX_MESSAGES * 2
  end

  # ── Rendering ──────────────────────────────────────────────────────────────

  def ensure_sprites
    return if @chat_sprite && !@chat_sprite.disposed?
    dispose_sprites
    begin
      screen_h  = Graphics.height
      @viewport = Viewport.new(CHAT_X, screen_h - CHAT_HEIGHT - CHAT_Y_OFFSET,
                               CHAT_WIDTH, CHAT_HEIGHT)
      @viewport.z   = 9999
      @chat_bitmap  = Bitmap.new(CHAT_WIDTH, CHAT_HEIGHT)
      @chat_sprite  = Sprite.new(@viewport)
      @chat_sprite.bitmap = @chat_bitmap
    rescue => e
      mp_log("CHAT: sprite creation error #{e.class}: #{e.message}") if defined?(mp_log)
      @chat_sprite = nil
      @chat_bitmap = nil
    end
  end

  def render_chat
    recent = @messages.last(MAX_MESSAGES)
    return if recent.empty?   # don't render empty overlay

    ensure_sprites
    return unless @chat_sprite && !@chat_sprite.disposed?

    @chat_bitmap.clear

    # Semi-transparent background only as tall as needed
    used_h = recent.length * LINE_HEIGHT
    @chat_bitmap.fill_rect(0, CHAT_HEIGHT - used_h, CHAT_WIDTH, used_h,
                           Color.new(0, 0, 0, 100))

    y = CHAT_HEIGHT - used_h
    recent.each do |msg|
      color = case msg[:type]
              when :system  then Color.new(255, 200,  80, msg[:alpha])
              when :whisper then Color.new(150, 255, 150, msg[:alpha])
              else               Color.new(255, 255, 255, msg[:alpha])
              end
      @chat_bitmap.font.size  = 14
      @chat_bitmap.font.color = color
      @chat_bitmap.draw_text(4, y, CHAT_WIDTH - 8, LINE_HEIGHT, msg[:text])
      y += LINE_HEIGHT
    end

    @chat_sprite.bitmap = @chat_bitmap
    @chat_sprite.visible = true
  end
end
